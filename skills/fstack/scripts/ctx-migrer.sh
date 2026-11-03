#!/usr/bin/env bash
#
# ctx-migrer.sh : remet la convention de contexte d'un projet en version 5.
#
# Lit la version de depart (0 a 4), rend un rapport, et n'ecrit qu'avec --appliquer.
# Jamais de suppression, aucun commit, aucune branche. Un second passage ne change rien.
# Ce qui demande un jugement (regles, copies de skills, script local, profils d'agents,
# MEMORY.md) est liste et propose, jamais tranche.
#
# Usage :
#   bash ctx-migrer.sh [--root <chemin>] [--dry-run]
#   bash ctx-migrer.sh [--root <chemin>] --appliquer
#
# Versions de depart : 0 rien, 1 quatre piliers avec MEMORY.md racine, 2 trois piliers sans bloc,
# 3 bloc sans taille:, 4 bloc avec taille:. Un bloc deja en version 5 n'est pas reecrit, mais les
# gestes idempotents tournent quand meme (lignes d'orchestration, anciennes commandes, listes
# a trier) : on repasse migrer apres une mise a jour du plugin. Sans effet : rien a faire.
#
set -euf

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/ctx-commun.sh"

ROOT=""
APPLIQUER=0
DRY_EXPLICITE=0
TAB="$(printf '\t')"

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      if [ $# -lt 2 ] || [ -z "$2" ]; then echo "--root demande un chemin." >&2; exit 2; fi
      ROOT="$2"; shift 2 ;;
    --appliquer) APPLIQUER=1; shift ;;
    --dry-run)   DRY_EXPLICITE=1; shift ;;
    -h|--help)   sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Option inconnue : $1" >&2; exit 2 ;;
  esac
done

if [ "$APPLIQUER" -eq 1 ] && [ "$DRY_EXPLICITE" -eq 1 ]; then
  echo "--appliquer et --dry-run s'excluent." >&2
  exit 2
fi

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
[ -d "$ROOT" ] || { echo "Racine introuvable : $ROOT" >&2; exit 1; }
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"
unset CTX_RACINE || true

version_scripts || exit 1

DATE="$(ctx_aujourdhui)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ "$APPLIQUER" -eq 1 ]; then
  MODE_TXT="application, les ecritures sont faites"
  V_ECRIT="ecrit"
  V_REECRIT="reecrites"
else
  MODE_TXT="simulation, rien n'est ecrit"
  V_ECRIT="serait ecrit"
  V_REECRIT="seraient reecrites"
fi

# Ecrit un fichier a la place d'un autre sans changer ses droits.
remplacer() { # <source> <destination>
  cat "$1" > "$2"
}

# --- lecture du bloc ----------------------------------------------------------
# Un parseur a part de conv_lire : il doit aussi lire un bloc mal ferme, ce que la
# bibliotheque ne fait pas, et dire sur quelles lignes il s'etend.
PORTEUR="$(conv_trouver)"
BLOC_O=0
BLOC_F=0
BLOC_MAL=0
B_version=""; B_profil=""; B_piliers=""; B_docs=""; B_archives=""; B_langue=""
B_journal=""; B_seuils=""; B_ajourne=""; B_exceptions=""; B_ecarts=""
B_taille=""; B_taille_forcee=""; B_inconnues=""; B_noms=""; B_brutes=0

lire_bloc() {
  [ -n "$PORTEUR" ] || return 0
  # Le bloc va de l'ouverture au vrai -->. Une ligne `cle: valeur` est un champ, toute autre
  # ligne (commentaire, cle avec _, majuscule ou chiffre) part telle quelle sous la cle #brut,
  # dans l'ordre. Une ligne vide ne porte rien, elle est ignoree. Sans --> avant la prochaine
  # ouverture de commentaire ou la fin du fichier, le bloc est mal ferme : on ne garde alors
  # que les lignes `cle: valeur` du debut, jamais le reste du document.
  awk -v kv="$TMP/bloc.kv" -v meta="$TMP/bloc.meta" '
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function estcle(l) { return l ~ /^[a-z][a-z-]*:/ }
    function champ(l,   p, k, v) {
      p = index(l, ":")
      k = trim(substr(l, 1, p - 1)); v = trim(substr(l, p + 1))
      if (!(k in vu)) { vu[k] = 1; print k "\t" v > kv; nch++ }
    }
    function ligne(l) {
      if (estcle(l)) champ(l)
      else if (trim(l) != "") print "#brut\t" l > kv
    }
    { L[NR] = $0 }
    END {
      printf "" > kv
      O = 0
      for (i = 1; i <= NR; i++) {
        p = index(L[i], "<!-- contexte:convention")
        if (p > 0) { O = i; break }
      }
      if (O == 0) { print 0 "\t" 0 "\t" 0 > meta; exit }
      F = O; mal = 0; nch = 0
      reste = substr(L[O], p + length("<!-- contexte:convention"))
      if (index(reste, "-->") > 0) {
        c = O
      } else {
        c = 0
        for (i = O + 1; i <= NR; i++) {
          if (index(L[i], "<!--") > 0) break
          if (index(L[i], "-->") > 0) { c = i; break }
        }
      }
      if (c > O) {
        for (i = O + 1; i < c; i++) ligne(L[i])
        avant = substr(L[c], 1, index(L[c], "-->") - 1)
        ligne(avant)
        F = c
      }
      if (c == 0) {
        mal = 1
        for (i = O + 1; i <= NR; i++) {
          if (estcle(L[i])) { champ(L[i]); F = i; continue }
          if (trim(L[i]) == "") continue
          break
        }
      } else if (c <= O + 1 && nch == 0) {
        # fermeture collee a l ouverture : des champs peuvent suivre, hors du commentaire
        for (i = c + 1; i <= NR && estcle(L[i]); i++) { champ(L[i]); F = i; mal = 1 }
      }
      print O "\t" F "\t" mal > meta
    }' "$PORTEUR"
  [ -f "$TMP/bloc.meta" ] || return 0
  IFS="$TAB" read -r BLOC_O BLOC_F BLOC_MAL < "$TMP/bloc.meta" || true
  local k v
  while IFS="$TAB" read -r k v; do
    [ -n "$k" ] || continue
    case "$k" in
      version) B_version="$v" ;;
      profil) B_profil="$v" ;;
      piliers) B_piliers="$v" ;;
      docs) B_docs="$v" ;;
      archives) B_archives="$v" ;;
      langue) B_langue="$v" ;;
      journal) B_journal="$v" ;;
      seuils) B_seuils="$v" ;;
      ajourne) B_ajourne="$v" ;;
      exceptions) B_exceptions="$v" ;;
      ecarts) B_ecarts="$v" ;;
      taille) B_taille="$v" ;;
      taille-forcee) B_taille_forcee="$v" ;;
      '#brut') B_inconnues="${B_inconnues}${v}
