#!/usr/bin/env bash
#
# ctx-archive.sh : sort un document de la circulation, en une passe et sans en
# oublier une etape.
#
# Le geste faisait quatre etapes a la main : git mv, en-tete, ligne d'index,
# correction des liens. La quatrieme est celle qu'on oublie, et c'est pour ça que
# l'audit a du inventer une alerte pour la rattraper. Ici tout se fait, ou rien.
#
# Usage :
#   bash ctx-archive.sh --verifier <chemin>
#   bash ctx-archive.sh <chemin> --raison "..." [--remplace-par "..."] [--dry-run] [--force]
#   bash ctx-archive.sh <chemin> --raison "..." --resume <fichier> [--remplace-par "..."] [--dry-run]
#
# --resume : le fichier garde sa place sous forme de resume. Le texte integral part dans
# les archives, <fichier> est pose a l'ancien chemin, ou {{ARCHIVE}} devient le chemin de
# l'archive. Les references entrantes restent valides, elles ne bloquent donc pas, et la
# verification finale controle que le resume est en place. Appel de ctx-rotation.sh --plans.
#
# Le critere d'archivage porte sur les REFERENCES ENTRANTES, pas sur une
# impression. Pour chaque reference : est-elle operative, quelqu'un a besoin du
# document pour agir maintenant, ou est-ce du contexte historique, un commentaire
# qui raconte la provenance ? On archive quand toutes les references restantes
# sont historiques. Un lien markdown vivant vers le document est operatif par
# construction, il bloque, et --force ne se prend qu'en connaissance de cause.
#
# La derniere etape est une VERIFICATION : plus aucune occurrence de l'ancien
# chemin hors des archives, sinon sortie en erreur.
set -euf

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=ctx-commun.sh
. "$DIR/ctx-commun.sh"

# Un accent grave litteral dans du code shell est une source de bug silencieux.
# On le fabrique une fois, on ne l'ecrit jamais.
BT="$(printf '\140')"
FENCE="$BT$BT$BT"

ROOT=""
CIBLE=""
RAISON=""
REMPLACE=""
DRY=0
FORCE=0
VERIFIER=0
RESUME=""

# Une option a valeur sans valeur : message clair et code 2, pas une sortie muette.
valeur() { # <option> <nombre d'arguments restants, option comprise>
  if [ "$2" -lt 2 ]; then
    echo "$1 attend une valeur" >&2
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root)         valeur "$1" $#; ROOT="$2"; shift 2 ;;
    --raison)       valeur "$1" $#; RAISON="$2"; shift 2 ;;
    --remplace-par) valeur "$1" $#; REMPLACE="$2"; shift 2 ;;
    --verifier)     valeur "$1" $#; VERIFIER=1; CIBLE="$2"; shift 2 ;;
    --resume)       valeur "$1" $#; RESUME="$2"; shift 2 ;;
    --dry-run)      DRY=1; shift ;;
    --force)        FORCE=1; shift ;;
    -h|--help)      sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)             echo "Option inconnue : $1" >&2; exit 2 ;;
    *)              CIBLE="$1"; shift ;;
  esac
done

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"

