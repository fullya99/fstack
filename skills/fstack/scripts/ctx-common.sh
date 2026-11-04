#!/usr/bin/env bash
#
# ctx-common.sh: library sourced by the ctx-*.sh scripts. Not run on its own.
#
# Usage: . "$(dirname "$0")/ctx-common.sh"
# Functions read from the current directory, or from $CTX_ROOT when it is set.
# The block read is the <!-- contexte:convention ... --> one, one `key: value` line at a time.
#
#   conv_find              path of the first root .md file that carries the block, or nothing
#   conv_read <key>           raw value of the `key: value` line, or nothing
#   conv_version              0 without a block, 4 for a block without version:, else the value
#   conv_threshold <file> <def>   threshold from `seuils: A=600, B=250` for <file>, else <def>
#   conv_exception <t> <path>  code 0 if `exceptions: t=pattern, ...` covers <path> (shell glob)
#   conv_log_format       value of `journal:`, or nothing
#   log_pattern <format>    ERE pattern of an entry heading: date-titre, keep-a-changelog, crochets
#   log_detect <file>    format declared by `journal:`, else the one found in <file>, or nothing
#   exclusions_find           pruned directories, as arguments for find: heavy generated output
#                             (list, CACHEDIR.TAG, game engines) and `ignorer:`, never the gitignore
#   exclusions_load        computes this list once in the main shell ($(...) calls reread it)
#   exclusions_names           what is pruned beyond the fixed list: `category<TAB>root<TAB>detail`
#   exclusions_names_grouped   the same names, one per engine and root, with their folders
#   exclusions_count_ignored <glob>   number of files an `ignorer:` glob skips
#   submodules              submodule paths, read from .gitmodules
#   scripts_version           code 1 and a message if the block is newer than CTX_VERSION
#   conv_load              reads the block once and keeps it in memory for later calls
#   detect_language        fr or en, guessed from CLAUDE.md, CODEMAP.md, README.md
#   ctx_today            today's date YYYY-MM-DD, or $CTX_TODAY when it is set (tests)
#   ctx_epoch <YYYY-MM-DD>    seconds since 1970, BSD first then GNU, nothing if unreadable
#   ctx_days_since <date>   days between <date> and ctx_today, nothing if unreadable
#
# Functions always return 0 except conv_exception and scripts_version, so they do not
# kill a caller running under set -e.

CTX_VERSION=5

_ctx_root() {
  printf '%s\n' "${CTX_ROOT:-.}"
}

# Convention block: the lines between the opening and the closing marker. After conv_load,
# the block comes from memory: an audit that queries the block per page no longer rereads the
# file on each call. The variable crosses $(...) subshells on purpose.
_conv_block() {
  if [ "${CTX_BLOCK_LOADED:-0}" = 1 ]; then
    if [ -n "${CTX_BLOCK_CACHE:-}" ]; then printf '%s\n' "$CTX_BLOCK_CACHE"; fi
    return 0
  fi
  _conv_block_read
}

conv_load() {
  CTX_BLOCK_LOADED=0
  CTX_BLOCK_CACHE="$(_conv_block_read)"
  CTX_BLOCK_LOADED=1
  return 0
}

_conv_block_read() {
  local f
  f="$(conv_find)"
  if [ -n "$f" ]; then
    # A block opened and closed on the same line is empty, the rest of the file is not read.
    awk '/<!-- contexte:convention/ { if ($0 ~ /contexte:convention.*-->/) exit; inside=1; next }
         inside && /-->/ {exit}
         inside {print}' "$f"
  fi
  return 0
}

# List `a=b, c=d` as one entry per line.
_conv_entries() { # <key>
  conv_read "$1" | tr ',' '\n'
  return 0
}