"; B_brutes=$((B_brutes + 1)) ;;
      *) B_inconnues="${B_inconnues}${k}: ${v}
"; B_noms="${B_noms}${k} " ;;
    esac
  done < "$TMP/bloc.kv"
  return 0
}
lire_bloc

# --- version de depart --------------------------------------------------------
PILIERS_PRESENTS=""
PILIERS_ABSENTS=""
NB_PILIERS=0
for p in CODEMAP.md TODOS.md CHANGELOG.md; do
  if [ -f "$p" ]; then
    PILIERS_PRESENTS="$PILIERS_PRESENTS $p"
    NB_PILIERS=$((NB_PILIERS + 1))
  else
    PILIERS_ABSENTS="$PILIERS_ABSENTS $p"
  fi
done

VERSION=0
if [ -n "$PORTEUR" ]; then
  VERSION=""
  case "$B_version" in
    ''|*[!0-9]*) ;;
    *) VERSION="$B_version" ;;
  esac
  if [ -z "$VERSION" ]; then
    if [ -n "$B_taille" ]; then VERSION=4; else VERSION=3; fi
  fi
elif [ -f MEMORY.md ] && [ "$NB_PILIERS" -ge 1 ]; then
  VERSION=1
elif [ "$NB_PILIERS" -eq 3 ]; then
  VERSION=2
fi

echo "Migration de la convention de contexte"
echo "  racine            : $ROOT"
echo "  mode              : $MODE_TXT"
echo "  version de depart : $VERSION"
echo "  version cible     : $CTX_VERSION"

# Un bloc deja a la version cible n'est pas reecrit, mais le script ne sort plus : les gestes
# idempotents ajoutes depuis la migration doivent atteindre les projets deja migres.
V5=0
if [ "$VERSION" -ge "$CTX_VERSION" ]; then V5=1; fi

# Le travail se fait sur une branche, l'operateur merge. Un avertissement, pas un refus.
avertir_branche() {
  if [ "$APPLIQUER" -eq 1 ] && git rev-parse --git-dir >/dev/null 2>&1; then
    BRANCHE="$(git symbolic-ref --short -q HEAD 2>/dev/null || true)"
    case "$BRANCHE" in
      main|master) echo "  [!] branche $BRANCHE : le mode MIGRER travaille sur une branche a part." ;;
    esac
    if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
      echo "  [!] des fichiers suivis sont deja modifies, le diff de la migration sera melange au leur."
    fi
  fi
  return 0
}
if [ "$V5" -eq 0 ]; then avertir_branche; fi

# --- mesures ------------------------------------------------------------------
# La taille et le profil sont ceux de ctx-init.sh, appele en simulation : une seule
# regle de mesure pour les deux scripts.
MESURE_TAILLE=""
MESURE_PROFIL=""
if [ "$V5" -eq 0 ] && [ -f "$SCRIPT_DIR/ctx-init.sh" ]; then
  bash "$SCRIPT_DIR/ctx-init.sh" --root "$ROOT" --dry-run > "$TMP/init.out" 2>/dev/null || true
  MESURE_TAILLE="$(sed -n 's/^  taille  : \([a-z]*\),.*/\1/p' "$TMP/init.out" | sed -n '1p')"
  MESURE_PROFIL="$(sed -n 's/^  profil  : //p' "$TMP/init.out" | sed -n '1p')"
fi

dir_existant() { # <candidats...> : premier repertoire present, avec barre finale
  local d
  for d in "$@"; do
    if [ -d "$d" ]; then printf '%s/\n' "$d"; return 0; fi
  done
  return 0
}

