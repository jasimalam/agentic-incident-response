# Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| FRR warns about `vtysh.conf` or `frr.conf processing failure` | FRR needs `lab/configs/upstream/vtysh.conf` with `service integrated-vtysh-config`, bind-mounted in the topology. |
| Alertmanager is not reachable from macOS | Docker Desktop host networking applies to the Linux VM, not the Mac. Alertmanager publishes `127.0.0.1:9093`. Prometheus and Blackbox stay on host networking. |
| `dc` prints `Parse error: bad token` | `dc` is not defined in this terminal. Define the function again. |
| `container ... is not running` | Docker restarted and stopped the Dev Container and lab nodes. Run `devcontainer up` again, then redeploy. |
| Agent account is gone | Redeploying recreates the nodes. Run `agent-user.sh` again. |
| Non-superuser role returns empty `show` output | SR Linux 24.10 behavior. See the [lab limitation](agent-setup.md#lab-limitation). |
| Netmiko MCP fails with `No module named 'mcp.server.fastmcp'` | Install with `--with 'mcp<2'`. |
| Homebrew refuses the Holmes formula | Read the formula, then run `brew trust --formula robusta-dev/holmesgpt/holmesgpt`. |
| Holmes runs `show bgp summary` and is denied | List the exact allowed commands in `llm_instructions`. The denial is the guardrail working. |
| Holmes assumes a 200K context | Set `OVERRIDE_MAX_CONTENT_SIZE`, `OVERRIDE_MAX_OUTPUT_TOKEN` and `OLLAMA_CONTEXT_LENGTH`. |
| `check.sh incident` prints `Expected affected probe failure in incident mode` | The incident is not active. Run `incident-on.sh --confirm` first, then `check.sh status` and confirm SR Linux B has the blackhole route. |
| Alertmanager fails to start | `lab/secrets/slack_webhook_url` is missing or is a directory. Create it as a file. |
