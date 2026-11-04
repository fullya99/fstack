> **Status**: ✅ up to date, checked on {{DATE}}
> **Type**: module
> **Scope**: `<path/**>`, `<other/file>`
> **See also**: `docs/features/<...>.md`, `docs/decisions/ADR-00NN-<...>.md`

# Module, <name>

**Role**: <what this brick does, in one or two sentences. The essential first, a reader who
stops here must already have understood.>

## Where it lives

| File | Role |
|---|---|
| `<path>` | <one line> |

## Interface

<What the rest of the project consumes: functions, classes, endpoints, events, CLI. Exact
signatures live in the code, here you say what it is for and how it is used.>

| Element | Signature or shape | Use |
|---|---|---|
| `<name>` | `<shape>` | <when to call it> |

## How it works

<How it works inside, only for what cannot be read in the code: order of steps, state kept,
structuring special cases.>

## Invariants, what breaks if you touch it

- <non-obvious rule the code assumes true>
- <order dependency, implicit contract, side effect>

## Pitfalls

- <observed symptom> → <real cause> → <what to do>

## Dependencies

- **Uses**: `<module or service>`, <for what>
- **Used by**: `<module>`, <for what>

## Tests

| What | Where | Command |
|---|---|---|
| <cases covered> | `<path>` | `<cmd>` |

**Not covered**: <what no test protects. It is often the most useful information in the
page.>