detecter_langue() {
  local f fichiers=""
  for f in CLAUDE.md CODEMAP.md README.md; do
    if [ -f "$f" ]; then fichiers="$fichiers $f"; fi
  done
  [ -n "$fichiers" ] || { echo fr; return 0; }
  # shellcheck disable=SC2086
  head -n 150 $fichiers 2>/dev/null | tr '[:upper:]' '[:lower:]' | awk '
    { n = split($0, m, /[^a-z]+/)
      for (i = 1; i <= n; i++) {
        if (m[i] == "the" || m[i] == "and" || m[i] == "of" || m[i] == "is" || m[i] == "with") en++
        if (m[i] == "le" || m[i] == "la" || m[i] == "les" || m[i] == "des" || m[i] == "et" || m[i] == "est") fr++
      } }
    END { if (en > 2 * fr + 3) print "en"; else print "fr" }'
  return 0
}

# --- conventions existantes : ecarts ------------------------------------------
E_ADD=""
ajouter_ecart() { # <nom> <justification>
  case "${B_ecarts:-}" in *"$1="*) return 0 ;; esac
  E_ADD="${E_ADD}${E_ADD:+, }$1=$2"
  return 0
}

CONV_TROUVEES=""
trouver_conventions() {
  local f
  if [ -f MEMORY.md ]; then
    ajouter_ecart "MEMORY.md" "quatrième pilier conservé (justification à compléter)"
    CONV_TROUVEES="${CONV_TROUVEES}  MEMORY.md : conserve et declare, rien n'est dissous. Son contenu se repartit
    (decisions, pieges, preferences) seulement si l'operateur le decide, par la PR.
"
  fi
  for f in PROJECT.md TASKS.md ETAT.md; do
    if [ -f "$f" ]; then
      ajouter_ecart "$f" "schéma propre au projet conservé (justification à compléter)"
      CONV_TROUVEES="${CONV_TROUVEES}  $f : schema existant, conserve et declare.
"
    fi
  done
  if [ -f AGENTS.md ]; then
    local porteur=0
    if [ ! -f CLAUDE.md ]; then
      porteur=1
    elif [ "$(wc -l < CLAUDE.md | tr -d ' ')" -lt 10 ] || grep -q '@AGENTS.md' CLAUDE.md 2>/dev/null; then
      porteur=1
    fi
    if [ "$porteur" -eq 1 ]; then
      ajouter_ecart "AGENTS.md" "porteur des règles à la place de CLAUDE.md (justification à compléter)"
      CONV_TROUVEES="${CONV_TROUVEES}  AGENTS.md : porte les regles du projet, conserve et declare.
"
    fi
  fi
  return 0
}
trouver_conventions

# --- script local qui fork l'audit : seuils -----------------------------------
SEUILS_ADD=""
AJOURNE_ADD=""
SCRIPTS_LOCAUX=""
SEUILS_LUS=""
SEUILS_SANS_FICHIER=""

fichier_du_seuil() { # <NOM_DE_VARIABLE>
  case "$1" in
    *CODEMAP*) echo CODEMAP.md ;;
    *TODOS*|*TODO*) echo TODOS.md ;;
    *CHANGELOG*) echo CHANGELOG.md ;;
    *CLAUDE*) echo CLAUDE.md ;;
    *AGENTS*) echo AGENTS.md ;;
    *MEMORY*) echo MEMORY.md ;;
  esac
  return 0
}

entree_deja_declaree() { # <liste a=b, c=d> <nom>
  printf '%s\n' "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/=.*//; s/[[:space:]]*$//' \
    | grep -xF "$2" >/dev/null
}

# Les lignes NOM=nombre dont le nom parle de seuil : SEUIL, MAX_..., LIMITE, BLOCAGE, AJOURN.
seuils_du_script() { # <script>
  sed -n -E "s/^[[:space:]]*(export[[:space:]]+)?([A-Z_0-9]*(SEUIL|MAX|LIMITE|BLOCAGE|AJOURN)[A-Z_0-9]*)=[\"']?([0-9]+)[\"']?.*/\\2 \\4/p" "$1"
  return 0
}

lire_scripts_locaux() {
  local s nom val fic lus
  [ -d scripts ] || return 0
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    if grep -qi 'CODEMAP' "$s" 2>/dev/null && grep -qi 'TODOS' "$s" 2>/dev/null; then
      SCRIPTS_LOCAUX="${SCRIPTS_LOCAUX}${s}
"
      lus="$(seuils_du_script "$s")"
      while read -r nom val; do
        [ -n "$nom" ] || continue
        fic="$(fichier_du_seuil "$nom")"
        if [ -z "$fic" ]; then
          SEUILS_SANS_FICHIER="${SEUILS_SANS_FICHIER}${s} : ${nom}=${val}
"
          continue
        fi
        case "$nom" in
          *AJOURN*)
            if entree_deja_declaree "$B_ajourne" "$fic" || entree_deja_declaree "$AJOURNE_ADD" "$fic"; then continue; fi
            AJOURNE_ADD="${AJOURNE_ADD}${AJOURNE_ADD:+, }$fic=$val@$DATE"
            SEUILS_LUS="${SEUILS_LUS}${s} : ${nom}=${val} -> ajourne: $fic=$val@$DATE
"
            ;;
          *)
            if entree_deja_declaree "$B_seuils" "$fic" || entree_deja_declaree "$SEUILS_ADD" "$fic"; then continue; fi
            SEUILS_ADD="${SEUILS_ADD}${SEUILS_ADD:+, }$fic=$val"
            SEUILS_LUS="${SEUILS_LUS}${s} : ${nom}=${val} -> seuils: $fic=$val
"
            ;;
        esac
      done <<FIN
$lus
FIN
    fi
  done <<FIN
