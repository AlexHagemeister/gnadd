---
name: start-issue-gnadd
description: >-
  Set up work on a GitHub issue using the bundled gnadd script and gh: identify
  the issue, protect any in-progress work, resume or create the issue branch,
  load the issue spec, propose an implementation plan, and wait for user
  approval before coding. Use when the user wants to begin or resume work from
  an open GitHub issue, switch into issue work, or turn an issue into an
  implementation session.
disable-model-invocation: false
---

# Start Issue

Set up a working session for a GitHub issue. Do not start coding until the plan is approved.

## Auto-Invocation Gate

If this skill was auto-selected from context rather than explicitly invoked with `/start-issue-gnadd`, stop before running git or GitHub commands. Briefly explain why starting issue work appears useful and ask: "Run `/start-issue-gnadd` now?" Proceed only after confirmation.

## GNADD Invariants

- Work happens on issue branches; protect any in-progress work before switching branches.
- A real commit is preferred over a stash because commits are visible and recoverable.
- Never create local-main divergence while rescuing work; carry dirty `main` changes onto a fresh issue branch when the user confirms that path.
- The issue is the contract for the work session; propose a plan and get approval before implementation.
- For broader workflow or file-hygiene guidance, use `help-gnadd`.

## Mechanics

All branch mechanics run through the bundled script — `gnadd.sh` in this skill's directory. It enforces the invariants deterministically: working-tree protection before any checkout, fast-forward-only syncs onto `main`, and a hard stop on the dangerous divergence direction. When it exits with `state=<NAME>`, that is a **human decision point** — have the conversation below, never work around the script with raw git. If the script is missing, stop and tell the user to reinstall the GNADD skills per help-gnadd's Install & Update guidance (`npx skills update -y` in the scope used at install, or `scripts/sync.sh` for local-checkout installs).

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

## 2. Survey The Ground

```bash
bash "<skill-dir>/gnadd.sh" state
```

Two situations need a conversation **before** touching branches:

**Dirty working tree** (`tree=dirty`) — the script will refuse to switch branches on it, by design. Ask the user how to handle it:

- **On an issue branch or other work branch:** offer — commit it to the current branch (**preferred**: a real commit is visible, recoverable, and survives sessions), stash it (only on explicit request; note that a stash is invisible and easy to forget), or abort. For the commit path, follow the `commit-gnadd` skill's conventions (conventional message, `Re #<M>` if on `issue-<M>/*`).
- **On `main`, no branch for this issue yet:** the correct rescue is carrying the changes onto the new issue branch — this is the "started editing before starting the issue" case, and it is lossless by construction. Confirm with the user, then use `--carry` in step 3. Never commit the changes to `main`.
- **On `main`, issue branch already exists:** carrying changes across a real checkout can conflict. Offer an explicit, supervised stash-carry — `git stash push -u`, check out the branch, `git stash pop`, report the result — or abort. If the pop conflicts, stop immediately and report; do not resolve it autonomously.

**Currently on a different issue branch** (`issue=<M>` where M ≠ N) — confirm the switch explicitly before proceeding, even with a clean tree. Do not switch away from someone's in-progress issue silently.

**`main_state=diverged`** — the script will halt in step 3 anyway, but if you already see it here, surface it now and point to `gnadd.sh doctor` before anything else.

## 3. Resume Or Create The Branch

Derive `<slug>` from the issue title: short kebab-case, most specific nouns and verbs, full branch name under ~50 characters (e.g. `issue-14/stale-navbar-data`).

Normal path (clean tree, or cleaned up via the step-2 conversation):

```bash
bash "<skill-dir>/gnadd.sh" start <N> <slug>
```

Confirmed dirty-main rescue only:

```bash
bash "<skill-dir>/gnadd.sh" start <N> <slug> --carry
```

The script resumes an existing `issue-<N>/*` branch (with a fast-forward-only pull if it has a remote) or creates a fresh one off a verified-safe, freshly synced `main`. Handle its outcomes:

| Output | Meaning | What to do |
|---|---|---|
| `result=created` | Fresh branch off synced main | Continue to step 4 |
| `result=resumed` | Existing branch checked out and up to date | Continue to step 4 (resume flavor) |
| `result=created-carry` | Branch created with your uncommitted changes carried | Continue; sync `main` next time the tree is clean |
| `state=DIRTY_TREE` | Tree not clean | Return to the step-2 conversation |
| `state=DIVERGED_MAIN` | Local main has commits origin lacks | **Stop.** Show the listed commits, explain, offer `gnadd.sh doctor --rescue-main <name>` or user-managed resolution. Do not pull, reset, or reconcile yourself |
| `state=BRANCH_DIVERGED_FROM_REMOTE` | Issue branch and its remote diverged | **Stop and report.** Do not merge or rebase autonomously |
| `state=FF_REFUSED` | Main could not fast-forward | **Stop and report.** Never retry without `--ff-only` |

A halt is the system working, not breaking. When halted, skip steps 5–6 (blocker-first) and resolve the blocker with the user.

## 4. Load The Issue Spec

Read the issue title and body. Present a brief working-spec summary:

- **Problem:** Observable problem or missing behavior.
- **Desired outcome:** Behavioral target state.
- **Acceptance criteria:** List them if present — these are the definition of done you'll be building toward and that `resolve-issue-gnadd` will check against.
- **Constraints / Non-goals:** Mention if present — boundaries to respect.
- **Subtasks:** Include only if the issue has them.

If the issue's **Context** section references other issues or artifacts, mention them without fetching automatically ("This references #11. Want me to pull that up?"). Keep context lean; let the user request more.

## 5. Propose A Plan

Translate the vertical slice into a systematic path — ordered steps derived from the acceptance criteria (and subtasks, if present). This is the skill's closing; do not add a separate next-step section after the approval ask.

**Plan quality:**

- Derive steps from the issue spec — acceptance criteria first, then constraints and subtasks.
- Stay at the "systematic path" level: what to do, in what order, and why it maps to done.
- Do not read source files, draft code, or do deep implementation exploration to build the plan. The issue is enough until the user confirms direction.
- Keep the plan proportional — a few ordered steps for thin slices, more only when the issue genuinely decomposes that way.

**Fresh start:** an ordered implementation plan mapping acceptance criteria to sequential work steps.

**Resume:** a lighter plan. Reconcile progress from shallow branch signals:

```bash
git log --oneline main..HEAD
git diff --stat main...HEAD
```

Summarize what appears done, which acceptance criteria remain open, and proposed next steps. No commit-by-commit archaeology.

## 6. Wait For Approval

Stop after the plan. Do not start coding, editing files, or deep implementation exploration until the user responds.

Explicitly ask whether:

- The plan looks right and they want to proceed.
- Intent needs correction — something in the issue was misunderstood.
- They want a different approach than the one proposed.

Tone is invitational ("Does this plan look right?"), not prescriptive. Honor corrections and revise the plan before proceeding. Implementation begins only after an explicit go-ahead ("go", "looks good", "proceed"). The issue is the contract; the plan is the agreed path.

## 7. After Approval

Implement the issue on the current issue branch.

- Stay aligned with the approved plan and issue acceptance criteria.
- Pause for user direction if new evidence changes the scope or approach.
- Commit coherent checkpoints when a behavioral slice is complete, tests pass for that slice, or before risky follow-on work — using the `commit-gnadd` skill's conventions (`Re #<N>` in the body).
- Report whether the issue work is complete, partial, or blocked. Include what changed, what was verified, and any remaining gaps.

When work appears complete and the working tree is clean, nudge to `/resolve-issue-gnadd` as the next operational step. `resolve-issue-gnadd` owns final acceptance verification, push, PR creation, merge decision, issue/PR sync, and branch cleanup.
