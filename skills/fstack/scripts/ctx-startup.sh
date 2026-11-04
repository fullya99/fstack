#!/usr/bin/env bash
#
# ctx-startup.sh: SessionStart hook of the fstack plugin, debrief marker and restart prompts.
#
# Usage:
#   bash ctx-startup.sh                    at startup: prints fifteen lines at most
#   bash ctx-startup.sh --write-marker     at the end of a debrief: writes the marker
#   bash ctx-startup.sh --write-brief      reads a restart prompt on stdin and stores it
#   bash ctx-startup.sh --read-brief       prints the next prompt of the queue, with its freshness, and marks it played
#   bash ctx-startup.sh --list-briefs      shows the queue without playing anything
#   bash ctx-startup.sh --settle <entry>   marks an entry played without printing it
#   --plan <path>      with --write-brief: the execution prompt of this plan, stored next to the handover
#   --after <entry>    with --plan: this plan plays after that one
#   --name <entry>     with --read-brief: plays this entry instead of the next one
#   --root <path>      project to read, else $CLAUDE_PROJECT_DIR, else the current directory
#   --data <folder>    plugin data folder, else $CLAUDE_PLUGIN_DATA
#
# It never blocks a session: exit code 0 in all cases, read-only on the project.
# What Claude Code does with the output: the stdout text of a SessionStart hook enters
# Claude's context, which sees it and can relay it. Nothing is written on stderr.
#
# Silent when all is well: a line by default costs context at every startup, resume and
# compaction. Only the debrief marker always speaks, it is the continuity info.
# Without a convention block: silence if none of the three pillars exists, one line that
# proposes /fstack:upgrade if at least one does.
#
# Silent does not mean mute on failure: a hook that cannot run says so in one line, else a
# failure and a healthy project give the same empty output.
#
# The hook reads the event JSON on stdin, for its `source` field (startup, resume, clear,
# compact, fork). After a compaction, the body of an invoked skill comes back truncated to its
# first 5,000 tokens and a file read is only a summary (code.claude.com/docs/en/skills, section
# Skill content lifecycle, read on 2026-11-02): the hook reminds to reread the mode file.
#
# The marker: <data>/markers/<stable name>, `key=value` lines (commit, tree, dirty, date).
# The restart prompts: a queue in <data>/briefs/<stable name>/, described above brief_dir().
# An entry read by --read-brief becomes <entry>.played.md and the hook no longer announces it.
# The stable name is the project folder name, sanitized, plus a sum of its absolute path:
# no `/` and no space, and two clones with the same name do not mix.
# The CLAUDE_PLUGIN_* variables do not exist in the Bash tool: the debrief mode passes
# --data with the value the skill received by substitution.
#
# Old data is read as is and moved on first read: markers older than 1.0.0-rc.6 (temoins/ with
# arbre= and sale=), queues (relance/ with reprise.md and .joue.md), headers
# `<!-- relance ... ordre= empreinte= apres= -->`.
set -f
# Never any noise on stderr, even if a tool is missing from the PATH.
exec 2>/dev/null

case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
DIR="$(cd "$DIR" && pwd)"
OUTPUT=""
SOURCE=""
# Due dates: an open task whose due date falls within this many days, or is past.
DUE_HORIZON=3
# Old French fstack names, with word boundaries (fstack:expert is not one of them).
OLD_NAMES='(^|[^A-Za-z0-9_-])fstack:(init|planifier|relance|cloture|audit|migrer|chercheur|explorateur|controleur|developpeur|executant|relecteur)([^A-Za-z0-9_]|$)'

line() { # <text>: adds a line to the output
  OUTPUT="${OUTPUT}[fstack] $1
"
  return 0
}

# Stable project name for the marker.
project_name() { # <root>
  local base sum
  base="$(basename "$1" | tr -c 'A-Za-z0-9._-' '-')"
  sum="$(printf '%s' "$1" | cksum | cut -d' ' -f1)"
  printf '%s-%s\n' "$base" "$sum"
  return 0
}

# Fingerprint of the working tree: differs if a file moved since.
tree_fingerprint() { # <root>
  git -C "$1" status --porcelain 2>/dev/null | cksum | cut -d' ' -f1
  return 0
}

dirty_count() { # <root>: number of uncommitted files
  git -C "$1" status --porcelain 2>/dev/null | wc -l | tr -d ' '
  return 0
}

