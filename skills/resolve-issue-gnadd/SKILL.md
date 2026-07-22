---
name: resolve-issue-gnadd
description: >-
  Wrap up work on a GitHub issue using the bundled gnadd script and gh:
  identify the issue branch, verify the work against acceptance criteria, run
  the project's tests, commit final changes, create or resume the PR, check
  mergeability and CI, optionally merge, sync the issue record, and clean up.
  Does not rebase. Use when issue work appears complete, the user wants to
  ship an issue branch, or the next step is verification, PR creation, merge
  decision, and cleanup.
disable-model-invocation: false
---

# Resolve Issue

Wrap up work on a GitHub issue. Do not commit, create a PR, or merge without user approval at the required gates.

## Auto-Invocation Gate

If this skill was auto-selected from context rather than explicitly invoked with `/resolve-issue-gnadd`, stop before running git or GitHub commands. Briefly explain why resolving the current issue appears useful and ask: "Run `/resolve-issue-gnadd` now?" Proceed only after confirmation.

## GNADD Invariants

- Resolve verifies the issue contract against actual changes before anything ships.
- The PR records what shipped, including descopes, divergences, and non-obvious decisions.
- GitHub computes mergeability; do not locally rebase or resolve conflicts autonomously.
- The human must review the diff before merge. Tests, CI, and mergeability checks support that decision; they do not replace it.
- For broader workflow or file-hygiene guidance, use `help-gnadd`.

## Mechanics

Ship mechanics run through the bundled script — `gnadd.sh` in this skill's directory. It enforces the invariants deterministically: never ships from `main`, refuses conflicting merges, halts on the dangerous divergence direction, and deletes branches only after GitHub confirms the merge. When it exits with `state=<NAME>`, that is a human decision point — have the conversation, never work around it with raw git. If the script is missing, stop and tell the user to reinstall the GNADD skills per help-gnadd's Install & Update guidance (`npx skills update -y` in the scope used at install, or `scripts/sync.sh` for local-checkout installs).

## 1. Identify The Issue

```bash
bash "<skill-dir>/gnadd.sh" state --no-fetch
```

- If `issue=<N>`, that is the issue being resolved.
- If on `main`, `master`, or detached HEAD, **stop**. Never run this flow from main: shipping from main would push unreviewed work straight to `origin/main`, bypassing the PR gate (the script refuses this too). List local issue branches (`git branch --list "issue-*"`), ask which one to resolve, and switch to it — applying the same working-tree protection as `start-issue-gnadd` (never switch on a dirty tree without an explicit commit/stash/abort choice).
- If on some other non-issue branch, ask the user to confirm this branch holds the work to resolve. Only after explicit confirmation, use `--any-branch` in step 4; everything below still applies.

## 2. Verify Completeness

Fetch the issue:

```bash
gh issue view <N>
```

Verify the finished work against the **Acceptance Criteria** — the issue's definition of done:

- Assess each criterion against the **actual diff and observable behavior**, not from memory of the session. Inspect `git diff origin/main...HEAD` to ground the assessment in what actually changed.
- Treat checkboxes already ticked in the issue as **claims, not facts** — later work may have invalidated them. Re-verify every criterion regardless of checkbox state.
- For each criterion, report: **met**, **not met**, or **descoped** (with a reason). Do the same for any subtask checklist.
- Flag anything unmet as a check, not a hard blocker. The user may override and proceed — but say so explicitly rather than skipping silently.
- Note any descopes or divergences now; they go in the PR body in step 5.

Then run the project's tests:

```bash
bash "<skill-dir>/gnadd.sh" test
```

It auto-detects the test command (npm/make/cargo/go/pytest). Report the result alongside the criteria assessment. `state=NO_TESTS` means nothing automated verified this work — say so; the diff review is then the only safeguard. A failing suite is a stop-and-discuss, not something to wave past.

## 3. Stage And Commit

**If the working tree is clean** (all work already committed via `/commit-gnadd`), skip to step 4 — nothing needs to be invented or re-staged. The PR body's `Closes #<N>` still auto-closes the issue on merge.

Otherwise inspect and stage intended changes:

```bash
git status
git diff
git add <relevant-files>
```

Choose a conventional commit message from the **actual change** (the issue label is only a starting point: `bug`→`fix`, `feature`→`feat`, `chore`→`chore`; override when the diff warrants it). Allowed types match the `commit-gnadd` skill: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `style`, `perf`.

```bash
git commit -m "$(cat <<'EOF'
<type>: <summary>

<brief behavioral description>

Closes #<N>
EOF
)"
```

## 4. Push (and detect an existing PR)

This workflow does **not** rebase the issue branch onto `main` — GitHub's squash-merge already applies the branch as one commit on top of latest main, and rebase is the most dangerous operation to hand an agent. Conflicts are detected via GitHub after the PR exists (step 6) and handed to the human.

```bash
bash "<skill-dir>/gnadd.sh" ship push
```

Outcomes:

- **`pr_exists=true` with `pr_number=<PR>`:** an open PR already exists for this branch — this is a **resume** (e.g. the PR was left open in a previous session). New commits are now pushed to it. Skip step 5 and go straight to the merge gate in step 6 with `<PR>`.
- **`pr_exists=false`:** continue to step 5 to create the PR.
- **`state=NOTHING_TO_SHIP`:** no commits beyond `origin/main` — nothing to resolve; stop and say so.
- **`state=ON_MAIN` / `NOT_ISSUE_BRANCH` / `DIRTY_TREE` / `DETACHED_HEAD`:** return to the step 1/3 conversations.
- **`state=PUSH_FAILED`:** report; retry after the user checks network/auth.

