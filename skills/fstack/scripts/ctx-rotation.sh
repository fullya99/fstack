#!/usr/bin/env bash
#
# ctx-rotation.sh : fait tourner un journal, ou compresse les plans executes.
#
# Journal : garde les N entrees les plus recentes dans le fichier, deplace les autres
# dans archives/<journal>/AAAA-MM.md, un fichier par mois, et pose une ligne d'index
# dans archives/README.md. Une entree ancienne n'est pas fausse, elle est froide.
# archives/ est le seul endroit que la convention ne lit jamais en reprise.
#
# Usage :
#   bash ctx-rotation.sh [--root <chemin>] [--fichier <journal.md>] [--garder <N>] [--plafond <N>] [--dry-run]
#   bash ctx-rotation.sh --plans [--root <chemin>] [--dry-run]
#
# --fichier : CHANGELOG.md par defaut.
# --garder  : nombre d'entrees conservees, 30 par defaut. Les N premieres du fichier,
#             donc les plus recentes, le journal etant range du plus recent au plus ancien.
# --plafond : lignes maximum d'un fichier d'archive, 1500 par defaut. Un mois qui
#             depasse se coupe en AAAA-MM-2.md, AAAA-MM-3.md, chacun indexe.
# --plans   : au lieu du journal, traite les plans du repertoire declare par `plans:` dans le
#             bloc (plans/ par defaut), soit <plans>/*.md.
# --dry-run : annonce ce qui bougerait, n'ecrit rien.
#
# Formats de journal, ceux de la convention. Le bloc contexte:convention les declare par
# `journal:`, sinon le script les reconnait lui-meme :
#   date-titre         ## AAAA-MM-JJ titre
#   keep-a-changelog   ## [x.y.z] - AAAA-MM-JJ
#   crochets           [AAAA-MM-JJ] [TYPE] texte, une ligne par entree ou une ligne
#                      suivie de son corps jusqu'a l'entree d'apres
#
# Ordre : un journal du plus ancien au plus recent est REFUSE, code 3. Le tourner
# archiverait les entrees les plus recentes. Remets-le du plus recent au plus ancien.
#
# Plan execute, pour --plans. Un plan l'est quand l'une de ces deux marques existe :
#   - une des 30 premieres lignes du plan porte `Statut : termine` (ou execute, clos,
#     done) ou la banniere `PLAN EXECUTE`, sans negation (non, pas, en cours, partiel)
#   - une ligne de TODOS.md cite `<plans>/<nom>.md` avec termine, execute, clos, done ou
#     [x], et sans case `[ ]` ouverte
# Un plan execute de plus de 20 lignes devient un resume de 20 lignes au plus : titre,
# objectif, registre des ecarts (un titre par ecart), commits. Le texte integral part
# par ctx-archive.sh dans archives/AAAA-MM/plans/<nom>.md, avec en-tete et index. Un plan
# deja resume (marqueur plan-resume) ou de 20 lignes ou moins n'est pas touche.
#
# Idempotent : relance sur un fichier deja tourne, il ne trouve rien a deplacer.
set -euf

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=ctx-commun.sh
. "$DIR/ctx-commun.sh"

ROOT=""
FICHIER="CHANGELOG.md"
GARDER=30
PLAFOND=1500
PLANS=0
DRY=0

aide() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
}

# Une option a valeur sans valeur : message clair et code 2, pas une sortie muette.
valeur() { # <option> <nombre d'arguments restants, option comprise>
  if [ "$2" -lt 2 ]; then
    echo "$1 attend une valeur" >&2
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root)    valeur "$1" $#; ROOT="$2"; shift 2 ;;
    --fichier) valeur "$1" $#; FICHIER="$2"; shift 2 ;;
    --garder)  valeur "$1" $#; GARDER="$2"; shift 2 ;;
    --plafond) valeur "$1" $#; PLAFOND="$2"; shift 2 ;;
    --plans)   PLANS=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) aide; exit 0 ;;
    *) echo "Option inconnue : $1" >&2; exit 2 ;;
  esac
done

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"

version_scripts || exit 1

