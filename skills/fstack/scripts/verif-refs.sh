#!/usr/bin/env bash
#
# verif-refs.sh : extrait les chemins, les commandes et les globs cites dans un fichier
# markdown d'instructions, et teste si le depot les confirme.
#
# Le script ne juge pas le contenu d'une regle, il verifie ses references. C'est la partie
# mecanisable de la phase 2 de clawd-audit-md. Tout le reste, conventions et taux de
# respect, se compte a la main.
#
# Trois verdicts, jamais deux pour la meme reference :
#   VRAI            le depot confirme
#   FAUX            le depot contredit, la preuve est dans la colonne preuve
#   NON-VERIFIABLE  pas de quoi trancher. Ce n'est pas un echec, et ca ne bouge pas
#
# Usage :
#   bash verif-refs.sh [--format=tsv|--format=md] [--racine <dir>] <fichier.md> [autre.md ...]
#
# Sortie 1 s'il reste au moins un FAUX, 0 sinon.
#
set -euf

FORMAT="tsv"
RACINE="."
FICHIERS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --format=*) FORMAT="${1#--format=}" ;;
    --racine)   shift; RACINE="${1:-.}" ;;
    -h|--help)  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         echo "option inconnue : $1" >&2; exit 2 ;;
    *)          FICHIERS="$FICHIERS $1" ;;
  esac
  shift
done
# Une barre finale doublerait le separateur dans les motifs de glob : p6//src/*.ts.
RACINE="${RACINE%/}"
[ -n "$RACINE" ] || RACINE=/

[ -n "$FICHIERS" ] || { echo "Usage : bash verif-refs.sh [--format=md] <fichier.md> [...]" >&2; exit 2; }
[ -d "$RACINE" ]   || { echo "racine introuvable : $RACINE" >&2; exit 2; }

# Une reference retenue. Les colonnes sont separees par des tabulations, et tout part
# sur la sortie standard : les boucles de lecture tournent dans des sous-shells, une
# variable accumulee n'y survivrait pas.
note() { # <statut> <type> <ligne> <valeur> <preuve>
  printf '%s\t%s\tL%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"
}

# Un jeton qui porte un trou ne se verifie pas : gabarit, variable, exemple abrege.
est_gabarit() { # <jeton>
  case "$1" in
    *'<'*|*'>'*|*'{{'*|*'$'*|*'...'*|*'…'*) return 0 ;;
    http://*|https://*|mailto:*|'#'*)       return 0 ;;
  esac
  # /clear, /compact, /planifier : une commande slash n'est pas un chemin absolu.
  grep -qE '^/[a-z][a-z0-9-]*$' <<<"$1" && return 0
  case "$1" in
    *) return 1 ;;
  esac
}

# --- chemins -----------------------------------------------------------------

ressemble_a_un_chemin() { # <jeton>
  case "$1" in
    */*)                                             return 0 ;;
    Makefile|Dockerfile|justfile|Procfile|LICENSE)   return 0 ;;
    *.*) grep -qE '^[A-Za-z0-9_.-]+\.[A-Za-z0-9]{1,6}$' <<<"$1" && return 0 ;;
  esac
  return 1
}

cherche_ailleurs() { # <nom>
  find "$RACINE" -name "$1" -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | sed -n '1p'
}

verif_chemin() { # <ligne> <jeton>
  chemin="${2%/}"

  if [ -e "$RACINE/$chemin" ]; then
    note VRAI chemin "$1" "$2" "existe"
    return 0
  fi

  base="$(basename "$chemin")"
  ailleurs="$(cherche_ailleurs "$base")"

  case "$chemin" in
    */*)
      # Un chemin a plusieurs segments se lit depuis la racine. S'il ne resout pas, il
      # est faux, meme si le fichier existe ailleurs. On donne l'endroit pour la reparation.
      if [ -n "$ailleurs" ]; then
        note FAUX chemin "$1" "$2" "absent, mais un $base existe en ${ailleurs#"$RACINE"/}"
      else
        note FAUX chemin "$1" "$2" "aucun fichier a ce chemin"
      fi
      ;;
    *)
      # Un nom seul, sans dossier, nomme un fichier plutot qu'il ne donne son chemin.
      # Le trouver quelque part suffit, sinon la reference ne designe rien.
      if [ -n "$ailleurs" ]; then
        note VRAI chemin "$1" "$2" "existe en ${ailleurs#"$RACINE"/}"
      else
        note FAUX chemin "$1" "$2" "aucun fichier de ce nom dans le depot"
      fi
      ;;
  esac
}

# --- globs -------------------------------------------------------------------

