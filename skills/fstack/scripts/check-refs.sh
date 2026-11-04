#!/usr/bin/env bash
#
# check-refs.sh: extracts the paths, commands and globs cited in a markdown instructions
# file, and tests whether the repo confirms them.
#
# The script does not judge what a rule says, it checks its references. This is the
# mechanical part of phase 2 of the markdown audit. Everything else, conventions and
# compliance rates, is counted by hand.
#
# Three verdicts, never two for the same reference:
#   TRUE          the repo confirms it
#   FALSE         the repo contradicts it, the proof is in the PROOF column
#   UNVERIFIABLE  nothing to decide on. Not a failure, and it changes nothing
#
# Usage:
#   bash check-refs.sh [--format=tsv|--format=md] [--root <dir>] <file.md> [other.md ...]
#
# Exits 1 if at least one FALSE remains, 0 otherwise.
#
set -euf

FORMAT="tsv"
ROOT="."
FILES=""

while [ $# -gt 0 ]; do
  case "$1" in
    --format=*) FORMAT="${1#--format=}" ;;
    --root)   shift; ROOT="${1:-.}" ;;
    -h|--help)  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         echo "unknown option: $1" >&2; exit 2 ;;
    *)          FILES="$FILES $1" ;;
  esac
  shift
done
# A trailing slash would double the separator in glob patterns: p6//src/*.ts.
ROOT="${ROOT%/}"
[ -n "$ROOT" ] || ROOT=/

[ -n "$FILES" ] || { echo "Usage: bash check-refs.sh [--format=md] <file.md> [...]" >&2; exit 2; }
[ -d "$ROOT" ]   || { echo "root not found: $ROOT" >&2; exit 2; }

# A kept reference. Columns are tab-separated, and everything goes to standard output:
# the read loops run in subshells, an accumulated variable would not survive there.
note() { # <status> <type> <line> <value> <proof>
  printf '%s\t%s\tL%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"
}

# A token with a hole cannot be checked: template, variable, shortened example.
is_template() { # <token>
  case "$1" in
    *'<'*|*'>'*|*'{{'*|*'$'*|*'...'*|*'…'*) return 0 ;;
    http://*|https://*|mailto:*|'#'*)       return 0 ;;
  esac
  # /clear, /compact, /plan: a slash command is not an absolute path.
  grep -qE '^/[a-z][a-z0-9-]*$' <<<"$1" && return 0
  case "$1" in
    *) return 1 ;;
  esac
}

# --- paths -----------------------------------------------------------------

looks_like_path() { # <token>
  case "$1" in
    */*)                                             return 0 ;;
    Makefile|Dockerfile|justfile|Procfile|LICENSE)   return 0 ;;
    *.*) grep -qE '^[A-Za-z0-9_.-]+\.[A-Za-z0-9]{1,6}$' <<<"$1" && return 0 ;;
  esac
  return 1
}

find_elsewhere() { # <name>
  find "$ROOT" -name "$1" -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | sed -n '1p'
}

check_path() { # <line> <token>
  pth="${2%/}"

  if [ -e "$ROOT/$pth" ]; then
    note TRUE path "$1" "$2" "exists"
    return 0
  fi

  base="$(basename "$pth")"
  elsewhere="$(find_elsewhere "$base")"

  case "$pth" in
    */*)
      # A multi-segment path is read from the root. If it does not resolve, it is
      # false, even if the file exists elsewhere. We give the location to help the fix.
      if [ -n "$elsewhere" ]; then
        note FALSE path "$1" "$2" "missing, but a $base exists in ${elsewhere#"$ROOT"/}"
      else
        note FALSE path "$1" "$2" "no file at this path"
      fi
      ;;
    *)
      # A bare name, without a folder, names a file rather than giving its path.
      # Finding it anywhere is enough, otherwise the reference points at nothing.
      if [ -n "$elsewhere" ]; then
        note TRUE path "$1" "$2" "exists in ${elsewhere#"$ROOT"/}"
      else
        note FALSE path "$1" "$2" "no file of this name in the repo"
      fi
      ;;
  esac
}

# --- globs -------------------------------------------------------------------

