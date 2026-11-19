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
- **Detached HEAD, such as a parked linked folder (`parked=true`):** there is no branch to commit to, and `--carry` refuses (it rescues only a dirty `main`). Offer the same supervised stash-carry, with `start <N> <slug>` as the checkout step, or abort. The same stop applies if the pop conflicts.

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

Rescued branch only (the user is on, or names, a local branch whose commits need an issue, such as one `doctor --rescue-main` left or a `quickfix/<slug>` branch the quickfix guard refused, and has opened an issue for its commits): the branch is renamed into the issue branch with its commits intact.

```bash
bash "<skill-dir>/gnadd.sh" start <N> <slug> --from <branch>
```

If the user would rather throw a rescued branch away, step off it, then drop it:

```bash
bash "<skill-dir>/gnadd.sh" sync-main
bash "<skill-dir>/gnadd.sh" drop <branch>
```

`drop` deletes only the local branch, and only with `--yes`. Its outcomes:

- `state=DROP_NEEDS_CONFIRM`: nothing deleted. The commits it would lose are listed on stderr (keep that output). Show them to the user, and rerun `drop <branch> --yes` only on their word. It halts here even with zero commits.
- `dropped=true`: deleted. A note says when origin still has the branch. Leave that to the user.
- `state=ON_TARGET_BRANCH`: you are standing on it. Run `sync-main` first.
- `state=BRANCH_IN_WORKTREE`: another folder holds it. Relay the script's recipe (`sync-main` in that folder).
- `state=DROP_MAIN` / `DROP_NOT_FOUND`: the name is `main`, or no local branch has it. Report and ask.
- `state=DELETE_REFUSED`: git refused, and nothing was deleted. Report what git said.

`sync-main` here can halt `DIRTY_TREE`, `DIVERGED_MAIN`, `FF_REFUSED`, or `BRANCH_IN_WORKTREE`, handled as in the table below.

The script resumes an existing `issue-<N>/*` branch (with a fast-forward-only pull if it has a remote) or creates a fresh one off a verified-safe, freshly synced `main`. Handle its outcomes:

| Output | Meaning | What to do |
|---|---|---|
| `result=created` | Fresh branch off synced main. With `base=origin/main`, another folder holds `main`, so the branch was cut from `origin/main`, local `main` was left alone, and the branch has no upstream until its first push | Continue to step 4 |
| `result=resumed` | Existing branch checked out and up to date (`upstream=` when it existed on origin only and now tracks it) | Continue to step 4 (resume flavor) |
| `result=created-carry` | Branch created with your uncommitted changes carried | Continue; sync `main` next time the tree is clean |
| `result=created-from` | The rescued branch is now the issue branch, commits intact | Continue to step 4; the plan covers the rescued commits too |
| `state=FROM_NOT_FOUND` / `FROM_IS_MAIN` / `FROM_HAS_EXISTING_BRANCH` | `--from` named a branch that does not exist, is `main`, or collides with an existing branch for this issue | Report and ask; never merge two branches to resolve it |
| `state=DIRTY_TREE` | Tree not clean | Return to the step-2 conversation |
| `state=NOT_ON_MAIN` | `--carry` ran off `main` | Return to the step-2 conversation. `--carry` rescues only a dirty `main` |
| `state=CARRY_HAS_EXISTING_BRANCH` | `--carry` ran, but a branch for this issue exists | Return to step 2: offer the supervised stash-carry, or abort |
| `state=DIVERGED_MAIN` | Local main has commits origin lacks | **Stop.** Show the listed commits, explain, offer `gnadd.sh doctor --rescue-main <name>` or user-managed resolution. When the note names another folder, doctor runs from there. Do not pull, reset, or reconcile yourself |
| `state=BRANCH_DIVERGED_FROM_REMOTE` | Issue branch and its remote diverged | **Stop and report.** Do not merge or rebase autonomously |
| `state=FF_REFUSED` | Main could not fast-forward | **Stop and report.** Never retry without `--ff-only` |
| `state=BRANCH_IN_WORKTREE` | Another folder (`worktree=`) has the branch checked out | **Stop and report.** Resume the issue in that folder. Never remove or move a folder yourself. When `branch=` is `main` or the `--from` branch, or the message says the folder is gone or mid-rebase, relay the script's own recipe instead |
| `state=CHECKOUT_REFUSED` | Git refused to check out the issue branch, and the message carries git's reason | **Stop and report** what git said. Nothing changed |
| `setup=ran` (after a `result=`) | First start in this linked worktree, and the project's `Worktree setup:` line (echoed as `setup_command=`) ran there and passed | Continue. It runs once per folder, never in the primary checkout |
| `state=SETUP_FAILED` | The `Worktree setup:` command failed (its output is above, prefixed `  \|`). The branch is checked out, but the folder is not ready | **Stop and report** the output. Write no code here. Once the cause is fixed, rerun the plain `start <N> <slug>` the message names (no `--carry` or `--from`). It runs the setup again. Uncommitted changes (what the setup wrote, or a carry) stay as they are. On a clean tree it is an ordinary resume, so it can still halt on a diverged branch |