# Where a commit stands relative to HEAD: "same", "N" commits added since, or "absent".
commit_gap() { # <root> <sha>
  local root="$1" sha="$2" head n
  head="$(git -C "$root" rev-parse -q --verify HEAD 2>/dev/null || true)"
  [ -n "$head" ] || { printf 'absent\n'; return 0; }
  if [ "$head" = "$sha" ]; then
    printf 'same\n'
  elif git -C "$root" cat-file -e "$sha^{commit}" 2>/dev/null \
       && git -C "$root" merge-base --is-ancestor "$sha" "$head" 2>/dev/null; then
    n="$(git -C "$root" rev-list --count "$sha..$head" 2>/dev/null || true)"
    printf '%s\n' "${n:-several}"
  else
    printf 'absent\n'
  fi
  return 0
}

# --- data migration -----------------------------------------------------------------------

# Moves <src> to <dst> without losing anything: a missing <dst> takes the whole folder, else
# each entry moves unless it already exists there.
merge_dir() { # <src> <dst>
  local e n
  [ -d "$1" ] || return 0
  if [ ! -e "$2" ]; then
    mv -f "$1" "$2" 2>/dev/null
    return 0
  fi
  mkdir -p "$2" 2>/dev/null || return 0
  find "$1" -mindepth 1 -maxdepth 1 2>/dev/null | while IFS= read -r e; do
    n="${e##*/}"
    if [ -d "$e" ] && [ -d "$2/$n" ]; then
      merge_dir "$e" "$2/$n"
    elif [ ! -e "$2/$n" ]; then
      mv -f "$e" "$2/$n" 2>/dev/null
    fi
  done
  rmdir "$1" 2>/dev/null
  return 0
}

# Gives an old queue file its new name unless the new name is taken.
rename_entry() { # <folder> <old name> <new name>
  [ -f "$1/$2" ] && [ ! -e "$1/$3" ] && mv -f "$1/$2" "$1/$3" 2>/dev/null
  return 0
}

# Brings the plugin data of this project to the current names: temoins/ and relance/ become
# markers/ and briefs/, a lone <stable name>.md next to the queue folder becomes its handover,
# reprise.md becomes handover.md and .joue.md becomes .played.md.
migrate_data() { # <root> <data>
  local d f n
  merge_dir "$2/temoins" "$2/markers"
  merge_dir "$2/relance" "$2/briefs"
  d="$(brief_dir "$1" "$2")"
  if [ -f "$d.md" ] || [ -f "$d.joue.md" ] || [ -f "$d.played.md" ]; then
    mkdir -p "$d" 2>/dev/null || return 0
    rename_entry "$(dirname "$d")" "$(basename "$d").md" "$(basename "$d")/handover.md"
    rename_entry "$(dirname "$d")" "$(basename "$d").joue.md" "$(basename "$d")/handover.played.md"
    rename_entry "$(dirname "$d")" "$(basename "$d").played.md" "$(basename "$d")/handover.played.md"
  fi
  [ -d "$d" ] || return 0
  find "$d" -maxdepth 1 -type f -name '*.joue.md' 2>/dev/null | while IFS= read -r f; do
    n="${f##*/}"
    rename_entry "$d" "$n" "${n%.joue.md}.played.md"
  done
  rename_entry "$d" reprise.played.md handover.played.md
  rename_entry "$d" reprise.md handover.md
  return 0
}

# --- the debrief marker -------------------------------------------------------------------

write_marker() { # <root> <data>
  local root="$1" data="$2" dest commit
  if [ -z "$data" ]; then
    line "Debrief marker not written: CLAUDE_PLUGIN_DATA is missing. The debrief mode passes it with --data."
    return 0
  fi
  commit="$(git -C "$root" rev-parse -q --verify HEAD 2>/dev/null || true)"
  if [ -z "$commit" ]; then
    line "Debrief marker not written: no commit in this repository."
    return 0
  fi
  dest="$data/markers/$(project_name "$root")"
  if mkdir -p "$data/markers" 2>/dev/null \
     && printf 'commit=%s\ntree=%s\ndirty=%s\ndate=%s\n' "$commit" "$(tree_fingerprint "$root")" \
          "$(dirty_count "$root")" "$(ctx_today)" > "$dest" 2>/dev/null; then
    line "Debrief marker written: commit $(printf '%s' "$commit" | cut -c1-7)."
  else
    line "Debrief marker not written: $data/markers is not writable."
  fi
  return 0
}

