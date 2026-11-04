#!/usr/bin/env bash
#
# ctx-rotation.sh: rotates a log, or compresses executed plans.
#
# Log: keeps the N most recent entries in the file, moves the others to
# archives/<log>/YYYY-MM.md, one file per month, and adds an index line to
# archives/README.md. An old entry is not false, it is cold.
# archives/ is the only place the convention never reads on resume.
#
# Usage:
#   bash ctx-rotation.sh [--root <path>] [--file <log.md>] [--keep <N>] [--cap <N>] [--dry-run]
#   bash ctx-rotation.sh --plans [--root <path>] [--dry-run]
#
# --file: CHANGELOG.md by default.
# --keep: number of entries kept, 30 by default. The first N of the file, so the most
#           recent ones, as the log is sorted from newest to oldest.
# --cap: maximum lines of an archive file, 1500 by default. A month that goes over
#           is split into YYYY-MM-2.md, YYYY-MM-3.md, each one indexed.
# --plans: instead of the log, handles the plans of the directory declared by `plans:` in
#           the block (plans/ by default), that is <plans>/*.md.
# --dry-run: says what would move, writes nothing.
#
# Log formats, those of the convention. The contexte:convention block declares them with
# `journal:`, otherwise the script recognizes them itself:
#   date-titre         ## YYYY-MM-DD title
#   keep-a-changelog   ## [x.y.z] - YYYY-MM-DD
#   crochets           [YYYY-MM-DD] [TYPE] text, one line per entry, or one line
#                      followed by its body up to the next entry
#
# Order: a log sorted from oldest to newest is REFUSED, code 3. Rotating it
# would archive the most recent entries. Put it back from newest to oldest.
#
# Executed plan, for --plans. A plan is executed when one of these two marks exists:
#   - one of the first 30 lines of the plan carries `Status: finished` (or executed,
#     closed, done) or the banner `PLAN EXECUTED`, without a negation (not, in progress,
#     partial)
#   - a line of TODOS.md cites `<plans>/<name>.md` with finished, executed, closed, done
#     or [x], and with no open `[ ]` box
# An executed plan of more than 20 lines becomes a summary of 20 lines at most: title,
# goal, deviation log (one title per deviation), commits. The full text goes through
# ctx-archive.sh to archives/YYYY-MM/plans/<name>.md, with header and index. A plan
# already summarized (plan-resume marker) or of 20 lines or fewer is left alone.
#
# Idempotent: run again on a file already rotated, it finds nothing to move.
set -euf

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=ctx-common.sh
. "$DIR/ctx-common.sh"

ROOT=""
FILE="CHANGELOG.md"
KEEP=30
CAP=1500
PLANS=0
DRY=0

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
}

# An option with a value but no value: clear message and code 2, not a silent exit.
needs_value() { # <option> <number of remaining arguments, option included>
  if [ "$2" -lt 2 ]; then
    echo "$1 expects a value" >&2
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root)    needs_value "$1" $#; ROOT="$2"; shift 2 ;;
    --file) needs_value "$1" $#; FILE="$2"; shift 2 ;;
    --keep)  needs_value "$1" $#; KEEP="$2"; shift 2 ;;
    --cap) needs_value "$1" $#; CAP="$2"; shift 2 ;;
    --plans)   PLANS=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"

scripts_version || exit 1

case "$KEEP" in ''|*[!0-9]*|0) echo "--keep expects an integer greater than 0" >&2; exit 2 ;; esac
case "$CAP" in ''|*[!0-9]*|0) echo "--cap expects an integer greater than 0" >&2; exit 2 ;; esac

TODAY="$(ctx_today)"
CURRENT_MONTH="${TODAY%-*}"
BT="$(printf '\140')"

ARCH="$(conv_read archives | sed 's|/*$||')"
[ -n "$ARCH" ] || ARCH="archives"

