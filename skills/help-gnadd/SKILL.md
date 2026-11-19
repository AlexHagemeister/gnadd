---
name: help-gnadd
description: >-
  GNADD workflow orientation: GitHub issues as backlog, describe-vs-track file
  rule, and which GNADD skill handles each workflow step. Use when the user asks
  about GNADD, agent-driven development workflow, project context files, tasks.md
  versus issues, startup guidance, how to set up work, or how to install,
  update, or refresh the GNADD skills themselves. Do not use for routine
  coding unless the question is workflow-shaped.
disable-model-invocation: false
---

# GNADD Help

Provide lightweight orientation for Git-Native Agent-Driven Development (GNADD).
Do not run git commands from this skill; route mechanics to the operational
skills.

## Core Model

- GitHub is the system of record: issues capture intent, branches hold work, PRs
  record what shipped, and git history is the audit trail.
- The operational skills drive the loop: `init-gnadd` (once per repo:
  rails and the conventions file), `prime-gnadd`, `new-issue-gnadd`,
  `start-issue-gnadd`, `commit-gnadd`, `resolve-issue-gnadd`,
  `quickfix-gnadd` (the no-issue fast path for trivial changes), and
  `yolo-gnadd` (autonomous full-loop on a decided unit; explicit invocation
  only). Their git mechanics run through a bundled deterministic script
  (`gnadd.sh`), not improvised commands. `vision-gnadd` sits before the
  loop: it interviews the user into `VISION.md` and touches no git.
- Enforcement is layered, lowest layer that can hold each invariant: GitHub
  server rules (`/init-gnadd`: squash-only merges, PR-required main), the
  script (ff-only syncs, divergence halts, gated cleanup), the skills
  (judgment and conversation), and the human (the merge call: checking the PR
  does what was meant, by whatever review they choose).
- Recovery from bad states has a sanctioned path: `gnadd.sh doctor` (bundled
  with `prime-gnadd`) diagnoses and offers lossless fixes (the Doctor Output
  table below reads what it prints), and a rescued branch has scripted exits:
  `/quickfix-gnadd` for a `quickfix/` name, `start --from` to make it an
  issue branch, or `drop` to discard it once the user has seen its commits.
  `start-issue-gnadd` owns the `start --from` and `drop` procedures.
  Never improvise `reset`/`force` recoveries.
- Several issues can be in flight at once, each in its own linked worktree
  folder. Git lets only one folder hold a branch, so the script names the
  folder that holds one, and after a merge a folder that cannot hold `main`
  parks on `origin/main` (`parked=true`), ready for the next issue. A
  `Worktree setup:` line in `AGENTS.md` makes a fresh folder runnable, and
  `start` runs it once per folder. `start-issue-gnadd` and
  `resolve-issue-gnadd` drive folders, and `prime-gnadd` lists every
  folder's work.
- Each build/try/feedback cycle is a round: one comment on the issue,
  posted at each checkpoint (`commit-gnadd`). Feedback the user gives with
  no commit goes on the record at once with `round feedback`
  (`start-issue-gnadd` on resume, `resolve-issue-gnadd` before the PR).
- A question for a person lives on the record, as a marked comment on the
  issue or PR it is about, with the item assigned to them. Only the repo's
  owner, members, and collaborators can ask or answer. `start-issue-gnadd`
  asks, records, and closes questions, and `prime-gnadd` lists them.
- A phase is the project's current stage: one open milestone whose
  description says what it is trying to find out and what ends it. Only
  the user opens or closes one. `vision-gnadd` offers the first,
  `new-issue-gnadd` attaches issues to it, and `resolve-issue-gnadd`
  notices when it empties.
- `init-gnadd` writes its own files (`AGENTS.md`, the CI workflow) and
  lands them on `main` through a PR with `init land`, so nothing is left
  uncommitted to block a quickfix.
- Two receipts are always available: `gnadd.sh trace show` prints every
  script call made from this folder (command, exit status, branch, kept in
  `gnadd-trace.log` inside the folder's git dir: `.git/` in the primary
  checkout, `.git/worktrees/<name>/` in a linked one), and
  `gnadd.sh round list <N>` prints an issue's round trail from any branch,
  not only its own.
- The user's load-bearing job is to describe desired behavior, answer scope
  questions, and check that each PR does what they meant before merge. How
  they check is theirs: the criteria table, CI, the preview, an agent review
  they ask for, or the diff.

## Describe vs Track

Files that describe stable truth are fine. Files that track mutable state should
not exist.

- Keep: `VISION.md` (intent, marked by commitment level), README run instructions, project conventions, stable reference docs.
- Avoid: task lists, progress files, maintained plans, status checklists.
- Test: would the agent need to keep this file up to date? If yes, that state
  belongs in GitHub issues, PRs, branches, or commits instead.

## Skill Router

- Adopt or realign a repo: use `/audit-gnadd`.
- Start a session or inspect state: use `/prime-gnadd`.
- Write or revise `VISION.md` in conversation: use `/vision-gnadd`.
- Capture new work: use `/new-issue-gnadd`.
- Begin or resume issue work: use `/start-issue-gnadd <N>`.
- Save progress on an issue branch: use `/commit-gnadd`.
- Verify, PR, merge, and clean up: use `/resolve-issue-gnadd`.
- Land one trivial fix (typo, doc line) without an issue: use `/quickfix-gnadd`.
- Run a decided issue or quickfix end-to-end without mid-loop gates: use
  `/yolo-gnadd <N or description>` (never auto-invoked).
