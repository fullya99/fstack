> **Status**: ✅ up to date, checked on {{DATE}}
> **Type**: feature
> **Scope**: `<paths involved>`
> **See also**: `docs/modules/<...>.md`

# Feature, <name>

**What it does, and for whom**: <one or two sentences, from the user's point of view, not the
code's.>

**State**: <in production, or behind a flag `<name>`, or partial with <what is missing>>

## Journey

<The end-to-end path, with the files crossed. This is the section that saves a cold reader the
most time.>

1. <trigger: user action, call, event> → `<file>`
2. <processing> → `<file>`
3. <observable result> → `<file>`

## Files involved

| File | Role in the feature |
|---|---|
| `<path>` | <one line> |

## Configuration

| Setting | Where | Default | Effect |
|---|---|---|---|
| `<name>` | `<env var or file>` | `<value>` | <what it changes> |

## Edge cases and errors

| Situation | Expected behavior |
|---|---|
| <invalid input, service down, concurrency, quota> | <what happens> |

## Known limits

- <what the feature does not do, or not yet, and why>

## How to check it works

```bash
<replayable command, request or manual scenario>
```

Expected result: <what you should observe>
