# Changelog

All notable changes to GNADD are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/). Pre-1.0, minor versions may
change skill names, script subcommands, or workflow behavior.

## [Unreleased]

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

[Unreleased]: https://github.com/AlexHagemeister/gnadd/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/AlexHagemeister/gnadd/releases/tag/v0.3.0
