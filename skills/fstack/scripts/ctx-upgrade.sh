#!/usr/bin/env bash
#
# ctx-upgrade.sh : brings a project's context convention up to version 5.
#
# Reads the starting version (0 to 4), prints a report, and writes only with --apply.
# Never deletes, never commits, never creates a branch. A second run changes nothing.
# What needs judgment (rules, skill copies, local script, agent profiles, MEMORY.md)
# is listed and proposed, never decided.
#
# Usage:
#   bash ctx-upgrade.sh [--root <path>] [--dry-run]
#   bash ctx-upgrade.sh [--root <path>] --apply
#
# Starting versions: 0 nothing, 1 four pillars with a root MEMORY.md, 2 three pillars without a
# block, 3 block without size:, 4 block with size:. A block already at version 5 is not rewritten,
# but the idempotent steps still run (orchestration lines, old names, lists to sort): run upgrade
# again after a plugin update. Nothing to do: no effect.
#
set -euf

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/ctx-common.sh"

ROOT=""
APPLY=0
DRY_EXPLICIT=0
TAB="$(printf '\t')"

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      if [ $# -lt 2 ] || [ -z "$2" ]; then echo "--root needs a path." >&2; exit 2; fi
      ROOT="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --dry-run)   DRY_EXPLICIT=1; shift ;;
    -h|--help)   sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [ "$APPLY" -eq 1 ] && [ "$DRY_EXPLICIT" -eq 1 ]; then
  echo "--apply and --dry-run are mutually exclusive." >&2
  exit 2
fi

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
[ -d "$ROOT" ] || { echo "Root not found: $ROOT" >&2; exit 1; }
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"
unset CTX_ROOT || true

scripts_version || exit 1

DATE="$(ctx_today)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ "$APPLY" -eq 1 ]; then
  MODE_TEXT="apply, writes are done"
  V_WRITTEN="written"
  V_REWRITTEN="rewritten"
else
  MODE_TEXT="dry run, nothing is written"
  V_WRITTEN="would be written"
  V_REWRITTEN="would be rewritten"
fi

# Overwrites a file with another one without changing its permissions.
replace_file() { # <source> <destination>
  cat "$1" > "$2"
}

# --- block reading ------------------------------------------------------------
# A parser apart from conv_read: it must also read a badly closed block, which the
# library does not, and say which lines the block spans.
CARRIER="$(conv_find)"
BLOCK_O=0
BLOCK_F=0
BLOCK_BAD=0
B_version=""; B_profile=""; B_pillars=""; B_docs=""; B_archives=""; B_language=""
B_log=""; B_thresholds=""; B_stale=""; B_exceptions=""; B_gaps=""
B_size=""; B_size_forced=""; B_unknown=""; B_names=""; B_raw=0

read_block() {
  [ -n "$CARRIER" ] || return 0
  # The block runs from the opening to the real -->. A `key: value` line is a field, any other
  # line (comment, key with _, capital or digit) goes unchanged under the key #raw, in order.
  # An empty line carries nothing and is ignored. Without --> before the next comment opening
  # or the end of the file, the block is badly closed: only the leading `key: value` lines are
  # kept, never the rest of the document.
  awk -v kv="$TMP/block.kv" -v meta="$TMP/block.meta" '
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function iskey(l) { return l ~ /^[a-z][a-z-]*:/ }
    function field(l,   p, k, v) {
      p = index(l, ":")
      k = trim(substr(l, 1, p - 1)); v = trim(substr(l, p + 1))
      if (!(k in seen)) { seen[k] = 1; print k "\t" v > kv; nf++ }
    }
    function line(l) {
      if (iskey(l)) field(l)
      else if (trim(l) != "") print "#raw\t" l > kv
    }
    { L[NR] = $0 }
    END {
      printf "" > kv
      O = 0
      for (i = 1; i <= NR; i++) {
        p = index(L[i], "<!-- contexte:convention")
        if (p > 0) { O = i; break }
      }
      if (O == 0) { print 0 "\t" 0 "\t" 0 > meta; exit }
      F = O; bad = 0; nf = 0
      rest = substr(L[O], p + length("<!-- contexte:convention"))
      if (index(rest, "-->") > 0) {
        c = O
      } else {
        c = 0
        for (i = O + 1; i <= NR; i++) {
          if (index(L[i], "<!--") > 0) break
          if (index(L[i], "-->") > 0) { c = i; break }
        }
      }
      if (c > O) {
        for (i = O + 1; i < c; i++) line(L[i])
        before = substr(L[c], 1, index(L[c], "-->") - 1)
        line(before)
        F = c
      }
      if (c == 0) {
        bad = 1
        for (i = O + 1; i <= NR; i++) {
          if (iskey(L[i])) { field(L[i]); F = i; continue }
          if (trim(L[i]) == "") continue
          break
        }
      } else if (c <= O + 1 && nf == 0) {
        # closing glued to the opening: fields may follow, outside the comment
        for (i = c + 1; i <= NR && iskey(L[i]); i++) { field(L[i]); F = i; bad = 1 }
      }
      print O "\t" F "\t" bad > meta
    }' "$CARRIER"
  [ -f "$TMP/block.meta" ] || return 0
  IFS="$TAB" read -r BLOCK_O BLOCK_F BLOCK_BAD < "$TMP/block.meta" || true
  local k v
  while IFS="$TAB" read -r k v; do
    [ -n "$k" ] || continue
    case "$k" in
      version) B_version="$v" ;;
      profil) B_profile="$v" ;;
      piliers) B_pillars="$v" ;;
      docs) B_docs="$v" ;;
      archives) B_archives="$v" ;;
      langue) B_language="$v" ;;
      journal) B_log="$v" ;;
      seuils) B_thresholds="$v" ;;
      ajourne) B_stale="$v" ;;
      exceptions) B_exceptions="$v" ;;
      ecarts) B_gaps="$v" ;;
      taille) B_size="$v" ;;
      taille-forcee) B_size_forced="$v" ;;
      '#raw') B_unknown="${B_unknown}${v}