_conv_trim() {
  sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

conv_find() {
  local r f
  r="$(_ctx_root)"
  for f in CODEMAP.md CLAUDE.md AGENTS.md; do
    if [ -f "$r/$f" ] && grep -q '<!-- contexte:convention' "$r/$f" 2>/dev/null; then
      if [ "$r" = "." ]; then printf '%s\n' "$f"; else printf '%s\n' "$r/$f"; fi
      return 0
    fi
  done
  # find and not a glob: callers run under set -f, where ./*.md would stay literal.
  for f in $(find "$r" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sed 's|.*/||' | LC_ALL=C sort); do
    case "$f" in CODEMAP.md|CLAUDE.md|AGENTS.md) continue ;; esac
    if grep -q '<!-- contexte:convention' "$r/$f" 2>/dev/null; then
      if [ "$r" = "." ]; then printf '%s\n' "$f"; else printf '%s\n' "$r/$f"; fi
      return 0
    fi
  done
  return 0
}

conv_read() { # <key>
  local key="$1"
  _conv_block | awk -v k="$key" '
    !seen && index($0, k ":") == 1 {
      v = substr($0, length(k) + 2)
      sub(/^[ \t]+/, "", v); sub(/[ \t\r]+$/, "", v)
      print v; seen = 1
    }'
  return 0
}

conv_version() {
  local f v
  f="$(conv_find)"
  if [ -z "$f" ]; then echo 0; return 0; fi
  v="$(conv_read version)"
  if [ -z "$v" ]; then echo 4; else echo "$v"; fi
  return 0
}

conv_threshold() { # <file> <default>
  local file="$1" default="$2" e name val
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    name="$(printf '%s' "${e%%=*}" | _conv_trim)"
    val="$(printf '%s' "${e#*=}" | _conv_trim)"
    case "$val" in ''|*[!0-9]*) continue ;; esac
    if [ "$name" = "$file" ]; then echo "$val"; return 0; fi
  done <<END
$(_conv_entries seuils)
END
  echo "$default"
  return 0
}

conv_exception() { # <type> <path>
  local type="$1" path="${2#./}" e t pattern
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    t="$(printf '%s' "${e%%=*}" | _conv_trim)"
    pattern="$(printf '%s' "${e#*=}" | _conv_trim)"
    [ "$t" = "$type" ] || continue
    [ -n "$pattern" ] || continue
    # in a case, * also covers /, so ** and * are equivalent here
    # shellcheck disable=SC2254
    case "$path" in $pattern) return 0 ;; esac
  done <<END
$(_conv_entries exceptions)
END
  return 1
}

conv_log_format() {
  conv_read journal
  return 0
}

# The three recognised log formats. date-titre is the widest, it also covers a
# keep-a-changelog heading on purpose: a mixed log reads as date-titre.
# No backslash and no {n} interval: the same pattern serves grep -E, awk -v, gawk which
# eats \[, and old awks without intervals. [[] and []] stand for a bracket.
log_pattern() { # <format>
  local d='[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
  case "${1:-}" in
    date-titre)       printf '%s\n' "^## .*${d}" ;;
    keep-a-changelog) printf '%s\n' "^## [[][^]]*[]] - ${d}" ;;
    crochets)         printf '%s\n' "^[[]${d}[]] " ;;
  esac
  return 0
}

# The block decides whether it declares `journal:`. Otherwise the headings of each format are
# counted outside code blocks, and the most specific wins when it covers the whole log.
log_detect() { # <file>
  local f="${1:-}" decl dt kac cr
  decl="$(conv_log_format)"
  if [ -n "$decl" ]; then
    printf '%s\n' "$decl"
    return 0
  fi
  [ -f "$f" ] || return 0
  _log_count() {
    M="$1" awk '/^```/ {code = !code; next} !code && $0 ~ ENVIRON["M"] {n++} END {print n + 0}' "$f"
  }
  dt="$(_log_count "$(log_pattern date-titre)")"
  kac="$(_log_count "$(log_pattern keep-a-changelog)")"
  cr="$(_log_count "$(log_pattern crochets)")"
  if [ "$cr" -gt "$dt" ]; then
    printf '%s\n' crochets
  elif [ "$kac" -gt 0 ] && [ "$kac" -eq "$dt" ]; then
    printf '%s\n' keep-a-changelog
  elif [ "$dt" -gt 0 ]; then
    printf '%s\n' date-titre
  fi
  return 0
}