# Plans directory, `plans:` key of the block. First word, without leading ./ or trailing /.
PLANS_DIR="$(conv_read plans)"
PLANS_DIR="${PLANS_DIR%%[[:space:],]*}"
while [ "${PLANS_DIR#./}" != "$PLANS_DIR" ]; do PLANS_DIR="${PLANS_DIR#./}"; done
while [ "${PLANS_DIR%/}" != "$PLANS_DIR" ]; do PLANS_DIR="${PLANS_DIR%/}"; done
[ -n "$PLANS_DIR" ] || PLANS_DIR="plans"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# =============================================================================
# Plans mode
# =============================================================================

# Why a plan is executed, or nothing.
plan_executed() { # <file>
  local f="$1" l
  l="$(head -n 30 "$f" \
       | grep -Ei '((statut|status|etat|état|state)[^a-z]*:.*(termin|ex.{1,2}cut|clos|done|complet|finish)|plan (ex.{1,2}cut|termin))' \
       | grep -Eiv '(^|[^a-z])(non|pas|en cours|partiel|not|in progress|partial)([^a-z]|$)' | sed -n '1p' || true)"
  if [ -n "$l" ]; then
    printf 'mark in the header\n'
    return 0
  fi
  if [ -f TODOS.md ]; then
    l="$(grep -F -- "$f" TODOS.md \
         | grep -Ei 'termin|ex.{1,2}cut|clos|done|finish|\[x\]' \
         | grep -Fv '[ ]' \
         | grep -Eiv '(^|[^a-z])(non|pas|en cours|partiel|not|in progress|partial)([^a-z]|$)' | sed -n '1p' || true)"
    if [ -n "$l" ]; then
      printf 'declared finished in TODOS.md\n'
      return 0
    fi
  fi
  return 0
}

# Plan title, first `# ` outside a code block.
plan_title() { # <file> <default>
  awk -v d="$2" '/^```/ { f = !f } !f && /^# / { sub(/^# +/, ""); print; ok = 1; exit } END { if (!ok) print d }' "$1"
}

