# GNADD

Git-Native Agent-Driven Development — a workflow where GitHub Issues, branches, PRs, and git history are the sole system of record. Five Cursor skills handle the git mechanics.

**Full guide:** [GNADD.md](GNADD.md)

## Install skills (Cursor)

Requires [Node.js](https://nodejs.org/) (for `npx`) and Cursor.

### Recommended: global install

GNADD skills are meant to run in **every repo** you work in (`/prime`, `/commit`, etc.), not only inside this repo. Install globally:

```bash
npx skills add AlexHagemeister/gnadd -g -a cursor --copy -y
```

Installs to `~/.cursor/skills/`. Verify in **Cursor Settings → Rules**.

| Skill | Invocation |
|---|---|
| `prime` | `/prime` |
| `new-issue` | `/new-issue` |
| `start-issue` | `/start-issue <N>` |
| `commit` | `/commit` |
| `resolve-issue` | `/resolve-issue` |

### Project install (optional)

If you prefer skills to live only in a specific repo (e.g. a team pins GNADD to one codebase), omit `-g`:

```bash
npx skills add AlexHagemeister/gnadd -a cursor --copy -y
```

Installs to `.agents/skills/` in the current directory. Skills are available when Cursor is working in that project.

### Install scope

The [skills CLI](https://github.com/vercel-labs/skills) supports two scopes:

| Scope | Flag | Installs to | Best for |
|---|---|---|---|
| **Global** | `-g` | `~/.cursor/skills/` | GNADD default — use `/prime` and friends in any repo |
| **Project** | (none) | `.agents/skills/` in cwd | Team pins GNADD to one repo; skills travel with that git clone |

Use the **same scope** for `add` and `update`. If you installed globally, update globally (`-g`). If you installed per-project, run `update` from that repo without `-g`, or use `-p`.

### Common flags

| Flag | Meaning |
|---|---|
| `-g` | Global (user-level) install or update |
| `-p` | Project-level update only |
| `-a cursor` | Target Cursor (also loads `.cursor/skills/` from the install) |
| `--copy` | Copy files instead of symlinking — more reliable across agents |
| `-y` | Skip interactive prompts (scope, confirmations) |

Drop `-y` if you want the CLI to ask where to install or which skills to pick.

## Authoring

Clone this repo, edit skills under `skills/<name>/SKILL.md`, then refresh your install.

### Local changes (not pushed yet)

Re-install from your working tree. Match the scope you chose above (`-g` for global):

```bash
./scripts/sync.sh
```

`sync.sh` runs `npx skills add . -g -a cursor --copy -y` — global by default.

For project scope:

```bash
npx skills add . -a cursor --copy -y
```

### After pushing to GitHub

Pull the latest from the remote source the CLI recorded at install time:

```bash
# global install
npx skills update -g -y

# project install (from the repo where skills were installed)
npx skills update -p -y
```

| Command | When to use |
|---|---|
| `npx skills add . …` | Refresh from **local files** on disk |
| `npx skills update …` | Refresh from **GitHub** (or whatever source was used at install) |

`-g` on `update` means "only touch global installs." Without it, the CLI may prompt or default based on your current directory.
