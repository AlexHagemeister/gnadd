## Learned User Preferences

- Prefer copy-based `npx skills` install (`--copy`) over symlinks for published skills — reliability over live sync.
- Keep consumer install docs minimal and set-and-forget; link to the [skills CLI](https://github.com/vercel-labs/skills) for agent names, flags, and scope details.
- Use `gh` for GitHub operations rather than the web portal.
- Superseded (2026-07, "Server-side rails" decision in GNADD.md Part 5): direct commits to `main` for small doc-only changes. All changes route through the loop; if micro-task overhead bites, that triggers the deferred `quick` skill.
- Position shareable repos as agent-agnostic; personally develop with Cursor and Claude Code (`AGENTS="cursor claude-code"` default in `scripts/sync.sh`).
- Solo, single-threaded GNADD usage; one active issue at a time is the normal pattern.
- Ask for critical-path confidence before large implementations; proceed when the user says go/proceed.

## Learned Workspace Facts

- GitHub remote: `AlexHagemeister/gnadd`.
- Seven GNADD skills live under `skills/<name>/SKILL.md`: `help-gnadd`, `audit-gnadd`, `prime-gnadd`, `new-issue-gnadd`, `start-issue-gnadd`, `commit-gnadd`, `resolve-issue-gnadd`.
- GNADD workflow: GitHub Issues, branches, PRs, and git history are the sole system of record.
- `GNADD.md` is the canonical workflow guide; `README.md` covers install; skills are the executable spec.
- Git mechanics are canonical in `bin/gnadd`; `scripts/build.sh` copies it into the operational skills as `gnadd.sh` (never edit the copies); `test/run.sh` is the zero-dependency test suite (gh stubbed at `test/stub/gh`) and fails if copies drift.
- Author local sync: `./scripts/sync.sh` (runs build.sh first); post-push refresh: `npx skills update` with the same scope (`-g` or project) used at install.
- Releases: `./scripts/release.sh vX.Y.Z` stamps the version and repins the canonical-guide URLs in `help-gnadd`/`audit-gnadd` to the tag.
- `.gitignore` excludes `.cursor/`.
- When `GNADD.md` and a skill disagree on mechanics, the skill wins; when a skill and `bin/gnadd` disagree, the script wins.