# First paragraph of the Goal section (or Context, Summary), on one line: the
# lines are joined up to the end of the sentence, three at most.
plan_goal() { # <file>
  awk '
    /^```/ { f = !f }
    f { next }
    /^#+ / {
      if (inside && sentence != "") exit
      inside = ($0 ~ /^## .*(Objectif|Contexte|Résumé|Resume|Goal|Objective|Context|Summary)/)
      next
    }
    /^<!--/ || /^>/ { next }
    /^[ \t]*$/ { if (sentence != "") exit; next }
    inside {
      sentence = (sentence == "" ? $0 : sentence " " $0)
      k++
      if ($0 ~ /[.!?:][ \t]*$/ || k >= 3) exit
    }
    END { if (sentence != "") print sentence }
  ' "$1"
}

# One deviation per line: the first line of the bullet, or only its leading bold in short mode.
plan_deviations() { # <file> <long|short>
  MODE="$2" awk '
    function cut_at(s, n,   p, i) {
      if (length(s) <= n) return s
      p = 0
      for (i = 1; i <= n; i++) if (substr(s, i, 1) == " ") p = i
      if (p == 0) return s
      return substr(s, 1, p - 1) " ..."
    }
    /^```/ { f = !f; next }
    f { next }
    /^#+ / {
      match($0, /^#+/); lvl = RLENGTH
      if (inside && lvl <= devlevel) inside = 0
      if (!inside && $0 ~ /^##+ .*((é|É|e|E)carts|Deviation)/) { inside = 1; devlevel = lvl }
      next
    }
    inside {
      if ($0 ~ /^[ \t]*$/ || $0 ~ /^[ \t]/ || $0 ~ /^<!--/) next
      if ($0 ~ /^\|[-: |]*\|?[ \t]*$/) next
      if (ENVIRON["MODE"] == "short" && match($0, /^[-*] \*\*[^*]+\*\*/)) { print substr($0, 1, RLENGTH); next }
      print cut_at($0, 160)
    }
  ' "$1"
}

# Lines that carry a commit id: seven to forty hex characters with at least one digit
# and one letter. Each id is returned only once.
plan_commits() { # <file>
  awk '
    function cut_at(s, n,   p, i) {
      if (length(s) <= n) return s
      p = 0
      for (i = 1; i <= n; i++) if (substr(s, i, 1) == " ") p = i
      if (p == 0) return s
      return substr(s, 1, p - 1) " ..."
    }
    /^```/ { f = !f }
    {
      n = split($0, word, /[^0-9A-Za-z]/)
      fresh = 0
      for (i = 1; i <= n; i++) {
        t = word[i]
        if (length(t) >= 7 && length(t) <= 40 && t ~ /^[0-9a-f]+$/ && t ~ /[0-9]/ && t ~ /[a-f]/ && !(t in seen)) {
          seen[t] = 1; fresh = 1
        }
      }
      if (fresh) {
        l = $0
        sub(/^[ \t]+/, "", l)
        if (l !~ /^[-*|]/) l = "- " l
        print cut_at(l, 150)
      }
    }
  ' "$1"
}

# Summary of twenty lines at most. The {{ARCHIVE}} replacement is done by ctx-archive.sh.
plan_summary() { # <file> <output> <open boxes>
  local f="$1" out="$2" open_boxes="$3" title obj nb_e nb_c left ec cc fixed
  title="$(plan_title "$f" "$(basename "$f" .md)")"
  obj="$(plan_goal "$f" | sed -n '1p')"
  plan_deviations "$f" long > "$TMP/deviations"
  plan_commits "$f" > "$TMP/commits"
  nb_e="$(wc -l < "$TMP/deviations" | tr -d ' ')"
  nb_c="$(wc -l < "$TMP/commits" | tr -d ' ')"

  # 20 lines. Fixed: title and blank, pointer, open boxes line if needed, goal and its
  # blank, then per section a blank, a title and a blank. The rest is the budget of the
  # entries of the two lists.
  fixed=3
  if [ "$open_boxes" -gt 0 ]; then fixed=$((fixed + 1)); fi
  if [ -n "$obj" ]; then fixed=$((fixed + 2)); fi
  if [ "$nb_e" -gt 0 ]; then fixed=$((fixed + 3)); fi
  if [ "$nb_c" -gt 0 ]; then fixed=$((fixed + 3)); fi
  left=$((20 - fixed))
  ec="$nb_e"; cc="$nb_c"
  if [ $((nb_e + nb_c)) -gt "$left" ]; then
    # too long: one title per deviation instead of its first line
    plan_deviations "$f" short > "$TMP/deviations"
    # the deviation log comes before the commits, which keep two lines at least
    cc=2
    if [ "$cc" -gt "$nb_c" ]; then cc="$nb_c"; fi
    ec=$((left - cc))
    if [ "$ec" -gt "$nb_e" ]; then
      ec="$nb_e"
      cc=$((left - ec))
      if [ "$cc" -gt "$nb_c" ]; then cc="$nb_c"; fi
    fi
  fi

  {
    printf '# %s\n\n' "$title"
    printf '> Plan executed, summarized on %s. Full text: %s{{ARCHIVE}}%s. <!-- plan-resume -->\n' "$TODAY" "$BT" "$BT"
    if [ "$open_boxes" -gt 0 ]; then
      printf '> %s box(es) were still open, they are in the full text.\n' "$open_boxes"
    fi
    if [ -n "$obj" ]; then
      printf '\n**Goal.** %s\n' "$obj"
    fi
    if [ "$nb_e" -gt 0 ]; then
      printf '\n## Deviation log\n\n'
      if [ "$nb_e" -gt "$ec" ]; then
        head -n $((ec - 1)) "$TMP/deviations"
        printf -- '- ... and %s more, see the full text.\n' "$((nb_e - ec + 1))"
      else
        cat "$TMP/deviations"
      fi
    fi
    if [ "$nb_c" -gt 0 ]; then
      printf '\n## Commits\n\n'
      if [ "$nb_c" -gt "$cc" ]; then
        printf -- '- ... %s older, see the full text.\n' "$((nb_c - cc + 1))"
        tail -n $((cc - 1)) "$TMP/commits"
      else
        cat "$TMP/commits"
      fi
    fi
  } > "$out"
}

plans_main() {
  local p reason nb open_boxes name dest done_count=0 failed=0 out code warn
  echo "Executed plans of $ROOT"
  if [ ! -d "$PLANS_DIR" ]; then
    echo "  no $PLANS_DIR/ directory, nothing to do."
    return 0
  fi
  [ "$DRY" -eq 1 ] && echo "  dry run, nothing will be written"
  echo
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    name="$(basename "$p")"
    [ "$name" = "README.md" ] && continue
    nb="$(wc -l < "$p" | tr -d ' ')"
    if grep -q 'plan-resume' "$p"; then
      printf '  = %-38s already summarized\n' "$p"
      continue
    fi
    reason="$(plan_executed "$p")"
    if [ -z "$reason" ]; then
      printf '  . %-38s %s lines, not executed, left as is\n' "$p" "$nb"
      continue
    fi
    if [ "$nb" -le 20 ]; then
      printf '  . %-38s %s lines, executed but already short, left as is\n' "$p" "$nb"
      continue
    fi
    open_boxes="$(grep -c '\[ \]' "$p" || true)"
    plan_summary "$p" "$TMP/summary-$name" "${open_boxes:-0}"
    dest="$ARCH/$CURRENT_MONTH/$p"
    printf '  - %-38s %s lines, executed (%s)\n' "$p" "$nb" "$reason"
    printf '      summary of %s lines, full text to %s\n' \
      "$(wc -l < "$TMP/summary-$name" | tr -d ' ')" "$dest"
    set +e
    if [ "$DRY" -eq 1 ]; then
      out="$(bash "$DIR/ctx-archive.sh" --root "$ROOT" "$p" --reason "plan executed, summary kept in place" \
        --replaced-by "$p" --summary "$TMP/summary-$name" --dry-run 2>&1)"
    else
      out="$(bash "$DIR/ctx-archive.sh" --root "$ROOT" "$p" --reason "plan executed, summary kept in place" \
        --replaced-by "$p" --summary "$TMP/summary-$name" 2>&1)"
    fi
    code=$?
    set -e
    if [ "$code" -ne 0 ]; then
      echo "      ctx-archive.sh FAILED (code $code):"
      printf '%s\n' "$out" | sed 's/^/        /'
      failed=1
    else
      # A success of ctx-archive.sh can carry a warning: without an index table, the plan
      # is archived without its line, and the line to add by hand is said here.
      warn="$(printf '%s\n' "$out" | grep -A1 -E 'Line to add by hand|^ *\[!\]' | grep -v '^--$' || true)"
      if [ -n "$warn" ]; then
        printf '%s\n' "$warn" | sed 's/^ */      /'
      fi
      done_count=$((done_count + 1))
    fi
  done <<END_PLANS
$(find "$PLANS_DIR" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)
END_PLANS
  echo
  if [ "$DRY" -eq 1 ]; then
    echo "  $done_count plan(s) to summarize."
  else
    echo "  $done_count plan(s) summarized and archived."
    echo
    echo "Nothing is committed. Check with git status, then git add the touched files."
  fi
  return "$failed"
}

if [ "$PLANS" -eq 1 ]; then
  plans_main
  exit $?
fi

# =============================================================================
# Log mode
# =============================================================================

[ -f "$FILE" ] || { echo "Log not found: $FILE" >&2; exit 1; }

SLUG="$(basename "$FILE" .md | tr '[:upper:]' '[:lower:]')"
DEST_DIR="$ARCH/$SLUG"
SENTINEL='<!-- end of header -->'
SENTINEL_FR='<!-- fin de l'"'"'en-tête -->'   # read on archives written by older versions
HEADER=7   # lines of the header put on a new archive file

# An entry starts at a line that carries the format pattern, outside a code block.
# What precedes the first entry is the preamble, what follows an entry up to the next
# one belongs to it. Manifest: number, date, first line, last line.
split_entries() { # <format>
  local pattern
  pattern="$(log_pattern "$1" | sed 's/\[0-9\]{4}/[0-9][0-9][0-9][0-9]/g; s/\[0-9\]{2}/[0-9][0-9]/g')"
  if [ -z "$pattern" ]; then
    echo "Unknown log format: $1 (expected: date-titre, keep-a-changelog, crochets)" >&2
    exit 2
  fi
  MOTIF="$pattern" awk '
    BEGIN { mot = ENVIRON["MOTIF"]; n = 0; fence = 0 }
    /^```/ { fence = !fence }
    !fence && $0 ~ mot {
      if (n > 0) fin[n] = NR - 1
      n++
      match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)
      date[n] = substr($0, RSTART, RLENGTH)
      deb[n] = NR
    }
    END {
      if (n > 0) fin[n] = NR
      for (i = 1; i <= n; i++) print i, date[i], deb[i], fin[i]
    }' "$FILE" > "$TMP/manifest"
}