check_glob() { # <line> <token>
  # find treats * as any run of characters, separator included,
  # so ** folds into * without changing the result.
  pattern="$(printf '%s' "$2" | sed 's|\*\*|*|g')"
  # find returns paths that start with $ROOT: the pattern anchors there, otherwise --root <dir>
  # never matches anything.
  case "$pattern" in /*) pattern="${pattern#/}" ;; ./*) pattern="${pattern#./}" ;; esac
  pattern="$ROOT/$pattern"
  # nb, not n: n is the line counter of read_file(), overwriting it shifts the whole report.
  nb="$(find "$ROOT" -path "$pattern" -not -path '*/node_modules/*' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$nb" -gt 0 ]; then
    note TRUE glob "$1" "$2" "$nb file(s)"
  else
    note FALSE glob "$1" "$2" "matches no file"
  fi
}

# --- commands ---------------------------------------------------------------

npm_script() { # <name>
  [ -f "$ROOT/package.json" ] || return 1
  grep -qE "\"$1\"[[:space:]]*:" "$ROOT/package.json"
}

make_target() { # <name>
  [ -f "$ROOT/Makefile" ] || [ -f "$ROOT/makefile" ] || return 1
  grep -hqE "^$1[[:space:]]*:" "$ROOT/Makefile" "$ROOT/makefile" 2>/dev/null
}

check_command() { # <line> <full command>
  set -- "$1" $2
  ln="$1"; shift
  tool="${1:-}"; sub="${2:-}"; third="${3:-}"

  case "$tool" in
    npm|pnpm|yarn|bun)
      target="$sub"
      [ "$sub" = "run" ] && target="$third"
      case "$target" in ""|-*) return 0 ;; esac
      case "$target" in
        install|ci|test|start|init|create|publish|audit) : ;;
      esac
      if [ ! -f "$ROOT/package.json" ]; then
        note FALSE command "$ln" "$tool $sub $third" "no package.json at the root"
      elif npm_script "$target"; then
        note TRUE command "$ln" "$tool $sub $third" "script \"$target\" in package.json"
      else
        note FALSE command "$ln" "$tool $sub $third" "no script \"$target\" in package.json"
      fi
      ;;
    make)
      case "$sub" in ""|-*) return 0 ;; esac
      if make_target "$sub"; then
        note TRUE command "$ln" "make $sub" "target \"$sub\" in the Makefile"
      elif [ -f "$ROOT/Makefile" ] || [ -f "$ROOT/makefile" ]; then
        note FALSE command "$ln" "make $sub" "no target \"$sub\" in the Makefile"
      else
        note FALSE command "$ln" "make $sub" "no Makefile at the root"
      fi
      ;;
    just)
      case "$sub" in ""|-*) return 0 ;; esac
      if [ -f "$ROOT/justfile" ] && grep -qE "^${sub}[[:space:]]*:" "$ROOT/justfile"; then
        note TRUE command "$ln" "just $sub" "recipe \"$sub\" in the justfile"
      elif [ -f "$ROOT/justfile" ]; then
        note FALSE command "$ln" "just $sub" "no recipe \"$sub\" in the justfile"
      else
        note FALSE command "$ln" "just $sub" "no justfile at the root"
      fi
      ;;
    poetry|uv|pipenv|hatch|tox|pytest|ruff|mypy)
      if [ -f "$ROOT/pyproject.toml" ] || [ -f "$ROOT/setup.py" ] || [ -f "$ROOT/tox.ini" ]; then
        note TRUE command "$ln" "$tool $sub" "python project, manifest present"
      else
        note FALSE command "$ln" "$tool $sub" "neither pyproject.toml nor setup.py at the root"
      fi
      ;;
    cargo)
      if [ -f "$ROOT/Cargo.toml" ]; then
        note TRUE command "$ln" "cargo $sub" "Cargo.toml present"
      else
        note FALSE command "$ln" "cargo $sub" "no Cargo.toml at the root"
      fi
      ;;
    go)
      if [ -f "$ROOT/go.mod" ]; then
        note TRUE command "$ln" "go $sub" "go.mod present"
      else
        note FALSE command "$ln" "go $sub" "no go.mod at the root"
      fi
      ;;
    bash|sh|python|python3|node)
      case "$sub" in ""|-*) return 0 ;; esac
      looks_like_path "$sub" && check_path "$ln" "$sub"
      ;;
    *)
      # A binary missing from this machine proves nothing about the project.
      case "$tool" in ""|-*|*=*) return 0 ;; esac
      if command -v "$tool" >/dev/null 2>&1; then
        note TRUE command "$ln" "$tool $sub" "$tool is installed here"
      else
        note UNVERIFIABLE command "$ln" "$tool $sub" "$tool missing from this machine"
      fi
      ;;
  esac
}

# --- reading the markdown -----------------------------------------------------

is_command() { # <token>
  grep -qE '^(npm|pnpm|yarn|bun|make|just|poetry|uv|pipenv|hatch|tox|pytest|ruff|mypy|cargo|go|bash|sh|python3?|node|docker|git|gh|terraform|kubectl) ' <<<"$1"
}

read_file() { # <file>
  file="$1"
  fence=0
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    case "$line" in
      '```'*|'~~~'*) fence=$((1 - fence)); continue ;;
    esac

    if [ "$fence" -eq 1 ]; then
      # In a code block, the first command of the line, comments removed.
      cmd="$(printf '%s' "$line" | sed -e 's/[[:space:]]*#.*$//' -e 's/^[[:space:]]*//')"
      is_command "$cmd" && check_command "$n" "$cmd"
      continue
    fi

    # An @path import loads the file at startup, recursively up to four hops. Between
    # backticks it becomes text again, so we look for it before splitting the line into
    # tokens, and we skip the lines where it is protected.
    imp="$(printf '%s\n' "$line" | sed 's/`[^`]*`//g' | grep -oE '(^|[[:space:]])@[^[:space:]`)]+' 2>/dev/null | sed 's/^[[:space:]]*//' || true)"
    if [ -n "$imp" ]; then
      printf '%s\n' "$imp" | while IFS= read -r target; do
        target="${target#@}"
        [ -n "$target" ] || continue
        case "$target" in *@*) continue ;; esac   # an email address is not an import
        reel="$target"
        case "$target" in "~/"*) reel="$HOME/${target#~/}" ;; esac
        if [ -e "$ROOT/$reel" ] || [ -e "$reel" ]; then
          note TRUE import "$n" "@$target" "resolves, and its content counts toward the root budget"
        else
          note FALSE import "$n" "@$target" "dead import, the file does not exist and nothing reports it"
        fi
      done
    fi

    # Outside a block: spans between backticks, and the targets of markdown links.
    tokens="$(printf '%s\n' "$line" \
      | grep -oE '`[^`]+`|\]\([^)]+\)' 2>/dev/null \
      | sed -e 's/^`//' -e 's/`$//' -e 's/^](\(.*\))$/\1/' || true)"

    [ -n "$tokens" ] || continue
    printf '%s\n' "$tokens" | while IFS= read -r token; do
      [ -n "$token" ] || continue
      is_template "$token" && continue
      if is_command "$token"; then
        check_command "$n" "$token"
      else
        case "$token" in *' '*) continue ;; esac
        case "$token" in
          *'*'*) check_glob "$n" "$token" ;;
          *) looks_like_path "$token" && check_path "$n" "$token" ;;
        esac
      fi
    done
  done < "$file"
}

