#!/usr/bin/env bash
#
# ctx-audit.sh: drift report between the documentation and reality, and
# context budget measurement.
#
# The script reports, it fixes nothing and it does not judge. You decide.
# Usage:
#   bash ctx-audit.sh [--root <path>] [--staleness <days>] [--strict] [--budget] [--json]
#
# --budget: runs only section 10, the budget measurement: sizes, resume cost,
#           ratchet. Fast, for the debrief and the startup hook.
# --strict: exits with code 1 if at least one warning is left (useful in CI).
# --json  : a JSON list on standard output, one object per warning
#           {"section","level","file","nature","message"}, and nothing else.
#
# set -f: without it, a scope like `src/auth/**` would be expanded by the shell
# when read, and files would be compared instead of the pattern.
set -euf

# Shared library, loaded before the cd to the audited root.
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPTS_DIR/ctx-common.sh"

ROOT=""
STALENESS=120
STRICT=0
BUDGET_ONLY=0
JSON=0

while [ $# -gt 0 ]; do
  case "$1" in
    --root)       ROOT="${2:-}"; shift 2 ;;
    --staleness)  STALENESS="${2:-120}"; shift 2 ;;
    --strict)     STRICT=1; shift ;;
    --budget)     BUDGET_ONLY=1; shift ;;
    --json)       JSON=1; shift ;;
    -h|--help)    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

CALL_DIR="$(pwd)"
ROOT_INFERRED=0
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  ROOT_INFERRED=1
fi
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"

# The block is read once here. The conv_read calls that follow, including inside $(...), come
# from memory: otherwise each call starts a find, a grep and an awk.
conv_load

# A block newer than these scripts: refuse to run rather than misread it.
scripts_version || exit 1

# In --json mode, standard output carries only the final list: all readable text
# goes to /dev/null, the list leaves through descriptor 3.
if [ "$JSON" -eq 1 ]; then
  exec 3>&1 1>/dev/null
fi

# In text mode, the report is written to a temporary file and only comes out at the end,
# through aggregate_output: the total of each warning nature is needed before printing the
# first one. The output is flushed on exit, including on an error or a signal, so that a
# run stopped halfway shows what was already said. Without a temporary file, the report is
# printed as is, without aggregation.
AGG_TMP=""
ROT_OUT=""
ROT_PID=""
final_output() {
  [ -z "$ROT_PID" ] || kill "$ROT_PID" 2>/dev/null || true
  [ -z "$ROT_OUT" ] || rm -f "$ROT_OUT"
  if [ -n "$AGG_TMP" ]; then
    exec 1>&5 5>&-
    aggregate_output < "$AGG_TMP" || true
    rm -f "$AGG_TMP"
  fi
  return 0
}
trap final_output EXIT
if [ "$JSON" -eq 0 ]; then
  AGG_TMP="$(mktemp "${TMPDIR:-/tmp}/ctx-audit.XXXXXX" 2>/dev/null)" || AGG_TMP=""
  if [ -n "$AGG_TMP" ]; then exec 5>&1 1>"$AGG_TMP"; fi
fi

TODAY="$(ctx_today)"
WARNINGS=0
BLOCKERS=0
SEC=""
JSON_RAW=""
TAB="$(printf '\t')"

# Warnings accumulate raw (section, level, file, message separated by the unit
# separator, one warning per record separator) and are escaped all at once at the end, in
# a single awk. One subprocess per field and per warning cost six milliseconds a warning,
# two seconds for three hundred. LC_ALL=C: a Latin-1 file name is an invalid UTF-8 byte
# sequence, and the BSD sed on macOS rejects the line. In C, a byte stays a byte. Control
# characters are removed, the tab becomes \t, the newline a space.
US="$(printf '\037')"
RS_="$(printf '\036')"
# The nature of a warning: its message without paths or numbers. Two warnings of the same
# nature say the same thing about different files ("no status header"). A word is a path
# if it carries a / or ends with a common file extension. awk source, shared by the JSON
# output and by the text aggregation.
NATURE_AWK='
function nature(m,   n, i, t, r, a) {
  n = split(m, a, " ")
  r = ""
  for (i = 1; i <= n; i++) {
    t = a[i]
    if (t ~ /\// || t ~ /^[`"\047(]*[A-Za-z0-9_.-]+\.(md|sh|json|jsonl|txt|yml|yaml|js|mjs|cjs|ts|py|toml|html|xml|csv|cfg|conf)[`"\047),.:;]*$/) continue
    gsub(/[0-9]+/, "", t)
    if (t == "") continue
    r = r (r == "" ? "" : " ") t
  }
  sub(/^[:,; ]+/, "", r)
  return r
}
'

json_output() { # <raw warnings>: the JSON list on standard output
  printf '%s' "$1" | LC_ALL=C awk "$NATURE_AWK"'BEGIN { RS = "\036"; FS = "\037"; n = 0 }
    function rep(s, de, par,   o, i) {
      o = ""
      while ((i = index(s, de)) > 0) { o = o substr(s, 1, i - 1) par; s = substr(s, i + length(de)) }
      return o s
    }
    function esc(s) {
      gsub(/\n/, " ", s)
      gsub(/[\001-\010\013-\037]/, "", s)
      s = rep(s, "\\", "\\\\")
      s = rep(s, "\"", "\\\"")
      return rep(s, "\t", "\\t")
    }
    NF >= 4 {
      m = $4
      for (k = 5; k <= NF; k++) m = m $k
      if (n++) printf ",\n"
      # nature before message: ctx-startup.sh reads the message by cutting everything after
      # `"message":"` up to the end of the line.
      printf "{\"section\":\"%s\",\"level\":\"%s\",\"file\":\"%s\",\"nature\":\"%s\",\"message\":\"%s\"}", esc($1), esc($2), esc($3), esc(nature(m)), esc(m)
    }
    END { if (n) printf "\n" }'
  return 0
}

# Aggregation of repetitive warnings, on the readable text only. Beyond 5 warnings of the
# same nature in a section, the first 3 are printed as is and one line says how many more
# follow. A blocker is never aggregated, the summary and the JSON list keep every warning:
# only the display is condensed. The filter reads the whole output, it needs the total of
# each nature before printing the first one.
aggregate_output() { # reads the report text on standard input
  LC_ALL=C awk "$NATURE_AWK"'
    { L[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (L[i] ~ /^[0-9]+b?\. /) { sec = L[i]; sub(/ .*/, "", sec) }
        if (substr(L[i], 1, 6) == "  [!] ") {
          K[i] = sec SUBSEP nature(substr(L[i], 7))
          T[K[i]]++
        }
      }
      for (i = 1; i <= NR; i++) {
        if (!(i in K)) { print L[i]; continue }
        k = K[i]; V[k]++
        if (T[k] <= 5 || V[k] <= 3) print L[i]
        if (T[k] > 5 && V[k] == 3) {
          n = k; sub(/^[^\034]*\034/, "", n)
          printf "  [!] ... and %d more of the same nature (%s)\n", T[k] - 3, n
        }
      }
    }'
  return 0
}

# The file a warning points at: what comes before " : ", or the first word if it
# looks like a path. Empty when the message does not point at a file.
file_of_message() { # <message>
  local m="$1" t
  case "$m" in
    *": "*) t="${m%%: *}"
            case "$t" in *" "*) ;; *) printf '%s' "$t"; return 0 ;; esac ;;
  esac
  t="${m%% *}"
  case "$t" in *[.,/]*) printf '%s' "${t%,}" ;; esac
  return 0
}

report() { # <level> <message> [<file>]
  local fic="${3:-}"
  WARNINGS=$((WARNINGS + 1))
  [ "$1" = blocker ] && BLOCKERS=$((BLOCKERS + 1))
  if [ "$JSON" -eq 1 ]; then
    [ -n "$fic" ] || fic="$(file_of_message "$2")"
    JSON_RAW="$JSON_RAW$SEC$US$1$US$fic$US$2$RS_"
  fi
  return 0
}
warn()  { printf '  [!] %s\n' "$1"; report warning "$@"; }
block() { printf '  [!!] %s\n' "$1"; report blocker "$@"; }
ok()    { printf '  [ok] %s\n' "$1"; }
info()  { printf '  ... %s\n' "$1"; }

# Age in days of a date, by ctx_days_since, cached per date: hundreds of pages share a few
# dates, and each call costs three `date`. The result is in DAYS, empty when the date is
# unreadable.
AGES=""
DAYS=""
days_since() { # <YYYY-MM-DD>: sets DAYS
  DAYS=""
  [ -n "${1:-}" ] || return 0
  if list_value "$AGES" "$1"; then DAYS="$VALUE"; return 0; fi
  DAYS="$(ctx_days_since "$1")"
  AGES="$AGES$NL$1=$DAYS"
  return 0
}
# wc pads the number with spaces on BSD: arithmetic swallows them, no extra tr needed.
count_lines() { local n; n="$(wc -l < "$1")"; printf '%s\n' "$((n + 0))"; }
# Characters of a file, not bytes: in C, tr removes UTF-8 continuation bytes (0x80 to
# 0xBF), one byte per character remains. Accented docs weigh 2% less in characters, a table
# of symbols or emojis much less.
count_chars() { local n; n="$(LC_ALL=C tr -d '\200-\277' < "$1" | wc -c)"; printf '%s\n' "$((n + 0))"; }
# Same measure on standard input.
count_chars_stdin() { local n; n="$(LC_ALL=C tr -d '\200-\277' | wc -c)"; printf '%s\n' "$((n + 0))"; }

# generic measure: <file> <label> <warning> <blocker> [<blocker in characters>]
#                  [<thresholds key>] [<warning in characters>]
# A line budget does not see a file of a few very wide lines: the character threshold
# catches it. It is overridden by `seuils: car-<key>=N` (warning, the blocker follows).
measure() {
  mf="$1"; ml="$2"; ma="$3"; mb="$4"; mo="${5:-0}"; mk="${6:-$1}"; mac="${7:-0}"
  [ -f "$mf" ] || return 0
  # A deferred file is judged by the ratchet, at the end of section 10.
  deferred_of "$mk"
  if [ -n "$DEF_N" ]; then return 0; fi
  thresholds_of "$mk" "$ma" "$mb"
  ma="$THR_A"; mb="$THR_B"
  mq=0
  if [ "$mo" -gt 0 ]; then
    thresholds_of "car-$mk" "$mac" "$mo"
    mac="$THR_A"; mo="$THR_B"
    mq="$(count_chars "$mf")"
  fi
  mn="$(count_lines "$mf")"
  if [ "$mn" -gt "$mb" ]; then
    block "$ml: $mn lines, blocker threshold $mb"
  elif [ "$mo" -gt 0 ] && [ "$mq" -gt "$mo" ]; then
    block "$ml: $mq characters, blocker threshold $mo"
  elif [ "$mn" -gt "$ma" ]; then
    warn "$ml: $mn lines, warning threshold $ma"
  elif [ "$mac" -gt 0 ] && [ "$mq" -gt "$mac" ]; then
    warn "$ml: $mq characters, warning threshold $mac"
  else
    ok "$ml: $mn lines"
  fi
}

