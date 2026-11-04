#!/usr/bin/env bash
#
# ctx-init.sh : installs the context convention in a project.
#
# Non-destructive. A file that already exists is NEVER touched.
# Usage:
#   bash ctx-init.sh [--root <path>] [--profile <profile>] [--dry-run] [--with-claude]
#   bash ctx-init.sh --zone <directory> [--with-claude] [--dry-run]
#
# --zone: puts a zone map, <directory>/CODEMAP.md, from the template. With
#         --with-claude, also puts <directory>/CLAUDE.md, the zone rules.
#         Does not touch the root pillars.
#
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TPL="$SKILL_DIR/templates"

. "$SCRIPT_DIR/ctx-common.sh"

ROOT=""
PROFILE=""
ZONE=""
DRY=0
WITH_CLAUDE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --root)        ROOT="${2:-}"; shift 2 ;;
    --profile)      PROFILE="${2:-}"; shift 2 ;;
    --zone)        ZONE="${2:-}"; shift 2 ;;
    --dry-run)     DRY=1; shift ;;
    --with-claude) WITH_CLAUDE=1; shift ;;
    -h|--help)
      sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option : $1" >&2; exit 2 ;;
  esac
done

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
[ -d "$ROOT" ] || { echo "Root not found : $ROOT" >&2; exit 1; }
ROOT="$(cd "$ROOT" && pwd)"

# A block newer than these scripts: refuse before writing anything.
CTX_ROOT="$ROOT"
scripts_version || exit 1

DATE="$(ctx_today)"
PROJECT_NAME="$(basename "$ROOT")"

# Language of the block: guessed from the project texts, en when there is nothing to read.
LANGUAGE=en
for f in CLAUDE.md CODEMAP.md README.md; do
  [ -f "$ROOT/$f" ] && { LANGUAGE="$(cd "$ROOT" && detect_language)"; break; }
done

# --- profile detection ------------------------------------------------------
# An entry of the root, case-sensitive. On a case-insensitive file system
# (macOS by default), `[ -d packages ]` says yes for the Packages/ of a Unity project.
has_entry() { # <root> <name>
  # The glob returns names as written on disk, so the comparison is case-sensitive.
  local e
  for e in "$1"/* "$1"/.[!.]*; do
    [ "${e##*/}" = "$2" ] && return 0
  done
  return 1
}

# At least one file of the root that matches the pattern (shell glob).
has_pattern() { # <root> <pattern>
  local f
  for f in "$1"/$2; do [ -e "$f" ] && return 0; done
  return 1
}

# Order matters: from the most specific to the most general. A game engine or a mobile app
# also carries a package.json or a Cargo.toml, so they come before app and monorepo.
detect_profile() {
  local r="$1"
  if has_pattern "$r" '.claude-plugin/plugin.json' || [ -f "$r/SKILL.md" ] || [ -d "$r/.claude/skills" ] \
     || [ -f "$r/plugin.json" ] || has_pattern "$r" 'skills/*/SKILL.md'; then
    echo outillage-agent; return
  fi
  if [ -f "$r/ProjectSettings/ProjectVersion.txt" ] || [ -f "$r/project.godot" ] \
     || has_pattern "$r" '*.uproject'; then
    echo jeu; return
  fi
  if [ -f "$r/pubspec.yaml" ] || { has_entry "$r" android && has_entry "$r" ios; } \
     || has_pattern "$r" '*.xcodeproj' || [ -f "$r/app/src/main/AndroidManifest.xml" ]; then
    echo mobile; return
  fi
  if [ -f "$r/pnpm-workspace.yaml" ] || [ -f "$r/turbo.json" ] || [ -f "$r/go.work" ] \
     || [ -f "$r/nx.json" ] || [ -f "$r/lerna.json" ] || has_entry "$r" packages || has_entry "$r" apps; then
    echo monorepo; return
  fi
  if [ -d "$r/src-tauri" ] || { [ -f "$r/package.json" ] && grep -q '"electron"' "$r/package.json" 2>/dev/null; }; then
    echo desktop; return
  fi
  if has_entry "$r" terraform || has_entry "$r" ansible || has_entry "$r" k8s \
     || has_pattern "$r" '*.tf' || [ -f "$r/Chart.yaml" ]; then
    echo infra; return
  fi
  if has_entry "$r" notebooks || [ -f "$r/dvc.yaml" ] || has_pattern "$r" '*.ipynb'; then
    echo data; return
  fi
  # A library: a lib entry point without a program, or a package that exports
  # without running.
  if { [ -f "$r/Cargo.toml" ] && [ -f "$r/src/lib.rs" ] && [ ! -f "$r/src/main.rs" ]; } \
     || { [ -f "$r/package.json" ] && grep -qE '"(exports|types)"[[:space:]]*:' "$r/package.json" 2>/dev/null \
          && ! grep -qE '"(start|dev)"[[:space:]]*:' "$r/package.json" 2>/dev/null; }; then
    echo lib; return
  fi
  if [ -f "$r/package.json" ] || [ -f "$r/pyproject.toml" ] || [ -f "$r/go.mod" ] \
     || [ -f "$r/Cargo.toml" ] || [ -f "$r/manage.py" ] || [ -f "$r/pom.xml" ] \
     || [ -f "$r/build.gradle" ] || [ -f "$r/build.gradle.kts" ] || [ -f "$r/composer.json" ] \
     || [ -f "$r/Gemfile" ] || [ -f "$r/mix.exs" ] || [ -f "$r/Package.swift" ] \
     || [ -f "$r/deno.json" ] || [ -f "$r/CMakeLists.txt" ] || has_pattern "$r" '*.sln' \
     || has_pattern "$r" '*.csproj' || [ -f "$r/requirements.txt" ]; then
    echo app; return
  fi
  if has_entry "$r" content || has_entry "$r" posts; then
    echo contenu; return
  fi
  echo non-technique
}

