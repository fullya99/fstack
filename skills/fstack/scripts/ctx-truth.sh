#!/usr/bin/env bash
#
# ctx-truth.sh: checks, without a model, the claims in the docs that can be verified
# against the repo. It reports, it fixes nothing.
#
# Usage:
#   bash ctx-truth.sh [--root <path>] [--strict] [--json] [--info]
#
# --strict: exit with code 1 if a false claim remains (useful in CI).
# --json  : a list of objects {"section":"truth","level","file","message"}, the line
#           number at the head of the message.
# --info  : also lists the claims to review (level info), cited mid-sentence or as a
#           bare name, which do not count for --strict. --json keeps them.
#
# Files read: CLAUDE.md, AGENTS.md, the pillars, docs/**/*.md. Never archives/.
# Outside code blocks and HTML comments, except directory trees, of which only the
# counts in comments are reread.
#
# What is checked:
#   paths between backticks, cited scripts, --x options of a repo script,
#   npm run, bun run, pnpm, yarn, make commands against package.json and Makefile,
#   "N files" counts placed before or after a directory, recounted.
#
# What is ignored: a line that says "does not exist yet", "removed", "to create",
# "example", URLs, patterns with <...>, * or {...}, paths ignored by git, paths under
# an uninitialized submodule, and what `exceptions: verite=<pattern>` (or
# `lien=<pattern>`) covers in the contexte:convention block.
#
# Output: file:line  claim  reason, then a total.
set -euf

# Shared library, loaded before the cd to the root.
. "$(dirname "$0")/ctx-common.sh"

ROOT=""
STRICT=0
JSON=0
INFO=0

# Level of each family. A family too noisy in the field moves to `info` here,
# without touching the rest of the script. Only `warning` counts for --strict.
LEVEL_path=warning
LEVEL_script=warning
LEVEL_option=warning
LEVEL_command=warning
LEVEL_count=warning

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      # An option with a value but no value: clear message and code 2, not a silent exit.
      if [ $# -lt 2 ]; then echo "--root needs a value" >&2; exit 2; fi
      ROOT="$2"; shift 2 ;;
    --strict)  STRICT=1; shift ;;
    --json)    JSON=1; shift ;;
    --info)    INFO=1; shift ;;
    -h|--help) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
[ -d "$ROOT" ] || { echo "Root not found: $ROOT" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"

# The block is read once: otherwise each conv_read or conv_exception finds the page
# and rereads the block, about ten processes per warning.
conv_load

scripts_version || exit 2

SEP="$(printf '\037')"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ctx-truth.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
FLAGS="$TMP/flags"
FLAGS_IGN="$TMP/flags-ign"
LIST="$TMP/list"
: > "$FLAGS"
: > "$FLAGS_IGN"

IN_GIT=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then IN_GIT=1; fi

# All files and directories of the repo, minus exclusions and archives, for lookups by
# suffix or by bare name.
# The pruning list is computed once (one walk for the CACHEDIR.TAG files), later calls,
# inside $(...), reread it from memory.
exclusions_load
# shellcheck disable=SC2046
find . \( $(exclusions_prune) -print \) -o \( -type f -o -type d \) -print 2>/dev/null | sed 's|^\./||' > "$LIST" || true

SUBMODULES="$(submodules)"
DIR_ARCHIVES="$(conv_read archives)"
[ -n "$DIR_ARCHIVES" ] || DIR_ARCHIVES="archives/"
DIR_ARCHIVES="${DIR_ARCHIVES%/}"
DIR_DOCS="$(conv_read docs)"
[ -n "$DIR_DOCS" ] || DIR_DOCS="docs/"
DIR_DOCS="${DIR_DOCS%/}"
PILLARS="$(conv_read piliers)"
[ -n "$PILLARS" ] || PILLARS="CODEMAP.md, TODOS.md, CHANGELOG.md"

# --- sorties -------------------------------------------------------------------

# The block exceptions are only read here, when reporting: rereading them for every token
# would make the script slow, and most tokens yield nothing. They are split only once, at
# the first warning: the `verite=` and `lien=` patterns go into EXC_PATTERN, and
# conv_exception no longer has to spawn ten processes per key and per warning.
EXC_LOADED=0
EXC_NB=0
exceptions_load() {
  local e t pattern
  EXC_LOADED=1
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    t="$(printf '%s' "${e%%=*}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    pattern="$(printf '%s' "${e#*=}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    case "$t" in verite|lien) : ;; *) continue ;; esac
    [ -n "$pattern" ] || continue
    EXC_PATTERN[$EXC_NB]="$pattern"
    EXC_NB=$((EXC_NB + 1))
  done <<END_LIST
$(conv_read exceptions | tr ',' '\n')
END_LIST
  return 0
}

exception_covered() { # <key>: code 0 if a verite= or lien= pattern covers it
  local path="${1#./}" i=0 pattern
  [ "$EXC_LOADED" -eq 1 ] || exceptions_load
  while [ "$i" -lt "$EXC_NB" ]; do
    pattern="${EXC_PATTERN[$i]}"
    # in a case, * also covers /, so ** and * are the same here
    # shellcheck disable=SC2254
    case "$path" in $pattern) return 0 ;; esac
    i=$((i + 1))
  done
  return 1
}

flag() { # <family> <file> <line> <claim> <reason> <exception key>...
  local fam="$1" fic="$2" lig="$3" claim="$4" reason="$5" key ign="$IGN_KEY"
  IGN_KEY=""
  shift 5
  for key in "$@"; do
    if exception_covered "$key"; then return 0; fi
  done
  # A warning on a path that git may ignore waits for git's verdict, given for all
  # paths at once (ignore_batch): one git process per path is expensive.
  if [ -n "$ign" ]; then
    printf '%s%s%s%s%s%s%s%s%s%s%s\n' "$ign" "$SEP" "$fam" "$SEP" "$fic" "$SEP" "$lig" "$SEP" "$claim" "$SEP" "$reason" >> "$FLAGS_IGN"
    return 0
  fi
  printf '%s%s%s%s%s%s%s%s%s\n' "$fam" "$SEP" "$fic" "$SEP" "$lig" "$SEP" "$claim" "$SEP" "$reason" >> "$FLAGS"
  return 0
}

# Path whose verdict check_path leaves to git, which flag reads once.
IGN_KEY=""

# --- resolution helpers ----------------------------------------------------

known_ext() { # <name>: code 0 if the extension is one we track
  case "$1" in
    *.sh|*.bash|*.zsh|*.py|*.js|*.mjs|*.cjs|*.ts|*.tsx|*.jsx|*.md|*.mdx|*.json|*.yaml|*.yml|*.toml) return 0 ;;
    *.sql|*.css|*.scss|*.html|*.txt|*.cfg|*.ini|*.csv|*.lock|*.xml|*.ps1|*.rb|*.go|*.rs|*.svg) return 0 ;;
    *.png|*.jpg|*.jpeg|*.gif|*.pdf|*.zip|*.tgz|*.pl) return 0 ;;
  esac
  return 1
}

