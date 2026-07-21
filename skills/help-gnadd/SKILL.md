---
name: help-gnadd
description: >-
  GNADD workflow orientation: GitHub issues as backlog, describe-vs-track file
  rule, and which GNADD skill handles each workflow step. Use when the user asks
  about GNADD, agent-driven development workflow, project context files, tasks.md
  versus issues, startup guidance, or how to set up work. Do not use for routine
  coding unless the question is workflow-shaped.
disable-model-invocation: false
---

# GNADD Help

Provide lightweight orientation for Git-Native Agent-Driven Development (GNADD).
Do not run git commands from this skill; route mechanics to the operational
skills.

## Core Model

- GitHub is the system of record: issues capture intent, branches hold work, PRs
  record what shipped, and git history is the audit trail.
- The seven operational skills drive the loop: `prime-gnadd`, `new-issue-gnadd`,
  `start-issue-gnadd`, `commit-gnadd`, `resolve-issue-gnadd`,
  `quickfix-gnadd` (the no-issue fast path for trivial changes), and
  `yolo-gnadd` (autonomous full-loop on a decided unit; explicit invocation
  only). Their git mechanics run through a bundled deterministic script
  (`gnadd.sh`), not improvised commands.
- Enforcement is layered, lowest layer that can hold each invariant: GitHub
  server rules (`gnadd init` — squash-only merges, PR-required main), the
  script (ff-only syncs, divergence halts, gated cleanup), the skills
  (judgment and conversation), and the human (reading the diff before merge).
- Recovery from bad states has a sanctioned path: `gnadd.sh doctor` (bundled
  with `prime-gnadd`) diagnoses and offers lossless fixes. Never improvise
  `reset`/`force` recoveries.
- The user's load-bearing job is to describe desired behavior, answer scope
  questions, and read diffs before merge.

## Describe vs Track

Files that describe stable truth are fine. Files that track mutable state should
not exist.

- Keep: README vision, project conventions, stable reference docs.
- Avoid: task lists, progress files, maintained plans, status checklists.
- Test: would the agent need to keep this file up to date? If yes, that state
  belongs in GitHub issues, PRs, branches, or commits instead.

## Skill Router

- Adopt or realign a repo: use `/audit-gnadd`.
- Start a session or inspect state: use `/prime-gnadd`.
- Capture new work: use `/new-issue-gnadd`.
- Begin or resume issue work: use `/start-issue-gnadd <N>`.
- Save progress on an issue branch: use `/commit-gnadd`.
- Verify, PR, merge, and clean up: use `/resolve-issue-gnadd`.
- Land one trivial fix (typo, doc line) without an issue: use `/quickfix-gnadd`.
- Run a decided issue or quickfix end-to-end without mid-loop gates: use
  `/yolo-gnadd <N or description>` (never auto-invoked).
- Diagnose or recover from a bad git state (diverged main, stashes,
  leftovers): run `gnadd.sh doctor` from the `prime-gnadd` skill's directory.
- Set up server-side rails on a new repo: `gnadd.sh init` (squash-only
  merges, branch ruleset on main; `--ci` adds a test workflow stub).
- If a git operation seems needed and no skill covers it, ask for a
  skill-shaped path before improvising raw git commands.

## Deep Reference

For startup guidance, file-hygiene questions, rationale, or edge cases not
covered here, fetch the canonical guide from this pinned URL:

https://raw.githubusercontent.com/AlexHagemeister/gnadd/v0.3.0/GNADD.md

This URL is pinned to a commit, not `main`, so installed skills do not drift with
unreleased guide changes. The pin is rewritten by `scripts/release.sh` at release
time — do not hand-edit it out of band.

## Closing Guidance

Do not nudge after every answer. Match nudge depth to user intent:

- **Purely informational** (describe-vs-track, "which skill does X?", rationale questions): no nudge — the answer stands alone.
- **Routing toward action** ("how do I start?", "where should this state live?"): light nudge — one skill pointer (e.g. `/prime-gnadd`, `/new-issue-gnadd`), no full loop recap.
- **Session bootstrap** ("I'm new here", end-to-end workflow orientation): full nudge toward `/prime-gnadd` to see live repo state.

When nudging, keep it to a sentence with an invitational option. Do not restate the skill router table.