# --- project size, in files outside dependencies ---------------------------
# The same exclusions as ctx-audit.sh, both must count the same.
detect_size() {
  local r="$1" n
  # set -f: exclusions_prune returns patterns the shell must not expand. With pruning,
  # find does not descend into an engine Library/ or a node_modules.
  n="$(cd "$r" && set -f && find . $(exclusions_prune) -o -type f -print 2>/dev/null | wc -l | tr -d ' ')"
  if   [ "$n" -lt 150 ]; then echo "petite $n"
  elif [ "$n" -le 600 ]; then echo "moyenne $n"
  else echo "grande $n"; fi
}

[ -n "$PROFILE" ] || PROFILE="$(detect_profile "$ROOT")"
# The pruning list is computed once for the target root, the size and the
# "pruning" line below reread it from memory.
CTX_ROOT="$ROOT" exclusions_load
SIZE_AND_COUNT="$(detect_size "$ROOT")"
SIZE="${SIZE_AND_COUNT%% *}"
FILE_COUNT="${SIZE_AND_COUNT#* }"

# --- the terrain ---------------------------------------------------------------
# We graft onto what exists. An already documented project has its doc directory,
# its rules carrier and sometimes another agent convention. Putting empty
# templates next to them would produce two sources of truth on day one.
DOCS_DIR=""
for d in docs doc documentation; do
  [ -d "$ROOT/$d" ] && { DOCS_DIR="$d"; break; }
done
DOCS_EXISTED=1
[ -n "$DOCS_DIR" ] || { DOCS_DIR="docs"; DOCS_EXISTED=0; }

ARCHIVES_DIR=""
for d in archives archive; do
  [ -d "$ROOT/$d" ] && { ARCHIVES_DIR="$d"; break; }
done
[ -n "$ARCHIVES_DIR" ] || ARCHIVES_DIR="archives"

# The rules carrier. CLAUDE.md if present, else AGENTS.md if present, else
# CLAUDE.md to create. A repository read by Codex alone need not receive a CLAUDE.md.
RULES="CLAUDE.md"
if [ ! -f "$ROOT/CLAUDE.md" ] && [ -f "$ROOT/AGENTS.md" ]; then
  RULES="AGENTS.md"
fi

# The four subdirectories of docs/ are created only if the directory is new,
# empty, or already of that shape. Otherwise the existing structure is left alone.
CREATE_SUBDOCS=1
if [ "$DOCS_EXISTED" -eq 1 ]; then
  CREATE_SUBDOCS=0
  for d in modules features ops decisions; do
    [ -d "$ROOT/$DOCS_DIR/$d" ] && CREATE_SUBDOCS=1
  done
  [ -z "$(ls -A "$ROOT/$DOCS_DIR" 2>/dev/null)" ] && CREATE_SUBDOCS=1