[ -n "$CIBLE" ] || { sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
CIBLE="${CIBLE#./}"

version_scripts || exit 1
ARCHIVES="$(conv_lire archives | sed 's|/*$||')"
if [ -z "$ARCHIVES" ]; then
  ARCHIVES="$(grep -m1 '^archives:' CODEMAP.md 2>/dev/null | sed 's/^archives: *//;s|/*$||' || true)"
fi
[ -n "$ARCHIVES" ] || ARCHIVES="archives"
TODAY="$(ctx_aujourdhui)"
MOIS="${TODAY%-*}"
DEST="$ARCHIVES/$MOIS/$CIBLE"

# --- 0. barrieres -------------------------------------------------------------
[ -e "$CIBLE" ] || { echo "Introuvable : $CIBLE" >&2; exit 1; }
[ -f "$CIBLE" ] || { echo "$CIBLE n'est pas un fichier. Archive les fichiers un par un." >&2; exit 1; }
case "$CIBLE" in
  "$ARCHIVES"/*) echo "$CIBLE est deja dans $ARCHIVES/." >&2; exit 1 ;;
esac
if [ -n "$RESUME" ] && [ ! -f "$RESUME" ]; then
  echo "--resume : fichier introuvable : $RESUME" >&2; exit 1
fi
if [ "$VERIFIER" -eq 0 ] && [ -e "$DEST" ]; then
  echo "$DEST existe deja, l'archivage l'ecraserait. Renomme l'un des deux." >&2; exit 1
fi
case "$(basename "$CIBLE")" in
  CODEMAP.md|TODOS.md|CHANGELOG.md|CLAUDE.md|AGENTS.md)
    echo "$CIBLE est un pilier ou un fichier de regles, il ne s'archive pas." >&2
    echo "Une section fausse dans un pilier se corrige sur place. Une regle durable" >&2
    echo "devenue fausse se supprime, elle est pire qu'une regle absente." >&2
    exit 1 ;;
esac
case "$CIBLE" in
  docs/README.md|"$ARCHIVES"/README.md)
    echo "$CIBLE est un index. Un index ne s'archive pas." >&2; exit 1 ;;
esac

# --- 1. references entrantes --------------------------------------------------
# On cherche le chemin complet ET le nom de base, hors archives. Le premier dit
# qui pointe vraiment vers le fichier, le second attrape les mentions en prose.
BASE="$(basename "$CIBLE")"
chercher() { # <motif litteral>
  if git rev-parse --git-dir >/dev/null 2>&1; then
    git grep -n --fixed-strings -- "$1" 2>/dev/null | grep -v "^$ARCHIVES/" || true
  else
    grep -rn --fixed-strings --exclude-dir=.git -- "$1" . 2>/dev/null \
      | sed 's|^\./||' | grep -v "^$ARCHIVES/" || true
  fi
}
REFS_CHEMIN="$(chercher "$CIBLE" | grep -v "^$CIBLE:" || true)"
REFS_BASE="$(chercher "$BASE" | grep -v "^$CIBLE:" | grep -vF "$CIBLE" || true)"

# Un lien markdown vers le fichier est operatif, il cassera au deplacement.
LIENS="$(printf '%s\n' "$REFS_CHEMIN" "$REFS_BASE" | grep -v '^$' \
         | grep -E "\]\([^)]*$BASE(#[^)]*)?\)" || true)"
NB_LIENS="$(printf '%s\n' "$LIENS" | grep -c . || true)"
NB_CHEMIN="$(printf '%s\n' "$REFS_CHEMIN" | grep -c . || true)"
NB_BASE="$(printf '%s\n' "$REFS_BASE" | grep -c . || true)"

echo "=============================================="
echo " Archivage : $CIBLE"
echo " $TODAY"
echo "=============================================="
echo
echo "1. References entrantes, hors $ARCHIVES/"
if [ "${NB_LIENS:-0}" -gt 0 ] && [ -n "$RESUME" ]; then
  echo "  liens vivants ($NB_LIENS), ils restent valides, le resume garde le chemin :"
  printf '%s\n' "$LIENS" | cut -c1-160 | sed 's/^/       /'
elif [ "${NB_LIENS:-0}" -gt 0 ]; then
  echo "  OPERATIVES, ces liens casseront ($NB_LIENS) :"
  printf '%s\n' "$LIENS" | cut -c1-160 | sed 's/^/       /'
fi
if [ "${NB_CHEMIN:-0}" -gt 0 ]; then
  echo "  chemin cite ($NB_CHEMIN), a classer une par une :"
  sed -n '1,20p' <<<"$REFS_CHEMIN" | cut -c1-160 | sed 's/^/       /'
  [ "$NB_CHEMIN" -gt 20 ] && printf '       ... et %s de plus\n' "$((NB_CHEMIN - 20))"
fi
if [ "${NB_BASE:-0}" -gt 0 ]; then
  echo "  nom seul cite ($NB_BASE), souvent du contexte historique :"
  sed -n '1,10p' <<<"$REFS_BASE" | cut -c1-160 | sed 's/^/       /'
  [ "$NB_BASE" -gt 10 ] && printf '       ... et %s de plus\n' "$((NB_BASE - 10))"
fi
[ "${NB_CHEMIN:-0}" -eq 0 ] && [ "${NB_BASE:-0}" -eq 0 ] \
  && echo "  aucune. Personne ne cite ce fichier."

if [ "$VERIFIER" -eq 1 ]; then
  echo
  echo "=============================================="
  echo " Mode verification, rien n'a ete ecrit."
  if [ "${NB_LIENS:-0}" -gt 0 ]; then
    echo " $NB_LIENS lien(s) vivant(s) a retirer ou a reformuler AVANT d'archiver."
    echo " Une fiche vivante ne cite pas une archive, la convention l'interdit."
  else
    echo " Aucun lien bloquant. L'archivage peut se faire."
  fi
  echo "=============================================="
  exit 0
fi

if [ -z "$RAISON" ]; then
  echo
  echo "--raison est obligatoire. « obsolete » ne renseigne personne." >&2
  exit 2
fi

if [ "${NB_LIENS:-0}" -gt 0 ] && [ "$FORCE" -eq 0 ] && [ -z "$RESUME" ]; then
  echo
  echo "REFUS : $NB_LIENS lien(s) markdown vivant(s) pointent vers ce fichier." >&2
  echo "Retire-les ou reformule-les d'abord, une fiche vivante ne cite pas une archive." >&2
  echo "Puis relance. Avec --force, tu archives en laissant des liens morts derriere toi." >&2
  exit 3
fi

# --- 2. deplacement -----------------------------------------------------------
echo
echo "2. Deplacement"
printf '  %s\n  -> %s\n' "$CIBLE" "$DEST"
if [ "$DRY" -eq 0 ]; then
  mkdir -p "$(dirname "$DEST")"
  if git rev-parse --git-dir >/dev/null 2>&1 \
     && git ls-files --error-unmatch "$CIBLE" >/dev/null 2>&1; then
    git mv "$CIBLE" "$DEST"
  else
    echo "  (non suivi par git, deplacement simple)"
    mv "$CIBLE" "$DEST"
  fi
fi

# --- 3. en-tete ---------------------------------------------------------------
echo
echo "3. En-tete de provenance"
if [ -n "$REMPLACE" ]; then
  REMPL_TXT="$BT$REMPLACE$BT"
else
  REMPL_TXT="aucun remplacant, le sujet n'existe plus"
fi
if [ "$DRY" -eq 0 ]; then
  TMP="$(mktemp)"
  {
    printf '> **ARCHIVE le %s**, document non maintenu, garde pour l historique.\n' "$TODAY"
    printf '> **Origine** : %s%s%s\n' "$BT" "$CIBLE" "$BT"
    printf '> **Raison** : %s\n' "$RAISON"
    printf '> **Remplace par** : %s\n' "$REMPL_TXT"
    printf '> **Ne pas utiliser comme source de verite.**\n'
    printf '\n'
    cat "$DEST"
  } > "$TMP"
  mv "$TMP" "$DEST"
fi
printf '  date %s, origine, raison, remplacant : %s\n' "$TODAY" "$REMPL_TXT"

# --- 4. liens du fichier deplace ----------------------------------------------
# Le fichier a change de profondeur, ses liens relatifs vers ce qui reste vivant
# ne resolvent plus. On ne peut pas se contenter de prefixer des ../ : le chemin
# d'origine est reinjecte SOUS le prefixe d'archive, donc remonter ne suffit pas,
# il faut redescendre. On resout donc chaque lien depuis la racine du depot, puis
# on repart de la nouvelle profondeur. Les liens externes, les ancres et les
# chemins absolus ne bougent pas, et on ne touche pas aux blocs de code.
OLDDIR="$(dirname "$CIBLE")"
[ "$OLDDIR" = "." ] && OLDDIR=""
NEWDIR="$(dirname "$DEST")"
PROFONDEUR="$(printf '%s' "$NEWDIR" | tr '/' '\n' | grep -c .)"
UP=""
i=0
while [ "$i" -lt "$PROFONDEUR" ]; do UP="../$UP"; i=$((i + 1)); done
echo
echo "4. Liens relatifs du fichier deplace"
AVANT="$(grep -oE '\]\([^)]*\)' "$DEST" 2>/dev/null \
         | grep -vcE '\]\((https?:|mailto:|#|/)' || true)"
if [ "${AVANT:-0}" -gt 0 ]; then
  printf '  %s lien(s) relatif(s) resolu(s) depuis la racine, prefixe %s\n' "$AVANT" "$UP"
  if [ "$DRY" -eq 0 ]; then
    TMP="$(mktemp)"
    awk -v UP="$UP" -v OLDDIR="$OLDDIR" -v FENCE="$FENCE" '
      # Normalise un chemin : retire . et resout .. sans toucher au disque.
      function normalise(p,   n, seg, m, i, out, r) {
        n = split(p, seg, "/")
        m = 0
        for (i = 1; i <= n; i++) {
          if (seg[i] == "" || seg[i] == ".") continue
          if (seg[i] == "..") { if (m > 0) m--; continue }
          m++; out[m] = seg[i]
        }
        r = ""
        for (i = 1; i <= m; i++) r = (r == "" ? out[i] : r "/" out[i])
        return r
      }
      function rebase(u,   anchor, h, cible) {
        if (u ~ /^(https?:|mailto:|#|\/)/) return u
        if (u ~ /^\{\{/) return u
        if (u ~ /^</) return u
        anchor = ""
        h = index(u, "#")
        if (h > 0) { anchor = substr(u, h); u = substr(u, 1, h - 1) }
        if (u == "") return anchor
        cible = normalise((OLDDIR == "" ? u : OLDDIR "/" u))
        return UP cible anchor
      }
      index($0, FENCE) == 1 { dans = !dans; print; next }
      dans { print; next }
      {
        out = ""; rest = $0
        while (match(rest, /\]\([^)]*\)/)) {
          pre = substr(rest, 1, RSTART - 1)
          tok = substr(rest, RSTART, RLENGTH)
          rest = substr(rest, RSTART + RLENGTH)
          url = substr(tok, 3, length(tok) - 3)
          out = out pre "](" rebase(url) ")"
        }
        print out rest
      }' "$DEST" > "$TMP"
    mv "$TMP" "$DEST"
  fi
else
  echo "  aucun lien relatif a resoudre"
fi

# --- 5. ligne d'index ---------------------------------------------------------
echo
echo "5. Index"
LIGNE="| $TODAY | $BT$CIBLE$BT | $BT$DEST$BT | $RAISON | $REMPL_TXT |"
if [ -f "$ARCHIVES/README.md" ] && grep -q '^|---' "$ARCHIVES/README.md"; then
  if [ "$DRY" -eq 0 ]; then
    TMP="$(mktemp)"
    awk -v l="$LIGNE" 'BEGIN{fait=0} { print } /^\|---/ && !fait { print l; fait=1 }' \
      "$ARCHIVES/README.md" > "$TMP"
    mv "$TMP" "$ARCHIVES/README.md"
  fi
  echo "  ligne ajoutee dans $ARCHIVES/README.md"
else
  echo "  $ARCHIVES/README.md absent ou sans table. Ligne a poser a la main :"
  echo "    $LIGNE"
fi

# --- 5 bis. resume en place ---------------------------------------------------
if [ -n "$RESUME" ]; then
  echo
  echo "5 bis. Resume a l'ancien chemin"
  printf '  %s reste en place, texte integral dans %s\n' "$CIBLE" "$DEST"
  if [ "$DRY" -eq 0 ]; then
    sed "s|{{ARCHIVE}}|$DEST|g" "$RESUME" > "$CIBLE"
  fi
fi

# --- 6. verification ----------------------------------------------------------
# La porte. C'est elle qui distingue un archivage fini d'un archivage a moitie
# fait, et c'est celle qui manquait quand le geste se faisait a la main.
echo
echo "6. Verification"
if [ "$DRY" -eq 1 ]; then
  echo "  sautee, mode simulation"
  echo
  echo "Simulation terminee, rien n'a ete ecrit."
  exit 0
fi
if [ -n "$RESUME" ]; then
  if [ -s "$CIBLE" ] && [ -s "$DEST" ]; then
    echo "  [ok] resume en place a $CIBLE, texte integral dans $DEST"
    echo
    echo "=============================================="
    echo " Archive, resume gardé. Rien n'est commite, verifie avec git status."
    echo "=============================================="
    exit 0
  fi
  echo "  [!] le resume ou l'archive manque apres l'operation" >&2
  exit 1
fi
RESTE="$(chercher "$CIBLE" | grep -v "^$DEST:" || true)"
NB_RESTE="$(printf '%s\n' "$RESTE" | grep -c . || true)"
if [ "${NB_RESTE:-0}" -gt 0 ]; then
  echo "  [!] $NB_RESTE occurrence(s) de l'ancien chemin hors des archives :"
  sed -n '1,15p' <<<"$RESTE" | cut -c1-160 | sed 's/^/       /'
  echo
  echo "=============================================="
  echo " Archivage INCOMPLET. Le fichier est deplace, son en-tete et sa ligne"
  echo " d'index sont poses, mais des references pointent encore vers l'ancien"
  echo " chemin. Corrige celles listees ci-dessus."
  echo "=============================================="
  exit 1
fi
echo "  [ok] aucune occurrence de l'ancien chemin hors des archives"
echo
echo "=============================================="
if git rev-parse --git-dir >/dev/null 2>&1; then
  echo " Archive. Rien n'est commite, verifie avec git status."
else
  echo " Archive. Le depot n'est pas suivi par git, l'historique du fichier n'est pas garde."
fi
echo " Pour retrouver ce contenu plus tard : ctx-archeo.sh <motif>"
echo "=============================================="