# Returns 0 if a marker was read, 1 otherwise (to decide on the heuristic fallback).
read_marker() { # <root> <data>
  local root="$1" data="$2" f tc ta ts td c7 e
  [ -n "$data" ] || return 1
  f="$data/markers/$(project_name "$root")"
  [ -f "$f" ] || return 1
  tc="$(sed -n 's/^commit=//p' "$f" | sed -n '1p')"
  ta="$(sed -n -E 's/^(tree|arbre)=//p' "$f" | sed -n '1p')"
  ts="$(sed -n -E 's/^(dirty|sale)=//p' "$f" | sed -n '1p')"
  td="$(sed -n 's/^date=//p' "$f" | sed -n '1p')"
  [ -n "$tc" ] || return 1
  c7="$(printf '%s' "$tc" | cut -c1-7)"
  e="$(commit_gap "$root" "$tc")"
  case "$e" in
    same)
      if [ -n "$ta" ] && [ "$ta" != "$(tree_fingerprint "$root")" ]; then
        line "Last debrief on $td at commit $c7, the same commit, but files have changed since."
      elif [ -n "$ts" ] && [ "$ts" -gt 0 ] 2>/dev/null; then
        line "The session resumes from the last debrief (on $td, commit $c7), which left $ts uncommitted file(s)."
      else
        line "The session resumes cleanly from the last debrief (on $td, commit $c7)."
      fi
      ;;
    absent) line "Last debrief on $td at commit $c7, absent from this branch (rebase or other branch)." ;;
    *)      line "Last debrief on $td at commit $c7, $e commit(s) added since." ;;
  esac
  return 0
}

# Fallback without a marker: many uncommitted files and no recent log entry.
debrief_forgotten() { # <root>
  local root="$1" n dj d
  n="$(dirty_count "$root")"
  [ "${n:-0}" -ge 5 ] 2>/dev/null || return 0
  [ -f "$root/CHANGELOG.md" ] || return 0
  # The most recent date among the headings, whatever the log format or order:
  # `## 2026-11-02`, `## [1.2.0] - 2026-11-02`, `[2026-11-02] [FIX]`, oldest first or last.
  dj="$(grep -E '^(#|\[)' "$root/CHANGELOG.md" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | sed -n '$p')"
  d="$(ctx_days_since "$dj")"
  if [ -z "$d" ] || [ "$d" -gt 1 ]; then
    line "$n uncommitted file(s) and no recent CHANGELOG entry: a debrief may have been forgotten."
  fi
  return 0
}

# Due dates in TODOS.md: `- [ ] (due YYYY-MM-DD) text`, past or near. French `échéance` and
# `echeance` are read too.
# One `date` per line and 200 lines at most: the hook has 10 seconds in all, and a huge
# TODOS.md is exactly the case it must be able to report.
due_dates() { # <root>
  local f="$1/TODOS.md" l e0 eb d txt n=0 total dues="" re c
  [ -f "$f" ] || return 0
  e0="$(ctx_epoch "$(ctx_today)")"
  [ -n "$e0" ] || return 0
  re='[^[:alnum:]](échéance|echeance|due) ([0-9]{4}-[0-9]{2}-[0-9]{2})'
  total="$(grep -cE '^[[:space:]]*- \[ \] .*[^[:alnum:]](échéance|echeance|due) [0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" 2>/dev/null)"
  [ "${total:-0}" -gt 0 ] 2>/dev/null || return 0
  while IFS= read -r l; do
    [[ $l =~ $re ]] || continue
    eb="$(ctx_epoch "${BASH_REMATCH[2]}")"
    [ -n "$eb" ] || continue
    d="$(ctx_days_between "$e0" "$eb")"
    [ "$d" -ge $(( -DUE_HORIZON )) ] || continue
    n=$((n + 1))
    txt="${l#*- \[ \] }"
    txt="${txt:0:140}"
    if [ "$d" -gt 0 ]; then
      dues="${dues}${d}	  overdue by $d d: $txt
"
    elif [ "$d" -eq 0 ]; then
      dues="${dues}0	  today: $txt
"
    else
      dues="${dues}${d}	  in $(( -d )) d: $txt
"
    fi
  done <<END_LIST
$(grep -E '^[[:space:]]*- \[ \] .*[^[:alnum:]](échéance|echeance|due) [0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" 2>/dev/null | sed -n '1,200p')
END_LIST
  [ "$n" -gt 0 ] || return 0
  c=""
  [ "$total" -gt 200 ] && c=" (first 200 read, $total in all)"
  line "$n due date(s) past or within $DUE_HORIZON days in TODOS.md$c. To settle: do it, postpone with a new date, or archive."
  # Most overdue first: the four-line truncation must not hide a delay.
  while IFS= read -r c; do
    [ -n "$c" ] && line "${c#*	}"
  done <<END_LIST
$(printf '%s' "$dues" | sort -t '	' -k1,1nr | sed -n '1,4p')
END_LIST
  return 0
}

