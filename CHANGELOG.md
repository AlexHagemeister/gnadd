# Changelog

All notable changes to GNADD are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/). Pre-1.0, minor versions may
change skill names, script subcommands, or workflow behavior.

## [Unreleased]

### Added

- prime shows who each open issue is assigned to once any issue is
  assigned, and marks the user's own (#138). It shows each issue's links:
  its open blockers (a closed blocker drops off, as GitHub stops counting
  it), the issues it blocks, its parent, sub-issue progress, and the open PR
  that will close it. It reads only GitHub's links, never issue text, and
  says so when gh is too old to read them. Its next-step suggestion steers to
  issues that are unblocked and free, or names the blocker or assignee.
  new-issue suggests likely blockers, blocked issues, and a parent from the
  open issues, and records the confirmed ones as native links (#139).

## [0.6.0] - 2026-11-18

### Added

- `gnadd round feedback`: records the last round's feedback on the issue the
  moment it is given, as its own append-only comment, with no commit. `round
  post` then cites it ("recorded on round N") and refuses the feedback flags
  as a duplicate; `round list` prints feedback comments in order. The round
  loop records feedback right after the user speaks, resolve-issue records
  the final word before the PR, prime reads the trail on an issue branch, and
  a resume with no feedback on the last round asks instead of assuming (#96).
- `gnadd init land`: commits init's own files (`AGENTS.md`, the CI workflow)
  on a `quickfix/gnadd-init` branch, pushes, and opens the PR, so a fresh
  init ends with a clean tree without a chore issue. Refuses to sweep up any
  other change in the tree (`INIT_LAND_FOREIGN_FILES`) (#98).
- `gnadd question ask|answer|close|list`: a question for a person lives on
  the issue or PR it is about. `ask` posts one marked comment (question,
  options, recommendation) and assigns the item to `--to <login>`. With no
  related item it opens an issue labeled `question`. `answer` records a
  chat answer on the thread, labeled as transcribed. `close --acted` says
  the answer was acted on, closes a question issue with its last open
  question, and removes the assignment only when asking added it. `list`
  reads markers to tell the agent's comments from a person's, so it works
  when agent and human share one account. prime lists open questions, start-issue owns the procedure, and
  yolo posts its stopping question before the run ends (#117).
- The loop works from inside a linked git worktree, one issue per folder.
  When another folder holds `main`, `start` and `quickfix start` branch
  from `origin/main` and `sync-main` parks the folder detached on
  `origin/main` (`parked=true`). Any command that would check out, rename,
  or delete a branch another folder holds halts with
  `state=BRANCH_IN_WORKTREE` naming the folder, including a folder stopped
  mid-rebase or mid-bisect. `state` prints `worktrees=` and one
  `in_flight=` line per issue or quickfix branch, and `doctor` reports
  `finding=WORKTREE_FOLDER_GONE`. A single ordinary checkout behaves as
  before (#115).
- `Worktree setup: <command>` in `AGENTS.md`: `gnadd start` runs it once in
  each fresh linked worktree after checkout, prints its output prefixed
  `  | `, and prints `setup=ran`. A failure halts with
  `state=SETUP_FAILED` and names the `start` to rerun. The primary checkout
  is never set up. `gnadd conventions --setup <command>|none` writes or
  removes the line, and `init-gnadd` offers it (#116).
- `state` prints `idle_folder=<path>` for each other linked worktree folder
  that holds no work (parked, clean, not mid-rebase or mid-bisect), and
  prime names each one with the command that removes it. GNADD removes
  nothing (#124).
- A rescued branch has three scripted exits. `doctor --rescue-main` now
  recommends a `quickfix/<slug>` name and prints them: land it with
  `quickfix ship`, rename it into an issue branch with `start <N> <slug>
  --from <branch>`, or discard it with the new `gnadd drop <branch>`, which
  lists the commits origin lacks and deletes only with `--yes` (#101).
- `gnadd push`: the railed checkpoint push (sets upstream on first push,
  never forces). `ship push` shares it. `state` prints `upstream=` and
  `ahead_of_upstream=` on any branch, and `start <N>` resumes an
  `issue-<N>/*` branch that exists only on origin (#97).
- `gnadd trace note <text>` records a step taken outside the script.
  `yolo-gnadd` notes each gh call it makes, and maps every auto-approved
  gate to its sibling skill's step (#100).
- `ship status` prints `checks=pass|pending|failed|not_started|none`, with
  `not_started` when a workflow file exists and nothing has reported (#95).
- `test/run.sh <name-or-glob>` runs only the matching cases and the summary
  says how many ran. A filter that matches nothing exits 2. The full run
  ends with a `lint` case that runs `scripts/lint.sh`, the one lint
  definition CI now runs too. A missing shellcheck prints a skip line, never
  a pass (#122).
- `test/TESTBED.md`: the procedure for running the whole loop end to end on
  a throwaway repo. `AGENTS.md` points at it (#105).

### Changed

- The guide explains parallel work. Part 2 gains a section to follow for
  running two issues in two worktree folders, with its known limits, and a
  section on one agent orchestrating others: what the script provides and
  the sequence tried once on #115 to #117. The README, the lifecycle, the
  branching model, and the list of caught mistakes point at them (#128).
- The docs and skills no longer make reading the diff the required human
  step before merge. The human owns the merge call and checks that the PR
  does what was meant, by whatever review they choose: the criteria table,
  the test plan, CI, the preview, an agent review they ask for, or the diff.
  The PR body's checkbox now reads "A human checked the PR against the goal
  before merge". The merge confirmation gate itself is unchanged (#127).
- `init` and `conventions` end with an `uncommitted=` line naming init's
  files not yet committed. `ruleset=failed` now prints gh's first error line
  as `ruleset_error=`, and the skill covers the private free-plan case. The
  preview lookup also greps README.md (#98).
- `ship merge` refuses unless every check GitHub reports passed or was
  skipped: `CHECKS_PENDING`, `NO_CHECKS`, or `CHECK_FAILED` naming the
  check. `--no-check` overrides, matching quickfix (#95).
- `round post` pushes the branch before it comments, so every round cites
  a commit GitHub holds. A moved remote halts with `state=PUSH_FAILED`. A
  repo with no remote reports `pushed=false` and still posts (#97).
- `quickfix guard` leaves a newly added `VISION.md` out of the line budget
  and says so (`exempt=VISION.md`). A modified one still counts.
  `quickfix-gnadd` names `GNADD_QF_MAX_FILES` and `GNADD_QF_MAX_LINES`
  beside the check override, and the PR footer states any override used.
  `release.sh` now also repins vision-gnadd's GNADD.md URL (#99).
- Testbed frictions from the v0.5.0 run: `state` prints `dirty_files=` and
  lists them, divergence lists print only when non-empty, and `phase close`
  takes its title from the one open milestone. Seven skills (prime,
  new-issue, start-issue, commit, resolve-issue, audit, help) each gained
  the sentence the testbed agent was missing (#102).
- `test/run.sh` asserts gh calls through `expect_gh_called` and
  `expect_gh_not_called` over a stub log every test creates, so a missing
  log fails instead of passing (#108).
- Every em dash is gone from `bin/gnadd`, `scripts/`, and `test/run.sh`,
  including the heading `release.sh` drafts. `mechanics_have_no_em_dash`
  keeps them out (#91).

### Fixed

- `gnadd question` counts a question marker, an answer, or a closing
  comment only from the repo's owner, members, and collaborators (GitHub's
  `author_association`), so anyone who can comment can no longer plant an
  open question or answer a waiting one. Any trusted author can answer any
  question, and one shared account works as before. An outside comment stays
  on the thread untouched, and `question list` (and a refused `question
  close`) names its item and login as not counted (#131).
- The skills name every halt their own commands can reach, with a next
  step, and no longer contradict the script. Among the fixes: a note on an
  issue starts with `<!-- gnadd:note -->` so it is not read as an answer,
  resolve skips `round feedback` on a non-issue branch, a merged or closed
  PR on the branch stops for the user before a new one is made, a quickfix
  the guard refuses moves to an issue with `start --from`, and init says to
  run from the folder that holds `main`. `help-gnadd` gains a table for
  `doctor`'s output and covers worktrees, rounds, questions, and phases,
  and `start-issue-gnadd` owns the `drop` procedure (#129).
- `cleanup <pr> <branch>` refuses to delete a branch the merged PR did not
  land: `BRANCH_MISMATCH` when the branch is not the PR's head (or GitHub
  returns none), `UNMERGED_COMMITS` when the local tip is past the merged
  head (#94).
- `new-issue-gnadd` ran `phase status` from its own folder, which has no
  script copy, so it failed on every install route. It now runs prime's
  copy, and `skill_self_refs_have_a_copy` catches the pattern (#90).
- A git refusal at the resume checkout, or at the branch delete in
  `cleanup` or `drop`, now halts with `state=CHECKOUT_REFUSED` or
  `state=DELETE_REFUSED` and git's message. It used to exit 1, and cleanup
  printed nothing (#115).

## [0.5.0] - 2026-09-06

### Added

- `init-gnadd`: bootstraps a repo onto GNADD. Confirms the GitHub remote,
  turns on the server-side rails, finds or asks for the preview launch
  command, and writes an agent-agnostic conventions file (`AGENTS.md`)
  through the new `gnadd conventions --preview` subcommand. Idempotent on
  rerun (#70).
- `vision-gnadd`: writes and revises `VISION.md` through an interview. The
  user brain-dumps once, the agent grills only the Core section, the
  possibility space is read back and never pruned, and the file lands
  unstaged for the user to commit. Closes by offering to open the first
  phase (#71).
- `VISION.md` as the project-level intent document (Core, Possibility space,
  Open tensions, with an operating clause). Replaces the thin README's "What
  done looks like" section and the requirements.md phase artifact. Prime
  reports Core when the file exists, new-issue offers to cite the invariant
  an issue serves (#65).
- Phases as GitHub milestones: `gnadd phase status|open|close`. One open at
  a time, no due dates, the closing verdict lands in the description. Prime
  reports the phase, new-issue attaches to it by default, resolve notices
  when it empties and asks (#69).
- Round comments: every checkpoint commit on an issue branch posts one
  append-only comment on the issue with the round number, the commit, what
  changed, and the user's feedback as typed. `gnadd round list` reads them
  back for the resume path (#67).
- The build, try, feedback loop: after plan approval, `start-issue-gnadd`
  runs issue work in rounds. Each round implements a slice, checkpoints it,
  presents a running preview from the project's `Preview launch:` line, and
  asks whether to run another round or resolve. The agent never enters
  resolve on its own (#68).
- Claude Code plugin install: the repo carries `.claude-plugin/plugin.json`
  and a one-entry marketplace, so `claude plugin marketplace add
  AlexHagemeister/gnadd` then `claude plugin install gnadd@gnadd` installs
  all eleven skills as `/gnadd:<skill>`. The skills CLI path is unchanged
  and both channels track `main` (the manifests carry no version so plugin
  updates follow the commit). `test/run.sh` checks the manifests (#79).
- `CLAUDE.md` at the repo root as the Claude Code entry point, importing
  `AGENTS.md` rather than restating it (#58).
- `test/run.sh` checks that every `skills/<name>` directory appears in the
  README skills table and every skill name in the docs has a directory (#77).

### Changed

- README rewritten as a front door for a first-time reader: the problems
  GNADD removes, where it sits among git workflows (GitHub Flow, compacted),
  what a session looks like, the skills table, and a Quickstart with three
  install routes (skills CLI, Claude Code plugin, fork and customize) plus a
  "For humans" prompt and a "For agents" procedure (#73, #83).
- CONTRIBUTING reopened: outside issues and pull requests are welcome, with
  the fork-branch-PR path, the issue-first rule for anything non-trivial,
  and the maintainer's terms. Reverses the closed posture from 0.4.0 (#84).
- `GNADD.md` reconciled with the skills after the sprint: the skills table
  now has one home (the README), and the guide's prose agrees with the
  skills on the startup sequence, the layer table, and the round loop
  (#75, #77).
- `resolve-issue-gnadd` reports the PR's files-changed link at creation and
  again at the merge gate (#66).

## [0.4.0] - 2026-07-22

### Added

- macOS bash 3.2 CI job (`test-macos-bash32`): the full suite now runs with
  gnadd executing under the primary consumer environment, so 3.2-only
  regressions fail CI before merge (#48).
- `yolo-gnadd`: issue loop restructured into a strict 8-phase fail-fast
  ladder: ship as draft PR, CI gate before the independent review, railed
  fix rounds, single finalizing body write, ready-flip at the merge gate
  (#51).
- `help-gnadd`: self-contained Install & Update guidance that travels with
  the install: per-scope update commands, the GitHub-install vs
  local-checkout (`scripts/sync.sh`) split, and the tracks-main / pre-1.0
  caveats. All skills' error paths now give scope-neutral advice (#52).
- `prime-gnadd`: issue and PR listings show authorship; items not authored
  by the authenticated user are annotated and counted as external
  submissions, while all-self snapshots stay unchanged (#53).
- Release flow drafts grouped release notes from squash-merge history when
  the changelog entry is missing. The gate still blocks until a human
  curates the draft (#55).

### Changed

- `gnadd version` now reports `channel=main` and frames the stamped version
  as a release baseline that installed copies may exceed, matching how the
  skills CLI actually distributes from the default branch (#54).
- CONTRIBUTING: closed to external contributions for now; the issue tracker
  is the project's own working backlog. Private security reports remain
  welcome (#47).

### Fixed

- Trace receipts no longer garble when a gnadd run is killed mid-pipe on
  macOS bash 3.2: the stale stdout buffer bash 3.2 retains after a failed
  write is drained before the exit-trap appends the trace line (#40).

## [0.3.0] - 2026-07-20

First tagged release. Versions 0.1.x–0.2.x were development iterations with
no published tags; this entry summarizes the project as first released.

### Added

- `bin/gnadd`: the canonical, tested mechanics script bundled into each
  operational skill: `state`, `start`, `guard-commit`, `ship
  push/status/merge`, `sync-main`, `cleanup`, `doctor` (lossless recovery),
  `test`, `init` (server-side rails: squash-only merges, PR-required main),
  `quickfix start/guard/ship/merge`, and `trace show/reset`.
- Seven operational skills driving the loop: `prime-gnadd`, `new-issue-gnadd`,
  `start-issue-gnadd`, `commit-gnadd`, `resolve-issue-gnadd`,
  `quickfix-gnadd` (no-issue fast path for trivial changes, CI-gated), and
  `yolo-gnadd` (autonomous full-loop on a decided unit, with independent
  review and a trace receipt), plus `help-gnadd` and `audit-gnadd`.
- Zero-dependency test suite (`test/run.sh`, 157 checks, `gh` stubbed) and a
  CI workflow that runs it plus copy-drift and shellcheck gates.
- MIT license, contributing/security policies, and issue templates.

### Changed

- All skills renamed to a uniform `-gnadd` suffix (`gnadd-context` became
  `help-gnadd`; `gnadd-audit` became `audit-gnadd`).
- Author-local sync installs to both Cursor and Claude Code by default.

[Unreleased]: https://github.com/AlexHagemeister/gnadd/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/AlexHagemeister/gnadd/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/AlexHagemeister/gnadd/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/AlexHagemeister/gnadd/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/AlexHagemeister/gnadd/releases/tag/v0.3.0
