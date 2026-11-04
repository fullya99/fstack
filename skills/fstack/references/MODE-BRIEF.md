# MODE-BRIEF: restart cold without paying much

> **The contract**: after a context reset (`/clear` in Claude Code), you give the right next step
> by reading only the resume block, the map and the last three log entries. Nothing more without a
> reason. An expensive resume cancels the benefit of the reset.

The operator's intent, if given, comes before deduction. Otherwise the logical follow-up is the
"Next step" of the block.

## 1. Read the marker

In Claude Code, the startup hook already shows the last debrief's marker: the commit, the tree
state and the date. You have nothing to run. Compare it with `git log --oneline -1`:

- same commit, clean tree: the repo is in the state the debrief described
- different commit: work happened after the debrief, the resume block may be behind
- no marker: no debrief on this machine, or another platform. Go to step 2, the block rules.

The marker is read in `<data>/markers/<project name>` (`key=value` lines). It is written by
`ctx-startup.sh --write-marker` at the end of a debrief, see `references/MODE-DEBRIEF.md`.

Without a marker, the hook flags a possibly forgotten debrief when the tree carries five or more
uncommitted files and the CHANGELOG has no entry from yesterday or today. Say so before anything
else: the resume then starts from a block that does not describe the repo.

**The brief queue (`/fstack:brief open`).** The hook announces the prompts waiting. Two kinds of
entries: `handover`, written by the last debrief, and `plan-<slug>`, one per plan, written by the
plan mode. Read the next one with the command in the "Debrief marker and restart prompt" section
of `SKILL.md`. The handover goes first, it describes the freshest state. Then come the plans in
the order they were queued, except a plan whose dependency is still waiting. A name given to
`open` (`open plan-x`, or `open x`) plays that entry.

The first line of the output says when and at which commit the prompt was produced, and how many
commits arrived since. Zero commits: it holds, follow its start. Commits since: read them
(`git log --oneline <commit>..HEAD`) before following the prompt, they may have done or undone its
next step. For a plan, it also says whether the plan file changed since queuing or has
disappeared. Changed: reread the plan before the prompt, the plan rules. Not found: execute
nothing and say so. Once read, the entry is marked played and the hook stops announcing it.

**One plan per session.** A plan's prompt drives the whole session. Once that plan is finished or
interrupted, other entries may remain in the queue. Do not chain them: debrief, then reset the
context and run `open` again. After a handover, which loads almost nothing, playing the next plan
in the same session remains possible.

## 2. Read in this order, and no more

Never a whole pillar.

```bash
awk '/^## /{n++} n<=1' TODOS.md      # the resume block, nothing else from TODOS.md
grep -n '^## ' CODEMAP.md            # the map's outline, then the one useful section
awk '/^## /{n++} n<=3' CHANGELOG.md  # the last three entries
```

`CLAUDE.md` is already loaded in Claude Code, elsewhere read it. If the task touches a zone, read
that zone's map. Read the `docs/` pages only for the modules the coming task concerns, and the
matching ADR if you are about to revisit a settled choice.

If the log is not in `## YYYY-MM-DD` form, the `contexte:convention` block declares its format in
`journal:`, see `references/PROJECT-CONFIG.md`.

**Never read `archives/`.** It is false or cold by construction. To find why something is done a
given way:

```bash
bash "$SKILL/scripts/ctx-archaeology.sh" <pattern>     # provenance before excerpt, bounded output
```

Never a bare `grep`: it returns a line without its header and you take cold for current.

**Observable**: you can quote the block's next step, and you read fewer than three whole files.

## 3. Check the terrain

The resume block carries a `Check the terrain` line with a copyable command. Run it as is, then
compare the repo to the docs:

```bash
git log --oneline -10 && git status -s
```

Without that line, these two commands are the minimum. A divergence gets flagged right away: a
block that no longer matches the repo is the symptom of a sloppy debrief, and it gets fixed before
coding. If `bash "$SKILL/scripts/ctx-audit.sh" --budget` is available, a pillar that overflows
gets flagged too.

**Observable**: the command ran, its output matches the block or the gap is named.

## 4. Report back

Ten lines at most: where we stand, what is in progress, the next step, the pitfalls from the "To
know before touching" heading, the inconsistencies found. Then ask whether to go with the next
step, or with the intent given.

## The restart prompt

When the operator wants to prepare the next session ("prepare the restart", "prompt for after
`/clear`"), and at the end of every debrief, your only deliverable is a prompt for the new
session. You modify no file in the repo. In Claude Code, you also store it outside the repo with
the command in the "Debrief marker and restart prompt" section of `SKILL.md`, so the next session
finds it without copy-paste. It is shown in the chat in every case. If the resume block is stale,
say so and propose a debrief first, since the prompt is worth only what the repo is worth.

The prompt fits in a single `text` block, nothing after it. Four sections, each fact coming from
the real state read, never invented:

1. **Mission**: 1 to 3 lines, what and why, with the real paths concerned.
2. **Orientation**: the reading order of step 2, with the zone concerned named.
3. **Rules**: a pointer to `CLAUDE.md` and the project's rules, not a copy. Constraints specific
   to the task (access, fragile external resource) are added, one line each.
4. **Start**: the block's `Check the terrain` line, then the next step, then "if an assumption
   is ambiguous, ask before acting". If plans are waiting in the queue and the next step is one of
   them, write "`/fstack:brief open plan-<slug>`" instead of redescribing the plan.

Three rules apply to the whole prompt:

- Its first line says when it was produced (`Produced on YYYY-MM-DD at HH:MM, commit <sha>`). A
  prompt played too early or too late is recognized by this line.
- A dated goal carries its condition: "if you read this before DD/MM, start with...". Otherwise a
  prompt played too early launches the session on a goal still out of reach.
- A copied fact carries its source and read date, `(read: TODOS.md, 2026-11-02)`. A fact that
  drives a decision gets measured in the new session instead of being believed.

Above the block, one line: the target level and the instruction "paste what follows after the
context reset, or run `/fstack:brief open`".

**Observable**: every path and command in the prompt exists in the repo.
