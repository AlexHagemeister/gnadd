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

- **Open issue number** → issue loop (phases 1–8).
- **Trivial-change description** → quickfix flow: load `../quickfix-gnadd/SKILL.md`
  and follow it with its PR-approval gate auto-approved (that gate already
  authorizes the merge), creating its PR as a **draft**. Guard refusals and
  all `state=` halts remain hard stops. Before its merge step, run the CI
  gate (phase 5) and independent review (phase 6) against that PR; finalize
  the body (review record only — a quickfix has no acceptance criteria) and
  mark it ready per phase 7, then return to `quickfix-gnadd`'s own CI-gated
  merge step and close with the report (phase 8).
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

**Phase 4 — Ship as draft.** Load and follow `../resolve-issue-gnadd/SKILL.md`
through its verification, test, push, and PR-creation steps, stopping before
its merge gate. Auto-approved gate: PR-draft approval. One overlay: create
the PR as a **draft** — verification is not finished yet, and draft status
makes a premature merge impossible. The creation body is a working summary;
the complete record lands in phase 7's single write. Any `state=` halt is a
hard stop, as that skill specifies.

**Phase 5 — CI gate.** Cheap signals before expensive ones: wait for the
draft PR's checks. Green → phase 6. Red → fix within the self-repair budget:
fix, re-run the project tests, re-push through the railed push this run's
shipping phase already used (it handles an existing PR), and wait for CI
again. Never spend review effort on a head CI has not validated.

**Phase 6 — Independent review.** Runs only against the CI-green head: give
a **fresh-context reviewer** only the spec (the issue body, or in quickfix
mode the stated trivial-change description) and the diff (`gh pr diff`),
never this session's reasoning. Use a subagent where the platform supports
one; otherwise perform a deliberate self-review pass restricted to spec +
diff, and say which mode ran. Triage findings: worthwhile → fix, re-test,
re-push through the same railed push as phase 5, and CI must return green
(same budget); dismissed → record why. Every finding and its disposition
goes into phase 7's body write under **## Autonomous review**.

**Phase 7 — Finalize and merge.** In one write, update the PR body with the
acceptance-criteria table and the **## Autonomous review** record, then mark
the draft ready. Resume `../resolve-issue-gnadd/SKILL.md` at its merge gate
with the merge confirmation auto-approved — **except**:

- If the diff touches `bin/`, `scripts/`, `.github/`, or any `gnadd.sh` copy,
  stop at the merge gate and hand the merge to the human. Autonomy must not
  self-modify its own rails; everything through PR + review still runs.
- CI newly red at this gate: back to phase 5 if self-repair budget remains,
  otherwise hard stop. `CONFLICTING` and every other `state=` halt: hard
  stop, as that skill already specifies.

After merge, complete that skill's record sync and cleanup.

**Phase 8 — Report.** After merge + record sync + cleanup, report:

- Merged PR URL and merge-commit hash (`git revert <hash>` = whole-change undo)
- Review summary: findings, dispositions, and which review mode ran
- The loop trace (`trace show`), with any gaps called out per the honesty rule

## Self-Repair Budget

CI failures (phase 5) and worthwhile review findings (phase 6) share at most
**2** fix → re-verify → re-push rounds across the whole run. After that,
escalate with: what failed, what was tried each round, and current branch/PR
state. Unbounded retry loops are how autonomous runs drift; the budget is the
leash.

## Escalation

A halt is the system working. When escalating, leave everything in place (the
branch and PR are the recoverable state), summarize precisely, and hand back
to the human. Never work around a `state=` halt, never resolve conflicts
autonomously, never `--no-check`, and never relax the guard or the protected
paths — those decisions belong to the human in every mode, YOLO included.