fi

ADR_DIRS=""
for d in adr "$DOCS_DIR/adr" "$DOCS_DIR/decisions" "$DOCS_DIR/architecture/decisions"; do
  [ -d "$ROOT/$d" ] && ADR_DIRS="$ADR_DIRS $d"
done
COMPETING=""
for c in AGENTS.md GEMINI.md .cursorrules .clinerules .windsurfrules CONVENTIONS.md \
         .github/copilot-instructions.md .cursor/rules memory-bank .roo MEMORY.md; do
  [ "$c" = "$RULES" ] && continue
  [ -e "$ROOT/$c" ] && COMPETING="$COMPETING $c"
done

# Where decisions go: the existing directory if there is one, else the
# convention's.
DECISIONS="$DOCS_DIR/decisions"
for d in $ADR_DIRS; do DECISIONS="$d"; break; done
ROOT_MD="$(cd "$ROOT" && find . -maxdepth 1 -name '*.md' 2>/dev/null | sed 's|^\./||' \
  | grep -vE '^(CODEMAP|TODOS|CHANGELOG|CLAUDE|AGENTS|README|MEMORY)\.md$' | sort | tr '\n' ' ' || true)"

# --- helpers ------------------------------------------------------------------
CREATED=0
SKIPPED=0

render() { # <source> <destination>
  local src="$1" dst="$2"
  if [ -e "$dst" ]; then
    printf '  = %-24s already present, untouched\n' "${dst#$ROOT/}"
    SKIPPED=$((SKIPPED + 1))
    return
  fi
  printf '  + %-24s created\n' "${dst#$ROOT/}"
  CREATED=$((CREATED + 1))
  [ "$DRY" -eq 1 ] && return
  mkdir -p "$(dirname "$dst")"
  sed -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
      -e "s|{{DATE}}|$DATE|g" \
      -e "s|{{PROFILE}}|$PROFILE|g" \
      -e "s|{{LANGUAGE}}|$LANGUAGE|g" \
      -e "s|{{ZONE}}|$ZONE|g" \
      -e "s|{{DOCS}}|$DOCS_DIR/|g" \
      -e "s|{{ARCHIVES}}|$ARCHIVES_DIR/|g" \
      "$src" > "$dst"
}

mkdirp() { # <path>
  if [ -d "$1" ]; then return; fi
  printf '  + %-24s created\n' "${1#$ROOT/}/"
  CREATED=$((CREATED + 1))
  [ "$DRY" -eq 1 ] && return
  mkdir -p "$1"
}

# --- mode zone ----------------------------------------------------------------
if [ -n "$ZONE" ]; then
  ZONE="${ZONE%/}"
  [ -d "$ROOT/$ZONE" ] || { echo "Zone not found : $ROOT/$ZONE" >&2; exit 1; }
  echo "Zone map"
  echo "  root    : $ROOT"
  echo "  zone    : $ZONE"
  [ "$DRY" -eq 1 ] && echo "  mode    : simulation, nothing will be written"
  echo
  render "$TPL/CODEMAP-zone.md" "$ROOT/$ZONE/CODEMAP.md"
  if [ "$WITH_CLAUDE" -eq 1 ]; then
    render "$TPL/CLAUDE-zone.md" "$ROOT/$ZONE/CLAUDE.md"
  else
    echo "  . $ZONE/CLAUDE.md not created, rerun with --with-claude if the zone has rules of its own"
  fi
  cat <<EOF

To do now:
  1. Fill $ZONE/CODEMAP.md from the real code of the zone: entry points, flow, pitfalls.
  2. Move into this map the sensitive areas of the root CODEMAP that talk about
     $ZONE, and the zone's own commands. Leave a pointer, not a copy.
  3. Add the zone to the "Zones" table of the root CODEMAP.
EOF
  exit 0
fi

