---
name: yolo-gnadd
description: >-
  Autonomously run the full GNADD loop on one already-decided unit of work:
  an open issue number (issue loop) or a trivial-change description (quickfix
  flow), end-to-end through merged-on-main, synced, and cleaned up, with no
  human intervention unless a real blocker halts it. Includes an independent
  review pass on the PR before merging. Use when the user says yolo, wants an
  issue or quickfix taken all the way to merged without further prompts, or
  delegates a decided piece of work end-to-end.
disable-model-invocation: true
---

# YOLO

Run one decided unit of work through the whole loop — no mid-loop prompts.
The consent being delegated is the *gates*, never the *what*: YOLO only ever
executes an existing open issue or an explicitly described trivial change,
and never chooses its own work. One invocation = one issue or one quickfix.

**What this trades, honestly:** the human's pre-merge diff review is replaced
by (a) the pre-approved spec as the contract, (b) an independent fresh-context
review pass, (c) the CI gate, and (d) post-merge revertability via the squash
commit. The run ends with a report built for skim-and-revert.

## Invocation Is The Consent

This skill must only run when explicitly invoked (`/yolo-gnadd <N>` or
`/yolo-gnadd <description>`). Never auto-invoke it; `disable-model-invocation`
is set, and if it is somehow entered without an explicit invocation, stop and
ask.

## No Loop Knowledge Lives Here

This skill deliberately contains **no branch, commit, PR, or merge mechanics**.
Each phase below is executed by loading the named sibling skill — installed
alongside this one (e.g. `../start-issue-gnadd/SKILL.md` relative to this
skill's directory) — and following it faithfully, with only the specific gates
listed below auto-approved. If a phase skill is missing, stop: tell the user to
reinstall the GNADD skills (`npx skills update -g -y`). Do not reconstruct a
phase from memory — an improvised loop is exactly what this design exists to
prevent, and the trace (below) will show the gap.

## The Receipt

Open the run by resetting the mechanics trace, using the bundled script in
this skill's directory:

```bash
bash "<skill-dir>/gnadd.sh" trace reset
```

Every `gnadd.sh` subcommand any phase runs leaves a line in the trace. The
closing report includes `trace show` output verbatim. **Honesty rule:** before
reporting, compare the trace against the phases actually claimed; if expected
steps are missing (a phase went around the script), say so explicitly in the
report — never present such a run as clean.

## Mode Selection

- **Open issue number** → issue loop (phases 1–6).
- **Trivial-change description** → quickfix flow: load `../quickfix-gnadd/SKILL.md`
  and follow it end-to-end with its PR-approval gate auto-approved (that gate
  already authorizes the merge). Guard refusals and all `state=` halts remain
  hard stops. Then skip to the review phase (4) before its merge step, and
  close with the report (6).
- Anything else (closed issue, ambiguous description, work that needs a spec)
  → stop; route to `/new-issue-gnadd`. YOLO never invents scope.

## Issue Loop

**Phase 1 — Start.** Load and follow `../start-issue-gnadd/SKILL.md`.
Auto-approved gate: plan approval (adopt the proposed plan as-is). All of its
step-2 conversations (dirty tree, diverged main, branch switches) remain hard
stops — those need a human.

**Phase 2 — Implement.** Do the work per that plan and the issue's acceptance
criteria. If evidence emerges that the spec is wrong or the scope moved, stop
and escalate — do not improvise scope autonomously.

**Phase 3 — Commit.** Load and follow `../commit-gnadd/SKILL.md`.
Auto-approved gate: staging confirmation (stage what the plan produced;
flagged-file warnings — credentials, logs, scratch files — remain hard stops).

**Phase 4 — Independent review.** After the PR exists (phase 5 creates it —
run this phase against the diff first): give a **fresh-context reviewer** only
the issue spec and the diff (`git diff origin/main...HEAD` or `gh pr diff`),
never this session's reasoning. Use a subagent where the platform supports
one; otherwise perform a deliberate self-review pass restricted to spec +
diff, and say which mode ran. Triage findings: worthwhile → fix, re-test,
re-push; dismissed → record why. Every finding and its disposition goes in
the PR body under **## Autonomous review**.

**Phase 5 — Resolve.** Load and follow `../resolve-issue-gnadd/SKILL.md`.
Auto-approved gates: PR-draft approval and the merge confirmation — **except**:

- If the diff touches `bin/`, `scripts/`, `.github/`, or any `gnadd.sh` copy,
  stop at the merge gate and hand the merge to the human. Autonomy must not
  self-modify its own rails; everything through PR + review still runs.
- Failing CI, `CONFLICTING`, and every other `state=` halt: hard stop, as
  that skill already specifies.

**Phase 6 — Report.** After merge + record sync + cleanup, report:

- Merged PR URL and merge-commit hash (`git revert <hash>` = whole-change undo)
- Review summary: findings, dispositions, and which review mode ran
- The loop trace (`trace show`), with any gaps called out per the honesty rule

## Self-Repair Budget

CI failures and worthwhile review findings get at most **2** fix → re-verify →
re-push rounds across the whole run. After that, escalate with: what failed,
what was tried each round, and current branch/PR state. Unbounded retry loops
are how autonomous runs drift; the budget is the leash.

## Escalation

A halt is the system working. When escalating, leave everything in place (the
branch and PR are the recoverable state), summarize precisely, and hand back
to the human. Never work around a `state=` halt, never resolve conflicts
autonomously, never `--no-check`, and never relax the guard or the protected
paths — those decisions belong to the human in every mode, YOLO included.
