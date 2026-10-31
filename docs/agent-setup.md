# Agent setup

Give HolmesGPT a read-only view of the routers, backed by a local model.

## Router account

```sh
AGENT_PASSWORD='<choose-a-lab-password>' ./lab/scripts/agent-user.sh
```

This creates `netops-agent` on both SR Linux nodes. Run it again after every topology redeploy.

### Lab limitation

On SR Linux 24.10, a non-superuser role returned empty `show` output, so `netops-agent` is a superuser. A superuser ignores the CLI command allow list, so the Netmiko MCP allowlist is the only layer keeping the agent read-only. In production, use a real read-only role or TACACS+/RADIUS command authorization.

## Netmiko MCP

```sh
uv tool install netmiko-mcp --with 'mcp<2'
cp lab/netmiko/netmiko-mcp.example.yml ~/.netmiko-mcp.yml
cp lab/netmiko/inventory.example.yml ~/.netmiko.yml
cp lab/netmiko/commands.example.yml ~/commands.yml
chmod 600 ~/.netmiko-mcp.yml ~/.netmiko.yml ~/commands.yml
```

Edit `~/.netmiko.yml`: devices `srl_a` (`127.0.0.1:2221`) and `srl_b` (`127.0.0.1:2223`), device type `nokia_srl`, username `netops-agent` and the lab password. Never commit these files. The `--with 'mcp<2'` pin is required.

`~/commands.yml` allows only exact `show` commands and denies `configure*`, `set*`, `delete*` and `commit*`. `~/.netmiko-mcp.yml` enables the audit log at `~/.netmiko_mcp_audit.log`.

## Ollama

```sh
ollama pull qwen3:14b
launchctl setenv OLLAMA_CONTEXT_LENGTH 16384   # then quit and reopen Ollama
```

Any model with reliable tool calling works. The `launchctl` setting does not survive a reboot.

## HolmesGPT

```sh
brew tap robusta-dev/homebrew-holmesgpt
brew cat robusta-dev/holmesgpt/holmesgpt        # read the formula first
brew trust --formula robusta-dev/holmesgpt/holmesgpt
brew install holmesgpt
```

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

Listing the exact commands stops the model guessing commands such as `show bgp summary`, which the allowlist denies.

## Verify

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

Next: [Run the incident](run-incident.md).
