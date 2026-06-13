---
name: start-issue
description: >-
  Set up work on a GitHub issue using gh and git: identify the issue, resume or
  create the issue branch, load the issue spec, propose an implementation plan,
  and wait for user approval before coding. Use only when explicitly invoked with
  /start-issue.
disable-model-invocation: true
---

# Start Issue

Set up a working session for a GitHub issue using `gh` and `git`. Do not start coding.

## GNADD Invariants

- Work happens on issue branches; protect any in-progress work before switching branches.
- A real commit is preferred over a stash because commits are visible and recoverable.
- Never create local-main divergence while rescuing work; carry dirty `main` changes onto a fresh issue branch when the user confirms that path.
- The issue is the contract for the work session; propose a plan and get approval before implementation.
- For broader workflow or file-hygiene guidance, use `gnadd-context`.

## Invocation

The user invokes `/start-issue` with either:

- An issue number, e.g. `/start-issue 14`
- A natural language description, e.g. `/start-issue the navbar caching bug`

## 1. Identify The Issue

If the user provides an issue number:

```bash
gh issue view <N>
```

If the user provides a description:

```bash
gh issue list --state open
```

Find the best matching open issue.

- If exactly one issue clearly matches, use it.
- If multiple issues are plausible, show the candidates and ask the user to choose. Do not guess.
- If no issue matches, say so and ask whether to list open issues or create a new one.
- If the issue is closed, stop and ask: "Issue #N is already closed. Want to reopen it, or did you mean a different one?"

Do not continue past a closed issue until the user clarifies.

## 2. Protect Any In-Progress Work (before any checkout)

**Do this before checking out or creating any branch** — including before resuming an existing issue branch. Switching branches with a dirty working tree can either fail or silently carry uncommitted changes onto the wrong branch. Never let that happen.

First, see the current branch and working state:

```bash
git branch --show-current
git status
```

**If the working tree is dirty** (staged, unstaged, or untracked changes), stop and ask how to handle it before going any further:

- **Commit it to the current branch** (preferred) — a real commit is visible, recoverable, and survives sessions.
- **Stash it** — only if the user explicitly chooses this. Note the tradeoff: a stash is invisible to `git status`/`git log` and easy to forget. Prefer a WIP commit.
- **Abort** the issue start.

**Special case — dirty tree while on `main`:** never commit the changes to `main`; that creates the local-ahead divergence the workflow treats as dangerous. Instead:

- **Fresh start** (no `issue-<N>/*` branch exists yet — check with `git branch --list "issue-<N>/*"`): prefer **carrying the changes onto the new issue branch**. `git checkout -b` preserves the working tree, and since the new branch starts at main's current commit nothing can conflict or be lost. This is the correct rescue for "started editing before starting the issue" — confirm with the user, then proceed to step 4 with the changes carried along (skip the pull in step 4 if the tree is dirty; sync main next time it is clean).
- **Resume** (the issue branch already exists): carrying changes across a real checkout can conflict or silently land them on the wrong branch. Offer an explicit, supervised stash-carry — `git stash push -u`, check out the branch, `git stash pop`, report the result — or abort. Never do this silently, and stop immediately and report if the pop conflicts; do not resolve it autonomously.

Do not silently stash. Do not proceed on a dirty working tree, with one exception: the explicit, user-confirmed fresh-start carry from `main` described above.

**If the current branch is a *different* issue branch** (`issue-<M>/*` where `<M>` is not the issue being started), make the switch explicit. Combined with the dirty-tree handling above, the choice is:

- Commit current work to `issue-<M>`, then switch (preferred).
- Stash, then switch (only on explicit request).
- Abort.

Do not switch away from a different issue branch without explicit confirmation.

Only once the working tree is clean (or the user has chosen commit/stash/abort) may you proceed to resume or create a branch.

## 3. Check For An Existing Branch

With the working tree now safe, check local branches:

```bash
git branch --list "issue-<N>/*"
```

If a matching branch exists, treat this as a **resume**:

1. Check out the branch (safe now that the working tree is clean).
2. If it has a remote tracking branch, pull with `git pull --ff-only`. If the pull refuses (the branch has diverged from its remote — e.g. someone pushed to it while local work continued), **stop and report**; do not merge or rebase autonomously.
3. Skip to "Load The Issue Spec".

If no matching branch exists, treat this as a **fresh start** and continue.