# Heading depth. GitLab is the only guide to publish a numeric split rule: beyond five
# levels, it is several topics, not one.
# A single awk for all the given files (one per line on standard input): prints
# `depth<TAB>path` for those that reach five levels, headings outside code blocks.
heading_depths() {
  local list
  list="$(cat)"
  [ -n "$list" ] || return 0
  printf '%s\n' "$list" | sed 's|^|./|' | tr '\n' '\000' | xargs -0 awk -v T="$TAB" '
    function fin() { if (f != "" && max >= 5) { sub(/^\.\//, "", f); print max T f } }
    FNR == 1 { fin(); f = FILENAME; fence = 0; max = 0 }
    /^```/ { fence = !fence; next }
    !fence && /^#+ / { n = index($0, " ") - 1; if (n > max) max = n }
    END { fin() }' 2>/dev/null || true
  return 0
}

# Path declared in the block (`docs:`, `archives:`), without the trailing /. `aucune`
# (or `non`, `-`) turns the surface off, a missing line means the default.
declared_path() { # <key> <default>
  local v
  v="$(conv_read "$1")"
  case "$v" in
    aucun|aucune|non|none|-) return 0 ;;
    '') v="$2" ;;
  esac
  v="${v%%[[:space:],]*}"
  while [ "${v%/}" != "$v" ]; do v="${v%/}"; done
  printf '%s' "$v"
  return 0
}
DOCS_DIR="$(declared_path docs docs)"
ARCH_DIR="$(declared_path archives archives)"
# Plans directory, optional key `plans:` (plans/ by default), without a leading ./
PLANS_DIR="$(declared_path plans plans)"
while [ "${PLANS_DIR#./}" != "$PLANS_DIR" ]; do PLANS_DIR="${PLANS_DIR#./}"; done
# Executed plans (section 11) are read from the output of ctx-rotation.sh --plans
# --dry-run, which takes more than a second on a repo of several dozen plans. It only
# depends on the root: it runs in the background during sections 0 to 10, and section 11
# picks up its output. The file is removed on exit, and the job stops with the script.
# Without a temporary file, section 11 runs it itself, as before.
if [ "$BUDGET_ONLY" -eq 0 ] && [ -n "$PLANS_DIR" ] && [ -d "$PLANS_DIR" ] && [ -f "$SCRIPTS_DIR/ctx-rotation.sh" ]; then
  ROT_OUT="$(mktemp "${TMPDIR:-/tmp}/ctx-audit.XXXXXX" 2>/dev/null)" || ROT_OUT=""
  if [ -n "$ROT_OUT" ]; then
    bash "$SCRIPTS_DIR/ctx-rotation.sh" --plans --dry-run --root "$ROOT" >"$ROT_OUT" 2>/dev/null 3>&- 5>&- &
    ROT_PID=$!
  fi
fi
# Formats read in French and in English, whatever `langue:` says: a project converted
# before the translation keeps French files.
RE_RESUME='la reprise|resume|handoff|hand-off|restart'
RE_BLOCK='reprise|resume|handoff|hand-off|restart'
RESUME_LABEL='Resume state'
RE_STATUS='Statut|Status'
RE_SCOPE='Port|Scope'
RE_REPLACED='Remplac|Replace|Supersed'
RE_ORIGIN='Origine|Origin'

# Directories that never count, neither in the docs nor in the project size: heavy
# generated output and the `ignorer:` key, never what .gitignore excludes. Computed once
# here, the $(exclusions_find) calls that follow read memory. Section 10 names each pruning.
exclusions_load
EXCLUDED="$(exclusions_find)"
if [ -n "$ARCH_DIR" ] && [ "$ARCH_DIR" != archives ]; then
  EXCLUDED="$EXCLUDED -not -path ./$ARCH_DIR/*"
fi
# The same list, as pruning: find no longer descends into .git, node_modules or dist at
# all instead of walking them to discard each file. On a repo of 150,000 files with
# 100,000 in .git, the walk is seven times shorter for the same list. It is derived from
# exclusions_find by exclusions_prune, a single source: each `-not -path X/*` becomes
# `-path X`. The declared archives folder, if it is not archives/, is added.
if [ -n "$ARCH_DIR" ] && [ "$ARCH_DIR" != archives ]; then
  PRUNE=( $(exclusions_prune -not -path "./$ARCH_DIR/*") )
else
  PRUNE=( $(exclusions_prune) )
fi
find_pruned() { # <start> <find tests...>: find outside the excluded directories, paths on output
  local start="$1"
  shift
  find "$start" "${PRUNE[@]}" -o "$@" -print 2>/dev/null
  return 0
}
SUBMODULES="$(submodules)"
# The block is read once, here. Exceptions, thresholds and deferrals are then looked up in
# memory, without a subprocess per file: on a repo of several hundred pages, one
# conv_threshold per page (two sed per entry) cost seconds.
NL='
'
TRIM=""
trim() { # <text>: sets TRIM, without leading and trailing blanks
  TRIM="${1#"${1%%[![:space:]]*}"}"
  TRIM="${TRIM%"${TRIM##*[![:space:]]}"}"
  return 0
}
# `name=value` entries of a block list, one per line, each preceded by a newline so that
# they are found by "$NL$name=". <numeric> keeps those whose value is an integer, <free>
# keeps everything that carries an =.
block_entries() { # <key> <numeric|free>
  local e name val list=""
  while IFS= read -r e; do
    case "$e" in *=*) ;; *) continue ;; esac
    trim "${e%%=*}"; name="${TRIM#./}"
    trim "${e#*=}"; val="$TRIM"
    [ -n "$name" ] || continue
    if [ "$2" = numeric ]; then
      case "$val" in ''|*[!0-9]*) continue ;; esac
    fi
    list="$list$NL$name=$val"
  done <<EOT
$(conv_read "$1" | tr ',' '\n')
EOT
  printf '%s' "$list"
  return 0
}
# Value of `key=value` in a list of lines `\nkey=value`, set in VALUE. Code 1 if the key
# is not there. The `case *"key="*` test is fast, but `${list#*"key="}` is not: on three
# hundred entries, two seconds. The value is therefore read through the prefix length.
VALUE=""
list_value() { # <list> <key>
  local list="$1" key="$2" before rest
  VALUE=""
  case "$list" in
    *"$NL$key="*)
      before="${list%%"$NL$key="*}"
      rest="${list:$((${#before} + ${#key} + 2))}"
      VALUE="${rest%%"$NL"*}"
      return 0 ;;
  esac
  return 1
}
EXCEPTIONS="$(conv_read exceptions)"
EXC_LIST=""
if [ -n "$EXCEPTIONS" ]; then EXC_LIST="$(block_entries exceptions free)"; fi
exception_of() { # <type> <path>: code 0 if `exceptions: type=pattern` covers the path (shell glob)
  local type="$1" path="${2#./}" e pattern IFS="$NL"
  [ -n "$EXC_LIST" ] || return 1
  for e in $EXC_LIST; do
    case "$e" in "$type="*) ;; *) continue ;; esac
    pattern="${e#*=}"
    [ -n "$pattern" ] || continue
    # in a case, * also covers /, so ** and * are equal here
    # shellcheck disable=SC2254
    case "$path" in $pattern) return 0 ;; esac
  done
  return 1
}

# Block thresholds: `seuils: <file>=N` sets the file's WARNING threshold to N. The
# blocker threshold follows in the same ratio as the BUDGET.md defaults, rounded to the
# integer.
THR_DECL="$(conv_read seuils)"
THR_LIST=""
if [ -n "$THR_DECL" ]; then THR_LIST="$(block_entries seuils numeric)"; fi
THR_A=0; THR_B=0
thresholds_of() { # <key> <default warning> <default blocker>: sets THR_A and THR_B
  local n="$2"
  THR_A="$2"; THR_B="$3"
  if list_value "$THR_LIST" "${1#./}"; then n="$VALUE"; fi
  if [ "$n" != "$2" ] && [ "$2" -gt 0 ]; then
    THR_A="$n"
    THR_B=$(( ($3 * n + $2 / 2) / $2 ))
  fi
  return 0
}

# Default thresholds of a convention file, those of BUDGET.md. DA is 0 for a file the
# budget does not know.
DA=0; DB=0
defaults_of() { # <file>: sets DA and DB
  DA=0; DB=0
  case "$1" in
    CLAUDE.md)    DA=150; DB=200 ;;
    CODEMAP.md)   DA=300; DB=400 ;;
    TODOS.md)     DA=200; DB=300 ;;
    CHANGELOG.md) DA=1000; DB=1500 ;;
    */CODEMAP.md) DA=200; DB=250 ;;
    */CLAUDE.md)  DA=40; DB=60 ;;
  esac
  if [ "$DA" -eq 0 ] && [ -n "$DOCS_DIR" ]; then
    case "$1" in "$DOCS_DIR"/*.md) DA=250; DB=300 ;; esac
  fi
  return 0
}

# Ratchet `ajourne: <file>=N@YYYY-MM-DD`: an overshoot is frozen at its value and date.
# DEF_LIST keeps `file=N` per readable entry, N empty when it is not an integer.
DEFERRED="$(conv_read ajourne)"
DEF_N=""
DEF_LIST=""
if [ -n "$DEFERRED" ]; then
  while IFS= read -r e; do
    trim "$e"; e="${TRIM#./}"
    case "$e" in *=*@*) ;; *) continue ;; esac
    trim "${e%%=*}"; name="$TRIM"
    trim "${e#*=}"; trim "${TRIM%%@*}"; val="$TRIM"
    case "$val" in ''|*[!0-9]*) val="" ;; esac
    DEF_LIST="$DEF_LIST$NL$name=$val"
  done <<EOT
$(printf '%s\n' "$DEFERRED" | tr ',' '\n')
EOT
fi
deferred_of() { # <file>: sets DEF_N (the frozen lines), empty without a readable entry
  DEF_N=""
  if list_value "$DEF_LIST" "${1#./}"; then DEF_N="$VALUE"; fi
  return 0
}

# Path without the . and .. segments, reading nothing from disk. The result is in NORM,
# not on output: a subshell per link is expensive on a big repo.
NORM=""
normalize() { # <path>
  local IFS=/ seg out=""
  for seg in $1; do
    case "$seg" in
      ''|.) ;;
      ..) case "$out" in
            ''|..|*/..) out="${out:+$out/}.." ;;
            */*) out="${out%/*}" ;;
            *) out="" ;;
          esac ;;
      *) out="${out:+$out/}$seg" ;;
    esac
  done
  NORM="$out"
  return 0
}

# A path under a never-initialized submodule does not resolve, and that is not a docs
# defect: the link is valid as soon as `git submodule update` runs.
empty_submodule() { # <normalized path>: code 0 if it is under an uninitialized submodule
  local p IFS="$NL"
  for p in $SUBMODULES; do
    case "$1" in
      "$p"|"$p"/*) if [ ! -e "$p/.git" ]; then return 0; fi ;;
    esac
  done
  return 1
}

# A markdown without its code blocks, HTML comments, code spans and indented code: what
# they contain is an example, never a link or a path of the docs.
# A block indented by four spaces or a tab only counts as code if it follows a blank line
# and does not live in a list: an indented sub-list remains docs.
# The same program serves both uses: the cleaned text of a file (links = 0), or the
# `](target)` links of several files at once, one per line `file<US>target` (links = 1).
AWK_MD='
  BEGIN { blank = 1 }
  FNR == 1 { fence = 0; com = 0; code = 0; list = 0; blank = 1 }
  /^[ \t]*```/ { fence = !fence; next }
  fence { next }
  {
    ind = ($0 ~ /^(    |\t)/)
    if ($0 ~ /^[ \t]*$/) { blank = 1; if (!code && !links) print; next }
    if (ind && (code || (blank && !list))) { code = 1; blank = 0; next }
    code = 0
    if ($0 ~ /^ ? ? ?([-*+]|[0-9]+[.)])[ \t]/) list = 1
    else if (blank && $0 ~ /^[^ \t]/) list = 0
    blank = 0
    l = $0; out = ""
    while (length(l) > 0) {
      if (com) {
        i = index(l, "-->")
        if (i == 0) { l = "" } else { l = substr(l, i + 3); com = 0 }
      } else {
        i = index(l, "<!--")
        if (i == 0) { out = out l; l = "" }
        else { out = out substr(l, 1, i - 1); l = substr(l, i + 4); com = 1 }
      }
    }
    res = ""
    while ((i = index(out, "`")) > 0) {
      rest = substr(out, i + 1)
      j = index(rest, "`")
      if (j == 0) break
      res = res substr(out, 1, i - 1)
      out = substr(rest, j + 1)
    }
    if (!links) { print res out; next }
    t = res out
    f = FILENAME; sub(/^\.\//, "", f)
    while (match(t, /\]\([^)#][^)]*\)/)) {
      print f U substr(t, RSTART + 2, RLENGTH - 3)
      t = substr(t, RSTART + RLENGTH)
    }
  }'
md_no_code() { # <file>
  awk -v links=0 "$AWK_MD" "$1" 2>/dev/null
  return 0
}
# The links of all the files of a list (one path per line on standard input), a single awk
# instead of a subprocess per file. Prints `file<US>target`.
links_all() {
  local list
  list="$(cat)"
  [ -n "$list" ] || return 0
  printf '%s\n' "$list" | sed 's|^|./|' | tr '\n' '\000' | xargs -0 awk -v links=1 -v U="$US" "$AWK_MD" 2>/dev/null || true
  return 0
}

# The relative links of a markdown, one per line, anchors and examples excluded.
links_of() { # <file>
  md_no_code "$1" | grep -oE '\]\([^)#][^)]*\)' | sed 's/^](//; s/)$//' || true
  return 0
}

# A link that does not lead to a repo path: a scheme (http:, https:, mailto:, tel:,
# ftp:, sms:...), a scheme-relative link (//cdn.example.com/x.js), a bare anchor, a
# template placeholder. The scheme has at least two letters, so as not to take a Windows
# path for a scheme. `http-api.md` is a file, not a scheme.
RE_SCHEME='^[A-Za-z][A-Za-z0-9+.-]+:'
external_link() { # <link>: code 0 if it is not a repo path
  case "$1" in
    '#'*|//*|*'<'*|*'{{'*) return 0 ;;
  esac
  if [[ "$1" =~ $RE_SCHEME ]]; then return 0; fi
  return 1
}

# The target of a markdown link: `[a](x.md "title")` points to x.md, the title is not part
# of it. The result is in TARGET, anchor removed.
SQ="'"
TARGET=""
link_target() { # <text between parentheses>
  local l="$1"
  case "$l" in
    *' "'*) l="${l%% \"*}" ;;
    *" $SQ"*) l="${l%% $SQ*}" ;;
  esac
  TARGET="${l%%#*}"
  return 0
}

# Pages reached from the index by links, three hops at most.
pages_reached() { # <index> -> one path per line
  local front="$1" all="$1" next f dir link target i=0
  while [ "$i" -lt 3 ] && [ -n "$front" ]; do
    next=""
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      dir="$(dirname "$f")"
      while IFS= read -r link; do
        [ -n "$link" ] || continue
        if external_link "$link"; then continue; fi
        link_target "$link"; target="$TARGET"
        [ -n "$target" ] || continue
        normalize "$dir/$target"
        target="$NORM"
        case "$target" in *.md) ;; *) continue ;; esac
        if grep -qxF "$target" <<<"$all"; then continue; fi
        all="$all
$target"
        next="${next:+$next
}$target"
      done <<EOT2
$(links_of "$f")
EOT2
    done <<EOT
$front
EOT
    front="$next"
    i=$((i + 1))
  done
  printf '%s\n' "$all"
  return 0
}

# Are CLAUDE.md and AGENTS.md already linked? Symbolic link in either direction, or an
# `@AGENTS.md` line in CLAUDE.md.
agents_linked() {
  if [ -L CLAUDE.md ] || [ -L AGENTS.md ]; then
    if [ CLAUDE.md -ef AGENTS.md ]; then return 0; fi
  fi
  if grep -qE '^[[:space:]]*@(\./)?AGENTS\.md[[:space:]]*$' CLAUDE.md 2>/dev/null; then return 0; fi
  return 1
}

# The file that really carries the rules when CLAUDE.md is only a redirect: its target if
# it is a symbolic link, the first import if it contains only imports. Empty when CLAUDE.md
# carries its own rules or does not exist.
claude_redirect() {
  local others first
  [ -f CLAUDE.md ] || return 0
  if [ -L CLAUDE.md ]; then
    readlink CLAUDE.md
    return 0
  fi
  others="$(grep -m1 -vE '^[[:space:]]*(@[^[:space:]]+[[:space:]]*)?$' CLAUDE.md || true)"
  first="$(grep -m1 -E '^[[:space:]]*@' CLAUDE.md || true)"
  if [ -z "$others" ] && [ -n "$first" ]; then
    first="${first#"${first%%[![:space:]]*}"}"
    first="${first#@}"
    printf '%s\n' "${first%%[[:space:]]*}"
  fi
  return 0
}
CLAUDE_REDIRECT="$(claude_redirect)"

# An obvious test value in a test file: the fixture of a leak scanner, not a key that
# leaked. Both conditions together, a real value in a test file is still reported.
fake_secret() { # <git grep line: path:line:content>
  local path="${1%%:*}" content
  case "/$path" in
    */tests/*|*/test/*|*/__tests__/*|*/fixtures/*|*/spec/*|*/test_*|*_test.*|*.test.*|*.spec.*) ;;
    *) return 1 ;;
  esac
  content="${1#*:}"; content="${content#*:}"
  grep -qiE 'factice|fake|dummy|example|exemple|placeholder|changeme|redacted|xxxx|0000|(.)\1\1\1\1\1\1' <<<"$content"
}