case "$GARDER" in ''|*[!0-9]*|0) echo "--garder attend un entier superieur a 0" >&2; exit 2 ;; esac
case "$PLAFOND" in ''|*[!0-9]*|0) echo "--plafond attend un entier superieur a 0" >&2; exit 2 ;; esac

TODAY="$(ctx_aujourdhui)"
MOIS_COURANT="${TODAY%-*}"
BT="$(printf '\140')"

ARCH="$(conv_lire archives | sed 's|/*$||')"
[ -n "$ARCH" ] || ARCH="archives"

# Repertoire des plans, cle `plans:` du bloc. Premier mot, sans ./ initial ni / final.
PLANS_DIR="$(conv_lire plans)"
PLANS_DIR="${PLANS_DIR%%[[:space:],]*}"
while [ "${PLANS_DIR#./}" != "$PLANS_DIR" ]; do PLANS_DIR="${PLANS_DIR#./}"; done
while [ "${PLANS_DIR%/}" != "$PLANS_DIR" ]; do PLANS_DIR="${PLANS_DIR%/}"; done
[ -n "$PLANS_DIR" ] || PLANS_DIR="plans"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# =============================================================================
# Mode plans
# =============================================================================

# Raison pour laquelle un plan est execute, ou rien.
plan_execute() { # <fichier>
  local f="$1" l
  l="$(head -n 30 "$f" \
       | grep -Ei '((statut|status|etat|état)[^a-z]*:.*(termin|ex.{1,2}cut|clos|done|complet)|plan (ex.{1,2}cut|termin))' \
       | grep -Eiv '(^|[^a-z])(non|pas|en cours|partiel)([^a-z]|$)' | sed -n '1p' || true)"
  if [ -n "$l" ]; then
    printf 'marque dans l'"'"'en-tete\n'
    return 0
  fi
  if [ -f TODOS.md ]; then
    l="$(grep -F -- "$f" TODOS.md \
         | grep -Ei 'termin|ex.{1,2}cut|clos|done|\[x\]' \
         | grep -Fv '[ ]' \
         | grep -Eiv '(^|[^a-z])(non|pas|en cours|partiel)([^a-z]|$)' | sed -n '1p' || true)"
    if [ -n "$l" ]; then
      printf 'declare termine dans TODOS.md\n'
      return 0
    fi
  fi
  return 0
}

# Titre du plan, premier `# ` hors bloc de code.
plan_titre() { # <fichier> <defaut>
  awk -v d="$2" '/^```/ { f = !f } !f && /^# / { sub(/^# +/, ""); print; ok = 1; exit } END { if (!ok) print d }' "$1"
}

