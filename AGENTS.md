## Learned User Preferences

- Prefer copy-based `npx skills` install (`--copy`) over symlinks for published skills — reliability over live sync.
- Keep consumer install docs minimal and set-and-forget; link to the [skills CLI](https://github.com/vercel-labs/skills) for agent names, flags, and scope details.
- Use `gh` for GitHub operations rather than the web portal.
- Direct commits to `main` are acceptable for small doc-only changes without an issue/PR.
- Position shareable repos as agent-agnostic; personally develop with Cursor (`AGENT=cursor` default in `scripts/sync.sh`).
- Ask for critical-path confidence before large implementations; proceed when the user says go/proceed.

## Learned Workspace Facts

- GitHub remote: `AlexHagemeister/gnadd`.
- Six GNADD skills live under `skills/<name>/SKILL.md`: `gnadd-context`, `prime`, `new-issue`, `start-issue`, `commit`, `resolve-issue`.
- GNADD workflow: GitHub Issues, branches, PRs, and git history are the sole system of record.
- `GNADD.md` is the canonical workflow guide; `README.md` covers install; skills are the executable spec.
- Author local sync: `./scripts/sync.sh`; post-push refresh: `npx skills update` with the same scope (`-g` or project) used at install.
- `.gitignore` excludes `.cursor/`.
- When `GNADD.md` and a skill disagree on mechanics, the skill wins.
