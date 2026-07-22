# Changelog

All notable changes to GNADD are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/). Pre-1.0, minor versions may
change skill names, script subcommands, or workflow behavior.

## [Unreleased]

## [0.4.0] — 2026-07-22

### Added

- macOS bash 3.2 CI job (`test-macos-bash32`): the full suite now runs with
  gnadd executing under the primary consumer environment, so 3.2-only
  regressions fail CI before merge (#48).
- `yolo-gnadd`: issue loop restructured into a strict 8-phase fail-fast
  ladder — ship as draft PR, CI gate before the independent review, railed
  fix rounds, single finalizing body write, ready-flip at the merge gate
  (#51).
- `help-gnadd`: self-contained Install & Update guidance that travels with
  the install — per-scope update commands, the GitHub-install vs
  local-checkout (`scripts/sync.sh`) split, and the tracks-main / pre-1.0
  caveats. All skills' error paths now give scope-neutral advice (#52).
- `prime-gnadd`: issue and PR listings show authorship; items not authored
  by the authenticated user are annotated and counted as external
  submissions, while all-self snapshots stay unchanged (#53).
- Release flow drafts grouped release notes from squash-merge history when
  the changelog entry is missing — the gate still blocks until a human
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

## [0.3.0] — 2026-07-20

First tagged release. Versions 0.1.x–0.2.x were development iterations with
no published tags; this entry summarizes the project as first released.

### Added

- `bin/gnadd`: the canonical, tested mechanics script bundled into each
  operational skill — `state`, `start`, `guard-commit`, `ship
  push/status/merge`, `sync-main`, `cleanup`, `doctor` (lossless recovery),
  `test`, `init` (server-side rails: squash-only merges, PR-required main),
  `quickfix start/guard/ship/merge`, and `trace show/reset`.
- Seven operational skills driving the loop: `prime-gnadd`, `new-issue-gnadd`,
  `start-issue-gnadd`, `commit-gnadd`, `resolve-issue-gnadd`,
  `quickfix-gnadd` (no-issue fast path for trivial changes, CI-gated), and
  `yolo-gnadd` (autonomous full-loop on a decided unit, with independent
  review and a trace receipt) — plus `help-gnadd` and `audit-gnadd`.
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