$(find scripts -maxdepth 1 -type f -name '*.sh' 2>/dev/null | LC_ALL=C sort)
FIN
  return 0
}
lire_scripts_locaux

# --- construction du bloc -----------------------------------------------------
fusionner() { # <existant> <ajouts>
  if [ -n "$1" ] && [ -n "$2" ]; then printf '%s, %s' "$1" "$2"
  elif [ -n "$1" ]; then printf '%s' "$1"
  else printf '%s' "$2"; fi
  return 0
}

NOTES=""
note() { NOTES="${NOTES}  $1
"; return 0; }

N_profil="$B_profil"
if [ -z "$N_profil" ] && [ -n "$MESURE_PROFIL" ]; then
  N_profil="$MESURE_PROFIL"
  note "+ profil: $N_profil (detecte comme ctx-init.sh)"
fi
N_piliers="$B_piliers"
if [ -z "$N_piliers" ]; then
  N_piliers="CODEMAP.md, TODOS.md, CHANGELOG.md"
  note "+ piliers: les trois par defaut"
fi
N_docs="$B_docs"
if [ -z "$N_docs" ]; then
  N_docs="$(dir_existant docs doc documentation)"
  [ -n "$N_docs" ] || N_docs="docs/"
  note "+ docs: $N_docs"
fi
N_archives="$B_archives"
if [ -z "$N_archives" ]; then
  N_archives="$(dir_existant archives archive)"
  [ -n "$N_archives" ] || N_archives="archives/"
  note "+ archives: $N_archives"
fi
N_langue="$B_langue"
if [ -z "$N_langue" ]; then
  N_langue="$(detecter_langue)"
  note "+ langue: $N_langue (devinee sur CLAUDE.md et CODEMAP.md, a verifier)"
fi
N_seuils="$(fusionner "$B_seuils" "$SEUILS_ADD")"
[ -z "$SEUILS_ADD" ] || note "+ seuils: $SEUILS_ADD (lus dans le script local)"
N_ajourne="$(fusionner "$B_ajourne" "$AJOURNE_ADD")"
[ -z "$AJOURNE_ADD" ] || note "+ ajourne: $AJOURNE_ADD (lu dans le script local, date de la migration)"
N_ecarts="$(fusionner "$B_ecarts" "$E_ADD")"
[ -z "$E_ADD" ] || note "+ ecarts: ecart(s) declare(s) pour $(printf '%s' "$E_ADD" | sed 's/=[^,]*//g')"

N_taille_forcee="$B_taille_forcee"
if [ -n "$B_taille" ]; then
  if [ -n "$MESURE_TAILLE" ] && [ "$B_taille" = "$MESURE_TAILLE" ]; then
    note "- taille: $B_taille retiree, la mesure donne la meme chose"
  elif [ -z "$B_taille_forcee" ]; then
    N_taille_forcee="$B_taille"
    if [ -n "$MESURE_TAILLE" ]; then
      note "~ taille: $B_taille devient taille-forcee, la mesure donne $MESURE_TAILLE (a confirmer, sinon la retirer)"
    else
      note "~ taille: $B_taille devient taille-forcee, la mesure n'a pas pu etre faite"
    fi
  else
    note "- taille: $B_taille retiree, taille-forcee: $B_taille_forcee existe deja"
  fi
fi
if [ -n "$B_version" ]; then
  note "~ version: $B_version devient $CTX_VERSION"
else
  note "+ version: $CTX_VERSION (le bloc n'en portait pas)"
fi
if [ "$BLOC_MAL" -eq 1 ]; then
  note "! bloc mal ferme, repare : la fermeture --> est remise apres le dernier champ, les champs sont dans le commentaire"
fi
if [ -n "$B_noms" ]; then
  note "= cle(s) inconnue(s) gardee(s) telles quelles : $B_noms"
fi
if [ "$B_brutes" -gt 0 ]; then
  note "= $B_brutes ligne(s) hors schema (commentaire, cle avec _ ou majuscule) gardee(s) telles quelles dans le bloc"
fi

{
  echo "<!-- contexte:convention"
  echo "version: $CTX_VERSION"
  [ -z "$N_profil" ] || echo "profil: $N_profil"
  echo "piliers: $N_piliers"
  echo "docs: $N_docs"
  echo "archives: $N_archives"
  echo "langue: $N_langue"
  [ -z "$B_journal" ] || echo "journal: $B_journal"
  [ -z "$N_seuils" ] || echo "seuils: $N_seuils"
  [ -z "$N_ajourne" ] || echo "ajourne: $N_ajourne"
  [ -z "$B_exceptions" ] || echo "exceptions: $B_exceptions"
  [ -z "$N_ecarts" ] || echo "ecarts: $N_ecarts"
  [ -z "$N_taille_forcee" ] || echo "taille-forcee: $N_taille_forcee"
  [ -z "$B_inconnues" ] || printf '%s' "$B_inconnues"
  echo "-->"
} > "$TMP/bloc.new"

# Ou va le bloc. Le fichier qui le porte deja, sinon CODEMAP.md, sinon le porteur des
# regles. Un projet sans aucun de ces fichiers n'a rien a migrer, c'est ctx-init.sh.
CIBLE_BLOC=""
if [ -n "$PORTEUR" ]; then
  CIBLE_BLOC="$PORTEUR"
elif [ "$VERSION" -ge 1 ]; then
  for f in CODEMAP.md CLAUDE.md AGENTS.md; do
    if [ -f "$f" ]; then CIBLE_BLOC="$f"; break; fi
  done
fi

# --- regles .claude/rules : globs: vers paths: --------------------------------
cat > "$TMP/globs.awk" <<'AWK'
function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function entre_guillemets(s,   c) {
  c = substr(s, 1, 1)
  if (length(s) >= 2 && (c == "\"" || c == "'") && substr(s, length(s), 1) == c \
      && index(substr(s, 2, length(s) - 2), c) == 0) return substr(s, 2, length(s) - 2)
  return s
}
function item(s) {
  s = trim(s)
  s = entre_guillemets(s)
  if (substr(s, 1, 1) == "\"" && substr(s, length(s), 1) == "\"") s = substr(s, 2, length(s) - 2)
  if (substr(s, 1, 1) == "'" && substr(s, length(s), 1) == "'") s = substr(s, 2, length(s) - 2)
  return "  - \"" s "\""
}
NR == 1 && $0 == "---" { fm = 1; print; next }
fm == 1 && $0 == "---" { fm = 2; print; next }
fm == 1 && $0 ~ /^globs:/ {
  v = trim(substr($0, 7))
  print "paths:"
  if (v == "") next
  if (v ~ /^\[.*\]$/) v = substr(v, 2, length(v) - 2)
  v = entre_guillemets(trim(v))
  depth = 0; cur = ""
  for (i = 1; i <= length(v); i++) {
    c = substr(v, i, 1)
    if (c == "{") depth++
    if (c == "}") depth--
    if (c == "," && depth == 0) { if (trim(cur) != "") print item(cur); cur = "" }
    else cur = cur c
  }
  if (trim(cur) != "") print item(cur)
  next
}
{ print }
AWK

REGLES_GLOBS=""
REGLES_DEJA_PATHS=""
lister_regles() {
  local r
  [ -d .claude/rules ] || return 0
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    r="${r#./}"
    if awk 'NR == 1 && $0 != "---" { exit 1 }
            NR > 1 && $0 == "---" { exit f ? 0 : 1 }
            /^globs:/ { f = 1 }
            END { exit f ? 0 : 1 }' "$r" 2>/dev/null; then
      if awk 'NR > 1 && $0 == "---" { exit }
              /^paths:/ { f = 1 }
              END { exit f ? 0 : 1 }' "$r" 2>/dev/null; then
        REGLES_DEJA_PATHS="${REGLES_DEJA_PATHS}${r}
"
      else
        REGLES_GLOBS="${REGLES_GLOBS}${r}
"
      fi
    fi
  done <<FIN
$(find .claude/rules -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)
FIN
  return 0
}
lister_regles

# --- copies locales de skills -------------------------------------------------
COPIES=""
lister_copies() {
  local base nom p
  for base in .claude/skills skills .opencode/skills .agents/skills marketplace/plugins; do
    for nom in cloture-session relance plan-prompt plan-review deep-plan clawd-audit-md; do
      p="$base/$nom"
      if [ -e "$p" ]; then COPIES="${COPIES}${p}
"; fi
    done
  done
  for nom in cloture-session plan-review relance audit-md cloture init-contexte reprise-session; do
    p=".claude/commands/$nom.md"
    if [ -e "$p" ]; then COPIES="${COPIES}${p}
"; fi
  done
  return 0
}
lister_copies

# --- commandes des anciens plugins --------------------------------------------
cat > "$TMP/commandes.awk" <<'AWK'
function mot(c) {
  return c != "" && index("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.:/~-", c) > 0
}
function apres_ok(r,   c1, c2) {
  c1 = substr(r, 1, 1)
  if (c1 == "") return 1
  if (index("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_/-:", c1) > 0) return 0
  if (c1 == ".") {
    c2 = substr(r, 2, 1)
    if (c2 != "" && index("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_", c2) > 0) return 0
  }
  return 1
}
function reecrire(l,   k, out, s, i, prev, reste) {
  for (k = 1; k <= n; k++) {
    out = ""; s = l
    while ((i = index(s, P[k])) > 0) {
      prev = (i > 1) ? substr(s, i - 1, 1) : substr(out, length(out), 1)
      reste = substr(s, i + length(P[k]))
      if (!mot(prev) && apres_ok(reste)) out = out substr(s, 1, i - 1) R[k]
      else out = out substr(s, 1, i - 1) P[k]
      s = reste
    }
    l = out s
  }
  return l
}
BEGIN {
  P[++n] = "/cloture-session:init-contexte";    R[n] = "/fstack:init"
  P[n+1] = "/cloture-session:reprise-session";  R[n+1] = "/fstack:relance"; n++
  P[++n] = "/cloture-session:cloture";          R[n] = "/fstack:cloture"
  P[++n] = "/deep-plan:planifier";              R[n] = "/fstack:planifier"
  P[++n] = "/clawd-audit-md:audit-md";          R[n] = "/fstack:audit"
  P[++n] = "/init-contexte";                    R[n] = "/fstack:init"
  P[++n] = "/reprise-session";                  R[n] = "/fstack:relance"
  P[++n] = "/audit-md";                         R[n] = "/fstack:audit"
  P[++n] = "/planifier";                        R[n] = "/fstack:planifier"
  P[++n] = "/cloture";                          R[n] = "/fstack:cloture"
  # Le plugin s'appelait clawd-stack jusqu'a la 1.0.0-rc.3 : commandes, agents, skill et marqueur
  # d'orchestration. Le slash se traite a part, mot() refuse un "/" juste avant le motif.
  k = split("init relance cloture planifier audit migrer orchestration clawd-stack chercheur controleur developpeur executant expert explorateur relecteur", A, " ")
  for (j = 1; j <= k; j++) {
    c = (A[j] == "clawd-stack") ? "fstack" : A[j]
    P[++n] = "/clawd-stack:" A[j];  R[n] = "/fstack:" c
    P[++n] = "clawd-stack:" A[j];   R[n] = "fstack:" c
  }
  P[++n] = "clawd-stack:<profil>";              R[n] = "fstack:<profil>"
  printf "" > rap
}
{
  nouvelle = reecrire($0)
  if (nouvelle != $0) { print NR ": " $0 "  ->  " nouvelle >> rap; chg++ }
  print nouvelle
}
END { close(rap) }
AWK

FICHIERS_COMMANDES_CHANGES=""
reecrire_commandes() {
  local f sm exclu i=0 sous liste
  sous="$(sous_modules)"
  # exclusions_prune rend des motifs que le shell ne doit pas developper : set -f est actif, pas de guillemets
  # shellcheck disable=SC2046
  liste="$(find . -maxdepth 4 $(exclusions_prune) -o -type f \( -name CLAUDE.md -o -name AGENTS.md \) -print 2>/dev/null | LC_ALL=C sort)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    f="${f#./}"
    exclu=0
    while IFS= read -r sm; do
      [ -n "$sm" ] || continue
      case "$f" in "$sm"/*) exclu=1 ;; esac
    done <<FIN
$sous
FIN
    [ "$exclu" -eq 0 ] || continue
    i=$((i + 1))
    awk -v rap="$TMP/rap.$i" -f "$TMP/commandes.awk" "$f" > "$TMP/cmd.$i"
    if ! cmp -s "$f" "$TMP/cmd.$i"; then
      FICHIERS_COMMANDES_CHANGES="${FICHIERS_COMMANDES_CHANGES}${f}${TAB}${i}
"
    fi
  done <<FIN
$liste
FIN
  return 0
}
reecrire_commandes

# --- profils d'agents locaux --------------------------------------------------
AGENTS_LOCAUX=""
modele_fige() { # <valeur du champ model>
  case "$1" in
    claude-*|*anthropic*|*-[0-9]*) return 0 ;;
  esac
  return 1
}
lister_agents() {
  local a nom modele raison
  [ -d .claude/agents ] || return 0
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    nom="$(basename "$a" .md)"
    modele="$(awk 'NR == 1 && $0 != "---" { exit }
                   NR > 1 && $0 == "---" { exit }
                   /^model:/ { sub(/^model:[ \t]*/, ""); gsub(/["'"'"'\r]/, ""); print; exit }' "$a")"
    raison=""
    case "$nom" in syz-*|gz-*) raison="profil local ($nom)" ;; esac
    if [ -n "$modele" ] && modele_fige "$modele"; then
      raison="${raison}${raison:+, }model fige : $modele"
    fi
    if [ -n "$raison" ]; then
      AGENTS_LOCAUX="${AGENTS_LOCAUX}${a} : ${raison}