"; B_raw=$((B_raw + 1)) ;;
      *) B_unknown="${B_unknown}${k}: ${v}
"; B_names="${B_names}${k} " ;;
    esac
  done < "$TMP/block.kv"
  return 0
}
read_block

# --- starting version ---------------------------------------------------------
PILLARS_PRESENT=""
PILLARS_ABSENT=""
NB_PILLARS=0
for p in CODEMAP.md TODOS.md CHANGELOG.md; do
  if [ -f "$p" ]; then
    PILLARS_PRESENT="$PILLARS_PRESENT $p"
    NB_PILLARS=$((NB_PILLARS + 1))
  else
    PILLARS_ABSENT="$PILLARS_ABSENT $p"
  fi
done

VERSION=0
if [ -n "$CARRIER" ]; then
  VERSION=""
  case "$B_version" in
    ''|*[!0-9]*) ;;
    *) VERSION="$B_version" ;;
  esac
  if [ -z "$VERSION" ]; then
    if [ -n "$B_size" ]; then VERSION=4; else VERSION=3; fi
  fi
elif [ -f MEMORY.md ] && [ "$NB_PILLARS" -ge 1 ]; then
  VERSION=1
elif [ "$NB_PILLARS" -eq 3 ]; then
  VERSION=2
fi

echo "Upgrade of the context convention"
echo "  root           : $ROOT"
echo "  mode           : $MODE_TEXT"
echo "  start version  : $VERSION"
echo "  target version : $CTX_VERSION"

# A block already at the target version is not rewritten, but the script no longer exits: the
# idempotent steps added since the upgrade must reach projects that are already upgraded.
V5=0
if [ "$VERSION" -ge "$CTX_VERSION" ]; then V5=1; fi

# Work happens on a branch, the operator merges. A warning, not a refusal.
warn_branch() {
  if [ "$APPLY" -eq 1 ] && git rev-parse --git-dir >/dev/null 2>&1; then
    BRANCH="$(git symbolic-ref --short -q HEAD 2>/dev/null || true)"
    case "$BRANCH" in
      main|master) echo "  [!] branch $BRANCH: the UPGRADE mode works on a branch of its own." ;;
    esac
    if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
      echo "  [!] tracked files are already modified, the upgrade diff will be mixed with theirs."
    fi
  fi
  return 0
}
if [ "$V5" -eq 0 ]; then warn_branch; fi

# --- measures -----------------------------------------------------------------
# Size and profile are those of ctx-init.sh, called as a dry run: one measuring rule for
# both scripts. Reads the new labels (size / profile) and the old ones (taille / profil).
MEASURED_SIZE=""
MEASURED_PROFILE=""
if [ "$V5" -eq 0 ] && [ -f "$SCRIPT_DIR/ctx-init.sh" ]; then
  bash "$SCRIPT_DIR/ctx-init.sh" --root "$ROOT" --dry-run > "$TMP/init.out" 2>/dev/null || true
  MEASURED_SIZE="$(sed -n -E 's/^  (size|taille) *: ([a-z]*),.*/\2/p' "$TMP/init.out" | sed -n '1p')"
  MEASURED_PROFILE="$(sed -n -E 's/^  (profile|profil) *: //p' "$TMP/init.out" | sed -n '1p')"
fi

first_dir() { # <candidates...>: first directory present, with a trailing slash
  local d
  for d in "$@"; do
    if [ -d "$d" ]; then printf '%s/\n' "$d"; return 0; fi
  done
  return 0
}

# --- existing conventions: gaps -----------------------------------------------
E_ADD=""
add_gap() { # <name> <justification>
  case "${B_gaps:-}" in *"$1="*) return 0 ;; esac
  E_ADD="${E_ADD}${E_ADD:+, }$1=$2"
  return 0
}