# --- pruning: what the scripts do not walk -------------------------------------
#
# Principle: the gitignore is NOT a pruning source. A file ignored by git (local notes,
# context-input/, deliverables, CLAUDE.local.md) is context, so the list never comes from
# `git ls-files`. For speed, only heavy generated output is pruned, recognised by its nature,
# and every pruning is named (exclusions_names, which the audit prints).
#
# A single list, to give to find WITHOUT quotes, in a context where the shell does not
# expand patterns (set -f): find . $(exclusions_find)
# It has four sources:
#   1. unambiguous generated folders, by name, at any depth;
#   2. any folder that carries a CACHEDIR.TAG with a verified signature (Cargo writes one);
#   3. the folders of a game engine, only if the engine marker is at the root:
#      Unity (ProjectSettings/ProjectVersion.txt), Unreal (*.uproject), Godot (project.godot).
#      A `Library/` of an ordinary project is still walked;
#   4. the `ignorer:` key of the block, globs relative to the root, for what git tracks but
#      is not part of the project (an old repo imported as is).
# Names with a space or a wildcard cannot be represented in a word list: they are not pruned.
_EXCL_STATIC='-not -path ./.git/* -not -path ./archives/* -not -path */node_modules/* -not -path */vendor/* -not -path */.venv/* -not -path */venv/* -not -path */dist/* -not -path */build/* -not -path */target/* -not -path */.next/* -not -path */__pycache__/* -not -path */.cache/* -not -path */.gradle/* -not -path */Pods/* -not -path */.dart_tool/* -not -path */.nuxt/* -not -path */.svelte-kit/* -not -path */.turbo/* -not -path */.parcel-cache/* -not -path */.terraform/* -not -path */.pytest_cache/* -not -path */.mypy_cache/* -not -path */.tox/*'
CTX_CACHEDIR_SIGNATURE='Signature: 8a477f597d28d172789f06886806bc55'

# A name that find -path and the word list carry without distorting it.
_excl_safe_name() { # <name>
  case "$1" in ''|*[[:space:]]*|*'*'*|*'?'*|*'['*|*'\'*) return 1 ;; esac
  return 0
}

# Generated folders of an engine in <root>/<rel>, `type<TAB>rel<TAB>folder`, only those
# that exist. <rel> is . for the root.
_excl_engine_dirs() { # <root> <rel> <type>
  local r="$1" rel="$2" t="$3" d dirs p
  case "$t" in
    Unity)           dirs="Library Temp Logs obj UserSettings" ;;
    Unreal)          dirs="Intermediate Binaries DerivedDataCache Saved" ;;
    'Unreal plugin') dirs="Intermediate Binaries" ;;
    Godot)           dirs=".godot" ;;
    *) return 0 ;;
  esac
  for d in $dirs; do
    if [ "$rel" = . ]; then p="$d"; else p="$rel/$d"; fi
    if [ -d "$r/$p" ]; then printf '%s\t%s\t%s\n' "$t" "$rel" "$d"; fi
  done
  return 0
}

# Engines whose marker is at the root, `type<TAB>.`: a direct test, no walk.
# They keep the walk out of their Library/ when looking for nested engines.
_excl_root_engines() { # <root>
  local r="$1" u f
  if [ -f "$r/ProjectSettings/ProjectVersion.txt" ]; then printf 'Unity\t.\n'; fi
  # a glob in a subshell, set +f: callers run under set -f
  u="$( set +f; for f in "$r"/*.uproject; do if [ -f "$f" ]; then echo yes; break; fi; done )"
  if [ -n "$u" ]; then printf 'Unreal\t.\n'; fi
  if [ -f "$r/project.godot" ]; then printf 'Godot\t.\n'; fi
  return 0
}

