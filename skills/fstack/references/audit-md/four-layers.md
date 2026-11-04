# Where to put what leaves the root

Loaded in phase 3 and phase 5. This is the part that does the work: moving out of the root file
everything that does not belong there. Checked on 2026-08-23 against `code.claude.com/docs`.

## Why it works

The root file is loaded **every session, in full, before your first question**. Every line in it is
paid for forever, useful or not. And the cost is not only token price: past 200 lines the official
docs announce a drop in compliance, and at 40,000 characters the tool shows a performance warning.

Hence the idea: the root file is working memory, the rest is disk. Moving a block out does not
delete it, it moves it to something that loads only when it is needed.

You still have to pick the right exit. There are three, and they are not equal.

## The four layers

| Layer | Where | When it loads | Permanent cost |
|---|---|---|---|
| 1. Root | `CLAUDE.md` | every session, always | the whole file |
| 2. Path-scoped rule | `.claude/rules/<topic>.md` with `paths:` | when the agent touches a matching file | nothing |
| 3. Skill | `.claude/skills/<name>/SKILL.md` | the body, when the skill is useful | the `name` and `description`, nothing more |
| 4. Page | `docs/<topic>.md`, bare link from the root | if the agent decides to open the link | nothing |

**`@file` is not a layer.** An import pastes the content into layer 1 at startup, recursively up to
four hops. Splitting a `CLAUDE.md` into imports does not save a byte. It is the most common
misunderstanding on the subject. The lazy-loading request was closed as "not planned", and the docs
themselves contradicted each other on it long enough for a ticket to be opened. If you see imports
in a file you audit, tell the operator they do not lighten it.

## How to choose

One question at a time, in this order, and you stop at the first yes.

1. **Is it true everywhere, all the time, whatever file is open?** Layer 1. It stays.
2. **Does it only apply to certain files or folders?** Layer 2.
3. **Is it a multi-step procedure, redone from time to time?** Layer 3.
4. **Otherwise**, it is reference knowledge. Layer 4.

## Ranking the exits, and why it matters

The three exits are not interchangeable, and this is the most important point of this page.

**Layer 2 is the best.** The rule loads by itself, at the right time, without the agent having to
decide anything. With `paths: ["src/api/**/*.ts"]` the rule appears when it opens an API file,
never before.

**Layer 3 comes next.** Loading depends on the agent's judgment of the `description`, so it can
miss. But the description stays in context, so at least the agent knows the skill exists.

**Layer 4 is the weakest.** A bare link guarantees nothing. The agent sees it, and chooses whether
to open it, based on what it thinks it needs to know.

The practical consequence: **a rule that must be applied never goes to layer 4.** It goes to 2 or
3. Layer 4 carries what you consult, context, a past decision, a documented pitfall, not a
constraint that must hold.

If you cannot make a constraint hold at layer 2 or 3, say so. It is a case where it stays at the
root, even if it lengthens the file. A lost constraint costs more than ten lines.

## What each reader can do

| Layer | Claude Code | Codex | Hermes | OpenClaw |
|---|---|---|---|---|
| 2, path-scoped rule | yes | no | no | no |
| 3, skill | yes | yes, `.agents/skills/` | yes | yes |
| 4, linked page | yes | yes | yes | yes |

**Layer 2 exists only in Claude Code.** In a repo read by several agents, a rule that goes there
disappears for the others. Two ways to handle it, and the operator decides, not you: either the
rule is important enough to stay at the root where everyone sees it, or it goes to layer 2 and the
root file keeps one line saying it exists.

## Writing a link that does something

A bare link does not say when to open it, so it does not get opened.

What does not work:

```markdown
See also `docs/migrations.md`.
```

What works, a table where each row states the situation before giving the path:

```markdown
| When | Page |
|---|---|
| You add or change a migration | `docs/migrations.md` |
| An integration test fails in CI but passes locally | `docs/ci-flaky.md` |
```

The left column is what makes the page open. Without it, the table is just a list of files, and it
will be ignored.

Same at layer 3: the skill's `description` decides whether it loads. It says when to call, not only
what the skill does.

## How many pages

One page per topic, and a topic is what you hold in mind at once. Two blocks about migrations go in
the same page, even if they come from two places in the root file.

Past 150 lines, split in two. Under 15, do not create the page: those lines join a neighboring
page, or stay at the root. A ten-line page costs more in navigation than it brings.

And before creating anything, look at what exists. Content already written in a `README`, a page or
an ADR does not go into a new page, it becomes a link to the existing one.