# markdown doc files, outside archives and dependencies
docs_md() {
  find_pruned . -name '*.md' | sed 's|^\./||' | sort
}

# A log is a markdown with dated entries. The CHANGELOG carries the format the block
# declares, or the one `log_detect` finds. The other logs of the docs are read as
# `## ...YYYY-MM-DD`, the most common format.
RE_DATE_TITLE="$(log_pattern date-titre)"
LOG_RE=""
log_pattern_of() { # <file>: sets LOG_RE, empty if the log has no recognized format
  if [ "$1" = CHANGELOG.md ]; then
    LOG_RE="$(log_pattern "$(log_detect CHANGELOG.md)")"
  else
    LOG_RE="$RE_DATE_TITLE"
  fi
  return 0
}
count_dated_entries() { # <file> -> number of dated entries
  log_pattern_of "$1"
  if [ -n "$LOG_RE" ]; then grep -cE "$LOG_RE" "$1" 2>/dev/null || true; else echo 0; fi
  return 0
}

# Length of the "Resume state" block: from the heading that contains "resume" (or the
# French "reprise") to the next level-2 heading.
resume_block_lines() { # <TODOS.md> -> number of lines, 0 if absent
  awk -v re="$RE_BLOCK" 'BEGIN{n=0; inside=0}
       /^## /{ if (inside) exit; if (tolower($0) ~ re) inside=1 }
       inside{n++}
       END{print n}' "$1" 2>/dev/null || echo 0
}

# Longest section of a markdown, in lines, with its heading.
section_max() { # <file> -> "N heading"
  awk '/^## /{ if (t != "") print n, t; t=$0; n=0 } { n++ } END{ if (t != "") print n, t }' "$1" 2>/dev/null \
    | sort -rn | sed -n '1p'
}

# The entries of a log in file order, one line "N heading" each.
log_entries() { # <file>
  local f="$1" total
  log_pattern_of "$f"
  [ -n "$LOG_RE" ] || return 0
  total="$(awk 'END{print NR}' "$f")"
  grep -nE "$LOG_RE" "$f" 2>/dev/null | awk -F: -v total="$total" '
    { n = $1; t = substr($0, length($1) + 2)
      if (p) print n - p, pt
      p = n; pt = t }
    END { if (p) print total - p + 1, pt }' || true
  return 0
}

# Longest entry of a log, in lines.
longest_entry() { # <file> -> "N heading"
  log_entries "$1" | sort -rn | sed -n '1p'
  return 0
}

# The page headers, read in one go: one awk for all of them instead of a head and two grep
# per page. One line per page, `path<US>status<US>date<US>scope`: the status line within
# the first six lines, the first date it carries, the scope line within the first eight.
# An empty page has no line, the caller handles it separately.
page_headers() { # <pages, one per line, on standard input>
  local list
  list="$(cat)"
  [ -n "$list" ] || return 0
  printf '%s\n' "$list" | sed 's|^|./|' | tr '\n' '\000' \
    | xargs -0 awk -v rs="$RE_STATUS" -v rp="$RE_SCOPE" -v U="$US" '
        function fin() { if (f != "") { sub(/^\.\//, "", f); print f U st U da U po } }
        FNR == 1 { fin(); f = FILENAME; st = ""; da = ""; po = "" }
        FNR <= 6 && st == "" && $0 ~ rs {
          st = $0
          if (match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) da = substr($0, RSTART, RLENGTH)
        }
        FNR <= 8 && po == "" && $0 ~ rp { po = $0 }
        END { fin() }' 2>/dev/null || true
  return 0
}

echo "=============================================="
echo " Context audit: $(basename "$ROOT")"
echo " $TODAY"
echo "=============================================="

PROFILE="$(conv_read profil)"
DECLARED_SIZE="$(conv_read taille)"
BLOCK_V="$(conv_version)"

# Zones: a CODEMAP.md alone in a subdirectory, with no TODOS or CHANGELOG beside it. A
# standalone level carries the three pillars.
LEVELS=""
ZONES=""
for c in $(find_pruned . -name CODEMAP.md -path './*/*' | sort); do
  d="${c%/CODEMAP.md}"; d="${d#./}"
  grep -q '{{' "$c" 2>/dev/null && continue
  if [ -f "$d/TODOS.md" ] && [ -f "$d/CHANGELOG.md" ]; then
    LEVELS="$LEVELS $d"
  else
    ZONES="$ZONES $d"
  fi
done

if [ "$BUDGET_ONLY" -eq 0 ]; then

# --- 0. terrain ---------------------------------------------------------------
# What the project already carries. A new project has nothing, an existing one often has
# docs filed some other way, and sometimes another agent convention that would make a
# second source of truth. We graft onto what exists, we do not drop empty templates next
# to it.
echo
echo "0. Terrain"
SEC=0

KIT_COMPLETE=1
for f in CODEMAP.md TODOS.md CHANGELOG.md; do
  [ -f "$f" ] || KIT_COMPLETE=0
done

# Documentation already present, outside the kit
DOC_DIRS=""
for d in docs doc documentation wiki .claude/docs notes; do
  [ -d "$d" ] && DOC_DIRS="$DOC_DIRS $d"
done
ADR_DIRS=""
for d in adr docs/adr doc/adr docs/decisions docs/architecture/decisions; do
  [ -d "$d" ] && ADR_DIRS="$ADR_DIRS $d"
done
ROOT_MD="$(find . -maxdepth 1 -name '*.md' 2>/dev/null | sed 's|^\./||' \
  | grep -vE '^(CODEMAP|TODOS|CHANGELOG|CLAUDE|AGENTS|README|MEMORY)\.md$' | sort || true)"

[ -n "$DOC_DIRS" ] && info "existing documentation:$DOC_DIRS"
[ -n "$ADR_DIRS" ] && info "existing decisions:$ADR_DIRS"
if [ -n "$ROOT_MD" ]; then
  info "markdown at the root, outside the kit: $(printf '%s ' $ROOT_MD)"
  [ "$KIT_COMPLETE" -eq 0 ] && info "  each has an owner in the convention, see references/PROJECT-PROFILES.md"
fi

# Competing agent conventions. Two sources of truth always diverge, and nothing says so
# when it happens.
COMPETING=""
for c in AGENTS.md GEMINI.md .cursorrules .clinerules .windsurfrules CONVENTIONS.md \
         .github/copilot-instructions.md .cursor/rules memory-bank .roo; do
  [ -e "$c" ] && COMPETING="$COMPETING $c"
done
if [ -n "$COMPETING" ]; then
  for c in $COMPETING; do
    case "$c" in
      AGENTS.md)
        if [ -f CLAUDE.md ] && agents_linked; then
          info "AGENTS.md is linked to CLAUDE.md (symbolic link or @AGENTS.md), a single source of rules"
        elif [ -f CLAUDE.md ]; then
          warn "AGENTS.md and CLAUDE.md coexist. Claude Code does not read AGENTS.md, Codex does not read CLAUDE.md. Without a link, two sources diverge in silence. The link is an @AGENTS.md line at the top of CLAUDE.md, or a symbolic link"
        else
          info "AGENTS.md present, it carries the rules here. The convention grafts onto it instead of creating a CLAUDE.md"
        fi ;;
      memory-bank|.roo)
        warn "$c present, it is a competing agent memory convention. It carries the same knowledge as the pillars, and two copies diverge. Choose which one holds and archive the other" ;;
      *)
        info "$c present, another agent convention. Check that it does not repeat the pillars" ;;
    esac
  done
fi

# Block version. A block without a `version:` line or in an old version comes from an older
# skill: the UPGRADE mode of the skill fixes it. With no block at all, section 1 says so and
# ctx-init.sh adds it, there is nothing to upgrade.
case "$BLOCK_V" in
  0) ;;
  ''|*[!0-9]*)
    warn "the contexte:convention block carries an unreadable version ($BLOCK_V). Run the UPGRADE mode of the skill" "$(conv_find)" ;;
  *)
    if [ "$BLOCK_V" -lt "$CTX_VERSION" ]; then
      if [ -z "$(conv_read version)" ]; then
        warn "the contexte:convention block has no version: line, it comes from an old version of the skill (the current one is $CTX_VERSION). Run the UPGRADE mode of the skill" "$(conv_find)"
      else
        warn "the contexte:convention block is at version $BLOCK_V, the current one is $CTX_VERSION. Run the UPGRADE mode of the skill" "$(conv_find)"
      fi
    fi ;;
esac

if [ "$KIT_COMPLETE" -eq 1 ] && [ -z "$COMPETING" ]; then
  ok "a single convention carrier, nothing competes with the pillars"
elif [ "$KIT_COMPLETE" -eq 0 ]; then
  info "the kit is incomplete, see section 1. The SETUP mode grafts onto what exists"
fi

# --- 1. kit presence ----------------------------------------------------------
echo
echo "1. Context kit"
SEC=1
for f in CODEMAP.md TODOS.md CHANGELOG.md; do
  if [ -f "$f" ]; then ok "$f"; else warn "$f missing"; fi
done
if [ ! -f CLAUDE.md ]; then
  info "CLAUDE.md absent, the project rules have no support"
elif [ -n "$CLAUDE_REDIRECT" ]; then
  info "CLAUDE.md is only a redirect to $CLAUDE_REDIRECT, that file carries the rules"
  # A redirect that leads nowhere, or to an empty file: no rule is loaded.
  if [ ! -f "$CLAUDE_REDIRECT" ]; then
    warn "CLAUDE.md redirects to $CLAUDE_REDIRECT, which does not exist. No project rule is loaded" CLAUDE.md
  elif ! grep -q '[^[:space:]]' "$CLAUDE_REDIRECT" 2>/dev/null; then
    warn "CLAUDE.md redirects to $CLAUDE_REDIRECT, which is empty. No project rule is loaded" CLAUDE.md
  fi
elif ! grep -q '[^[:space:]]' CLAUDE.md 2>/dev/null; then
  warn "CLAUDE.md is empty. The project rules have no support, or an @AGENTS.md redirect if another file carries them" CLAUDE.md
else
  ok "CLAUDE.md"
fi
# Leftover of a four-pillar convention. The content has an owner elsewhere now, leaving it
# in place creates two sources of truth.
# A project that uses it on purpose declares it in ecarts: (MEMORY.md=<justification>):
# the warning becomes an info that quotes the justification.
if [ -f MEMORY.md ]; then
  MEMORY_GAP=""
  case "$(conv_read ecarts)" in
    *MEMORY.md=*)
      MEMORY_GAP="$(conv_read ecarts | sed -e 's/^.*MEMORY\.md=//' -e 's/,[[:space:]]*[A-Za-z][A-Za-z0-9._-]*=.*$//' -e 's/[[:space:]]*$//')"
      ;;
  esac
  if [ -n "$MEMORY_GAP" ]; then
    info "MEMORY.md committed at the root, gap declared in ecarts: $MEMORY_GAP"
  else
    warn "MEMORY.md present, the convention no longer has a memory pillar. Declare the gap in the ecarts: line of the block (MEMORY.md=<justification>), or drain the file: decisions to docs/decisions/, pitfalls to the module page or the sensitive zones of the CODEMAP, preferences to CLAUDE.md"
  fi
fi
if [ -z "$DOCS_DIR" ]; then
  info "the block declares docs: aucune, no pages in this project"
elif [ -d "$DOCS_DIR" ]; then
  ok "$DOCS_DIR/"
  [ -f "$DOCS_DIR/README.md" ] || warn "$DOCS_DIR/README.md missing, the index is required"
else
  warn "$DOCS_DIR/ missing"
fi
if [ -z "$ARCH_DIR" ]; then
  info "the block declares archives: aucune, nothing is archived in this project"
elif [ -d "$ARCH_DIR" ]; then
  ok "$ARCH_DIR/"
  [ -f "$ARCH_DIR/README.md" ] || warn "$ARCH_DIR/README.md missing, the index is required"
else
  warn "$ARCH_DIR/ missing"
fi

BLOCK_FILE="$(conv_find)"
if [ -n "$PROFILE" ]; then
  info "declared profile: $PROFILE"
elif [ -n "$BLOCK_FILE" ]; then
  info "contexte:convention block read in $BLOCK_FILE, no declared profile"
else
  info "no contexte:convention block, default paths"
fi

# Without --root, the root is inferred from git, so calling the script from a subproject
# audits the PARENT and not the subproject. Silent and costly.
if [ "$ROOT_INFERRED" -eq 1 ] && [ "$CALL_DIR" != "$ROOT" ]; then
  warn "called from ${CALL_DIR#"$ROOT"/}, but $ROOT is what gets audited. The root is inferred from git. To audit the subproject: ctx-audit.sh --root ${CALL_DIR#"$ROOT"/}"
fi

# Context outside git. A .md ignored by git (local notes, context-input/, CLAUDE.local.md)
# is still context, the audit reads it like the rest. But it travels neither to a colleague
# nor to another machine: an info, never a warning. What lives under a pruned folder
# (node_modules, an engine Library/, `ignorer:`) does not count. A single awk filters the
# git list against the pruning patterns, without a subprocess per path.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_IGNORED="$(git -c core.quotepath=off ls-files -o -i --exclude-standard -- '*.md' 2>/dev/null | LC_ALL=C awk -v ex="$EXCLUDED" '
    BEGIN {
      n = split(ex, words, " ")
      for (i = 1; i <= n; i++) {
        if (words[i] == "-not" || words[i] == "-path") continue
        p = words[i]
        gsub(/[][\\.+?(){}|^$]/, "\\\\&", p)
        gsub(/\*/, ".*", p)
        patterns[++k] = "^" p "$"
      }
    }
    {
      q = "./" $0; skip = 0
      for (i = 1; i <= k; i++) if (q ~ patterns[i]) { skip = 1; break }
      if (skip) next
      nb++
      if (nb <= 3) ex3 = ex3 (nb > 1 ? ", " : "") $0
    }
    END { if (nb > 0) printf "%d\t%s\n", nb, ex3 }' || true)"
  if [ -n "$GIT_IGNORED" ]; then
    info "${GIT_IGNORED%%"$TAB"*} context .md file(s) ignored by git: they travel neither to a colleague nor to another machine (examples: ${GIT_IGNORED#*"$TAB"})"
  fi
fi

