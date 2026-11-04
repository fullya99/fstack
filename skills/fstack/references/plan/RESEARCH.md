# Research, when and how

## When to search, when not to

The external surface decides. A pure internal refactor, a fix in code we own, a rename: no
research, and the plan says so plainly rather than filling up with off-topic notes.

An external lib, a provider's API, a recent version, a behavior that may have moved, a technology
choice to settle: research.

## Order of sources

1. The official documentation of the tool or service, at the targeted version. It is the source of
   truth and it prevents invented APIs.
2. The platform's native web search, for dated facts, field reports and pages to read in full.
3. MCP search connectors, if the session has any. They are sometimes deferred at startup: load them
   with `ToolSearch` before concluding they are missing, and find their real name through that
   search, never hardcode it.

## Degradation

No connector is a prerequisite. When absent, or invisible to the subagent that does not inherit the
parent's tools, native search does the job, less well, and the subagent notes it in its report. The
plan writes "native search" in that case.

## Splitting into axes

One subagent per axis, all launched in the same turn. Three to five axes are enough, rarely more.
Typical axes:

- the targeted tool or lib and its current version
- the state of the art of the practice
- pitfalls and field reports
- the regulatory or platform constraint, when there is one

Never give two axes to the same subagent. A researcher who must cover two subjects covers one well
and the other badly, and nothing says which.

## A researcher's output contract

Raw notes, not a formatted report. Every claim comes with its link and date. A source older than
six months is marked as possibly stale. What is disputed between two sources is flagged as such
rather than settled in the operator's place. Nothing found on a point is written "not found", never
a guess dressed up as fact, and never bare: it carries the queries run, the sources consulted and
the date, otherwise nobody knows whether the point was searched.

Two traps recur. A procedure reconstructed from two general pages misses the page that names both
technologies together, hence a first query that cites both, in the vendor's terms. And an extracted
page is judged by its status code before its content: behind a 401 or a login page, extraction
still returns text, and a model draws an invented procedure from it.

No introduction, no conclusion. A subagent that synthesizes before returning loses the traceability
these notes exist to provide.

## What goes into the plan

Only what shaped a decision. A research note the plan does not use is not copied into it, it stays
in the subagent's notes. A plan cluttered with unused research is harder to review than one that
goes straight to the decisions it produced.