# Premier paragraphe de la section Objectif (ou Contexte, Resume), sur une ligne : les
# lignes se joignent jusqu'a la fin de la phrase, trois au plus.
plan_objectif() { # <fichier>
  awk '
    /^```/ { f = !f }
    f { next }
    /^#+ / {
      if (dans && phrase != "") exit
      dans = ($0 ~ /^## .*(Objectif|Contexte|Résumé|Resume)/)
      next
    }
    /^<!--/ || /^>/ { next }
    /^[ \t]*$/ { if (phrase != "") exit; next }
    dans {
      phrase = (phrase == "" ? $0 : phrase " " $0)
      k++
      if ($0 ~ /[.!?:][ \t]*$/ || k >= 3) exit
    }
    END { if (phrase != "") print phrase }
  ' "$1"
}

# Un ecart par ligne : la premiere ligne de la puce, ou son seul gras de tete en mode court.
plan_ecarts() { # <fichier> <long|court>
  MODE="$2" awk '
    function coupe(s, n,   p, i) {
      if (length(s) <= n) return s
      p = 0
      for (i = 1; i <= n; i++) if (substr(s, i, 1) == " ") p = i
      if (p == 0) return s
      return substr(s, 1, p - 1) " ..."
    }
    /^```/ { f = !f; next }
    f { next }
    /^#+ / {
      match($0, /^#+/); niv = RLENGTH
      if (dans && niv <= nivreg) dans = 0
      if (!dans && $0 ~ /^##+ .*(é|É|e|E)carts/) { dans = 1; nivreg = niv }
      next
    }
    dans {
      if ($0 ~ /^[ \t]*$/ || $0 ~ /^[ \t]/ || $0 ~ /^<!--/) next
      if ($0 ~ /^\|[-: |]*\|?[ \t]*$/) next
      if (ENVIRON["MODE"] == "court" && match($0, /^[-*] \*\*[^*]+\*\*/)) { print substr($0, 1, RLENGTH); next }
      print coupe($0, 160)
    }
  ' "$1"
}

# Lignes qui portent un identifiant de commit : sept a quarante caracteres hexa avec au
# moins un chiffre et une lettre. Chaque identifiant n'est rendu qu'une fois.
plan_commits() { # <fichier>
  awk '
    function coupe(s, n,   p, i) {
      if (length(s) <= n) return s
      p = 0
      for (i = 1; i <= n; i++) if (substr(s, i, 1) == " ") p = i
      if (p == 0) return s
      return substr(s, 1, p - 1) " ..."
    }
    /^```/ { f = !f }
    {
      n = split($0, mot, /[^0-9A-Za-z]/)
      nouveau = 0
      for (i = 1; i <= n; i++) {
        t = mot[i]
        if (length(t) >= 7 && length(t) <= 40 && t ~ /^[0-9a-f]+$/ && t ~ /[0-9]/ && t ~ /[a-f]/ && !(t in vu)) {
          vu[t] = 1; nouveau = 1
        }
      }
      if (nouveau) {
        l = $0
        sub(/^[ \t]+/, "", l)
        if (l !~ /^[-*|]/) l = "- " l
        print coupe(l, 150)
      }
    }
  ' "$1"
}

# Resume de vingt lignes au plus. Le remplacement {{ARCHIVE}} est fait par ctx-archive.sh.
plan_resume() { # <fichier> <sortie> <cases ouvertes>
  local f="$1" out="$2" ouvertes="$3" titre obj nb_e nb_c reste ec cc bloc_fixe
  titre="$(plan_titre "$f" "$(basename "$f" .md)")"
  obj="$(plan_objectif "$f" | sed -n '1p')"
  plan_ecarts "$f" long > "$TMP/ecarts"
  plan_commits "$f" > "$TMP/commits"
  nb_e="$(wc -l < "$TMP/ecarts" | tr -d ' ')"
  nb_c="$(wc -l < "$TMP/commits" | tr -d ' ')"

  # 20 lignes. Fixes : titre et blanc, pointeur, ligne des cases ouvertes si besoin,
  # objectif et son blanc, puis par section un blanc, un titre et un blanc. Le reste est
  # le budget des entrees des deux listes.
  bloc_fixe=3
  if [ "$ouvertes" -gt 0 ]; then bloc_fixe=$((bloc_fixe + 1)); fi
  if [ -n "$obj" ]; then bloc_fixe=$((bloc_fixe + 2)); fi
  if [ "$nb_e" -gt 0 ]; then bloc_fixe=$((bloc_fixe + 3)); fi
  if [ "$nb_c" -gt 0 ]; then bloc_fixe=$((bloc_fixe + 3)); fi
  reste=$((20 - bloc_fixe))
  ec="$nb_e"; cc="$nb_c"
  if [ $((nb_e + nb_c)) -gt "$reste" ]; then
    # trop long : un titre par ecart au lieu de sa premiere ligne
    plan_ecarts "$f" court > "$TMP/ecarts"
    # le registre passe avant les commits, qui gardent deux lignes au moins
    cc=2
    if [ "$cc" -gt "$nb_c" ]; then cc="$nb_c"; fi
    ec=$((reste - cc))
    if [ "$ec" -gt "$nb_e" ]; then
      ec="$nb_e"
      cc=$((reste - ec))
      if [ "$cc" -gt "$nb_c" ]; then cc="$nb_c"; fi
    fi
  fi

  {
    printf '# %s\n\n' "$titre"
    printf '> Plan exécuté, résumé le %s. Texte intégral : %s{{ARCHIVE}}%s. <!-- plan-resume -->\n' "$TODAY" "$BT" "$BT"
    if [ "$ouvertes" -gt 0 ]; then
      printf '> %s case(s) restaient ouvertes, elles sont dans le texte intégral.\n' "$ouvertes"
    fi
    if [ -n "$obj" ]; then
      printf '\n**Objectif.** %s\n' "$obj"
    fi
    if [ "$nb_e" -gt 0 ]; then
      printf '\n## Registre des écarts\n\n'
      if [ "$nb_e" -gt "$ec" ]; then
        head -n $((ec - 1)) "$TMP/ecarts"
        printf -- '- ... et %s autre(s), voir le texte intégral.\n' "$((nb_e - ec + 1))"
      else
        cat "$TMP/ecarts"
      fi
    fi
    if [ "$nb_c" -gt 0 ]; then
      printf '\n## Commits\n\n'
      if [ "$nb_c" -gt "$cc" ]; then
        printf -- '- ... %s plus ancien(s), voir le texte intégral.\n' "$((nb_c - cc + 1))"
        tail -n $((cc - 1)) "$TMP/commits"
      else
        cat "$TMP/commits"
      fi
    fi
  } > "$out"
}

plans_main() {
  local p raison nb ouvertes nom dest fini=0 echec=0 sortie code avert
  echo "Plans executes de $ROOT"
  if [ ! -d "$PLANS_DIR" ]; then
    echo "  pas de repertoire $PLANS_DIR/, rien a faire."
    return 0
  fi
  [ "$DRY" -eq 1 ] && echo "  mode simulation, rien ne sera ecrit"
  echo
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    nom="$(basename "$p")"
    [ "$nom" = "README.md" ] && continue
    nb="$(wc -l < "$p" | tr -d ' ')"
    if grep -q 'plan-resume' "$p"; then
      printf '  = %-38s deja resume\n' "$p"
      continue
    fi
    raison="$(plan_execute "$p")"
    if [ -z "$raison" ]; then
      printf '  . %-38s %s lignes, pas execute, laisse tel quel\n' "$p" "$nb"
      continue
    fi
    if [ "$nb" -le 20 ]; then
      printf '  . %-38s %s lignes, execute mais deja court, laisse tel quel\n' "$p" "$nb"
      continue
    fi
    ouvertes="$(grep -c '\[ \]' "$p" || true)"
    plan_resume "$p" "$TMP/resume-$nom" "${ouvertes:-0}"
    dest="$ARCH/$MOIS_COURANT/$p"
    printf '  - %-38s %s lignes, execute (%s)\n' "$p" "$nb" "$raison"
    printf '      resume de %s lignes, texte integral vers %s\n' \
      "$(wc -l < "$TMP/resume-$nom" | tr -d ' ')" "$dest"
    set +e
    if [ "$DRY" -eq 1 ]; then
      sortie="$(bash "$DIR/ctx-archive.sh" --root "$ROOT" "$p" --raison "plan exécuté, résumé gardé à la même place" \
        --remplace-par "$p" --resume "$TMP/resume-$nom" --dry-run 2>&1)"
    else
      sortie="$(bash "$DIR/ctx-archive.sh" --root "$ROOT" "$p" --raison "plan exécuté, résumé gardé à la même place" \
        --remplace-par "$p" --resume "$TMP/resume-$nom" 2>&1)"
    fi
    code=$?
    set -e
    if [ "$code" -ne 0 ]; then
      echo "      ECHEC de ctx-archive.sh (code $code) :"
      printf '%s\n' "$sortie" | sed 's/^/        /'
      echec=1
    else
      # Un succes de ctx-archive.sh peut porter un avertissement : sans table d'index,
      # le plan est archive sans sa ligne, et la ligne a poser a la main est dite ici.
      avert="$(printf '%s\n' "$sortie" | grep -A1 -E 'Ligne a poser a la main|^ *\[!\]' | grep -v '^--$' || true)"
      if [ -n "$avert" ]; then
        printf '%s\n' "$avert" | sed 's/^ */      /'
      fi
      fini=$((fini + 1))
    fi
  done <<FIN
$(find "$PLANS_DIR" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)
FIN
  echo
  if [ "$DRY" -eq 1 ]; then
    echo "  $fini plan(s) a resumer."
  else
    echo "  $fini plan(s) resume(s) et archive(s)."
    echo
    echo "Rien n'est commite. Verifie avec git status, puis git add les fichiers touches."
  fi
  return "$echec"
}

if [ "$PLANS" -eq 1 ]; then
  plans_main
  exit $?
fi

# =============================================================================
# Mode journal
# =============================================================================

[ -f "$FICHIER" ] || { echo "Journal introuvable : $FICHIER" >&2; exit 1; }

SLUG="$(basename "$FICHIER" .md | tr '[:upper:]' '[:lower:]')"
DEST_DIR="$ARCH/$SLUG"
SENTINELLE='<!-- fin de l'"'"'en-tête -->'
ENTETE=7   # lignes de l'en-tete pose sur un fichier d'archive neuf

# Une entree commence a une ligne qui porte le motif du format, hors bloc de code.
# Ce qui precede la premiere entree est le preambule, ce qui suit une entree jusqu'a
# la suivante lui appartient. Manifeste : numero, date, premiere ligne, derniere ligne.
decouper() { # <format>
  local motif
  motif="$(journal_motif "$1" | sed 's/\[0-9\]{4}/[0-9][0-9][0-9][0-9]/g; s/\[0-9\]{2}/[0-9][0-9]/g')"
  if [ -z "$motif" ]; then
    echo "Format de journal inconnu : $1 (attendus : date-titre, keep-a-changelog, crochets)" >&2
    exit 2
  fi
  MOTIF="$motif" awk '
    BEGIN { mot = ENVIRON["MOTIF"]; n = 0; fence = 0 }
    /^```/ { fence = !fence }
    !fence && $0 ~ mot {
      if (n > 0) fin[n] = NR - 1
      n++
      match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)
      date[n] = substr($0, RSTART, RLENGTH)
      deb[n] = NR
    }
    END {
      if (n > 0) fin[n] = NR
      for (i = 1; i <= n; i++) print i, date[i], deb[i], fin[i]
    }' "$FICHIER" > "$TMP/manifeste"
}

