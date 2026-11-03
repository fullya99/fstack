#!/usr/bin/env bash
#
# ctx-archeo.sh : la seule façon sanctionnee de lire dans archives/.
#
# La convention interdit de lire archives/ en reprise, parce que c'est du faux ou
# du froid. Mais un agent qui cherche POURQUOI une chose est faite comme ça doit
# pouvoir y aller. Ce script est ce chemin. Il rend toujours l'en-tete de
# provenance AVANT la ligne trouvee, donc on ne peut pas prendre une archive pour
# une verite courante.
#
# Usage :
#   bash ctx-archeo.sh <motif>                  # cherche, rend provenance + extraits
#   bash ctx-archeo.sh --liste                  # inventaire de ce qui est archive
#   bash ctx-archeo.sh --fichier <chemin>       # la provenance d'une archive precise
#   bash ctx-archeo.sh <motif> --max 10 --contexte 4
#
# La sortie est BORNEE, expres. Une archive de journal fait des milliers de
# lignes, et deverser ça dans un contexte coute plus que ça ne rend. Le script
# dit ce qu'il a coupe et comment voir la suite.
set -euf

ROOT=""
MOTIF=""
FICHIER=""
LISTE=0
MAX=20
CONTEXTE=2

while [ $# -gt 0 ]; do
  case "$1" in
    --root)     ROOT="${2:-}"; shift 2 ;;
    --liste)    LISTE=1; shift ;;
    --fichier)  FICHIER="${2:-}"; shift 2 ;;
    --max)      MAX="${2:-20}"; shift 2 ;;
    --contexte) CONTEXTE="${2:-2}"; shift 2 ;;
    -h|--help)  sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         echo "Option inconnue : $1" >&2; exit 2 ;;
    *)          MOTIF="$1"; shift ;;
  esac
done

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"

# Le repertoire d'archives se declare dans le bloc contexte:convention, sinon
# c'est archives/ par defaut.
ARCHIVES="$(grep -m1 '^archives:' CODEMAP.md 2>/dev/null | sed 's/^archives: *//;s|/*$||' || true)"
[ -n "$ARCHIVES" ] || ARCHIVES="archives"
[ -d "$ARCHIVES" ] || { echo "Aucun repertoire d'archives ($ARCHIVES/). Rien a fouiller." >&2; exit 1; }

# --- provenance d'un fichier archive -----------------------------------------
# L'en-tete fait cinq lignes au plus, en blockquote, pose par ctx-archive.sh ou
# par ctx-rotation.sh. Les deux formes se distinguent : l'une porte du faux,
# l'autre du vrai devenu froid, et le lecteur doit savoir laquelle il tient.
provenance() { # <fichier>
  local f="$1" tete
  tete="$(head -8 "$f" | grep '^>' || true)"
  if grep -q 'rotation' <<<"$tete"; then
    printf '  nature   : FROID, encore vrai a sa date, sorti du journal courant\n'
  elif [ -n "$tete" ]; then
    printf '  nature   : FAUX ou PERIME, ne pas s en servir pour agir\n'
  else
    printf '  nature   : SANS EN-TETE, provenance inconnue, defaut d archivage\n'
  fi
  [ -n "$tete" ] && printf '%s\n' "$tete" | sed 's/^> *//; s/^/  /' | grep -v '^ *$' || true
}

# --- mode inventaire ----------------------------------------------------------
if [ "$LISTE" -eq 1 ]; then
  echo "=============================================="
  echo " Inventaire de $ARCHIVES/"
  echo "=============================================="
  n=0
  for f in $(find "$ARCHIVES" -type f -name '*.md' -not -name 'README.md' 2>/dev/null | sort); do
    n=$((n + 1))
    printf '\n%s  (%s lignes)\n' "$f" "$(wc -l < "$f" | tr -d ' ')"
    provenance "$f"
  done
  autres="$(find "$ARCHIVES" -type f -not -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  echo
  echo "$n fichier(s) markdown archive(s), $autres autre(s) fichier(s)."
  [ -f "$ARCHIVES/README.md" ] && echo "L'index est dans $ARCHIVES/README.md."
  exit 0