A halt is the system working, not breaking. When halted, skip steps 5–6 (blocker-first) and resolve the blocker with the user.

## 4. Load The Issue Spec

Read the issue title and body. Present a brief working-spec summary:

- **Problem:** Observable problem or missing behavior.
- **Desired outcome:** Behavioral target state.
- **Acceptance criteria:** List them if present — these are the definition of done you'll be building toward and that `resolve-issue-gnadd` will check against.
- **Constraints / Non-goals:** Mention if present — boundaries to respect.
- **Subtasks:** Include only if the issue has them.

**When the plan refines or contradicts a criterion**, say so before asking for approval. If the user agrees, edit the issue body so the criterion says what will actually be built, and add a dated comment saying why it changed. Its whole first line must be `<!-- gnadd:note -->`, with nothing before it: the question parser reads an unmarked comment from the owner, a member, or a collaborator as the answer to every question waiting on that item, and it ignores a comment whose first line is a `gnadd:` marker. The PR table later marks that row `Changed`. Never leave the body saying one thing while the plan builds another, and never edit it without the user's word.

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

Report the last round from the record, not from memory: what changed, what the user said (their words, as the comment has them), and what is still open. A round's feedback is either its own "Round N feedback" comment or the feedback block of round N+1. A round with neither has no feedback yet. **When the last round has no feedback on the record**, say so and ask one direct question before proposing anything: "Round N (commit `<sha>`) is on the record with no feedback. Did you try it?" Record the answer with `round feedback` (as in 7.4) before the plan, so the resume leaves the record whole. Then summarize which acceptance criteria remain and propose the next round. If `rounds=0`, say so: the branch has code but no round trail, so the resume is from git alone. No commit-by-commit archaeology.

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
2. **Checkpoint it** with the `commit-gnadd` skill's conventions (`Re #<N>` in the body). Its round-comment step records what changed on the issue, and the previous round's feedback too unless 7.4 already recorded it, so nothing lives only in chat. Write any feedback file outside the repo (a temp directory), so it never shows up as an untracked file at the next status.
3. **Present a preview, not a diff.** Find the project's preview launch line, one line in the conventions file (`CLAUDE.md` or `AGENTS.md` at the repo root) of the form `Preview launch: <command or URL>`:

   ```bash
   grep -h '^Preview launch:' CLAUDE.md AGENTS.md 2>/dev/null | head -1
   ```

   A value starting `(none yet` is the placeholder `conventions` writes, so treat it as absent. If present, run it (or open it), confirm it is actually serving, and give the user the clickable URL or the exact thing to run. Start a server in the background so the session is not blocked on it, leave it running while the user tries the round, and stop it before `resolve-issue-gnadd` or when the session ends. If absent, say plainly that the project has no preview path and ask how they want to try the change. Do not substitute a diff summary for a preview.