"
    fi
  done <<FIN
$(find .claude/agents -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)
FIN
  return 0
}
lister_agents

# ==============================================================================
# Rapport
# ==============================================================================
echo
echo "Bloc contexte:convention"
if [ -n "$PORTEUR" ]; then
  echo "  porteur : $PORTEUR, lignes $BLOC_O a $BLOC_F"
else
  echo "  aucun bloc dans les fichiers de la racine"
fi
[ -z "$PILIERS_PRESENTS" ] || echo "  piliers presents :$PILIERS_PRESENTS"
[ -z "$PILIERS_ABSENTS" ] || echo "  piliers absents  :$PILIERS_ABSENTS"
if [ -n "$MESURE_TAILLE" ]; then echo "  taille mesuree   : $MESURE_TAILLE"; fi

BLOC_ECRIT=0
if [ "$V5" -eq 1 ]; then
  echo "  bloc deja en version $CTX_VERSION, pas reecrit"
elif [ "$VERSION" -eq 0 ] && [ -z "$PORTEUR" ]; then
  echo "  [!] aucune convention : le bloc n'est pas pose ici. ctx-init.sh installe le kit"
  echo "      et le bloc en version $CTX_VERSION, c'est le bon outil pour ce projet."
elif [ -z "$CIBLE_BLOC" ]; then
  echo "  [!] aucun fichier pour porter le bloc (ni CODEMAP.md, ni CLAUDE.md, ni AGENTS.md)."
  echo "      ctx-init.sh cree le kit, relance la migration ensuite."
