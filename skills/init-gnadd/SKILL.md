---
name: init-gnadd
description: >-
  Bootstrap a project onto GNADD using the bundled gnadd script and gh: turn on
  the server-side rails (squash-only merges, PR-required main), write the
  agent-agnostic conventions file (AGENTS.md) that points agents at GNADD and
  carries the preview launch line, land init's own files on main through a
  PR, and report what was set up and what is still the user's to do. Safe to
  rerun. Use when the user wants to set up a
  new repo for GNADD, initialize the workflow, or add the rails and
  conventions to an existing repo.
---

# Init

Set a repo up to run GNADD. Two things come out of it: GitHub enforces the
workflow's invariants itself, and a conventions file tells every agent that
this repo runs GNADD and how to launch a preview. Nothing here creates task
state. Rerunning reports what already holds and changes nothing that matches.

## Auto-Invocation Gate

If this skill was auto-selected from context rather than explicitly invoked
with `/init-gnadd`, stop before running commands. Briefly explain why
bootstrapping appears useful and ask: "Run `/init-gnadd` now?" Proceed only
after confirmation.

## GNADD Invariants

- The rails live on the GitHub server, not in anyone's discipline: squash-only
  merges with the PR body as the commit message, auto-deleted merged branches,
  a ruleset on `main` requiring a PR and blocking force pushes and deletion.
- The conventions file is a pointer, not a copy of the guide or the skills. It
  holds no task state and nothing an agent must keep updated.
- The repo must already exist on GitHub. This skill does not create it.
- For broader workflow guidance, use `help-gnadd`.

## Mechanics

All mechanics run through the bundled script, `gnadd.sh` in this skill's
directory. When it exits with `state=<NAME>`, that is a human decision point:
have the conversation, never work around it. If the script is missing, stop
and tell the user to reinstall the GNADD skills per help-gnadd's Install &
Update guidance.

## 1. Confirm The Remote

```bash
gh repo view --json nameWithOwner --jq .nameWithOwner
```

If this fails, the repo has no GitHub remote gh can see. Stop and say so: the
workflow assumes GitHub exists from minute one. Point at `gh repo create` and
`git remote add origin`, and offer to rerun once the remote exists.

## 2. Turn On The Rails

```bash
bash "<skill-dir>/gnadd.sh" init
```

Add `--ci` when the user wants a minimal GitHub Actions test workflow dropped
in, and `--strict` to remove the admin bypass on the main ruleset (the default
keeps it as a solo escape hatch). Read the output and report each rail as
**changed** or **already held**: `merge_policy=squash-only`,
`ruleset=created` or `ruleset=exists`, and `ci=created` or `ci=exists` if
requested. The last line, `uncommitted=`, names init's own files that are not
yet on main (step 5 lands them). Handle the failures:

- **`merge_policy=failed`:** an older gh; relay the script's note about
  setting it in repo Settings.
- **`ruleset=failed`:** the rails on `main` are not up. `ruleset_error=`
  carries gh's first error line. When it says "Upgrade to GitHub Pro or make
  this repository public", rulesets are unavailable on a private free-plan
  repo: tell the user the choice is theirs (make the repo public, upgrade, or
  run without the server-side guard on `main`), and that the rest of the
  workflow still works, with force pushes and direct pushes to `main` left to
  discipline. For any other cause, show the line and relay the script's note
  about adding the ruleset in repo Settings > Rules.
- **`state=GH_UNAUTHENTICATED`** or **`state=NO_REPO`:** stop the flow;
  resolve with the user.

## 3. Find The Preview Launch Line

The build/try/feedback loop needs one project fact: how to start a preview a
person can try. Look for an obvious answer before asking:

```bash
test -f package.json && grep -E '"(dev|start|preview)"' package.json
test -f Makefile && grep -E '^(dev|run|serve|preview):' Makefile
ls .claude/launch.json 2>/dev/null
test -f README.md && grep -nE 'localhost:[0-9]+|127\.0\.0\.1|(npm|pnpm|yarn|bun) (run )?(dev|start|serve|preview)|make (run|dev|serve)|python .*(-m http\.server|manage\.py runserver|app\.py)|cargo run|go run' README.md
```

- **Obvious candidate** (a `dev` script, a `run` target, a README line
  naming a localhost URL or a serve command): state it as the proposed line
  and ask the user to confirm or correct it.
- **Nothing obvious:** ask one question. "How do you start a dev preview of
  this app? A command, or a URL." Accept "there is none yet" as an answer.

Never guess silently. The line the user confirms is what every later session
will run.

## 4. Write The Conventions File

```bash
bash "<skill-dir>/gnadd.sh" conventions --preview "<confirmed command or URL>"
```

Omit `--preview` when the user has no preview yet; the script writes a
placeholder they can fill in later. The script creates `AGENTS.md` if absent,
appends a marked GNADD block to an existing one without touching its other
content, and on rerun changes only a preview line that differs. Report the
result from its output: `conventions=created`, `updated`, or `unchanged`.

If the project's agent reads a differently named file (`CLAUDE.md`), tell the
user to import `AGENTS.md` from it rather than duplicating the block.

## 5. Land Init's Own Files

Init's files (`AGENTS.md`, and the CI workflow when `--ci` ran) are written
to the working tree, not committed. Left there they block every quickfix
(`.github/` is a protected path and the leftover makes the tree dirty), so
the script lands them itself, through the rails, with no issue: a
`quickfix/gnadd-init` branch carrying them, one commit, a push, and a PR.

```bash
bash "<skill-dir>/gnadd.sh" init land
```

Local `main` is never touched. Handle the outcomes:

- **`pr_url=...`:** the PR exists. Merge it through the CI gate, then sync
  and clean up:

  ```bash
  gh pr checks <PR> --watch
  bash "<skill-dir>/gnadd.sh" ship merge <PR>
  bash "<skill-dir>/gnadd.sh" sync-main
  bash "<skill-dir>/gnadd.sh" cleanup <PR> quickfix/gnadd-init
  ```

  When `--ci` ran, the workflow this PR adds runs on it and is the gate.
  When it did not and the repo has no workflow, `ship merge` halts
  `state=NO_CHECKS`; say so, and with the user's go-ahead re-run it with
  `--no-check`. `state=CHECKS_PENDING` means wait and re-run.
  `state=CHECK_FAILED` is a stop: the project's test command failed on a
  clean checkout, and the user decides.
- **`landed=none`:** init's files are already on main (a rerun). Skip on.
- **`state=INIT_LAND_FOREIGN_FILES`:** the tree holds changes that are not
  init's (listed). They take their own route (an issue, or a quickfix); ask
  the user how to handle them, then re-run `init land`.
- **`state=DIVERGED_MAIN`:** point at `gnadd.sh doctor` before anything else.
- **`state=QF_BRANCH_EXISTS`:** an earlier landing was not cleaned up; finish
  it (merge, sync, cleanup) and re-run.
- **`state=PR_CREATE_FAILED`:** the commit and push landed but the PR did
  not. Run `gh pr create` by hand, then continue from `ship merge`.

## 6. Report

State plainly, in two lists:

- **Set up now:** each rail (changed or already held), the conventions file
  and its preview line, and the landing PR (merged, or its number and what
  still gates it).
- **Still yours:** any file init left uncommitted (from the last
  `uncommitted=` line; say "none" when it is none), CI if it was not
  requested, `VISION.md` (offer to run `/vision-gnadd` next, and do not run
  it unasked), and the first issues via `/new-issue-gnadd`.

## Closing Guidance

At natural completion, nudge toward `/vision-gnadd` for a project that has no
`VISION.md` yet, or `/new-issue-gnadd` for one that does. On a `state=` halt,
nudge only toward resolving it.
