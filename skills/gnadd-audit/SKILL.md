---
name: gnadd-audit
description: >-
  Read-only GNADD alignment audit: load workflow principles, scrutinize context
  files for describe-vs-track violations, perform a shallow git/workflow check,
  and return a severity-grouped report with minimal proposed fixes. Nudges
  /new-issue for remediation slices; never edits files or creates issues. Use
  when the user asks to audit GNADD alignment, review workflow hygiene, check
  project context files, or find describe-vs-track violations.
disable-model-invocation: false
---

# GNADD Audit

Review a repository against GNADD workflow principles and propose a minimal set
of alignment fixes. This is read-only: do not create, edit, stage, commit, stash,
or delete files; do not auto-create GitHub issues.

## Auto-Invocation Gate

If this skill was auto-selected from context rather than explicitly invoked with `/gnadd-audit`, stop before running commands or reading repo context. Briefly explain why a GNADD audit appears useful and ask: "Run `/gnadd-audit` now?" Proceed only after confirmation.

## GNADD Invariants

- GitHub is the system of record; tracking state belongs in issues, branches, PRs,
  and commits — not in markdown files.
- Context-file scrutiny is the primary audit dimension; git/workflow checks are
  secondary alignment signals.
- The audit complements `prime` (live snapshot) — it does not replace session
  orientation or duplicate its narrative output.
- Proposed fixes are slices for the user to capture via `/new-issue`; the agent
  never files issues autonomously.
- For broader workflow rationale, use `gnadd-context`.

## Purpose

Answer: **Is this repo aligned with GNADD principles, and what is the smallest
fix set to get there?**

Build a structured report covering:

- Context files that violate or risk violating the describe-vs-track rule
- Shallow git/workflow misalignment (orphaned branches, diverged `main`, stashes)
- Whether GNADD skills appear installed
- Minimal proposed fixes, each mappable to one `/new-issue`

Do not read source code, schemas, tests, or dependencies. Do not perform deep
commit archaeology.

## Workflow

### 1. Load Audit Criteria

Before inspecting the repo, load GNADD file-hygiene and workflow principles:

1. Use the describe-vs-track rule from `gnadd-context` if already in context.
2. Fetch Part 1 of the canonical guide from this pinned URL (same pin as
   `gnadd-context` — do not use `main`):

   https://raw.githubusercontent.com/AlexHagemeister/gnadd/6471f13ed95d99785fd3962cf3fe250672dccbf3/GNADD.md

3. If the repo being audited contains a local `GNADD.md`, reading Part 1 locally
   is an acceptable fallback or supplement.

Extract the operational taxonomy:

| Category | Examples | Default severity |
|---|---|---|
| Tracking files | `tasks.md`, `TODO.md`, progress/session-state files, maintained plans, status checklists | Violation |
| Expired phase artifacts | `requirements.md`, standalone PRD/spec not distilled into README + issues | Warning |
| Misplaced decisions | `decisions.md`, ADR folders used as live tracking | Warning |
| Describe-only (OK) | README vision, `AGENTS.md`, agent rules, archived/dated requirements | OK |
| Missing describe content | README without project-level "What done looks like" on a GNADD-shaped project | Warning |

Apply the tiebreaker from GNADD Part 1:

> Would the agent need to keep this file up to date? If yes → tracking violation.

### 2. Discover Context Files

From the repo root, run a shallow filename discovery (depth-capped, skip
`.git`, `node_modules`, `vendor`, `dist`, `build`, `.next`, `.venv`,
`coverage`, `target`):

```bash
find . -maxdepth 4 -type f \( \
  -iname 'tasks.md' -o -iname 'task.md' -o -iname 'todo.md' -o -iname 'todo.txt' \
  -o -iname 'requirements.md' -o -iname 'prd.md' -o -iname 'spec.md' \
  -o -iname 'decisions.md' -o -iname 'progress.md' -o -iname 'status.md' \
  -o -iname 'roadmap.md' -o -iname 'changelog-dev.md' \
  -o -iname 'session.md' -o -iname 'session-state.md' \
\) -not -path './.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' \
  -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/.next/*' \
  -not -path '*/.venv/*' -not -path '*/coverage/*' -not -path '*/target/*' 2>/dev/null
```

Always read `README.md` at the repo root if it exists.

For each discovered file (and `README.md`):

- Read enough to classify — usually the first ~50 lines suffices.
- Look for **tracking signals:** `- [ ]` / `- [x]` checkboxes, "Status:",
  "In Progress", sprint/progress sections, satisfaction tracking, maintained
  task lists, "current focus" notes the agent would need to update.
- Look for **safe signals:** archive headers, "as of DATE", explicit notes that
  content was distilled into issues/README, pure vision/convention text with no
  mutable state.

Classify each file as **Violation**, **Warning**, or **OK** with a one-line
rationale. When filename and content conflict, content wins.

### 3. Check GNADD Skills Presence

Determine whether GNADD skills appear available to the agent:

```bash
ls .agents/skills/ 2>/dev/null
```