FORMAT="$(journal_detecter "$FICHIER")"
DECLARE="$(conv_journal_format)"
TOTAL=0
if [ -n "$FORMAT" ]; then
  decouper "$FORMAT"
  TOTAL="$(wc -l < "$TMP/manifeste" | tr -d ' ')"
  if [ "$TOTAL" -eq 0 ] && [ -n "$DECLARE" ]; then
    # Le bloc parle du journal du projet, ce fichier-ci peut en etre un autre.
    AUTO="$(CTX_RACINE=/nonexistent journal_detecter "$FICHIER")"
    if [ -n "$AUTO" ] && [ "$AUTO" != "$FORMAT" ]; then
      echo "Le bloc declare journal: $FORMAT, aucune entree de ce format dans $FICHIER."
      FORMAT="$AUTO"
      decouper "$FORMAT"
      TOTAL="$(wc -l < "$TMP/manifeste" | tr -d ' ')"
    fi
  fi
fi

echo "Rotation de $FICHIER"
if [ -z "$FORMAT" ]; then
  echo "  format : aucun reconnu (date-titre, keep-a-changelog, crochets)"
else
  echo "  format : $FORMAT"
fi
echo "  entrees datees : $TOTAL, a garder : $GARDER"

# --- ordre chronologique ------------------------------------------------------
# Le journal garde les N premieres entrees. Range du plus ancien au plus recent, il
# archiverait les plus recentes. On compare chaque entree a la suivante, la majorite
# decide, une entree isolee hors place ne fait pas refuser le journal.
if [ "$TOTAL" -gt 1 ]; then
  SENS="$(awk 'NR > 1 { if ($2 < prev) desc++; else if ($2 > prev) asc++ } { prev = $2 } END { print asc + 0, desc + 0 }' "$TMP/manifeste")"
  ASC="${SENS% *}"
  DESC="${SENS#* }"
  if [ "$ASC" -gt "$DESC" ]; then
    echo >&2
    echo "REFUS : $FICHIER est range dans l'ordre chronologique, du plus ancien au plus recent." >&2
    echo "  ($ASC passages en avant dans le temps contre $DESC en arriere.)" >&2
    echo "  La rotation garde les $GARDER premieres entrees du fichier et archive le reste." >&2
    echo "  Ici elle archiverait les plus recentes et garderait les plus vieilles." >&2
    echo "  Remets le journal du plus recent en haut au plus ancien en bas, puis relance." >&2
    exit 3
  fi
