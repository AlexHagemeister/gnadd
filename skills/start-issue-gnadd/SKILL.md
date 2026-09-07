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

Rescued branch only (the user is on, or names, a branch `doctor --rescue-main` left, and has opened an issue for its commits): the branch is renamed into the issue branch with its commits intact.

```bash
bash "<skill-dir>/gnadd.sh" start <N> <slug> --from <branch>
```

The script resumes an existing `issue-<N>/*` branch (with a fast-forward-only pull if it has a remote) or creates a fresh one off a verified-safe, freshly synced `main`. Handle its outcomes:

| Output | Meaning | What to do |
|---|---|---|
| `result=created` | Fresh branch off synced main | Continue to step 4 |
| `result=resumed` | Existing branch checked out and up to date | Continue to step 4 (resume flavor) |
| `result=created-carry` | Branch created with your uncommitted changes carried | Continue; sync `main` next time the tree is clean |
| `result=created-from` | The rescued branch is now the issue branch, commits intact | Continue to step 4; the plan covers the rescued commits too |
| `state=FROM_NOT_FOUND` / `FROM_IS_MAIN` / `FROM_HAS_EXISTING_BRANCH` | `--from` named a branch that does not exist, is `main`, or collides with an existing branch for this issue | Report and ask; never merge two branches to resolve it |
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

**When the plan refines or contradicts a criterion**, say so before asking for approval. If the user agrees, edit the issue body so the criterion says what will actually be built, and add a dated comment saying why it changed. The PR table later marks that row `Changed`. Never leave the body saying one thing while the plan builds another, and never edit it without the user's word.

If the issue's **Context** section references other issues or artifacts, mention them without fetching automatically ("This references #11. Want me to pull that up?"). Keep context lean; let the user request more.

## 5. Propose A Plan

Translate the vertical slice into a systematic path — ordered steps derived from the acceptance criteria (and subtasks, if present). This is the skill's closing; do not add a separate next-step section after the approval ask.

**Plan quality:**

- Derive steps from the issue spec — acceptance criteria first, then constraints and subtasks.
- Stay at the "systematic path" level: what to do, in what order, and why it maps to done.
- Do not read source files, draft code, or do deep implementation exploration to build the plan. The issue is enough until the user confirms direction.
- Keep the plan proportional — a few ordered steps for thin slices, more only when the issue genuinely decomposes that way.

**Fresh start:** an ordered implementation plan mapping acceptance criteria to sequential work steps.

**Resume:** a lighter plan. First read the round record on the issue, then shallow branch signals:

```bash
bash "<skill-dir>/gnadd.sh" round list
git log --oneline main..HEAD
git diff --stat main...HEAD
```

Report the last round from the record, not from memory: what changed, what the user said (their words, as the comment has them), and what is still open. A round's feedback is either its own "Round N feedback" comment or the feedback block of round N+1; a round with neither has no feedback yet. **When the last round has no feedback on the record**, say so and ask one direct question before proposing anything: "Round N (commit `<sha>`) is on the record with no feedback. Did you try it?" Record the answer with `round feedback` before the plan, so the resume leaves the record whole. Then summarize which acceptance criteria remain and propose the next round. If `rounds=0`, say so: the branch has code but no round trail, so the resume is from git alone. No commit-by-commit archaeology.

## 6. Wait For Approval

Stop after the plan. Do not start coding, editing files, or deep implementation exploration until the user responds.

Explicitly ask whether:

- The plan looks right and they want to proceed.
- Intent needs correction — something in the issue was misunderstood.
- They want a different approach than the one proposed.

Tone is invitational ("Does this plan look right?"), not prescriptive. Honor corrections and revise the plan before proceeding. Implementation begins only after an explicit go-ahead ("go", "looks good", "proceed"). The issue is the contract; the plan is the agreed path.

## 7. After Approval: The Round Loop

Work on the issue branch proceeds in rounds, not in a straight line to the PR. A round is: implement a slice, checkpoint it, hand the user something to try, and wait for what they say. Tests going green ends a slice, never the issue.

Each round:

1. **Implement one slice** of the approved plan. Stay aligned with the plan and the acceptance criteria. Pause for direction if new evidence changes scope or approach.
2. **Checkpoint it** with the `commit-gnadd` skill's conventions (`Re #<N>` in the body). Its round-comment step records what changed on the issue, and the previous round's feedback too unless step 4 already recorded it, so nothing lives only in chat. Write any feedback file outside the repo (a temp directory), so it never shows up as an untracked file at the next status.
3. **Present a preview, not a diff.** Find the project's preview launch line, one line in the conventions file (`CLAUDE.md` or `AGENTS.md` at the repo root) of the form `Preview launch: <command or URL>`:

   ```bash
   grep -h '^Preview launch:' CLAUDE.md AGENTS.md 2>/dev/null | head -1
   ```

   If present, run it (or open it), confirm it is actually serving, and give the user the clickable URL or the exact thing to run. Start a server in the background so the session is not blocked on it, leave it running while the user tries the round, and stop it before `resolve-issue-gnadd` or when the session ends. If absent, say plainly that the project has no preview path and ask how they want to try the change. Do not substitute a diff summary for a preview.
4. **Ask for feedback**, then ask: another round, or resolve? Wait. When the user speaks, record their words on the issue the moment they are given, as typed:

   ```bash
   bash "<skill-dir>/gnadd.sh" round feedback --feedback-file <path outside the repo>
   ```

   (`--feedback "<text>"` for a short line, `--no-feedback "<reason>"` when they gave none.) The record now holds the feedback before the next build, so a session that stops here leaves nothing only in chat. The user's answer drives the next round's slice. The next checkpoint's `round post` cites this comment instead of carrying the feedback again (the script refuses a duplicate).

Never start `resolve-issue-gnadd` on your own. Enter it only when the user says the work is done. Report at each round whether the issue looks complete, partial, or blocked, with what was verified and what remains, so the user can decide.

`resolve-issue-gnadd` owns final acceptance verification, push, PR creation, merge decision, issue/PR sync, and branch cleanup.