else
  if [ -z "$PORTEUR" ] && [ "$CIBLE_BLOC" != "CODEMAP.md" ]; then
    echo "  [!] CODEMAP.md absent : le bloc est pose dans $CIBLE_BLOC. Quand CODEMAP.md sera cree,"
    echo "      le bloc ira en tete de ce fichier, un seul bloc par projet."
  fi
  BLOC_ECRIT=1
  echo "  bloc en version $CTX_VERSION, $V_ECRIT dans $CIBLE_BLOC :"
  sed 's/^/    | /' "$TMP/bloc.new"
  printf '%s' "$NOTES"
fi

if [ "$V5" -eq 0 ] && [ -n "$CONV_TROUVEES" ]; then
  echo
  echo "Conventions existantes, declarees dans ecarts: et non dissoutes"
  printf '%s' "$CONV_TROUVEES"
fi

if [ -n "$REGLES_GLOBS" ] || [ -n "$REGLES_DEJA_PATHS" ]; then
  echo
  echo "Regles .claude/rules : globs: vers paths:, PROPOSE, jamais applique par ce script"
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    awk -f "$TMP/globs.awk" "$r" > "$TMP/regle.new"
    echo "  $r"
    diff -u -L "a/$r" -L "b/$r" "$r" "$TMP/regle.new" | sed 's/^/    /' || true
  done <<FIN