fi

if [ "$TOTAL" -le "$GARDER" ]; then
  echo "  rien a deplacer."
  exit 0
fi
A_DEPLACER=$((TOTAL - GARDER))
echo "  a deplacer : $A_DEPLACER, vers $DEST_DIR/AAAA-MM.md"
[ "$DRY" -eq 1 ] && echo "  mode simulation, rien ne sera ecrit"
echo

# --- regroupement par mois ----------------------------------------------------
nom_archive() { # <mois> <rang>
  if [ "$2" -le 1 ]; then
    printf '%s/%s.md\n' "$DEST_DIR" "$1"
  else
    printf '%s/%s-%s.md\n' "$DEST_DIR" "$1" "$2"
  fi
}

lignes_entree() { # <numero>
  awk -v i="$1" '$1 == i { print $4 - $3 + 1 }' "$TMP/manifeste"
}

lire_entree() { # <numero>
  local a b
  a="$(awk -v i="$1" '$1 == i { print $3 }' "$TMP/manifeste")"
  b="$(awk -v i="$1" '$1 == i { print $4 }' "$TMP/manifeste")"
  sed -n "${a},${b}p" "$FICHIER"
}

MOIS="$(awk -v g="$GARDER" '$1 > g { print substr($2, 1, 7) }' "$TMP/manifeste" | awk '!vu[$0]++')"
CREES=""
for m in $MOIS; do
  ids="$(awk -v g="$GARDER" -v m="$m" '$1 > g && substr($2, 1, 7) == m { print $1 }' "$TMP/manifeste" | tr '\n' ' ')"
  total_m=0
  for i in $ids; do total_m=$((total_m + $(lignes_entree "$i"))); done

  # fichier de tete de la chaine existante du mois : le rang le plus haut, le plus recent
  k=1
  while [ -f "$(nom_archive "$m" $((k + 1)))" ]; do k=$((k + 1)); done
  existe=0
  [ -f "$(nom_archive "$m" "$k")" ] && existe=1

  : > "$TMP/plan-$m"
  place=0
  deborde=0
  if [ "$existe" -eq 1 ]; then
    l0="$(wc -l < "$(nom_archive "$m" "$k")" | tr -d ' ')"
    if [ $((l0 + total_m)) -le "$PLAFOND" ]; then
      echo "$k|ajout|$ids" >> "$TMP/plan-$m"
      place=1
    else
      deborde=1
      k=$((k + 1))
    fi
  fi
  if [ "$place" -eq 0 ]; then
    # du plus ancien au plus recent, le plus ancien dans le fichier de rang le plus bas
    grp=""
    lg="$ENTETE"
    for i in $(printf '%s\n' $ids | sort -rn); do
      nb="$(lignes_entree "$i")"
      if [ -n "$grp" ] && [ $((lg + nb)) -gt "$PLAFOND" ]; then
        echo "$k|nouveau|$grp" >> "$TMP/plan-$m"
        k=$((k + 1))
        grp=""
        lg="$ENTETE"
      fi
      grp="$i $grp"
      lg=$((lg + nb))
    done
    if [ -n "$grp" ]; then echo "$k|nouveau|$grp" >> "$TMP/plan-$m"; fi
  fi

  nb_fichiers="$(wc -l < "$TMP/plan-$m" | tr -d ' ')"
  if [ "$nb_fichiers" -gt 1 ] || [ "$deborde" -eq 1 ]; then
    echo "  ! $m : $total_m lignes a poser, un fichier ne depasse pas $PLAFOND lignes, le mois se coupe"
  fi

  while IFS='|' read -r k mode ids_f; do
    dest="$(nom_archive "$m" "$k")"
    bloc="$TMP/bloc"
    : > "$bloc"
    nb=0
    for i in $ids_f; do
      lire_entree "$i" >> "$bloc"
      nb=$((nb + 1))
    done
    if [ "$mode" = "ajout" ]; then
      printf '  ~ %-44s %s entree(s) ajoutee(s) en tete\n' "$dest" "$nb"
    else
      printf '  + %-44s %s entree(s), fichier cree\n' "$dest" "$nb"
    fi
    [ "$DRY" -eq 1 ] && continue
    mkdir -p "$DEST_DIR"
    if [ "$mode" = "ajout" ]; then
      # en-tete conserve, entrees neuves d'abord, puis les anciennes
      tete="$(grep -nxF -- "$SENTINELLE" "$dest" | sed -n '1p' | cut -d: -f1 || true)"
      if [ -z "$tete" ]; then
        tete="$(awk '/^>/ || /^[ \t]*$/ { n++; next } { exit } END { print n + 0 }' "$dest")"
      fi
      {
        if [ "$tete" -gt 0 ]; then sed -n "1,${tete}p" "$dest"; fi
        echo
        cat "$bloc"
        if [ "$tete" -gt 0 ]; then sed "1,${tete}d" "$dest"; else cat "$dest"; fi
      } > "$TMP/dest"
    else
      partie=""
      [ "$k" -gt 1 ] && partie=" (partie $k)"
      {
        echo "> ⚠️ **ARCHIVÉ**, entrées de $BT$FICHIER$BT déplacées par rotation le $TODAY, gardées pour l'historique."
        echo "> **Origine** : $BT$FICHIER$BT"
        echo "> **Mois** : $m$partie"
        echo "> **Ne pas utiliser comme source de vérité.** L'état courant est dans les piliers de la racine."
        echo "$SENTINELLE"
        echo
        cat "$bloc"
      } > "$TMP/dest"
      CREES="$CREES $dest"
    fi
    mv "$TMP/dest" "$dest"
  done < "$TMP/plan-$m"