script_ext() { # <name>: code 0 if it is a script an interpreter can run
  case "$1" in
    *.sh|*.bash|*.zsh|*.py|*.js|*.mjs|*.cjs|*.ts|*.rb|*.pl) return 0 ;;
  esac
  return 1
}

# Name of a directory that exclusions skip or that a repo does not version.
excluded_dir() { # <path>
  case "/$1/" in
    */node_modules/*|*/dist/*|*/build/*|*/target/*|*/vendor/*|*/.venv/*|*/venv/*) return 0 ;;
    */.next/*|*/.next-*|*/.cache/*|*/__pycache__/*|*/.git/*|*/coverage/*|*/.tmp/*) return 0 ;;
  esac
  return 1
}

git_ignored() { # <path>
  [ "$IN_GIT" -eq 1 ] || return 1
  # `.venv/` only ignores a missing path when given with its trailing slash
  git check-ignore -q -- "$1" 2>/dev/null && return 0
  git check-ignore -q -- "$1/" 2>/dev/null
}

submodule_empty() { # <path>: code 0 if it is under a missing or empty submodule
  local sm
  [ -n "$SUBMODULES" ] || return 1
  while IFS= read -r sm; do
    [ -n "$sm" ] || continue
    case "$1" in
      "$sm"|"$sm"/*)
        if [ ! -d "$sm" ] || [ -z "$(ls -A "$sm" 2>/dev/null)" ]; then return 0; fi
        ;;
    esac
  done <<END_LIST
$SUBMODULES
END_LIST
  return 1
}

# Index of the file list, to look up a suffix without launching awk for each token
# (several thousand lookups on a dense repo). A single awk sorts the list into buckets by
# the first letter of the base name, lowercase: c_<k> keeps paths as they are (preceded by
# a `/`), l_<k> the same ones through awk's tolower. A bucket is read into a variable the
# first time it is asked for, and a lookup only scans that one.
NL="$(printf '\nx')"; NL="${NL%x}"
IDX="$TMP/idx"
mkdir "$IDX"
awk -v dir="$IDX" '
  { c = "/" $0
    b = c; sub(/^.*\//, "", b)
    k = tolower(substr(b, 1, 1))
    if (k !~ /^[a-z0-9]$/) k = "_"
    print c > (dir "/c_" k)
    print tolower(c) > (dir "/l_" k)
  }' "$LIST"

# ASCII lowercase of <text> in MIN, without a process (the old tr 'A-Z' 'a-z').
MIN=""
lower() { # <text>
  MIN="$1"
  # nothing to change without an ASCII capital, and [:lower:] contains none
  case "$MIN" in
    *[![:lower:][:digit:]/._-]*) : ;;
    *) return 0 ;;
  esac
  MIN="${MIN//A/a}"; MIN="${MIN//B/b}"; MIN="${MIN//C/c}"; MIN="${MIN//D/d}"; MIN="${MIN//E/e}"
  MIN="${MIN//F/f}"; MIN="${MIN//G/g}"; MIN="${MIN//H/h}"; MIN="${MIN//I/i}"; MIN="${MIN//J/j}"
  MIN="${MIN//K/k}"; MIN="${MIN//L/l}"; MIN="${MIN//M/m}"; MIN="${MIN//N/n}"; MIN="${MIN//O/o}"
  MIN="${MIN//P/p}"; MIN="${MIN//Q/q}"; MIN="${MIN//R/r}"; MIN="${MIN//S/s}"; MIN="${MIN//T/t}"
  MIN="${MIN//U/u}"; MIN="${MIN//V/v}"; MIN="${MIN//W/w}"; MIN="${MIN//X/x}"; MIN="${MIN//Y/y}"
  MIN="${MIN//Z/z}"
}

# Sets in BUCKET the <l|c> bucket of the first letter of <base name>, a newline before
# and one after each line. Letters outside a-z and 0-9 share the _ bucket.
BUCKET=""
bucket_load() { # <l|c> <name de base>
  local k v content=""
  case "${2:0:1}" in
    a|A) k=a ;; b|B) k=b ;; c|C) k=c ;; d|D) k=d ;; e|E) k=e ;; f|F) k=f ;; g|G) k=g ;;
    h|H) k=h ;; i|I) k=i ;; j|J) k=j ;; k|K) k=k ;; l|L) k=l ;; m|M) k=m ;; n|N) k=n ;;
    o|O) k=o ;; p|P) k=p ;; q|Q) k=q ;; r|R) k=r ;; s|S) k=s ;; t|T) k=t ;; u|U) k=u ;;
    v|V) k=v ;; w|W) k=w ;; x|X) k=x ;; y|Y) k=y ;; z|Z) k=z ;;
    0|1|2|3|4|5|6|7|8|9) k="${2:0:1}" ;;
    *) k=_ ;;
  esac
  v="BKT_${1}_$k"
  eval "BUCKET=\${$v-}"
  if [ -z "$BUCKET" ]; then
    if [ -f "$IDX/${1}_$k" ]; then IFS= read -r -d '' content < "$IDX/${1}_$k" || true; fi
    BUCKET="$NL$content"
    eval "$v=\$BUCKET"
  fi
}

# Path of the first repo file that carries exactly this name, in FOUND, or nothing.
FOUND=""
find_elsewhere() { # <name>
  local n="/$1" l IFS="$NL"
  FOUND=""
  bucket_load c "$1"
  case "$BUCKET" in
    *"$n$NL"*) ;;
    *) return 0 ;;
  esac
  # the bucket keeps the list order: the first line that ends this way. set -f is
  # on, and IFS (local) splits the bucket into lines.
  # shellcheck disable=SC2086
  set -- $BUCKET
  for l in "$@"; do
    case "$l" in
      *"$n") FOUND="${l#/}"; return 0 ;;
    esac
  done
  return 0
}

first_known() { # <doc dir> <path or segment>
  local cur="$1" seg="$2"
  [ -e "$seg" ] && return 0
  while [ -n "$cur" ] && [ "$cur" != "." ] && [ "$cur" != "/" ]; do
    [ -e "$cur/$seg" ] && return 0
    case "$cur" in */*) cur="${cur%/*}" ;; *) cur="." ;; esac
  done
  case "$seg" in
    scripts|src|docs|tests|lib|bin|app|apps|packages|.claude|.github) return 0 ;;
  esac
  return 1
}