## 4. Create The Branch

For a clean fresh start, first make sure local `main` is safe to build on:

```bash
git checkout main
git fetch origin main
git log --oneline origin/main..main
```

- If that log shows **any commits**, local `main` has diverged: it holds commits origin lacks (usually a sign something was committed directly to local `main`). **Stop.** Do not pull, reset, or reconcile autonomously. Explain the state, show both directions (`origin/main..main` and `main..origin/main`), offer the options (rebase local main onto origin, merge origin into local main, or user handles it), and wait for the user's choice.
- If it is empty, proceed:

```bash
git pull --ff-only origin main
git checkout -b issue-<N>/<slug>
```

`--ff-only` is the backstop: if `main` cannot fast-forward for any reason, the pull refuses rather than creating a merge commit on `main`. A refused or failed pull here is a **stop-and-report** event, not something to fix autonomously.

(If arriving here via the dirty-tree carry from step 2, skip the fetch/pull — don't sync `main` with a dirty tree — and go straight to `git checkout -b`.)

Derive `<slug>` from the issue title:

- Use short kebab-case.
- Keep the full branch name under about 50 characters.
- Prefer the most specific nouns and verbs from the title.

Example: `issue-14/stale-navbar-data`

## 5. Load The Issue Spec

Read the issue title and body. Present a brief working-spec summary:

- **Problem:** Observable problem or missing behavior.
- **Desired outcome:** Behavioral target state.
- **Acceptance criteria:** List them if present — these are the definition of done you'll be building toward and that `resolve-issue` will check against.
- **Constraints / Non-goals:** Mention if present — boundaries to respect.
- **Subtasks:** Include only if the issue has them.

If the issue's **Context** section references other issues or artifacts, mention them without fetching automatically.

Example: "This references #11. Want me to pull that up?"

Keep context lean. Let the user request more.

## 6. Propose A Plan

After the working-spec summary, translate the vertical slice into a systematic path — ordered steps derived from the acceptance criteria (and subtasks, if present). This is the skill's closing; do not add a separate next-step section after the approval ask in step 7.

**Plan quality:**

- Derive steps from the issue spec — acceptance criteria first, then constraints and subtasks.
- Stay at the "systematic path" level: what to do, in what order, and why it maps to done.
- Do not read source files, draft code, or do deep implementation exploration to build the plan. The issue is enough until the user confirms direction.
- Keep the plan proportional — a few ordered steps for thin slices, more only when the issue genuinely decomposes that way.

**Fresh start:** Present an ordered implementation plan mapping acceptance criteria to sequential work steps.

**Resume:** Present a lighter plan. Use shallow branch signals to reconcile progress:

```bash
git log --oneline main..HEAD
git diff --stat main...HEAD
```

Summarize what appears done on the branch, which acceptance criteria remain open, and proposed next steps. Do not turn this into a commit-by-commit archaeology session.

**Skip steps 6 and 7** (blocker-first only) when the skill stopped earlier: dirty tree awaiting a choice, diverged `main`, closed issue, pull refused, or switching away from a different issue branch without confirmation.

## 7. Wait For Approval

Stop after the plan. Do not start coding, editing files, or deep implementation exploration until the user responds.

Explicitly ask whether:

- The plan looks right and they want to proceed.
- Intent needs correction — something in the issue was misunderstood.
- They want a different approach than the one proposed.

Tone is invitational ("Does this plan look right?"), not prescriptive. Honor corrections and revise the plan before proceeding.

Implementation begins only after the user approves the plan or gives an explicit go-ahead (e.g. "go", "looks good", "proceed"). The issue is the contract; the plan is the agreed path.

## 8. After Approval

When the user approves the plan, implement the issue on the current issue branch.

- Stay aligned with the approved plan and issue acceptance criteria.
- Pause for user direction if new evidence changes the scope or approach.
- Commit coherent checkpoints when a behavioral slice is complete, tests pass for that slice, or before risky follow-on work.
- Use the issue-branch commit convention from `commit`: conventional commit message with `Re #<N>` in the body.
- Report whether the issue work is complete, partial, or blocked. Include what changed, what was verified, and any remaining gaps.

When work appears complete and the working tree is clean, nudge to `/resolve-issue` as the next operational step. `resolve-issue` owns final acceptance verification, push, PR creation, merge decision, issue/PR sync, and branch cleanup.
