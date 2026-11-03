#!/usr/bin/env bash
#
# verif-agents.sh : controle le frontmatter des fichiers de definition de sous-agents.
#
# Un fichier d'agent mal forme n'est pas charge, et rien ne le dit. Pas d'erreur au
# demarrage, pas d'avertissement, l'agent n'apparait simplement pas dans la liste. Ce
# script cherche les facons de disparaitre en silence, plus les valeurs d'enumeration
# qui ne veulent rien dire.
#
# Memes trois verdicts que verif-refs.sh :
#   VRAI            le fichier sera charge
#   FAUX            il ne le sera pas, ou une valeur sera ignoree. La preuve est a cote
#   NON-VERIFIABLE  depend de quelque chose qui n'est pas dans le depot
#
# Usage :
#   bash verif-agents.sh [--format=tsv|--format=md] <repertoire|fichier> [...]
#
# Sortie 1 s'il reste au moins un FAUX, 0 sinon.
#
set -euf

FORMAT="tsv"
CIBLES=""

while [ $# -gt 0 ]; do
  case "$1" in
    --format=*) FORMAT="${1#--format=}" ;;
    -h|--help)  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         echo "option inconnue : $1" >&2; exit 2 ;;
    *)          CIBLES="$CIBLES $1" ;;
  esac
  shift
done

[ -n "$CIBLES" ] || CIBLES=".claude/agents"

# Les cles admises. Une cle absente d'ici est ignoree en silence par le lecteur, donc
# une faute de frappe sur un nom de cle desactive l'option sans rien dire.
CLES="name description tools disallowedTools model permissionMode maxTurns skills mcpServers hooks memory background effort isolation color initialPrompt"

VAL_model="sonnet opus haiku fable inherit"
VAL_effort="low medium high xhigh max"
VAL_permissionMode="default acceptEdits auto dontAsk bypassPermissions plan manual"
VAL_memory="user project local"
VAL_background="true false"
VAL_isolation="worktree"
VAL_color="red blue green yellow purple orange pink cyan"

TAMPON="$(mktemp)"
NOMS="$(mktemp)"
trap 'rm -f "$TAMPON" "$NOMS"' EXIT

note() { # <statut> <fichier> <cle> <constat>
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$TAMPON"
}

dans_la_liste() { # <valeur> <liste>
  for v in $2; do [ "$1" = "$v" ] && return 0; done
  return 1
}

# Le frontmatter, entre le premier --- et le suivant. Rien d'autre ne compte.
frontmatter() { # <fichier>
  awk 'NR==1 && $0!="---" { exit } NR==1 { dedans=1; next } dedans && $0=="---" { exit } dedans' "$1"
}

valeur_de() { # <frontmatter> <cle>
  sed -n "s/^$2:[[:space:]]*//p" <<<"$1" | sed -n '1p' | sed -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}