# Does a path end with this suffix in the repo file list?
exists_by_suffix() { # <suffixe>
  local n
  lower "/$1"
  n="$MIN"
  bucket_load l "${n##*/}"
  case "$BUCKET" in
    *"$n$NL"*) return 0 ;;
  esac
  return 1
}

# Resolves <path> from the document directory, then its parents, then the root.
# Returns 0 if the path exists, and sets RES.
RES=""
resolve() { # <doc dir> <path>
  local d="$1" p="${2%/}" cur
  RES=""
  [ -n "$p" ] || return 1
  if [ -e "$p" ]; then RES="$p"; return 0; fi
  cur="$d"
  while [ -n "$cur" ] && [ "$cur" != "." ] && [ "$cur" != "/" ]; do
    if [ -e "$cur/$p" ]; then RES="$cur/$p"; return 0; fi
    case "$cur" in */*) cur="${cur%/*}" ;; *) cur="." ;; esac
  done
  case "$p" in
    ../*) return 1 ;;
    */*)  if exists_by_suffix "$p"; then RES="$p"; return 0; fi ;;
    *)    if exists_by_suffix "$p"; then find_elsewhere "$p"; RES="$FOUND"; return 0; fi ;;
  esac
  return 1
}

# --- checking a path -------------------------------------------------------

# Cleans a backtick token and sets the candidate path in NORM, or nothing if it is not
# one. No subshell: this function runs for every token of the repo.
NORM=""
normalize_path() { # <jeton>
  local t="$1"
  NORM=""
  t="${t#\"}"; t="${t%\"}"; t="${t#\'}"; t="${t%\'}"
  t="${t#./}"
  case "$t" in
    ''|-*|/*|'~'*|http:*|https:*|mailto:*|git@*|'#'*) return 0 ;;
    .env*|*/.env*) return 0 ;;
    *YYYY*|*AAAA*|*MM-DD*|*MM-JJ*|*JJ-*|*XXXX*|*NNNN*|*xxxx*) return 0 ;;
    *'<'*|*'>'*|*'*'*|*'{'*|*'}'*|*'$'*|*'...'*|*'…'*|*'|'*|*'='*|*'@'*|*'('*|*')'*|*'['*|*']'*|*'\'*) return 0 ;;
    *' '*|*'	'*) return 0 ;;
  esac
  # line number, anchor or symbol after the path: src/a.py:42, src/a.py#L3
  t="${t%%#*}"
  case "$t" in
    *:*) t="${t%%:*}" ;;
  esac
  t="${t%[.,;]}"
  [ -n "$t" ] || return 0
  [ "${#t}" -le 200 ] || return 0
  # a domain is not a repo path
  case "$t" in
    *.com/*|*.fr/*|*.io/*|*.org/*|*.net/*|*.dev/*|*.app/*|*.ai/*|*.co/*) return 0 ;;
  esac
  NORM="$t"
  return 0
}

# Is a token one we know how to check, and in which shape?
# Sets SHAPE: "file" (name with a tracked extension), "dir" (trailing slash), "path"
# (no extension, checked if its first segment exists), or nothing.
path_shape() { # <path normalise>
  local t="$1" base
  SHAPE=""
  base="${t##*/}"
  case "$t" in
    */)
      SHAPE=dir; return 0 ;;
  esac
  # `.py`, `.md`: a bare extension, not a file
  case "$base" in
    .*.*) : ;;
    .*) if known_ext "x$base"; then return 0; fi ;;
  esac
  if known_ext "$base"; then
    case "$base" in
      .env*|*.example) return 0 ;;
    esac
    case "$t" in
      */*) SHAPE=file ;;
      *)
        # Next.js, Node.js: a technology name, not a file
        case "$base" in
          [A-Z]*.js) return 0 ;;
        esac
        SHAPE=nu
        ;;
    esac
    return 0
  fi
  case "$t" in
    */*) SHAPE=path ;;
  esac
  return 0
}

# Checks a cited path. Family: script if the extension is a script one.
# Sets SCRIPT_RESOLVED when the cited path exists and is a script.
SCRIPT_RESOLVED=""
POS_SPAN="m"
check_path() { # <doc> <line> <jeton raw>
  check_path_body "$@"
  IGN_KEY=""
  return 0
}

