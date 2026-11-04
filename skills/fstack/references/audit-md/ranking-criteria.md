# Ranking criteria

Loaded in phase 3, when a block resists the phase 3 ranking table. The four labels are exclusive:
a block gets one, never two.

## The test, in order

Ask the questions in this order and stop at the first one that settles it.

1. **Is it true?** The phase 2 verdict. If it is `UNVERIFIABLE`, the block stays where it is and
   you do not rank it. You flag it in the report, under a separate heading.
2. **Is it false?** See whether anything is left to keep. A false rule whose value can be fixed
   keeps its previous label, you just change the value. A false rule that traces a past decision
   goes to `ARCHIVE`. A false rule that leaves nothing goes to `DELETE`.
3. **Does it hold everywhere, all the time?** Yes is `ROOT`. No is `MOVE`, and `four-layers.md`
   says through which exit.

## ROOT

True, and true whatever file you are working on. It is the only category that costs tokens every
session, so it has to be earned.

In it: what the project is in two sentences, the build, test and lint commands, the bans with no
exception, the links to pages.

```markdown
Never commit to `main`. Work goes through a branch and a PR.
```

True everywhere, no exception, one line. That is the target format.

A useful doubt: if you can name a folder or a task where the rule does not apply, it is not
`ROOT`.

## MOVE

True, but only useful to someone working on a specific subject. A module, a folder, a procedure,
an integration.

This label does all the shortening work, and it should carry the majority of the blocks of an
overlong file. It calls for a second choice, the exit, and that choice matters as much as the
ranking: a constraint that must be applied never goes into a linked page, it goes to a path-scoped
rule or a skill. See `four-layers.md`.

```markdown
Alembic migrations are generated with `alembic revision --autogenerate`, then reviewed
by hand: autogenerate misses column renames and turns them into a drop plus add.
```

Useful, precise, true. And pointless for nine sessions out of ten. It goes to
`.claude/rules/migrations.md` with a `paths:` on the migrations folder, because it is a constraint
that must hold when someone touches a migration. A `docs/` page linked from the root would be the
wrong choice here: the link does not get opened by itself.

Before creating the page, check that it does not already exist. Content that repeats a `README.md`
or an existing page becomes a link to it, not one more file.

Two `MOVE` blocks on the same subject go to the same place. One page per block is scattering, and
nobody finds anything. Under 15 lines, do not create a page at all.

## ARCHIVE

Used to be true. No longer is. And it keeps trace value, because someone will ask "why was it like
that".

```markdown
The cache runs on Redis. Never set a key without a TTL, the instance is small.
```

If the project moved to something else, the rule is false, but it explains why some odd
serialization code remains. It goes to `archives/`, with a header giving the archive date and the
reason in one line.

The criterion separating `ARCHIVE` from `DELETE`: does it answer a question someone will ask while
reading the code? Yes, archive. No, delete.

A rule that has been false for a long time and that nobody ever applied is not a trace, it is
noise. It goes to `DELETE`.

## DELETE

False with nothing to keep, or true but meaningless. The detail of the empty forms is in
`anti-patterns.md`.

Watch how you use this label: it is for what deserves to exist nowhere. A bulky but true block is
not to be deleted, it is to be moved. On an overlong file, most lines are in that case, and an
audit that mostly proposes deletions picked the wrong tool.

Deletion is the only label that requires a row in the report's final table, with its proof beside
it. That is what lets the operator refuse case by case.

## Edge cases

| Case | What you do |
|---|---|
| A rule that is 60% true | you do not rank it, you ask the question in phase 4 with the count |
| A rule that repeats another rule in the same file | you keep the more precise wording, the other goes to `DELETE` |
| A true rule that a nested file contradicts | contradiction, phase 4 |
| A true rule that concerns a single file | `MOVE` to a path-scoped rule, with a `paths:` on that file |
| A block mixing a `ROOT` rule and a detail to move out | you split it in two, each piece takes its label |
| A security rule, even unverifiable | it stays at the root. A guardrail is not moved on a hunch |
| A constraint that no exit can hold | it stays at the root, even if that lengthens it. A lost constraint costs more than ten lines |
| A rule that comes from user scope | you do not touch it, you flag it |
