# MODE-DEBRIEF: leave the repo complete, exact and readable

> **The contract**: at the end, a fresh session without this conversation resumes at the right
> place, without paying for context it will not use. The goal is not to summarize the session.

Question to ask again at each phase: does a cold reader, with the resume block, the `CODEMAP.md`,
`CLAUDE.md` and the pages of their zone, understand the real state, know what to do, and how much
does it cost them to read?

Style: load `style-redaction` before writing. If it is missing, the prose follows the language
declared by `langue:` in the `contexte:convention` block, a direct tone, no phrasing that smells
of generated text.

Without the kit, do `references/MODE-SETUP.md` then come back here, without asking. For a simple
trim, phases 0, 1, 5 and 8 are enough.

## Phase 0. Frame and measure

```bash
git status -s && git diff --stat && git log --oneline -10
bash "$SKILL/scripts/ctx-audit.sh" --budget
```

1. **Scope.** What changed, including outside git: untracked files, external resources created
   (service, database, DNS, key), system side effects.
2. **Levels.** A session started in a subdirectory often touches above, and may have crossed
   several projects. A folder that carries the three pillars is a standalone level, it is
   debriefed separately and the parent points to it. A folder that carries only a `CODEMAP.md` is a
   zone, it is updated here. Section 1b of the audit lists them.
3. **Budget.** Section 10 says what overflows, phase 5 handles it. A blocker is not postponed.
4. **Proportion.** Small session: short CHANGELOG, TODOS, and always phases 4 and 5. Substantial
   session: all phases. State the plan in one line, then execute.

**Observable**: the list of touched levels is written, and the `--budget` output is read.

## Reading a check without losing its code

Applies to every check in the phases that follow. The code is read on the command itself, never
behind a pipe: `ctx-truth.sh --strict | tail -3` returns `tail`'s code, so 0 on a red.

```bash
bash "$SKILL/scripts/ctx-truth.sh" --strict > <scratchpad>/truth.txt 2>&1; echo "code $?"
```

Then read the file. A check that looked at nothing (code 2, no file found, missing dependency) is
not a green, it is rerun on the right scope or named in the report.

## Phase 1. Audit the real state, without believing the docs

```bash
bash "$SKILL/scripts/ctx-audit.sh"                       # the current level
bash "$SKILL/scripts/ctx-audit.sh" --root packages/api   # a nested level
```

One pass per touched level, without `--root` the script takes the git root. Verify on the terrain
what the session touched (service, resource, test, cited path). Note each gap as "the docs say X,
reality is Y". Each gap has one outcome and only one: fixed in phase 2 or 3, or archived in phase
4.

**Observable**: the list of gaps is done, none is without an outcome.

## Phase 2. Sync the three pillars

| Pillar | What you do there |
|---|---|
| `CHANGELOG.md` | At the top, `## YYYY-MM-DD, title`: what, why, rollback. 25 lines at most, a big batch points to `docs/`. |
| `CODEMAP.md` | Reflects the structure: module added, removed or renamed, entry point, dependency, command. Remove what no longer exists. A pitfall goes in its zone's map or its module's page. Date and zone maps up to date. |
| `TODOS.md` | Check off what is done then delete it, delete the obsolete, add the tasks discovered. Deferred work carries its due date, `- [ ] (due YYYY-MM-DD) description`, which the startup hook surfaces. Then rewrite the "Resume state" block from the current state, never by editing the previous one. |

The block fits in 40 lines, four fields plus a `Check the terrain` line: the command that confirms
the repo is in the described state, copyable as is (tests, `git status -s`, the project's fastest
check). Before removing anything from the block, sort it: an event is already in the CHANGELOG, a
pitfall goes in its zone's map or its module's page, a task in the list with its anchor, a
decision in an ADR. The narrative is not kept.

Each fact in the block says where it comes from, so the resume knows what to recheck:
`(seen: <command>)` when a command showed it this session, `(read: <file>)` when it is copied,
`(assumed)` otherwise. A fact that drives the next step does not stay `(assumed)`: it is measured
now or becomes the resume's first task.

**Past due dates.** Each task in the touched scope whose due date has passed is settled here:
done, postponed with a new date and its reason, or archived because the facts overtook it. None
stays as a reminder. A reminder that returns at every startup without being settled stops being
read.

Durable facts go to their owner, never into a pillar. The question: who owns this sentence? If you
do not know, it probably should not be written. Full specification in `references/CONVENTION.md`.