check_path_body() { # <doc> <line> <jeton raw>
  local doc="$1" line="$2" raw="$3" t shape docdir parent base family tilde="" moved=""
  SCRIPT_RESOLVED=""
  normalize_path "$raw"
  t="$NORM"
  [ -n "$t" ] || return 0
  path_shape "$t"
  shape="$SHAPE"
  [ -n "$shape" ] || return 0
  case "$doc" in */*) docdir="${doc%/*}" ;; *) docdir="." ;; esac
  if excluded_dir "${t%/}"; then return 0; fi
  if submodule_empty "${t%/}"; then return 0; fi

  if resolve "$docdir" "$t"; then
    if [ -f "$RES" ] && script_ext "${RES##*/}"; then SCRIPT_RESOLVED="$RES"; fi
    return 0
  fi
  # Ignored by git: the verdict comes later, in a batch, see flag. Outside a git repo,
  # nothing is ignored.
  if [ "$IN_GIT" -eq 1 ]; then IGN_KEY="${t%/}"; fi

  # A path whose parent directory does not exist and whose name is found nowhere almost
  # always points at a third-party library, another repo or a runtime folder
  # (httpx/_models.py, worker/data/x), not a hole in the repo. If the name exists
  # elsewhere, the file was moved: we report it.
  case "$shape" in
    nu) : ;;
    *)
      parent="${t%/}"
      case "$parent" in */*) parent="${parent%/*}" ;; *) parent="." ;; esac
      if [ "$parent" != "." ] && ! first_known "$docdir" "$parent" && ! exists_by_suffix "${t%/}"; then
        base="${t%/}"; base="${base##*/}"
        exists_by_suffix "$base" || return 0
      fi
      if [ "$parent" = "." ]; then
        # a lone directory: we only follow it under a conventional directory name
        first_known "$docdir" "${t%/}" || return 0
      fi
      ;;
  esac
  case "$shape" in
    path)
      # no extension and no trailing slash: "and/or", "client/server"
      [ -d "${t%%/*}" ] || return 0
      ;;
    nu)
      # a bare name is only followed for a shell script or a document: a data file,
      # a config file or a source cited by its short name comes from elsewhere
      case "${t##*/}" in
        *.sh|*.bash|*.md) : ;;
        *) return 0 ;;
      esac
      ;;
  esac
  # A span cited mid-sentence, or a bare name, gets reread: we report it as info,
  # unless the file exists elsewhere under the same name, proof that it was moved.
  if [ "$POS_SPAN" != "s" ] || [ "$shape" = nu ]; then tilde="~"; fi
  moved=""
  if [ "$shape" = file ]; then
    base="${t##*/}"
    case "$base" in
      README.md|readme.md|index.*|__init__.py|main.*|Makefile|LICENSE*) : ;;
      # a config name is carried by too many tools to prove a move
      *.json|*.yaml|*.yml|*.toml|*.ini|*.cfg) : ;;
      *) find_elsewhere "$base"; moved="$FOUND" ;;
    esac
    if [ -n "$moved" ]; then
      family=path
      if script_ext "$base"; then family=script; fi
      case "$moved" in
        */*) moved="in $moved" ;;
        *)   moved="at the root" ;;
      esac
      flag "$family" "$doc" "$line" "\`$raw\`" "missing, but $base exists $moved" "$t"
      return 0
    fi
  fi
  family=path
  if script_ext "${t##*/}"; then family=script; fi
  if [ "$family" = script ]; then
    case "$shape" in
      nu) flag "script$tilde" "$doc" "$line" "\`$raw\`" "no script of this name in the repo" "$t" ;;
      *)  flag "script$tilde" "$doc" "$line" "\`$raw\`" "this script does not exist" "$t" ;;
    esac
  else
    case "$shape" in
      dir) flag "path$tilde" "$doc" "$line" "\`$raw\`" "this directory does not exist" "$t" "${t%/}" ;;
      nu)      flag "path$tilde" "$doc" "$line" "\`$raw\`" "no file of this name in the repo" "$t" ;;
      *)       flag "path$tilde" "$doc" "$line" "\`$raw\`" "this path does not exist" "$t" ;;
    esac
  fi
  return 0
}

# --- options of a script ---------------------------------------------------

# Equivalent of `grep -Fq -- <text> <file>`, without one grep per question: a cited script
# is read once into memory (OPT_TEXT) and later questions launch nothing. A file that is
# not a script, unreadable, too big or that carries a null byte stays with grep: we never
# load a neighbouring data file into memory.
OPT_NB=0
script_contains() { # <file> <text>
  local f="$1" t="$2" i=0 c=""
  [ -n "$t" ] || { grep -Fq -- "$t" "$f" 2>/dev/null; return $?; }
  while [ "$i" -lt "$OPT_NB" ]; do
    [ "${OPT_FILE[$i]}" = "$f" ] && break
    i=$((i + 1))
  done
  if [ "$i" -eq "$OPT_NB" ]; then
    OPT_FILE[$i]="$f"; OPT_TEXT[$i]=""; OPT_MODE[$i]="grep"
    OPT_NB=$((OPT_NB + 1))
    if script_ext "${f##*/}" && [ -f "$f" ] && [ -r "$f" ]; then
      # read returns 0 if it hits a null byte: the text is then truncated, we keep grep
      if ! IFS= read -r -d '' c < "$f" && [ "${#c}" -le 60000 ]; then
        OPT_TEXT[$i]="$c"; OPT_MODE[$i]=memory
      fi
    fi
  fi
  if [ "${OPT_MODE[$i]}" = memory ]; then
    case "${OPT_TEXT[$i]}" in
      *"$t"*) return 0 ;;
    esac
    return 1
  fi
  grep -Fq -- "$t" "$f" 2>/dev/null
  return $?
}

# Does the option appear in the script, or in a neighbouring file it sources?
option_present() { # <script> <option>
  local s="$1" o="${2%%=*}" dir f name
  if script_contains "$s" "$o"; then return 0; fi
  case "$s" in */*) dir="${s%/*}" ;; *) dir="." ;; esac
  # set -f is on: no glob, find makes the list
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$f" != "$s" ] || continue
    name="${f##*/}"
    if script_contains "$s" "$name" && script_contains "$f" "$o"; then return 0; fi
  done <<END_LIST
$(find "$dir" -maxdepth 1 -type f 2>/dev/null)
END_LIST
  return 1
}