# --- the brief queue ----------------------------------------------------------------------
# One folder per project, <data>/briefs/<stable name>/, one entry per file:
#   handover.md      the prompt of the debrief (or of /fstack:brief prompt), only one, rewritten
#   plan-<slug>.md   the execution prompt of a plan, one per plan, stored by the plan mode
# A played entry becomes <entry>.played.md. First line of each entry:
#   <!-- brief commit=<sha> date=<YYYY-MM-DD> order=<n> [plan=<path> fingerprint=<cksum>] [after=<entry>] -->
# Play order: the handover first, it describes the freshest state and knows what waits.
# Then the plans in writing order, a plan whose dependency still waits passes its turn.

brief_dir() { # <root> <data>
  printf '%s/briefs/%s\n' "$2" "$(project_name "$1")"
  return 0
}

# Value of a field of the first line, under its current key, else its old French key.
head_field() { # <file> <key> [<old key>]
  local v
  v="$(sed -n '1p' "$1" | sed -n "s/.* $2=\([^ ]*\).*/\1/p")"
  if [ -z "$v" ] && [ -n "${3:-}" ]; then
    v="$(sed -n '1p' "$1" | sed -n "s/.* $3=\([^ ]*\).*/\1/p")"
  fi
  printf '%s\n' "$v"
  return 0
}

head_order()       { head_field "$1" order ordre; return 0; }
head_fingerprint() { head_field "$1" fingerprint empreinte; return 0; }
head_plan()        { head_field "$1" plan; return 0; }
head_after() { # <file>: the old `reprise` entry is now `handover`
  local a
  a="$(head_field "$1" after apres)"
  [ "$a" = reprise ] && a=handover
  printf '%s\n' "$a"
  return 0
}

file_fingerprint() { # <file>
  cksum < "$1" | cut -d' ' -f1
  return 0
}

sanitize() { # <text>: nothing but letters, digits, dot, dash and underscore
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'
  return 0
}

# The name of an entry from what is typed (--name, --after): handover, plan-x, x or plans/x.md.
# `reprise` is still accepted for `handover`. Always sanitized: it enters a file name and the header.
entry_name() { # <input>
  local s="$1"
  case "$s" in
    */*|*.md) s="${s##*/}"; s="plan-${s%.md}" ;;
    reprise) s=handover ;;
    handover|plan-*) ;;
    *) s="plan-$s" ;;
  esac
  printf '%s\n' "$(sanitize "$s")"
  return 0
}

# The entry name of a stored plan: plan-<file name>, never `handover`. If this name is already
# taken by another plan (same file name, other folder), the whole path tells them apart.
plan_name() { # <queue folder> <plan path relative to the project>
  local n other f
  n="plan-$(sanitize "$(basename "$2" .md)")"
  for f in "$1/$n.md" "$1/$n.played.md"; do
    [ -f "$f" ] || continue
    other="$(head_plan "$f")"
    if [ -n "$other" ] && [ "$other" != "$2" ]; then
      n="plan-$(sanitize "${2%.md}")"
      break
    fi
  done
  printf '%s\n' "$n"
  return 0
}

# The waiting entries, one per line, in play order (the handover first).
waiting() { # <folder>
  local f n o
  [ -d "$1" ] || return 0
  find "$1" -maxdepth 1 -type f -name '*.md' ! -name '*.played.md' ! -name '*.joue.md' 2>/dev/null | while IFS= read -r f; do
    n="${f##*/}"
    n="${n%.md}"
    o="$(head_order "$f")"
    [ "$n" = handover ] && o=0
    case "$o" in ''|*[!0-9]*) o=0 ;; esac
    printf '%s\t%s\n' "$o" "$n"
  done | sort -t "$(printf '\t')" -k1,1n -k2,2 | cut -f2
  return 0
}

# The dependency of an entry, if it still waits. Empty otherwise.
waiting_dependency() { # <folder> <entry>
  local a
  a="$(head_after "$1/$2.md")"
  if [ -n "$a" ] && [ -f "$1/$a.md" ]; then printf '%s\n' "$a"; fi
  return 0
}

# The next entry to play: the first whose dependency no longer waits, else the first.
next_entry() { # <folder>
  local list n
  list="$(waiting "$1")"
  [ -n "$list" ] || return 0
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    if [ -z "$(waiting_dependency "$1" "$n")" ]; then
      printf '%s\n' "$n"
      return 0
    fi
  done <<END_LIST
$list
END_LIST
  printf '%s\n' "$list" | sed -n '1p'
  return 0
}