$REGLES_GLOBS
FIN
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    echo "  $r : porte globs: ET paths:, retirer globs: a la main"
  done <<FIN
$REGLES_DEJA_PATHS
FIN
fi

if [ -n "$COPIES" ]; then
  echo
  echo "Copies locales de skills et de commandes, A RETIRER dans la PR (rien n'est supprime ici)"
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    if [ -d "$c" ]; then
      printf '  %s (%s fichier(s))\n' "$c" "$(find "$c" -type f | wc -l | tr -d ' ')"
    else
      printf '  %s\n' "$c"
      printf '    retrait d'"'"'un fichier : bash %s/ctx-archive.sh %s --raison "remplace par fstack"\n' "$SCRIPT_DIR" "$c"
    fi
  done <<FIN
$COPIES
FIN
  echo "  Verifier avant le retrait qu'aucune copie ne porte un reglage propre au projet."
fi

if [ -n "$SCRIPTS_LOCAUX" ]; then
  echo
  echo "Script local qui fork l'audit, A RETIRER une fois ses seuils reportes"
  printf '%s' "$SCRIPTS_LOCAUX" | sed 's/^/  /'
  if [ -n "$SEUILS_LUS" ]; then
    if [ "$V5" -eq 1 ]; then
      echo "  seuils lus, absents du bloc, a reporter a la main :"
    else
      echo "  seuils lus :"
    fi
    printf '%s' "$SEUILS_LUS" | sed 's/^/    /'
  fi
  if [ -n "$SEUILS_SANS_FICHIER" ]; then
    echo "  seuils lus sans fichier reconnu, a reporter a la main :"
    printf '%s' "$SEUILS_SANS_FICHIER" | sed 's/^/    /'
  fi
  if [ -z "$SEUILS_LUS" ] && [ -z "$SEUILS_SANS_FICHIER" ]; then
    if [ "$V5" -eq 1 ]; then
      echo "  aucun seuil a reporter (deja dans le bloc, ou aucun lisible simplement)."
    else
      echo "  aucun seuil lisible simplement : a reprendre a la main."
    fi
  fi
  echo "  Le reste de sa logique (controles propres au projet) est a relire a la main."
fi

if [ -n "$FICHIERS_COMMANDES_CHANGES" ]; then
  echo
  echo "Commandes des anciens plugins citees dans CLAUDE.md et AGENTS.md, $V_REECRIT vers /fstack:*"
  while IFS="$TAB" read -r f i; do
    [ -n "$f" ] || continue
    printf '  %s : %s ligne(s)\n' "$f" "$(wc -l < "$TMP/rap.$i" | tr -d ' ')"
    head -n 10 "$TMP/rap.$i" | cut -c1-170 | sed 's/^/    /'
  done <<FIN
$FICHIERS_COMMANDES_CHANGES
FIN
fi

if [ -n "$AGENTS_LOCAUX" ]; then
  echo
  echo "Profils d'agents locaux, PROPOSE, rien n'est supprime ni declare"
  printf '%s' "$AGENTS_LOCAUX" | sed 's/^/  /'
  echo "  Au choix : les remplacer par les profils d'agents du skill (explorateur, controleur,"
  echo "  executant, developpeur, chercheur, expert, relecteur), ou les declarer dans ecarts: avec"
  echo "  une ligne comme : ecarts: agents=<noms>: profils locaux assumes (justification a completer)"
fi

# Les trois lignes d'orchestration du gabarit, posees dans le CLAUDE.md du projet (AGENTS.md
# a defaut). Le marqueur fstack:orchestration, ou l'ancien clawd-stack:orchestration, rend le geste idempotent.
TPL_SNIPPET="$SCRIPT_DIR/../templates/CLAUDE-snippet.md"
CIBLE_ORCH=""
for f in CLAUDE.md AGENTS.md; do
  if [ -f "$f" ]; then CIBLE_ORCH="$f"; break; fi
done
ORCH_A_POSER=0
if [ ! -f "$TPL_SNIPPET" ] || ! grep -q "fstack:orchestration" "$TPL_SNIPPET"; then
  [ "$V5" -eq 1 ] || { echo; echo "Orchestration"; echo "  gabarit sans bloc d'orchestration, rien a poser"; }
elif [ "$V5" -eq 0 ] && [ "$BLOC_ECRIT" -ne 1 ]; then
  echo; echo "Orchestration"; echo "  pas de migration ici, rien a poser"
elif [ -z "$CIBLE_ORCH" ]; then
  # Sur un bloc deja en version 5, un projet sans CLAUDE.md ni AGENTS.md est l'affaire de l'audit.
  [ "$V5" -eq 1 ] || { echo; echo "Orchestration"; echo "  [!] ni CLAUDE.md ni AGENTS.md : trois lignes non posees, ctx-init.sh cree le fichier"; }