# An engine and its root <rel>: adds its generated folders to the list and the names. Cap of
# 20 engine roots, the following ones are counted and reported. The _EX_* variables belong
# to _exclusions_compute, which runs in the calling shell: no subshell here.
_EX_BASE=""; _EX_NAMES=""; _EX_SEEN=""; _EX_N=0; _EX_CAP=0; _EX_DIRS=""
_excl_add_engine() { # <root> <rel> <type>
  local r="$1" rel="$2" t="$3" l d p tab
  tab="$(printf '\t')"
  case "$_EX_SEEN" in *"|$t|$rel|"*) return 0 ;; esac
  _excl_safe_name "$rel" || return 0
  if [ "$_EX_N" -ge 20 ]; then _EX_CAP=$((_EX_CAP + 1)); return 0; fi
  _EX_SEEN="$_EX_SEEN|$t|$rel|"
  _EX_N=$((_EX_N + 1))
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    d="${l##*"$tab"}"
    if [ "$rel" = . ]; then p="$d"; else p="$rel/$d"; fi
    _EX_BASE="$_EX_BASE -not -path ./$p/*"
    _EX_DIRS="$_EX_DIRS ./$p/"
    _EX_NAMES="${_EX_NAMES}${l}
"
  done <<END
$(_excl_engine_dirs "$r" "$rel" "$t")
END
  return 0
}

# The `ignorer:` globs, one per line, without a leading ./. A value with a blank is skipped.
_excl_ignore_globs() {
  local e g
  # without the key there is nothing to read: neither tr nor sed is started
  [ -n "$(conv_read ignorer)" ] || return 0
  while IFS= read -r e; do
    g="$(printf '%s' "$e" | _conv_trim)"
    while [ "${g#./}" != "$g" ]; do g="${g#./}"; done
    _excl_safe_glob "$g" || continue
    printf '%s\n' "$g"
  done <<END
$(_conv_entries ignorer)
END
  return 0
}
_excl_safe_glob() { # a glob keeps its wildcards, not its blanks
  case "$1" in ''|*[[:space:]]*|*'\'*|/*) return 1 ;; esac
  return 0
}

# An `ignorer:` glob as find arguments. A subtree (`d/**`, `d/*`, `d/`) gives
# `-not -path ./d/*`, anything else the path itself and its content. `**/x` means x at any depth.
_excl_ignore_args() { # <glob>
  local g="$1" out
  out="$(_excl_anchor './' "$g")"
  case "$g" in
    '**/'*) g="${g#\*\*/}"; out="$(_excl_anchor './' "$g") $(_excl_anchor '*/' "$g")" ;;
  esac
  printf '%s\n' "$out"
  return 0
}
# An anchored glob: a subtree (`d/**`, `d/*`, `d/`) keeps only its content, anything else
# the path itself and its content.
_excl_anchor() { # <anchor> <glob>
  local a="$1" g="$2" d
  case "$g" in '**/'*) g="${g#\*\*/}" ;; esac
  case "$g" in
    *'/**') d="${g%/\*\*}"; printf '%s\n' "-not -path $a$d/*" ;;
    *'/*')  d="${g%/\*}";   printf '%s\n' "-not -path $a$d/*" ;;
    */)     d="${g%/}";     printf '%s\n' "-not -path $a$d/*" ;;
    *)      printf '%s\n' "-not -path $a$g -not -path $a$g/*" ;;
  esac
  return 0
}

# A single walk looks for the engine markers and the CACHEDIR.TAG files, sorted `./...` paths.
# It skips what the other sources already prune (fixed list, `ignorer:`, root engine
# folders), and does not descend into a Library/ to find it.
_excl_discover() { # <root> <words already pruned>
  local r="$1"
  shift
  # shellcheck disable=SC2046
  ( cd "$r" 2>/dev/null && set -f && \
      find . $(_excl_prune_args "$@") -o -type f \( -name CACHEDIR.TAG -o -name project.godot \
        -o -name '*.uproject' -o -name '*.uplugin' -o -path '*/ProjectSettings/ProjectVersion.txt' \) -print 2>/dev/null
  ) | LC_ALL=C sort
  return 0
}

