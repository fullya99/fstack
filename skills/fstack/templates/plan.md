# <short plan title>

<!-- File slug: plans/<slug>.md, lowercase and dashes. -->

## Goal and validation case

<!-- The result in one sentence, and the observable thing that will say it is done. -->

<goal sentence>

**Validation**: <observation or command that proves it is done>

## Locked decisions

<!-- Numbered, one-line justification each. Do not reopen during execution. -->

1. <decision>: <justification>
2. <decision>: <justification>

## What we do not touch

<!-- Files, modules, behaviors out of reach. Explicit, nothing implied. -->

- <path or behavior>

## Research

<!-- What shaped the design, one link and one date per point. -->
<!-- If the task had no external surface, write the sentence as is and nothing else. -->

- <claim>: <link>, <date>

Or: this task has no external surface, no research done.

## Current state

<!-- Real paths and symbols the work starts from. No abstract placeholder. -->

- <real path>: <what is there today>

## Invariants

<!-- What must stay true at every step: passing tests, no secret on disk,
     backward compatibility, constraints imposed by the project. -->

- <invariant>

## Prior gates

<!-- Three questions settled in writing before the design. A forced gate goes to the deviation
     log, never silently. -->

- **Simplicity**: does a smaller version solve the real need? <answer>
- **Anti-abstraction**: are we adding a layer nothing requires today? <answer>
- **Integration first**: does end to end work before we polish one part? <answer>

## Deviation log

<!-- What we allowed ourselves against a prior gate, and why. Empty if nothing was forced. -->

- <deviation>: <reason>

## Design

<!-- The changes, file by file. -->

### <file or area>

<what changes and why>

## Tasks

<!-- One entry per task, this format as is. -->

### Task 1, <short name>

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

## Team split

<!-- Which batches run in parallel. Which are serial, and why. Two batches touching
     the same files never start together. -->

<!-- One role per batch, taken from `references/DELEGATION.md`: explorer, tester, runner, builder,
     researcher, expert or reviewer. The lowest one that meets the batch's end criterion. -->

- Batch A (<tasks>), role <role>: parallel with <batch or nothing>
- Batch B (<tasks>), role <role>: after <batch>, because <reason>

## Counter-review

<!-- A fresh-context reviewer challenges the plan's assumptions. One written decision per finding,
     without which the plan is not returned. -->

| Id | Level | Finding and source | Decision |
|---|---|---|---|
| F-01 | Blocker, Major or Moderate | <what is wrong, link> | integrated (<section>) or rejected (<reason>) |

Validated: <findings confirmed by a primary source, in one line>

## Out of scope and deferred

<!-- What we chose not to do here, and why it can wait. -->

- <point>

## Known risks and pitfalls

<!-- What is likely to go wrong, drawn from research or exploration. -->

- <risk>: <how to spot or avoid it>

## Restart notes

<!-- Enough to restart in a session that knows nothing. Updated as execution goes,
     never frozen when the plan is written. -->

- Current state: <sentence>
- Next task: <task number and name>
- Already validated, do not redo: <list>
- Terrain check command: <tests, lint, git status command>
