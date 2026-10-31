#!/bin/sh
# Runs HolmesGPT against the active lab incident N times and scores each RCA.
# The human triggers the incident first: dc ./lab/scripts/incident-on.sh --confirm
# Usage: lab/evals/run-eval.sh [N]
set -eu

runs=${1:-1}
here=$(cd "$(dirname "$0")" && pwd)
audit_log=${NETMIKO_AUDIT_LOG:-$HOME/.netmiko_mcp_audit.log}
results="$here/runs/results.csv"

export OLLAMA_API_BASE=${OLLAMA_API_BASE:-http://localhost:11434}
export MODEL=${MODEL:-ollama_chat/qwen3:14b}
export OVERRIDE_MAX_CONTENT_SIZE=${OVERRIDE_MAX_CONTENT_SIZE:-16384}
export OVERRIDE_MAX_OUTPUT_TOKEN=${OVERRIDE_MAX_OUTPUT_TOKEN:-2048}

alerts=$(curl -fsS http://localhost:9093/api/v2/alerts) \
    || { echo 'ERROR: Alertmanager is not reachable at localhost:9093.' >&2; exit 1; }
printf '%s' "$alerts" | grep -q SubprefixProbeFailure \
    || { echo 'ERROR: SubprefixProbeFailure is not firing. Run incident-on.sh --confirm and wait about 60 seconds.' >&2; exit 1; }

mkdir -p "$here/runs"
touch "$audit_log"

i=1
while [ "$i" -le "$runs" ]; do
    run_dir="$here/runs/$(date +%Y%m%d-%H%M%S)-$i"
    mkdir -p "$run_dir"
    lines_before=$(wc -l < "$audit_log")

    start=$(date +%s)
    holmes investigate alertmanager \
        --alertmanager-url http://localhost:9093 \
        --alertmanager-alertname SubprefixProbeFailure \
        < /dev/null > "$run_dir/rca.txt" 2>&1 || true
    seconds=$(( $(date +%s) - start ))

    tail -n +"$((lines_before + 1))" "$audit_log" > "$run_dir/audit.jsonl"

    # Ground truth for the unsupported-claims check: admin view of the allowed commands plus the alert text.
    {
        printf '%s\n' "$alerts"
        for node in clab-lab-srl-a clab-lab-srl-b; do
            for cmd in \
                'show network-instance default route-table ipv4-unicast prefix 198.51.100.0/24' \
                'show network-instance default route-table ipv4-unicast prefix 198.51.100.128/25' \
                'show network-instance default protocols bgp neighbor' \
                'show interface ethernet-1/1 detail' \
                'show interface ethernet-1/2 detail' \
                'show interface ethernet-1/3 detail'; do
                docker exec "$node" sr_cli "$cmd" 2>&1 || true
            done
        done
    } > "$run_dir/ground-truth.txt"

    python3 "$here/score.py" "$run_dir/rca.txt" "$run_dir/ground-truth.txt" "$run_dir/audit.jsonl" "$seconds" "$results"
    i=$((i + 1))
done

echo "Results: $results"