# --- 1b. nested levels and zones ----------------------------------------------
# A monorepo carries several kits, each one a standalone level to debrief separately. A
# zone only carries a map, state and log stay at the root. In both cases the parent points,
# it does not absorb.
echo
echo "1b. Nested levels and zones"
SEC=1b
if [ -n "$LEVELS" ]; then
  for n in $LEVELS; do
    warn "$n carries its own kit, it is a level to audit and debrief separately: ctx-audit.sh --root $n"
    grep -q "$n" CODEMAP.md 2>/dev/null \
      || warn "$n is not cited anywhere in the root CODEMAP, the parent must point to it"
  done
else
  ok "no nested kit, a single level to maintain"
fi
if [ -n "$ZONES" ]; then
  for z in $ZONES; do
    info "zone: $z ($(count_lines "$z/CODEMAP.md") map lines$([ -f "$z/CLAUDE.md" ] && printf ', CLAUDE.md of %s lines' "$(count_lines "$z/CLAUDE.md")"))"
    grep -q "$z" CODEMAP.md 2>/dev/null \
      || warn "zone $z is not cited in the root CODEMAP, it must point to it"
  done
else
  info "no zone, the root CODEMAP carries the whole map"
fi
# A subdirectory CLAUDE.md without a map beside it: it loads when a file of the subtree is
# touched, but nothing says where the map of this zone is.
for c in $(find_pruned . -name CLAUDE.md -path './*/*' -not -path './.claude/*' | sort); do
  d="${c%/CLAUDE.md}"; d="${d#./}"
  [ -f "$d/CODEMAP.md" ] || info "$d carries a CLAUDE.md without a CODEMAP.md, a zone without a map"
done

# --- 2. freshness -------------------------------------------------------------
echo
echo "2. Freshness"
SEC=2
# The log format comes from the block, otherwise from what the CHANGELOG contains. The
# date of the last entry is read with the pattern of that format, outside code blocks.
CL_FORMAT="$(log_detect CHANGELOG.md)"
CL_DATE=""
if [ -f CHANGELOG.md ] && [ -n "$CL_FORMAT" ]; then
  CL_DATE="$(awk '/^[ \t]*```/{c=!c; next} !c' CHANGELOG.md \
             | grep -E "$(log_pattern "$CL_FORMAT")" | sed -n '1p' \
             | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sed -n '1p' || true)"
  if [ -n "$(conv_log_format)" ]; then
    info "log CHANGELOG.md: format $CL_FORMAT, declared by the block"
  else
    info "log CHANGELOG.md: format $CL_FORMAT, found in the file"
  fi
fi
if [ -n "$CL_DATE" ]; then
  days_since "$CL_DATE"; d="$DAYS"
  if [ -n "$d" ] && [ "$d" -gt 30 ]; then
    warn "last CHANGELOG entry on $CL_DATE, that is $d days"
  else
    ok "last CHANGELOG entry on $CL_DATE"
  fi
else
  warn "no dated entry in CHANGELOG.md (recognized formats: ## YYYY-MM-DD, ## [x] - YYYY-MM-DD, [YYYY-MM-DD] [TYPE])"
fi

# The map date: its update line, outside the contexte:convention block (a path date in
# `exceptions:` is not its own). Without that line, the first date outside the block. A
# dated pitfall line only comes first in that fallback.
CM_DATE=""
if [ -f CODEMAP.md ]; then
  CM_OUTSIDE_BLOCK="$(awk '/<!-- contexte:convention/{b=1} !b{print} b && /-->/{b=0}' CODEMAP.md)"
  CM_DATE="$(printf '%s\n' "$CM_OUTSIDE_BLOCK" \
             | grep -iE '(mise +[^ ]+ +jour|last +updated)' \
             | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sed -n '1p' || true)"
  [ -n "$CM_DATE" ] || CM_DATE="$(printf '%s\n' "$CM_OUTSIDE_BLOCK" \
             | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sed -n '1p' || true)"
fi
[ -n "$CM_DATE" ] && info "CODEMAP dated $CM_DATE" || warn "CODEMAP.md without an update date"

if [ -f TODOS.md ]; then
  if grep -qiE "$RE_RESUME" TODOS.md; then
    # The block date, from the heading that contains "resume" to the next heading: a date at
    # the top of the file or of a higher section is not the state's.
    TD_DATE="$(awk -v re="$RE_BLOCK" '/^## /{ if (inside) exit; if (tolower($0) ~ re) inside=1 } inside{print}' TODOS.md \
               | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sed -n '1p' || true)"
    days_since "${TD_DATE:-}"; d="$DAYS"
    if [ -n "$d" ] && [ "$d" -gt 14 ]; then
      warn "Resume state block dated $TD_DATE, that is $d days"
    else
      ok "Resume state block present (${TD_DATE:-no date})"
    fi
  else
    warn "TODOS.md has no '$RESUME_LABEL' block, a cold restart would lose the thread"
  fi
fi

# --- 3. modified scope --------------------------------------------------------
echo
echo "3. Scope changed since the last CHANGELOG entry"
SEC=3
CHANGED="$( { git status --porcelain -uall 2>/dev/null | sed 's/^...//' ;
             if [ -n "$CL_DATE" ]; then
               # Explicit time: a bare date is completed with the current time,
               # and the list of touched files would vary by the second.
               git log --since="${CL_DATE}T00:00:00" --name-only --pretty=format: 2>/dev/null
             else
               git log -20 --name-only --pretty=format: 2>/dev/null
             fi ; } | grep -v '^$' | sort -u || true)"
NB_CHANGED="$(printf '%s\n' "$CHANGED" | grep -c . || true)"
if [ "${NB_CHANGED:-0}" -eq 0 ]; then
  ok "nothing changed"
else
  info "$NB_CHANGED file(s) touched"
  head -15 <<<"$CHANGED" | sed 's/^/       /'
  [ "$NB_CHANGED" -gt 15 ] && printf '       ... and %s more\n' "$((NB_CHANGED - 15))"
fi

# --- 4. state of the docs/ pages ----------------------------------------------
echo
echo "4. Pages $DOCS_DIR/"
SEC=4
if [ -n "$DOCS_DIR" ] && [ -d "$DOCS_DIR" ]; then
  NB_PAGES=0
  DOCS_INDEX="$DOCS_DIR/README.md"
  REACHED=""
  INDEX_TXT=""
  if [ -f "$DOCS_INDEX" ]; then
    REACHED="$(pages_reached "$DOCS_INDEX")"
    INDEX_TXT="$(cat "$DOCS_INDEX")"
  fi
  # The awk returns nothing for an empty page: it is handled afterwards, like a missing header.
  PAGE_LIST="$(find "$DOCS_DIR" -name '*.md' -not -name 'README.md' 2>/dev/null | sort)"
  EMPTY_PAGES="$(find "$DOCS_DIR" -name '*.md' -not -name 'README.md' -empty 2>/dev/null | sort)"
  while IFS="$US" read -r f header vdate scope; do
    [ -n "$f" ] || continue
    NB_PAGES=$((NB_PAGES + 1))
    # A judgment already made, written in `exceptions: fiche=<path>`
    if [ -n "$EXCEPTIONS" ] && exception_of fiche "$f"; then continue; fi
    if [ -z "$header" ]; then
      warn "$f: no status header"
      continue
    fi
    case "$header" in
      *"🔴"*) warn "$f: marked obsolete, move to archives/ now" ;;
      *"🟡"*) warn "$f: marked to verify" ;;
    esac
    if [ -z "$vdate" ]; then
      warn "$f: header without a verification date"
    else
      days_since "$vdate"; d="$DAYS"
      if [ -n "$d" ] && [ "$d" -gt "$STALENESS" ]; then
        warn "$f: verified $d days ago (threshold $STALENESS)"
      fi
    fi
    # does the scope overlap a modified file? A page verified today has already been
    # reread, reporting it would make noise at every debrief. And an ADR is never redated,
    # it is superseded, so its scope does not need watching.
    case "$f" in *fecisions/*|*decisions/*|*/adr/*) scope="" ;; esac
    if [ -n "$scope" ] && [ "${NB_CHANGED:-0}" -gt 0 ] && [ "${vdate:-}" != "$TODAY" ]; then
      while IFS= read -r p; do
        prefix="${p%%\**}"
        prefix="${prefix%/}"
        [ -n "$prefix" ] || continue
        if grep -q "^$prefix" <<<"$CHANGED"; then
          warn "$f: its scope ($p) has moved, reread the page"
          break
        fi
      done <<EOT2
$(printf '%s' "$scope" | grep -oE '`[^`]+`' | tr -d '`' || true)
EOT2
    fi
    # indexed? Cited in the index by name, or reached from it by links, three hops at most
    # (root index, zone sub-index, page).
    base="${f##*/}"
    if [ -f "$DOCS_INDEX" ]; then
      case "$INDEX_TXT" in *"$base"*) ;; *)
        case "$NL$REACHED$NL" in *"$NL$f$NL"*) ;; *)
          warn "$f: missing from the index $DOCS_INDEX" ;;
        esac ;;
      esac
    fi
  done <<EOT
$(printf '%s\n' "$PAGE_LIST" | page_headers)
EOT
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    NB_PAGES=$((NB_PAGES + 1))
    if [ -n "$EXCEPTIONS" ] && exception_of fiche "$f"; then continue; fi
    warn "$f: no status header"
  done <<EOT
$EMPTY_PAGES
EOT
  [ "$NB_PAGES" -eq 0 ] && info "no page yet" \
                        || info "$NB_PAGES page(s) examined"
fi

# --- 5. modules without a page ------------------------------------------------
echo
echo "5. Modules without a page"
SEC=5
SRC=""
for d in src lib app packages apps internal cmd services; do [ -d "$d" ] && SRC="$SRC $d"; done
if [ -n "$SRC" ]; then
  found=0
  for base in $SRC; do
    for m in $(find "$base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort); do
      name="$(basename "$m")"
      case "$name" in .*|__pycache__|node_modules|test|tests) continue ;; esac
      # A subproject that carries its own kit is not a module of the parent. Asking it for
      # a page here would push to duplicate its docs, which the convention forbids. It is
      # reported in section 1b as a separate level. A zone that carries its map is already
      # documented by it.
      [ -f "$m/CODEMAP.md" ] && continue
      if [ ! -f "${DOCS_DIR:-docs}/modules/$name.md" ]; then
        info "$m: no page ${DOCS_DIR:-docs}/modules/$name.md"
        found=$((found + 1))
      fi
    done
  done
  [ "$found" -eq 0 ] && ok "each top-level module has its page or its zone map"
  [ "$found" -gt 0 ] && info "not all deserve a page, see references/DOCS-SYSTEM.md"
else
  info "no standard source directory detected"
fi