FORMAT="$(log_detect "$FILE")"
DECLARED="$(conv_log_format)"
TOTAL=0
if [ -n "$FORMAT" ]; then
  split_entries "$FORMAT"
  TOTAL="$(wc -l < "$TMP/manifest" | tr -d ' ')"
  if [ "$TOTAL" -eq 0 ] && [ -n "$DECLARED" ]; then
    # The block speaks of the project log, this file may be another one.
    AUTO="$(CTX_ROOT=/nonexistent log_detect "$FILE")"
    if [ -n "$AUTO" ] && [ "$AUTO" != "$FORMAT" ]; then
      echo "The block declares journal: $FORMAT, no entry of this format in $FILE."
      FORMAT="$AUTO"
      split_entries "$FORMAT"
      TOTAL="$(wc -l < "$TMP/manifest" | tr -d ' ')"
    fi
  fi
fi

echo "Rotation of $FILE"
if [ -z "$FORMAT" ]; then
  echo "  format: none recognized (date-titre, keep-a-changelog, crochets)"
else
  echo "  format: $FORMAT"
fi
echo "  dated entries: $TOTAL, to keep: $KEEP"

# --- chronological order ------------------------------------------------------
# The log keeps the first N entries. Sorted from oldest to newest, it would archive the
# most recent ones. Each entry is compared to the next, the majority decides, a single
# misplaced entry does not get the log refused.
if [ "$TOTAL" -gt 1 ]; then
  SENS="$(awk 'NR > 1 { if ($2 < prev) desc++; else if ($2 > prev) asc++ } { prev = $2 } END { print asc + 0, desc + 0 }' "$TMP/manifest")"
  ASC="${SENS% *}"
  DESC="${SENS#* }"
  if [ "$ASC" -gt "$DESC" ]; then
    echo >&2
    echo "REFUSED: $FILE is sorted in chronological order, from oldest to newest." >&2
    echo "  ($ASC steps forward in time against $DESC backward.)" >&2
    echo "  Rotation keeps the first $KEEP entries of the file and archives the rest." >&2
    echo "  Here it would archive the most recent ones and keep the oldest." >&2
    echo "  Put the log back with the newest on top and the oldest at the bottom, then run again." >&2
    exit 3
  fi
