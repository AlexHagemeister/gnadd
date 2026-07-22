---
name: commit-gnadd
description: Make atomic git commits during active development. Use when the user invokes /commit-gnadd or asks to commit, save progress, checkpoint work, or create a git commit; reviews changes, confirms staging, writes a conventional commit message, creates the commit, and reports the result.
disable-model-invocation: false
---

# Commit

Make an atomic git commit during active development. Work with the current branch and integrate with issue branches when applicable.

Do not stage files, amend, push, stash, or clean up without user approval where required below.

## GNADD Invariants

- Commits are visible save points during issue work; keep them atomic and recoverable.
- `commit-gnadd` can trigger from casual phrasing, so it must guard against accidental commits on `main`, `master`, or detached HEAD.
- Do not cross-check issue completion here; drift and acceptance criteria verification belong to `resolve-issue-gnadd`.
- For broader workflow or file-hygiene guidance, use `help-gnadd`.

## 1. Branch Guard (before anything else)

Run the guard from the bundled script (`gnadd.sh` in this skill's directory; if missing, stop and have the user reinstall the GNADD skills per help-gnadd's Install & Update guidance — `npx skills update -y` in the scope used at install, or `scripts/sync.sh` for local-checkout installs):

```bash
bash "<skill-dir>/gnadd.sh" guard-commit
```

- **`state=ON_MAIN`:** stop. This workflow routes work through issue branches; committing to local `main` creates the exact local-ahead divergence the other skills halt on as dangerous. Say so plainly, and offer: switch to or start an issue branch (suggest `/start-issue-gnadd` — it can carry uncommitted changes onto the new branch safely), or — only with the user's explicit confirmation — commit to `main` anyway with raw git.
- **`state=DETACHED_HEAD`:** stop. Commits made in detached HEAD belong to no branch and are easy to lose permanently. Recommend creating a branch first (`git switch -c <name>`); proceed only on explicit confirmation.
- **Success:** the output includes `issue=<N>` when on an issue branch — use it for the message convention below.

This guard matters because `commit-gnadd` is the one skill that can auto-trigger from casual phrasing ("commit this") — it must not be an unguarded path onto `main`.

## 2. Review Changes

```bash
git status --porcelain
git diff HEAD
```

Summarize: staged files, modified unstaged files, untracked files, deleted or renamed files.

Flag files that may not belong in the commit:

- `.env` files or credentials
- `*.log`
- Scratch, temp, or generated files
- Lockfile-only changes
- Files outside the project's typical source, docs, config, or test directories

Do not silently stage everything.

If there are no changes, say so and stop.

## 3. Confirm What To Stage

Present the file list and recommended inclusion set.

- Default assumption: include everything that looks intentional.
- Ask before including flagged files.
- If the user says "all" or "everything," stage all current changes without further questions.
- Respect explicit include/exclude instructions.

Stage only confirmed files.

## 4. Choose Commit Message

Use conventional commits:

```text
<type>: <concise summary>

<optional body>
```

Allowed types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `style`, `perf`.

Choose the type from the actual change, not from filenames alone. Include a body only when the change needs context beyond the summary.

### Issue Branch Integration

If on an issue branch (`issue=<N>` from the guard), include `Re #<N>` in the commit body.

- Use `Re #<N>` for mid-session commits.
- Do not use `Closes #<N>` or `Fixes #<N>`; those are reserved for the final PR.

If not on an issue branch, omit issue references.

## 5. Commit

```bash
git add <confirmed-files>
git commit -m "$(cat <<'EOF'
<commit message>
EOF
)"
```

Report the short hash and summary:

```bash
git log -1 --format="%h %s"
```

## Closing Guidance

Offer a brief next-step nudge only after the commit succeeds and the hash is reported — not when the branch guard stopped the flow or there were no changes.

After reporting the commit, check whether work remains:

```bash
git status --porcelain
```

**Still dirty:** nudge toward continuing implementation or `/commit-gnadd` again — not `/resolve-issue-gnadd`.

**Clean on an issue branch:** nudge toward continuing work; offer `/resolve-issue-gnadd` only as a secondary option ("when you feel done"), never as the primary suggestion.

**Clean, not on an issue branch:** suggest `/start-issue-gnadd` if appropriate.

Keep it to a sentence or two with invitational options. Do not verify acceptance criteria here — that belongs to `resolve-issue-gnadd`.
