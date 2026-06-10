# GNADD

Git-Native Agent-Driven Development — a workflow where GitHub Issues, branches, PRs, and git history are the sole system of record. Five Cursor skills handle the git mechanics.

**Full guide:** [GNADD.md](GNADD.md)

## Install skills (Cursor)

Requires [Node.js](https://nodejs.org/) (for `npx`) and Cursor.

```bash
npx skills add AlexHagemeister/gnadd -g -a cursor --copy -y
```

Installs all five skills globally to `~/.cursor/skills/`. Verify in **Cursor Settings → Rules**.

| Skill | Invocation |
|---|---|
| `prime` | `/prime` |
| `new-issue` | `/new-issue` |
| `start-issue` | `/start-issue <N>` |
| `commit` | `/commit` |
| `resolve-issue` | `/resolve-issue` |

## Authoring

Clone this repo, edit skills under `skills/<name>/SKILL.md`, then sync to your local Cursor install:

```bash
./scripts/sync.sh
```

Or manually:

```bash
npx skills add . -g -a cursor --copy -y
```

After pushing to GitHub, refresh from the remote:

```bash
npx skills update -g -y
```