Look for `gnadd-context`, `prime`, `new-issue`, or similar GNADD skill names.
Optionally try `npx skills list 2>/dev/null` if the skills CLI is available.

If undetectable or absent, report as **Info** — not a blocker. Include the
minimal install recommendation:

```bash
npx skills add AlexHagemeister/gnadd -g -a <agent> --copy -y
```

The file and git audit still runs regardless.

### 4. Shallow Git / Workflow Alignment

Verify GitHub CLI when checking workflow alignment:

```bash
gh auth status
```

If `gh` is not installed or authenticated, warn the user, skip GitHub
cross-checks, and still report local git signals from the commands below.

When auth is confirmed (or for local-only checks), run from the repo root:

```bash
git fetch --prune origin 2>/dev/null || true
git branch --show-current
git branch --list
git stash list
git log --oneline origin/main..main 2>/dev/null
git log --oneline main..origin/main 2>/dev/null
gh issue list --state open 2>/dev/null
gh pr list --state open 2>/dev/null
```

`git fetch --prune` updates remote-tracking refs only — read-only, same as
`prime`. If no remote is configured, note it and continue with local signals.

Interpret for **alignment only** — do not produce a session-orientation
narrative:

| Signal | Severity | Finding |
|---|---|---|
| `origin/main..main` shows commits | Violation | Local `main` ahead of origin — direct commits bypassing the loop |
| `main..origin/main` shows commits | Info | Local `main` behind origin — sync before adopting the loop |
| Non-empty stash list | Warning | Invisible WIP outside issues/branches |
| Branch `issue-<N>/*` with no open issue #N | Warning | Orphaned issue branch |
| Open issue #N with no branch and no recent merged PR | Info | Issue may be unstarted |
| Active WIP branch not matching `issue-<N>/<slug>` | Warning | Off-loop branch naming |
| Open PR with no issue reference in title/body | Warning | Weak issue linkage |

Do **not** review individual commits, run blame, or lint commit messages.

Cross-reference open issues with local branches by issue number extracted from
branch names (`issue-<N>/...`).

### 5. Synthesize Minimal Fixes

For every Violation and Warning, propose **one concrete minimal fix** — not a
broad rewrite plan. Group related fixes into **proposed issue slices** the user
can capture separately via `/new-issue`.

Examples:

- `tasks.md` exists → "Migrate open items to GitHub issues, then delete the
  file."
- Stale `requirements.md` → "Archive with a date header or delete after
  distilling stable conclusions into README and actionable items into issues."
- Standalone PRD with tracking content → "Collapse vision into README 'What
  done looks like'; move actionable specifics to issues."
- GNADD skills not detected → "Install GNADD skills globally per README."
- Diverged local `main` → "Resolve main divergence before starting new issue
  work."

Keep the fix set minimal — prefer the smallest change that restores alignment.

### 6. Produce the Report

Use the output format below. Lead with violations; do not bury context-file
findings below git noise.

## Classification Reference

**Violation** — Confirmed tracking file or workflow habit that actively
undermines GNADD (task lists, progress files, diverged `main` with local-only
commits).

**Warning** — Likely misalignment needing human judgment (expired
`requirements.md`, fat PRD, orphaned branch, missing README criteria section).

**OK** — Describe-only content correctly structured (vision docs, `AGENTS.md`,
archived phase artifacts clearly marked).

**Info** — Informational, not necessarily a problem (skills install unverified,
issue with no branch yet, `main` behind origin).

## Output Format

```markdown
## Summary
<1-2 sentences: overall alignment verdict — counts of violations, warnings, OK>

## Context Files
### Violations
- `<path>` — <rationale>. **Fix:** <minimal fix>

### Warnings
- `<path>` — <rationale>. **Fix:** <minimal fix>

### OK
- `<path>` — <why this is fine>

## Workflow Alignment
<git/github findings with severity; omit section if nothing to report>

## GNADD Skills
<detected / not detected / undetermined + install note if needed>

## Proposed Fixes
1. <minimal fix mappable to one /new-issue>
2. ...

## Already Aligned
<brief positives — keeps the report honest and the change set minimal>
```

Keep the report scannable. Each proposed fix should be actionable without
reading the rest of the audit.

## Closing Guidance

Offer a brief next-step nudge only when the audit completed successfully — not
when `gh auth` failed mid-run and GitHub checks were skipped.

**Skip** when the audit halted early or critical checks could not run — tell the
user what's missing first.

**Infer one primary suggestion** from findings, plus at least one alternative
when ambiguous:

1. **Violations present** → nudge `/new-issue` for the highest-severity fix;
   offer capturing the full proposed-fix list as separate issues.
2. **Warnings only, no violations** → nudge confirming which warnings are
   intentional before filing issues; offer `/new-issue` for any the user wants
   to act on.
3. **Clean audit** → nudge `/prime` for ongoing session work, or `/new-issue`
   if new work is ready to capture.
4. **GNADD skills not detected on a repo being adopted** → nudge installing
   skills first, then re-running `/gnadd-audit` after remediation issues are
   filed.

Keep it to a sentence or two with invitational options. Do not restate the full
GNADD workflow. Never auto-create issues.
