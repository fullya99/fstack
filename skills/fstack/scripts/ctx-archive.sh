#!/usr/bin/env bash
#
# ctx-archive.sh: takes a document out of circulation, in one pass and without
# forgetting a step.
#
# The gesture used to be four steps by hand: git mv, header, index line, link fixing.
# The fourth is the one people forget, which is why the audit had to invent an alert
# to catch it. Here everything is done, or nothing.
#
# Usage:
#   bash ctx-archive.sh --verify <path>
#   bash ctx-archive.sh <path> --reason "..." [--replaced-by "..."] [--dry-run] [--force]
#   bash ctx-archive.sh <path> --reason "..." --summary <file> [--replaced-by "..."] [--dry-run]
#
# --summary: the file keeps its place as a summary. The full text goes to the archives,
# <file> is put at the old path, where {{ARCHIVE}} becomes the archive path. Incoming
# references stay valid, so they do not block, and the final check controls that the
# summary is in place. Called by ctx-rotation.sh --plans.
#
# The archiving criterion is about INCOMING REFERENCES, not about a feeling. For each
# reference: is it operative, does someone need the document to act now, or is it
# historical context, a comment that tells where something came from? We archive when
# all the remaining references are historical. A live markdown link to the document is
# operative by construction, it blocks, and --force is only for those who know why.
#
# The last step is a CHECK: no occurrence of the old path left outside the archives,
# otherwise exit with an error.
set -euf

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=ctx-common.sh
. "$DIR/ctx-common.sh"

# A literal backtick in shell code is a source of silent bugs.
# We build it once, we never type it.
BT="$(printf '\140')"
FENCE="$BT$BT$BT"

ROOT=""
TARGET=""
REASON=""
REPLACED=""
DRY=0
FORCE=0
VERIFY=0
SUMMARY=""

# An option with a value but no value: clear message and code 2, not a silent exit.
needs_value() { # <option> <number of remaining arguments, option included>
  if [ "$2" -lt 2 ]; then
    echo "$1 expects a value" >&2
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root)         needs_value "$1" $#; ROOT="$2"; shift 2 ;;
    --reason)       needs_value "$1" $#; REASON="$2"; shift 2 ;;
    --replaced-by) needs_value "$1" $#; REPLACED="$2"; shift 2 ;;
    --verify)     needs_value "$1" $#; VERIFY=1; TARGET="$2"; shift 2 ;;
    --summary)       needs_value "$1" $#; SUMMARY="$2"; shift 2 ;;
    --dry-run)      DRY=1; shift ;;
    --force)        FORCE=1; shift ;;
    -h|--help)      sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)             echo "Unknown option: $1" >&2; exit 2 ;;
    *)              TARGET="$1"; shift ;;
  esac
done

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"