check_option() { # <doc> <line> <script> <option> <explicit>
  local doc="$1" line="$2" script="$3" opt="$4" explicit="${5:-0}" f dscdir tilde=""
  if ! option_present "$script" "$opt"; then
    if [ "$explicit" -eq 0 ]; then
      case "$script" in */*) dscdir="${script%/*}" ;; *) dscdir="." ;; esac
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        if grep -Fq -- "${opt%%=*}" "$f" 2>/dev/null; then return 0; fi
      done <<END_LIST
$(find "$dscdir" -maxdepth 1 -type f 2>/dev/null)
END_LIST
    fi
    if [ "$explicit" -eq 0 ] && [ "$POS_SPAN" != "s" ]; then tilde="~"; fi
    flag "option$tilde" "$doc" "$line" "\`${opt%%=*}\`" "the option does not appear in $script" "$opt" "$script"
  fi
  return 0
}

# --- commandes de manifeste ----------------------------------------------------

package_json_has() { # <script>
  local f found=1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if grep -Eq "\"$1\"[[:space:]]*:" "$f" 2>/dev/null; then found=0; break; fi
  done <<END_LIST
$PACKAGES
END_LIST
  return "$found"
}

make_target_has() { # <target>
  local f found=1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if grep -Eq "^$1[[:space:]]*:([^=]|\$)" "$f" 2>/dev/null; then found=0; break; fi
  done <<END_LIST
$MAKEFILES
END_LIST
  return "$found"
}

check_command() { # <doc> <line> <tool> <target> <text>
  local doc="$1" line="$2" tool="$3" target="$4" text="$5"
  case "$target" in ''|-*|*[!A-Za-z0-9_:.-]*) return 0 ;; esac
  case "$target" in *.*) return 0 ;; esac
  case "$tool" in
    make)
      if [ -z "$MAKEFILES" ]; then
        flag command "$doc" "$line" "\`$text\`" "no Makefile in the repo" "$text"
      elif ! make_target_has "$target"; then
        flag command "$doc" "$line" "\`$text\`" "no target \"$target\" in the Makefile" "$text"
      fi
      ;;
    *)
      if [ -z "$PACKAGES" ]; then
        flag command "$doc" "$line" "\`$text\`" "no package.json in the repo" "$text"
      elif ! package_json_has "$target"; then
        flag command "$doc" "$line" "\`$text\`" "no script \"$target\" in package.json" "$text"
      fi
      ;;
  esac
  return 0
}

# Spots the commands of a span and checks them. Returns 0 if the span carried one.
examine_command() { # <doc> <line> <span>
  local doc="$1" line="$2" span="$3" tool m1 m2 target
  case "$span" in
    npm\ *|bun\ *|pnpm\ *|yarn\ *|make\ *) : ;;
    *) return 1 ;;
  esac
  # shellcheck disable=SC2086
  set -- $span
  tool="$1"; m1="${2:-}"; m2="${3:-}"
  case "$tool" in
    make)
      case "$m1" in -*) return 0 ;; esac
      check_command "$doc" "$line" make "$m1" "make $m1"
      ;;
    npm)
      if [ "$m1" = run ] || [ "$m1" = run-script ]; then
        check_command "$doc" "$line" npm "$m2" "npm run $m2"
      fi
      ;;
    bun|pnpm|yarn)
      if [ "$m1" = run ]; then
        target="$m2"
        # bun run src/x.ts, pnpm run --filter ...: a file or an option, not a script
        case "$target" in */*|-*) return 0 ;; esac
        check_command "$doc" "$line" "$tool" "$target" "$tool run $target"
      else
        case "$m1" in
          ''|install|i|add|remove|rm|update|up|upgrade|test|t|start|publish|exec|dlx|x|create|init|audit|outdated|list|ls|why|link|unlink|prune|store|fetch|import|rebuild|patch|env|setup|deploy|pack|pm|repl|build|info|config|cache|help|workspace|workspaces|global|set|get|login|logout|whoami|version|view|search|-*) return 0 ;;
        esac
        check_command "$doc" "$line" "$tool" "$m1" "$tool $m1"
      fi
      ;;
  esac
  return 0
}

# --- one line of prose -----------------------------------------------------

# The spans of a line arrive one by one. We keep them to tie a lone option to the
# script that another span of the same line cites.
CURRENT_LINE=""
CURRENT_DOC=""
LINE_SPANS=""

flush_line() {
  local entry span opt script_unique nb sl s line="$CURRENT_LINE" doc="$CURRENT_DOC"
  local scripts_ligne="" options_seules="" pos_script="m"
  [ -n "$line" ] || return 0
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    POS_SPAN="${entry%"${entry#?}"}"
    span="${entry#?}"
    [ -n "$span" ] || continue
    if examine_command "$doc" "$line" "$span"; then continue; fi
    # a lone option: --force, --root=<x>
    case "$span" in
      --[a-z]*)
        case "$span" in
          *[!A-Za-z0-9=\ \<\>._/-]*) : ;;
          *) options_seules="$options_seules
${span%% *}" ;;
        esac
        continue
        ;;
    esac
    # a form "interpreter script option..." or "script option..."
    case "$span" in
      *' '*)
        # shellcheck disable=SC2086
        set -- $span
        while [ $# -gt 0 ]; do
          case "$1" in
            bash|sh|zsh|python|python3|node|bun|deno|tsx|uv|run|npx|'$') shift ;;
            *) break ;;
          esac
        done
        [ $# -gt 0 ] || continue
        s="$1"; shift
        normalize_path "$s"
        s="$NORM"
        [ -n "$s" ] || continue
        if script_ext "${s##*/}"; then
          check_path "$doc" "$line" "$s"
          if [ -n "$SCRIPT_RESOLVED" ]; then
            for opt in "$@"; do
              case "$opt" in
                --[a-z]*) check_option "$doc" "$line" "$SCRIPT_RESOLVED" "$opt" 1 ;;
              esac
            done
          fi
        fi
        ;;
      *)
        check_path "$doc" "$line" "$span"
        if [ -n "$SCRIPT_RESOLVED" ]; then
          scripts_ligne="$scripts_ligne
$SCRIPT_RESOLVED"
          pos_script="$POS_SPAN"
        fi
        ;;
    esac
  done <<END_LIST
$LINE_SPANS
END_LIST
  if [ -n "$options_seules" ]; then
    # the distinct scripts of the line: we only keep the single-script case, no process
    script_unique=""; nb=0
    while IFS= read -r sl; do
      [ -n "$sl" ] || continue
      if [ "$nb" -eq 0 ]; then
        script_unique="$sl"; nb=1
      elif [ "$sl" != "$script_unique" ]; then
        nb=2; break
      fi
    done <<END_LIST
$scripts_ligne
END_LIST
    if [ "$nb" -eq 1 ]; then
      while IFS= read -r opt; do
        [ -n "$opt" ] || continue
        POS_SPAN="$pos_script"
        check_option "$doc" "$line" "$script_unique" "$opt"
      done <<END_LIST
$options_seules
END_LIST
    fi
  fi
  return 0
}

# --- counts -----------------------------------------------------------------

count_files() { # <dir> <name>
  local d="$1" name="$2" list
  # Always the disk, never `git ls-files -co --exclude-standard`: a file ignored by git
  # (local notes, local script) is in the directory, it counts. Only heavy generated output is pruned.
  # shellcheck disable=SC2046
  list="$(find "$d" $(exclusions_prune) -o -type f -print 2>/dev/null || true)"
  case "$name" in
    scripts)
      printf '%s\n' "$list" | awk '/\.(sh|bash|py|js|mjs|cjs|ts|rb|pl|ps1)$/ {n++} END {print n + 0}'
      ;;
    pages)
      printf '%s\n' "$list" | awk '/\.md$/ {n++} END {print n + 0}'
      ;;
    *)
      printf '%s\n' "$list" | awk 'NF {n++} END {print n + 0}'
      ;;
  esac
  return 0
}

