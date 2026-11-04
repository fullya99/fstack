# Rules that serve no purpose

Loaded in phase 3, to justify a `DELETE` with a reason rather than a feeling. Each form below has
the same consequence: it costs tokens every session and changes nothing about what the agent does.

A rule that falls into one of these forms is not deleted outright. It is **proposed** for deletion,
with the reason. The operator decides.

## 1. What the agent already does by default

> "Write readable code." · "Add useful comments." · "Handle errors."

No model aims for the opposite. The line moves nothing.

**The test**: would removing the line change an output? If you cannot name which, it is a
deletion.

**The exception**: when the rule says *how*, it becomes useful again. "Errors bubble up as
`Result`, never as exceptions" is a real constraint.

## 2. What a tool already enforces

> "Indent with 2 spaces." · "No semicolon at end of line." · "Sort imports."

If Prettier, Black, `gofmt`, ESLint or Ruff is configured, the tool always wins, and it wins after
the agent. The line is useless at best, and at worst it contradicts the config.

**The proof to give**: the config file line that carries the rule.

```
.prettierrc:3   "semi": false
```

## 3. What the project already says by itself

> "This project uses TypeScript." · "We're on React." · "The database is PostgreSQL."

The agent reads the manifest and the file extensions. Restating the language takes space and
teaches nothing.

**The exception**: a version constraint that is not in the manifest, "we stay on React 18, 19
breaks server rendering here", is real information. It stays, and often moves to a `docs/` page.

## 4. Too vague to follow

> "Be rigorous." · "Mind performance." · "Follow best practices."

Two people reading the line do two different things, so it coordinates nothing.

**The test**: can you tell, reading a diff, whether the rule was followed? No means deletion. A
rule that cannot be checked is not a rule.

## 5. The negative with no alternative

> "Don't use `any`." · "Don't query inside the render loop."

A ban with no replacement leaves the agent to find its own way, and it often finds worse. The rule
is not wrong, it is incomplete.

**Careful**, this is the trap of the category: **you do not complete the rule yourself.**
Completing means inventing. You flag it to the operator in phase 4, with the question "what do we
replace it with". If they do not answer, it stays as it is.

## 6. Politeness and meta

> "Please kindly..." · "Feel free to ask questions." · "You are a senior developer expert."

Role and tone are set elsewhere. In a project instructions file, these lines carry no information
about the project.

## 7. Documentation in disguise

> Twenty lines describing the project architecture, the folder list, the history of rewrites.

Useful, but not an instruction. It does not go to `DELETE`, it goes to `DOC`, or into a
`CODEMAP.md` if the project has one. This form is the first cause of a 400-line root file.

## 8. The dead rule

> A rule whose `paths:` matches no file. An instruction about a deleted folder. A path that no
> longer exists.

It is a `FALSE` from phase 2. Depending on whether it explains something about the current code,
it goes to `ARCHIVE` or `DELETE`.

**The proof to give**: the script output.

```
FALSE  glob  L42  src/legacy/**/*.js  matches no file
```

## The reasons table, for the report

A deletion is justified by one of the reasons below, never by "useless".

| Code | Short reason |
|---|---|
| `default` | behavior already the default |
| `tool` | already enforced by a linter or formatter |
| `obvious` | already carried by the language or the manifest |
| `vague` | cannot be checked in a diff |
| `negative` | ban with no replacement, not completed by the operator |
| `meta` | politeness, role, off-topic for the project |
| `dead` | broken reference, no value as a trace |
| `duplicate` | said elsewhere, in the same file or on a page |
