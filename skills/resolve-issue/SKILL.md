---
name: resolve-issue
description: >-
  Wrap up work on a GitHub issue using git and gh: identify the issue branch,
  check completeness against the issue spec, commit with approval, create a PR,
  check mergeability and CI, optionally merge, and clean up. Does not rebase.
  Use only when explicitly invoked with /resolve-issue.
disable-model-invocation: true
---

# Resolve Issue

Wrap up work on a GitHub issue using `git` and `gh`. Do not commit, create a PR, or merge without user approval at the required gates.

## GNADD Invariants

- Resolve verifies the issue contract against actual changes before anything ships.
- The PR records what shipped, including descopes, divergences, and non-obvious decisions.
- GitHub computes mergeability; do not locally rebase or resolve conflicts autonomously.
- The human must review the diff before merge. CI and mergeability checks support that decision; they do not replace it.
- For broader workflow or file-hygiene guidance, use `gnadd-context`.

## 1. Identify The Issue

Infer the issue number from the current branch:

```bash
git branch --show-current
```

Expected branch format: `issue-<N>/<slug>`.

- If the current branch matches, use `<N>` as the issue number.
- If the current branch is `main`, `master`, or **empty** (detached HEAD), **stop**. Never run this flow from main: every step below commits to and pushes the *current* branch, which on main would ship unreviewed work straight to `origin/main` — bypassing the PR gate entirely. Instead, list local issue branches (`git branch --list "issue-*"`), ask which one to resolve, and switch to it, applying the same working-tree protection as `start-issue` (never switch on a dirty tree without an explicit commit/stash/abort choice).
- If the current branch is some other non-issue branch, ask the user to confirm that this branch holds the work to resolve. Proceed on it only after explicit confirmation; everything below (PR, merge gate, cleanup) still applies.

## 2. Sanity Check Completeness

Fetch the issue:

```bash
gh issue view <N>
```

Review the issue title, body, labels, **Acceptance Criteria**, and any subtask checklist.

Verify the finished work against the acceptance criteria specifically — these are the issue's definition of done:

- Go through each acceptance criterion and assess it against the **actual diff and observable behavior**, not from memory of the session. Inspect `git diff origin/main...HEAD` if needed to ground the assessment in what actually changed.
- Treat any checkboxes already checked in the issue (e.g. ticked mid-work) as **claims, not facts** — later work may have invalidated them. Re-verify every criterion regardless of its current checkbox state.
- For each criterion, report: **met**, **not met**, or **descoped** (with a reason).
- Do the same for any subtask checklist items.
- Flag anything unmet as a check, not a hard blocker. The user may override and proceed if remaining items are unnecessary or will be handled separately — but say so explicitly rather than skipping silently.
- If criteria were descoped or the outcome diverged from the spec, note it now; it will go in the PR body in step 5.

Do not silently skip obvious unmet criteria or checklist items.

## 3. Stage And Draft Commit

Inspect the working tree, then stage intended changes:

```bash
git status
git diff
git add <relevant-files>
```

**If the working tree is clean** (all work was already committed via `/commit`), skip the staging and commit below and go straight to step 4 — nothing needs to be invented or re-staged. The PR body's `Closes #<N>` (step 5) still auto-closes the issue on merge, so no final commit is required to carry it.

Draft a conventional commit message. Choose the type from the **actual change**, not from the label alone. The issue label is a default starting point:

- `bug` -> usually `fix: <summary>`
- `feature` -> usually `feat: <summary>`
- `chore` -> usually `chore: <summary>`

Override when the diff warrants it — a `chore`-labeled issue may land a `docs`, `refactor`, or `test` commit. The allowed types are the same as the `commit` skill: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `style`, `perf`.

Commit body requirements:

- Reference the issue with `Closes #<N>`.
- Briefly describe what was done.
- Keep the description behavioral and outcome-focused.

Show the draft commit message and ask for approval before committing.

Commit only after approval:

```bash
git commit -m "$(cat <<'EOF'
<summary>

<body>

Closes #<N>
EOF
)"
```

