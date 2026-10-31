# Run the incident

The human operator triggers and clears the fault. Do not run these scripts through the agent.

## Trigger and investigate

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

## Recover

```sh
dc ./lab/scripts/incident-off.sh --confirm
dc ./lab/scripts/check.sh recovery
```

## Optional: post the RCA to Slack automatically

Alertmanager also sends firing alerts to `http://host.docker.internal:9095/alert`. Run the receiver on the Mac. It runs a read-only `holmes investigate` and posts the RCA to Slack, or prints it if no webhook is set:

```sh
export OLLAMA_API_BASE=http://localhost:11434 MODEL=ollama_chat/qwen3:14b
export OVERRIDE_MAX_CONTENT_SIZE=16384 OVERRIDE_MAX_OUTPUT_TOKEN=2048
SLACK_WEBHOOK_URL="$(cat lab/secrets/slack_webhook_url)" python3 lab/scripts/alert-receiver.py
```

Settings are environment variables: `RECEIVER_HOST`, `RECEIVER_PORT`, `ALERTMANAGER_URL`, `HOLMES_BIN`, `ALLOWED_ALERTS`, `DEDUPE_SECONDS` and `HOLMES_TIMEOUT`.

## Tear down

```sh
dc docker compose -f lab/docker-compose.yml down
dc sudo clab destroy -t lab/topology.clab.yml
```
