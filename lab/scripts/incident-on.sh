#!/bin/sh
set -eu

if [ "$#" -ne 1 ] || [ "$1" != "--confirm" ]; then
    printf '%s\n' 'Usage: incident-on.sh --confirm' >&2
    printf '%s\n' 'This changes the lab FRR route table. Run it only as the human operator.' >&2
    exit 2
fi

attacker_container=clab-lab-srl-b
container_state=$(docker inspect --format '{{.State.Running}}' "$attacker_container") || {
    printf 'Could not inspect container %s; deploy the lab first.\n' "$attacker_container" >&2
    exit 1
}
if [ "$container_state" != true ]; then
    printf 'Container %s is not running; deploy the lab first.\n' "$attacker_container" >&2
    exit 1
fi

docker exec "$attacker_container" sr_cli \
    --candidate-mode \
    --commit-at-end \
    -- \
    'set / network-instance default static-routes route 198.51.100.128/25 next-hop-group hijack-sink'

printf '%s\n' 'Added the 198.51.100.128/25 blackhole route on SR Linux B.'
printf '%s\n' 'SR Linux B advertises the route to SR Linux A, which advertises it to FRR.'
printf '%s\n' 'Run ./lab/scripts/check.sh incident to verify propagation and impact.'