### Draining the auto-memory

If the project has an auto-memory (a `MEMORY.md` index outside the tool's repo), each entry is
handled before the end: promoted to its owner (ADR, page, `CLAUDE.md`, CODEMAP) or deleted. None
stays in place by default. The move and the edge cases are in `references/AUTO-MEMORY.md`. A
`MEMORY.md` at the root of a project that uses it as a pillar is never dissolved here, see
`references/MODE-UPGRADE.md`.

**Observable**: `awk '/^## /{n++} n<=1' TODOS.md | wc -l` returns 40 or less, and the auto-memory
index keeps no unhandled entry.

## Phase 3. Document the modules in `docs/`

For each module touched seriously: the page exists, fix it and set its header to
`up to date, checked on YYYY-MM-DD`. It does not exist and the subject deserves one, create it from
`templates/docs/`. The subject has disappeared, it goes to `archives/` in phase 4. It exceeds 250
lines, split it or move its narrative out. The "deserves a page" criterion (several files
cooperate, an API consumed elsewhere, a non-obvious invariant, a replayable procedure, a
structuring decision) is in `references/DOCS-SYSTEM.md`. Update `docs/README.md` in the same move.

**Observable**: each touched page carries today's date, and appears in the index.

## Phase 4. Purge the obsolete to `archives/`

Never skipped. Go over pages, procedures, scripts, plans and abandoned proposals. Decision tree and
header in `references/ARCHIVING.md`.

```bash
bash "$SKILL/scripts/ctx-archive.sh" --verify <path>
bash "$SKILL/scripts/ctx-archive.sh" <path> --reason "..." --replaced-by "..."
```

The criterion is about incoming references: a live link is operative, it blocks. An executed plan
keeps its place as a summary, `ctx-rotation.sh --plans` handles it (it calls
`ctx-archive.sh --summary`). A false section in a file that is still useful gets fixed in place and
the fix goes to the CHANGELOG. A durable rule in `CLAUDE.md` that became false gets deleted, and
leaves a CHANGELOG line if its disappearance matters. A pillar is not archived, the script refuses.

### Mechanical pass and contradictor pass

**Mechanical.** Hand the claim verification to the `fstack:tester` profile (without subagents, run
it yourself):

```bash
bash "$SKILL/scripts/ctx-truth.sh"            # paths, scripts, options, commands, counts
bash "$SKILL/scripts/ctx-truth.sh" --info     # adds the claims to reread
bash "$SKILL/scripts/ctx-truth.sh" --strict   # code 1 if a false claim remains
```

The tester returns the raw output, without commenting on it. Each line has an outcome: fixed, or
covered by `exceptions: verite=<pattern>` in the block with its reason.

**Contradictor.** For only the pages whose scope moved (the audit says which), launch
`fstack:reviewer` in a fresh context: it receives the pages and the diff, nothing from the
conversation, and lists the false or stale sentences with the proof. Without subagents, reread the
page cold against the diff, after closing what you know about it. **The orchestrator decides**: a
listed sentence is false only once you verified it yourself. The lowest profile that meets the
criterion, see `references/DELEGATION.md`.

**Observable**: `ctx-truth.sh --strict` returns 0. No known-false claim remains in the pillars,
`CLAUDE.md` or `docs/`, and no silent deletion.

## Phase 5. Keep the budget

```bash
bash "$SKILL/scripts/ctx-audit.sh" --budget
```

Each `[!]` is handled now, or gets a dated task in TODOS just once: a warning that comes back at
the next debrief is a blocker. Each `[!!]` is handled now. Thresholds and why in
`references/BUDGET.md`.

| What overflows | The move |
|---|---|
| resume block | rewrite from the current state, sort what leaves |
| TODOS.md | delete checked boxes, move session narratives to the CHANGELOG, trim tasks without an anchor |
| log with dated entries | `ctx-rotation.sh` (below), then shorten entries over 25 lines |
| root CODEMAP.md | create zones with `ctx-init.sh --zone`, move their pitfalls and commands down, point from the "Zones" table |
| CLAUDE.md | see "Self-improving `CLAUDE.md`" below |
| a `docs/` page | split in two subjects, or move the narrative to `archives/` |
| a zone map | split the zone in two |

### Log rotation and plan lifecycle

```bash
bash "$SKILL/scripts/ctx-rotation.sh" --dry-run                       # CHANGELOG.md, announces without writing
bash "$SKILL/scripts/ctx-rotation.sh" --file <log> --keep 30 --cap 1500
bash "$SKILL/scripts/ctx-rotation.sh" --plans --dry-run               # executed plans
bash "$SKILL/scripts/ctx-rotation.sh" --plans
```

Always `--dry-run` first, read what it announces. Rotation stores cold material, it does not
archive falsehood. A log ordered oldest to newest is refused (code 3), put it back in order. An
executed plan over 20 lines becomes a 20-line summary, its full text goes to the archive. The
script recognizes an executed plan by the mark `Status: finished` or by a `TODOS.md` line that
cites it, with no open box.

### Self-improving `CLAUDE.md`

Bounded by its budget, never on top. A rule learned this session and true at every moment is
added, and in exchange a line leaves. Each line passes the test "would removing it cause a
mistake?". State goes in TODOS, narrative in the page, zone rule in `<zone>/CLAUDE.md` or
`.claude/rules/<zone>.md`. Beyond the budget, `references/MODE-CHECK.md`.

On a large codebase, the trimming is split by zone between profiles (`references/DELEGATION.md`).
You keep the resume block and every archiving decision.

**Observable**: `bash "$SKILL/scripts/ctx-audit.sh" --budget` returns no `[!!]`, each `[!]` has its
move or its task.

## Phase 6. "Ready for a fresh context" test

Blocking, full checklist in `references/HANDOFF.md`. The points that fail most: each touched level
has its pass, the pillars do not contradict each other (read TODOS and CODEMAP side by side), all
work in progress has its written task, no secret in a tracked file, `CLAUDE.md` carries neither
state nor narrative.

## Phase 7. Lessons learned, commit, marker

1. **Lessons learned.** A line with numbers in the day's CHANGELOG entry, for example
   `Session: 3 pages fixed, 2 archived, 4 audit warnings before, 1 after, 2 contradictor reviews,
   1 false sentence found.` Measured numbers, not an impression.
2. **Commit.** Never without an explicit request, you propose and wait. On request: a working
   branch, a message that says what and why. You add by explicit paths, never `git add -A`:
   another session in the same folder shares the git index, and a commit can carry one session's
   title and the other's files. Right after, `git log -1 --stat`, and the list must be the
   debrief's. On a push request, it landed only if `git rev-parse HEAD` and `git rev-parse @{u}`
   return the same value.
3. **Marker.** After the commit if there is one, so the marker carries the right `commit`. Run the
   command in the "Debrief marker and restart prompt" section of `SKILL.md`. It is written out in
   full there because `CLAUDE_PLUGIN_DATA` is substituted only in the body of a skill, a command
   or an agent, not in this file, and does not exist in the Bash tool. Outside Claude Code it is
   empty and the script exits without a marker.
4. **Final check.** Everything the debrief touched is in the commit:

   ```bash
   git status --porcelain
   ```

   The output is empty, or lists only what you decided to leave and can name. A debrief file still
   listed is an oversight. The marker lives outside the repo, it does not appear there.
5. **Undo.** A failed debrief is undone by `git revert <commit>`, never by hand editing. That is
   why the debrief fits in a single commit and the CHANGELOG carries its rollback.
6. **Handover.** Unless the debrief note contains `no-brief`, write the restart prompt (format in
   `references/MODE-BRIEF.md`, "The restart prompt" section) and store it for the next session
   with the command in the "Debrief marker and restart prompt" section of `SKILL.md`. The hook
   will announce it at the next startup with its freshness, and `/fstack:brief open` will play it.
   Outside Claude Code, nothing is stored and the prompt stays in the report. This prompt replaces
   the previous handover, never a plan's prompt. Before writing it, list the queue
   (`--list-briefs`, same section): if the next step is a waiting plan, the prompt's start points
   to its entry. A plan the session executed without going through the queue keeps its pending
   entry: settle it (`--settle <entry>`, same section) so it is not replayed, and say so in the
   report.

## Phase 8. Report

Plain text, never an artifact: what was done in 1 to 3 lines, then one line each for the pillars,
`docs/` (pages added, fixed, ADRs), `archives/` (items and reason), truth (`ctx-truth.sh` fixes,
the contradictor's false sentences), auto-memory (promoted, deleted), budget (sizes before and
after), `CLAUDE.md`, the levels updated, and what is left to do with a pointer to `TODOS.md`, and
the restart prompt (stored, or why not). Each check cited carries its bare code. It ends with
"Ready for a fresh context" only if phase 6 passes.
