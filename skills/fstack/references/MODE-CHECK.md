# Mode CHECK

> **The contract**: a short root file, where every remaining line is true and proven, and
> everything else stored where it costs nothing until it is needed. Nothing is written before the
> operator has read the report and said yes.

An instructions file is loaded in full at every session, so every line is paid for forever, and
past 200 lines the docs announce a drop in obedience. This mode shortens, and verification against
the code makes each cut defensible.

Load `style-redaction` before writing. If it is missing, apply the language declared by the
`contexte:convention` block, a direct tone and no phrasing that smells of generated text.

## What the mode handles

Six phases for a trim or an audit. "Just check whether it is true" stops after phase 2. A specific
block to move out goes through phases 3 and 5. Adding a rule or writing a file from scratch is out
of scope: the mode moves and deletes, it does not invent.

## The readers

Claude Code reads `CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md`, nested `CLAUDE.md` files,
`.claude/rules/*.md` and `.claude/agents/*.md`. Codex, Hermes Agent and OpenClaw read `AGENTS.md`
(Hermes also reads `CLAUDE.md`), Cursor, Windsurf and Cline their own rules files.

**Claude Code does not read `AGENTS.md`.** A repo carrying both files runs two sources that
diverge without anything saying so. The link is an `@AGENTS.md` line at the top of `CLAUDE.md`, or
a symbolic link. Two files without a link are noted in phase 2.

Everything that lives outside the repo (`~/.claude/`, `~/.agents/`, `~/.codex/`, `~/.hermes/`, the
managed policy) is flagged in the inventory without touching it. No instruction is universal:
`/clear`, `/compact`, a model identifier or a subagent name are Claude Code cases, and a rule that
mentions them is stored with a note of which reader it holds for.

### Imports and rules

In Claude Code, an `@path/file` line outside a code block loads that file at startup, up to four
hops. A dead import is a silent dead line, and an imported file counts in the budget as if pasted
into the root. An `@docs/guide.md` cited as an example really loads one.

Claude Code reads only `paths:` in a rule's frontmatter. A rule with `globs:` does not load on
demand, `ctx-audit.sh` flags it. The fix is `globs:` to `paths:`, with the diff.

## Before starting

The command's argument, if given, is the file or folder to audit first.

**The git tree must be clean**, so everything can be undone with a `git checkout`.

```bash
git status --porcelain
```

If anything comes out, ask to commit first. No `.bak`, no stash decided alone.

**The project's storage convention wins.** `ls -1 docs/ archives/ CODEMAP.md TODOS.md 2>/dev/null`
says what exists, the `contexte:convention` block says what is declared. You store there. If
nothing exists, you propose `docs/` and `archives/` and wait for confirmation. Never a parallel
tree under `.claude/`.

## The six phases

### Phase 1. Inventory

