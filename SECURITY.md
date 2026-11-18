# Security Policy

## Supported versions

Only the latest release (and current `main`) is supported. There are no
backported fixes.

## Reporting a vulnerability

Please report vulnerabilities **privately** via GitHub's vulnerability
reporting: **Security → Report a vulnerability** on this repository. Do not
open a public issue for security problems.

## What counts as a vulnerability here

These skills instruct coding agents and execute shell commands (`git`, `gh`,
and a project's own worktree setup command) with the full permissions of
your agent. Reports are especially welcome for:

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

The script runs one command that GNADD does not write. When `gnadd start`
runs in a linked worktree that has not been set up yet, it runs the
`Worktree setup:` line from the AGENTS.md of the branch it just checked out,
as a shell command, with no review step. Read that line on any branch you
start, as you would read a build script.
