# Changelog

All notable changes to GNADD are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/). Pre-1.0, minor versions may
change skill names, script subcommands, or workflow behavior.

## [Unreleased]

Nothing yet.

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

[Unreleased]: https://github.com/AlexHagemeister/gnadd/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/AlexHagemeister/gnadd/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/AlexHagemeister/gnadd/releases/tag/v0.3.0
