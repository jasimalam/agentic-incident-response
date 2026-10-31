# agentic-incident-response

A laptop lab for investigating a BGP subprefix hijack with an AI agent. A human triggers and clears the fault. [HolmesGPT](https://holmesgpt.dev) reads the alert and queries the routers through a read-only [Netmiko MCP](https://github.com/ktbyers/netmiko_mcp) server, using a local Ollama model. The agent never changes router configuration.

The lab runs on macOS with containerlab, two Nokia SR Linux routers, an FRR upstream and a Prometheus/Alertmanager stack. An eval harness scores each root-cause analysis (RCA) on ten pass/fail checks.

## How it works

1. SR Linux B advertises a more-specific `198.51.100.128/25` and blackholes it. The `/24` aggregate still serves the control target.
2. Blackbox Exporter probes a control target and an affected target. Prometheus fires `SubprefixProbeFailure` when the affected probe fails.
3. HolmesGPT reads the alert, runs allowlisted `show` commands on the routers and writes an RCA.
4. A human verifies the RCA and approves any change.

See [docs/architecture.md](docs/architecture.md) for the diagram and addressing plan.

## Quick start

Requirements: macOS, Docker Desktop or OrbStack, Node.js, Homebrew, `uv`, Ollama and about 32 GB RAM.

```sh
npx --yes @devcontainers/cli up --workspace-folder "$PWD"
dc() { npx --yes @devcontainers/cli exec --workspace-folder "$PWD" "$@"; }

printf '%s' 'https://hooks.slack.com/services/REPLACE/ME' > lab/secrets/slack_webhook_url
dc sudo clab deploy --reconfigure -t lab/topology.clab.yml
dc docker compose -f lab/docker-compose.yml up -d
dc ./lab/scripts/check.sh baseline
```

Then set up the agent and run the incident with the guides below.

## Documentation

| Guide | Contents |
| --- | --- |
| [Architecture](docs/architecture.md) | Topology, addressing, repository layout |
| [Getting started](docs/getting-started.md) | Prerequisites, Dev Container, deploy, monitoring, baseline |
| [Agent setup](docs/agent-setup.md) | Router account, Netmiko MCP, Ollama, HolmesGPT |
| [Run the incident](docs/run-incident.md) | Trigger, investigate, recover, Slack receiver, teardown |
| [Evals](docs/evals.md) | Running and scoring RCAs |
| [Troubleshooting](docs/troubleshooting.md) | Known problems and fixes |

## Safety

- Lab use only. Addresses are documentation ranges (`198.51.100.0/24`, `203.0.113.0/24`).
- The agent account is a superuser on the lab routers, so the Netmiko MCP allowlist is the only read-only guard. See [Agent setup](docs/agent-setup.md#lab-limitation).
- Treat every RCA as unverified. A human approves any change.
- Keep credentials and the Slack webhook out of the repository.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