# --- 6. dead relative links ---------------------------------------------------
echo
echo "6. Dead links"
SEC=6
dead=0
# Code blocks, HTML comments, code spans and indented code are removed before looking for
# links: what they show is an example, not a docs link.
while IFS="$US" read -r f link; do
  [ -n "$link" ] || continue
  case "$f" in */*) dir="${f%/*}" ;; *) dir=. ;; esac
  # skip external links and template placeholders
  if external_link "$link"; then continue; fi
  link_target "$link"; target="$TARGET"
  [ -n "$target" ] || continue
  case "$target" in URL|url|LIEN|lien|link|chemin|path) continue ;; esac
  normalize "$dir/$target"
  norm="$NORM"
  # A judgment already made, written in `exceptions: lien=<path>`. It covers the target as
  # written, the target from the root, or the page that carries the link.
  if [ -n "$EXCEPTIONS" ]; then
    if exception_of lien "$target" || exception_of lien "$norm" || exception_of lien "$f"; then continue; fi
  fi
  if [ ! -e "$dir/$target" ] && [ ! -e "$target" ]; then
    if empty_submodule "$norm"; then continue; fi
    warn "$f: dead link to $target"
    dead=$((dead + 1))
  else
    # A link that resolves INTO the archives is a defect of another kind: the link works,
    # and it sends the reader to false or cold content. The convention forbids it, and
    # nothing saw it.
    if [ -n "$ARCH_DIR" ]; then
      case "$norm" in
        "$ARCH_DIR"/*|*/"$ARCH_DIR"/*)
          warn "$f: links to the archive $target. A living page does not cite an archive, remove the link or reword it as prose"
          dead=$((dead + 1)) ;;
      esac
    fi
  fi
done <<EOT
$(docs_md | links_all)
EOT
[ "$dead" -eq 0 ] && ok "no broken relative link"

# --- 7. archive consistency ---------------------------------------------------
# Four defects proven on a test repo, none was seen before: the index searched by base
# name, a replacement that no longer resolves, an archive recreated as a living file at the
# same path, and the index itself never measured or reread.
echo
echo "7. Archives"
SEC=7
if [ -n "$ARCH_DIR" ] && [ -d "$ARCH_DIR" ]; then
  nb=0
  # A single awk reads the header of all archives, the loop no longer launches anything per
  # file: on 250 archives, a dozen head and grep each cost 2.7 s. One record per file,
  # fields separated by US: the path, the ARCHIVE header present in the first 6 lines, the
  # backtick paths of the "Replaced by" line then of the "Origin" line (separated by RS_), a
  # rotation or a judgment said in prose in the first 8 lines, the number of lines read. The
  # index is read once: a path has no newline, searching the text is searching line by line.
  ARCH_INDEX=""
  if [ -f "$ARCH_DIR/README.md" ]; then ARCH_INDEX="$(cat "$ARCH_DIR/README.md")"; fi
  ARCH_REC="$(find "$ARCH_DIR" -name '*.md' -not -name 'README.md' 2>/dev/null | sort | awk -v remp="$RE_REPLACED" -v orig="$RE_ORIGIN" '
    function tokens(s,   t, r) {
      r = ""
      while (match(s, /`[^`]+`/)) {
        t = substr(s, RSTART + 1, RLENGTH - 2)
        r = r (r == "" ? "" : "\036") t
        s = substr(s, RSTART + RLENGTH)
      }
      return r
    }
    $0 != "" {
      f = $0; n = 0; e6 = 0; rot = 0; rem = ""; ori = ""; vrem = 0; vori = 0
      while ((getline l < f) > 0) {
        n++
        if (n > 8) continue
        if (n <= 6 && (index(l, "ARCHIV") > 0 || tolower(l) ~ /^[[:space:]]*>.*archiv/)) e6 = 1
        if (!vrem && l ~ remp) { vrem = 1; rem = l }
        if (!vori && l ~ orig) { vori = 1; ori = l }
        if (l !~ orig && l !~ remp && tolower(l) ~ /rotation|jugement|volontaire|deliber|intentionn|judg(e)?ment|on purpose/) rot = 1
      }
      close(f)
      printf "%s\037%d\037%s\037%s\037%d\037%d\n", f, e6, tokens(rem), tokens(ori), rot, n
    }')"
  while IFS="$US" read -r f e6 targets origins rotation nread; do
    [ -n "$f" ] || continue
    nb=$((nb + 1))
    # A judgment already made, written in `exceptions: archive=<path>`
    if [ -n "$EXCEPTIONS" ] && exception_of archive "$f"; then continue; fi
    # The header is written in capitals or not: a quote at the top that talks about
    # archive is enough. An "archive" word in the text does not count.
    if [ "$e6" -eq 0 ]; then
      warn "$f: no ARCHIVE header"
    fi
    # Index searched by FULL PATH. By base name, a name present in the "Replaced by" column
    # of another line was enough to pass.
    if [ -f "$ARCH_DIR/README.md" ]; then
      case "$ARCH_INDEX" in *"$f"*) ;; *) warn "$f: missing from the index $ARCH_DIR/README.md" ;; esac
    fi
    # Does the replacement still resolve? It is the field that gives the header its value,
    # and it rots silently.
    if [ -n "$targets" ]; then
      while IFS= read -r target; do
        case "$target" in *' '*|*aucun*|*none*|*'<'*|*'{{'*|'') continue ;; esac
        # A path carries a / and does not end with a /. "SKILL.md" or "references/" name a
        # part of a package, not a repo file.
        case "$target" in */) continue ;; esac
        case "$target" in */*) : ;; *) continue ;; esac
        [ -e "$target" ] || warn "$f: its replacement $target no longer exists"
      done <<EOT3
${targets//$RS_/$NL}
EOT3
    fi
    # A living file at the same path as the origin: two truths face to face, one of them
    # marked false.
    orig="${origins//$RS_/$NL}"
    # A rotation or a judgment written in prose in the header (deliberate recreation): the
    # coexistence is already settled, the warning would come back at every audit saying
    # nothing. The `Origin:` and `Replaced by:` lines do not count: they carry paths, and
    # `docs/modules/rotation.md` is not a judgment.
    # A summary placed by ctx-rotation.sh --plans (via ctx-archive.sh --summary) carries the
    # plan-resume marker: the living file is the expected gesture, not a recreation.
    summary=0
    if [ -n "$orig" ] && [ -f "$orig" ] && grep -qF 'plan-resume' "$orig"; then summary=1; fi
    if [ -n "$orig" ] && [ -e "$orig" ] && [ "$rotation" -eq 0 ] && [ "$summary" -eq 0 ]; then
      warn "$f: $orig also exists as a living file. An archive recreated at the same path leaves two truths face to face"
    fi
    # Size of an archive file. Wikipedia archive bots cap a page at 200 KB, for the same
    # reason: beyond that nobody digs, they suffer.
    # awk counts a last line without a newline that wc does not count: wc decides as soon
    # as awk goes over the threshold.
    if [ "$nread" -gt 1500 ]; then
      n="$(count_lines "$f")"
      if [ "$n" -gt 1500 ]; then warn "$f: $n lines. Beyond 1500 an archive is split, by month or by topic"; fi
    fi
  done <<EOT
$ARCH_REC
EOT
  # The index is the ONLY archive file that is really read, in archaeology. It was neither
  # measured nor reread, and it carried a false claim for 25 days.
  if [ -f "$ARCH_DIR/README.md" ]; then
    measure "$ARCH_DIR/README.md" "index $ARCH_DIR/README.md" 250 400
    while IFS= read -r p; do
      # Template placeholders are not paths.
      case "$p" in *'<'*|*'{{'*|*'>'*) continue ;; esac
      case "$p" in "$ARCH_DIR"/*) [ -e "$p" ] || warn "archive index: $p does not exist" ;; esac
    done <<EOT
$(grep -oE '`[^`]+`' "$ARCH_DIR/README.md" 2>/dev/null | tr -d '`' | sort -u || true)
EOT
  fi
  [ "$nb" -eq 0 ] && info "archives empty" || info "$nb archived item(s)"
  info "to look something up there: ctx-archaeology.sh <pattern>, never a bare grep"
elif [ -z "$ARCH_DIR" ]; then
  info "the block declares archives: aucune, nothing to check here"
fi

# --- 8. markers left in the code ----------------------------------------------
echo
echo "8. Markers in the code"
SEC=8
MARK="$(grep -rIn --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=archives \
        --exclude-dir=.venv --exclude-dir=dist --exclude-dir=build \
        -E '(TODO|FIXME|HACK|XXX)[:( ]' . 2>/dev/null | grep -vc '^$' || true)"
if [ "${MARK:-0}" -gt 0 ]; then
  info "${MARK} TODO/FIXME/HACK marker(s). The ones that matter must be in TODOS.md"
else
  ok "no marker"
fi

# --- 9. secrets, light heuristic ----------------------------------------------
echo
echo "9. Secrets"
SEC=9
SUSPECT="$(git grep -InE '(api[_-]?key|secret|token|password|passwd)[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9_/+-]{16,}' \
           -- . 2>/dev/null | grep -v -E '(\.example|\.sample|templates/|references/)' || true)"
# Two judgments are not redone at every audit: the paths of `exceptions: secret=<path>`,
# and the obvious test value in a test file (fixture of a leak scanner).
FILTERED=""
if [ -n "$SUSPECT" ]; then
  while IFS= read -r l; do
    if [ -n "$EXCEPTIONS" ] && exception_of secret "${l%%:*}"; then continue; fi
    if fake_secret "$l"; then continue; fi
    FILTERED="$FILTERED$l
"
  done <<EOT
$SUSPECT
EOT
fi
if [ -n "$FILTERED" ]; then
  FIRST="$(printf '%s' "$FILTERED" | sed -n '1,5p' | cut -d: -f1 | sort -u | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  warn "values that look like secrets in tracked files: $FIRST" "${FIRST%%,*}"
  printf '%s' "$FILTERED" | sed -n '1,5p' | sed 's/^/       /'
else
  ok "nothing suspect in tracked files"
fi

fi # end of sections 1 to 9, skipped by --budget

# --- 10. context budget -------------------------------------------------------
# Docs that are true but too long to be read are lost docs. Each surface has a target, a
# warning threshold and a blocker threshold. The numbers are those of references/BUDGET.md,
# they change there and here at the same time.
echo
echo "10. Context budget"
SEC=10

# project size, in files
NB_FILES="$(find_pruned . -type f | wc -l | tr -d ' ')"
if   [ "$NB_FILES" -lt 150 ]; then SIZE=petite
elif [ "$NB_FILES" -le 600 ]; then SIZE=moyenne
else SIZE=grande; fi
info "measured size: $SIZE, $NB_FILES files outside dependencies"
# A pruning is always named. Beyond the fixed list (node_modules, dist, target...), three
# sources can skip files: a game engine recognized by its marker at the root, a folder that
# carries a CACHEDIR.TAG, the block's `ignorer:` key.
# An engine is recognized by its marker, at the root or down to depth 3: each root found
# has its line, with its folder.
PR_CACHE=""; PR_IGN=""; PR_CAP=""
while IFS= read -r _l; do
  [ -n "$_l" ] || continue
  _c="${_l%%"$TAB"*}"; _d="${_l#*"$TAB"}"; _r="${_d%%"$TAB"*}"; _d="${_d#*"$TAB"}"
  case "$_c" in
    Unity|Unreal|Godot|'Unreal plugin')
      _m=""
      if [ "$_r" = . ]; then
        case "$_c" in
          Unity)  _m="Unity pruning, recognized by ProjectSettings/ProjectVersion.txt at the root" ;;
          Unreal) _m="Unreal pruning, recognized by a .uproject file at the root" ;;
          Godot)  _m="Godot pruning, recognized by project.godot at the root" ;;
        esac
      else
        case "$_c" in
          Unity)           _m="Unity pruning ($_r/), recognized by $_r/ProjectSettings/ProjectVersion.txt" ;;
          Unreal)          _m="Unreal pruning ($_r/), recognized by a .uproject file in $_r/" ;;
          'Unreal plugin') _m="Unreal plugin pruning ($_r/), recognized by its .uplugin file" ;;
          Godot)           _m="Godot pruning ($_r/), recognized by $_r/project.godot" ;;
        esac
      fi
      info "$_m: ${_d//, //, }/ count neither in the size nor in the checks" ;;
    CACHEDIR.TAG) PR_CACHE="${_d//, //, }/" ;;
    ignorer)      _n="$(exclusions_count_ignored "$_d")"
                  PR_IGN="${PR_IGN:+$PR_IGN, }$_d ($_n)"
                  PR_IGN_N=$(( ${PR_IGN_N:-0} + _n )) ;;
    cap)          PR_CAP="$_d" ;;
  esac
done <<EOT
$(exclusions_names_grouped)
EOT
[ -z "$PR_CACHE" ] || info "CACHEDIR.TAG pruning, signature verified: $PR_CACHE count neither in the size nor in the checks"
[ -z "$PR_IGN" ]   || info "the block's ignorer: key skips ${PR_IGN_N:-0} file(s): $PR_IGN"
[ -z "$PR_CAP" ]   || info "$PR_CAP game engine root(s) beyond the cap of 20: their generated folders are not pruned"
# The measure holds. `taille-forcee:` imposes it by hand and the checks then follow the
# forced value. A `taille:` line is no longer read since version 5.
FORCED_SIZE="$(conv_read taille-forcee)"
case "$FORCED_SIZE" in
  '') ;;
  petite|moyenne|grande)
    if [ "$FORCED_SIZE" != "$SIZE" ]; then
      info "the block forces « taille-forcee: $FORCED_SIZE », the measure gives $SIZE ($NB_FILES files). The checks follow the forced value. Remove it if the measure fits" "$(conv_find)"
    fi
    SIZE="$FORCED_SIZE" ;;
  *) info "taille-forcee: $FORCED_SIZE is not a known size (petite, moyenne, grande), the measure is kept" ;;
esac
case "$BLOCK_V" in ''|*[!0-9]*) ;; *)
  if [ "$BLOCK_V" -ge 5 ] && [ -n "$DECLARED_SIZE" ]; then
    info "the taille: line is no longer read since version 5, the size is measured ($SIZE). Remove it, or turn it into taille-forcee:" "$(conv_find)"
  fi ;;
esac

# Root CLAUDE.md: neither state nor story. A file that carries many dates has absorbed
# history, and history has another owner.
# A CLAUDE.md reduced to a redirect carries nothing itself: we measure the file that
# carries the rules, and we do not say "ok" on a one-line file.
CLAUDE_READ=""
# An empty CLAUDE.md is reported in section 1, measuring it "ok" would contradict that.
if [ -f CLAUDE.md ] && grep -q '[^[:space:]]' CLAUDE.md 2>/dev/null; then
  if [ -z "$CLAUDE_REDIRECT" ]; then
    measure CLAUDE.md "CLAUDE.md" 150 200 40000
    CLAUDE_READ=CLAUDE.md
  elif [ -f "$CLAUDE_REDIRECT" ] && grep -q '[^[:space:]]' "$CLAUDE_REDIRECT" 2>/dev/null; then
    measure "$CLAUDE_REDIRECT" "$CLAUDE_REDIRECT (carries the rules of CLAUDE.md)" 150 200 40000 CLAUDE.md
    CLAUDE_READ="$CLAUDE_REDIRECT"
  fi
fi
if [ -n "$CLAUDE_READ" ]; then
  nd="$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$CLAUDE_READ" | wc -l | tr -d ' ')"
  [ "$nd" -gt 8 ] && warn "CLAUDE.md carries $nd dates, a state or a story has slipped in. State goes in TODOS, history in the CHANGELOG"
  grep -qiE '^\*\*(etat|état|state|status)|^#+ (.*[^[:alpha:]])?(etat|état|state|status)([^[:alpha:]]|$)' "$CLAUDE_READ" \
    && warn "CLAUDE.md carries a state paragraph. It belongs in the resume block of TODOS.md"
  # Careful heuristic, as an info: a line that carries a date AND a state or story verb. A
  # rules file says what is always true, not what happened.
  MONTHS_FR='janvier|fevrier|février|mars|avril|mai|juin|juillet|aout|août|septembre|octobre|novembre|decembre|décembre'
  MONTHS_EN='january|february|march|april|may|june|july|august|september|october|november|december'
  RE_FREE_DATE="[0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{1,2}(er|st|nd|rd|th)? ($MONTHS_FR|$MONTHS_EN) [0-9]{4}|($MONTHS_EN) [0-9]{1,2}(st|nd|rd|th)?,? [0-9]{4}"
  RE_STORY='(etat|état|statut|status|state)[^.]{0,30}( au | le | du | depuis |as of| on | since )|en cours|derni(e|è)re (session|cl(o|ô)ture|mise)|livr(e|é)|termin(e|é)|session du|nous avons|on a |j.ai |a (e|é)t(e|é)|reste (a|à) |prochaine (session|etape|étape)|in progress|last (session|debrief|update)|delivered|finished|completed|session of|we (have|did)|(^|[^[:alpha:]])i (did|have)|has been|remains to|next (session|step)'
  story="$(md_no_code "$CLAUDE_READ" | grep -iE "$RE_FREE_DATE" | grep -iE "$RE_STORY" || true)"
  ns_story="$(printf '%s' "$story" | grep -c . || true)"
  if [ "${ns_story:-0}" -ge 2 ]; then
    info "CLAUDE.md: $ns_story line(s) carry a date and a state or story verb, for example « $(head -1 <<<"$story" | cut -c1-70) ». State goes in the resume block of TODOS, the story in the CHANGELOG" CLAUDE.md
  fi
fi

# Unbounded startup instruction: a CLAUDE.md or AGENTS.md that orders reading in full a
# file longer than its blocker threshold. "read TODOS.md" loads the whole file, "read the
# resume block of TODOS.md" loads only a part.
RE_ORDER='(^|[^[:alpha:]])(lis|lire|lisez|read|ouvre|ouvrir|ouvrez|consulte|consulter)([^[:alpha:]]|$)'
RE_NEG="(^|[^[:alpha:]])(ne|n')[^.]{0,25}(pas|jamais|plus)|jamais|sans lire|do not|don't|never|inutile|pas besoin"
# A bounded read limits the scope: "the resume block of X", "section Y of X", "the first 40
# lines", "head -n", "only the resume block", "up to ...". A bare word bounds nothing:
# "first", "for the last session" do not say which part to read, and the file loads in full.
# The `X.md#title` anchor also bounds, it is tested apart in unbounded_orders.
# The start of a word is written (^|[^[:alpha:]]): "partir de" does not contain "partie".
AV='(^|[^[:alpha:]])'
RE_BOUND="${AV}(bloc|block|section|rubrique|chapitre|paragraphe|partie|heading|titre)[^.]{0,40}( de | du | d'| of | in | dans | from )"
RE_BOUND="$RE_BOUND|${AV}(uniquement|seulement|only)[^.]{0,30}${AV}(bloc|block|section|rubrique|partie|part|lignes|lines|header|heading|resume|reprise)"
RE_BOUND="$RE_BOUND|[0-9]+[[:space:]]+(premi|derni|first|last)|${AV}(premi[eè]res?|derni[eè]res?|first|last|top)[[:space:]]+[0-9]+"
RE_BOUND="$RE_BOUND|${AV}(head|tail)[[:space:]]+-|${AV}sed[[:space:]]+-n|[0-9]+[[:space:]]+(lignes|entrees|entrées|lines|entries)"
RE_BOUND="$RE_BOUND|${AV}(haut|debut|début|top|beginning|start)[[:space:]]+(de|du|of)[[:space:]]+(la |le |l'|the )?[A-Za-z0-9_./-]*[.]md"
RE_BOUND="$RE_BOUND|jusqu|${AV}(until|up to)${AV}|§"
# The lines of a file outside code blocks, each preceded by its number and ":".
numbered_lines() { # <file>
  awk '/^[ \t]*```/ { f = !f; next } !f { print NR ":" $0 }' "$1"
  return 0
}
unbounded_orders() { # <file>
  local f="$1" l num txt tok n seen=""
  [ -f "$f" ] || return 0
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    num="${l%%:*}"; txt="${l#*:}"
    if grep -qiE "$RE_NEG" <<<"$txt"; then continue; fi
    if grep -qiE "$RE_BOUND" <<<"$txt"; then continue; fi
    for tok in $(printf '%s\n' "$txt" | grep -oE '[A-Za-z0-9_./-]+\.md' | sort -u || true); do
      tok="${tok#./}"
      case "$txt" in *"$tok#"*) continue ;; esac
      [ -f "$tok" ] || continue
      case " $seen " in *" $tok "*) continue ;; esac
      seen="$seen $tok"
      defaults_of "$tok"
      if [ "$DA" -eq 0 ]; then DA=250; DB=300; fi
      thresholds_of "$tok" "$DA" "$DB"
      n="$(count_lines "$tok")"
      if [ "$n" -gt "$THR_B" ]; then
        warn "$f: orders reading $tok without bounding the read (line $num), yet it is $n lines, blocker threshold $THR_B. Name the part to read, for example « the resume block of $tok »" "$f"
      fi
    done
  done <<EOT
$(numbered_lines "$f" | grep -iE "$RE_ORDER" || true)
EOT
  return 0
}
unbounded_orders CLAUDE.md
if [ -f AGENTS.md ] && ! [ CLAUDE.md -ef AGENTS.md ]; then unbounded_orders AGENTS.md; fi

# Root CODEMAP, and its heaviest section
if [ -f CODEMAP.md ]; then
  measure CODEMAP.md "CODEMAP.md" 300 400 40000 CODEMAP.md 30000
  sm="$(section_max CODEMAP.md)"
  [ -n "$sm" ] && [ "${sm%% *}" -gt 60 ] \
    && info "heaviest CODEMAP section: ${sm#* }, ${sm%% *} lines. Above 60, it calls for a zone or a page"
fi

# TODOS: the file, the resume block, and what has no business there
if [ -f TODOS.md ]; then
  measure TODOS.md "TODOS.md" 200 300 30000 TODOS.md 20000
  nb="$(resume_block_lines TODOS.md)"
  thresholds_of reprise 50 80
  if   [ "$nb" -gt "$THR_B" ]; then block "Resume state block: $nb lines, blocker threshold $THR_B. It is rewritten from the current state, it does not pile up"
  elif [ "$nb" -gt "$THR_A" ]; then warn "Resume state block: $nb lines, warning threshold $THR_A"
  elif [ "$nb" -gt 0 ];  then ok "Resume state block: $nb lines"; fi
  nc="$(grep -c '^- \[x\]' TODOS.md || true)"
  [ "${nc:-0}" -gt 0 ] && warn "TODOS.md keeps $nc checked task(s). A done task is deleted, the fact lives in the CHANGELOG"
  ns="$(grep -ciE '^## .*(session|séance|seance)' TODOS.md || true)"
  [ "${ns:-0}" -gt 0 ] && warn "TODOS.md carries $ns session report section(s). That is CHANGELOG material, TODOS keeps only the future"
fi

# CHANGELOG and any other log: number of entries, length, longest entry
journal() { # <file> <label>
  local f="$1" lib="$2" ne n em ja jb ea eb
  [ -f "$f" ] || return 0
  ne="$(count_dated_entries "$f")"; n="$(count_lines "$f")"
  # `seuils: <log>=N` sets the warning in lines, the number of entries follows in the same ratio.
  thresholds_of "$f" 1000 1500
  ja="$THR_A"; jb="$THR_B"
  ea=$(( 40 * ja / 1000 )); eb=$(( 60 * jb / 1500 ))
  deferred_of "$f"
  if [ -n "$DEF_N" ]; then
    : # a deferred log is judged by the ratchet, at the end of section 10
  elif [ "${ne:-0}" -ge "$eb" ] || [ "$n" -gt "$jb" ]; then
    block "$lib: $ne entries, $n lines. Blocker threshold $eb entries or $jb lines. Rotate: ctx-rotation.sh --file $f"
  elif [ "${ne:-0}" -ge "$ea" ] || [ "$n" -gt "$ja" ]; then
    warn "$lib: $ne entries, $n lines. Warning threshold $ea entries or $ja lines. Rotate: ctx-rotation.sh --file $f"
  else
    ok "$lib: $ne entries, $n lines"
  fi
  # The cap of 25 lines per entry applies AT WRITING TIME. A log is append-only, the past
  # is not rewritten, so an old entry that is too long is an info and not a warning. Only
  # the three most recent are still ours to fix.
  em="$(log_entries "$f" | sed -n '1,3p' | sort -rn | sed -n '1p')"
  if [ -n "$em" ] && [ "${em%% *}" -gt 40 ]; then
    warn "$lib: recent entry of ${em%% *} lines (${em#* }). An entry fits in 25 lines, the detail goes in a page"
  else
    ev="$(longest_entry "$f")"
    # if and not an [ ] && chain: the function must return 0, otherwise set -e kills the audit
    # on the healthiest case, a log without an old entry of more than 40 lines.
    if [ -n "$ev" ] && [ "${ev%% *}" -gt 40 ]; then
      info "$lib: the longest log entry is ${ev%% *} lines, but it is old. A log is not rewritten, the cap of 25 lines applies at writing time"
    fi
  fi
  return 0
}
journal CHANGELOG.md "CHANGELOG.md"

# Markdown sizes, measured in one go: one wc and one grep for all files instead of several
# subprocesses per file. One line per file, `lines<TAB>dated entries<TAB>path`. Fine
# measures (heading depth) then only run on the files that exceed a low threshold.
md_sizes() { # <list of paths, one per line, on standard input>
  local list wc_out gr_out
  list="$(cat)"
  [ -n "$list" ] || return 0
  # A variable does not keep null bytes: the list stays in lines, xargs -0 receives them
  # through a tr at each use. The ./ in front of each path prevents a name like `a=b.md`
  # from being read as an option, and `total` from being confused with the wc total line.
  wc_out="$(printf '%s\n' "$list" | sed 's|^|./|' | tr '\n' '\000' | xargs -0 wc -l 2>/dev/null || true)"
  gr_out="$(printf '%s\n' "$list" | sed 's|^|./|' | tr '\n' '\000' | xargs -0 grep -cHE "$RE_DATE_TITLE" 2>/dev/null || true)"
  { printf '%s\n' "$wc_out"; printf '@@GREP\n'; printf '%s\n' "$gr_out"; } | awk -v T="$TAB" '
    /^@@GREP$/ { gr = 1; next }
    !gr {
      sub(/^[ \t]+/, ""); i = index($0, " ")
      if (i == 0) next
      p = substr($0, i + 1)
      if (p == "total") next
      sub(/^\.\//, "", p); n[p] = substr($0, 1, i - 1); order[++k] = p
      next
    }
    {
      i = length($0)
      while (i > 0 && substr($0, i, 1) != ":") i--
      if (i == 0) next
      p = substr($0, 1, i - 1); sub(/^\.\//, "", p); e[p] = substr($0, i + 1)
    }
    END { for (j = 1; j <= k; j++) { p = order[j]; print n[p] T (p in e ? e[p] : 0) T p } }'
  return 0
}
MD_TABLE="$(docs_md | md_sizes)"
LOGS=""
# Files with ten dated entries or more: the filter is done in awk, a shell loop over
# several thousand lines costs more than it brings.
while IFS="$TAB" read -r n ne f; do
  [ -n "$f" ] || continue
  case "$f" in CHANGELOG.md|TODOS.md|CODEMAP.md|CLAUDE.md) continue ;; esac
  LOGS="$LOGS$NL$f"
  journal "$f" "log $f"
done <<EOT
$(printf '%s\n' "$MD_TABLE" | awk -F "$TAB" '$2 + 0 >= 10')
EOT

# docs/ pages that are too long. A log has already been measured as a log, its answer is
# rotation and not splitting.
if [ -n "$DOCS_DIR" ] && [ -d "$DOCS_DIR" ]; then
  while IFS="$TAB" read -r n ne f; do
    [ -n "$f" ] || continue
    case "$LOGS" in *"$NL$f"*) continue ;; esac
    deferred_of "$f"
    if [ -n "$DEF_N" ]; then continue; fi
    thresholds_of "$f" 250 300
    if   [ "$n" -gt "$THR_B" ]; then block "$f: $n lines, blocker threshold $THR_B. Split into two topics"
    elif [ "$n" -gt "$THR_A" ]; then warn "$f: $n lines, warning threshold $THR_A"; fi
  done <<EOT
$(find "$DOCS_DIR" -name '*.md' -not -name 'README.md' 2>/dev/null | sort | md_sizes)
EOT
fi

# Heading depth. A file with five levels or more carries several topics, it is the only
# numeric split rule a style guide publishes. Reported only beyond the target, otherwise
# it is noise: only files of more than 150 lines are read.
BIG="$(printf '%s\n' "$MD_TABLE" | awk -F "$TAB" '$1 + 0 > 150 { print $3 }')"
while IFS="$TAB" read -r d f; do
  [ -n "$f" ] || continue
  n="$(count_lines "$f")"
  info "$f: $d heading levels over $n lines. Beyond four, it is often several topics to split"
done <<EOT
$(printf '%s\n' "$BIG" | heading_depths)
EOT

# existing zones
for z in $ZONES; do
  measure "$z/CODEMAP.md" "zone map $z" 200 250 25000 "$z/CODEMAP.md" 20000
  [ -f "$z/CLAUDE.md" ] && measure "$z/CLAUDE.md" "zone CLAUDE.md $z" 40 60
done
for c in $(find_pruned . -name CLAUDE.md -path './*/*' -not -path './.claude/*' | sort); do
  d="${c%/CLAUDE.md}"; d="${d#./}"
  [ -f "$d/CODEMAP.md" ] || measure "$c" "zone CLAUDE.md $d" 40 60
done

# LINE length in the state files. A budget counted in lines does not see a table cell that
# swallowed a whole proof. Beyond the threshold (800 by default, `seuils: ligne=N`), one
# warning per file. ``` code blocks do not count.
thresholds_of ligne 800 0
LINE_LIMIT="$THR_A"
long_lines() { # <file>: "number line_number length" of the lines outside code blocks beyond the threshold
  # The length is counted in characters: with mawk, length counts bytes, and a line of 508
  # accented characters passed for a line of more than 800. In C, tr removes the UTF-8
  # continuation bytes (0x80 to 0xBF), only one byte per character remains. The filter is
  # done before awk and not in awk: an awk that reads UTF-8 itself would read the range as
  # code points. Newlines stay, the numbering is intact.
  LC_ALL=C tr -d '\200-\277' < "$1" | LC_ALL=C awk -v s="$LINE_LIMIT" '
    /^[ \t]*```/ { f = !f; next }
    !f && length($0) > s { n++; if (length($0) > m) { m = length($0); l = NR } }
    END { if (n > 0) print n, l, m }'
  return 0
}
LL_SEEN=" "
for f in TODOS.md CODEMAP.md CLAUDE.md CHANGELOG.md \
  $(for z in $ZONES; do printf '%s\n' "$z/CODEMAP.md" "$z/CLAUDE.md"; done) \
  $(find_pruned . -name CLAUDE.md -path './*/*' -not -path './.claude/*' | sed 's|^\./||' | sort); do
  [ -f "$f" ] || continue
  case "$LL_SEEN" in *" $f "*) continue ;; esac
  LL_SEEN="$LL_SEEN$f "
  ll="$(long_lines "$f")"
  [ -n "$ll" ] || continue
  read -r ll_n ll_num ll_max <<<"$ll"
  warn "$f: $ll_n line(s) of more than $LINE_LIMIT characters, the longest is line $ll_num ($ll_max characters). Move the proof to a docs/ or archives/ page, the line keeps the fact, its date and a pointer" "$f"
done

# candidate zones: a code directory of 25 files or more, without a map.
# A plain info as long as the root CODEMAP holds its budget or the project is small, a
# warning as soon as it overflows on a medium or large project, because it is the natural
# way out for what overflows.
CM_LINES=0; [ -f CODEMAP.md ] && CM_LINES="$(count_lines CODEMAP.md)"
BASES=""
for d in src lib app packages apps internal cmd services; do [ -d "$d" ] && BASES="$BASES $d"; done
[ -n "$BASES" ] || BASES="."
candidates=0
for base in $BASES; do
  # As pruning: a folder that the list prunes (an Unity Library/, dist/, a CACHEDIR.TAG) is
  # not a candidate, `-not -path X/*` only removes its content and not itself.
  for m in $(find "$base" -mindepth 1 -maxdepth 1 "${PRUNE[@]}" -o -type d -print 2>/dev/null | sort); do
    name="${m#./}"
    case "$(basename "$name")" in .*|docs|"${DOCS_DIR##*/}"|archives|tests|test|scripts|node_modules|__pycache__) continue ;; esac
    [ -f "$name/CODEMAP.md" ] && continue
    nf="$(find_pruned "$name" -type f | wc -l | tr -d ' ')"
    [ "$nf" -ge 25 ] || continue
    mentions="$(grep -c "$(basename "$name")" CODEMAP.md 2>/dev/null || true)"
    candidates=$((candidates + 1))
    if [ "$SIZE" != petite ] && { [ "$CM_LINES" -gt 300 ] || [ "$SIZE" = grande ]; }; then
      warn "candidate zone: $name, $nf files, cited ${mentions:-0} times in the CODEMAP. Give it its map: ctx-init.sh --zone $name"
    else
      info "possible zone: $name, $nf files, cited ${mentions:-0} times in the CODEMAP"
    fi
  done
