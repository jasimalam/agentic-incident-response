# Getting started

Deploy the routers and monitoring stack, then verify the baseline. All commands run from the repository root.

## Prerequisites

- macOS with Docker Desktop or OrbStack running.
- Node.js (for `npx @devcontainers/cli`), Homebrew, [`uv`](https://docs.astral.sh/uv/) and [Ollama](https://ollama.com).
- About 32 GB RAM for two SR Linux nodes plus a 14B model.

```sh
uname -m
docker info --format '{{.ServerVersion}} {{.OSType}}/{{.Architecture}}'
ollama list
```

## 1. Start the Dev Container

Containerlab runs inside the Dev Container. Define a helper for commands that must run in it:

```sh
npx --yes @devcontainers/cli up --workspace-folder "$PWD"
dc() { npx --yes @devcontainers/cli exec --workspace-folder "$PWD" "$@"; }
dc containerlab version
```

Define `dc` again in every new terminal. Without it, macOS runs its built-in `dc` calculator and prints `Parse error: bad token`.

## 2. Deploy the topology

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

## 3. Start monitoring

Alertmanager mounts `lab/secrets/slack_webhook_url`. Create the file first, or Docker creates a directory in its place. Use a real Slack webhook URL, or any placeholder if you do not use Slack:

```sh
printf '%s' 'https://hooks.slack.com/services/REPLACE/ME' > lab/secrets/slack_webhook_url
dc docker compose -f lab/docker-compose.yml up -d
dc curl -fsS http://127.0.0.1:9090/-/ready
dc curl -fsS http://127.0.0.1:9093/-/ready
```

## 4. Check the baseline

```sh
dc ./lab/scripts/check.sh baseline
```

Expected: both probes return `1`, both BGP sessions are Established, and Alertmanager shows no alerts.

Next: [Agent setup](agent-setup.md).
