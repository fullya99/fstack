# RESOLUTION: why the `$SKILL` loop looks there, in that order

Read this page when the loop returns empty although the skill is installed on the machine, or
when it resolves the wrong version.

## The candidate order

The order is deliberate. `CLAUDE_PLUGIN_ROOT` first when the skill runs as a plugin, then the
project scope in Claude Code and in Codex, then the user scope of both, then Claude Code's plugin
copies.

## Codex's two user directories

Codex has two user-scope directories, `~/.codex/skills/` where its installer drops files, and
`~/.agents/skills/` from the open standard. Both are scanned, verified on 2026-08-14. The first
comes first because it holds the version the user actually installed, while the other may keep a
hand-placed copy that has gone stale.

## The two copies of a Claude Code plugin

An installed plugin exists in two copies. `cache/<marketplace>/<plugin>/<version>/` holds the
version actually installed, `marketplaces/<marketplace>/` holds the tip of the repo's `master`.
The cache is searched first, and `sort -r` takes the highest version when several are cached.
Without that order, a single `find` returns both and takes whichever the traversal yields first,
which picks at random as soon as the repo has moved past the installed version.

The test looks for `scripts/ctx-audit.sh`, which also rules out same-named directories.

## Climbing the ancestors

Codex has no equivalent of `CLAUDE_PLUGIN_ROOT`, this loop is its only resolution mechanism. It
climbs the tree to find `.agents/skills/`, and `$ANCESTORS` does the same before the loop, testing
each ancestor of the current directory. A skill placed at a repo root while you work in a
subfolder is therefore found. Verified on a Codex test bench on 2026-08-14.

## Symptom, cause, action

| Symptom | Likely cause | What to do |
|---|---|---|
| Empty loop on a plugin install | `CLAUDE_PLUGIN_ROOT` not set | go through the user scope |
| Old version resolved | the marketplace clone won over the cache | rerun `claude plugin update` |
| Codex finds nothing | the skill is in `~/.claude/skills` and not in `~/.agents/skills` | copy it |