done
[ "$candidates" -eq 0 ] && [ -n "$ZONES" ] && ok "each code directory big enough carries its map"

# Rules `.claude/rules/*.md`. A rule without `paths:` loads at every session, like the root
# CLAUDE.md: its weight counts. A `globs:` rule never loads by path, only `paths:` is read,
# so it falls into the previous case.
fm_key() { # <file> <key>: code 0 if the file's YAML header carries the key
  awk -v k="$2" 'NR == 1 { if ($0 !~ /^---[ \t\r]*$/) exit; inside = 1; next }
       inside && /^---[ \t\r]*$/ { exit }
       inside && index($0, k ":") == 1 { t = 1; exit }
       END { exit t ? 0 : 1 }' "$1" 2>/dev/null
}
RULES_LINES=0
RULES_CHARS=0
RULES_NB=0
RULES_LIST=""
if [ -d .claude/rules ]; then
  for r in $(find .claude/rules -type f -name '*.md' 2>/dev/null | LC_ALL=C sort); do
    if fm_key "$r" globs; then
      warn "$r: declares globs:, which Claude Code does not read. Only paths: loads it when a related file is touched. As is, it loads at every session" "$r"
    fi
    if ! fm_key "$r" paths; then
      n="$(count_lines "$r")"
      RULES_LINES=$((RULES_LINES + n))
      RULES_CHARS=$((RULES_CHARS + $(count_chars "$r")))
      RULES_NB=$((RULES_NB + 1))
      RULES_LIST="${RULES_LIST:+$RULES_LIST, }${r#.claude/rules/} ($n)"
    fi
  done
