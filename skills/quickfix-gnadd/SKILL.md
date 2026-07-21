---
name: quickfix-gnadd
description: >-
  Land a trivial change on main through a PR in one flow using the bundled
  gnadd script and gh: no GitHub issue required — the PR is the record. Branch
  off synced main, commit, push, PR, wait for CI, squash-merge, sync main, and
  clean up. Refuses oversized or mechanics-touching changes with a redirect to
  the full loop. Use when the user wants to quickfix, quickly land, or ship a
  small change — a typo, one-line doc fix, or tiny tweak — without opening an
  issue.
disable-model-invocation: false
---

# Quickfix

Land one small change on `main` through a PR in a single flow. No issue is
created — the PR title and body are the permanent record. This is a fast path
*through* the safety rails (branch, PR, CI gate, squash merge), never a bypass
around them.

## Auto-Invocation Gate

If this skill was auto-selected from context rather than explicitly invoked
with `/quickfix-gnadd`, stop before running git or GitHub commands. Briefly
explain why a quickfix appears to fit and ask: "Run `/quickfix-gnadd` now?"
Proceed only after confirmation.

## GNADD Invariants

- Nothing lands on `main` without a PR — quickfix included.
- The deterministic guard is the contract: small diffs only, and never the
  safety machinery (`bin/`, `scripts/`, `.github/`, any `gnadd.sh` copy).
  A guard refusal is a redirect to the full loop, not an obstacle to work
  around.
- One quickfix = one concern. Batching unrelated fixes is out of scope; each
  gets its own invocation.
- The merge is CI-gated in the script itself: `quickfix merge` refuses unless
  the named check passed.
- For broader workflow guidance, use `help-gnadd`.

## Mechanics

All git mechanics run through the bundled script — `gnadd.sh` in this skill's
directory. When it exits with `state=<NAME>`, that is a human decision point —
have the conversation, never work around it with raw git. If the script is
missing, stop and tell the user to reinstall the GNADD skills
(`npx skills update -g -y`).

## The Stated Gates (tell the user up front)

This flow has exactly two human gates; everything between them runs without
further prompting:

1. **PR approval** — the drafted title/body shown before creation. Approving
   it also authorizes the merge once CI passes; say so when presenting it.
2. **Any `state=` halt** — guard refusals, CI failures, conflicts. These stop
   the flow and get discussed.

## 1. Scope Check (judgment, before any command)

A quickfix is one trivial, self-contained change: a typo, a doc line, a small
config value. If what the user describes has real behavioral surface, needs a
spec, or bundles several concerns, say so and route to `/new-issue-gnadd` —
before touching git. The deterministic guard in step 3 backstops this
judgment; it does not replace it.

## 2. Survey And Branch

```bash
bash "<skill-dir>/gnadd.sh" state
```

Derive `<slug>` from the change: short kebab-case (e.g. `readme-typo`).

- **Clean tree:** create the branch, then make the described change on it:

  ```bash
  bash "<skill-dir>/gnadd.sh" quickfix start <slug>
  ```

- **Dirty tree on `main`** (the change was already made before invoking):
  confirm with the user, then carry it losslessly:

  ```bash
  bash "<skill-dir>/gnadd.sh" quickfix start <slug> --carry
  ```

- **Dirty tree elsewhere, or any `state=` halt** (`DIVERGED_MAIN`,
  `QF_BRANCH_EXISTS`, `FF_REFUSED`): stop and resolve with the user;
  `gnadd.sh doctor` is the recovery path for bad states.

## 3. Verify, Commit, Ship

Make the change if it isn't already in the tree, then run the project's tests:

```bash
bash "<skill-dir>/gnadd.sh" test
```

A failing suite stops the flow — a quickfix must not ship on red. Commit with
a conventional message (no issue reference; there is no issue):

```bash
bash "<skill-dir>/gnadd.sh" guard-commit
git add <files>
git commit -m "<type>: <summary>"
```

Then ship — this runs the deterministic guard and pushes:

```bash
bash "<skill-dir>/gnadd.sh" quickfix ship
```

- **`state=TOO_BIG` or `state=PROTECTED_PATH`:** the change does not qualify.
  Tell the user exactly why, and route to the full loop: `/new-issue-gnadd`,
  then `/start-issue-gnadd` — the work is safe on the current branch and can
  be carried into that conversation.
- **`pr_exists=true`:** an open PR already exists for this branch — resume at
  step 5 with that PR number.

## 4. Draft And Create The PR

Show the draft for approval before creating. Title: the commit summary. Body:
what changed and why, in a few lines — this is the permanent record, so say
why the change was worth making, not just what it touches. Remind the user
that approval authorizes the merge once CI passes.

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
<what and why>

Quickfix: no issue; this PR is the record. Guard-verified small diff;
merges automatically once CI passes.
EOF
)"
```

Capture the PR number from the output URL.

## 5. CI-Gated Merge

Wait for checks, then merge — the script re-verifies the check at merge time:

```bash
gh pr checks <PR> --watch
bash "<skill-dir>/gnadd.sh" quickfix merge <PR>
```

The default gate is the check named `test` (override:
`--check <name>`, or `GNADD_QF_CHECK`). Handle halts:

- **`state=QF_CHECKS_PENDING`:** still running; wait and re-run.
- **`state=QF_CHECK_FAILED`:** stop and discuss — never wave past a red CI.
- **`state=QF_NO_CHECKS` / `state=QF_CHECK_NOT_FOUND`:** nothing automated
  (or nothing recognizable) verified this PR. Surface that to the user; only
  with their explicit go-ahead re-run with `--no-check` or `--check <name>`.
- **`state=PR_CONFLICTING`:** hand resolution to the human, as always.

## 6. Sync And Clean Up

```bash
bash "<skill-dir>/gnadd.sh" sync-main
bash "<skill-dir>/gnadd.sh" cleanup <PR> quickfix/<slug>
```

Report the merge commit hash — the one-command undo (`git revert <hash>`).

## Closing Guidance

At natural completion, report: merged PR URL, merge commit, and that `main`
is synced and the branch cleaned up. No nudge needed — quickfix is usually
invoked mid-flow of something else; hand the session back.

On a guard refusal, nudge only toward `/new-issue-gnadd` for the full loop.