CONV_FOUND=""
find_conventions() {
  local f
  if [ -f MEMORY.md ]; then
    add_gap "MEMORY.md" "fourth pillar kept (justification to complete)"
    CONV_FOUND="${CONV_FOUND}  MEMORY.md: kept and declared, nothing is dissolved. Its content is split
    (decisions, pitfalls, preferences) only if the operator decides so, in the PR.
"
  fi
  for f in PROJECT.md TASKS.md ETAT.md; do
    if [ -f "$f" ]; then
      add_gap "$f" "project-specific scheme kept (justification to complete)"
      CONV_FOUND="${CONV_FOUND}  $f: existing scheme, kept and declared.
"
    fi
  done
  if [ -f AGENTS.md ]; then
    local carrier=0
    if [ ! -f CLAUDE.md ]; then
      carrier=1
    elif [ "$(wc -l < CLAUDE.md | tr -d ' ')" -lt 10 ] || grep -q '@AGENTS.md' CLAUDE.md 2>/dev/null; then
      carrier=1
    fi
    if [ "$carrier" -eq 1 ]; then
      add_gap "AGENTS.md" "carries the rules instead of CLAUDE.md (justification to complete)"
      CONV_FOUND="${CONV_FOUND}  AGENTS.md: carries the project rules, kept and declared.
"
    fi
  fi
  return 0
}
find_conventions

# --- local script that forks the audit: thresholds ----------------------------
THRESHOLDS_ADD=""
STALE_ADD=""
LOCAL_SCRIPTS=""
THRESHOLDS_READ=""
THRESHOLDS_NO_FILE=""

file_of_threshold() { # <VARIABLE_NAME>
  case "$1" in
    *CODEMAP*) echo CODEMAP.md ;;
    *TODOS*|*TODO*) echo TODOS.md ;;
    *CHANGELOG*) echo CHANGELOG.md ;;
    *CLAUDE*) echo CLAUDE.md ;;
    *AGENTS*) echo AGENTS.md ;;
    *MEMORY*) echo MEMORY.md ;;
  esac
  return 0
}

already_declared() { # <list a=b, c=d> <name>
  printf '%s\n' "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/=.*//; s/[[:space:]]*$//' \
    | grep -xF "$2" >/dev/null
}

# NAME=number lines whose name talks about a threshold: SEUIL, MAX_..., LIMITE, BLOCAGE, AJOURN.
# The names stay French, they are what the projects' local scripts already use.
script_thresholds() { # <script>
  sed -n -E "s/^[[:space:]]*(export[[:space:]]+)?([A-Z_0-9]*(SEUIL|MAX|LIMITE|BLOCAGE|AJOURN)[A-Z_0-9]*)=[\"']?([0-9]+)[\"']?.*/\\2 \\4/p" "$1"
  return 0
}

read_local_scripts() {
  local s name val fic lus
  [ -d scripts ] || return 0
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    if grep -qi 'CODEMAP' "$s" 2>/dev/null && grep -qi 'TODOS' "$s" 2>/dev/null; then
      LOCAL_SCRIPTS="${LOCAL_SCRIPTS}${s}
"
      lus="$(script_thresholds "$s")"
      while read -r name val; do
        [ -n "$name" ] || continue
        fic="$(file_of_threshold "$name")"
        if [ -z "$fic" ]; then
          THRESHOLDS_NO_FILE="${THRESHOLDS_NO_FILE}${s}: ${name}=${val}
"
          continue
        fi
        case "$name" in
          *AJOURN*)
            if already_declared "$B_stale" "$fic" || already_declared "$STALE_ADD" "$fic"; then continue; fi
            STALE_ADD="${STALE_ADD}${STALE_ADD:+, }$fic=$val@$DATE"
            THRESHOLDS_READ="${THRESHOLDS_READ}${s}: ${name}=${val} -> ajourne: $fic=$val@$DATE
"
            ;;
          *)
            if already_declared "$B_thresholds" "$fic" || already_declared "$THRESHOLDS_ADD" "$fic"; then continue; fi
            THRESHOLDS_ADD="${THRESHOLDS_ADD}${THRESHOLDS_ADD:+, }$fic=$val"
            THRESHOLDS_READ="${THRESHOLDS_READ}${s}: ${name}=${val} -> seuils: $fic=$val
"
            ;;
        esac
      done <<END_LIST
$lus
END_LIST
    fi
  done <<END_LIST
$(find scripts -maxdepth 1 -type f -name '*.sh' 2>/dev/null | LC_ALL=C sort)
END_LIST
  return 0
}
read_local_scripts

# --- building the block -------------------------------------------------------
merge_lists() { # <existing> <additions>
  if [ -n "$1" ] && [ -n "$2" ]; then printf '%s, %s' "$1" "$2"
  elif [ -n "$1" ]; then printf '%s' "$1"
  else printf '%s' "$2"; fi
  return 0
}