## 4. No Local Rebase (conflict policy)

This workflow does **not** rebase the issue branch onto `main` before merging. GitHub's squash-merge already applies the branch as a single new commit on top of the latest `main`, so a local pre-rebase is redundant — and it is the single most dangerous operation to hand an agent (it rewrites history and forces a force-push). It was deliberately removed.

> If strictly linear history ever becomes a requirement (e.g. the project grows to a team that bisects `main`), a pre-rebase step can be reintroduced here — paired with a hard `git push --force-with-lease` rule (never bare `--force`) and explicit rebase-abort handling. For a small repo this cost is not worth paying.

Conflict policy: mergeability is checked against GitHub **after** the PR exists (in step 6), not via a local rebase. If `main` has moved and the PR conflicts, **stop and hand it to the user** — the agent never resolves conflicts autonomously. Concrete handling is in step 6.

## 5. Push And Draft PR

Push the branch:

```bash
git push -u origin HEAD
```

Draft a PR with:

- **Title:** Same as or close to the commit summary line.
- **Body:** Concise behavioral summary of what was actually done.
- Include any divergence from the original issue spec, such as descoped work or follow-up issues.
- Include `Closes #<N>`.

Show the draft PR title and body for approval before creating it.

Create only after approval:

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)"
```

Report the PR URL.

## 6. Merge Only If Confirmed

After creating the PR, ask whether to merge now or leave it open. Do not auto-merge.

Before presenting the merge choice, surface two signals so the decision is informed, not blind:

**Mergeability:**

```bash
gh pr view <N> --json mergeable
```

- `MERGEABLE` — proceed.
- `CONFLICTING` — **do not offer to merge.** `main` has moved and the PR conflicts. Report it and hand resolution to the user: they can resolve in GitHub's web editor or via a deliberate local rebase they invoke, then come back. The agent does **not** resolve conflicts autonomously.
- `UNKNOWN` — GitHub is still computing; wait briefly and re-check.

**CI / checks status:**

```bash
gh pr checks <N>
```

- If checks are passing, note it and proceed.
- If checks are failing, **say so explicitly** and require the user to acknowledge before merging anyway.
- If there are no checks configured, note that nothing automated verified this PR — the diff is the only safeguard. Encourage the user to review it.

> AI-authored PRs read as authoritative and can hide subtle logic errors. The merge gate is only as good as the human reading the diff. Do not let "merge now" become reflexive.

If the user confirms:

```bash
gh pr merge --squash
git checkout main
git fetch origin main
```

Before updating local `main`, distinguish two states (see **Main branch safety** below). After a merge, local `main` is normally just **behind** origin by the squash commit you just created — this is expected and safe to fast-forward. A true **divergence** (local `main` holding commits origin lacks) is the dangerous case. Pull only in the safe case:

```bash
git pull --ff-only origin main
git log -1 --format="%H"
```

`--ff-only` is the mechanical backstop: if `main` cannot fast-forward for any reason, the pull refuses rather than creating a merge commit on `main` — even if the classification above was somehow missed or stale.

Report the merge commit hash so the user can revert if needed.

## 7. Sync Acceptance Criteria (Issue + PR)

After merge (or when closing the issue without merge), sync **both** the GitHub issue and the PR body with the step-2 assessment. Do this **before** reporting resolve complete.

### Issue

1. Edit each **Acceptance Criteria** checkbox in the issue body:
   - `- [x]` for criteria assessed **met**
   - `- [ ]` for criteria **not met** or **not verified**
2. Append or update a **## Resolution** section with:
   - PR link and merge commit (if merged)
   - One line per unchecked criterion explaining why the issue still closed (e.g. deferred, not verified, acceptable for ship)
   - Explicit callout if closing with any criteria unchecked

```bash
gh issue edit <N> --body "$(cat <<'EOF'
<full updated issue body with checkboxes and Resolution section>
EOF
)"
```

If the issue auto-closed from `Closes #<N>` in the PR, editing the body still works on closed issues.

