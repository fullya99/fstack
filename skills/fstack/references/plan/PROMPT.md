# Anatomy of the execution prompt

## 1. The shape

A single block of text, never written to a project file. It is played in a fresh session, with no
residue from the exploration before it. Each platform has its own way to open one, in Claude Code
a new session or `/clear`.

In Claude Code, the block goes into the brief queue, one entry per plan, and
`/fstack:brief open` plays it after the restart. Elsewhere, it is produced in the chat and the
operator pastes it. In both cases it stands on its own: it assumes neither the debrief handover nor
another plan's prompt.

## 2. Order of the pieces

Anthropic's prompting docs measure up to 30% better quality when long context comes at the top of
the prompt and instructions at the bottom. A model that first reads what it must know, and only
then what it must do, relies on that knowledge when it acts. The other way around, the instruction
arrives before the context that justifies it and the model handles it half empty.

Required order:

1. the plan path, named as the source of truth, to read in full before anything else
2. the locked decisions, restated in plain words, not only cited by reference
3. the list of what we do not touch
4. the invariants
5. the team composition and each member's role
6. the steps and their verification gates
7. the start, last, explicit

## 3. Wording

Say what to do rather than what not to do. "Gather the result into a short three-line status"
carries better than "don't return a wall of text". When a prohibition is truly needed, it always
comes with its reason: a bare ban is respected less than a justified one, the executor understands
the risk and does not look for a workaround. Avoid the "CRITICAL, you MUST" register, which pushes
the model to excessive caution on the whole rest of the prompt, not only on the targeted point.

## 4. Tags

Separate the pieces with named XML tags, consistent from one end of the prompt to the other:
`<plan>`, `<decisions>`, `<off_limits>`, `<invariants>`, `<team>`, `<steps>`, `<start>`.
One tag per section of part 2, in the same order.

## 5. The team

Three to five agents, no more. Beyond that, the pilot spends more time coordinating than moving.

- **The pilot.** The main session that reads the prompt. It sequences the batches, opens the
  verification gates, and does not code the big batches itself so as to keep its attention on
  scheduling.
- **The implementers.** One per independent batch, each in a fresh context. The underlying ask is
  a capable and diligent executor, whose model is set through the platform's own mechanism. In
  Claude Code, that goes through a plugin profile, `fstack:builder` or `fstack:expert` depending
  on the batch, the lowest one that meets the end criterion. Elsewhere, the same requirement is
  stated in plain words in the prompt.
- **The reviewer.** In a fresh context, it sees only the diff produced and the criteria of the task
  concerned, never the conversation history that gave birth to it. Its mandate stops at what
  breaks the correctness of the code or a requirement written in the plan. Style and personal
  preference stay outside its mandate, otherwise it always finds some and execution drifts into
  over-engineering to satisfy remarks that did not matter.

## 6. The parallelism rule

Two batches touching the same files never start in the same turn. The plan has already settled this
split in its dedicated section, the prompt only restates it so the pilot does not have to reread
the whole plan to find the information at the moment of acting.

## 7. Verification gates

One gate per step, taken from the plan. They are written here, in the execution prompt, never in
the skill itself. The skill runs on a model that already checks itself, asking it again for an
explicit verification only wastes tokens on correction narration. The implementers run on a model
that benefits from hearing it, so the instruction "before concluding, check that [criterion]" goes
in every step of the prompt.

## 8. What comes back

A subagent returns only its final result, the pilot never sees its working thread. The prompt
therefore asks each implementer to finish with a short three-line status: `Done`, `Left`,
`Surprises`. Without this instruction the pilot chains batches blind. It also asks them to update
the plan's Restart notes section and tick the steps at the end of their batch. Those are the only
two zones of the plan an executor edits, and the prompt says so: decisions, design and criteria
are not rewritten along the way. A criterion that turns out to be wrong goes back up to the pilot,
it is not loosened to turn green.

## 9. Example

Simple case, a plan that adds an `archived` field to a model and exposes it in a route.

```
<plan>
Read plans/add-archived-field.md in full before starting. It is the source of truth,
above everything else in this message.
</plan>

<decisions>
1. The field is called `archived`, boolean, default false. No `archivedAt` field, the date
   has no identified use today.
2. The GET route filters out archived items by default, a `?archived=true` parameter includes them.
</decisions>

<off_limits>
The `users` table and the authentication route. The subject is the `Task` model alone.
</off_limits>

<invariants>
The existing test suite passes at every step. No destructive migration, the column
is added with a default, it replaces nothing.
</invariants>

<team>
You, the pilot: you sequence the two batches below and open the gates.
Implementer A: migration and model batch, profile fstack:builder.
Implementer B: route and integration tests batch, profile fstack:builder, starts
after batch A since it consumes the field A adds.
Reviewer: profile fstack:reviewer, fresh context, it sees only the final diff and the criteria of
task 2 of the plan. It only reports what would break the default filter or the migration.
</team>

<steps>
1. Batch A: migration and model. Before concluding, check that the migration applies on an
   empty database and that the existing test `tests/models/task.test.js` still passes.
2. Batch B: route and tests. Before concluding, check that `GET /tasks` hides archived items by
   default and includes them with `?archived=true`.
3. Review of the full diff by the reviewer in a fresh context.
</steps>

<start>
Start by reading plans/add-archived-field.md in full, then launch batch A.
</start>
```