NOTES=""
note() { NOTES="${NOTES}  $1
"; return 0; }

N_profile="$B_profile"
if [ -z "$N_profile" ] && [ -n "$MEASURED_PROFILE" ]; then
  N_profile="$MEASURED_PROFILE"
  note "+ profil: $N_profile (detected like ctx-init.sh does)"
fi
N_pillars="$B_pillars"
if [ -z "$N_pillars" ]; then
  N_pillars="CODEMAP.md, TODOS.md, CHANGELOG.md"
  note "+ piliers: the three by default"
fi
N_docs="$B_docs"
if [ -z "$N_docs" ]; then
  N_docs="$(first_dir docs doc documentation)"
  [ -n "$N_docs" ] || N_docs="docs/"
  note "+ docs: $N_docs"
fi
N_archives="$B_archives"
if [ -z "$N_archives" ]; then
  N_archives="$(first_dir archives archive)"
  [ -n "$N_archives" ] || N_archives="archives/"
  note "+ archives: $N_archives"
fi
N_language="$B_language"
if [ -z "$N_language" ]; then
  N_language="$(detect_language)"
  note "+ langue: $N_language (guessed from CLAUDE.md and CODEMAP.md, to check)"
fi
N_thresholds="$(merge_lists "$B_thresholds" "$THRESHOLDS_ADD")"
[ -z "$THRESHOLDS_ADD" ] || note "+ seuils: $THRESHOLDS_ADD (read from the local script)"
N_stale="$(merge_lists "$B_stale" "$STALE_ADD")"
[ -z "$STALE_ADD" ] || note "+ ajourne: $STALE_ADD (read from the local script, upgrade date)"
N_gaps="$(merge_lists "$B_gaps" "$E_ADD")"
[ -z "$E_ADD" ] || note "+ ecarts: gap(s) declared for $(printf '%s' "$E_ADD" | sed 's/=[^,]*//g')"

N_size_forced="$B_size_forced"
if [ -n "$B_size" ]; then
  if [ -n "$MEASURED_SIZE" ] && [ "$B_size" = "$MEASURED_SIZE" ]; then
    note "- taille: $B_size removed, the measure gives the same"
  elif [ -z "$B_size_forced" ]; then
    N_size_forced="$B_size"
    if [ -n "$MEASURED_SIZE" ]; then
      note "~ taille: $B_size becomes taille-forcee, the measure gives $MEASURED_SIZE (to confirm, else remove it)"
    else
      note "~ taille: $B_size becomes taille-forcee, the measure could not be made"
    fi
  else
    note "- taille: $B_size removed, taille-forcee: $B_size_forced already exists"
  fi
fi
if [ -n "$B_version" ]; then
  note "~ version: $B_version becomes $CTX_VERSION"
else
  note "+ version: $CTX_VERSION (the block carried none)"
fi
if [ "$BLOCK_BAD" -eq 1 ]; then
  note "! badly closed block, repaired: the closing --> is put back after the last field, the fields are inside the comment"
fi
if [ -n "$B_names" ]; then
  note "= unknown key(s) kept as they are: $B_names"
fi
if [ "$B_raw" -gt 0 ]; then
  note "= $B_raw line(s) outside the schema (comment, key with _ or capital) kept as they are in the block"
fi

{
  echo "<!-- contexte:convention"
  echo "version: $CTX_VERSION"
  [ -z "$N_profile" ] || echo "profil: $N_profile"
  echo "piliers: $N_pillars"
  echo "docs: $N_docs"
  echo "archives: $N_archives"
  echo "langue: $N_language"
  [ -z "$B_log" ] || echo "journal: $B_log"
  [ -z "$N_thresholds" ] || echo "seuils: $N_thresholds"
  [ -z "$N_stale" ] || echo "ajourne: $N_stale"
  [ -z "$B_exceptions" ] || echo "exceptions: $B_exceptions"
  [ -z "$N_gaps" ] || echo "ecarts: $N_gaps"
  [ -z "$N_size_forced" ] || echo "taille-forcee: $N_size_forced"
  [ -z "$B_unknown" ] || printf '%s' "$B_unknown"
  echo "-->"
} > "$TMP/block.new"

# Where the block goes. The file that already carries it, else CODEMAP.md, else the rules
# carrier. A project with none of these files has nothing to upgrade, that is ctx-init.sh.
BLOCK_TARGET=""
if [ -n "$CARRIER" ]; then
  BLOCK_TARGET="$CARRIER"
elif [ "$VERSION" -ge 1 ]; then
  for f in CODEMAP.md CLAUDE.md AGENTS.md; do
    if [ -f "$f" ]; then BLOCK_TARGET="$f"; break; fi
  done
fi

# --- .claude/rules: globs: to paths: ------------------------------------------
cat > "$TMP/globs.awk" <<'AWK'
function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function unquote(s,   c) {
  c = substr(s, 1, 1)
  if (length(s) >= 2 && (c == "\"" || c == "'") && substr(s, length(s), 1) == c \
      && index(substr(s, 2, length(s) - 2), c) == 0) return substr(s, 2, length(s) - 2)
  return s
}
function item(s) {
  s = trim(s)
  s = unquote(s)
  if (substr(s, 1, 1) == "\"" && substr(s, length(s), 1) == "\"") s = substr(s, 2, length(s) - 2)
  if (substr(s, 1, 1) == "'" && substr(s, length(s), 1) == "'") s = substr(s, 2, length(s) - 2)
  return "  - \"" s "\""
}
NR == 1 && $0 == "---" { fm = 1; print; next }
fm == 1 && $0 == "---" { fm = 2; print; next }
fm == 1 && $0 ~ /^globs:/ {
  v = trim(substr($0, 7))
  print "paths:"
  if (v == "") next
  if (v ~ /^\[.*\]$/) v = substr(v, 2, length(v) - 2)
  v = unquote(trim(v))
  depth = 0; cur = ""
  for (i = 1; i <= length(v); i++) {
    c = substr(v, i, 1)
    if (c == "{") depth++
    if (c == "}") depth--
    if (c == "," && depth == 0) { if (trim(cur) != "") print item(cur); cur = "" }
    else cur = cur c
  }
  if (trim(cur) != "") print item(cur)
  next
}
{ print }
AWK

RULES_GLOBS=""
RULES_HAVE_PATHS=""
list_rules() {
  local r
  [ -d .claude/rules ] || return 0
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    r="${r#./}"
    if awk 'NR == 1 && $0 != "---" { exit 1 }
            NR > 1 && $0 == "---" { exit f ? 0 : 1 }
            /^globs:/ { f = 1 }
            END { exit f ? 0 : 1 }' "$r" 2>/dev/null; then
      if awk 'NR > 1 && $0 == "---" { exit }
              /^paths:/ { f = 1 }
              END { exit f ? 0 : 1 }' "$r" 2>/dev/null; then
        RULES_HAVE_PATHS="${RULES_HAVE_PATHS}${r}
"
      else
        RULES_GLOBS="${RULES_GLOBS}${r}
"
      fi
    fi
  done <<END_LIST
$(find .claude/rules -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)
END_LIST
  return 0
}
list_rules

# --- local copies of skills ---------------------------------------------------
# The names are those of the old plugins, they are what old projects carry.
COPIES=""
list_copies() {
  local base name p
  for base in .claude/skills skills .opencode/skills .agents/skills marketplace/plugins; do
    for name in cloture-session relance plan-prompt plan-review deep-plan clawd-audit-md; do
      p="$base/$name"
      if [ -e "$p" ]; then COPIES="${COPIES}${p}
"; fi
    done
  done
  for name in cloture-session plan-review relance audit-md cloture init-contexte reprise-session; do
    p=".claude/commands/$name.md"
    if [ -e "$p" ]; then COPIES="${COPIES}${p}
"; fi
  done
  return 0
}
list_copies

# --- old names cited in CLAUDE.md and AGENTS.md -------------------------------
# Three series, rewritten straight to the final name: the commands of the pre-fstack plugins,
# the clawd-stack: names (the plugin was called clawd-stack until 1.0.0-rc.3), the old French
# fstack names (commands, agents, scripts). The script names use a looser left boundary, so
# a path like scripts/ctx-verite.sh is rewritten too.
cat > "$TMP/names.awk" <<'AWK'
function word(c) {
  return c != "" && index("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.:/~-", c) > 0
}
function leftword(c) {
  return c != "" && index("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-", c) > 0
}
function after_ok(r,   c1, c2) {
  c1 = substr(r, 1, 1)
  if (c1 == "") return 1
  if (index("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_/-:", c1) > 0) return 0
  if (c1 == ".") {
    c2 = substr(r, 2, 1)
    if (c2 != "" && index("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_", c2) > 0) return 0
  }
  return 1
}
function rewrite(l,   k, out, s, i, prev, rest, bad) {
  for (k = 1; k <= n; k++) {
    out = ""; s = l
    while ((i = index(s, P[k])) > 0) {
      prev = (i > 1) ? substr(s, i - 1, 1) : substr(out, length(out), 1)
      rest = substr(s, i + length(P[k]))
      bad = F[k] ? leftword(prev) : word(prev)
      if (!bad && after_ok(rest)) out = out substr(s, 1, i - 1) R[k]
      else out = out substr(s, 1, i - 1) P[k]
      s = rest
    }
    l = out s
  }
  return l
}
BEGIN {
  P[++n] = "/cloture-session:init-contexte";    R[n] = "/fstack:setup"
  P[n+1] = "/cloture-session:reprise-session";  R[n+1] = "/fstack:brief"; n++
  P[++n] = "/cloture-session:cloture";          R[n] = "/fstack:debrief"
  P[++n] = "/deep-plan:planifier";              R[n] = "/fstack:plan"
  P[++n] = "/clawd-audit-md:audit-md";          R[n] = "/fstack:check"
  P[++n] = "/init-contexte";                    R[n] = "/fstack:setup"
  P[++n] = "/reprise-session";                  R[n] = "/fstack:brief"
  P[++n] = "/audit-md";                         R[n] = "/fstack:check"
  P[++n] = "/planifier";                        R[n] = "/fstack:plan"
  P[++n] = "/cloture";                          R[n] = "/fstack:debrief"
  # clawd-stack: straight to the final name. The slash is handled apart, word() refuses a "/"
  # right before the pattern.
  k = split("init relance cloture planifier audit migrer orchestration clawd-stack chercheur controleur developpeur executant expert explorateur relecteur setup brief debrief plan check upgrade researcher tester builder runner explorer reviewer", A, " ")
  split("setup brief debrief plan check upgrade orchestration fstack researcher tester builder runner expert explorer reviewer setup brief debrief plan check upgrade researcher tester builder runner explorer reviewer", C, " ")
  for (j = 1; j <= k; j++) {
    P[++n] = "/clawd-stack:" A[j];  R[n] = "/fstack:" C[j]
    P[++n] = "clawd-stack:" A[j];   R[n] = "fstack:" C[j]
  }
  P[++n] = "clawd-stack:<profil>";              R[n] = "fstack:<profil>"
  P[++n] = "clawd-stack:<profile>";             R[n] = "fstack:<profile>"
  # Old French fstack names: the six commands and the six renamed agents. fstack:expert and
  # fstack:<profil> stay as they are.
  k = split("init relance cloture planifier audit migrer chercheur controleur developpeur executant explorateur relecteur", A, " ")
  split("setup brief debrief plan check upgrade researcher tester builder runner explorer reviewer", C, " ")
  for (j = 1; j <= k; j++) {
    P[++n] = "/fstack:" A[j];  R[n] = "/fstack:" C[j]
    P[++n] = "fstack:" A[j];   R[n] = "fstack:" C[j]
  }
  # The seven renamed scripts.
  k = split("ctx-verite.sh ctx-migrer.sh ctx-demarrage.sh ctx-commun.sh ctx-archeo.sh verif-agents.sh verif-refs.sh", A, " ")
  split("ctx-truth.sh ctx-upgrade.sh ctx-startup.sh ctx-common.sh ctx-archaeology.sh check-agents.sh check-refs.sh", C, " ")
  for (j = 1; j <= k; j++) { P[++n] = A[j]; R[n] = C[j]; F[n] = 1 }
  printf "" > rep
}
{
  changed = rewrite($0)
  if (changed != $0) { print NR ": " $0 "  ->  " changed >> rep; chg++ }
  print changed
}
END { close(rep) }
AWK

FILES_RENAMED=""
rewrite_names() {
  local f sm skip i=0 subs list
  subs="$(submodules)"
  # exclusions_prune gives patterns the shell must not expand: set -f is on, no quotes
  # shellcheck disable=SC2046
  list="$(find . -maxdepth 4 $(exclusions_prune) -o -type f \( -name CLAUDE.md -o -name AGENTS.md \) -print 2>/dev/null | LC_ALL=C sort)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    f="${f#./}"
    skip=0
    while IFS= read -r sm; do
      [ -n "$sm" ] || continue
      case "$f" in "$sm"/*) skip=1 ;; esac
    done <<END_LIST
$subs
END_LIST
    [ "$skip" -eq 0 ] || continue
    i=$((i + 1))
    awk -v rep="$TMP/rep.$i" -f "$TMP/names.awk" "$f" > "$TMP/cmd.$i"
    if ! cmp -s "$f" "$TMP/cmd.$i"; then
      FILES_RENAMED="${FILES_RENAMED}${f}${TAB}${i}
"
    fi
  done <<END_LIST
$list
END_LIST
  return 0
}
rewrite_names

# --- local agent profiles -----------------------------------------------------
LOCAL_AGENTS=""
model_pinned() { # <value of the model field>
  case "$1" in
    claude-*|*anthropic*|*-[0-9]*) return 0 ;;
  esac
  return 1
}
list_agents() {
  local a name model reason
  [ -d .claude/agents ] || return 0
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    name="$(basename "$a" .md)"
    model="$(awk 'NR == 1 && $0 != "---" { exit }
                   NR > 1 && $0 == "---" { exit }
                   /^model:/ { sub(/^model:[ \t]*/, ""); gsub(/["'"'"'\r]/, ""); print; exit }' "$a")"
    reason=""
    case "$name" in syz-*|gz-*) reason="local profile ($name)" ;; esac
    if [ -n "$model" ] && model_pinned "$model"; then
      reason="${reason}${reason:+, }pinned model: $model"
    fi
    if [ -n "$reason" ]; then
      LOCAL_AGENTS="${LOCAL_AGENTS}${a}: ${reason}