# Each file pours its lines into a buffer, prefixed with its name. Deduplication is on
# the reference: a path cited ten times earns only one report line.
BUFFER="$(mktemp)"
trap 'rm -f "$BUFFER"' EXIT

for f in $FILES; do
  [ -f "$f" ] || { echo "file not found: $f" >&2; exit 2; }
  read_file "$f" | grep -E '^(TRUE|FALSE|UNVERIFIABLE)	' | sort -u -t'	' -k4,4 \
    | sed "s|^|$f	|" >> "$BUFFER" || true
done

# --- output -------------------------------------------------------------------

TOTAL="$(wc -l < "$BUFFER" | tr -d ' ')"
NB_FALSE="$(grep -c '	FALSE	' "$BUFFER" || true)"
NB_UNV="$(grep -c '	UNVERIFIABLE	' "$BUFFER" || true)"

if [ "$FORMAT" = "md" ]; then
  echo "| Status | File | Line | Reference | Proof |"
  echo "|---|---|---|---|---|"
  awk -F'	' '{printf "| %s | `%s` | %s | `%s` | %s |\n", $2, $1, $4, $5, $6}' "$BUFFER"
  echo
  echo "$TOTAL reference(s), $NB_FALSE false, $NB_UNV unverifiable."
else
  printf 'STATUS\tFILE\tTYPE\tLINE\tREFERENCE\tPROOF\n'
  awk -F'	' '{printf "%s\t%s\t%s\t%s\t%s\t%s\n", $2, $1, $3, $4, $5, $6}' "$BUFFER"
  printf -- '---\n%s reference(s), %s false, %s unverifiable.\n' "$TOTAL" "$NB_FALSE" "$NB_UNV"
fi

[ "$NB_FALSE" -eq 0 ] || exit 1
exit 0