## 5. Draft And Create The PR

Draft the PR and show it for approval **before** creating:

- **Title:** same as or close to the final commit summary.
- **Body** (this exact structure — step 7 updates it after merge):

```markdown
<concise behavioral summary of what was actually done>

## Acceptance Criteria

| Criterion | Status |
|---|---|
| <criterion text> | Met / Not verified / Descoped — <reason> |

## Decisions & Divergences

<non-obvious implementation decisions made during the work, descopes,
follow-ups; omit the section if genuinely none — but remember chat
evaporates and PRs are permanent>

## Test Plan

- [ ] Automated tests pass (<runner from step 2, or "none configured">)
- [ ] Diff reviewed by a human before merge

Closes #<N>
```

Create only after approval, and **capture the PR number from the output URL** — issues and PRs share a number space, so the issue number is never the PR number:

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)"
```

Report the PR URL. `<PR>` below means this captured PR number.

## 6. Merge Only If Confirmed

Surface the two signals, then ask whether to merge now or leave the PR open. Do not auto-merge.

```bash
bash "<skill-dir>/gnadd.sh" ship status <PR>
```

- **`mergeable=MERGEABLE`** — present the merge choice.
- **`mergeable=CONFLICTING`** — **do not offer to merge.** `main` has moved and the PR conflicts. Hand resolution to the user: GitHub's web editor, or a deliberate local resolution they drive. The agent never resolves conflicts autonomously.
- **`mergeable=UNKNOWN`** — GitHub is still computing; wait briefly and re-run.
- **Checks:** if failing, say so explicitly and require the user to acknowledge before merging anyway. If none are configured, note that nothing automated verified this PR beyond the local test run.

> AI-authored PRs read as authoritative and can hide subtle logic errors. The merge gate is only as good as the human reading the diff. Do not let "merge now" become reflexive. If the user hasn't looked at the diff, offer it (`gh pr diff <PR>`).

If — and only if — the user confirms:

```bash
bash "<skill-dir>/gnadd.sh" ship merge <PR>
bash "<skill-dir>/gnadd.sh" sync-main
```

`ship merge` squash-merges only when the PR is OPEN and MERGEABLE. `sync-main` returns to `main` and fast-forwards it — after a merge, local main is normally just *behind* by the squash commit, which is the expected, safe state. If it reports `state=DIVERGED_MAIN` instead, **stop**: show the listed commits, and offer `gnadd.sh doctor --rescue-main <name>` or user-managed resolution. Never reset, never merge without `--ff-only`.

If the user leaves the PR open: stop here. Next session, `/resolve-issue-gnadd` on this branch resumes at the merge gate automatically (step 4 detects the open PR).

## 7. Sync The Record (Issue + PR)

After merge (or when closing the issue without merge), sync both the issue and the PR body with the step-2 assessment. Do this before reporting resolve complete.

### Issue

**Fetch the current body fresh immediately before editing** — never reconstruct it from memory or an earlier read; `gh issue edit --body` replaces the whole body, so a stale copy silently destroys collaborator edits:

```bash
gh issue view <N> --json body --jq .body
```

Modify **only**: acceptance-criteria checkboxes (`- [x]` for met, `- [ ]` for not met / not verified) and an appended **## Resolution** section (PR link, merge commit, one line per unchecked criterion explaining why the issue still closed). Preserve everything else verbatim.

```bash
gh issue edit <N> --body "$(cat <<'EOF'
<full updated issue body>
EOF
)"
```

Editing works on closed issues, so auto-close from `Closes #<N>` is not a problem.

### PR

Same fetch-fresh rule (`gh pr view <PR> --json body --jq .body`), then update the step-5 structure to match what was actually verified: the acceptance-criteria table's Status column, and the Test Plan checkboxes for steps that actually ran.

```bash
gh pr edit <PR> --body "$(cat <<'EOF'
<full updated PR body>
EOF
)"
```

The issue is the canonical record; the PR is the ship-time audit trail — both should agree on what was met vs deferred.

## 8. Clean Up After Merge

```bash
bash "<skill-dir>/gnadd.sh" cleanup <PR> issue-<N>/<slug>
```

The script confirms via GitHub that the PR actually merged (`state=MERGED` with a real `mergedAt`) **before** force-deleting the branch — that check is what makes `-D` provably non-destructive after a squash-merge (safe `-d` always refuses, because squash commits are not ancestors of the branch). It then removes the remote branch if GitHub's auto-delete hasn't already, and reports `merge_commit=<hash>`.

- **`state=NOT_MERGED`:** the PR didn't merge (left open, or merge failed) — the branch is **not** deleted. Stop and report.
- **Never run `git reset` on `main` to discard commits** — in any form, for any reason. If anything about main looks wrong here, `gnadd.sh doctor` is the sanctioned path.

Report what was cleaned up, and give the user the merge commit hash — their one-command undo for the whole feature (`git revert <hash>`).

## Closing Guidance

Offer a brief next-step nudge only at natural completion — not at intermediate gates (wrong branch, unmet criteria discussion, commit/PR approval waits, merge conflicts, failing tests or CI, or main divergence during cleanup).

**Natural completion:**

- Merged and cleanup finished → nudge toward `/prime-gnadd` for the next session.
- PR created but left open → nudge toward reviewing the diff or addressing feedback — not `/start-issue-gnadd` for new work.

**Stopped on a blocker:** nudge only toward resolving that blocker.

Keep it to a sentence or two with invitational options. Do not restate the full GNADD workflow.