write_brief() { # <root> <data> <plan> <after>: the prompt arrives on stdin
  local root="$1" data="$2" plan="$3" after="$4" dir name dest commit content order header n f
  content="$(head -c 20001)"
  if [ "${#content}" -gt 20000 ]; then
    content="${content:0:20000}"
    line "Restart prompt truncated to 20,000 characters: shorten it, the end is lost."
  fi
  if [ -z "$data" ]; then
    line "Restart prompt not stored: CLAUDE_PLUGIN_DATA is missing. It stays in the chat."
    return 0
  fi
  if [ -z "$(printf '%s' "$content" | tr -d '[:space:]')" ]; then
    line "Restart prompt not stored: nothing received on stdin."
    return 0
  fi
  name=handover
  if [ -n "$plan" ]; then
    case "$plan" in "$root"/*) plan="${plan#"$root"/}" ;; esac
    plan="${plan#./}"
    case "$plan" in
      /*|*..*|*[!A-Za-z0-9._/-]*)
        line "Plan prompt not stored: the path $plan must be relative to the project, with no space or '..'."
        return 0
        ;;
    esac
    if [ ! -f "$root/$plan" ]; then
      line "Plan prompt not stored: $plan not found in the project. Write the plan before its prompt."
      return 0
    fi
  fi
  dir="$(brief_dir "$root" "$data")"
  [ -n "$plan" ] && name="$(plan_name "$dir" "$plan")"
  dest="$dir/$name.md"
  if ! mkdir -p "$dir" 2>/dev/null; then
    line "Restart prompt not stored: $dir is not writable."
    return 0
  fi
  # A rewritten plan keeps its place in the queue, a new one takes the next.
  order=""
  [ -f "$dest" ] && order="$(head_order "$dest")"
  case "$order" in ''|*[!0-9]*)
    order="$(find "$dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null | while IFS= read -r f; do head_order "$f"; done \
             | grep -E '^[0-9]+$' | sort -n | sed -n '$p')"
    order=$(( ${order:-0} + 1 ))
    ;;
  esac
  commit="$(git -C "$root" rev-parse -q --verify HEAD 2>/dev/null || true)"
  header="<!-- brief commit=${commit:-none} date=$(ctx_today) order=$order"
  [ -n "$plan" ] && header="$header plan=$plan fingerprint=$(file_fingerprint "$root/$plan")"
  [ -n "$plan" ] && [ -n "$after" ] && header="$header after=$(entry_name "$after")"
  header="$header -->"
  if printf '%s\n%s\n' "$header" "$content" > "$dest" 2>/dev/null; then
    rm -f "$dir/$name.played.md" 2>/dev/null
    if [ -n "$plan" ]; then
      n="$(waiting "$dir" | wc -l | tr -d ' ')"
      line "Execution prompt of $plan stored in the brief queue as $name ($n waiting). After the context restart: /fstack:brief open."
    else
      line "Restart prompt stored for the next session: $dest"
    fi
  else
    line "Restart prompt not stored: $dir is not writable."
  fi
  return 0
}

# Freshness of a stored prompt, in one sentence.
brief_freshness() { # <root> <file>
  local root="$1" f="$2" header pc pd pp pe e d c7 phrase
  header="$(sed -n '1p' "$f")"
  # At least seven hexadecimal characters: `commit=none` would not match, nor would a word.
  pc="$(sed -n 's/.*commit=\([0-9a-f]\{7,\}\).*/\1/p' <<<"$header")"
  pd="$(sed -n 's/.*date=\([0-9-]*\).*/\1/p' <<<"$header")"
  c7="$(printf '%s' "$pc" | cut -c1-7)"
  if [ -z "$pc" ]; then
    phrase="produced on ${pd:-?}, no commit"
  else
    e="$(commit_gap "$root" "$pc")"
    case "$e" in
      same)   phrase="produced on $pd at commit $c7, nothing committed since" ;;
      absent) phrase="produced on $pd at commit $c7, absent from this branch" ;;
      *)      phrase="produced on $pd at commit $c7, $e commit(s) since" ;;
    esac
  fi
  d="$(ctx_days_since "$pd")"
  if [ -n "$d" ] && [ "$d" -gt 14 ]; then
    phrase="$phrase, $d days ago, possibly stale"
  fi
  # The plan is not committed yet when its prompt is stored: the commit does not cover it.
  pp="$(head_plan "$f")"
  pe="$(head_fingerprint "$f")"
  if [ -n "$pp" ]; then
    if [ ! -f "$root/$pp" ]; then
      phrase="$phrase, plan not found: $pp"
    elif [ -n "$pe" ] && [ "$pe" != "$(file_fingerprint "$root/$pp")" ]; then
      phrase="$phrase, $pp modified since"
    fi
  fi
  printf '%s\n' "$phrase"
  return 0
}