fi

if [ "$TOTAL" -le "$KEEP" ]; then
  echo "  nothing to move."
  exit 0
fi
TO_MOVE=$((TOTAL - KEEP))
echo "  to move: $TO_MOVE, to $DEST_DIR/YYYY-MM.md"
[ "$DRY" -eq 1 ] && echo "  dry run, nothing will be written"
echo

# --- grouping by month --------------------------------------------------------
archive_name() { # <month> <rank>
  if [ "$2" -le 1 ]; then
    printf '%s/%s.md\n' "$DEST_DIR" "$1"
  else
    printf '%s/%s-%s.md\n' "$DEST_DIR" "$1" "$2"
  fi
}

entry_lines() { # <number>
  awk -v i="$1" '$1 == i { print $4 - $3 + 1 }' "$TMP/manifest"
}

read_entry() { # <number>
  local a b
  a="$(awk -v i="$1" '$1 == i { print $3 }' "$TMP/manifest")"
  b="$(awk -v i="$1" '$1 == i { print $4 }' "$TMP/manifest")"
  sed -n "${a},${b}p" "$FILE"
}

MONTHS="$(awk -v g="$KEEP" '$1 > g { print substr($2, 1, 7) }' "$TMP/manifest" | awk '!vu[$0]++')"
CREATED=""
for m in $MONTHS; do
  ids="$(awk -v g="$KEEP" -v m="$m" '$1 > g && substr($2, 1, 7) == m { print $1 }' "$TMP/manifest" | tr '\n' ' ')"
  total_m=0
  for i in $ids; do total_m=$((total_m + $(entry_lines "$i"))); done

  # head file of the existing chain of the month: the highest rank, the most recent
  k=1
  while [ -f "$(archive_name "$m" $((k + 1)))" ]; do k=$((k + 1)); done
  existe=0
  [ -f "$(archive_name "$m" "$k")" ] && existe=1

  : > "$TMP/plan-$m"
  place=0
  deborde=0
  if [ "$existe" -eq 1 ]; then
    l0="$(wc -l < "$(archive_name "$m" "$k")" | tr -d ' ')"
    if [ $((l0 + total_m)) -le "$CAP" ]; then
      echo "$k|append|$ids" >> "$TMP/plan-$m"
      place=1
    else
      deborde=1
      k=$((k + 1))
    fi
  fi
  if [ "$place" -eq 0 ]; then
    # from oldest to newest, the oldest in the file of the lowest rank
    grp=""
    lg="$HEADER"
    for i in $(printf '%s\n' $ids | sort -rn); do
      nb="$(entry_lines "$i")"
      if [ -n "$grp" ] && [ $((lg + nb)) -gt "$CAP" ]; then
        echo "$k|new|$grp" >> "$TMP/plan-$m"
        k=$((k + 1))
        grp=""
        lg="$HEADER"
      fi
      grp="$i $grp"
      lg=$((lg + nb))
    done
    if [ -n "$grp" ]; then echo "$k|new|$grp" >> "$TMP/plan-$m"; fi
  fi

  nb_fichiers="$(wc -l < "$TMP/plan-$m" | tr -d ' ')"
  if [ "$nb_fichiers" -gt 1 ] || [ "$deborde" -eq 1 ]; then
    echo "  ! $m: $total_m lines to write, a file does not go over $CAP lines, the month is split"
  fi

  while IFS='|' read -r k mode ids_f; do
    dest="$(archive_name "$m" "$k")"
    bloc="$TMP/bloc"
    : > "$bloc"
    nb=0
    for i in $ids_f; do
      read_entry "$i" >> "$bloc"
      nb=$((nb + 1))
    done
    if [ "$mode" = "append" ]; then
      printf '  ~ %-44s %s entry(ies) added at the top\n' "$dest" "$nb"
    else
      printf '  + %-44s %s entry(ies), file created\n' "$dest" "$nb"
    fi
    [ "$DRY" -eq 1 ] && continue
    mkdir -p "$DEST_DIR"
    if [ "$mode" = "append" ]; then
      # header kept, new entries first, then the old ones
      head_n="$(grep -nxF -e "$SENTINEL" -e "$SENTINEL_FR" -- "$dest" | sed -n '1p' | cut -d: -f1 || true)"
      if [ -z "$head_n" ]; then
        head_n="$(awk '/^>/ || /^[ \t]*$/ { n++; next } { exit } END { print n + 0 }' "$dest")"
      fi
      {
        if [ "$head_n" -gt 0 ]; then sed -n "1,${head_n}p" "$dest"; fi
        echo
        cat "$bloc"
        if [ "$head_n" -gt 0 ]; then sed "1,${head_n}d" "$dest"; else cat "$dest"; fi
      } > "$TMP/dest"
    else
      part=""
      [ "$k" -gt 1 ] && part=" (part $k)"
      {
        echo "> ⚠️ **ARCHIVED**, entries of $BT$FILE$BT moved by rotation on $TODAY, kept for history."
        echo "> **Origin**: $BT$FILE$BT"
        echo "> **Month**: $m$part"
        echo "> **Not a source of truth.** Current state lives in the root pillars."
        echo "$SENTINEL"
        echo
        cat "$bloc"
      } > "$TMP/dest"
      CREATED="$CREATED $dest"
    fi
    mv "$TMP/dest" "$dest"
  done < "$TMP/plan-$m"
