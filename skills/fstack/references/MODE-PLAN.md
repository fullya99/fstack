# Mode PLAN

> **The contract**: a plan anchored in the real terrain, sourced on recent material, validated by
> the operator before being written, put through a counter-review, followed by an execution prompt
> that drives a team of agents. This mode plans, it does not execute.

Before writing, load the `style-redaction` skill. If it is missing, apply the language declared by
the project's `contexte:convention` block, a direct tone, no phrasing that smells of generated
text.

## When this mode applies

| Situation | What you do |
|---|---|
| Idea to turn into a plan, subject with a real surface (code, infra, docs, migration, investigation) | The six phases, in order |
| Task of two steps and three files | You say so, propose adding them to `TODOS.md`, no plan |
| Simple change, question answered by reading a file | You answer directly |
| End of session, tidying the repo | Mode DEBRIEF, not this one |

If the request fits no row, say so rather than forcing a plan.

## The six phases

### Phase 0. Triage

Two minutes, without reading code.

- **The type**: feature, fix, migration, overhaul, infrastructure, documentation, investigation,
  non-code. Two possible types, take the more constraining. Sections and pitfalls in
  `references/plan/PLAN-TYPES.md`.
- **The environment**: git repo or not, stack from the manifests (`package.json`,
  `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`, `*.csproj`...), test, lint and build
  commands actually present, context convention in place (`CLAUDE.md`, `AGENTS.md`, `CODEMAP.md`,
  `TODOS.md`, `docs/`). Blank terrain, you note it and move on.
- **The external surface**: lib, API, provider, behavior that may have moved. With no surface,
  phase 1 is skipped and the plan says so in black and white.

**End of phase**: you state the type, the stack and the external surface in three lines.

### Phase 1. Research

Only if the external surface is real. A fan of `fstack:researcher` subagents, one axis each, all
launched in the same turn, three to five axes. Never one agent searching everything.

Each claim comes back with its link and date. Past six months, it is flagged as possibly stale. An
agent that finds nothing writes "not found", never a guess.

**Source order.** Official documentation first, then native web search, then MCP search connectors
if the session has any. An MCP server is never a prerequisite. A subagent does not always see the
parent's tools: without them, it uses native search. The agent writes in its report which tool it
actually used, and the plan notes "native search" when that is the case. Full cascade and output
contract in `references/plan/RESEARCH.md`.

**End of phase**: each axis returned facts with link and date, or "not found".

### Phase 2. Exploration

`fstack:explorer` agents on the zones that triage and research pointed to. They return paths,
symbols and facts, not impressions. You cross-check by command (`ls`, `grep -n`, `wc -l`) every
path and number that will enter the plan. Without subagents, you explore yourself. Blank terrain,
you read only the language's conventions.

**End of phase**: every cited path and symbol was seen in the real repo.

### Phase 3. Questions

The phase the operator lives through, it stays light.

- Five questions at most, in one pass, each with its default answer stated. "ok for all" is
  enough.
- Plain language, no implementation jargon.
- A question is asked only if the answer changes the plan. Otherwise you decide and write the
  assumption.
- A decision that changes the plan but that nobody can make now, because information is missing,
  is neither invented nor silently postponed. It is written
  `DECISION NEEDED: <question> | options | what depends on it` at the place in the plan it
  blocks. The counter-review closes it with the operator.
- You propose, the operator decides, you never widen the scope alone.
- You end with five lines of restatement. **Nothing is written before the yes.**

**End of phase**: an explicit yes, or corrections that you integrate and resubmit.

### Phase 4. The plan

**Location.** The folder declared by the `contexte:convention` block (key `plans:` if present),
otherwise `plans/<slug>.md` at the project root, slug in lowercase and hyphens. Never outside the
project. On a small task, propose adding the steps to the existing tracker.

Write from `templates/plan.md`. Skeleton, task format and prohibitions ("TBD", invented path,
step without verification) in `references/plan/PLAN.md`, type-specific sections in
`references/plan/PLAN-TYPES.md`.

**The `Deviation log` section is mandatory.** Every prerequisite gate that was forced has its entry with its
reason. Nothing forced, the section says "no deviation" and stays in the plan.

**The new gate, verify before writing.** Any splitting assumption like "these batches share no
file" is proven by the real file list of each batch, then by the intersection:

```bash
comm -12 <(sort batch-a.txt) <(sort batch-b.txt)
```

An empty output allows parallel work. A non-empty output puts the two batches in series, or those
files move into a batch of their own. The claim "no common file" enters the plan only with this
check done.

**One profile per batch.** Each batch of the split carries a `fstack:<profile>` profile among
`explorer`, `tester`, `runner`, `builder`, `researcher`, `expert`, `reviewer`. You take the lowest
that meets the batch's done criterion and write the reason in one line if you go up. Rules for
grading, for recovery after failure and for the brief are in `references/DELEGATION.md`. At most
five agents in parallel, never two on the same files. Without subagents on the platform, the split
becomes a series of verified steps, one batch at a time.