fi

# --- mode fichier -------------------------------------------------------------
if [ -n "$FICHIER" ]; then
  FICHIER="${FICHIER#./}"
  [ -f "$FICHIER" ] || { echo "Introuvable : $FICHIER" >&2; exit 1; }
  case "$FICHIER" in
    "$ARCHIVES"/*) : ;;
    *) echo "$FICHIER n'est pas dans $ARCHIVES/. Ce script ne lit que les archives." >&2; exit 2 ;;
  esac
  echo "$FICHIER  ($(wc -l < "$FICHIER" | tr -d ' ') lignes)"
  provenance "$FICHIER"
  echo
  echo "Pour le lire en entier, sachant ce que dit sa nature ci-dessus :"
  echo "  sed -n '1,120p' $FICHIER"
  exit 0
fi

# --- mode recherche -----------------------------------------------------------
[ -n "$MOTIF" ] || { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
case "$MAX" in ''|*[!0-9]*) echo "--max attend un entier" >&2; exit 2 ;; esac
case "$CONTEXTE" in ''|*[!0-9]*) echo "--contexte attend un entier" >&2; exit 2 ;; esac

echo "=============================================="
echo " Archeologie : « $MOTIF » dans $ARCHIVES/"
echo "=============================================="
echo
echo "⚠️  Rien de ce qui suit n'est une source de verite. Chaque bloc dit sa nature."
echo "    L'etat courant est dans les piliers de la racine et dans docs/."

FICHIERS="$(grep -rl -- "$MOTIF" "$ARCHIVES" 2>/dev/null | sort || true)"
if [ -z "$FICHIERS" ]; then
  echo
  echo "Aucune occurrence. Rien d'archive ne parle de ça."
  exit 0
fi

TOTAL=0
for f in $FICHIERS; do
  nb="$(grep -c -- "$MOTIF" "$f" 2>/dev/null || echo 0)"
  TOTAL=$((TOTAL + nb))
done

echo
echo "$TOTAL occurrence(s) dans $(printf '%s\n' "$FICHIERS" | wc -l | tr -d ' ') fichier(s)."

MONTRES=0
RESTE=0
for f in $FICHIERS; do
  nb="$(grep -c -- "$MOTIF" "$f" 2>/dev/null || echo 0)"
  printf '\n----------------------------------------------\n'
  printf '%s\n' "$f"
  case "$f" in
    */README.md|README.md)
          printf '  nature   : INDEX des archives, pas un document archive\n' ;;
    *.md) provenance "$f" ;;
    *)    printf '  nature   : fichier non markdown, pas d en-tete\n' ;;
  esac
  printf '\n'
  if [ "$MONTRES" -ge "$MAX" ]; then
    printf '  [%s occurrence(s) non affichee(s), plafond atteint]\n' "$nb"
    RESTE=$((RESTE + nb))
    continue
  fi
  # Les lignes sont tronquees a 200 caracteres. Une ligne de doc peut etre tres
  # longue, et le but est de situer, pas de tout rapatrier.
  LIMITE=$(( (MAX - MONTRES) * (2 * CONTEXTE + 1) ))
  grep -n -C "$CONTEXTE" -- "$MOTIF" "$f" 2>/dev/null | sed -n "1,${LIMITE}p" \
    | cut -c1-200 | sed 's/^/  /' || true
  if [ "$nb" -gt $(( MAX - MONTRES )) ]; then
    RESTE=$(( RESTE + nb - (MAX - MONTRES) ))
  fi
  MONTRES=$((MONTRES + nb))
done

echo
echo "=============================================="
if [ "$RESTE" -gt 0 ]; then
  echo " $RESTE occurrence(s) non affichee(s). Relance avec --max plus haut,"
  echo " ou lis un fichier precis : ctx-archeo.sh --fichier <chemin>"
else
  echo " Tout est affiche."
fi
echo " Ce qui est vrai aujourd'hui ne se lit pas ici. Va aux piliers et a docs/."
echo "=============================================="
