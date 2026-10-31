# agentic-incident-response

A hands-on lab for agentic network incident response: an AI agent investigates a real BGP incident on real router software, with strict read-only guardrails and measurable results.

## Why this exists

At 03:00 an alert fires and an on-call engineer starts the same routine: read the alert, log in to devices, run `show` commands, compare routes and neighbors, and work out what changed. Most of that first pass is evidence gathering, not judgment. It is slow when you are tired, and it is the part an agent can do.

Agentic NetOps applies LLM agents to that first pass. The agent reads the alert, picks the diagnostic commands, interprets the output and drafts a root-cause analysis (RCA) with evidence. A human still decides what to do.

The hard questions are about trust, not capability:

- **Can the agent be kept read-only?** Command allowlists, denied patterns and an audit log of every call.
- **Can you trust its RCA?** Every claim must cite tool output, state its confidence and say "insufficient evidence" when it lacks it.
- **Can you measure it?** An eval harness scores each RCA, so prompt, skill and model changes become comparable numbers rather than impressions.
- **Can it run without sending network data to a third party?** The lab uses a local model.

This repository is a small, reproducible place to explore those questions before pointing an agent at production.

## The scenario

A BGP subprefix hijack: a peer starts advertising a more-specific `/25` inside your `/24`. Longest-prefix match sends part of the traffic to the wrong place, while the rest of the prefix stays healthy.

1. SR Linux B advertises `198.51.100.128/25` and blackholes it. The `/24` aggregate still serves the control target.
2. Blackbox Exporter probes a control target and an affected target. Prometheus fires `SubprefixProbeFailure` when the affected probe fails.
3. [HolmesGPT](https://holmesgpt.dev) reads the alert and runs allowlisted `show` commands through a read-only [Netmiko MCP](https://github.com/ktbyers/netmiko_mcp) server, using a local Ollama model.
4. The agent reports the cause, evidence, confidence and caveats. A human verifies and approves any change.

A human triggers and clears the fault. The agent never changes router configuration.

## What is in the lab

- [containerlab](https://containerlab.dev) topology: two Nokia SR Linux routers, an FRR upstream and an nginx service.
- Prometheus, Blackbox Exporter and Alertmanager.
- Scripts to trigger, verify and clear the incident.
- A Netmiko MCP allowlist and an investigation skill for HolmesGPT.
- An eval harness with ten pass/fail checks per RCA.

See [docs/architecture.md](docs/architecture.md) for the diagram and addressing plan.

## Quick start

Requirements: Docker Desktop or OrbStack, Node.js, Homebrew, `uv`, Ollama and about 32 GB RAM.

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