# The `-not -path X/*` arguments of a list, as a prune prefix for find:
# `( -type d ( -path X -o ... ) -prune )`. Returns the words, to give without quotes.
# A path that does not end in /* (an `ignorer:` glob aimed at a file) is pruned
# whatever its type: `( ( ( -type d ( ... ) ) -o ( -path F ) ) -prune )`.
_excl_prune_args() { # <exclusion words>
  local w d="" f=""
  for w in "$@"; do
    case "$w" in
      -not|-path) ;;
      */\*) d="$d${d:+ -o }-path ${w%/\*}" ;;
      *)    f="$f${f:+ -o }-path $w" ;;
    esac
  done
  if [ -z "$f" ]; then
    printf '( -type d ( %s ) -prune )\n' "$d"
  else
    printf '( ( ( -type d ( %s ) ) -o ( %s ) ) -prune )\n' "$d" "$f"
  fi
  return 0
}

# The same list as pruning, to give to find WITHOUT quotes under set -f, before `-o` and the test:
#   find . $(exclusions_prune) -o -type f -print
# find no longer descends into a 20,000-file Library/ only to discard each file. Words passed
# as arguments are added to the list (`-not -path ./x/*`). The pruned folder itself is not
# printed, true for the prefix: to list it too,
# `find . \( $(exclusions_prune) -print \) -o ...`.
exclusions_prune() { # [<extra exclusion words>]
  # subshell under set -f: the list words carry wildcards, whatever the caller
  # shellcheck disable=SC2046
  ( set -f; _excl_prune_args $(exclusions_find) "$@" )
  return 0
}

# Computes the list and the names. Sets CTX_EXCL_BASE (static, engines, CACHEDIR.TAG), CTX_EXCL_IGN
# (the `ignorer:` globs), CTX_EXCL_LIST (both) and CTX_EXCL_NAMES, one line per folder:
# `type<TAB>root<TAB>folder` for an engine (Unity, Unreal, Unreal plugin, Godot, root . for
# the project one), `CACHEDIR.TAG<TAB>-<TAB>folder`, `ignorer<TAB>-<TAB>glob`, `cap<TAB>-<TAB>N`.
# An engine is recognised by its marker, at the root or down to depth 3: Unity
# ProjectSettings/ProjectVersion.txt, Unreal *.uproject, Godot project.godot, and for Unreal a
# plugin (Plugins/*/*.uplugin, depth 5). Its generated folders are read from its root.
_exclusions_compute() {
  local r l g a t rel p d x tab ign="" found tags="" depth lim under
  tab="$(printf '\t')"
  r="$(_ctx_root)"
  _EX_BASE="$_EXCL_STATIC"; _EX_NAMES=""; _EX_SEEN=""; _EX_N=0; _EX_CAP=0; _EX_DIRS=""
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    a="$(_excl_ignore_args "$g")"
    ign="$ign $a"
    _EX_NAMES="${_EX_NAMES}ignorer${tab}-${tab}${g}
"
  done <<END
$(_excl_ignore_globs)
END
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    _excl_add_engine "$r" "${l#*"$tab"}" "${l%%"$tab"*}"
  done <<END
$(_excl_root_engines "$r")
END
  # shellcheck disable=SC2086
  found="$(set -f; _excl_discover "$r" $_EX_BASE$ign)"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    t=""; rel=""; lim=3
    case "$p" in
      */CACHEDIR.TAG) tags="$tags$p