### PR

Update the merged PR so its checklist matches what was actually verified:

1. **Acceptance criteria table** — set `Status` to **Met** / **Not verified** / **Descoped** per criterion (mirror the issue assessment).
2. **Test plan checkboxes** — `- [x]` for steps completed (merge/deploy, prod smoke, manual path, etc.); leave optional or unrun steps unchecked.

```bash
gh pr edit <pr-number> --body "$(cat <<'EOF'
<full updated PR body>
EOF
)"
```

The issue is the canonical record; the PR is the ship-time audit trail — both should agree on what was met vs deferred.

## 8. Clean Up After Merge

**Never run `git reset` on `main` to discard commits.** This applies to `--hard`, `--soft`, `--mixed`, or any reset intended to drop local commits. Losing local commits silently is never acceptable — even if they appear redundant with what just merged.

After `git fetch origin main`, classify the state with these two commands:

```bash
git log --oneline origin/main..main    # commits LOCAL main has that origin lacks
git log --oneline main..origin/main    # commits ORIGIN has that local main lacks
```

Read them like this:

- **Behind (safe, normal after a merge):** the first command is **empty**, the second shows commits (typically the squash commit just merged). Local `main` simply needs to catch up. `git pull --ff-only origin main` will fast-forward cleanly. **Proceed.**
- **Up to date:** both empty. Nothing to pull. **Proceed.**
- **Diverged (dangerous — STOP):** the **first command shows any commits**. This means local `main` holds commits that are not on origin — usually a sign something was committed directly to local `main` or its history was rewritten. A plain pull cannot fast-forward this.

**Stop and do not proceed** if:

- `git log --oneline origin/main..main` shows **any** commits (local `main` has unpushed/divergent commits), or
- `git pull --ff-only origin main` refuses, fails, or leaves `main` and `origin/main` out of sync. A refused pull is a stop-and-report event — never retry it without `--ff-only` and never "fix" it with a merge, rebase, or reset.

> The danger signal is specifically `origin/main..main` (local-ahead), **not** `main..origin/main` (local-behind). Being behind is the normal, safe state after every merge — do not treat it as divergence, or the skill will false-alarm on every single resolve and the warning becomes noise.

When stopped:

1. Explain clearly that local `main` has commits not on `origin/main` (or that pull failed).
2. Show both sides using the log commands above — what is on local that is not on origin, and vice versa.
3. Offer options only; **do not resolve divergence autonomously**:
   - Rebase local `main` onto `origin/main`
   - Merge `origin/main` into local `main`
   - User decides / handles manually
4. Wait for the user's choice before running any further git commands on `main`.

Only proceed with cleanup when local `main` is successfully aligned with `origin/main` (no divergence, pull clean).

### Verify the merge before deleting (hard rule)

A squash-merge creates a **new** commit on `main` that is not a descendant of the issue branch's commits. Because of this, `git branch -d` (safe delete) will **refuse** to delete the branch — git cannot see it as "merged" — and will fail on every successful squash-merge resolve.

The correct delete is `git branch -D` (force delete), but **only after confirming the PR actually merged**. The merge-state check is what makes the force delete provably non-destructive: if the PR merged, the work is on `main` via the squash commit, so the branch is genuinely redundant.

Confirm the merge first:

```bash
gh pr view <N> --json state,mergedAt
```

Proceed only if `state` is `MERGED` and `mergedAt` is non-null. If the PR did not merge (e.g. left open in step 6, or merge failed), **do not delete the branch** — stop and report.

Once merge is confirmed, delete the local issue branch:

```bash
git branch -D issue-<N>/<slug>
```

> Do not "simplify" this back to `git branch -d`. After a squash-merge it will always fail. `-D` is correct and safe **only** because the `gh pr view` check above proved the work is on `main`.

If the remote branch was not auto-deleted by GitHub, delete it:

```bash
git push origin --delete issue-<N>/<slug>
```

Report what was cleaned up.
