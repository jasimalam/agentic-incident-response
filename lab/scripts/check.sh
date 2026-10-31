#!/bin/sh
set -eu

usage() {
    printf '%s\n' 'Usage: check.sh [status|baseline|incident|recovery]' >&2
}

mode=${1:-status}
case "$mode" in
    status|baseline|incident|recovery)
        ;;
    *)
        usage
        exit 2
        ;;
esac

upstream_container=clab-lab-upstream
srl_a_container=clab-lab-srl-a

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

get_probe_success() {
    target_address=$1
    probe_metrics=$(curl -fsS "http://127.0.0.1:9115/probe?target=${target_address}&module=http_2xx") \
        || fail "Blackbox Exporter could not probe ${target_address}. Is the monitoring stack running?"
    probe_success=$(printf '%s\n' "$probe_metrics" | awk '$1 == "probe_success" { print $2; found = 1 } END { if (!found) exit 1 }') \
        || fail "No probe_success metric returned for ${target_address}."
    printf '%s\n' "$probe_success"
}

curl -fsS http://127.0.0.1:9090/-/ready >/dev/null \
    || fail 'Prometheus is not ready at 127.0.0.1:9090.'
curl -fsS http://127.0.0.1:9093/-/ready >/dev/null \
    || fail 'Alertmanager is not ready at 127.0.0.1:9093.'

control_success=$(get_probe_success 198.51.100.10)
affected_success=$(get_probe_success 198.51.100.130)
printf 'Control probe (198.51.100.10): %s\n' "$control_success"
printf 'Affected probe (198.51.100.130): %s\n' "$affected_success"

if [ "$control_success" != 1 ]; then
    fail 'The control target must remain reachable.'
fi
if [ "$affected_success" != 0 ] && [ "$affected_success" != 1 ]; then
    fail "Unexpected affected probe result: ${affected_success}"
fi

case "$mode" in
    baseline|recovery)
        [ "$affected_success" = 1 ] || fail "Expected affected probe success in ${mode} mode."
        ;;
    incident)
        [ "$affected_success" = 0 ] || fail 'Expected affected probe failure in incident mode.'
        ;;
esac

bgp_output=$(docker exec "$upstream_container" vtysh -c 'show ip bgp neighbors 10.0.1.2') \
    || fail 'Could not query the upstream FRR BGP neighbor.'
printf '%s\n' "$bgp_output" | grep -F 'BGP state = Established' >/dev/null \
    || fail 'The BGP session to srl-a is not established.'
printf '%s\n' 'FRR BGP session to srl-a: Established'

srl_a_bgp_output=$(docker exec "$srl_a_container" sr_cli 'show network-instance default protocols bgp neighbor') \
    || fail 'Could not query SR Linux A BGP neighbors.'
printf '%s\n' "$srl_a_bgp_output" | grep -E '10\.0\.2\.2.*established' >/dev/null \
    || fail 'The eBGP session from SR Linux B is not established.'
printf '%s\n' 'SR Linux A BGP session to SR Linux B: Established'

if [ "$mode" = incident ]; then
    frr_bgp_route=$(docker exec "$upstream_container" vtysh -c 'show ip bgp 198.51.100.128/25') \
        || fail 'Could not query the FRR BGP route for the affected prefix.'
    printf '%s\n' 'FRR BGP route for the affected prefix:'
    printf '%s\n' "$frr_bgp_route"
    printf '%s\n' "$frr_bgp_route" | grep -E '65001[[:space:]]+65002' >/dev/null \
        || fail 'FRR did not learn the affected prefix from SR Linux B through SR Linux A.'

    frr_route=$(docker exec "$upstream_container" vtysh -c 'show ip route 198.51.100.128/25') \
        || fail 'Could not query the FRR route for the affected prefix.'
    printf '%s\n' "$frr_route" | grep -F '10.0.1.2, via eth2' >/dev/null \
        || fail 'FRR did not install the affected prefix through SR Linux A.'
    printf '%s\n' 'FRR routes the affected prefix through SR Linux A.'
fi

printf '%s\n' 'Alertmanager alerts:'
curl -fsS http://127.0.0.1:9093/api/v2/alerts || fail 'Could not read Alertmanager alerts.'