controle() { # <fichier>
  f="$1"
  base="$(basename "$f" .md)"
  fm="$(frontmatter "$f")"

  if [ -z "$fm" ]; then
    note FAUX "$f" frontmatter "aucun frontmatter, le fichier est lu comme de la documentation et jamais comme un agent"
    return 0
  fi

  nom="$(valeur_de "$fm" name)"
  desc="$(valeur_de "$fm" description)"

  # --- les quatre facons de disparaitre en silence ---
  if [ -z "$nom" ]; then
    note FAUX "$f" name "cle name absente, le fichier est ignore sans message"
  else
    case "$nom" in
      *:*)  note FAUX "$f" name "name contient un deux-points, le fichier est rejete au chargement" ;;
      -*)   note FAUX "$f" name "name commence par un tiret, le fichier est rejete au chargement" ;;
      *)
        if grep -qE '^[a-z][a-z0-9-]*$' <<<"$nom"; then
          note VRAI "$f" name "$nom"
        else
          note FAUX "$f" name "\"$nom\" hors convention, minuscules et tirets seulement"
        fi
        # Le nom fait foi, pas le fichier. Deux fichiers du meme repertoire qui portent
        # le meme nom, et un seul des deux se charge, sans que rien ne dise lequel.
        printf '%s\t%s\n' "$(dirname "$f")/$nom" "$f" >> "$NOMS"
        [ "$nom" = "$base" ] || note NON-VERIFIABLE "$f" name "name \"$nom\" et fichier \"$base.md\" different, legal mais deroutant a la lecture"
        ;;
    esac
  fi

  if [ -z "$desc" ]; then
    note FAUX "$f" description "cle description absente, le fichier est ignore sans message"
  elif [ "${#desc}" -lt 40 ]; then
    note FAUX "$f" description "${#desc} caracteres, trop court pour que la delegation automatique se declenche"
  else
    note VRAI "$f" description "${#desc} caracteres"
  fi

  # --- les enumerations, une valeur hors liste est ignoree ---
  for cle in model effort permissionMode memory background isolation color; do
    val="$(valeur_de "$fm" "$cle")"
    [ -n "$val" ] || continue
    eval "liste=\$VAL_$cle"
    if dans_la_liste "$val" "$liste"; then
      note VRAI "$f" "$cle" "$val"
    elif [ "$cle" = "model" ]; then
      # Un identifiant complet est admis en plus des alias.
      if grep -qE '^claude-[a-z0-9.-]+$' <<<"$val"; then
        note VRAI "$f" model "$val, identifiant complet"
      else
        note FAUX "$f" model "\"$val\" hors liste. Admis : $liste, ou un identifiant claude-*"
      fi
    else
      note FAUX "$f" "$cle" "\"$val\" hors liste. Admis : $liste"
    fi
  done

  val="$(valeur_de "$fm" maxTurns)"
  if [ -n "$val" ]; then
    if grep -qE '^[1-9][0-9]*$' <<<"$val"; then
      note VRAI "$f" maxTurns "$val"
    else
      note FAUX "$f" maxTurns "\"$val\" n'est pas un entier positif"
    fi
  fi

  # --- les cles inconnues, ignorees en silence ---
  printf '%s\n' "$fm" | grep -oE '^[A-Za-z][A-Za-z0-9_-]*:' | sed 's/:$//' | while IFS= read -r cle; do
    dans_la_liste "$cle" "$CLES" || note FAUX "$f" "$cle" "cle inconnue, elle est ignoree en silence. Faute de frappe ?"
  done
}

# --- balayage ----------------------------------------------------------------

for cible in $CIBLES; do
  if [ -f "$cible" ]; then
    controle "$cible"
  elif [ -d "$cible" ]; then
    trouve=0
    for f in $(find "$cible" -name '*.md' -type f 2>/dev/null | sort); do
      trouve=1
      controle "$f"
    done
    [ "$trouve" -eq 1 ] || echo "aucun fichier .md dans $cible" >&2
  else
    echo "cible introuvable : $cible" >&2
    exit 2
  fi
done

# Les noms en double, une fois tout lu.
if [ -s "$NOMS" ]; then
  # split avec un espace seul applique le decoupage par defaut d'awk, qui rogne les
  # blancs de tete. On compte donc les fichiers, pas les champs plus un.
  sort "$NOMS" | awk -F'\t' '
    { n[$1] = n[$1] " " $2 }
    END {
      for (k in n) {
        c = split(n[k], a, " ")
        nom = k; sub(/.*\//, "", nom)
        if (c > 1) printf "FAUX\t%s\tname\tnom \"%s\" porte par %d fichiers du meme repertoire, un seul se charge et rien ne dit lequel\n", a[1], nom, c
      }
    }' >> "$TAMPON"
fi

# --- rendu -------------------------------------------------------------------

TOTAL="$(wc -l < "$TAMPON" | tr -d ' ')"
NB_FAUX="$(grep -c '^FAUX	' "$TAMPON" || true)"
NB_NV="$(grep -c '^NON-VERIFIABLE	' "$TAMPON" || true)"

if [ "$FORMAT" = "md" ]; then
  echo "| Statut | Fichier | Clé | Constat |"
  echo "|---|---|---|---|"
  awk -F'\t' '{printf "| %s | `%s` | `%s` | %s |\n", $1, $2, $3, $4}' "$TAMPON"
  echo
  echo "$TOTAL contrôle(s), $NB_FAUX en échec, $NB_NV à regarder."
else
  printf 'STATUT\tFICHIER\tCLE\tCONSTAT\n'
  cat "$TAMPON"
  printf -- '---\n%s controle(s), %s en echec, %s a regarder.\n' "$TOTAL" "$NB_FAUX" "$NB_NV"
fi

[ "$NB_FAUX" -eq 0 ] || exit 1
exit 0
