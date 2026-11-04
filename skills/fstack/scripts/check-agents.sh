#!/usr/bin/env bash
#
# check-agents.sh: checks the frontmatter of sub-agent definition files.
#
# A malformed agent file is not loaded, and nothing says so. No startup error, no
# warning, the agent simply does not show up in the list. This script looks for the ways
# of vanishing silently, plus enumeration values that mean nothing.
#
# Same three verdicts as check-refs.sh:
#   TRUE          the file will be loaded
#   FALSE         it will not be, or a value will be ignored. The proof is alongside
#   UNVERIFIABLE  depends on something that is not in the repo
#
# Usage:
#   bash check-agents.sh [--format=tsv|--format=md] <directory|file> [...]
#
# Exits 1 if at least one FALSE remains, 0 otherwise.
#
set -euf

FORMAT="tsv"
TARGETS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --format=*) FORMAT="${1#--format=}" ;;
    -h|--help)  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         echo "unknown option: $1" >&2; exit 2 ;;
    *)          TARGETS="$TARGETS $1" ;;
  esac
  shift
done

[ -n "$TARGETS" ] || TARGETS=".claude/agents"

# The allowed keys. A key missing from here is silently ignored by the reader, so a
# typo in a key name disables the option without a word.
KEYS="name description tools disallowedTools model permissionMode maxTurns skills mcpServers hooks memory background effort isolation color initialPrompt"

VAL_model="sonnet opus haiku fable inherit"
VAL_effort="low medium high xhigh max"
VAL_permissionMode="default acceptEdits auto dontAsk bypassPermissions plan manual"
VAL_memory="user project local"
VAL_background="true false"
VAL_isolation="worktree"
VAL_color="red blue green yellow purple orange pink cyan"

BUFFER="$(mktemp)"
NAMES="$(mktemp)"
trap 'rm -f "$BUFFER" "$NAMES"' EXIT

note() { # <status> <file> <key> <finding>
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$BUFFER"
}

in_list() { # <value> <list>
  for v in $2; do [ "$1" = "$v" ] && return 0; done
  return 1
}

# The frontmatter, between the first --- and the next one. Nothing else counts.
frontmatter() { # <file>
  awk 'NR==1 && $0!="---" { exit } NR==1 { inside=1; next } inside && $0=="---" { exit } inside' "$1"
}

value_of() { # <frontmatter> <key>
  sed -n "s/^$2:[[:space:]]*//p" <<<"$1" | sed -n '1p' | sed -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}