done

# --- reecriture du journal ----------------------------------------------------
PLUS_ANCIENNE_GARDEE="$(awk -v g="$GARDER" '$1 == g { print $2 }' "$TMP/manifeste")"
DEBUT_PREMIERE="$(awk '$1 == 1 { print $3 }' "$TMP/manifeste")"
FIN_GARDEE="$(awk -v g="$GARDER" '$1 == g { print $4 }' "$TMP/manifeste")"
if [ "$DRY" -eq 0 ]; then
  : > "$TMP/preambule"
  if [ "$DEBUT_PREMIERE" -gt 1 ]; then
    sed -n "1,$((DEBUT_PREMIERE - 1))p" "$FICHIER" | grep -v '^> Entrées antérieures au ' > "$TMP/preambule" || true
  fi
  {
    printf '%s\n' "$(cat "$TMP/preambule")"
    echo
    echo "> Entrées antérieures au $PLUS_ANCIENNE_GARDEE : $BT$DEST_DIR/$BT, un fichier par mois, jamais lues en reprise."
    echo
    sed -n "${DEBUT_PREMIERE},${FIN_GARDEE}p" "$FICHIER"
  } > "$TMP/journal"
  mv "$TMP/journal" "$FICHIER"
fi
echo
echo "  $FICHIER garde $GARDER entrees, la plus ancienne du $PLUS_ANCIENNE_GARDEE."