announce_briefs() { # <root> <data>
  local dir list n name dep i=0 next
  [ -n "$2" ] || return 0
  dir="$(brief_dir "$1" "$2")"
  list="$(waiting "$dir")"
  [ -n "$list" ] || return 0
  n="$(printf '%s\n' "$list" | wc -l | tr -d ' ')"
  if [ "$n" -eq 1 ]; then
    line "One restart prompt is waiting ($list, $(brief_freshness "$1" "$dir/$list.md")). /fstack:brief open to resume it."
    return 0
  fi
  next="$(next_entry "$dir")"
  line "$n restart prompts are waiting. /fstack:brief open plays $next, /fstack:brief open <name> picks one:"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    i=$((i + 1))
    [ "$i" -le 4 ] || continue
    dep="$(waiting_dependency "$dir" "$name")"
    line "  $name: $(brief_freshness "$1" "$dir/$name.md")${dep:+, after $dep}"
  done <<END_LIST
$list
END_LIST
  [ "$n" -gt 4 ] && line "  and $((n - 4)) more"
  return 0
}

# Marks an entry played without printing it: a plan run some other way than by the queue.
settle_brief() { # <root> <data> <entry>
  local root="$1" data="$2" name dir
  [ -n "$data" ] || { line "Nothing to settle: CLAUDE_PLUGIN_DATA is missing."; return 0; }
  [ -n "$3" ] || { line "--settle expects an entry name."; return 0; }
  dir="$(brief_dir "$root" "$data")"
  name="$(entry_name "$3")"
  if [ -f "$dir/$name.md" ] && mv -f "$dir/$name.md" "$dir/$name.played.md" 2>/dev/null; then
    line "Entry $name settled: marked played without being read."
  else
    line "No waiting entry $name."
  fi
  return 0
}

# Prints the prompt on stdout, as is, then marks it played.
read_brief() { # <root> <data> [entry]
  local root="$1" data="$2" target="$3" dir name f p dep rest last
  [ -n "$data" ] || { line "No restart prompt: CLAUDE_PLUGIN_DATA is missing."; return 0; }
  dir="$(brief_dir "$root" "$data")"
  if [ -n "$target" ]; then
    name="$(entry_name "$target")"
    if [ ! -f "$dir/$name.md" ]; then
      if [ -f "$dir/$name.played.md" ]; then
        line "Prompt $name was already played ($(brief_freshness "$root" "$dir/$name.played.md")). It is in $dir/$name.played.md."
      else
        line "No waiting prompt $name."
      fi
      rest="$(waiting "$dir" | tr '\n' ' ' | sed 's/ $//')"
      [ -n "$rest" ] && line "Waiting: $rest."
      return 0
    fi
  else
    name="$(next_entry "$dir")"
    if [ -z "$name" ]; then
      last="$(find "$dir" -maxdepth 1 -type f -name '*.played.md' 2>/dev/null | while IFS= read -r f; do
                printf '%s\t%s\n' "$(head_order "$f")" "$f"; done | sort -n | sed -n '$p' | cut -f2)"
      if [ -n "$last" ]; then
        line "The last restart prompt was already played ($(brief_freshness "$root" "$last")). It is in $last."
      else
        line "No restart prompt stored for this project."
      fi
      return 0
    fi
  fi
  f="$dir/$name.md"
  p="$dir/$name.played.md"
  dep="$(waiting_dependency "$dir" "$name")"
  [ -n "$dep" ] && line "Warning: $name normally plays after $dep, which is still waiting."
  line "Restart prompt $name $(brief_freshness "$root" "$f")."
  rest="$(waiting "$dir" | grep -vxF "$name" | tr '\n' ' ' | sed 's/ $//')"
  if [ -n "$rest" ]; then
    line "Still waiting: $rest. Each plan plays in its own fresh session."
  fi
  OUTPUT="${OUTPUT}$(sed '1d' "$f")
"
  mv -f "$f" "$p" 2>/dev/null
  return 0
}