done

# --- rewrite of the log -------------------------------------------------------
OLDEST_KEPT="$(awk -v g="$KEEP" '$1 == g { print $2 }' "$TMP/manifest")"
FIRST_START="$(awk '$1 == 1 { print $3 }' "$TMP/manifest")"
KEPT_END="$(awk -v g="$KEEP" '$1 == g { print $4 }' "$TMP/manifest")"
if [ "$DRY" -eq 0 ]; then
  : > "$TMP/preamble"
  if [ "$FIRST_START" -gt 1 ]; then
    sed -n "1,$((FIRST_START - 1))p" "$FILE" | grep -Ev '^> (Entrées antérieures au |Entries before )' > "$TMP/preamble" || true
  fi
  {
    printf '%s\n' "$(cat "$TMP/preamble")"
    echo
    echo "> Entries before $OLDEST_KEPT: $BT$DEST_DIR/$BT, one file per month, never read on resume."
    echo
    sed -n "${FIRST_START},${KEPT_END}p" "$FILE"
  } > "$TMP/journal"
  mv "$TMP/journal" "$FILE"
fi
echo
echo "  $FILE keeps $KEEP entries, the oldest from $OLDEST_KEPT."

# --- archive index ------------------------------------------------------------
# One line per created file, added at its creation. A file already indexed does not
# get a second line.
if [ -n "$CREATED" ] && [ "$DRY" -eq 0 ]; then
  if [ -f "$ARCH/README.md" ] && grep -q '^|---' "$ARCH/README.md"; then
    for dest in $CREATED; do
      if grep -qF -- "$BT$dest$BT" "$ARCH/README.md"; then continue; fi
      line="| $TODAY | $BT$FILE$BT | $BT$dest$BT | log rotation, entries of month $(basename "$dest" .md) | $BT$FILE$BT |"
      awk -v l="$line" 'BEGIN { done = 0 } { print } /^\|---/ && !done { print l; done = 1 }' "$ARCH/README.md" > "$TMP/readme"
      mv "$TMP/readme" "$ARCH/README.md"
      echo "  index: line added to $ARCH/README.md for $dest"
    done
  else
    echo "  index: $ARCH/README.md missing or without a table, add by hand one line per created file:"
    for dest in $CREATED; do echo "          $dest"; done
  fi
fi

echo
if [ "$DRY" -eq 1 ]; then
  echo "Dry run finished, nothing was written."
else
  echo "Nothing is committed. Check with git status, then git add the touched files."
fi