# --- index des archives -------------------------------------------------------
# Une ligne par fichier cree, posee a sa creation. Un fichier deja indexe ne recoit
# pas de seconde ligne.
if [ -n "$CREES" ] && [ "$DRY" -eq 0 ]; then
  if [ -f "$ARCH/README.md" ] && grep -q '^|---' "$ARCH/README.md"; then
    for dest in $CREES; do
      if grep -qF -- "$BT$dest$BT" "$ARCH/README.md"; then continue; fi
      ligne="| $TODAY | $BT$FICHIER$BT | $BT$dest$BT | rotation du journal, entrées du mois $(basename "$dest" .md) | $BT$FICHIER$BT |"
      awk -v l="$ligne" 'BEGIN { fait = 0 } { print } /^\|---/ && !fait { print l; fait = 1 }' "$ARCH/README.md" > "$TMP/readme"
      mv "$TMP/readme" "$ARCH/README.md"
      echo "  index : ligne ajoutee dans $ARCH/README.md pour $dest"
    done
  else
    echo "  index : $ARCH/README.md absent ou sans table, ajouter a la main une ligne par fichier cree :"
    for dest in $CREES; do echo "          $dest"; done
  fi
fi

echo
if [ "$DRY" -eq 1 ]; then
  echo "Simulation terminee, rien n'a ete ecrit."
else
  echo "Rien n'est commite. Verifie avec git status, puis git add les fichiers touches."
fi