fi
if [ "$RULES_NB" -gt 0 ]; then
  thresholds_of regles-sans-paths 150 200
  if   [ "$RULES_LINES" -gt "$THR_B" ]; then
    block "rules without paths: $RULES_LINES lines loaded by default at every session, blocker threshold $THR_B ($RULES_LIST). Give them a paths:" .claude/rules
  elif [ "$RULES_LINES" -gt "$THR_A" ]; then
    warn "rules without paths: $RULES_LINES lines loaded by default at every session, warning threshold $THR_A ($RULES_LIST). Give them a paths:" .claude/rules
  else
    info "$RULES_NB rule(s) without paths, $RULES_LINES lines loaded by default at every session: $RULES_LIST"
  fi
fi

# `@file` imports of a file: what it loads besides itself. Code blocks and code spans
# import nothing. Paths relative to the importing file.
imports_of() { # <file> -> existing paths from the root, one per line
  local f="$1" dir t
  dir="$(dirname "$f")"
  for t in $(md_no_code "$f" | grep -oE '(^|[[:space:]])@[A-Za-z0-9_./-]+' | sed 's/^[[:space:]]*@//' || true); do
    t="${t%[.,]}"
    case "$t" in */*|*.*) ;; *) continue ;; esac
    case "$t" in /*|~*) continue ;; esac
    normalize "$dir/$t"
    if [ -f "$NORM" ]; then printf '%s\n' "$NORM"; fi
  done
  return 0
}
# All the imports reached from a file, four hops at most, without duplicates.
imports_reached() { # <file>
  local front="$1" all="$1" next f c i=0
  while [ "$i" -lt 4 ] && [ -n "$front" ]; do
    next=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      for c in $(imports_of "$f"); do
        if grep -qxF "$c" <<<"$all"; then continue; fi
        all="$all
$c"
        next="${next:+$next
}$c"
      done
    done <<EOT
$front
EOT
    front="$next"
    i=$((i + 1))
  done
  printf '%s\n' "$all" | sed 1d
  return 0
}

# Total resume cost: everything a session loads before the first question. CLAUDE.md, its
# imports, the rules without paths, the resume block, the root map and the last three log
# entries.
c_claude=0; c_imports=0; c_resume=0; c_map=0; c_log=0
# The same cost in characters: k_* is to c_* what characters are to lines.
k_claude=0; k_imports=0; k_resume=0; k_map=0; k_log=0
if [ -f CLAUDE.md ]; then
  c_claude="$(count_lines CLAUDE.md)"; k_claude="$(count_chars CLAUDE.md)"
  for f in $(imports_reached CLAUDE.md); do
    c_imports=$((c_imports + $(count_lines "$f")))
    k_imports=$((k_imports + $(count_chars "$f")))
  done
elif [ -f AGENTS.md ]; then
  c_claude="$(count_lines AGENTS.md)"; k_claude="$(count_chars AGENTS.md)"
  for f in $(imports_reached AGENTS.md); do
    c_imports=$((c_imports + $(count_lines "$f")))
    k_imports=$((k_imports + $(count_chars "$f")))
  done
fi
if [ -f TODOS.md ]; then
  c_resume="$(resume_block_lines TODOS.md)"
  if [ "$c_resume" -gt 0 ]; then
    k_resume="$(awk -v re="$RE_BLOCK" '/^## /{ if (inside) exit; if (tolower($0) ~ re) inside=1 } inside' TODOS.md 2>/dev/null | count_chars_stdin)"
  fi
fi
if [ -f CODEMAP.md ]; then c_map="$(count_lines CODEMAP.md)"; k_map="$(count_chars CODEMAP.md)"; fi
if [ -f CHANGELOG.md ]; then
  for n in $(log_entries CHANGELOG.md | sed -n '1,3p' | awk '{print $1}'); do
    c_log=$((c_log + n))
  done
  # The first three entries of the file, from the first dated line over c_log lines.
  if [ "$c_log" -gt 0 ]; then
    log_pattern_of CHANGELOG.md
    jstart="$(grep -nE "$LOG_RE" CHANGELOG.md 2>/dev/null | sed -n '1p' | cut -d: -f1 || true)"
    if [ -n "$jstart" ]; then
      k_log="$(sed -n "${jstart},$((jstart + c_log - 1))p" CHANGELOG.md | count_chars_stdin)"
    fi
  fi
fi
c_total=$((c_claude + c_imports + RULES_LINES + c_resume + c_map + c_log))
k_total=$((k_claude + k_imports + RULES_CHARS + k_resume + k_map + k_log))
c_detail="CLAUDE.md $c_claude, imports $c_imports, rules without paths $RULES_LINES, resume block $c_resume, root map $c_map, last three log entries $c_log"
thresholds_of cout-reprise 600 900
if   [ "$c_total" -gt "$THR_B" ]; then
  block "resume cost: $c_total lines loaded before the first question, blocker threshold $THR_B ($c_detail)" CLAUDE.md
elif [ "$c_total" -gt "$THR_A" ]; then
  warn "resume cost: $c_total lines loaded before the first question, warning threshold $THR_A ($c_detail)" CLAUDE.md
else
  ok "resume cost: $c_total lines ($c_detail)"
fi
# The same sum in characters: a hundred per budget line, so 60,000 and 90,000. A map of 191
# lines that weighs 126,000 characters passes the line budget without passing this one.
# Tokens (characters / 4, rounded) are only an order of magnitude, in the message only.
k_detail="CLAUDE.md $k_claude, imports $k_imports, rules without paths $RULES_CHARS, resume block $k_resume, root map $k_map, last three log entries $k_log"
k_tokens=$(((k_total + 2) / 4))
thresholds_of car-cout-reprise 60000 90000
if   [ "$k_total" -gt "$THR_B" ]; then
  block "resume cost: $k_total characters (about $k_tokens tokens) loaded before the first question, blocker threshold $THR_B ($k_detail)" CLAUDE.md
elif [ "$k_total" -gt "$THR_A" ]; then
  warn "resume cost: $k_total characters (about $k_tokens tokens) loaded before the first question, warning threshold $THR_A ($k_detail)" CLAUDE.md
fi

# Ratchet `ajourne:`. The file must no longer grow beyond its frozen value, and the entry
# must leave as soon as it goes back under its warning threshold.
if [ -n "$DEFERRED" ]; then
  while IFS= read -r e; do
    trim "$e"; e="${TRIM#./}"
    [ -n "$e" ] || continue
    ajf=""; ajn=""; ajd=""
    case "$e" in
      *=*@*)
        trim "${e%%=*}"; ajf="$TRIM"
        trim "${e#*=}"; rest="$TRIM"
        trim "${rest%%@*}"; ajn="$TRIM"
        trim "${rest#*@}"; ajd="$TRIM" ;;
    esac
    case "$ajn" in ''|*[!0-9]*) ajn="" ;; esac
    if [ -z "$ajf" ] || [ -z "$ajn" ] || [ -z "$ajd" ]; then
      warn "ajourne: the entry « $e » is unreadable, the form is file=lines@YYYY-MM-DD" "$(conv_find)"
      continue
    fi
    if [ ! -f "$ajf" ]; then
      warn "ajourne: $ajf does not exist, remove the entry $ajf=$ajn@$ajd" "$ajf"
      continue
    fi
    # A CLAUDE.md reduced to a redirect carries nothing: the deferral targets the rules, so
    # the target file, like the measure above.
    ajm="$ajf"; ajnote=""
    if [ "$ajf" = CLAUDE.md ] && [ -n "$CLAUDE_REDIRECT" ] && [ -f "$CLAUDE_REDIRECT" ]; then
      ajm="$CLAUDE_REDIRECT"; ajnote=" Measured file: $CLAUDE_REDIRECT, which carries the rules of CLAUDE.md."
    fi
    n="$(count_lines "$ajm")"
    defaults_of "$ajf"
    thresholds_of "$ajf" "$DA" "$DB"
    if [ "$n" -gt "$ajn" ]; then
      block "$ajf: $n lines, more than its deferral ($ajn lines since $ajd). A frozen overshoot no longer grows. Cut at least down to $ajn lines.$ajnote" "$ajf"
    elif [ "$DA" -gt 0 ] && [ "$n" -le "$THR_A" ]; then
      warn "$ajf: $n lines, back under its warning threshold ($THR_A). Remove the ajourne entry $ajf=$ajn@$ajd.$ajnote" "$ajf"
    else
      days_since "$ajd"; jr="$DAYS"
      info "$ajf: $n lines, deferred at $ajn since $ajd${jr:+ ($jr days)}. It must no longer grow.$ajnote" "$ajf"
    fi
  done <<EOT
$(printf '%s\n' "$DEFERRED" | tr ',' '\n')
EOT
fi

if [ "$BUDGET_ONLY" -eq 0 ]; then

# --- 11. structure and hygiene ------------------------------------------------
# What section 10 does not measure in lines: finished plans, drifting summaries, automatic
# memory, submodules, pitfalls, agents.
echo
echo "11. Structure and hygiene"
SEC=11

# Value of a key in a file's YAML header, without quotes. Empty if absent.
fm_value() { # <file> <key>
  awk -v k="$2" 'NR == 1 { if ($0 !~ /^---[ \t\r]*$/) exit; inside = 1; next }
       inside && /^---[ \t\r]*$/ { exit }
       inside && index($0, k ":") == 1 {
         v = substr($0, length(k) + 2)
         gsub(/"/, "", v); gsub(/\047/, "", v)
         sub(/^[ \t]+/, "", v); sub(/[ \t\r]+$/, "", v)
         print v; exit
       }' "$1" 2>/dev/null
  return 0
}

# Executed plans. The rule for a "finished" plan is that of ctx-rotation.sh --plans, it is
# called as a dry run instead of copied. A finished plan that keeps open boxes or goes
# over 300 lines has not been compressed.
if [ -n "$PLANS_DIR" ] && [ -d "$PLANS_DIR" ] && [ -f "$SCRIPTS_DIR/ctx-rotation.sh" ]; then
  if [ -n "$ROT_OUT" ]; then
    wait "$ROT_PID" 2>/dev/null || true
    ROT_PID=""
    plans_output="$(cat "$ROT_OUT")"
  else
    plans_output="$(bash "$SCRIPTS_DIR/ctx-rotation.sh" --plans --dry-run --root "$ROOT" 2>/dev/null || true)"
  fi
  nbp=0; bad_plans=0
  while IFS= read -r l; do
    case "$l" in "  - "*) ;; *) continue ;; esac
    p="${l#  - }"; p="${p%% *}"
    [ -f "$p" ] || continue
    nbp=$((nbp + 1))
    n="$(count_lines "$p")"
    o="$(grep -c '\[ \]' "$p" || true)"
    if [ "${o:-0}" -gt 0 ] || [ "$n" -gt 300 ]; then
      bad_plans=$((bad_plans + 1))
      warn "$p: executed plan that stays heavy ($n lines, ${o:-0} open [ ] box(es), cap 300 lines). To compress then archive: ctx-rotation.sh --plans" "$p"
    fi
  done <<EOT
$plans_output
EOT
  if [ "$bad_plans" -eq 0 ]; then
    ok "no executed plan to compress"
  fi
fi

# Recomputable summaries. The "Recently archived" section of docs/README.md summarizes the
# archive index, which is the source. A line of the summary absent from the source is false.
if [ -n "$DOCS_DIR" ] && [ -f "$DOCS_DIR/README.md" ] && [ -n "$ARCH_DIR" ] && [ -f "$ARCH_DIR/README.md" ]; then
  SUMMARY="$(awk '/^#+ / { inside = ($0 ~ /[Aa]rchiv/); next } inside' "$DOCS_DIR/README.md")"
  nres=0; wrong=0
  while IFS= read -r l; do
    d="$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' <<<"$l" | sed -n '1p' || true)"
    [ -n "$d" ] || continue
    toks="$(printf '%s' "$l" | grep -oE '`[^`]+`' | tr -d '`' || true)"
    [ -n "$toks" ] || continue
    nres=$((nres + 1))
    found=0
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      if [ -n "$(grep -F -- "$d" "$ARCH_DIR/README.md" | grep -F -- "$t" || true)" ]; then found=1; fi
    done <<EOT
$toks
EOT
    if [ "$found" -eq 0 ]; then
      wrong=$((wrong + 1))
      warn "$DOCS_DIR/README.md: the archived line of $d ($(head -1 <<<"$toks")) is not found in $ARCH_DIR/README.md. The summary is recomputed from the archive index" "$DOCS_DIR/README.md"
    fi
  done <<EOT
$SUMMARY
EOT
  # The most recent archive that is not a log rotation must appear in the summary.
  latest="$(awk -F'|' '/^\|---/ { t = 1; next }
      t && NF >= 6 {
        d = $2; o = $3; r = $6
        gsub(/^[ \t]+|[ \t]+$/, "", d); gsub(/^[ \t]+|[ \t]+$/, "", o); gsub(/^[ \t]+|[ \t]+$/, "", r)
        if (d !~ /^[0-9][0-9][0-9][0-9]-/) next
        if (o == r) next
        print d "|" o; exit
      }' "$ARCH_DIR/README.md")"
  if [ -n "$latest" ] && [ "$nres" -gt 0 ]; then
    rd="${latest%%|*}"; ro="${latest#*|}"
    ro="$(grep -oE '`[^`]+`' <<<"$ro" | sed -n '1p' | tr -d '`' || true)"
    if [ -n "$ro" ] && ! grep -qF -- "$ro" <<<"$SUMMARY" && ! grep -qF -- "$(basename "$ro")" <<<"$SUMMARY"; then
      info "$DOCS_DIR/README.md: the « recently archived » summary lacks the latest archive, of $rd ($ro). Recompute it from $ARCH_DIR/README.md" "$DOCS_DIR/README.md"
    fi
  fi
  if [ "$nres" -gt 0 ] && [ "$wrong" -eq 0 ]; then
    ok "the archive summary of $DOCS_DIR/README.md is found in $ARCH_DIR/README.md"
  fi
fi

# Automatic project memory. Claude Code stores the index under
# ~/.claude/projects/<project path, every non-alphanumeric character as a dash>/memory/MEMORY.md
# and only loads its first 200 lines. If absent, there is nothing to say.
auto_memory_index() { # -> path of this project's MEMORY.md, nothing if it does not exist
  local base c
  base="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/projects"
  for c in "$(printf '%s' "$ROOT" | sed 's/[^A-Za-z0-9]/-/g')" "$(printf '%s' "$ROOT" | sed 's|/|-|g')"; do
    if [ -f "$base/$c/memory/MEMORY.md" ]; then printf '%s\n' "$base/$c/memory/MEMORY.md"; return 0; fi
  done
  return 0
}
# Text in ASCII lowercase, everything else as single spaces: two sentences that only differ
# by punctuation or case become identical.
norm_txt() {
  LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed 's/[^a-z0-9]/ /g' | LC_ALL=C tr -s ' '
}
MEM="$(auto_memory_index)"
if [ -n "$MEM" ]; then
  nm="$(count_lines "$MEM")"
  thresholds_of memoire-auto 150 200
  if [ "$nm" -gt "$THR_A" ]; then
    warn "automatic memory index: $nm lines, warning threshold $THR_A ($MEM). Claude Code only loads the first 200 lines, the rest is invisible. Merge or drain the entries whose content has an owner in the repo" "$MEM"
  else
    ok "automatic memory index: $nm lines"
  fi
  # Entries that copy CLAUDE.md: a project rule lives in CLAUDE.md, memory keeps what has no
  # other owner. Equality after normalization, 50 characters at least.
  if [ -f CLAUDE.md ]; then
    BLOB="$( { cat CLAUDE.md; if [ -n "$CLAUDE_REDIRECT" ] && [ -f "$CLAUDE_REDIRECT" ]; then cat "$CLAUDE_REDIRECT"; fi; } | norm_txt | tr '\n' ' ' | tr -s ' ')"
    memdir="$(dirname "$MEM")"
    nrec=0
    for ef in $(grep -oE '\]\([^)#:]+\.md\)' "$MEM" | sed 's/^](//; s/)$//' | sort -u || true); do
      [ -f "$memdir/$ef" ] || continue
      copy=""
      # A single awk per entry: it skips the header, normalizes each line like norm_txt
      # (ASCII lowercase, everything else as a space, tight spaces, edges removed) and only
      # returns segments of at least 50 characters. In C, like norm_txt: a byte stays a
      # byte, and any byte outside a-z0-9 falls into the space.
      while IFS= read -r seg; do
        case "$BLOB" in *"$seg"*) copy="$seg"; break ;; esac
      done <<EOT
$(LC_ALL=C awk 'NR == 1 && /^---/ { fm = 1; next } fm && /^---/ { fm = 0; next }
     !fm { if (++n > 200) next
           s = tolower($0); gsub(/[^a-z0-9]/, " ", s); gsub(/  +/, " ", s)
           sub(/^ /, "", s); sub(/ $/, "", s)
           if (length(s) >= 50) print s }' "$memdir/$ef")
EOT
      if [ -n "$copy" ]; then
        nrec=$((nrec + 1))
        warn "automatic memory: the entry $ef copies CLAUDE.md (« $(printf '%s' "$copy" | cut -c1-60) »). A project rule lives in CLAUDE.md, not duplicated in memory" "$MEM"
      fi
    done
    if [ "$nrec" -eq 0 ]; then ok "no automatic memory entry copies CLAUDE.md"; fi
  fi
fi

# Parent and submodules. A child that has its own kit is not described as kit-less by the
# parent's map, and the parent's pointer does not lag behind the child's state.
# Does the path of a submodule appear in the line as a word? A submodule `ops` or `lib`
# must not be found in "workshops" or "lib.rs" nor in "docs/ops". Before: start of line, or a
# character that is neither a letter, a digit, nor _ . / -. After: end of line, or a
# character that is neither a letter, a digit, nor _ -, a final dot remaining allowed.
# Backticks, spaces, punctuation and the / of a folder therefore bound the path.
word_in_line() { # <path> <line>: code 0 if the path appears there as a word
  local p="$1" rest="$2" pre="" before after cb ca c2
  while :; do
    case "$rest" in *"$p"*) ;; *) return 1 ;; esac
    before="${rest%%"$p"*}"; after="${rest#*"$p"}"
    pre="$pre$before"
    cb="${pre: -1}"; ca="${after:0:1}"; c2="${after:1:1}"
    case "$cb" in
      ''|[![:alnum:]_./-])
        case "$ca" in
          ''|[![:alnum:]_.-]) return 0 ;;
          .) case "$c2" in ''|[![:alnum:]_]) return 0 ;; esac ;;
        esac ;;
    esac
    pre="$pre$p"; rest="$after"
  done
}

RE_NO_KIT="(sans|pas de|aucun|aucune|n'a pas|ne porte pas|ne possede pas|ni )[^|.]{0,40}(kit|pilier|pillar|CODEMAP|TODOS|CHANGELOG)|no (own )?kit|without (its|a) own|(has|have) no [^|.]{0,40}(kit|pillar)|(lacks|missing) [^|.]{0,40}(kit|pillar)"
while IFS= read -r p; do
  [ -n "$p" ] || continue
  [ -e "$p/.git" ] || continue
  if [ -f "$p/CODEMAP.md" ] && [ -f "$p/TODOS.md" ] && [ -f "$p/CHANGELOG.md" ]; then
    against=""
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      txt="${l#*:}"; txt="${txt#*:}"
      word_in_line "$p" "$txt" || continue
      if grep -qiE "$RE_NO_KIT" <<<"$txt"; then against="$l"; break; fi
    done <<EOT2
$(grep -nF -- "$p" CODEMAP.md CLAUDE.md 2>/dev/null || true)
EOT2
    if [ -n "$against" ]; then
      warn "$p carries its own kit (CODEMAP, TODOS, CHANGELOG), but ${against%%:*} line $(printf '%s' "$against" | cut -d: -f2) says otherwise. Fix the parent's map" "${against%%:*}"
    fi
  fi
  sha="$(git ls-tree HEAD -- "$p" 2>/dev/null | awk '$2 == "commit" && !seen { print $3; seen = 1 }')"
  if [ -n "$sha" ] && git -C "$p" cat-file -e "$sha^{commit}" 2>/dev/null; then
    dptr="$(git -C "$p" show -s --format=%ci "$sha" 2>/dev/null | cut -c1-10)"
    dstat="$(git -C "$p" log -1 --format=%ci -- TODOS.md 2>/dev/null | cut -c1-10)"
    if [ -n "$dptr" ] && [ -n "$dstat" ] && [[ "$dstat" > "$dptr" ]]; then
      info "$p: the parent's pointer is dated $dptr, the child's last state change (TODOS.md) $dstat. Advance the pointer: git add $p" "$p"
    fi
  fi
done <<EOT
$SUBMODULES
EOT

# Marked pitfalls. A pitfall has an owner: the module page, its zone map, the root map when
# there is no zone, or docs/pitfalls/ for those without a module. A pitfall left in TODOS.md
# will be lost with the resume block. docs/pieges/ (French name) is read like docs/pitfalls/.
P_PAGE=0; P_ZONE=0; P_ROOT=0; P_PITFALLS=0; P_CLAUDE=0; P_TODOS=0; P_OTHER=0; P_OTHERS=""
MARKED="$(find . "${PRUNE[@]}" -o -name '*.md' -exec grep -cHF '🪤' {} + 2>/dev/null | grep -v ':0$' || true)"
while IFS= read -r l; do
  [ -n "$l" ] || continue
  f="${l%:*}"; f="${f#./}"; c="${l##*:}"
  case "$f" in
    CHANGELOG.md) ;;
    "$PLANS_DIR"/*) ;;
    TODOS.md) P_TODOS=$((P_TODOS + c)) ;;
    CLAUDE.md) P_CLAUDE=$((P_CLAUDE + c)) ;;
    CODEMAP.md) P_ROOT=$((P_ROOT + c)) ;;
    */CODEMAP.md) P_ZONE=$((P_ZONE + c)) ;;
    "$DOCS_DIR"/pitfalls/*|"$DOCS_DIR"/pieges/*) P_PITFALLS=$((P_PITFALLS + c)) ;;
    "$DOCS_DIR"/modules/*|"$DOCS_DIR"/features/*) P_PAGE=$((P_PAGE + c)) ;;
    *) P_OTHER=$((P_OTHER + c)); P_OTHERS="${P_OTHERS:+$P_OTHERS, }$f" ;;
  esac
done <<EOT
$MARKED
EOT
P_TOTAL=$((P_PAGE + P_ZONE + P_ROOT + P_PITFALLS + P_CLAUDE + P_TODOS + P_OTHER))
if [ "$P_TOTAL" -gt 0 ]; then
  info "$P_TOTAL pitfall(s) marked 🪤: $P_PAGE in a module page, $P_ZONE in a zone map, $P_ROOT in the root map, $P_PITFALLS in $DOCS_DIR/pitfalls/, $P_CLAUDE in CLAUDE.md, $P_TODOS in TODOS.md, $P_OTHER elsewhere"
  if [ "$P_TODOS" -gt 0 ]; then
    warn "TODOS.md carries $P_TODOS pitfall(s) 🪤 without an owner. A pitfall goes in the module page, its zone map, or $DOCS_DIR/pitfalls/ if it has no module" TODOS.md
  fi
  if [ "$P_OTHER" -gt 0 ]; then
    info "pitfall(s) 🪤 outside a recognized owner: $P_OTHERS"
  fi
fi
if [ -n "$DOCS_DIR" ] && [ -d "$DOCS_DIR/pitfalls" ]; then
  info "$DOCS_DIR/pitfalls/: owner of the pitfalls that have no module ($P_PITFALLS marked pitfall(s))"
fi
if [ -n "$DOCS_DIR" ] && [ -d "$DOCS_DIR/pieges" ]; then
  info "$DOCS_DIR/pieges/: owner of the pitfalls that have no module ($P_PITFALLS marked pitfall(s))"
fi

# Project agents. A `model:` with a frozen identifier does not follow the latest version of
# its family, an agent without `model:` inherits the main session's model, often Opus.
if [ -d .claude/agents ]; then
  nag=0; bad=0
  for a in $(find .claude/agents -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort); do
    if [ -n "$EXCEPTIONS" ] && exception_of agent "$a"; then continue; fi
    nag=$((nag + 1))
    m="$(fm_value "$a" model)"
    if [ -z "$m" ]; then
      bad=$((bad + 1))
      warn "$a: no model:, the agent inherits the main session's model, often Opus. Set an alias: haiku, sonnet or opus" "$a"
    elif grep -qiE 'claude-.*[0-9]|anthropic\.claude' <<<"$m"; then
      bad=$((bad + 1))
      case "$m" in
        *[Hh]aiku*) al=haiku ;;
        *[Ss]onnet*) al=sonnet ;;
        *[Oo]pus*) al=opus ;;
        *) al="haiku, sonnet or opus" ;;
      esac
      warn "$a: model: $m is a frozen identifier, it does not follow the latest version of its family. Set the alias: $al" "$a"
    fi
  done
  if [ "$nag" -gt 0 ] && [ "$bad" -eq 0 ]; then ok "$nag project agent(s) with a model: alias"; fi
fi

fi # end of section 11, skipped by --budget

# --- summary ------------------------------------------------------------------
echo
echo "=============================================="
if [ "$WARNINGS" -eq 0 ]; then
  echo " No warnings. The docs and the repo agree, and everything fits its budget."
else
  echo " $WARNINGS warning(s), of which $BLOCKERS blocker(s). Each one ends with a fix,"
  echo " a move to archives/, or a rotation. A blocker is not deferred."
fi
echo "=============================================="

if [ "$JSON" -eq 1 ]; then
  if [ -z "$JSON_RAW" ]; then
    printf '[]\n' >&3
  else
    { printf '[\n'; json_output "$JSON_RAW"; printf ']\n'; } >&3
  fi
fi

if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0
