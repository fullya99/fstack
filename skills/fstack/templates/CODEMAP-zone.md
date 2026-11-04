<!-- Zone map. Read on demand, when working in {{ZONE}}.
     No TODOS or CHANGELOG here: state and log stay unique, at the root.
     Aim for 150 lines, beyond 250 the zone splits. -->

# Zone map, {{ZONE}}

> What this zone does, and what breaks when you touch it. Part of {{PROJECT_NAME}},
> whose general map is `CODEMAP.md` at the root.
> Last updated: {{DATE}}

**In one sentence**: <what this zone does, and who consumes it>.

---

## Tree

```
{{ZONE}}/
├── <dir or file>    # role in one line
└── <dir or file>    # role in one line
```

---

## Entry points

| Entry | File | Called by |
|---|---|---|
| <name> | `<path>:<line>` | <route, command, event, other zone> |

---

## Flow

<The nominal path through the zone, in three to six steps, with the files crossed.>

---

## Pitfalls

<!-- A symptom followed by its cause, not an instruction. The sensitive areas of this zone
     live here, not in the root CODEMAP. -->

- `<path>`: <what surprises, and why>

---

## Zone commands

<!-- Only if they differ from the root ones. Otherwise delete the section. -->

| Goal | Command |
|---|---|
| Test this zone alone | `<cmd>` |
