#!/usr/bin/env bash
#
# ctx-archaeology.sh: the one sanctioned way to read inside archives/.
#
# The convention forbids reading archives/ on resume, because it is false or cold. But
# an agent looking for WHY something is done a certain way must be able to go there.
# This script is that path. It always returns the provenance header BEFORE the line
# found, so an archive cannot be taken for a current truth.
#
# Usage:
#   bash ctx-archaeology.sh <pattern>              # search, returns provenance + excerpts
#   bash ctx-archaeology.sh --list                 # inventory of what is archived
#   bash ctx-archaeology.sh --file <path>          # provenance of one given archive
#   bash ctx-archaeology.sh <pattern> --max 10 --context 4
#
# The output is BOUNDED, on purpose. A log archive is thousands of lines, and pouring
# that into a context costs more than it returns. The script says what it cut and how
# to see the rest.
set -euf

ROOT=""
PATTERN=""
FILE=""
LIST=0
MAX=20
CONTEXT=2

while [ $# -gt 0 ]; do
  case "$1" in
    --root)     ROOT="${2:-}"; shift 2 ;;
    --list)    LIST=1; shift ;;
    --file)  FILE="${2:-}"; shift 2 ;;
    --max)      MAX="${2:-20}"; shift 2 ;;
    --context) CONTEXT="${2:-2}"; shift 2 ;;
    -h|--help)  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         echo "Unknown option: $1" >&2; exit 2 ;;
    *)          PATTERN="$1"; shift ;;
  esac
done

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"

# The archives directory is declared in the contexte:convention block, otherwise it is
# archives/ by default.
ARCHIVES="$(grep -m1 '^archives:' CODEMAP.md 2>/dev/null | sed 's/^archives: *//;s|/*$||' || true)"
[ -n "$ARCHIVES" ] || ARCHIVES="archives"
[ -d "$ARCHIVES" ] || { echo "No archives directory ($ARCHIVES/). Nothing to dig into." >&2; exit 1; }

# --- provenance of an archived file ------------------------------------------
# The header is five lines at most, as a blockquote, put by ctx-archive.sh or by
# ctx-rotation.sh. The two forms are told apart: one carries false content, the other
# true content gone cold, and the reader must know which one they hold.
# Both the English and the French headers are read.
provenance() { # <file>
  local f="$1" head_lines
  head_lines="$(head -8 "$f" | grep '^>' || true)"
  if grep -q 'rotation' <<<"$head_lines"; then
    printf '  nature   : COLD, still true at its date, moved out of the current log\n'
  elif [ -n "$head_lines" ]; then
    printf '  nature   : FALSE or STALE, do not use it to act\n'
  else
    printf '  nature   : NO HEADER, unknown provenance, archiving defect\n'
  fi
  [ -n "$head_lines" ] && printf '%s\n' "$head_lines" | sed 's/^> *//; s/^/  /' | grep -v '^ *$' || true
}

# --- list mode ----------------------------------------------------------
if [ "$LIST" -eq 1 ]; then
  echo "=============================================="
  echo " Inventory of $ARCHIVES/"
  echo "=============================================="
  n=0
  for f in $(find "$ARCHIVES" -type f -name '*.md' -not -name 'README.md' 2>/dev/null | sort); do
    n=$((n + 1))
    printf '\n%s  (%s lines)\n' "$f" "$(wc -l < "$f" | tr -d ' ')"
    provenance "$f"
  done
  others="$(find "$ARCHIVES" -type f -not -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  echo
  echo "$n archived markdown file(s), $others other file(s)."
  [ -f "$ARCHIVES/README.md" ] && echo "The index is in $ARCHIVES/README.md."
  exit 0
fi

# --- file mode -------------------------------------------------------------
if [ -n "$FILE" ]; then
  FILE="${FILE#./}"
  [ -f "$FILE" ] || { echo "Not found: $FILE" >&2; exit 1; }
  case "$FILE" in
    "$ARCHIVES"/*) : ;;
    *) echo "$FILE is not in $ARCHIVES/. This script only reads archives." >&2; exit 2 ;;
  esac
  echo "$FILE  ($(wc -l < "$FILE" | tr -d ' ') lines)"
  provenance "$FILE"
  echo
  echo "To read it in full, knowing what its nature above says:"
  echo "  sed -n '1,120p' $FILE"
  exit 0
fi

# --- search mode -----------------------------------------------------------
[ -n "$PATTERN" ] || { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
case "$MAX" in ''|*[!0-9]*) echo "--max expects an integer" >&2; exit 2 ;; esac
case "$CONTEXT" in ''|*[!0-9]*) echo "--context expects an integer" >&2; exit 2 ;; esac

echo "=============================================="
echo " Archaeology: \"$PATTERN\" in $ARCHIVES/"
echo "=============================================="
echo
echo "⚠️  Nothing below is a source of truth. Each block says its nature."
echo "    Current state lives in the root pillars and in docs/."

FILES="$(grep -rl -- "$PATTERN" "$ARCHIVES" 2>/dev/null | sort || true)"
if [ -z "$FILES" ]; then
  echo
  echo "No occurrence. Nothing archived mentions it."
  exit 0
fi

TOTAL=0
for f in $FILES; do
  nb="$(grep -c -- "$PATTERN" "$f" 2>/dev/null || echo 0)"
  TOTAL=$((TOTAL + nb))
done

echo
echo "$TOTAL occurrence(s) in $(printf '%s\n' "$FILES" | wc -l | tr -d ' ') file(s)."

SHOWN=0
LEFT=0
for f in $FILES; do
  nb="$(grep -c -- "$PATTERN" "$f" 2>/dev/null || echo 0)"
  printf '\n----------------------------------------------\n'
  printf '%s\n' "$f"
  case "$f" in
    */README.md|README.md)
          printf '  nature   : archives INDEX, not an archived document\n' ;;
    *.md) provenance "$f" ;;
    *)    printf '  nature   : non-markdown file, no header\n' ;;
  esac
  printf '\n'
  if [ "$SHOWN" -ge "$MAX" ]; then
    printf '  [%s occurrence(s) not shown, cap reached]\n' "$nb"
    LEFT=$((LEFT + nb))
    continue
  fi
  # Lines are truncated to 200 characters. A doc line can be very long, and the goal
  # is to locate, not to bring everything back.
  LIMIT=$(( (MAX - SHOWN) * (2 * CONTEXT + 1) ))
  grep -n -C "$CONTEXT" -- "$PATTERN" "$f" 2>/dev/null | sed -n "1,${LIMIT}p" \
    | cut -c1-200 | sed 's/^/  /' || true
  if [ "$nb" -gt $(( MAX - SHOWN )) ]; then
    LEFT=$(( LEFT + nb - (MAX - SHOWN) ))
  fi
  SHOWN=$((SHOWN + nb))
done

echo
echo "=============================================="
if [ "$LEFT" -gt 0 ]; then
  echo " $LEFT occurrence(s) not shown. Run again with a higher --max,"
  echo " or read one given file: ctx-archaeology.sh --file <path>"
else
  echo " Everything is shown."
fi
echo " What is true today is not read here. Go to the pillars and docs/."
echo "=============================================="
