# Contributing

GNADD is a personal project, maintained primarily for my own use and shared
as-is in case it's useful to you. Setting expectations honestly:

- **Not currently accepting external contributions.** Unsolicited pull
  requests will be closed without review.
- **The issue tracker is this project's own working backlog**, not a support
  channel (yet). This project practices what it preaches: GitHub Issues are
  its entire backlog. You're welcome to read it, but issues opened by others
  may be closed or go unanswered. This may open up later.
- **Security vulnerabilities are always welcome** — please use the private
  reporting channel (see [SECURITY.md](SECURITY.md)).
- **No response-time promises.** I'll get to things when I get to them.

If a change is agreed in an issue, it flows through the GNADD workflow itself
(issue → branch → PR; see [GNADD.md](GNADD.md)): the test suite
(`bash test/run.sh`) must pass, and git mechanics are canonical in
[`bin/gnadd`](bin/gnadd) — never edit the per-skill `gnadd.sh` copies;
`scripts/build.sh` regenerates them.
