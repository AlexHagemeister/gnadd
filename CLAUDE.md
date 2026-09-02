# CLAUDE.md: working in the GNADD repo

This is the source repo of GNADD, Alex's published agent-driven development workflow. `GNADD.md` is the canonical guide, the skills under `skills/` are the executable spec, and `bin/gnadd` is the tested script that carries every git mechanic. Repo facts and the authority chain (guide < skill < script) live in AGENTS.md, imported below. This file holds how Alex wants agents to work here, plus the vault connector.

@AGENTS.md

## The repo runs on its own loop

Dogfood it. Start every session with `/prime-gnadd`. Every change lands through an issue, a branch, and a PR that Alex reads before merge, or through `/quickfix-gnadd` for a trivial one. No direct commits to `main`, no markdown task or progress files, no design doc the agent is expected to keep current. Edit `bin/gnadd`, run `scripts/build.sh`, and let `test/run.sh` prove the per-skill copies match. When the guide and a skill disagree on a mechanic, fix the guide.

## How Alex works with agents

Distilled from his vault (the connector below has the full pages). These are current practice, not fixed canon.

1. Align, then act, then audit. Confirm the task before doing it, do one unit of work, and give him a chance to react before the next.
2. Come back with answers, not questions. Read the file, run the test, check the repo, then ask only what the record cannot answer. At real ambiguity or a known bad state, halt and ask rather than improvise.
3. Smallest possible diff, and nothing lives twice. A rule or fact has one home and thin pointers elsewhere. Before adding a sentence, check whether a script, a field, or a file boundary could hold it instead. Mechanics go in tested code, judgment stays in prose.
4. Build on observed friction, not speculation. Unbuilt skills and mechanisms stay unbuilt until a named trigger fires (see the deferred list in `GNADD.md` Part 5). Roughly three repeats of the same friction earn a change. One does not.
5. A shipped decision is a hypothesis. Record the why and the conditions for revisiting it in the PR body, and expect it to be evaluated.
6. Specs say what and why, never how. Acceptance criteria must be observable without reading the implementation.
7. Root-cause instead of patching the symptom. Investigate before fixing, and say so when the investigation overturns the bug report's framing.
8. Report observation and inference separately, in structure and word choice. Absence from the record is absence of record, never a claim. Quote him verbatim or do not call it a quote.
9. Prose style, for any text you write here (docs, PR bodies, commit messages, skill wording): no em dashes, no semicolons joining clauses, short plain sentences, colons and parentheses are fine. Existing text keeps its punctuation until a change touches that line.

## The exocortex connector

Alex keeps a knowledge vault (the exocortex) that agents can reach through an MCP connector when it is present in the session. Its tools are `query_wiki` (status-weighted search across the vault), `get_page` (read one page by repo-relative path, with a section or frontmatter slice), and `capture_to_inbox` (the only write path: drops a note into the vault's inbox for its pipeline to file). The mirror it reads lags the vault by up to an hour. If the connector is absent, skip this section. Nothing in the loop depends on it.

What in the vault bears on work here, and when to fetch it:

- `wiki/craft/software-design-practice.md`: the 21 practices the list above is distilled from, each with its reasoning. Fetch before any design or workflow change, not for routine issue work.
- `wiki/craft/idea-to-first-version.md`: Alex's position on specs, PRDs, and plan mode, the VISION.md shape, and milestones as phases. Fetch before touching the startup sequence, the thin-README rule, or anything about phases or milestones.
- `wiki/projects/gnadd.md`: the vault's own record of this project, including proposals discussed with Alex but not yet filed as issues. Fetch when a session starts on a design question, to see what has already been decided or floated.
- `wiki/craft/dev-stack.md`: his tooling defaults. Fetch only if the work reaches outside this repo's shell-and-gh world.
- `query_wiki` for anything else: a past ruling, a term he uses, a person or project a task mentions.

Writing back: the GitHub record (issues, PRs, history) remains the sole system of record for this repo. The vault holds what generalizes beyond it. When a session produces a ruling about how Alex works, a preference change, or a design position that no issue or PR body will carry, capture it with `capture_to_inbox`: his exact words as marked quotes with a speaker, your own conclusions in a separate section marked as yours, inference marked as inference. Never describe a capture as an edit to the vault. Tell him when you have captured something, so he can veto it on the spot.
