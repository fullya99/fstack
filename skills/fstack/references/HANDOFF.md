# HANDOFF: the "ready for a fresh context" test

> Starting cold is irreversible for context, whether through Claude Code's `/clear` or another
> agent's equivalent. Whatever was not written is lost. This page is the safety barrier before
> you trigger it.

## The test, in one sentence

> If this conversation disappeared now, could a new session pick the work up exactly where it
> stands, without asking the user a question?

As long as the answer is no, the debrief is not done. A longer summary in the chat does not fix
that, since the chat is going away.

---

## Cold-resume simulation

The only check that really counts is to reread yourself as if you knew nothing.

1. Reopen `TODOS.md`, the "Resume state" section, and read only that.
2. Ask yourself what your very next action is, concretely, which file you open. If the answer is
   clear, the block does its job. If you hesitate, information is missing, add it now.
3. Open `CODEMAP.md` and check that the files cited in step 2 are listed there.
4. Check that any pitfall met this session is written down somewhere: in the `docs/` page of the
   module concerned, or in `docs/pitfalls/`, or in the sensitive zones of `CODEMAP.md` (only one
   of the two per project, `docs/pitfalls/` if it exists). Otherwise it will be rediscovered
   later, at the price of the same mistakes.
5. Compare `git status` and `git log -3` with what the CHANGELOG says.

A gap found here is always a real debrief defect. Fix it, do not note it for later.

---

## Blocking checklist

### Accuracy
- [ ] The 3 pillars reflect the verified state, not the assumed one.
- [ ] No contradiction between pillars. The classic case: TODOS announces a finished task that
      CODEMAP still describes as missing.
- [ ] No cited path, command or resource that no longer exists.
- [ ] No known-false claim left "for later".

### Completeness
- [ ] The "Resume state" block is rewritten with today's date.
- [ ] Any work started and not finished has an explicit task in TODOS, with its files.
- [ ] Half-applied work is flagged: partial migration, interrupted refactor, feature behind a
      flag, file left in an intermediate state.
- [ ] Every structural decision made this session has its ADR in `docs/decisions/`.
- [ ] Every pitfall met is written down, in the module page or in the sensitive zones of the
      CODEMAP. This is the most direct gain of the debrief.
- [ ] Every preference the user expressed is in `CLAUDE.md`, and nothing volatile was added to it
      along the way.
- [ ] The modules and features touched have an up-to-date, indexed `docs/` page.

### Cleanliness
- [ ] What is obsolete is in `archives/`, with a header and an index line.
- [ ] No silent deletion.
- [ ] The `🔴` statuses in `docs/` have been handled. The `🟡` are verified or dated today.
- [ ] `ctx-audit.sh --budget` returns no `[!!]`, each `[!]` has its action or a dated task.
- [ ] No session section or ticked box in TODOS, no state or narrative in `CLAUDE.md`.

### Security
- [ ] No secret in a tracked file: key, token, password, signed URL.
- [ ] Environment files stay ignored.
- [ ] `git status` matches the intent, nothing forgotten, nothing stray.

### Multi-level
- [ ] Every level touched has been updated: root, sub-project, shared configuration.
- [ ] The parent points to the children's docs, it has not absorbed them.
- [ ] Every zone touched has its map up to date, and every zone is cited in the root CODEMAP.

### What proves a ticked box

A box is ticked on fresh proof from this session, never on a memory.

| Claim | Proof required | What is not enough |
|---|---|---|
| a check is green | its bare exit code, read from the command itself | a `tail` at the end of a pipe, which returns 0, or an exit code 2 (nothing was inspected) |
| the docs are true | `ctx-truth.sh --strict` returns 0 | a reread from memory |
| it is committed | `git log -1 --stat` lists the debrief files | a clean `git status` (another commit may have taken them) |
| it is pushed | `git rev-parse HEAD` equals `git rev-parse @{u}` | a push that was started and whose exit code was not read |
| an agent is done | its diff reread, its final command replayed | its "Done" report |
| nothing uses X | the command that would have found it, and what it swept | a `grep` that skips git-ignored files |
| the operator approved | their sentence, on that exact point | an "ok" given on something else |

### The excuses that skip a debrief

| What we tell ourselves | What is true |
|---|---|
| "I saw it pass earlier" | Output seen before the last edit proves nothing about the current state |
| "It's a small session, no need" | Phase 4 and phase 5 always run, one line is enough |
| "I'll note it at the next debrief" | There is no next time, there is a restart that wipes it |
| "The sub-agent said it was fine" | Its report is a claim, the diff is the proof |

---

## Handover anti-patterns

| Anti-pattern | Why it breaks | Instead |
|---|---|---|
| "Continue the refactor" | On return, nobody knows where it stood | "Finish extracting `parse()` to `lib/parser.ts`, 3 callers left to migrate: `a.ts:12`, `b.ts:88`, `c.ts:40`" |
| Chronological session summary | What comes next cannot be deduced from the story | A state: what works, what is in progress, the next action |
| Docs written from memory | Memory keeps an intermediate state, not the final one | Check the file, the command, the service |
| Redating a page without rereading it | `docs/` becomes a trap, the reader trusts it wrongly | Reread, fix, then date |
| Stacking "Resume state" blocks | The reader no longer knows which one counts | One block, rewritten |
| Piling everything into `CLAUDE.md` | It loads every session, the signal drowns and the context is paid for all the time | A decision in an ADR, a pitfall in the module page, a preference only if it is always true |
| Keeping the false claim "for later" | There is no later, there is a restart | Fix or archive, now |
| Postponing the debrief "to the end" | The end comes from running out of context, at the worst moment | Debrief when the work is coherent, not when the context is full |
| Stacking the resume block into the log | The reader pays 40,000 tokens before knowing what to do | Rewrite from the current state, 40 lines, file away what falls out |
| A session report in TODOS | TODOS keeps only the future | The entry goes to the CHANGELOG |
| Meeting the threshold by deleting a pitfall | The pitfall comes back at the price of a session | It moves down into its zone map or the module page |

---

## When to debrief

Before any deliberate cold restart, obviously. But also when a coherent unit of work is done,
even if the session continues. When the context nears saturation, before quality drops and not
after. Before a long interruption. Before switching to an unrelated subject.

An early debrief costs a few minutes. A missed one costs a full rediscovery, and sometimes
redone work.

---

## On return, the brief

Reading order, this is the BRIEF mode of the skill.

1. `CLAUDE.md`, the lasting rules and preferences.
2. Partial reading, never a whole pillar:

   ```bash
   awk '/^## /{n++} n<=1' TODOS.md      # the resume block, nothing else
   grep -n '^## ' CODEMAP.md            # the outline, then the useful section
   awk '/^## /{n++} n<=3' CHANGELOG.md  # the last 3 entries
   ```
3. Then the map of the one zone the task concerns.
4. The `docs/` pages of the modules concerned only, and the ADR if you are revisiting a settled
   choice.
5. `git log --oneline -10` and `git status -s`, to compare with reality.

Do not load `archives/`. Do not read all of `docs/`. Do not reread the whole CHANGELOG. The
brief must cost little context, otherwise it cancels the benefit of the restart.

Report in ten lines at most: where we stand, what is in progress, the next step, the pitfalls.
Any inconsistency between the docs and the repo gets fixed before coding. It is the symptom of
an incomplete earlier debrief, and the only moment when the repair has not yet been paid for dearly.