check_count() { # <doc> <line> <number> <name> <dir>
  local doc="$1" line="$2" number="$3" rawname="$4" name d="${5%/}" actual docdir
  case "$doc" in */*) docdir="${doc%/*}" ;; *) docdir="." ;; esac
  # "files" and "fichiers", "pages" and "fiches" count the same things
  case "$rawname" in
    fichiers) name=files ;;
    fiches) name=pages ;;
    *) name="$rawname" ;;
  esac
  if [ ! -d "$d" ]; then
    if [ "$docdir" != "." ] && [ -d "$docdir/$d" ]; then d="$docdir/$d"; else return 0; fi
  fi
  if submodule_empty "$d"; then return 0; fi
  actual="$(count_files "$d" "$name")"
  if [ "$actual" -ne "$number" ]; then
    flag count "$doc" "$line" "$number $rawname (\`$d/\`)" "the directory has $actual" "$d" "$d/"
  fi
  return 0
}

# --- extraction ------------------------------------------------------------

# A file becomes a stream of records separated by \037:
#   S line span                       a span between backticks, outside a code block
#   N line number name dir-span       a prose count next to a directory
#   T line number name path root      a count in the comment of a tree
extract() { # <file>
  awk -v SEP="$SEP" '
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  function is_dir_span(s) {
    if (s !~ /\/$/) return 0
    if (s ~ /[ \t*<>{}$|]/) return 0
    if (s ~ /^(\/|~|http)/) return 0
    return 1
  }
  # The counts of a text: looks for "N files" and its neighbours.
  function qualified(before) {
    before = tolower(before)
    if (before ~ /(~|≈|environ|pres de|près de|plus de|moins de|au moins|au plus|jusqu.à|quelque|max|maximum|soit|about|around|roughly|approximately|nearly|almost|over|more than|fewer than|less than|at least|at most|up to|some|>|<|\+|×|x|\/) ?$/) return 1
    if (before ~ /[0-9.,]$/) return 1
    # a number between quotes is cited, often to contradict it
    if (before ~ /(«|")[ \t]*(\*\*)?$/) return 1
    return 0
  }
  function tail_ok(after) {
    after = trim(after)
    if (after == "") return 1
    if (after ~ /^(dont|dans|au |et |sous|hors|sur|en |à |a |ici|au total|of |in |inside |within |under |outside |on |at |and |here|in total|overall|including|across|total)/) return 1
    if (after ~ /^[^A-Za-z]/) return 1
    return 0
  }
  function passe(l) {
    l = tolower(l)
    return (l ~ /(décrivait|annonçait|affirmait|disait|indiquait|comptait|portait|était|étaient|avait|au lieu de|contre [0-9]|passé de|passait|used to|instead of|up from|down from|went from|against [0-9]|(^|[^a-z])(was|were|had)([^a-z]|$)|described|announced|claimed|stated|counted)/)
  }
  function counts(text, mode, path, tree_root,    rest, off, deb, len, m, number, name, before, after, i, best, dist, d, endp) {
    rest = text; off = 0
    while (match(rest, /[0-9]+ (fichiers|files|scripts|fiches|pages)/)) {
      deb = off + RSTART; len = RLENGTH
      m = substr(rest, RSTART, RLENGTH)
      split(m, mm, " ")
      number = mm[1]; name = mm[2]
      before = substr(text, (deb > 25 ? deb - 25 : 1), (deb > 25 ? 25 : deb - 1))
      after = substr(text, deb + len, 30)
      if (!qualified(before) && tail_ok(after) && !passe(text)) {
        if (mode == "T") {
          printf "T%s%d%s%s%s%s%s%s%s%s\n", SEP, NR, SEP, number, SEP, name, SEP, path, SEP, tree_root
        } else {
          best = ""; dist = 100000
          for (i = 1; i <= nsp; i++) {
            if (!is_dir_span(sp[i])) continue
            # distance from the span edge to the number edge, on a tie the span before
            endp = spos[i] + length(sp[i]) + 2
            if (endp <= deb) d = deb - endp
            else d = spos[i] - (deb + len)
            if (d < 0) d = 0
            if (d < dist || (d == dist && spos[i] < deb)) { dist = d; best = sp[i] }
          }
          if (best != "" && dist <= 90 && !ext_line) {
            printf "N%s%d%s%s%s%s%s%s\n", SEP, NR, SEP, number, SEP, name, SEP, best
          }
        }
      }
      off = deb + len - 1
      rest = substr(text, off + 1)
    }
  }
  BEGIN { infence = 0; inhtml = 0; tree_root = "" }
  {
    line = $0
    sub(/\r$/, "", line)

    if (infence) {
      if (line ~ /^[ \t>]*(```|~~~)/) { infence = 0; next }
      t = line
      gsub(/\302\240/, " ", t)
      gsub(/│/, "|", t)
      gsub(/(├|└)(─|-)+/, "+--", t)
      gsub(/\|--/, "+--", t)
      gsub(/`--/, "+--", t)
      p = index(t, "+--")
      if (p == 0) {
        s = trim(t)
        if (first && s ~ /\/$/ && s !~ /[ \t]/) { tree_root = s; sub(/\/$/, "", tree_root); sub(/^~?\//, "", tree_root) }
        if (s != "") first = 0
        next
      }
      first = 0
      depth = int((p - 1) / 4)
      rest = trim(substr(t, p + 3))
      nm = rest; sub(/[ \t].*$/, "", nm)
      com = substr(rest, length(nm) + 1)
      stack[depth] = nm
      path = ""
      for (k = 0; k <= depth; k++) {
        e = stack[k]; sub(/\/$/, "", e)
        if (e == "") continue
        path = (path == "" ? e : path "/" e)
      }
      if (com != "") { nsp = 0; ext_line = 0; counts(com, "T", path, tree_root) }
      next
    }

    if (inhtml) {
      p = index(line, "-->")
      if (p == 0) next
      line = substr(line, p + 3); inhtml = 0
    }
    if (line ~ /^[ \t>]*(```|~~~)/) {
      infence = 1; first = 1; tree_root = ""
      for (k in stack) delete stack[k]
      next
    }
    while ((s = index(line, "<!--")) > 0) {
      e = index(substr(line, s + 4), "-->")
      if (e == 0) { line = substr(line, 1, s - 1); inhtml = 1; break }
      line = substr(line, 1, s - 1) " " substr(line, s + 4 + e + 2)
    }

    # a ticked task tells what was done, not what is true now
    # a line that points to a dated document or a history folder talks about it
    if (line ~ /\]\([^)]*(sessions|plans|prompts|audits|superpowers|retros|journal|logs|log|postmortems)\/[^)]*\)/) next
    if (line ~ /\]\([^)]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][^)]*\)/) next
    # an open task describes what remains to do, its paths are often to be created
    if (line ~ /^[ \t>]*[-*+] \[[ xX]\]/) next
    # a sentence folded over two lines: the marker of the previous line counts too
    cont = (line !~ /^[ \t>]*([-*+]|[0-9]+[.)]|#|\|)/ && line !~ /^[ \t]*$/)
    low = tolower(line)
    if (cont) low = tolower(previous) " " low
    previous = line
    if (low ~ /n(.|...)existe (pas|plus)|existe pas encore|supprim|à créer|a creer|à écrire|a ecrire|exemple|example|e\.g\.|par ex\.|hypoth|fictif|à venir|a venir|retiré|archiv|futur|prévu|à terme|deplac|déplac|renomm|remplacé|remplace par|obsol|ancien|gitignor|ignoré par git|n.est pas versionn|non versionn|does( not|n.t) exist|no longer exist|not exist yet|removed|deleted|to create|to be created|to write|planned|upcoming|future|to come|renamed|moved|replaced|superseded|obsolete|deprecated|legacy|former|hypothetical|fictional|archived|ignored by git|not versioned|untracked/) next

    # the spans of the line
    nsp = 0; ext_line = 0
    rest = line; off = 0
    while (match(rest, /`[^`]+`/)) {
      nsp++
      sp[nsp] = substr(rest, RSTART + 1, RLENGTH - 2)
      spos[nsp] = off + RSTART
      off += RSTART + RLENGTH - 1
      rest = substr(rest, RSTART + RLENGTH)
      sp[nsp] = trim(sp[nsp])
      if (sp[nsp] ~ /^\*?\.[A-Za-z0-9]+$/ || sp[nsp] ~ /^\*\.[A-Za-z0-9]+$/) ext_line = 1
      # we only send the shell what it knows how to check
      w1 = sp[nsp]; sub(/[ \t].*$/, "", w1)
      if (sp[nsp] ~ /[ \t]/) {
        if (w1 !~ /^(npm|bun|pnpm|yarn|make|bash|sh|zsh|python|python3|node|deno|tsx|uv|npx|\$)$/ && w1 !~ /\.(sh|bash|py|js|mjs|cjs|ts|rb|pl)$/) continue
      } else if (sp[nsp] !~ /[\/.]/ && sp[nsp] !~ /^--/) continue
      # Position: "s" if the span is the subject of its line (first of a bullet, lone table
      # cell), "m" if it is cited mid-sentence. A line start is not enough: a folded
      # paragraph puts anything there.
      pref = substr(line, 1, spos[nsp] - 1)
      suff = substr(line, spos[nsp] + length(sp[nsp]) + 2)
      pos = "m"
      if (pref ~ /^[ \t>]*([-*+]|[0-9]+[.)])[ \t]+(\*\*)?(\[[ xX]\] )?$/) pos = "s"
      else if (pref ~ /\|[ \t]*$/ && suff ~ /^[ \t]*\|/) pos = "s"
      printf "S%s%d%s%s%s%s\n", SEP, NR, SEP, pos, SEP, sp[nsp]
    }
    if (nsp > 0 || line ~ /[0-9]+ (fichiers|files|scripts|fiches|pages)/) counts(line, "N", "", "")
  }' "$1"
}

process_file() { # <file>
  local f="$1" k line a b c d
  CURRENT_LINE=""; CURRENT_DOC="$f"; LINE_SPANS=""
  while IFS="$SEP" read -r k line a b c d || [ -n "${k:-}" ]; do
    case "$k" in
      S)
        if [ "$line" != "$CURRENT_LINE" ]; then
          flush_line
          CURRENT_LINE="$line"; LINE_SPANS=""
        fi
        LINE_SPANS="$LINE_SPANS
$a$b"
        ;;
      N)
        check_count "$f" "$line" "$a" "$b" "$c"
        ;;
      T)
        # a = number, b = name, c = path de l'entry, d = tree_root de l'arbre
        if [ -n "$d" ] && [ -d "$d" ]; then c="$d/$c"; fi
        check_count "$f" "$line" "$a" "$b" "$c"
        ;;
    esac
  done < <(extract "$f")
  flush_line
  return 0
}

# --- files to read -------------------------------------------------------------

DOC_LIST="$TMP/docs"
: > "$DOC_LIST"
add_doc() { # <file>
  local f="$1" target
  [ -f "$f" ] || return 0
  # the log tells the past, its paths are allowed to have vanished
  case "${f##*/}" in CHANGELOG*|changelog*) return 0 ;; esac
  if [ -L "$f" ]; then
    target="$(readlink "$f" 2>/dev/null || true)"
    case "$target" in
      CLAUDE.md|AGENTS.md|./CLAUDE.md|./AGENTS.md) return 0 ;;
    esac
  fi
  printf '%s\n' "$f" >> "$DOC_LIST"
  return 0
}

