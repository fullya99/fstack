> **Status**: ✅ up to date, checked on {{DATE}}
> **Type**: procedure
> **Scope**: <what the procedure operates>
> **See also**: `docs/modules/<...>.md`

# Procedure, <name>

**Goal**: <what you get at the end.>
**When to run it**: <the trigger.>
**Duration and risk**: <~N minutes, reversible, or irreversible with <what>>

## Prerequisites

- [ ] <access, right, tool installed, variable set>
- [ ] <expected state of the system before starting>

## Steps

<For each step: the exact command, and how to know it succeeded. A procedure that does not say
how to check each step cannot be replayed.>

1. **<step>**
   ```bash
   <command>
   ```
   ✅ Expected: <output or observable state>

2. **<step>**
   ```bash
   <command>
   ```
   ✅ Expected: <output or observable state>

## Final check

```bash
<end-to-end check command>
```

## Rollback

<How to undo, step by step. If it is not reversible, say so here in plain words, with what is
lost.>

```bash
<command>
```

## Pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| <error message or behavior> | <the real cause> | <what to do> |