# --- execution ----------------------------------------------------------------
echo "Context convention"
echo "  root    : $ROOT"
echo "  project : $PROJECT_NAME"
echo "  profile : $PROFILE"
echo "  size    : $SIZE, $FILE_COUNT files outside dependencies"
# A pruning is named: what does not count in the size above, beyond the fixed list.
EL_NOMS="$(exclusions_names_grouped | awk -F'\t' '
  $1 == "cap" { p = $3 " engine root(s) beyond the cap of 20"; next }
  { k = $1 ($2 != "-" && $2 != "." ? " (" $2 "/)" : "")
    if (!(k in l)) { o[++n] = k; l[k] = $3 } else l[k] = l[k] ", " $3 }
  END { for (i = 1; i <= n; i++) printf "%s%s %s", (i > 1 ? " ; " : ""), o[i], l[o[i]]
        if (p != "") printf "%s%s", (n > 0 ? " ; " : ""), p }')"
[ -z "$EL_NOMS" ] || echo "  pruning : $EL_NOMS"
[ "$DRY" -eq 1 ] && echo "  mode    : simulation, nothing will be written"
echo

echo "The terrain, what we graft onto"
if [ "$DOCS_EXISTED" -eq 1 ]; then
  echo "  = $DOCS_DIR/ already exists, the convention adopts it instead of creating another"
  [ "$CREATE_SUBDOCS" -eq 0 ] \
    && echo "    its structure is not the convention's, subdirectories will not be created"
else
  echo "  . no existing documentation, $DOCS_DIR/ will be created"
fi
echo "  . rules carrier : $RULES"
[ -n "$ADR_DIRS" ] && echo "  = decisions already somewhere:$ADR_DIRS"
[ -n "$ROOT_MD" ] && echo "  = markdown at the root, outside the kit: $ROOT_MD"
if [ -n "$COMPETING" ]; then
  echo "  ! competing conventions or memories:$COMPETING"
  echo "    to handle, otherwise two sources of truth. See the end of this message."
fi
echo

echo "Pillars"
render "$TPL/CODEMAP.md"   "$ROOT/CODEMAP.md"
render "$TPL/TODOS.md"     "$ROOT/TODOS.md"
render "$TPL/CHANGELOG.md" "$ROOT/CHANGELOG.md"
if [ "$DRY" -eq 1 ] && [ ! -e "$ROOT/CODEMAP.md" ]; then
  echo "  convention block the CODEMAP will receive:"
  sed -n '/<!-- contexte:convention/,/^-->/p' "$TPL/CODEMAP.md" \
    | sed -e "s|{{PROFILE}}|$PROFILE|g" -e "s|{{LANGUAGE}}|$LANGUAGE|g" -e "s|{{DOCS}}|$DOCS_DIR/|g" \
          -e "s|{{ARCHIVES}}|$ARCHIVES_DIR/|g" -e 's/^/    /'
fi

echo
echo "Documentation"
if [ "$CREATE_SUBDOCS" -eq 1 ]; then
  mkdirp "$ROOT/$DOCS_DIR/modules"
  mkdirp "$ROOT/$DOCS_DIR/features"
  mkdirp "$ROOT/$DOCS_DIR/ops"
  mkdirp "$ROOT/$DOCS_DIR/decisions"
else
  mkdirp "$ROOT/$DOCS_DIR"
  echo "  = subdirectories left as they are, the existing structure rules"
fi
render "$TPL/docs/README.md" "$ROOT/$DOCS_DIR/README.md"

echo
echo "Archives"
render "$TPL/archives/README.md" "$ROOT/$ARCHIVES_DIR/README.md"

