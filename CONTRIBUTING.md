# Contributing

Thanks for your interest. Issues and pull requests are welcome.

## Before you start

- Open an issue to discuss larger changes first.
- The lab must stay safe: the agent is read-only, and only a human runs `incident-on.sh` and `incident-off.sh`. Changes must not weaken that boundary.
- Use documentation-only IP ranges (`198.51.100.0/24`, `203.0.113.0/24`, `192.0.2.0/24`). Do not add real addresses, credentials or webhook URLs.

## Making a change

1. Fork the repository and create a branch.
2. Deploy the lab and confirm `lab/scripts/check.sh baseline` passes. See [Getting started](docs/getting-started.md).
3. If you change the prompt, skill, allowlist or model, re-run the [evals](docs/evals.md) and include the results.
4. Update the docs for any behavior change.
5. Open a pull request that describes what changed and how you tested it.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org), for example `fix: correct BGP neighbor allowlist entry`.

## Style

- Shell scripts use POSIX `sh` with `set -eu`.
- Pin container image and tool versions.
- Keep docs short and put commands in fenced code blocks.