**The counter-review, before returning the plan.** A `fstack:reviewer` in a fresh context rereads
the plan and challenges its assumptions. Without subagents, you do the pass yourself, rereading
the plan as a stranger. Method:

1. Extract the challengeable assumptions: lib versions and flags, API or service behavior,
   compatibilities, resource and cost estimates, points marked "to confirm", decisions like "X
   does not support Y". Note the source section of each.
2. Verify them by research, never from memory: primary source (official doc, issue, changelog), in
   parallel, with the phase 1 degradation. Assumptions about the repo are verified by command.
3. Rank each finding:

| Level | Criterion |
|---|---|
| Blocker | False assumption that breaks the plan as is or violates an irreversible constraint |
| Major | Unverified or partly false, redesign or bug likely |
| Moderate | Simpler alternative or precision to add, does not block |
| Validated | Confirmed by a primary source |

A finding fits in one entry: identifier `F-01`, severity, what is false, source with link,
concrete action. No finding of taste, no marginal issue to pad the list, no "Validated" without a
source.

4. Annotate the plan: a `Counter-review` section with the table of unvalidated findings. Each
   finding is **integrated** (the plan section changes, you cite it) or **rejected** (reason
   written). A finding without a written decision forbids returning the plan. The validated ones
   are listed in one line.

**End of phase**: the plan file exists at the planned location,
`grep -nE 'TBD|TODO|to check|DECISION NEEDED|DÉCISION À PRENDRE'` finds nothing in it, the
counter-review has no Blocker or Major without a written decision, the interfaces close in both
directions (`references/plan/PLAN.md`, section 2), and each batch has its profile.

### Phase 5. The prompt

A single block, never in a project file. It addresses a fresh session, with no residue from the
exploration, which each platform allows in its own way (in Claude Code, a new session or
`/clear`). Order, long context first: the plan to read in full, the locked decisions restated,
what is not touched, the invariants, the team, the steps with their verification gate, the start
last. Tags `<plan>`, `<decisions>`, `<off_limits>`, `<invariants>`, `<team>`, `<steps>`,
`<start>`.

The team reuses the profiles of the split. Anatomy, wording and example in
`references/plan/PROMPT.md`.

**The prompt goes into the brief queue, not the chat.** In Claude Code, you store it with the
"plan prompt" command of the "Debrief marker and restart prompt" section of `SKILL.md`, with the
plan's path. It sits next to the debrief handover without overwriting it, the hook announces it at
the next startup and `/fstack:brief open` plays it. The chat receives only one line: the entry's
name and the instruction "reset the context, then `/fstack:brief open`". The block is shown in
full only if the operator asks, or if the script answers that it stored nothing
(`CLAUDE_PLUGIN_DATA` absent, other platform).

**Platforms with no prompt to paste.** They read the plan itself. The plan's Restart notes section is
then enough to restart, the phase 5 prompt is optional.

**End of phase**: the script answered that it stored the prompt in the brief queue with the entry's
name, or the block is in the chat, and its seven tags are present.

## Several plans in the same session

Each plan goes through its six phases and ends in its own queue entry. The next plan restarts at
phase 0. Research and exploration already done are reused when they cover the subject, the phase 3
questions are asked again for it alone.

- **One plan, one execution session.** A plan's prompt drives only that plan. Never a prompt that
  chains two plans: the execution session would load both and lose the benefit of a fresh context.
- **The order.** The queue plays plans in the order they were queued. A plan that consumes what
  another delivers is queued with `--after <plan>`: while the other waits, it passes its turn. The
  plan writes it in its Current state section, with what it expects from the other.
- **No common file without saying so.** Two plans that touch the same files are queued as a
  dependency, never side by side. The `comm -12` check of phase 4 applies between plans too.
- **The final report** lists the queued entries, in the order they will be played.

## Restart notes, kept by the executor

The plan's Restart notes section is not frozen at writing. The executor updates it at the end of each
batch: current state, next unchecked task, what is validated and not redone, terrain status
command. The step boxes are checked at the same time. The phase 5 prompt asks for it in plain
words in each step.

## Invariants, never negotiable

- ❌ Nothing is written before the operator's yes at the end of phase 3.
- ❌ No path or symbol that was not verified in the real repo.
- ❌ No step without a verification criterion.
- ❌ No claim "these batches share no file" without the real file list.
- ❌ No plan returned with a Blocker or Major finding without a written decision.
- ❌ No MCP tool as a prerequisite, you degrade and say so in the plan.
- ❌ No commit, no push. This mode modifies no project file except the plan. The brief queue
  lives outside the repo.
- ❌ No plan outside the project.

## References, to load as needed

| File | When to read it |
|---|---|
| `references/plan/RESEARCH.md` | Server cascade, degradation, axes, output contract |
| `references/plan/PLAN-TYPES.md` | The eight types, their sections and their pitfall |
| `references/plan/PLAN.md` | Skeleton, task format, prohibitions |
| `references/plan/PROMPT.md` | Prompt anatomy, team, example |
| `references/DELEGATION.md` | Profiles, grading, brief and parallelism rules |
| `templates/plan.md` | Phase 4 template |
