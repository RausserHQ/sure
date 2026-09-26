# Issue tracker: GitHub

Issues and specs for this repo live in GitHub Issues for `RausserHQ/sure`. Use the `gh` CLI.

## Conventions

- Create, read, list, comment on, label, and close issues with `gh issue`.
- Use the label strings in `docs/agents/triage-labels.md` for triage.
- When a skill says "publish to the issue tracker", create a GitHub issue.
- When a skill says "fetch the relevant ticket", read that GitHub issue and its comments.

## Pull requests as a triage surface

**PRs as a request surface: no.** Set this to `yes` if external PRs should enter the triage queue.

## Wayfinding operations

- A map is one issue labelled `wayfinder:map`; child tickets are GitHub sub-issues.
- If sub-issues are unavailable, list children in the map and put `Part of #<map>` in each child.
- Use `wayfinder:<type>` labels (`research`, `prototype`, `grilling`, `task`).
- Record blockers with native issue dependencies when available; otherwise use a `Blocked by: #<n>` line.
- The next ticket is the first open, unassigned child in map order with no open blockers.
- Claim with `gh issue edit <n> --add-assignee @me`.
- Resolve by commenting with the answer, closing the child, and linking the decision from the map.