"; continue ;;
      */ProjectSettings/ProjectVersion.txt) t=Unity; rel="${p%/ProjectSettings/ProjectVersion.txt}" ;;
      */project.godot) t=Godot; rel="${p%/project.godot}" ;;
      */Plugins/*/*.uplugin) t='Unreal plugin'; rel="${p%/*}"; lim=5 ;;
      *.uproject) t=Unreal; rel="${p%/*}" ;;
      *) continue ;;
    esac
    rel="${rel#./}"
    depth=0
    if [ "$rel" != . ]; then x="${rel//[!\/]/}"; depth=$(( ${#x} + 1 )); fi
    [ "$depth" -le "$lim" ] || continue
    _excl_add_engine "$r" "$rel" "$t"
  done <<END
$found
END
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    d="${p%/CACHEDIR.TAG}"; d="${d#./}"
    # the root CACHEDIR.TAG does not prune the whole project
    [ -n "$d" ] && [ "$d" != "." ] && [ "$d" != "$p" ] || continue
    _excl_safe_name "$d" || continue
    case "$_EX_BASE$ign" in *" -not -path ./$d/*"*) continue ;; esac
    under=0
    for x in $_EX_DIRS; do
      case "./$d/" in "$x"*) under=1; break ;; esac
    done
    [ "$under" -eq 0 ] || continue
    l=""
    IFS= read -r l < "$r/$p" 2>/dev/null || true
    case "$l" in "$CTX_CACHEDIR_SIGNATURE"*) ;; *) continue ;; esac
    _EX_BASE="$_EX_BASE -not -path ./$d/*"
    _EX_DIRS="$_EX_DIRS ./$d/"
    _EX_NAMES="${_EX_NAMES}CACHEDIR.TAG${tab}-${tab}${d}
"
  done <<END
$tags
END
  if [ "$_EX_CAP" -gt 0 ]; then
    _EX_NAMES="${_EX_NAMES}cap${tab}-${tab}${_EX_CAP}
"
  fi
  CTX_EXCL_BASE="$_EX_BASE"
  CTX_EXCL_IGN="$ign"
  CTX_EXCL_LIST="$_EX_BASE$ign"
  CTX_EXCL_NAMES="$_EX_NAMES"
  return 0
}

# Call once in the main shell: later calls, including inside $(...), read memory
# instead of walking again for the CACHEDIR.TAG files.
exclusions_load() {
  CTX_EXCL_LOADED=0
  _exclusions_compute
  CTX_EXCL_LOADED=1
  return 0
}

exclusions_find() {
  if [ "${CTX_EXCL_LOADED:-0}" != 1 ]; then _exclusions_compute; fi
  printf '%s\n' "$CTX_EXCL_LIST"
  return 0
}

# What is pruned beyond the static list, one `category<TAB>root<TAB>detail` line each:
# `Unity<TAB>game<TAB>Library`, `CACHEDIR.TAG<TAB>-<TAB>target`, `ignorer<TAB>-<TAB>projets/*/context-input/**`.
exclusions_names() {
  if [ "${CTX_EXCL_LOADED:-0}" != 1 ]; then _exclusions_compute; fi
  printf '%s' "$CTX_EXCL_NAMES"
  return 0
}

# The grouped names, `category<TAB>root<TAB>list`: one engine per root (the list of its
# folders separated by commas), all CACHEDIR.TAG files together, one `ignorer` per glob, and
# `cap` when engine roots exceed the 20 recognised. root is - outside an engine.
exclusions_names_grouped() {
  exclusions_names | awk -F'\t' '
    { k = ($1 == "ignorer" || $1 == "cap" ? $1 "\t" $2 "\t" $3 : $1 "\t" $2)
      if (!(k in l)) { order[++n] = k; l[k] = $3 } else if ($1 != "ignorer" && $1 != "cap") l[k] = l[k] ", " $3 }
    END { for (i = 1; i <= n; i++) { k = order[i]; if (k ~ /^(ignorer|cap)\t/) print k; else print k "\t" l[k] } }'
  return 0
}

# How many files an `ignorer:` glob skips. Folders that the other sources prune are not
# walked, and the counted glob does not prune its own target.
exclusions_count_ignored() { # <glob>
  local g="$1" r n="" a
  r="$(_ctx_root)"
  if [ "${CTX_EXCL_LOADED:-0}" != 1 ]; then _exclusions_compute; fi
  a="$(_excl_ignore_args "$g")"
  # All in a subshell under set -f: the glob wildcards stay literal, whatever the caller.
  # shellcheck disable=SC2046,SC2086
  n="$( cd "$r" && set -f && {
      patterns=""; or=""
      for w in $a; do
        # (pattern) with an opening parenthesis: otherwise bash 3.2 closes the $( at the first pattern) of the case.
        case "$w" in (-not|-path) ;; (*) patterns="$patterns${or:+ -o }-path $w"; or=1 ;; esac
      done
      find . $(_excl_prune_args $CTX_EXCL_BASE) -o -type f \( $patterns \) -print 2>/dev/null | wc -l | tr -d ' '
    } )"
  printf '%s\n' "${n:-0}"
  return 0
}

submodules() {
  local r
  r="$(_ctx_root)"
  if [ -f "$r/.gitmodules" ]; then
    sed -n 's/^[[:space:]]*path[[:space:]]*=[[:space:]]*//p' "$r/.gitmodules" | sed 's/[[:space:]]*$//'
  fi
  return 0
}

