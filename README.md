# GNADD

Git-Native Agent-Driven Development — a workflow where GitHub Issues, branches, PRs, and git history are the sole system of record. Five [Agent Skills](https://agentskills.io) handle the git mechanics.

Works with any agent the [skills CLI](https://github.com/vercel-labs/skills) supports (Cursor, Claude Code, Codex, and others).

**Full guide:** [GNADD.md](GNADD.md)

## Install

Requires [Node.js](https://nodejs.org/) (for `npx`) and an agent with shell access.

**Global install (recommended)** — skills available in every repo:

```bash
npx skills add AlexHagemeister/gnadd -g -a <agent> --copy -y
```

Replace `<agent>` with your agent (`cursor`, `claude-code`, `codex`, etc.). See the [supported agents list](https://github.com/vercel-labs/skills#supported-agents).

Omit `-g` to install project-local only (skills live in `.agents/skills/` and travel with that repo).

**Update after a new release:**

```bash
npx skills update -g -y    # global
npx skills update -p -y    # project
```

Use the same scope (`-g` or project) you used at install. Flag details and interactive options are in the [skills CLI docs](https://github.com/vercel-labs/skills) — no need to track them here.

| Skill | Invocation |
|---|---|
| `prime` | `/prime` |
| `new-issue` | `/new-issue` |
| `start-issue` | `/start-issue <N>` |
| `commit` | `/commit` |
| `resolve-issue` | `/resolve-issue` |

## Authoring (repo maintainers)

Edit `skills/<name>/SKILL.md`, then refresh your local install:

```bash
./scripts/sync.sh
```

Defaults to `AGENT=cursor`. Override: `AGENT=claude-code ./scripts/sync.sh`.

After pushing to GitHub: `npx skills update -g -y` (or project scope if that's how you installed).
