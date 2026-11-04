# Templates

Loaded in phase 5. Two templates, the root file and a page. They are shapes, not texts to copy:
the content always comes from the audited project.

---

## The root file

Target 100 lines, warning at 150, blocker at 200. Four sections, in this order and nothing else.

````markdown
# <project name>

<Two sentences. What the project does, and the one thing a newcomer must know
before touching the code.>

## Commands

```bash
<install>
<run in dev>
<test>
<lint>
```

## Constraints

- **<A ban with no exception.>** <The reason, in one line, when it is not obvious.>
- **<Another one.>**

## Where to look for the rest

| When | Where |
|---|---|
| <the situation that makes you open it> | `docs/<topic>.md` |
| <the situation that makes you open it> | `docs/<topic>.md` |
````

**Commands are copied from the real manifest**, not retyped from memory. If `npm run dev` does not
exist in `package.json`, it does not go here.

**The constraints section only takes what has no exception.** A rule with an "except in..." goes to
a page, and its exception with it.

**The pointer table is what keeps the file at 50 lines.** Without it, everything flows back up. Its
left column states the situation, not the domain: it decides whether the page opens. A table that
lists topics is a list of files, and it will be ignored.

Rules moved to `.claude/rules/` do not need a line here, they load by themselves. A line is still
useful when the repo is read by an agent other than Claude Code, which does not know this layer.

If the file exceeds 100 lines after restructuring, a block ranked `ROOT` should have moved out.
Redo phase 3 on the longest blocks, not on all of them.

---

## A path-scoped rule

The best exit when the constraint must hold on a specific folder, because it loads by itself at the
right time. Claude Code only.

````markdown
---
paths:
  - "<glob matching at least one file>"
---

# <Topic>

- **<Rule.>** <What to do.>
- **<Rule.>**
````

Check the glob before writing the file. A `paths:` that matches nothing gives a dead rule, and
nothing signals it. An unescaped `[` in a glob makes it invalid, it matches zero files.

## A `docs/` page

One topic per page. Past 150 lines, split in two. Under 15, do not create it.

````markdown
# <Topic>

> Applies when <the reading condition, in one line: you touch this folder,
> you add this kind of thing, you debug this symptom>.

<Two or three lines of context. What the reader must have in mind before the rules.>

## Rules

- **<Rule.>** <What to do, not what to avoid.>
- **<Rule.>**

## Pitfalls

<What has already cost someone time. A symptom, a cause, a fix.>

## See also

- `<path/to/a/file>`
- `docs/<other-topic>.md`
````

**The first line says when to read the page.** It is what lets the agent decide whether to open it,
and it is the only part someone will surely read.

**Pitfalls are worth more than rules.** A rule can often be guessed, a pitfall never.

---

## The archive header

Everything that goes to `archives/` carries this header. Without it, `archives/` becomes a
graveyard that gets reread by mistake as a source.

```markdown
> ⚠️ **ARCHIVED on <YYYY-MM-DD>**, unmaintained, kept for history.
> **Origin**: `<original file>`
> **Reason**: <what made it false, in one line>
> **Replaced by**: <path, or none, the subject no longer exists>
> **Not a source of truth.**
```

The archive file name reuses the topic and the date, `archives/<YYYY-MM-DD>-<topic>.md`. If the
project already has its own naming convention in `archives/`, it wins.

---

## The phase 6 report

Four parts, in this order. It is what the operator reads before saying yes.

````markdown
## 1. Checks

| Status | Line | Claim | Proof |
|---|---|---|---|

## 2. Root file

<N> lines before, <N> after, <N> % fewer. Diff:

```diff
```

## 3. What moves out

| Destination | Layer | Lines | Comes from |
|---|---|---|---|

## 4. Deletions

| Line | Content | Reason | Proof |
|---|---|---|---|
````

The phase 4 contradictions come before all of this, as questions. The report is not presented until
they are settled, unless the operator asks to see the rest first.