elif grep -qE "(fstack|clawd-stack):orchestration" "$CIBLE_ORCH"; then
  [ "$V5" -eq 1 ] || { echo; echo "Orchestration"; echo "  = $CIBLE_ORCH contient deja les lignes d'orchestration"; }
else
  ORCH_A_POSER=1
  echo; echo "Orchestration"
  echo "  trois lignes d'orchestration, $V_ECRIT a la fin de $CIBLE_ORCH"
fi

# ==============================================================================
# Ecriture
# ==============================================================================
# Les fichiers touches, comptes une fois chacun, en simulation comme en application.
A_ECRIRE=""
marquer_ecrit() { # <fichier>
  local m="${1#./}"
  case "
$A_ECRIRE" in *"
$m
"*) return 0 ;; esac
  A_ECRIRE="${A_ECRIRE}${m}
"
  return 0
}
if [ "$BLOC_ECRIT" -eq 1 ]; then marquer_ecrit "$CIBLE_BLOC"; fi
while IFS="$TAB" read -r f i; do
  [ -n "$f" ] || continue
  marquer_ecrit "$f"
done <<FIN
$FICHIERS_COMMANDES_CHANGES
FIN
if [ "$ORCH_A_POSER" -eq 1 ]; then marquer_ecrit "$CIBLE_ORCH"; fi
NB_ECRITS="$(printf '%s' "$A_ECRIRE" | grep -c . || true)"

NB_DECISIONS=0
for liste in "$REGLES_GLOBS" "$REGLES_DEJA_PATHS" "$COPIES" "$SCRIPTS_LOCAUX" "$AGENTS_LOCAUX"; do
  if [ -n "$liste" ]; then NB_DECISIONS=$((NB_DECISIONS + 1)); fi
done
if [ "$V5" -eq 0 ] && [ -n "$CONV_TROUVEES" ]; then NB_DECISIONS=$((NB_DECISIONS + 1)); fi

# Un bloc deja a jour, aucun geste a faire, rien a trier : on le dit et on sort.
if [ "$V5" -eq 1 ] && [ "$NB_ECRITS" -eq 0 ] && [ "$NB_DECISIONS" -eq 0 ]; then
  echo
  echo "Le bloc est deja en version $CTX_VERSION, rien a faire."
  exit 0
fi

if [ "$V5" -eq 1 ] && [ "$NB_ECRITS" -gt 0 ]; then avertir_branche; fi

if [ "$APPLIQUER" -eq 1 ]; then
  CMD_FAIT=""
  if [ "$BLOC_ECRIT" -eq 1 ]; then
    # Si le fichier qui porte le bloc cite aussi d'anciennes commandes, la pose du bloc
    # part de la version deja reecrite : les deux gestes se composent en une seule ecriture.
    # La reecriture des commandes garde les numeros de ligne, BLOC_O et BLOC_F restent justes.
    BASE_BLOC="$CIBLE_BLOC"
    while IFS="$TAB" read -r f i; do
      [ -n "$f" ] || continue
      if [ "$f" = "${CIBLE_BLOC#./}" ]; then BASE_BLOC="$TMP/cmd.$i"; CMD_FAIT="$i"; fi
    done <<FIN
$FICHIERS_COMMANDES_CHANGES
FIN
    if [ -n "$PORTEUR" ]; then
      awk -v O="$BLOC_O" -v F="$BLOC_F" -v nf="$TMP/bloc.new" '
        NR == O { while ((getline l < nf) > 0) print l; close(nf) }
        NR < O || NR > F { print }' "$BASE_BLOC" > "$TMP/porteur.new"
    else
      { cat "$TMP/bloc.new"; echo; cat "$BASE_BLOC"; } > "$TMP/porteur.new"
    fi
    remplacer "$TMP/porteur.new" "$CIBLE_BLOC"
  fi
  while IFS="$TAB" read -r f i; do
    [ -n "$f" ] || continue
    [ "$i" != "$CMD_FAIT" ] || continue
    remplacer "$TMP/cmd.$i" "$f"
  done <<FIN
$FICHIERS_COMMANDES_CHANGES
FIN
  if [ "$ORCH_A_POSER" -eq 1 ]; then
    { cat "$CIBLE_ORCH"; echo; sed -n '/fstack:orchestration/,$p' "$TPL_SNIPPET"; } > "$TMP/orch.new"
    remplacer "$TMP/orch.new" "$CIBLE_ORCH"
  fi
fi

echo
if [ "$APPLIQUER" -eq 1 ]; then
  echo "Bilan : $NB_ECRITS fichier(s) ecrit(s), $NB_DECISIONS point(s) laisse(s) a l'operateur."
  echo "Rien n'est commite. Un second --appliquer ne change rien."
elif [ "$V5" -eq 1 ] && [ "$NB_ECRITS" -eq 0 ]; then
  echo "Bilan : aucune ecriture a faire, $NB_DECISIONS point(s) restent a l'operateur."
else
  echo "Bilan : simulation, rien n'a ete ecrit. $NB_DECISIONS point(s) restent a l'operateur."
  echo "Relire ce rapport avec lui, puis relancer avec --appliquer."
fi
if [ "$V5" -eq 0 ]; then
  echo "Ensuite : une cloture complete du projet, puis la PR est ouverte par l'operateur."
fi
exit 0