```bash
find . -path ./node_modules -prune -o \( -name 'CLAUDE*.md' -o -name 'AGENTS.md' \
  -o -path '*/.claude/rules/*.md' -o -path '*/.claude/agents/*.md' \) -print
grep -nE '^[[:space:]]*@[^[:space:]`]+' CLAUDE.md 2>/dev/null   # the imports
wc -l CLAUDE.md AGENTS.md 2>/dev/null
git log -1 --format=%ad --date=short -- CLAUDE.md
grep -nE '^[[:space:]]*@[^[:space:]`]+' CLAUDE.md 2>/dev/null   # the imports
```

Note for each file the size, the date of the last commit and the loading scope. An imported file
counts in the root's total. Also note the existing documents (`docs/`, `CODEMAP.md`, ADRs): a line
whose content appears there becomes a link, not a page.
Observable: a table of file, lines, date, scope.

### Phase 2. Verification against the code

Two mechanical passes, then your judgment. `$SKILL` resolves as described in `SKILL.md`.

```bash
bash "$SKILL/scripts/check-refs.sh" --format=md CLAUDE.md AGENTS.md
bash "$SKILL/scripts/ctx-truth.sh" --info
```

`check-refs.sh` gives a verdict per cited path, command, glob or import. `ctx-truth.sh` also
covers `docs/` and the pillars, and checks the `--x` options of the repo's scripts, the `npm run`,
`bun run`, `make` commands against the manifest and the "N files" counts in front of a directory.
In Claude Code, hand the second to the `fstack:tester` profile, which returns the output as is.
Elsewhere, run it yourself.

`ctx-truth.sh` grades its outputs. The `warning` level is a false claim proven by the repo, it
blocks `--strict` and goes to the evidence table. The `info` level is a path cited in passing or a
bare name, shown by `--info` only, never blocking. An `info` is not a falsehood: across three
clones these mentions were false in 87% of cases, you reread them and decide.

What the scripts leave to you: a dependency or a version (you read the manifest and compare the
value), a rule's `paths:` (it must match at least one file), a code or naming convention (you
count, "3 files out of 40" is the proof), an organization rule (a grep that would contradict it,
nothing in the output confirms it), and the `info` lines.

Three verdicts, one per claim. `TRUE`: the repo confirms. `FALSE`: the repo contradicts and you
hold a proof the operator can rerun, the missing path, the manifest line, the count.
`UNVERIFIABLE`: you have nothing to decide with, that is honest, and the claim stays where it is.
A convention followed 90% of the time is true. At 8% it is false, the count proves it. In between,
you ask in phase 4.

Patterns declared by `exceptions: verite=<pattern>` in the block are already settled, do not
report them.

### Agent files

A malformed agent file is not loaded, with no error or warning.

```bash
bash "$SKILL/scripts/check-agents.sh" .claude/agents/
```

The script covers the ways of disappearing silently, the key table is in
`references/audit-md/agent-files.md`.

**The model is set by alias** (`haiku`, `sonnet`, `opus`), never by dated identifier. A pinned
identifier does not follow the latest version of its family, and an agent without `model` inherits
the session's model, often the most expensive. `ctx-audit.sh` flags it (check for a pinned model
identifier or an agent without `model:`). You propose the alias, with the diff, and only the
frontmatter changes.

**Local profiles.** In Claude Code, reread the agents in `.claude/agents/` and compare each to the
plugin's profiles. A local agent that redoes `explorer`, `tester`, `runner`, `builder`,
`researcher`, `expert` or `reviewer` is proposed for replacement by `fstack:<profile>`, with the
justification and the deletion diff. An agent that carries a role specific to the project stays.
The doctrine is in `DELEGATION.md`.

Left to read: the `description` must trigger (three words never trigger), two close descriptions
step on each other (question in phase 4), and the body must not repeat `CLAUDE.md`. **You never
rewrite an agent's body.** The frontmatter gets fixed, the prompt is its author's choice.

### Phase 3. Ranking, block by block

A block is a rule: a bullet, a paragraph, a short section. It gets a label.

| Label | Criterion | Destination |
|---|---|---|
| `ROOT` | true everywhere, all the time | stays in the root file |
| `MOVE` | true, but only serves one task, folder or module | one of the three lower layers |
| `ARCHIVE` | was true, keeps trace value | `archives/`, with its date and the reason |
| `DELETE` | false with nothing to keep, or meaningless | deleted, listed with the proof |

`MOVE` calls for a second choice, the layer.

| Layer | Where | When it loads |
|---|---|---|
| Simple link | a line of the pointer table | if the agent opens the link |
| Rule with `paths` | `.claude/rules/<topic>.md` with `paths:` | alone, when a matching file is touched |
| Zone map | `CODEMAP.md` or a subfolder's map | when working in the zone |
| Page | `docs/<topic>.md`, linked from the root | if the agent opens the link |

A procedure that gets replayed becomes a skill. **A constraint that must be enforced never goes in
a page**, a bare link guarantees nothing: rule with `paths` if it is specific to a folder,
otherwise it stays at the root, even if that lengthens it. Detail in
`references/audit-md/four-layers.md`, edge cases in `references/audit-md/ranking-criteria.md`.

Put in `DELETE` what the agent already does by default, what a linter enforces, what is too
vague to follow. The full list is in `references/audit-md/anti-patterns.md`. A false rule that
becomes true again by fixing a value gets fixed, not deleted.

Observable: every block carries a label, and every `MOVE` a layer.

### Phase 4. Contradictions

List the rules that oppose each other, including `CLAUDE.md` against `AGENTS.md` or a nested file
against the root. For each you show both versions, their location and date, and **you ask the
operator**. You never decide. An open contradiction blocks the ranking of its two blocks, not the
rest.

### Phase 5. Restructuring

The root aims for **100 lines**, warning at **150**, blocker at **200** (thresholds from
`references/BUDGET.md`), unless a threshold is declared in the `contexte:convention` block. It
carries the project in two sentences, the real commands, the constraints without exception and the
pointer table. Each line of the table gives the situation before the path ("You add a migration",
then `docs/migrations.md`), otherwise it does not get opened.

A page says when it applies and covers a single topic, from 15 to 150 lines. A rule with `paths`
carries a glob that matches at least one file. **No `@import` to lighten**, it loads at startup.
Templates are in `references/audit-md/templates.md`.

**You do not break links.** After a move, go over the repo again.

```bash
grep -rn "CLAUDE.md" --include='*.md' --include='*.yml' --include='*.yaml' . | grep -v node_modules
bash "$SKILL/scripts/check-refs.sh" CLAUDE.md
bash "$SKILL/scripts/ctx-truth.sh" --strict
```

Observable: `check-refs.sh` and `ctx-truth.sh --strict` exit with 0.

### Phase 6. Report, then validation

You present the complete plan **before writing**, in four parts in this order.

1. The verification table, a verdict and a proof per claim.
2. The root file's diff, lines before and after, gain in percent.
3. What moves out, with the layer and the line count of each piece.
4. The deletions, one line per block with the proof.

Proposals on agents (alias, replacement by a profile) and `globs:` to convert come with their
diff. The operator approves, corrects or refuses block by block, you write only afterward. Then
rerun the check: a second pass must change nothing, otherwise phase 3 ranked badly.

## Invariants

- No write before the report is validated, no work on a dirty git tree.
- No `FALSE` without a rerunnable proof, no contradiction decided without the operator.
- No invention: you move, you delete, you replace a false value with the true one.
- No broken link, no parallel tree, no change outside the repo.
- No rewrite of an agent's body, no `@import` to lighten.

## References

| File | When to read it |
|---|---|
| `references/audit-md/four-layers.md` | phases 3 and 5, choosing a block's layer |
| `references/audit-md/ranking-criteria.md` | phase 3, `MOVE` against `ARCHIVE`, edge cases |
| `references/audit-md/anti-patterns.md` | phase 3, justifying a `DELETE` |
| `references/audit-md/templates.md` | phase 5, root and page templates |
| `references/audit-md/agent-files.md` | phase 2, repo that declares subagents |
