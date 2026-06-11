---
name: gnadd-context
description: >-
  GNADD workflow orientation: GitHub issues as backlog, describe-vs-track file
  rule, and which GNADD skill handles each workflow step. Use when the user asks
  about GNADD, agent-driven development workflow, project context files, tasks.md
  versus issues, startup guidance, or how to set up work. Do not use for routine
  coding unless the question is workflow-shaped.
disable-model-invocation: false
---

# GNADD Context

Provide lightweight orientation for Git-Native Agent-Driven Development (GNADD).
Do not run git commands from this skill; route mechanics to the operational
skills.

## Core Model

- GitHub is the system of record: issues capture intent, branches hold work, PRs
  record what shipped, and git history is the audit trail.
- The five operational skills handle git mechanics: `prime`, `new-issue`,
  `start-issue`, `commit`, and `resolve-issue`.
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

- Adopt or realign a repo: use `/gnadd-audit`.
- Start a session or inspect state: use `/prime`.
- Capture new work: use `/new-issue`.
- Begin or resume issue work: use `/start-issue <N>`.
- Save progress on an issue branch: use `/commit`.
- Verify, PR, merge, and clean up: use `/resolve-issue`.
- If a git operation seems needed and no skill covers it, ask for a
  skill-shaped path before improvising raw git commands.

## Deep Reference

For startup guidance, file-hygiene questions, rationale, or edge cases not
covered here, fetch the canonical guide from this pinned URL:

https://raw.githubusercontent.com/AlexHagemeister/gnadd/6471f13ed95d99785fd3962cf3fe250672dccbf3/GNADD.md

This URL is pinned to a commit, not `main`, so installed skills do not drift with
unreleased guide changes.

## Closing Guidance

Do not nudge after every answer. Match nudge depth to user intent:

- **Purely informational** (describe-vs-track, "which skill does X?", rationale questions): no nudge — the answer stands alone.
- **Routing toward action** ("how do I start?", "where should this state live?"): light nudge — one skill pointer (e.g. `/prime`, `/new-issue`), no full loop recap.
- **Session bootstrap** ("I'm new here", end-to-end workflow orientation): full nudge toward `/prime` to see live repo state.

When nudging, keep it to a sentence with an invitational option. Do not restate the skill router table.