"
    fi
  done <<END_LIST
$(find .claude/agents -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)
END_LIST
  return 0
}
list_agents

# ==============================================================================
# Report
# ==============================================================================
echo
echo "Block contexte:convention"
if [ -n "$CARRIER" ]; then
  echo "  carrier: $CARRIER, lines $BLOCK_O to $BLOCK_F"
else
  echo "  no block in the root files"
fi
[ -z "$PILLARS_PRESENT" ] || echo "  pillars present :$PILLARS_PRESENT"
[ -z "$PILLARS_ABSENT" ] || echo "  pillars absent  :$PILLARS_ABSENT"
if [ -n "$MEASURED_SIZE" ]; then echo "  measured size   : $MEASURED_SIZE"; fi

BLOCK_WRITTEN=0
if [ "$V5" -eq 1 ]; then
  echo "  block already at version $CTX_VERSION, not rewritten"
elif [ "$VERSION" -eq 0 ] && [ -z "$CARRIER" ]; then
  echo "  [!] no convention: the block is not placed here. ctx-init.sh installs the kit"
  echo "      and the block at version $CTX_VERSION, it is the right tool for this project."
elif [ -z "$BLOCK_TARGET" ]; then
  echo "  [!] no file to carry the block (neither CODEMAP.md, nor CLAUDE.md, nor AGENTS.md)."
  echo "      ctx-init.sh creates the kit, run the upgrade again afterwards."