scripts_version() {
  local v
  v="$(conv_version)"
  case "$v" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$v" -gt "$CTX_VERSION" ]; then
    printf 'The contexte:convention block is at version %s, these scripts only know version %s.\n' \
      "$v" "$CTX_VERSION" >&2
    printf 'Update the fstack plugin before running again.\n' >&2
    return 1
  fi
  return 0
}

# Language of a project, guessed from its root docs: fr or en, fr by default.
detect_language() {
  local f files=""
  for f in CLAUDE.md CODEMAP.md README.md; do
    if [ -f "$f" ]; then files="$files $f"; fi
  done
  [ -n "$files" ] || { echo fr; return 0; }
  # shellcheck disable=SC2086
  head -n 150 $files 2>/dev/null | tr '[:upper:]' '[:lower:]' | awk '
    { n = split($0, m, /[^a-z]+/)
      for (i = 1; i <= n; i++) {
        if (m[i] == "the" || m[i] == "and" || m[i] == "of" || m[i] == "is" || m[i] == "with") en++
        if (m[i] == "le" || m[i] == "la" || m[i] == "les" || m[i] == "des" || m[i] == "et" || m[i] == "est") fr++
      } }
    END { if (en > 2 * fr + 3) print "en"; else print "fr" }'
  return 0
}

ctx_today() {
  printf '%s\n' "${CTX_TODAY:-$(date +%Y-%m-%d)}"
  return 0
}

# date -j -f first: the BSD date of macOS takes -d for something else and may return
# the current time with code 0. On GNU, -j fails cleanly and -d takes over.
# An input that is not shaped YYYY-MM-DD returns empty: GNU `date -d ""` would return midnight today,
# and a missing date would read as today's date.
ctx_epoch() { # <YYYY-MM-DD>
  case "${1:-}" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) return 0 ;;
  esac
  date -j -f '%Y-%m-%d' "${1:-}" +%s 2>/dev/null || date -d "${1:-}" +%s 2>/dev/null || true
  return 0
}

# Whole days between two instants, rounded to the nearest (the 43200 absorbs daylight saving).
# Positive in the past, negative in the future. Bash division truncates toward zero, which
# would give 0 for tomorrow: the negative case is rounded separately.
ctx_days_between() { # <epoch now> <epoch date>
  local x=$(( $1 - $2 + 43200 ))
  if [ "$x" -lt 0 ]; then
    printf '%s\n' $(( (x - 86399) / 86400 ))
  else
    printf '%s\n' $(( x / 86400 ))
  fi
  return 0
}

ctx_days_since() { # <YYYY-MM-DD>
  local a b
  a="$(ctx_epoch "$(ctx_today)")"
  b="$(ctx_epoch "${1:-}")"
  if [ -n "$a" ] && [ -n "$b" ]; then
    ctx_days_between "$a" "$b"
  fi
  return 0
}
