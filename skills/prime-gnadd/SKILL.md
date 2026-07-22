---
name: prime-gnadd
description: >-
  Orient a new chat session with a read-only project snapshot using the bundled
  gnadd script, git, and gh: project shape, current branch state, whether main
  is behind or diverged from origin, stashes, recent commits, open issues, open
  and merged PRs, and active issue context. Fetches latest remote state first.
  Use when the user asks to inspect project state, orient a session, see what
  work is open, or decide what to do next.
disable-model-invocation: false
---

# Prime

Orient a new chat session with the project's current state. This is read-only: do not create, edit, stage, commit, stash, or delete files.

## Auto-Invocation Gate

If this skill was auto-selected from context rather than explicitly invoked with `/prime-gnadd`, stop before running commands. Briefly explain why a repo snapshot appears useful and ask: "Run `/prime-gnadd` now?" Proceed only after confirmation.

## GNADD Invariants

- `prime-gnadd` gives spatial awareness and momentum; it does not load implementation context speculatively.
- GitHub is the system of record, so open issues, open PRs, recent merged PRs, branches, and commits are the working state.
- Surface local `main` divergence and stashes prominently, but do not fix them here; this skill is read-only.
- For broader workflow or file-hygiene guidance, use `help-gnadd`.

## Mechanics

Git state classification runs through the bundled script — `gnadd.sh` in this skill's directory (the directory containing this SKILL.md). If the script is missing, stop and tell the user to reinstall the GNADD skills per help-gnadd's Install & Update guidance (`npx skills update -y` in the scope used at install, or `scripts/sync.sh` for local-checkout installs); do not reconstruct its logic from raw git commands.

## Commands

Run the state snapshot first:

```bash
bash "<skill-dir>/gnadd.sh" state
```

It fetches (`git fetch --prune` — updates remote-tracking refs only, touching no working files, so it honors the read-only contract) and reports: current branch, detached HEAD, tree clean/dirty, stash count, active issue number, and the main classification (`synced` / `behind` / `diverged`, with the divergent commits listed when dangerous). If the repo has no remote it reports `remote=none` — note that and move on.

Then gather orientation context:

```bash
tree -L 2 -I 'node_modules|__pycache__|.git|dist|build|.next|.venv|coverage|target|vendor|.pytest_cache|*.egg-info'
git log --oneline -15
git branch --list
```

If `tree` is not installed, use `find . -maxdepth 2 -type d -not -path './.git*' -not -path './node_modules*'` instead.

Then check GitHub CLI auth:

```bash
gh auth status
```

**If `gh` is unavailable or unauthenticated:** do not abort. Report the local snapshot anyway — it contains the safety-relevant signals (divergence, stashes, dirty tree) — and note that issue/PR context was skipped; suggest `gh auth login`.

When auth is confirmed, capture the authenticated login (authorship baseline
for everything below), then list with authors included:

```bash
GH_SELF="$(gh api user --jq .login)"
gh issue list --state open --json number,title,author,labels --jq '.[] | "#\(.number)\t\(.author.login)\t\(.title)\t\([.labels[].name] | join(","))"'
gh pr list --state open --json number,title,author,isDraft --jq '.[] | "#\(.number)\t\(.author.login)\t\(if .isDraft then "draft" else "open" end)\t\(.title)"'
gh pr list --state merged --limit 10 --json number,title,author --jq '.[] | "#\(.number)\t\(.author.login)\t\(.title)"'
```

If `state` reported an active issue N (`issue=<N>`), also run:

```bash
gh issue view <N>
```

## Interpretation

### Project Shape

Use the tree output to identify the top-level layout: where source, config, tests, docs, and scripts appear to live. Keep this shallow. Do not inspect files unless the user asks.

### Recent Git History

Use `git log --oneline -15` to infer the recent trajectory — active areas, development focus, recently completed themes. Avoid over-explaining individual commits.

### Current State

From the `state` output, report:

- Active branch and whether the working tree is clean.
- Other local branches that may indicate in-progress work.
- **`main_state=behind`:** normal and safe — origin has commits local main lacks. Say so plainly: "local `main` is N commits behind origin; it will sync on the next `/start-issue-gnadd`."
- **`main_state=diverged` (dangerous):** local `main` holds commits origin lacks. **Flag it as the first line of the summary**, recommend resolving before any new work, and point at the sanctioned recovery path: `gnadd.sh doctor` diagnoses it and `doctor --rescue-main <name>` performs the lossless fix. Do not fix it from this skill.
- **Stashes:** if `stashes` is nonzero, surface it — invisible saved work, easy to abandon.

### Authorship

Compare each listed item's author against `GH_SELF`. Items authored by
someone else — including bots — are **external submissions**: annotate them
inline (`— by @<login>`) wherever they appear in the summary, and if any
exist, say so up front in the relevant section ("2 of 5 open issues are
external"). When every item is self-authored — the common solo case — add no
annotations and no authorship commentary at all; the snapshot stays exactly
as uncluttered as before.

### Open Issues

Summarize pending work from the issue listing. Group by label when present;
keep issue titles and numbers visible. Apply the authorship rule — external
issues are input from other people and usually deserve a triage look before
new self-directed work.

### Open PRs

Surface work in flight. Flag PRs awaiting review — a PR sitting open is either waiting on you to review/merge or waiting on feedback. Apply the authorship rule: an external open PR is someone waiting on the maintainer, and outranks self-authored work in the "what needs attention" ordering.

### Recent Completions

Summarize the last ~10 merged PRs. Highlight momentum, not every detail. Apply the authorship rule to reveal whether recent shipping was solo or included external contributions.

### Active Issue

Only when on an `issue-<N>/<slug>` branch: summarize the issue's problem, desired outcome, and subtasks. Do not fetch referenced issues or artifacts automatically.

## Output Format

```markdown
## Project Shape
<1-2 sentences about top-level layout>

## Current State
<active branch, working tree status, local branches; flag if main is behind origin or stashes exist>

## Recent Activity
<what the last ~15 commits suggest>

## Open Work
<open issues grouped by label if useful; external ones annotated "— by @login">

## In Flight
<open PRs, flagging any awaiting review; external ones annotated "— by @login">

## Recently Shipped
<last ~10 merged PRs; external ones annotated "— by @login">

## Active Issue
<only if on issue branch>
```

Keep the summary short enough to use as quick working context.

## Closing Guidance

Offer a brief next-step nudge only when orientation completed successfully — not when the skill halted mid-run.

**Skip** when blockers were surfaced in the summary (diverged `main`, stashes, dirty tree on the wrong branch). Nudge toward resolving those first — for a diverged main, that means `gnadd.sh doctor` — not advancing the happy-path loop.

**Infer one primary suggestion** from repo state, plus at least one alternative when ambiguous:

1. Open PR awaiting review → review or merge before starting new work.
2. On `issue-<N>/*` with a dirty tree → `/commit-gnadd` or continue implementation.
3. On `issue-<N>/*`, clean → continue that issue's work.
4. On clean `main` with open issues → `/start-issue-gnadd <N>` on the most actionable issue.
5. No open issues → `/new-issue-gnadd`.

Keep it to a sentence or two with invitational options. Do not restate the full GNADD workflow.