else
  if [ -z "$CARRIER" ] && [ "$BLOCK_TARGET" != "CODEMAP.md" ]; then
    echo "  [!] CODEMAP.md missing: the block is placed in $BLOCK_TARGET. When CODEMAP.md is created,"
    echo "      the block goes at the top of that file, one block per project."
  fi
  BLOCK_WRITTEN=1
  echo "  block at version $CTX_VERSION, $V_WRITTEN in $BLOCK_TARGET:"
  sed 's/^/    | /' "$TMP/block.new"
  printf '%s' "$NOTES"
fi

if [ "$V5" -eq 0 ] && [ -n "$CONV_FOUND" ]; then
  echo
  echo "Existing conventions, declared in ecarts: and not dissolved"
  printf '%s' "$CONV_FOUND"
fi

if [ -n "$RULES_GLOBS" ] || [ -n "$RULES_HAVE_PATHS" ]; then
  echo
  echo "Rules in .claude/rules: globs: to paths:, PROPOSED, never applied by this script"
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    awk -f "$TMP/globs.awk" "$r" > "$TMP/rule.new"
    echo "  $r"
    diff -u -L "a/$r" -L "b/$r" "$r" "$TMP/rule.new" | sed 's/^/    /' || true
  done <<END_LIST
$RULES_GLOBS
END_LIST
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    echo "  $r: carries globs: AND paths:, remove globs: by hand"
  done <<END_LIST