- Diagnose or recover from a bad git state (diverged main, stashes,
  leftovers): run `gnadd.sh doctor` from the `prime-gnadd` skill's directory.
  Keep a rescued branch's commits with `/start-issue-gnadd` (`start --from`)
  or `/quickfix-gnadd`, or discard them with `drop` as `start-issue-gnadd`
  describes.
- Ask a person a question, or act on an answer: `/start-issue-gnadd` (its
  Questions part). Open questions show in `/prime-gnadd`.
- Set up a repo (server-side rails, the `AGENTS.md` conventions file, and
  landing init's own files): use `/init-gnadd`.
- If a git operation seems needed and no skill covers it, ask for a
  skill-shaped path before improvising raw git commands.
- Update, refresh, or reinstall the skills themselves: see **Install &
  Update** below.

## Doctor Output

`gnadd.sh doctor` prints one `finding=` line per problem, each followed by a
`note:` line naming the fix, and ends with `findings=<N>` (`findings=0`: nothing
known is wrong). A parked folder (detached on `origin/main` while another
folder holds `main`) is reported in a note, not as a finding.

| `finding=` | Meaning | Recipe |
|---|---|---|
| `DETACHED_HEAD` | HEAD is on no branch, so commits made here are easy to lose | `git switch -c rescue/<desc>` |
| `DIVERGED_MAIN` | local `main` has commits origin lacks (listed) | `gnadd.sh doctor --rescue-main quickfix/<slug>` (or `rescue/<desc>`) |
| `DIRTY_TREE_ON_MAIN` | uncommitted changes on `main` | `/start-issue-gnadd` carries them onto an issue branch |
| `STASHES` | stashed work no branch shows (listed) | `git stash branch rescue/<desc>` |
| `WORKTREE_FOLDER_GONE` | a worktree folder was deleted but still holds its branch (`worktree=`, `branch=`) | `git worktree prune`, then `cleanup <pr> <branch>` if its PR merged, otherwise `drop <branch>` |
| `STALE_ISSUE_BRANCH` | an issue or quickfix branch with no commits beyond `main` | `cleanup <pr> <branch>` if its PR merged |

`doctor --rescue-main <name>` moves the stray commits to `<name>`, realigns
`main` to `origin/main` with no reset, leaves you on `<name>`, and prints
`rescued=true` and the branch's exits. It halts, changing nothing, with
`NO_REMOTE` (no origin to realign against), `NO_ORIGIN_MAIN` (origin has no
`main`), `NOT_DIVERGED` (nothing to rescue), `RESCUE_EXISTS` (pick another
name), or `BRANCH_IN_WORKTREE` (another folder holds `main`: run it from the
folder in `worktree=`). `RESCUE_FAILED` and `REALIGN_FAILED` mean a check
after a git step failed: stop, report the message, and let the user inspect.
Every recipe and exit is the user's call. Show the finding and ask first.

## Install & Update

The right refresh command depends on how the skills were installed — answer
update questions with the path that matches, and never assume a scope.

- **Installed from GitHub** (`npx skills add AlexHagemeister/gnadd ...`):
  refresh **in the same scope as the install** — `npx skills update -g -y`
  for a global install, `npx skills update -p -y` for a project-local one.
  Updating the wrong scope leaves the active copies stale without any
  warning.
- **Installed from a local checkout** (`npx skills add . --copy`, e.g. the
  repo's `scripts/sync.sh` while developing): `skills update` cannot track
  local-path installs and skips them silently — re-run `scripts/sync.sh`
  from the checkout instead.
- **Installed as a Claude Code plugin** (`claude plugin install gnadd@gnadd`,
  skills invoked as `/gnadd:<skill>`): refresh the marketplace, then the
  plugin — `claude plugin marketplace update gnadd` followed by
  `claude plugin update gnadd@gnadd` (or the same two steps as `/plugin ...`
  inside a session). `npx skills update` does not see plugin installs.
- **Caveats for any update:** both channels install from the repo's
  default branch, so an update pulls the latest `main`, not the last tagged
  release. Pre-1.0, read the release notes (repo Releases page) before
  updating. `gnadd version` reports the release *baseline* — the installed
  copy may include changes merged after that release. Updated skill
  *content* applies from the next invocation; newly added or renamed
  skills may need an agent restart to appear.

## Deep Reference

For startup guidance, file-hygiene questions, rationale, or edge cases not
covered here, fetch the canonical guide from this pinned URL:

https://raw.githubusercontent.com/AlexHagemeister/gnadd/v0.6.0/GNADD.md

This URL is pinned to a commit, not `main`, so installed skills do not drift with
unreleased guide changes. The pin is rewritten by `scripts/release.sh` at release
time — do not hand-edit it out of band.

## Closing Guidance

Do not nudge after every answer. Match nudge depth to user intent:

- **Purely informational** (describe-vs-track, "which skill does X?", rationale questions): no nudge — the answer stands alone.
- **Routing toward action** ("how do I start?", "where should this state live?"): light nudge — one skill pointer (e.g. `/prime-gnadd`, `/new-issue-gnadd`), no full loop recap.
- **Session bootstrap** ("I'm new here", end-to-end workflow orientation): full nudge toward `/prime-gnadd` to see live repo state.

When nudging, keep it to a sentence with an invitational option. Do not restate the skill router table.
