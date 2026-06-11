---
name: prime
description: >-
  Orient a new chat session with a read-only project snapshot using tree, git,
  and gh: project shape, current branch state, whether main is behind origin,
  stashes, recent commits, open issues, open and merged PRs, and active issue
  context. Fetches latest remote state first. Use only when explicitly invoked
  with /prime.
disable-model-invocation: true
---

# Prime

Orient a new chat session with the project's current state. This is read-only: do not create, edit, stage, commit, stash, or delete files.

## GNADD Invariants

- `prime` gives spatial awareness and momentum; it does not load implementation context speculatively.
- GitHub is the system of record, so open issues, open PRs, recent merged PRs, branches, and commits are the working state.
- Surface local `main` divergence and stashes prominently, but do not fix them here; this skill is read-only.
- For broader workflow or file-hygiene guidance, use `gnadd-context`.

## Purpose

Build a lightweight working model of:

- Where things live
- What changed recently
- What work is outstanding
- Whether the current branch maps to an active issue

Do not read individual source files, schemas, or entry points. This skill is for spatial awareness and momentum, not deep implementation context.

Assume `AGENTS.md` and project rules are already loaded. Do not read or summarize them.

## Commands

First, verify the GitHub CLI is installed and authenticated:

```bash
gh auth status
```

If `gh` is not installed or is not authenticated:

- Warn the user.
- Tell them to run `gh auth login`.
- Do not proceed with the rest of the orientation until `gh auth status` is confirmed working.

After GitHub CLI auth is confirmed, run these commands from the repo root:

```bash
tree -L 2 -I 'node_modules|__pycache__|.git|dist|build|.next|.venv|coverage|target|vendor|.pytest_cache|*.egg-info'
git fetch --prune origin
git log --oneline -15
git status
git branch --show-current
git branch --list
git stash list
git log --oneline main..origin/main
git log --oneline origin/main..main
gh issue list --state open
gh pr list --state open
gh pr list --state merged --limit 10
```

`git fetch --prune` updates remote-tracking refs only — it does not touch your working tree, branches, or commits, so it stays within this skill's read-only contract. It is what makes the rest of the snapshot reflect reality rather than a stale local cache. (If the repo has no remote, `fetch` and the `main..origin/main` comparison will no-op or error harmlessly — note "no remote configured" and move on.)

If the current branch matches `issue-<N>/<slug>`, also run:

```bash
gh issue view <N>
```

## Interpretation

### Project Shape

Use the `tree` output to identify the top-level layout:

- Where source appears to live
- Where config appears to live
- Where tests appear to live
- Any notable docs, scripts, assets, or deployment files

Keep this shallow. Do not inspect files unless the user asks.

### Recent Git History

Use `git log --oneline -15` to infer the recent trajectory:

- Active areas of the codebase
- Development focus
- Recently completed issue or PR themes

Avoid over-explaining individual commits.

### Current State

Use `git status`, current branch, local branch list, `git stash list`, and `git log main..origin/main` to report:

- Active branch
- Whether the working tree is clean
- Other local branches that may indicate in-progress work
- **Behind origin:** If `git log --oneline main..origin/main` shows commits, `main` is behind origin by that many commits. Surface this plainly — e.g. "local `main` is 2 commits behind origin; pull before starting new work." This is the signal that someone (you elsewhere, or a collaborator) has merged since you last synced.
- **Diverged (dangerous):** If `git log --oneline origin/main..main` shows commits, local `main` holds commits that origin lacks — usually a sign something was committed directly to local `main`. This is the dangerous state the other skills halt on. **Flag it as the first line of the summary**, recommend resolving it before starting any new work, and do not attempt to fix it from this skill — prime is read-only. (Behind is normal; ahead is the alarm.)
- **Stashes:** If `git stash list` is non-empty, surface it — e.g. "you have 1 stashed change; don't forget it's there." Stashes are invisible to every other command here and easy to abandon.

### Open Issues

Use `gh issue list --state open` to summarize pending work.

- Group by label when labels are present.
- Prefer labels `bug`, `feature`, and `chore` when available.
- Keep issue titles and numbers visible.

### Open PRs

Use `gh pr list --state open` to surface work in flight that is not yet merged.

- Include PR numbers and titles.
- Flag PRs awaiting review — these are the most actionable items, especially with a collaborator. A PR sitting open is either waiting on you to review/merge or waiting on feedback.

### Recent Completions

Use `gh pr list --state merged --limit 10` to summarize what shipped recently.

- Include PR numbers and titles.
- Highlight momentum, not every detail.

### Active Issue

Only include this section when the branch matches `issue-<N>/<slug>`.

Use `gh issue view <N>` to summarize:

- Problem
- Desired outcome
- Subtasks, if present

Do not fetch referenced issues or artifacts automatically.

## Output Format

Produce a concise, scannable orientation summary:

```markdown
## Project Shape
<1-2 sentences about top-level layout>

## Current State
<active branch, working tree status, local branches; flag if main is behind origin or stashes exist>

## Recent Activity
<what the last ~15 commits suggest>

## Open Work
<open issues grouped by label if useful>

## In Flight
<open PRs, flagging any awaiting review>

## Recently Shipped
<last ~10 merged PRs>

## Active Issue
<only if on issue branch>
```

Keep the summary short enough to use as quick working context.

## Closing Guidance

Offer a brief next-step nudge only when orientation completed successfully — not when `gh` auth failed or the skill halted mid-run.

**Skip** when blockers were surfaced in the summary (diverged `main`, stashes, dirty tree on the wrong branch). Nudge toward resolving those first, not advancing the happy-path loop.

**Infer one primary suggestion** from repo state, plus at least one alternative when ambiguous:

1. Open PR awaiting review → review or merge before starting new work.
2. On `issue-<N>/*` with a dirty tree → `/commit` or continue implementation.
3. On `issue-<N>/*`, clean → continue that issue's work.
4. On clean `main` with open issues → `/start-issue <N>` on the most actionable issue.
5. No open issues → `/new-issue`.

Keep it to a sentence or two with invitational options. Do not restate the full GNADD workflow.