$RULES_HAVE_PATHS
END_LIST
fi

if [ -n "$COPIES" ]; then
  echo
  echo "Local copies of skills and commands, TO REMOVE in the PR (nothing is deleted here)"
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    if [ -d "$c" ]; then
      printf '  %s (%s file(s))\n' "$c" "$(find "$c" -type f | wc -l | tr -d ' ')"
    else
      printf '  %s\n' "$c"
      printf '    to remove a file: bash %s/ctx-archive.sh %s --reason "replaced by fstack"\n' "$SCRIPT_DIR" "$c"
    fi
  done <<END_LIST
$COPIES
END_LIST
  echo "  Check before removing that no copy carries a project-specific setting."
fi

if [ -n "$LOCAL_SCRIPTS" ]; then
  echo
  echo "Local script that forks the audit, TO REMOVE once its thresholds are carried over"
  printf '%s' "$LOCAL_SCRIPTS" | sed 's/^/  /'
  if [ -n "$THRESHOLDS_READ" ]; then
    if [ "$V5" -eq 1 ]; then
      echo "  thresholds read, missing from the block, to carry over by hand:"
    else
      echo "  thresholds read:"
    fi
    printf '%s' "$THRESHOLDS_READ" | sed 's/^/    /'
  fi
  if [ -n "$THRESHOLDS_NO_FILE" ]; then
    echo "  thresholds read with no known file, to carry over by hand:"
    printf '%s' "$THRESHOLDS_NO_FILE" | sed 's/^/    /'
  fi
  if [ -z "$THRESHOLDS_READ" ] && [ -z "$THRESHOLDS_NO_FILE" ]; then
    if [ "$V5" -eq 1 ]; then
      echo "  no threshold to carry over (already in the block, or none simple to read)."
    else
      echo "  no threshold simple to read: carry them over by hand."
    fi
  fi
  echo "  The rest of its logic (project-specific checks) is to review by hand."
fi

if [ -n "$FILES_RENAMED" ]; then
  echo
  echo "Old names cited in CLAUDE.md and AGENTS.md, $V_REWRITTEN to the current /fstack:* names"
  while IFS="$TAB" read -r f i; do
    [ -n "$f" ] || continue
    printf '  %s: %s line(s)\n' "$f" "$(wc -l < "$TMP/rep.$i" | tr -d ' ')"
    head -n 10 "$TMP/rep.$i" | cut -c1-170 | sed 's/^/    /'
  done <<END_LIST
$FILES_RENAMED
END_LIST
fi

if [ -n "$LOCAL_AGENTS" ]; then
  echo
  echo "Local agent profiles, PROPOSED, nothing is deleted or declared"
  printf '%s' "$LOCAL_AGENTS" | sed 's/^/  /'
  echo "  Either replace them with the skill's agent profiles (explorer, tester, runner,"
  echo "  builder, researcher, expert, reviewer), or declare them in ecarts: with"
  echo "  a line like: ecarts: agents=<names>: local profiles kept (justification to complete)"
fi

# The three orchestration lines of the template, added to the project's CLAUDE.md (AGENTS.md
# failing that). The fstack:orchestration marker, or the old clawd-stack:orchestration one,
# makes the step idempotent.
TPL_SNIPPET="$SCRIPT_DIR/../templates/CLAUDE-snippet.md"
ORCH_TARGET=""
for f in CLAUDE.md AGENTS.md; do
  if [ -f "$f" ]; then ORCH_TARGET="$f"; break; fi
done
ORCH_TO_ADD=0
if [ ! -f "$TPL_SNIPPET" ] || ! grep -q "fstack:orchestration" "$TPL_SNIPPET"; then
  [ "$V5" -eq 1 ] || { echo; echo "Orchestration"; echo "  template without an orchestration block, nothing to add"; }
elif [ "$V5" -eq 0 ] && [ "$BLOCK_WRITTEN" -ne 1 ]; then
  echo; echo "Orchestration"; echo "  no upgrade here, nothing to add"