verif_glob() { # <ligne> <jeton>
  # find traite * comme n'importe quelle suite de caracteres, separateur compris,
  # donc ** se replie sur * sans changer le resultat.
  motif="$(printf '%s' "$2" | sed 's|\*\*|*|g')"
  # find rend des chemins qui commencent par $RACINE : le motif s'y ancre, sinon --racine <dir>
  # ne matche jamais rien.
  case "$motif" in /*) motif="${motif#/}" ;; ./*) motif="${motif#./}" ;; esac
  motif="$RACINE/$motif"
  # nb, pas n : n est le compteur de lignes de lire(), l'ecraser decale tout le rapport.
  nb="$(find "$RACINE" -path "$motif" -not -path '*/node_modules/*' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$nb" -gt 0 ]; then
    note VRAI glob "$1" "$2" "$nb fichier(s)"
  else
    note FAUX glob "$1" "$2" "ne matche aucun fichier"
  fi
}

# --- commandes ---------------------------------------------------------------

script_npm() { # <nom>
  [ -f "$RACINE/package.json" ] || return 1
  grep -qE "\"$1\"[[:space:]]*:" "$RACINE/package.json"
}

cible_make() { # <nom>
  [ -f "$RACINE/Makefile" ] || [ -f "$RACINE/makefile" ] || return 1
  grep -hqE "^$1[[:space:]]*:" "$RACINE/Makefile" "$RACINE/makefile" 2>/dev/null
}

verif_commande() { # <ligne> <commande complete>
  set -- "$1" $2
  lg="$1"; shift
  outil="${1:-}"; sous="${2:-}"; trois="${3:-}"

  case "$outil" in
    npm|pnpm|yarn|bun)
      cible="$sous"
      [ "$sous" = "run" ] && cible="$trois"
      case "$cible" in ""|-*) return 0 ;; esac
      case "$cible" in
        install|ci|test|start|init|create|publish|audit) : ;;
      esac
      if [ ! -f "$RACINE/package.json" ]; then
        note FAUX commande "$lg" "$outil $sous $trois" "aucun package.json a la racine"
      elif script_npm "$cible"; then
        note VRAI commande "$lg" "$outil $sous $trois" "script \"$cible\" dans package.json"
      else
        note FAUX commande "$lg" "$outil $sous $trois" "pas de script \"$cible\" dans package.json"
      fi
      ;;
    make)
      case "$sous" in ""|-*) return 0 ;; esac
      if cible_make "$sous"; then
        note VRAI commande "$lg" "make $sous" "cible \"$sous\" dans le Makefile"
      elif [ -f "$RACINE/Makefile" ] || [ -f "$RACINE/makefile" ]; then
        note FAUX commande "$lg" "make $sous" "pas de cible \"$sous\" dans le Makefile"
      else
        note FAUX commande "$lg" "make $sous" "aucun Makefile a la racine"
      fi
      ;;
    just)
      case "$sous" in ""|-*) return 0 ;; esac
      if [ -f "$RACINE/justfile" ] && grep -qE "^${sous}[[:space:]]*:" "$RACINE/justfile"; then
        note VRAI commande "$lg" "just $sous" "recette \"$sous\" dans le justfile"
      elif [ -f "$RACINE/justfile" ]; then
        note FAUX commande "$lg" "just $sous" "pas de recette \"$sous\" dans le justfile"
      else
        note FAUX commande "$lg" "just $sous" "aucun justfile a la racine"
      fi
      ;;
    poetry|uv|pipenv|hatch|tox|pytest|ruff|mypy)
      if [ -f "$RACINE/pyproject.toml" ] || [ -f "$RACINE/setup.py" ] || [ -f "$RACINE/tox.ini" ]; then
        note VRAI commande "$lg" "$outil $sous" "projet python, manifeste present"
      else
        note FAUX commande "$lg" "$outil $sous" "ni pyproject.toml ni setup.py a la racine"
      fi
      ;;
    cargo)
      if [ -f "$RACINE/Cargo.toml" ]; then
        note VRAI commande "$lg" "cargo $sous" "Cargo.toml present"
      else
        note FAUX commande "$lg" "cargo $sous" "aucun Cargo.toml a la racine"
      fi
      ;;
    go)
      if [ -f "$RACINE/go.mod" ]; then
        note VRAI commande "$lg" "go $sous" "go.mod present"
      else
        note FAUX commande "$lg" "go $sous" "aucun go.mod a la racine"
      fi
      ;;
    bash|sh|python|python3|node)
      case "$sous" in ""|-*) return 0 ;; esac
      ressemble_a_un_chemin "$sous" && verif_chemin "$lg" "$sous"
      ;;
    *)
      # Un binaire absent de cette machine ne prouve rien sur le projet.
      case "$outil" in ""|-*|*=*) return 0 ;; esac
      if command -v "$outil" >/dev/null 2>&1; then
        note VRAI commande "$lg" "$outil $sous" "$outil est installe ici"
      else
        note NON-VERIFIABLE commande "$lg" "$outil $sous" "$outil absent de cette machine"
      fi
      ;;
  esac
}

# --- lecture du markdown -----------------------------------------------------

est_une_commande() { # <jeton>
  grep -qE '^(npm|pnpm|yarn|bun|make|just|poetry|uv|pipenv|hatch|tox|pytest|ruff|mypy|cargo|go|bash|sh|python3?|node|docker|git|gh|terraform|kubectl) ' <<<"$1"
}

lire() { # <fichier>
  fichier="$1"
  fence=0
  n=0
  while IFS= read -r ligne || [ -n "$ligne" ]; do
    n=$((n + 1))
    case "$ligne" in
      '```'*|'~~~'*) fence=$((1 - fence)); continue ;;
    esac

    if [ "$fence" -eq 1 ]; then
      # Dans un bloc de code, la premiere commande de la ligne, commentaires enleves.
      cmd="$(printf '%s' "$ligne" | sed -e 's/[[:space:]]*#.*$//' -e 's/^[[:space:]]*//')"
      est_une_commande "$cmd" && verif_commande "$n" "$cmd"
      continue
    fi

    # Un import @chemin charge le fichier au demarrage, recursivement jusqu'a quatre
    # sauts. Entre accents graves il redevient du texte, donc on le cherche avant de
    # decouper la ligne en jetons, et on saute les lignes ou il est protege.
    imp="$(printf '%s\n' "$ligne" | sed 's/`[^`]*`//g' | grep -oE '(^|[[:space:]])@[^[:space:]`)]+' 2>/dev/null | sed 's/^[[:space:]]*//' || true)"
    if [ -n "$imp" ]; then
      printf '%s\n' "$imp" | while IFS= read -r cible; do
        cible="${cible#@}"
        [ -n "$cible" ] || continue
        case "$cible" in *@*) continue ;; esac   # une adresse mail n'est pas un import
        reel="$cible"
        case "$cible" in "~/"*) reel="$HOME/${cible#~/}" ;; esac
        if [ -e "$RACINE/$reel" ] || [ -e "$reel" ]; then
          note VRAI import "$n" "@$cible" "resout, et son contenu compte dans le budget de la racine"
        else
          note FAUX import "$n" "@$cible" "import mort, le fichier n'existe pas et rien ne le signale"
        fi
      done
    fi

    # Hors bloc : les spans entre accents graves, et les cibles de liens markdown.
    jetons="$(printf '%s\n' "$ligne" \
      | grep -oE '`[^`]+`|\]\([^)]+\)' 2>/dev/null \
      | sed -e 's/^`//' -e 's/`$//' -e 's/^](\(.*\))$/\1/' || true)"

    [ -n "$jetons" ] || continue
    printf '%s\n' "$jetons" | while IFS= read -r jeton; do
      [ -n "$jeton" ] || continue
      est_gabarit "$jeton" && continue
      if est_une_commande "$jeton"; then
        verif_commande "$n" "$jeton"
      else
        case "$jeton" in *' '*) continue ;; esac
        case "$jeton" in
          *'*'*) verif_glob "$n" "$jeton" ;;
          *) ressemble_a_un_chemin "$jeton" && verif_chemin "$n" "$jeton" ;;
        esac
      fi
    done
  done < "$fichier"
}