add_doc CLAUDE.md
add_doc AGENTS.md
while IFS= read -r p; do
  p="$(printf '%s' "$p" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$p" ] || continue
  case "$p" in CLAUDE.md|AGENTS.md) continue ;; esac
  add_doc "$p"
done <<END_LIST
$(printf '%s\n' "$PILLARS" | tr ',' '\n')
END_LIST
if [ -d "$DIR_DOCS" ]; then
  # Folders that tell the past: nothing is checked there. Nor a dated document, nor a
  # log, which describe a moment and not the state of the repo.
  set --
  for h in archives sessions plans superpowers retros journal log logs postmortems prompts audits; do
    set -- "$@" -not -path "*/$h/*"
  done
  # shellcheck disable=SC2046
  find "$DIR_DOCS" $(exclusions_prune) -o -name '*.md' -not -path "$DIR_ARCHIVES/*" "$@" \
    -not -name 'journal*' -not -name 'log-*' -not -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*' -print 2>/dev/null \
    | LC_ALL=C sort >> "$DOC_LIST" || true
fi
sort -u "$DOC_LIST" -o "$DOC_LIST"

# Repo manifests, minus excluded folders.
# shellcheck disable=SC2046
PACKAGES="$(find . -maxdepth 4 $(exclusions_prune) -o -name package.json -print 2>/dev/null | sed 's|^\./||' || true)"
# shellcheck disable=SC2046
MAKEFILES="$(find . -maxdepth 4 $(exclusions_prune) -o \( -name Makefile -o -name makefile -o -name GNUmakefile -o -name '*.mk' \) -print 2>/dev/null | sed 's|^\./||' || true)"

