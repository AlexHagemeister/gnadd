# GNADD

Git-Native Agent-Driven Development — a workflow where GitHub Issues, branches, PRs, and git history are the sole system of record. Seven operational [Agent Skills](https://agentskills.io) drive the loop — from issue capture through gated resolution, plus a no-issue quickfix path and an autonomous YOLO mode — backed by a tested, deterministic script (`gnadd.sh`, bundled inside the skills) that enforces the git invariants in code. Help and audit skills orient and align agents on the workflow.

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

Use the same scope (`-g` or project) you used at install — updating the wrong scope leaves the active copies stale without warning. Note: `skills update` only tracks GitHub-source installs; if you installed from a local checkout (e.g. `scripts/sync.sh` while developing), re-run that instead. Flag details and interactive options are in the [skills CLI docs](https://github.com/vercel-labs/skills) — no need to track them here.

**Versioning:** releases follow [semver](https://semver.org/) and are listed on the [releases page](https://github.com/AlexHagemeister/gnadd/releases) with a [changelog](CHANGELOG.md). Pre-1.0, minor versions may change skill names or behavior — read the release notes before updating. To be notified of releases: **Watch → Custom → Releases** on the repo.

**Distribution channel:** `main` is the channel. The skills CLI installs from the default branch and cannot pin a tag, so every install and update pulls the latest `main` — which this workflow keeps always-releasable (nothing lands without a PR, green CI, and review). Tagged releases mark the tested snapshots and document what changed between updates. Consequently `gnadd version` reports the *release baseline*: the installed copy is that release plus any changes merged since, and says so.

| Skill | Invocation |
|---|---|
| `help-gnadd` | Auto when workflow-shaped; `/help-gnadd` |
| `audit-gnadd` | `/audit-gnadd` |
| `prime-gnadd` | `/prime-gnadd` |
| `new-issue-gnadd` | `/new-issue-gnadd` |
| `start-issue-gnadd` | `/start-issue-gnadd <N>` |
| `commit-gnadd` | `/commit-gnadd` |
| `resolve-issue-gnadd` | `/resolve-issue-gnadd` |
| `quickfix-gnadd` | `/quickfix-gnadd` |
| `yolo-gnadd` | `/yolo-gnadd <N or description>` |

## Per-project setup (recommended)

Once per repo, turn on the server-side rails:

```bash
bash <path-to-installed-prime-skill>/gnadd.sh init        # add --ci for a test workflow stub
```

This makes GitHub itself enforce the workflow's core invariants: squash-only merges (with the PR body as the commit message), auto-deleted merged branches, and a ruleset on `main` requiring PRs and blocking force pushes. See GNADD.md Part 4 ("The enforcement layers").

## Repo layout

| Path | Role |
|---|---|
| `bin/gnadd` | Canonical mechanics script — the single source of truth |
| `skills/<name>/SKILL.md` | The skills: judgment + conversation around the script |
| `skills/<name>/gnadd.sh` | Generated copies of `bin/gnadd` — never edit these |
| `scripts/build.sh` | Copies `bin/gnadd` into the operational skills |
| `test/run.sh` | Test suite (bash + git only; `gh` is stubbed) |
| `scripts/release.sh` | Stamps version, repins guide URLs to the release tag |
| `GNADD.md` | Canonical workflow guide and design rationale |

## Authoring (repo maintainers)

- Skill behavior: edit `skills/<name>/SKILL.md`.
- Git mechanics: edit `bin/gnadd`, then `./scripts/build.sh` (test/run.sh fails if copies drift).
- Always: `bash test/run.sh` before committing — every safety guarantee is a test.

Refresh your local install after changes:

```bash
./scripts/sync.sh
```

Installs to Cursor and Claude Code by default. Override the agent list (space-separated, [supported agents](https://github.com/vercel-labs/skills#supported-agents)): `AGENTS="cursor" ./scripts/sync.sh`.

Releases: `./scripts/release.sh vX.Y.Z`, then follow its printed steps (it stamps the version, repins the canonical-guide URLs in `help-gnadd`/`audit-gnadd` to the tag, and re-runs the tests). After pushing to GitHub, consumers refresh with `npx skills update -g -y` (or project scope if that's how you installed).