elif [ -z "$ORCH_TARGET" ]; then
  # On a block already at version 5, a project with neither CLAUDE.md nor AGENTS.md is the check's business.
  [ "$V5" -eq 1 ] || { echo; echo "Orchestration"; echo "  [!] neither CLAUDE.md nor AGENTS.md: three lines not added, ctx-init.sh creates the file"; }
elif grep -qE "(fstack|clawd-stack):orchestration" "$ORCH_TARGET"; then
  [ "$V5" -eq 1 ] || { echo; echo "Orchestration"; echo "  = $ORCH_TARGET already has the orchestration lines"; }
else
  ORCH_TO_ADD=1
  echo; echo "Orchestration"
  echo "  three orchestration lines, $V_WRITTEN at the end of $ORCH_TARGET"
fi

# ==============================================================================
# Writing
# ==============================================================================
# The files touched, counted once each, in dry run as in apply.
TO_WRITE=""
mark_written() { # <file>
  local m="${1#./}"
  case "
$TO_WRITE" in *"
$m
"*) return 0 ;; esac
  TO_WRITE="${TO_WRITE}${m}
"
  return 0
}
if [ "$BLOCK_WRITTEN" -eq 1 ]; then mark_written "$BLOCK_TARGET"; fi
while IFS="$TAB" read -r f i; do
  [ -n "$f" ] || continue
  mark_written "$f"
done <<END_LIST
$FILES_RENAMED
END_LIST
if [ "$ORCH_TO_ADD" -eq 1 ]; then mark_written "$ORCH_TARGET"; fi
NB_WRITTEN="$(printf '%s' "$TO_WRITE" | grep -c . || true)"

NB_DECISIONS=0
for list in "$RULES_GLOBS" "$RULES_HAVE_PATHS" "$COPIES" "$LOCAL_SCRIPTS" "$LOCAL_AGENTS"; do
  if [ -n "$list" ]; then NB_DECISIONS=$((NB_DECISIONS + 1)); fi
done
if [ "$V5" -eq 0 ] && [ -n "$CONV_FOUND" ]; then NB_DECISIONS=$((NB_DECISIONS + 1)); fi

# A block already up to date, no step to take, nothing to sort: say so and leave.
if [ "$V5" -eq 1 ] && [ "$NB_WRITTEN" -eq 0 ] && [ "$NB_DECISIONS" -eq 0 ]; then
  echo
  echo "The block is already at version $CTX_VERSION, nothing to do."
  exit 0
fi

if [ "$V5" -eq 1 ] && [ "$NB_WRITTEN" -gt 0 ]; then warn_branch; fi

if [ "$APPLY" -eq 1 ]; then
  CMD_DONE=""
  if [ "$BLOCK_WRITTEN" -eq 1 ]; then
    # If the file that carries the block also cites old names, the block is placed from the
    # already rewritten version: both steps compose into a single write.
    # The renaming keeps line numbers, BLOCK_O and BLOCK_F stay right.
    BLOCK_BASE="$BLOCK_TARGET"
    while IFS="$TAB" read -r f i; do
      [ -n "$f" ] || continue
      if [ "$f" = "${BLOCK_TARGET#./}" ]; then BLOCK_BASE="$TMP/cmd.$i"; CMD_DONE="$i"; fi
    done <<END_LIST
$FILES_RENAMED
END_LIST
    if [ -n "$CARRIER" ]; then
      awk -v O="$BLOCK_O" -v F="$BLOCK_F" -v nf="$TMP/block.new" '
        NR == O { while ((getline l < nf) > 0) print l; close(nf) }
        NR < O || NR > F { print }' "$BLOCK_BASE" > "$TMP/carrier.new"
    else
      { cat "$TMP/block.new"; echo; cat "$BLOCK_BASE"; } > "$TMP/carrier.new"
    fi
    replace_file "$TMP/carrier.new" "$BLOCK_TARGET"
  fi
  while IFS="$TAB" read -r f i; do
    [ -n "$f" ] || continue
    [ "$i" != "$CMD_DONE" ] || continue
    replace_file "$TMP/cmd.$i" "$f"
  done <<END_LIST
$FILES_RENAMED
END_LIST
  if [ "$ORCH_TO_ADD" -eq 1 ]; then
    { cat "$ORCH_TARGET"; echo; sed -n '/fstack:orchestration/,$p' "$TPL_SNIPPET"; } > "$TMP/orch.new"
    replace_file "$TMP/orch.new" "$ORCH_TARGET"
  fi
fi

echo
if [ "$APPLY" -eq 1 ]; then
  echo "Summary: $NB_WRITTEN file(s) written, $NB_DECISIONS point(s) left to the operator."
  echo "Nothing is committed. A second --apply changes nothing."
elif [ "$V5" -eq 1 ] && [ "$NB_WRITTEN" -eq 0 ]; then
  echo "Summary: no write to make, $NB_DECISIONS point(s) remain for the operator."
else
  echo "Summary: dry run, nothing was written. $NB_DECISIONS point(s) remain for the operator."
  echo "Review this report with them, then run again with --apply."
fi
if [ "$V5" -eq 0 ]; then
  echo "Next: a full debrief of the project, then the operator opens the PR."
fi
exit 0
