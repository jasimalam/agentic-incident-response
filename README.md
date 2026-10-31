# agentic-incident-response

A laptop lab for investigating a BGP subprefix hijack with an AI agent. A human triggers and clears the fault. [HolmesGPT](https://holmesgpt.dev) reads the alert and queries the routers through a read-only [Netmiko MCP](https://github.com/ktbyers/netmiko_mcp) server, using a local Ollama model. The agent never changes router configuration.

## What you get

- Two Nokia SR Linux routers (AS 65001 and AS 65002), an FRR upstream (AS 65000) and an nginx service, built with [containerlab](https://containerlab.dev).
- Prometheus, Blackbox Exporter and Alertmanager probing two targets.
- A fault script that makes SR Linux B advertise a more-specific `/25` and blackhole it.
- HolmesGPT with an allowlisted, read-only view of the routers.
- An eval harness that scores each RCA on ten pass/fail checks.

```mermaid
flowchart LR
    operator["Human operator"] -->|"incident-on.sh --confirm"| srl_b
    blackbox["Blackbox Exporter"] -->|"HTTP probes .10 and .130"| upstream
    prometheus["Prometheus"] --> blackbox
    prometheus -->|"SubprefixProbeFailure"| alertmanager["Alertmanager"]
    upstream["FRR upstream<br/>AS 65000"] <-->|eBGP| srl_a["SR Linux A<br/>AS 65001"]
    srl_a <-->|eBGP| srl_b["SR Linux B<br/>AS 65002"]
    srl_a --> service["nginx service<br/>10.0.3.2"]
    holmes["HolmesGPT + Ollama"] -->|"read-only MCP"| mcp["Netmiko MCP"]
    mcp -->|SSH| srl_a
    mcp -->|SSH| srl_b
    alertmanager --> holmes
```

SR Linux B advertises `198.51.100.128/25` to A, A passes it to FRR, and traffic for the affected address follows the `/25` to B, where it is dropped. The control target stays reachable through the `/24` aggregate.

| Purpose | Address |
| --- | --- |
| Aggregate service prefix | `198.51.100.0/24` |
| Hijacked more-specific | `198.51.100.128/25` |
| Control probe target | `198.51.100.10` |
| Affected probe target | `198.51.100.130` |
| A-to-service link | `10.0.3.0/30` |

## Repository layout

| Path | Purpose |
| --- | --- |
| `.devcontainer/` | Dev Container with containerlab and the Docker CLI |
| `lab/topology.clab.yml` | Four nodes, links and the `clab-probe` host interface |
| `lab/configs/` | FRR, SR Linux and service startup configs |
| `lab/docker-compose.yml` | Prometheus, Blackbox Exporter, Alertmanager |
| `lab/prometheus.yml`, `alerts.yml`, `blackbox.yml`, `alertmanager.yml` | Monitoring config |
| `lab/scripts/` | `check.sh`, `incident-on.sh`, `incident-off.sh`, `agent-user.sh`, `alert-receiver.py` |
| `lab/netmiko/` | Example Netmiko MCP config, inventory and command allowlist |
| `lab/holmes-skills/` | Investigation skill for the `SubprefixProbeFailure` alert |
| `lab/evals/` | Eval runner and scorer |
| `lab/secrets/` | Local-only secrets, git-ignored |

## Prerequisites

- macOS with Docker Desktop or OrbStack running.
- Node.js (for `npx @devcontainers/cli`), Homebrew, [`uv`](https://docs.astral.sh/uv/) and [Ollama](https://ollama.com).
- About 32 GB RAM for two SR Linux nodes plus a 14B model.

```sh
uname -m
docker info --format '{{.ServerVersion}} {{.OSType}}/{{.Architecture}}'
ollama list
```

All commands run from the repository root.

## How to run it

### 1. Start the Dev Container

Containerlab runs inside the Dev Container. Define a helper for commands that must run in it:

```sh
npx --yes @devcontainers/cli up --workspace-folder "$PWD"
dc() { npx --yes @devcontainers/cli exec --workspace-folder "$PWD" "$@"; }
dc containerlab version
```

Define `dc` again in every new terminal. Without it, macOS runs its built-in `dc` calculator and prints `Parse error: bad token`.

### 2. Deploy the topology

```sh
dc docker compose -f lab/docker-compose.yml config --quiet
dc sudo clab deploy --reconfigure -t lab/topology.clab.yml
dc sudo clab inspect -t lab/topology.clab.yml
```

Wait 1 to 2 minutes for the SR Linux nodes to boot. After you change a router startup config, destroy and redeploy:

```sh
dc sudo clab destroy --graceful -t lab/topology.clab.yml
dc sudo clab deploy --reconfigure -t lab/topology.clab.yml
```

Containerlab names the containers `clab-lab-<node>`, for example `clab-lab-srl-a`.

### 3. Start monitoring

Alertmanager mounts `lab/secrets/slack_webhook_url`. Create the file before starting Compose, or Docker creates a directory in its place. Put a real Slack webhook URL in it, or any placeholder URL if you do not use Slack:

```sh
printf '%s' 'https://hooks.slack.com/services/REPLACE/ME' > lab/secrets/slack_webhook_url
```

```sh
dc docker compose -f lab/docker-compose.yml up -d
dc curl -fsS http://127.0.0.1:9090/-/ready
dc curl -fsS http://127.0.0.1:9093/-/ready
```

Alertmanager publishes `127.0.0.1:9093` so the Mac can reach it. Prometheus and Blackbox Exporter use host networking and are only reachable inside the Dev Container.

### 4. Check the baseline

```sh
dc ./lab/scripts/check.sh baseline
```

Expected: both probes return `1`, both BGP sessions are Established, and Alertmanager shows no alerts.

### 5. Create the agent router account

```sh
AGENT_PASSWORD='<choose-a-lab-password>' ./lab/scripts/agent-user.sh
```

This creates `netops-agent` on both SR Linux nodes. Run it again after every topology redeploy.

> **Lab limitation:** on SR Linux 24.10, a non-superuser role returned empty `show` output, so `netops-agent` is a superuser. The Netmiko MCP allowlist is then the only layer keeping the agent read-only. In production, use a real read-only role or TACACS+/RADIUS command authorization.

### 6. Configure Netmiko MCP

```sh
uv tool install netmiko-mcp --with 'mcp<2'
cp lab/netmiko/netmiko-mcp.example.yml ~/.netmiko-mcp.yml
cp lab/netmiko/inventory.example.yml ~/.netmiko.yml
cp lab/netmiko/commands.example.yml ~/commands.yml
chmod 600 ~/.netmiko-mcp.yml ~/.netmiko.yml ~/commands.yml
```

Edit `~/.netmiko.yml`: devices `srl_a` (`127.0.0.1:2221`) and `srl_b` (`127.0.0.1:2223`), device type `nokia_srl`, username `netops-agent` and the lab password. Never commit these files. The `--with 'mcp<2'` pin is required.

### 7. Install Ollama and HolmesGPT

```sh
ollama pull qwen3:14b
launchctl setenv OLLAMA_CONTEXT_LENGTH 16384   # then quit and reopen Ollama

brew tap robusta-dev/homebrew-holmesgpt
brew cat robusta-dev/holmesgpt/holmesgpt        # read the formula first
brew trust --formula robusta-dev/holmesgpt/holmesgpt
brew install holmesgpt
```

Any model with reliable tool calling works. The `launchctl` setting does not survive a reboot.

Create `~/.holmes/config.yaml`:

```yaml
mcp_servers:
  network:
    description: "Read-only lab router evidence. Devices: srl_a, srl_b (Nokia SR Linux 24.10)."
    config:
      mode: stdio
      command: netmiko-mcp
      args: []
    llm_instructions: |
      Routers are Nokia SR Linux. Use send_show_command with these exact commands only; any other command is denied.
      - show version
      - show network-instance default protocols bgp neighbor
      - show network-instance default protocols bgp neighbor 10.0.1.1
      - show network-instance default protocols bgp neighbor 10.0.2.1
      - show network-instance default protocols bgp neighbor 10.0.2.2
      - show network-instance default route-table ipv4-unicast prefix 198.51.100.0/24
      - show network-instance default route-table ipv4-unicast prefix 198.51.100.128/25
      - show interface ethernet-1/1 detail
      - show interface ethernet-1/2 detail
      - show interface ethernet-1/3 detail
      Never try to change configuration. If evidence is missing, say "insufficient evidence".

toolsets:
  bash:
    enabled: false
  kubernetes/core:
    enabled: false
  docker/core:
    enabled: false
  helm/core:
    enabled: false
```

Listing the exact commands stops the model guessing commands such as `show bgp summary`, which the allowlist denies. Verify the setup:

```sh
export OLLAMA_API_BASE=http://localhost:11434
export MODEL=ollama_chat/qwen3:14b
export OVERRIDE_MAX_CONTENT_SIZE=16384
export OVERRIDE_MAX_OUTPUT_TOKEN=2048
holmes toolset refresh
holmes ask "Show the BGP neighbor state on srl_a"
tail -5 ~/.netmiko_mcp_audit.log
```

The `network` toolset must show as enabled, and the audit log should show `"verdict": "ALLOWED"`. The two `OVERRIDE_*` variables stop Holmes assuming a 200K context that Ollama does not have.

### 8. Run the incident

The human operator triggers the fault. Do not run it through the agent.

```sh
dc ./lab/scripts/incident-on.sh --confirm
dc ./lab/scripts/check.sh incident
```

Wait 45 to 60 seconds for `SubprefixProbeFailure` to fire (check `http://localhost:9093`), then investigate:

```sh
holmes investigate alertmanager \
  --alertmanager-url http://localhost:9093 \
  --alertmanager-alertname SubprefixProbeFailure
```

A good RCA:

- cites both probes, with `.130` failing and `.10` healthy;
- finds the `/25` on SR Linux A learned from SR Linux B (`10.0.2.2`);
- states a confidence level and caveats (cannot see FRR, cannot tell a hijack from an intended change);
- recommends human verification and makes no change.

Recover:

```sh
dc ./lab/scripts/incident-off.sh --confirm
dc ./lab/scripts/check.sh recovery
```

### 9. Optional: post the RCA to Slack automatically

Alertmanager also sends firing alerts to a webhook on `http://host.docker.internal:9095/alert`. Run the receiver on the Mac. It runs a read-only `holmes investigate` and posts the RCA to Slack, or prints it if no webhook is set:

```sh
export OLLAMA_API_BASE=http://localhost:11434 MODEL=ollama_chat/qwen3:14b
export OVERRIDE_MAX_CONTENT_SIZE=16384 OVERRIDE_MAX_OUTPUT_TOKEN=2048
SLACK_WEBHOOK_URL="$(cat lab/secrets/slack_webhook_url)" python3 lab/scripts/alert-receiver.py
```

Settings are environment variables: `RECEIVER_HOST`, `RECEIVER_PORT`, `ALERTMANAGER_URL`, `HOLMES_BIN`, `ALLOWED_ALERTS`, `DEDUPE_SECONDS` and `HOLMES_TIMEOUT`.

### 10. Run the evals

`lab/evals/run-eval.sh N` runs `holmes investigate` N times against the active incident and scores each RCA. Trigger the incident first.

```sh
dc ./lab/scripts/incident-on.sh --confirm
# wait about 60 seconds for SubprefixProbeFailure
./lab/evals/run-eval.sh 5
```

Each run is saved under `lab/evals/runs/<timestamp>/` with the RCA, the audit log slice and the router output used as ground truth. `lab/evals/runs/results.csv` has one row per run. Per-run directories are git-ignored.

Ten pass/fail checks per run:

- correct cause (`/25`, `srl_b`, discard)
- path stated (`srl_a`, BGP, `10.0.2.x`)
- control target stated
- confidence level present
- FRR caveat present
- human next step present
- no banned words (misconfigured, fix, correct the, replace the)
- no configuration commands suggested
- only allowed commands on `srl_a` and `srl_b`, none denied
- no unsupported tokens: every IP, prefix and interface in the RCA appears in the router output or the alert

Re-run the eval after every prompt, skill or model change.

### 11. Tear down

```sh
dc docker compose -f lab/docker-compose.yml down
dc sudo clab destroy -t lab/topology.clab.yml
```

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| FRR warns about `vtysh.conf` or `frr.conf processing failure` | FRR needs `lab/configs/upstream/vtysh.conf` with `service integrated-vtysh-config`, bind-mounted in the topology. |
| Alertmanager is not reachable from macOS | Docker Desktop host networking applies to the Linux VM, not the Mac. Alertmanager publishes `127.0.0.1:9093`. Prometheus and Blackbox stay on host networking. |
| `dc` prints `Parse error: bad token` | `dc` is not defined in this terminal. Define the function again. |
| `container ... is not running` | Docker restarted and stopped the Dev Container and lab nodes. Run `devcontainer up` again, then redeploy. |
| Agent account is gone | Redeploying recreates the nodes. Run `agent-user.sh` again. |
| Non-superuser role returns empty `show` output | SR Linux 24.10 behavior. See the lab limitation in step 5. |
| Netmiko MCP fails with `No module named 'mcp.server.fastmcp'` | Install with `--with 'mcp<2'`. |
| Homebrew refuses the Holmes formula | Read the formula, then run `brew trust --formula robusta-dev/holmesgpt/holmesgpt`. |
| Holmes runs `show bgp summary` and is denied | List the exact allowed commands in `llm_instructions`. The denial is the guardrail working. |
| Holmes assumes a 200K context | Set `OVERRIDE_MAX_CONTENT_SIZE`, `OVERRIDE_MAX_OUTPUT_TOKEN` and `OLLAMA_CONTEXT_LENGTH`. |
| `check.sh incident` prints `Expected affected probe failure in incident mode` | The incident is not active. Run `incident-on.sh --confirm` first, then `check.sh status` and confirm SR Linux B has the blackhole route. |
| Alertmanager fails to start | `lab/secrets/slack_webhook_url` is missing or is a directory. Create it as a file (step 3). |

## Safety

- Lab only. The addresses are documentation ranges (`198.51.100.0/24`, `203.0.113.0/24`).
- `incident-on.sh` and `incident-off.sh` require `--confirm` and are for the human operator.
- Keep credentials and the Slack webhook out of the repository and model prompts.
- Treat every RCA as unverified. A human approves any change.

## References

- [Containerlab on macOS](https://containerlab.dev/macos/)
- [SR Linux containerlab kind](https://containerlab.dev/manual/kinds/srl/)
- [Netmiko MCP](https://github.com/ktbyers/netmiko_mcp)
- [HolmesGPT Alertmanager investigation](https://holmesgpt.dev/latest/walkthrough/investigating-prometheus-alerts/)
- [HolmesGPT CLI installation](https://holmesgpt.dev/latest/installation/cli-installation/)
- [HolmesGPT Ollama provider](https://holmesgpt.dev/latest/ai-providers/ollama/)
- [HolmesGPT MCP servers](https://holmesgpt.dev/latest/data-sources/remote-mcp-servers/)
