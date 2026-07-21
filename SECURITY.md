# Security Policy

## Supported versions

Only the latest release (and current `main`) is supported. There are no
backported fixes.

## Reporting a vulnerability

Please report vulnerabilities **privately** via GitHub's vulnerability
reporting: **Security → Report a vulnerability** on this repository. Do not
open a public issue for security problems.

## What counts as a vulnerability here

These skills instruct coding agents and execute shell commands (`git`, `gh`)
with the full permissions of your agent. Reports are especially welcome for:

- Ways `gnadd.sh` could be induced to perform destructive or
  history-rewriting git operations despite its guards
- Prompt-injection vectors in the skill documents themselves
- Anything that could cause an agent following these skills to push
  unreviewed work to a protected branch

## A note for installers

Review skills before installing them — installed skills run with your
agent's full permissions. All git mechanics here are concentrated in one
auditable script ([`bin/gnadd`](bin/gnadd), copied verbatim into each
operational skill), and its behavior is covered by the test suite.
