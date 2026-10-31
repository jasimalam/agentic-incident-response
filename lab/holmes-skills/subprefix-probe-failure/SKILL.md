---
name: subprefix-probe-failure
description: Investigate the SubprefixProbeFailure alert, where the HTTP probe to 198.51.100.130 fails while the control probe to 198.51.100.10 stays up, using read-only SR Linux show commands
---

## Goal
Find why 198.51.100.130 is unreachable while 198.51.100.10 works and both BGP sessions are up. The usual cause is a more-specific /25 that wins over the /24 aggregate and sends traffic to the wrong next hop.

## Lab facts
- Devices: `srl_a` (AS 65001) and `srl_b` (AS 65002). These are the only valid `device_name` values. Never use `router-1` or any other name.
- srl_a peers with FRR upstream `10.0.1.1` (AS 65000) and with srl_b at `10.0.2.2`.
- The service sits behind srl_a at `10.0.3.2`. The /24 aggregate normally points there.
- The probe runs outside the routers. Do not run TCP or connectivity checks; they are blocked for private addresses.

## Workflow
Run these exact commands with `send_show_command`. Any other command is denied.

1. On `srl_a`: `show network-instance default route-table ipv4-unicast prefix 198.51.100.128/25`
   * Note the route type and next hop. A BGP route via `10.0.2.2` means srl_b announced it.
2. On `srl_a`: `show network-instance default route-table ipv4-unicast prefix 198.51.100.0/24`
   * Normally a static route to the service at `10.0.3.2`.
3. On `srl_a`: `show network-instance default protocols bgp neighbor 10.0.2.2`
   * Confirm the session state and the prefixes received from srl_b.
4. On `srl_b`: `show network-instance default route-table ipv4-unicast prefix 198.51.100.128/25`
   * Check whether srl_b holds a local route (for example a blackhole) for the /25.

## Synthesize Findings
- The longest match wins. If srl_a prefers the /25 from srl_b over the /24 to the service, traffic to 198.51.100.130 follows srl_b and never reaches the service. Addresses outside the /25, such as 198.51.100.10, still use the /24.
- Cite the tool output for every claim. Do not state anything you did not see.

## Report format
- Root cause, in one or two sentences.
- Evidence: the exact route lines you saw, with the device name.
- Confidence: HIGH if the /25 and its next hop appear in tool output, MEDIUM if one link is inferred, LOW if evidence is missing. If evidence is missing, say "insufficient evidence".
- Caveats: you cannot see the FRR upstream, and you cannot tell a hijack from an intended route change.
- Recommended next step: a human verifies the /25 with the peer and changes it through change control. Never propose or run a configuration command yourself.