check_file() { # <file>
  f="$1"
  base="$(basename "$f" .md)"
  fm="$(frontmatter "$f")"

  if [ -z "$fm" ]; then
    note FALSE "$f" frontmatter "no frontmatter, the file is read as documentation and never as an agent"
    return 0
  fi

  name="$(value_of "$fm" name)"
  desc="$(value_of "$fm" description)"

  # --- the four ways of vanishing silently ---
  if [ -z "$name" ]; then
    note FALSE "$f" name "name key missing, the file is ignored without a message"
  else
    case "$name" in
      *:*)  note FALSE "$f" name "name contains a colon, the file is rejected at load" ;;
      -*)   note FALSE "$f" name "name starts with a dash, the file is rejected at load" ;;
      *)
        if grep -qE '^[a-z][a-z0-9-]*$' <<<"$name"; then
          note TRUE "$f" name "$name"
        else
          note FALSE "$f" name "\"$name\" breaks the convention, lowercase and dashes only"
        fi
        # The name rules, not the file. Two files in the same directory with the same
        # name, and only one loads, with nothing saying which.
        printf '%s\t%s\n' "$(dirname "$f")/$name" "$f" >> "$NAMES"
        [ "$name" = "$base" ] || note UNVERIFIABLE "$f" name "name \"$name\" and file \"$base.md\" differ, legal but confusing to read"
        ;;
    esac
  fi

  if [ -z "$desc" ]; then
    note FALSE "$f" description "description key missing, the file is ignored without a message"
  elif [ "${#desc}" -lt 40 ]; then
    note FALSE "$f" description "${#desc} characters, too short for automatic delegation to trigger"
  else
    note TRUE "$f" description "${#desc} characters"
  fi

  # --- enumerations, a value outside the list is ignored ---
  for key in model effort permissionMode memory background isolation color; do
    val="$(value_of "$fm" "$key")"
    [ -n "$val" ] || continue
    eval "list=\$VAL_$key"
    if in_list "$val" "$list"; then
      note TRUE "$f" "$key" "$val"
    elif [ "$key" = "model" ]; then
      # A full identifier is allowed besides the aliases.
      if grep -qE '^claude-[a-z0-9.-]+$' <<<"$val"; then
        note TRUE "$f" model "$val, full identifier"
      else
        note FALSE "$f" model "\"$val\" not in the list. Allowed: $list, or a claude-* identifier"
      fi
    else
      note FALSE "$f" "$key" "\"$val\" not in the list. Allowed: $list"
    fi
  done

  val="$(value_of "$fm" maxTurns)"
  if [ -n "$val" ]; then
    if grep -qE '^[1-9][0-9]*$' <<<"$val"; then
      note TRUE "$f" maxTurns "$val"
    else
      note FALSE "$f" maxTurns "\"$val\" is not a positive integer"
    fi
  fi

  # --- unknown keys, silently ignored ---
  printf '%s\n' "$fm" | grep -oE '^[A-Za-z][A-Za-z0-9_-]*:' | sed 's/:$//' | while IFS= read -r key; do
    in_list "$key" "$KEYS" || note FALSE "$f" "$key" "unknown key, silently ignored. Typo?"
  done
}

# --- sweep ----------------------------------------------------------------

for target in $TARGETS; do
  if [ -f "$target" ]; then
    check_file "$target"
  elif [ -d "$target" ]; then
    found=0
    for f in $(find "$target" -name '*.md' -type f 2>/dev/null | sort); do
      found=1
      check_file "$f"
    done
    [ "$found" -eq 1 ] || echo "no .md file in $target" >&2
  else
    echo "target not found: $target" >&2
    exit 2
  fi
done

# Duplicate names, once everything is read.
if [ -s "$NAMES" ]; then
  # split with a single space applies awk's default splitting, which trims leading
  # blanks. So we count files, not fields plus one.
  sort "$NAMES" | awk -F'\t' '
    { n[$1] = n[$1] " " $2 }
    END {
      for (k in n) {
        c = split(n[k], a, " ")
        nm = k; sub(/.*\//, "", nm)
        if (c > 1) printf "FALSE\t%s\tname\tname \"%s\" carried by %d files of the same directory, only one loads and nothing says which\n", a[1], nm, c
      }
    }' >> "$BUFFER"
fi

# --- output -------------------------------------------------------------------

TOTAL="$(wc -l < "$BUFFER" | tr -d ' ')"
NB_FALSE="$(grep -c '^FALSE	' "$BUFFER" || true)"
NB_UNV="$(grep -c '^UNVERIFIABLE	' "$BUFFER" || true)"

if [ "$FORMAT" = "md" ]; then
  echo "| Status | File | Key | Finding |"
  echo "|---|---|---|---|"
  awk -F'\t' '{printf "| %s | `%s` | `%s` | %s |\n", $1, $2, $3, $4}' "$BUFFER"
  echo
  echo "$TOTAL check(s), $NB_FALSE failed, $NB_UNV to look at."
else
  printf 'STATUS\tFILE\tKEY\tFINDING\n'
  cat "$BUFFER"
  printf -- '---\n%s check(s), %s failed, %s to look at.\n' "$TOTAL" "$NB_FALSE" "$NB_UNV"
fi

[ "$NB_FALSE" -eq 0 ] || exit 1
exit 0
