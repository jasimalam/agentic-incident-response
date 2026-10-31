#!/bin/sh
# Creates the agent account on both SR Linux nodes. Password comes from the environment only.
# Lab limitation: SR Linux 24.10 returned empty show output for a non-superuser role, so this
# account is a superuser. The Netmiko MCP allowlist is the only thing keeping the agent read-only.
set -eu

: "${AGENT_PASSWORD:?Set AGENT_PASSWORD before running this script.}"
agent_user=${AGENT_USER:-netops-agent}

for node in clab-lab-srl-a clab-lab-srl-b; do
    printf '%s\n' \
        'enter candidate' \
        'set / system aaa authorization role agent-role services [ cli ]' \
        'set / system aaa authorization role agent-role superuser true' \
        "set / system aaa authentication user ${agent_user} role [ agent-role ]" \
        "set / system aaa authentication user ${agent_user} password ${AGENT_PASSWORD}" \
        'commit now' \
        | docker exec -i "$node" sr_cli >/dev/null \
        || { printf 'ERROR: could not configure %s\n' "$node" >&2; exit 1; }
    printf 'Configured %s on %s\n' "$agent_user" "$node"
done