main() {
  local mode=hook root="" data="${CLAUDE_PLUGIN_DATA:-}" base top v version_line input
  local out rc nb nw handover d date_r msgs c l pillars=0 plan="" after="" target=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --write-marker)  mode=write_marker; shift ;;
      --write-brief)   mode=write_brief; shift ;;
      --read-brief)    mode=read_brief; shift ;;
      --list-briefs)   mode=list_briefs; shift ;;
      --settle)        mode=settle; target="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      --plan)          plan="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      --after)         after="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      --name)          target="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      --root)          root="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      --data)          data="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      *) shift ;;
    esac
  done

  # The event JSON, only in hook mode and only if there is a pipe.
  # read -t keeps what it read, where `timeout head` loses its buffer when stdin stays open.
  # The JSON usually fits on one line: we stop as soon as `source` is past.
  if [ "$mode" = hook ] && [ ! -t 0 ]; then
    input=""
    c=0
    while [ "$c" -lt 50 ]; do
      l=""
      if IFS= read -r -t 1 l; then input="$input$l"; else input="$input$l"; break; fi
      c=$((c + 1))
      case "$l" in *'"source"'*) break ;; esac
    done
    SOURCE="$(grep -oE '"source"[[:space:]]*:[[:space:]]*"[a-z_]+"' <<<"$input" | sed -n '1p' | sed -E 's/.*"([a-z_]+)"$/\1/')"
  fi
  # The commands below never read stdin, except the restart prompt.
  [ "$mode" = write_brief ] || exec </dev/null

  # No git repository (or no git): not a project, we say nothing.
  base="${root:-${CLAUDE_PROJECT_DIR:-$PWD}}"
  [ -d "$base" ] || return 0
  top="$(git -C "$base" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -z "$top" ]; then
    # In hook mode, silence. A requested write must say why nothing was stored.
    [ "$mode" = hook ] || line "Not a git repository ($base): nothing written or read."
    return 0
  fi
  root="$(cd "$top" && pwd -P)" || return 0

  CTX_ROOT="$root"
  export CTX_ROOT
  # shellcheck source=ctx-common.sh
  if ! . "$DIR/ctx-common.sh"; then
    line "Hook not working: ctx-common.sh not found in $DIR. Reinstall the plugin."
    return 0
  fi

  # Old data folders and file names move to the current ones on first read.
  [ -n "$data" ] && migrate_data "$root" "$data"

  case "$mode" in
    write_marker) write_marker "$root" "$data"; return 0 ;;
    write_brief)  write_brief "$root" "$data" "$plan" "$after"; return 0 ;;
    read_brief)   read_brief "$root" "$data" "$target"; return 0 ;;
    settle)       settle_brief "$root" "$data" "$target"; return 0 ;;
    list_briefs)
      if [ -z "$data" ]; then
        line "No brief queue: CLAUDE_PLUGIN_DATA is missing."
      else
        announce_briefs "$root" "$data"
        [ -n "$OUTPUT" ] || line "No restart prompt waiting."
      fi
      return 0
      ;;
  esac

  for c in CODEMAP.md TODOS.md CHANGELOG.md; do
    [ -f "$root/$c" ] && pillars=$((pillars + 1))
  done

  v="$(conv_version)"
  if [ "$v" = 0 ]; then
    # The plugin is installed for all repositories, forks included: without a block and
    # without any pillar, this is not a convention project, complete silence. With at least
    # one pillar, someone started, one line proposes to add the block.
    if [ "$pillars" -gt 0 ]; then
      line "Context pillars present but no convention block. /fstack:upgrade to add it."
    fi
    return 0
  fi

  # Compaction: the first line is the one that avoids continuing a mode without its procedure.
  if [ "$SOURCE" = compact ]; then
    line "Compaction: only the start of SKILL.md comes back, the mode files already read are only a summary. A running fstack mode continues by rereading its references/MODE-*.md."
  fi

  # Block version.
  case "$v" in
    ''|*[!0-9]*)
      line "Version of the contexte:convention block unreadable ($v). /fstack:upgrade to fix it."
      ;;
    *)
      if [ "$v" -lt "$CTX_VERSION" ]; then
        version_line=""
        [ -n "$(conv_read version)" ] || version_line=", without a version: line"
        line "Convention block at version $v${version_line}, the current one is $CTX_VERSION. /fstack:upgrade"
      elif [ "$v" -gt "$CTX_VERSION" ]; then
        line "Convention block at version $v, newer than the plugin scripts (version $CTX_VERSION). Update the plugin."
      fi
      ;;
  esac

  # The plugin was called clawd-stack until 1.0.0-rc.3, and its commands and agents had French
  # names until 1.0.0-rc.5. An instructions file that still cites them is brought up to date
  # by upgrade.
  for c in CLAUDE.md AGENTS.md; do
    [ -f "$root/$c" ] || continue
    if grep -q "clawd-stack:" "$root/$c" 2>/dev/null; then
      line "$c still cites the old clawd-stack name. Run /fstack:upgrade."
      break
    elif grep -qE "$OLD_NAMES" "$root/$c" 2>/dev/null; then
      line "$c still cites old fstack names. Run /fstack:upgrade."
      break
    fi
  done

  # Continuity first, it must not be cut by the fifteen-line truncation.
  # After a compaction, the session continues: no marker, no brief, no due dates.
  if [ "$SOURCE" != compact ]; then
    if ! read_marker "$root" "$data"; then
      case "$SOURCE" in startup|'') debrief_forgotten "$root" ;; esac
    fi
    case "$SOURCE" in startup|clear|'') announce_briefs "$root" "$data" ;; esac
  fi

  # Resume block of TODOS.md: the date of its title.
  if [ -f "$root/TODOS.md" ]; then
    handover="$(grep -iE '^#+ .*(reprise|resume state)' "$root/TODOS.md" 2>/dev/null | sed -n '1p' || true)"
    if [ -n "$handover" ]; then
      date_r="$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' <<<"$handover" | sed -n '1p' || true)"
      d="$(ctx_days_since "$date_r")"
      if [ -n "$d" ] && [ "$d" -gt 14 ]; then
        line "The resume block of TODOS.md dates from $date_r, $d days ago. It may be stale."
      fi
    fi
  fi

  [ "$SOURCE" = compact ] || due_dates "$root"

  # Budget audit, unless the block is newer than the scripts: it would refuse to run.
  if [ "$v" -le "$CTX_VERSION" ] 2>/dev/null; then
    rc=0
    if command -v timeout >/dev/null 2>&1; then
      out="$(timeout 7 bash "$DIR/ctx-audit.sh" --root "$root" --budget --json 2>/dev/null)" || rc=$?
    else
      out="$(bash "$DIR/ctx-audit.sh" --root "$root" --budget --json 2>/dev/null)" || rc=$?
    fi
    case "$out" in
      "["*)
        if [ "$rc" -eq 0 ]; then
          # The old French keys (niveau, blocage, alerte) are still counted.
          nb="$(printf '%s\n' "$out" | grep -oE '"(level|niveau)":"(blocker|blocage)"' | wc -l | tr -d ' ')"
          nw="$(printf '%s\n' "$out" | grep -oE '"(level|niveau)":"(warning|alerte)"' | wc -l | tr -d ' ')"
          if [ "${nb:-0}" -gt 0 ] || [ "${nw:-0}" -gt 0 ]; then
            line "${nb:-0} blocker(s) and ${nw:-0} warning(s) on the context budget. /fstack:debrief to tidy them."
            msgs="$(printf '%s\n' "$out" | grep -E '"(level|niveau)":"(blocker|blocage)"' | sed -e 's/.*"message":"//' -e 's/"}*,*$//' -e 's/\\"/"/g' | sed -n '1,3p' | cut -c1-200 || true)"
            if [ -n "$msgs" ]; then
              while IFS= read -r c; do
                [ -n "$c" ] && line "  blocker: $c"
              done <<END_LIST
$msgs
END_LIST
            fi
          fi
        elif [ "$rc" -eq 124 ]; then
          line "The budget audit exceeded 7 seconds and returned nothing. /fstack:check to read it plainly."
        else
          line "The budget audit returned code $rc. /fstack:check to read it plainly."
        fi
        ;;
      *)
        if [ "$rc" -eq 124 ]; then
          line "The budget audit exceeded 7 seconds and returned nothing. /fstack:check to read it plainly."
        else
          line "The budget audit returned nothing (code $rc). /fstack:check to read it plainly."
        fi
        ;;
    esac
  fi

  return 0
}

# main speaks only through OUTPUT. In hook mode, it is printed truncated to fifteen lines. The
# restart prompt read by --read-brief comes out in full, it is the deliverable.
MODE_ARG=hook
for a in "$@"; do [ "$a" = --read-brief ] && MODE_ARG=read_brief; done
main "$@" >/dev/null 2>&1 || line "Hook crashed (code $?). Run bash $DIR/ctx-startup.sh by hand to see why."
if [ "$MODE_ARG" = read_brief ]; then
  printf '%s' "$OUTPUT"
else
  printf '%s' "$OUTPUT" | sed -n '1,15p' | cut -c1-240
fi
exit 0