4. **Ask for feedback**, then ask: another round, or resolve? Wait. When the user speaks, record their words on the issue the moment they are given, as typed:

   ```bash
   bash "<skill-dir>/gnadd.sh" round feedback --feedback-file <path outside the repo>
   ```

   (`--feedback "<text>"` for a short line, `--no-feedback "<reason>"` when they gave none.) The record now holds the feedback before the next build, so a session that stops here leaves nothing only in chat. The user's answer drives the next round's slice. The next checkpoint's `round post` cites this comment instead of carrying the feedback again (the script refuses a duplicate).

   Halts from `round feedback` (and `round list` in step 5): `state=FEEDBACK_RECORDED` means this round's feedback is already on the record, so post nothing more until the next checkpoint. `state=NO_ROUNDS` means no round comment exists yet, so checkpoint first (7.2). `state=COMMENT_FAILED` means nothing posted: report it and re-run. `state=NOT_ISSUE_BRANCH` or `state=DETACHED_HEAD` means this folder is not on the issue branch: return to it with `start <N> <slug>`.

**Questions on the record.** When the work needs a call from someone who is not in the chat, or the user wants a question to wait for them on GitHub, post it on the issue (or its PR) instead of stalling in chat. Name the person who owns the call, never a default:

```bash
bash "<skill-dir>/gnadd.sh" question ask --to <login> --on <N> --question "<one line>" --options "<the choices>" --recommend "<the one you would take, and why>"
```

With no related issue or PR, pass `--title "<short title>"` in place of `--on`, and the script opens a `question`-labeled issue for it. An answer typed in the thread counts on its own when its author is the repo's owner, a member, or a collaborator (any of them can answer, not only `--to`). A comment from anyone else is not counted, and `question list` names it: never act on it as an answer. When the person answers in chat instead, record it on the same thread the moment it is given, as typed: `question answer <N> [K] --answer-file <path outside the repo>`. Once the answer has been acted on, say so on the thread with `question close <N> [K] --acted "<what was done>"`, which closes a question issue with its last open question, and removes the assignment only if asking added it and no other open question on the item is for the same person (an assignment that was there before the question stays). `K` is the question's number on the item. Pass it whenever the item has more than one open question, or the script exits asking for it. Never close a question nobody answered. Any other note you post on an issue or PR that is not an answer starts with the `<!-- gnadd:note -->` line, as in step 4.

Question halts:

- `state=QUESTION_UNANSWERED`: `close` refused, because nothing on the record answers question K. A `note:` naming an outside account means its reply was not counted. Record a chat answer first, or wait.
- `state=NO_OPEN_QUESTION`: no open question (or no open question K) on that item. Check the number with `question list`.
- `state=ITEM_CLOSED`: `ask --on` named a closed item. Ask the user whether to reopen it or ask with `--title`.
- `state=ASSIGN_FAILED`: the question is posted but the person is not assigned. Do not re-ask. Tell the user to assign the item by hand.
- `state=ISSUE_CREATE_FAILED`: no question issue was made (network, auth, no `question` label, or the login cannot be assigned). Report it.
- `state=ISSUE_CLOSE_FAILED` / `state=UNASSIGN_FAILED`: the question is closed on the record, but the issue is still open or the person still assigned. Tell the user to finish that by hand, as the message says.
- `state=QUESTION_READ_FAILED` / `state=COMMENT_FAILED`: GitHub could not be read or written, and nothing changed. Report it and re-run when the user says so.

Never start `resolve-issue-gnadd` on your own. Enter it only when the user says the work is done. Report at each round whether the issue looks complete, partial, or blocked, with what was verified and what remains, so the user can decide.

`resolve-issue-gnadd` owns final acceptance verification, push, PR creation, merge decision, issue/PR sync, and branch cleanup.