while IFS= read -r f; do
  [ -n "$f" ] || continue
  f="${f#./}"
  process_file "$f"
done < "$DOC_LIST"

# Git's verdict on the paths of pending warnings: a single git check-ignore for all,
# taking each path in both forms (with and without trailing slash) like git_ignored. A
# path that leaves the repo (`..`) or any batch failure falls back to git_ignored, path
# by path, which stays the reference. An ignored path loses its warning.
ignore_batch() {
  local k rc=0 LOT="$TMP/ign-lot" ENTREE="$TMP/ign-entry" SORTIE="$TMP/ign-sortie" IGNORES="$TMP/ign-list"
  : > "$IGNORES"
  : > "$LOT"
  awk -v SEP="$SEP" '
    { i = index($0, SEP); k = substr($0, 1, i - 1)
      if (!(k in vu)) { vu[k] = 1; print k } }' "$FLAGS_IGN" > "$TMP/ign-cles"
  # paths that climb out of the root: git refuses them, we judge them one by one
  while IFS= read -r k; do
    case "$k" in
      ..|../*|*/..|*/../*) if git_ignored "$k"; then printf '%s\n' "$k" >> "$IGNORES"; fi ;;
      *) printf '%s\n%s/\n' "$k" "$k" >> "$LOT" ;;
    esac
  done < "$TMP/ign-cles"
  if [ -s "$LOT" ]; then
    tr '\n' '\0' < "$LOT" > "$ENTREE"
    git check-ignore -z --stdin < "$ENTREE" > "$SORTIE" 2>/dev/null || rc=$?
    if [ "$rc" -le 1 ]; then
      tr '\0' '\n' < "$SORTIE" >> "$IGNORES"
    else
      while IFS= read -r k; do
        case "$k" in
          ..|../*|*/..|*/../*) continue ;;
        esac
        if git_ignored "$k"; then printf '%s\n' "$k" >> "$IGNORES"; fi
      done < "$TMP/ign-cles"
    fi
  fi
  awk -v SEP="$SEP" '
    FILENAME == ARGV[1] { ign[$0] = 1; next }
    { i = index($0, SEP); k = substr($0, 1, i - 1)
      if (!(k in ign) && !((k "/") in ign)) print substr($0, i + 1) }' "$IGNORES" "$FLAGS_IGN" >> "$FLAGS"
  return 0
}
if [ -s "$FLAGS_IGN" ]; then ignore_batch; fi

# --- rendu ---------------------------------------------------------------------

# The same claim cited on several lines of a file makes only one warning: the first
# line, with the number of the others.
SUMMARY="$TMP/resume"
sort -t "$SEP" -k2,2 -k3,3n "$FLAGS" | awk -F "$SEP" -v SEP="$SEP" '
  { key = $2 SEP $4
    if (!(key in vu)) { vu[key] = ++n; fam[n] = $1; fic[n] = $2; lig[n] = $3; claim[n] = $4; reason[n] = $5; rest[n] = 0 }
    else {
      i = vu[key]; rest[i]++
      # an occurrence in subject position wins over mid-sentence mentions
      if (fam[i] ~ /~$/ && $1 !~ /~$/) { fam[i] = $1; lig[i] = $3; reason[i] = $5 }
    } }
  END { for (i = 1; i <= n; i++) {
          r = reason[i]
          if (rest[i] > 0) r = r " (also cited on " rest[i] " other line(s))"
          printf "%s%s%s%s%s%s%s%s%s\n", fam[i], SEP, fic[i], SEP, lig[i], SEP, claim[i], SEP, r } }' > "$SUMMARY"

level_of() { # <family>, with a ~ at the end when the claim is cited mid-sentence
  case "$1" in
    *'~') printf 'info\n'; return 0 ;;
  esac
  case "$1" in
    path)    printf '%s\n' "$LEVEL_path" ;;
    script)    printf '%s\n' "$LEVEL_script" ;;
    option)    printf '%s\n' "$LEVEL_option" ;;
    command)  printf '%s\n' "$LEVEL_command" ;;
    count)  printf '%s\n' "$LEVEL_count" ;;
    *)         printf 'warning\n' ;;
  esac
  return 0
}

NB_WARNINGS=0
NB_INFOS=0
FIRST=1
if [ "$JSON" -eq 1 ]; then printf '['; fi
while IFS="$SEP" read -r fam fic lig claim reason; do
  [ -n "$fam" ] || continue
  lvl="$(level_of "$fam")"
  if [ "$lvl" = warning ]; then NB_WARNINGS=$((NB_WARNINGS + 1)); else NB_INFOS=$((NB_INFOS + 1)); fi
  if [ "$JSON" -eq 1 ]; then
    msg="line $lig: $claim: $reason"
    msg="$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    fjs="$(printf '%s' "$fic" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    if [ "$FIRST" -eq 1 ]; then printf '\n'; FIRST=0; else printf ',\n'; fi
    printf '  {"section":"truth","level":"%s","file":"%s","message":"%s"}' "$lvl" "$fjs" "$msg"
  else
    if [ "$lvl" = warning ]; then
      printf '%s:%s  %s  %s\n' "$fic" "$lig" "$claim" "$reason"
    elif [ "$INFO" -eq 1 ]; then
      printf '%s:%s  %s  %s (info)\n' "$fic" "$lig" "$claim" "$reason"
    fi
  fi
done < "$SUMMARY"
if [ "$JSON" -eq 1 ]; then
  if [ "$FIRST" -eq 1 ]; then printf ']\n'; else printf '\n]\n'; fi
else
  if [ "$NB_INFOS" -gt 0 ]; then
    if [ "$INFO" -eq 1 ]; then
      printf 'Total: %s false claim(s), %s to review (info).\n' "$NB_WARNINGS" "$NB_INFOS"
    else
      printf 'Total: %s false claim(s), %s to review with --info.\n' "$NB_WARNINGS" "$NB_INFOS"
    fi
  else
    printf 'Total: %s false claim(s).\n' "$NB_WARNINGS"
  fi
fi

if [ "$STRICT" -eq 1 ] && [ "$NB_WARNINGS" -gt 0 ]; then exit 1; fi
exit 0
