# Mode UPGRADE

> **The contract**: a project that already has a context convention moves to version 5 without
> losing any true information. The script simulates first, the operator reads the report, then it
> is applied on a branch. Nothing is pushed or merged without the operator.

**Before writing anything**, load the **`style-redaction`** skill. If it is missing: direct tone,
no em dash, no semicolon.

## When this mode applies

| The project has | What you do |
|---|---|
| a `contexte:convention` block at version 3 or 4 | this mode |
| three pillars without a block (version 2), or four pillars with `MEMORY.md` (version 1) | this mode |
| a block at version 5 | the block is not rewritten, but the script safely replays its moves (orchestration lines, old commands, lists to sort) and says "nothing to do" if it has nothing to add |
| no pillar (version 0) | `scripts/ctx-init.sh`, mode SETUP, not this one |

After a plugin update, run `upgrade` again on a project already at version 5: the moves added
since then arrive, the block stays as is.

## The steps

1. **A branch.** `git switch -c fstack-upgrade` on a clean tree. The script creates neither a
   branch nor a commit.
2. **The simulation.** `bash "$SKILL/scripts/ctx-upgrade.sh" --root <root>` writes nothing.
   `<root>` is the command's argument if given, otherwise `.`. Resolve `$SKILL` as in `SKILL.md`.
3. **The review with the operator.** Read the report section by section, see below. Every point
   that calls for judgment is theirs.
4. **The application.** `bash "$SKILL/scripts/ctx-upgrade.sh" --root <root> --apply` installs the
   block at version 5 and rewrites the cited commands. A second pass changes nothing.
5. **The review decisions.** Apply by hand what the operator decided.
6. **A full debrief**, mode DEBRIEF, until `ctx-audit.sh --strict` reports no blocker. It checks
   the pillars, fills the gaps the new block reveals and rotates the logs.
7. **The PR, opened by the operator.** You prepare the description: starting version, what
   changed, what stays open. Rollback: close the PR, or `git revert` the merge.

An old project may carry the French forms (`Statut`, `docs/pieges/`, `ARCHIVE le`). The scripts
read both, and what they write is English.

## Reading the report

| Section | What the script does | What the operator decides |
|---|---|---|
| Block | installs or rewrites the block, keeps known keys, repairs an unclosed block | the guessed `langue`, the detected profile |
| `taille:` | removes it if it equals the measure, otherwise turns it into `taille-forcee:` | keep the forced value, or drop it |
| Existing conventions | declares `MEMORY.md`, `PROJECT.md`, `TASKS.md`, `ETAT.md`, the `AGENTS.md` that carries content, in `ecarts:` | the justification to complete, and whether to split `MEMORY.md` |
| `globs:` rules | proposes the diff to `paths:`, never applies it | apply the diff, or not |
| Local copies | lists them for removal, deletes nothing | the removal, after checking that no copy carries a setting of its own |
| Local script | reads its thresholds (`SEUIL=`, `MAX_...=`) and carries them into `seuils:` or `ajourne:` | the rest of its logic, to rework by hand |
| Commands | rewrites `/cloture-session:cloture`, `/cloture`, `/deep-plan:planifier`, `/planifier`, `/init-contexte`, `/reprise-session`, `/audit-md` to `/fstack:*` | reread the `CLAUDE.md` diff |
| Agent profiles | lists those named `syz-*` or `gz-*` or that pin a model identifier | replace them with `fstack:<profile>`, or declare them in `ecarts:` |

## The rules that hold

- **Nothing is deleted.** A file that leaves goes to `archives/` through `ctx-archive.sh`, with
  its reason. For a local copy folder, removal is the operator's decision, git keeps the history.
- **`MEMORY.md` is never dissolved silently.** The script declares it, the split of its content
  (decisions, pitfalls, preferences) is proposed in the PR and the operator decides.
- **A submodule is not touched** from the parent repo, it is upgraded in its own repo.
- **The installed block gets reread.** The language and the profile are guessed, check them in the
  diff before the debrief.