# Chaque fichier verse ses lignes dans un tampon, prefixees de son nom. Le dedoublonnage
# porte sur la reference : un meme chemin cite dix fois ne merite qu'une ligne de rapport.
TAMPON="$(mktemp)"
trap 'rm -f "$TAMPON"' EXIT

for f in $FICHIERS; do
  [ -f "$f" ] || { echo "fichier introuvable : $f" >&2; exit 2; }
  lire "$f" | grep -E '^(VRAI|FAUX|NON-VERIFIABLE)	' | sort -u -t'	' -k4,4 \
    | sed "s|^|$f	|" >> "$TAMPON" || true
done

# --- rendu -------------------------------------------------------------------

TOTAL="$(wc -l < "$TAMPON" | tr -d ' ')"
NB_FAUX="$(grep -c '	FAUX	' "$TAMPON" || true)"
NB_NV="$(grep -c '	NON-VERIFIABLE	' "$TAMPON" || true)"

if [ "$FORMAT" = "md" ]; then
  echo "| Statut | Fichier | Ligne | Référence | Preuve |"
  echo "|---|---|---|---|---|"
  awk -F'	' '{printf "| %s | `%s` | %s | `%s` | %s |\n", $2, $1, $4, $5, $6}' "$TAMPON"
  echo
  echo "$TOTAL référence(s), $NB_FAUX fausse(s), $NB_NV non vérifiable(s)."
else
  printf 'STATUT\tFICHIER\tTYPE\tLIGNE\tREFERENCE\tPREUVE\n'
  awk -F'	' '{printf "%s\t%s\t%s\t%s\t%s\t%s\n", $2, $1, $3, $4, $5, $6}' "$TAMPON"
  printf -- '---\n%s reference(s), %s fausse(s), %s non verifiable(s).\n' "$TOTAL" "$NB_FAUX" "$NB_NV"
fi

[ "$NB_FAUX" -eq 0 ] || exit 1
exit 0