echo
echo "Project rules"
if [ -f "$ROOT/$RULES" ]; then
  if grep -qE "Convention de contexte|Context convention" "$ROOT/$RULES" 2>/dev/null; then
    printf '  = %-24s already contains the convention\n' "$RULES"
    if ! grep -qE "(fstack|clawd-stack):orchestration" "$ROOT/$RULES" 2>/dev/null \
       && grep -q "fstack:orchestration" "$TPL/CLAUDE-snippet.md" 2>/dev/null; then
      printf '  ~ %-24s three orchestration lines added at the end\n' "$RULES"
      if [ "$DRY" -eq 0 ]; then
        printf '\n' >> "$ROOT/$RULES"
        sed -n '/fstack:orchestration/,$p' "$TPL/CLAUDE-snippet.md" >> "$ROOT/$RULES"
      fi
    fi
  elif [ "$WITH_CLAUDE" -eq 1 ]; then
    printf '  ~ %-24s convention block added at the end\n' "$RULES"
    if [ "$DRY" -eq 0 ]; then
      printf '\n' >> "$ROOT/$RULES"
      sed -e '/^<!--$/,/^-->$/d' \
          -e "s|docs/README.md|$DOCS_DIR/README.md|g" \
          -e "s|docs/decisions/|$DOCS_DIR/decisions/|g" \
          -e "s|\`archives/\`|\`$ARCHIVES_DIR/\`|g" \
          "$TPL/CLAUDE-snippet.md" >> "$ROOT/$RULES"
    fi
  else
    echo "  ! $RULES exists but does not mention the convention."
    echo "    Rerun with --with-claude, or paste by hand the block from:"
    echo "    $TPL/CLAUDE-snippet.md"
  fi
else
  printf '  + %-24s created\n' "$RULES"
  CREATED=$((CREATED + 1))
  if [ "$DRY" -eq 0 ]; then
    {
      echo "# $RULES, $PROJECT_NAME"
      echo
      sed -e '/^<!--$/,/^-->$/d' \
          -e "s|docs/README.md|$DOCS_DIR/README.md|g" \
          -e "s|docs/decisions/|$DOCS_DIR/decisions/|g" \
          -e "s|\`archives/\`|\`$ARCHIVES_DIR/\`|g" \
          "$TPL/CLAUDE-snippet.md"
    } > "$ROOT/$RULES"
  fi
fi

echo
echo "Summary: $CREATED created, $SKIPPED kept."
cat <<EOF

To do now, the templates are empty and useless as they are:
  1. Read the project before writing: tree, entry points, build, CI, latest commits.
EOF
if [ -n "$ROOT_MD" ] || [ "$DOCS_EXISTED" -eq 1 ]; then
  cat <<EOF
  2. Sort the docs that already exist. Each document has an owner in the convention:
     a map goes to the CODEMAP, a state goes to TODOS, a history to the CHANGELOG, a decision
     in $DECISIONS/, the rest as a page in $DOCS_DIR/. What is false goes to the archives,
     through ctx-archive.sh, never by deletion.
  3. Fill CODEMAP.md with the real map, pointing to what exists instead of copying it.
EOF
else
  cat <<EOF
  2. Check the contexte:convention block at the top of the CODEMAP, the script put the profile
     and the detected paths. This block makes the convention self-describing.
  3. Fill CODEMAP.md with the real map.
EOF
fi
cat <<EOF
  4. Fill TODOS.md with the real state, then the "Resume state" block, 40 lines at most.
  5. Create the pages of $DOCS_DIR/ for what deserves it, the criterion is in
     $SKILL_DIR/references/DOCS-SYSTEM.md. No empty page, no page for everything.
  6. Put in $RULES what must be true at every moment, and nothing else.
     No state, no story, no event date. Aim for 100 lines.
EOF
if [ "$SIZE" = grande ]; then
  cat <<EOF
  7. The project is LARGE. The root CODEMAP is an index that points, not a complete
     map. Put one map per zone right away, the candidates are in section
     10 of the audit:
       bash $SCRIPT_DIR/ctx-audit.sh --budget
       bash $SCRIPT_DIR/ctx-init.sh --zone <directory>
EOF
fi
if [ -n "$COMPETING" ]; then
  cat <<EOF

Competing conventions found:$COMPETING
  Two sources of truth always diverge, and nothing signals it when it happens.
  For each one, a single question: which one rules? The loser is archived, with its reason.
  Special cases. An AGENTS.md next to a CLAUDE.md is not read by the same agents,
  the link is an @AGENTS.md line at the top of CLAUDE.md. A MEMORY.md comes from an earlier
  version of this convention, its content is split: decisions to $DOCS_DIR/decisions/,
  pitfalls to the module page, preferences to $RULES, environment to the CODEMAP.
EOF
fi
echo
echo "Check drift and budget at any time: bash $SCRIPT_DIR/ctx-audit.sh"
echo "Search the archives without loading them: bash $SCRIPT_DIR/ctx-archaeology.sh <pattern>"
