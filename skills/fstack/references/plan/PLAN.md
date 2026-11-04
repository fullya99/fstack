# Anatomy of a plan

## 1. Common skeleton

In this order. The template to fill in is `templates/plan.md`.

1. **Goal and validation case.** The result in one sentence, and the observable thing that will
   say it is done. Not "the system is improved", rather "the `X` command answers in under two
   seconds on the `Y` dataset".
2. **Locked decisions.** Numbered, each with its justification in one line, marked as not open to
   discussion from here on. This is what phase 3 settled with the operator.
3. **What we do not touch.** Files, modules and behaviors out of reach, named explicitly. It is the
   fence that keeps an execution session from going off the rails and widening the job on its own.
4. **Research.** What shaped the design, each point with its link and date. If the task had no
   external surface, the section says so in one line and stops there.
5. **Current state.** Real paths and symbols the work starts from. No abstract placeholder like
   "the user management module", the real path or nothing.
6. **Invariants.** What must stay true at every step: passing tests, backward compatibility, no
   secret on disk, whatever the project imposes on its side.
7. **Prior gates.** Three questions settled in writing before the design is written. The answer
   goes in the plan, not only in the author's head.
   - Simplicity: does a smaller version solve the real need?
   - Anti-abstraction: are we adding a layer nothing requires today?
   - Integration first: does end to end work before we polish one part?
   A gate we decide to force is justified in the deviation log, never silently.
8. **Deviation log.** What we allowed ourselves against a gate, and why. A forced gate with no
   entry here is a plan that started drifting before the first task.
9. **Design.** The changes, file by file.
10. **Tasks.** The format is fixed below and applies as is.
11. **Team split.** Which batches run in parallel, which in series, and why, with one role per
    batch, taken from `references/DELEGATION.md`. Two batches touching the same files never start
    together.
12. **Counter-review.** Findings `F-01`, `F-02` and so on, ranked Blocker, Major, Moderate or
    Validated, each with its written decision, integrated (section cited) or rejected (reason). A
    finding with no decision forbids returning the plan.
13. **Out of scope and deferred.**
14. **Known risks and pitfalls.**
15. **Restart notes.** Enough to restart in a session that knows nothing: where we stand, the next
    unchecked task, what is already validated and not redone, the command that gives the state of
    the terrain (tests, lint, the project's git status). It is updated as execution goes, not frozen
    when the plan is written.

## 2. Task format

Reused as is, with no variation from one plan to the next.

```
### Task N, <short name>

**Files**
- create: <exact paths>
- modify: <exact paths>
- test: <exact paths>

**Interfaces**
- consumes: <exact signatures>
- produces: <exact signatures>

**Steps**
- [ ] <one verifiable action, two to five minutes>
- [ ] <...>

**Verification**: <the command or observation that says the task is done>
```

Interfaces are read both ways before the plan is returned: everything a task consumes is produced
by an earlier task or already exists (path checked), and everything a task produces is consumed by
a later one or by the validation case. A production nothing consumes is an orphan task, it reaches
its end criterion without serving any purpose.

## 3. Level of proof

Every claim about the behavior of a tool, an API or a service states its level, in the sentence
itself: `proven on YYYY-MM-DD by <command>`, `first-hand doc <link>`, or
`inferred, to prove before task N`. In a table, the level goes in a column of every row, never in
a global "verified" at the top: an unmeasured figure placed under a "verified" heading ends up
copied elsewhere as a fact.

## 4. What is forbidden in a plan

"TBD", "TODO", "to be seen", "add appropriate validation", an invented path, a function whose
existence was not checked, a step with no verification criterion. Each of these makes the plan
unexecutable by anyone else, and that is precisely the point of the plan: the execution session
has nothing to guess.

## 5. Sections the type adds

Depending on the type chosen in phase 0, `PLAN-TYPES.md` lists sections on top of the common
skeleton. This file does not repeat them, it points to the table.

## 6. Location and naming

`plans/<slug>.md` at the project root, slug in lowercase and dashes, descriptive. If the project
already has a place where it keeps its plans, use that instead.

## 7. When not to write a plan

The task fits in two steps and three files, or the project already has tracking that would do
(`TODOS.md`, an issue, a board). Tell the operator and propose the alternative rather than
producing a plan for a task that does not need one.