[ -n "$TARGET" ] || { sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
TARGET="${TARGET#./}"

scripts_version || exit 1
ARCHIVES="$(conv_read archives | sed 's|/*$||')"
if [ -z "$ARCHIVES" ]; then
  ARCHIVES="$(grep -m1 '^archives:' CODEMAP.md 2>/dev/null | sed 's/^archives: *//;s|/*$||' || true)"
fi
[ -n "$ARCHIVES" ] || ARCHIVES="archives"
TODAY="$(ctx_today)"
MONTH="${TODAY%-*}"
DEST="$ARCHIVES/$MONTH/$TARGET"

# --- 0. barriers -------------------------------------------------------------
[ -e "$TARGET" ] || { echo "Not found: $TARGET" >&2; exit 1; }
[ -f "$TARGET" ] || { echo "$TARGET is not a file. Archive files one by one." >&2; exit 1; }
case "$TARGET" in
  "$ARCHIVES"/*) echo "$TARGET is already in $ARCHIVES/." >&2; exit 1 ;;
esac
if [ -n "$SUMMARY" ] && [ ! -f "$SUMMARY" ]; then
  echo "--summary: file not found: $SUMMARY" >&2; exit 1
fi
if [ "$VERIFY" -eq 0 ] && [ -e "$DEST" ]; then
  echo "$DEST already exists, archiving would overwrite it. Rename one of the two." >&2; exit 1
fi
case "$(basename "$TARGET")" in
  CODEMAP.md|TODOS.md|CHANGELOG.md|CLAUDE.md|AGENTS.md)
    echo "$TARGET is a pillar or a rules file, it is not archived." >&2
    echo "A false section in a pillar is fixed in place. A lasting rule" >&2
    echo "that became false is deleted, it is worse than no rule." >&2
    exit 1 ;;
esac
case "$TARGET" in
  docs/README.md|"$ARCHIVES"/README.md)
    echo "$TARGET is an index. An index is not archived." >&2; exit 1 ;;
esac

# --- 1. incoming references ---------------------------------------------------
# We search for the full path AND the base name, outside archives. The first says who
# really points to the file, the second catches the mentions in prose.
BASE="$(basename "$TARGET")"
find_refs() { # <literal pattern>
  if git rev-parse --git-dir >/dev/null 2>&1; then
    git grep -n --fixed-strings -- "$1" 2>/dev/null | grep -v "^$ARCHIVES/" || true
  else
    grep -rn --fixed-strings --exclude-dir=.git -- "$1" . 2>/dev/null \
      | sed 's|^\./||' | grep -v "^$ARCHIVES/" || true
  fi
}
REFS_PATH="$(find_refs "$TARGET" | grep -v "^$TARGET:" || true)"
REFS_BASE="$(find_refs "$BASE" | grep -v "^$TARGET:" | grep -vF "$TARGET" || true)"

# A markdown link to the file is operative, it will break on the move.
LINKS="$(printf '%s\n' "$REFS_PATH" "$REFS_BASE" | grep -v '^$' \
         | grep -E "\]\([^)]*$BASE(#[^)]*)?\)" || true)"
NB_LINKS="$(printf '%s\n' "$LINKS" | grep -c . || true)"
NB_PATH="$(printf '%s\n' "$REFS_PATH" | grep -c . || true)"
NB_BASE="$(printf '%s\n' "$REFS_BASE" | grep -c . || true)"

echo "=============================================="
echo " Archiving: $TARGET"
echo " $TODAY"
echo "=============================================="
echo
echo "1. Incoming references, outside $ARCHIVES/"
if [ "${NB_LINKS:-0}" -gt 0 ] && [ -n "$SUMMARY" ]; then
  echo "  live links ($NB_LINKS), they stay valid, the summary keeps the path:"
  printf '%s\n' "$LINKS" | cut -c1-160 | sed 's/^/       /'
elif [ "${NB_LINKS:-0}" -gt 0 ]; then
  echo "  OPERATIVE, these links will break ($NB_LINKS):"
  printf '%s\n' "$LINKS" | cut -c1-160 | sed 's/^/       /'
fi
if [ "${NB_PATH:-0}" -gt 0 ]; then
  echo "  path cited ($NB_PATH), to sort one by one:"
  sed -n '1,20p' <<<"$REFS_PATH" | cut -c1-160 | sed 's/^/       /'
  [ "$NB_PATH" -gt 20 ] && printf '       ... and %s more\n' "$((NB_PATH - 20))"
fi
if [ "${NB_BASE:-0}" -gt 0 ]; then
  echo "  name only cited ($NB_BASE), often historical context:"
  sed -n '1,10p' <<<"$REFS_BASE" | cut -c1-160 | sed 's/^/       /'
  [ "$NB_BASE" -gt 10 ] && printf '       ... and %s more\n' "$((NB_BASE - 10))"
fi
[ "${NB_PATH:-0}" -eq 0 ] && [ "${NB_BASE:-0}" -eq 0 ] \
  && echo "  none. Nobody cites this file."

if [ "$VERIFY" -eq 1 ]; then
  echo
  echo "=============================================="
  echo " Verify mode, nothing was written."
  if [ "${NB_LINKS:-0}" -gt 0 ]; then
    echo " $NB_LINKS live link(s) to remove or reword BEFORE archiving."
    echo " A live page does not cite an archive, the convention forbids it."
  else
    echo " No blocking link. Archiving can go ahead."
  fi
  echo "=============================================="
  exit 0
fi

if [ -z "$REASON" ]; then
  echo
  echo "--reason is required. \"obsolete\" tells nobody anything." >&2
  exit 2
fi

if [ "${NB_LINKS:-0}" -gt 0 ] && [ "$FORCE" -eq 0 ] && [ -z "$SUMMARY" ]; then
  echo
  echo "REFUSED: $NB_LINKS live markdown link(s) point to this file." >&2
  echo "Remove or reword them first, a live page does not cite an archive." >&2
  echo "Then run again. With --force, you archive and leave dead links behind." >&2
  exit 3
fi

# --- 2. move -----------------------------------------------------------
echo
echo "2. Move"
printf '  %s\n  -> %s\n' "$TARGET" "$DEST"
if [ "$DRY" -eq 0 ]; then
  mkdir -p "$(dirname "$DEST")"
  if git rev-parse --git-dir >/dev/null 2>&1 \
     && git ls-files --error-unmatch "$TARGET" >/dev/null 2>&1; then
    git mv "$TARGET" "$DEST"
  else
    echo "  (not tracked by git, plain move)"
    mv "$TARGET" "$DEST"
  fi
fi

# --- 3. header ---------------------------------------------------------------
echo
echo "3. Provenance header"
if [ -n "$REPLACED" ]; then
  REPL_TXT="$BT$REPLACED$BT"
else
  REPL_TXT="none, the subject no longer exists"
fi
if [ "$DRY" -eq 0 ]; then
  TMP="$(mktemp)"
  {
    printf '> ⚠️ **ARCHIVED on %s**, unmaintained, kept for history.\n' "$TODAY"
    printf '> **Origin**: %s%s%s\n' "$BT" "$TARGET" "$BT"
    printf '> **Reason**: %s\n' "$REASON"
    printf '> **Replaced by**: %s\n' "$REPL_TXT"
    printf '> **Not a source of truth.**\n'
    printf '\n'
    cat "$DEST"
  } > "$TMP"
  mv "$TMP" "$DEST"
fi
printf '  date %s, origin, reason, replacement: %s\n' "$TODAY" "$REPL_TXT"

# --- 4. links of the moved file -----------------------------------------------
# The file changed depth, its relative links to what stays alive no longer resolve.
# Prefixing ../ is not enough: the original path is reinjected UNDER the archive
# prefix, so going up is not enough, one has to come back down. Each link is resolved
# from the repository root, then rebuilt from the new depth. External links, anchors
# and absolute paths do not move, and code blocks are left alone.
OLDDIR="$(dirname "$TARGET")"
[ "$OLDDIR" = "." ] && OLDDIR=""
NEWDIR="$(dirname "$DEST")"
DEPTH="$(printf '%s' "$NEWDIR" | tr '/' '\n' | grep -c .)"
UP=""
i=0
while [ "$i" -lt "$DEPTH" ]; do UP="../$UP"; i=$((i + 1)); done
echo
echo "4. Relative links of the moved file"
BEFORE="$(grep -oE '\]\([^)]*\)' "$DEST" 2>/dev/null \
         | grep -vcE '\]\((https?:|mailto:|#|/)' || true)"
if [ "${BEFORE:-0}" -gt 0 ]; then
  printf '  %s relative link(s) resolved from the root, prefix %s\n' "$BEFORE" "$UP"
  if [ "$DRY" -eq 0 ]; then
    TMP="$(mktemp)"
    awk -v UP="$UP" -v OLDDIR="$OLDDIR" -v FENCE="$FENCE" '
      # Normalizes a path: removes . and resolves .. without touching the disk.
      function normalize(p,   n, seg, m, i, out, r) {
        n = split(p, seg, "/")
        m = 0
        for (i = 1; i <= n; i++) {
          if (seg[i] == "" || seg[i] == ".") continue
          if (seg[i] == "..") { if (m > 0) m--; continue }
          m++; out[m] = seg[i]
        }
        r = ""
        for (i = 1; i <= m; i++) r = (r == "" ? out[i] : r "/" out[i])
        return r
      }
      function rebase(u,   anchor, h, target) {
        if (u ~ /^(https?:|mailto:|#|\/)/) return u
        if (u ~ /^\{\{/) return u
        if (u ~ /^</) return u
        anchor = ""
        h = index(u, "#")
        if (h > 0) { anchor = substr(u, h); u = substr(u, 1, h - 1) }
        if (u == "") return anchor
        target = normalize((OLDDIR == "" ? u : OLDDIR "/" u))
        return UP target anchor
      }
      index($0, FENCE) == 1 { inside = !inside; print; next }
      inside { print; next }
      {
        out = ""; rest = $0
        while (match(rest, /\]\([^)]*\)/)) {
          before = substr(rest, 1, RSTART - 1)
          tok = substr(rest, RSTART, RLENGTH)
          rest = substr(rest, RSTART + RLENGTH)
          url = substr(tok, 3, length(tok) - 3)
          out = out before "](" rebase(url) ")"
        }
        print out rest
      }' "$DEST" > "$TMP"
    mv "$TMP" "$DEST"
  fi
else
  echo "  no relative link to resolve"
fi

# --- 5. index line ---------------------------------------------------------
echo
echo "5. Index"
LINE="| $TODAY | $BT$TARGET$BT | $BT$DEST$BT | $REASON | $REPL_TXT |"
if [ -f "$ARCHIVES/README.md" ] && grep -q '^|---' "$ARCHIVES/README.md"; then
  if [ "$DRY" -eq 0 ]; then
    TMP="$(mktemp)"
    awk -v l="$LINE" 'BEGIN{done=0} { print } /^\|---/ && !done { print l; done=1 }' \
      "$ARCHIVES/README.md" > "$TMP"
    mv "$TMP" "$ARCHIVES/README.md"
  fi
  echo "  line added to $ARCHIVES/README.md"
else
  echo "  $ARCHIVES/README.md missing or without a table. Line to add by hand:"
  echo "    $LINE"
fi

# --- 5 bis. summary in place ---------------------------------------------------
if [ -n "$SUMMARY" ]; then
  echo
  echo "5 bis. Summary at the old path"
  printf '  %s stays in place, full text in %s\n' "$TARGET" "$DEST"
  if [ "$DRY" -eq 0 ]; then
    sed "s|{{ARCHIVE}}|$DEST|g" "$SUMMARY" > "$TARGET"
  fi
fi

# --- 6. verification ----------------------------------------------------------
# The gate. It tells a finished archiving from a half-done one, and it is the one that
# was missing when the gesture was done by hand.
echo
echo "6. Check"
if [ "$DRY" -eq 1 ]; then
  echo "  skipped, dry run"
  echo
  echo "Dry run finished, nothing was written."
  exit 0
fi
if [ -n "$SUMMARY" ]; then
  if [ -s "$TARGET" ] && [ -s "$DEST" ]; then
    echo "  [ok] summary in place at $TARGET, full text in $DEST"
    echo
    echo "=============================================="
    echo " Archived, summary kept. Nothing is committed, check with git status."
    echo "=============================================="
    exit 0
  fi
  echo "  [!] the summary or the archive is missing after the operation" >&2
  exit 1
fi
LEFT="$(find_refs "$TARGET" | grep -v "^$DEST:" || true)"
NB_LEFT="$(printf '%s\n' "$LEFT" | grep -c . || true)"
if [ "${NB_LEFT:-0}" -gt 0 ]; then
  echo "  [!] $NB_LEFT occurrence(s) of the old path outside the archives:"
  sed -n '1,15p' <<<"$LEFT" | cut -c1-160 | sed 's/^/       /'
  echo
  echo "=============================================="
  echo " Archiving INCOMPLETE. The file is moved, its header and its index line"
  echo " are in place, but references still point to the old path."
  echo " Fix the ones listed above."
  echo "=============================================="
  exit 1
fi
echo "  [ok] no occurrence of the old path outside the archives"
echo
echo "=============================================="
if git rev-parse --git-dir >/dev/null 2>&1; then
  echo " Archived. Nothing is committed, check with git status."
else
  echo " Archived. The repository is not tracked by git, the file history is not kept."
fi
echo " To find this content later: ctx-archaeology.sh <pattern>"
echo "=============================================="
