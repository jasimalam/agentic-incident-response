# Security policy

This project is a lab. It uses documentation IP ranges and throwaway credentials, and it is not meant for production networks.

## Reporting a vulnerability

Report security issues privately through [GitHub private vulnerability reporting](https://github.com/jasimalam/agentic-incident-response/security/advisories/new). Do not open a public issue.

Please include what you found, the affected file or step, and how to reproduce it. Expect an acknowledgement, then a fix or a documented limitation.

## Scope

In scope: scripts, configs and docs in this repository, including anything that could leak credentials or let the agent change router configuration.

Known limitation: the lab agent account is a superuser, so the Netmiko MCP allowlist is the only read-only guard. See [Agent setup](docs/agent-setup.md#lab-limitation).

## Secrets

Never commit credentials, `~/.netmiko.yml`, or the Slack webhook in `lab/secrets/`. If you committed one by mistake, rotate it immediately.
