#!/usr/bin/env bash
#
# ctx-init.sh : installe la convention de contexte dans un projet.
#
# Non destructif. Un fichier qui existe deja n'est JAMAIS touche.
# Usage :
#   bash ctx-init.sh [--root <chemin>] [--profil <profil>] [--dry-run] [--with-claude]
#   bash ctx-init.sh --zone <repertoire> [--with-claude] [--dry-run]
#
# --zone : pose une carte de zone, <repertoire>/CODEMAP.md, depuis le gabarit. Avec
#          --with-claude, pose aussi <repertoire>/CLAUDE.md, les regles de la zone.
#          Ne touche pas aux piliers de la racine.
#
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TPL="$SKILL_DIR/templates"

. "$SCRIPT_DIR/ctx-commun.sh"

ROOT=""
PROFIL=""
ZONE=""
DRY=0
WITH_CLAUDE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --root)        ROOT="${2:-}"; shift 2 ;;
    --profil)      PROFIL="${2:-}"; shift 2 ;;
    --zone)        ZONE="${2:-}"; shift 2 ;;
    --dry-run)     DRY=1; shift ;;
    --with-claude) WITH_CLAUDE=1; shift ;;
    -h|--help)
      sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Option inconnue : $1" >&2; exit 2 ;;
  esac
done

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
[ -d "$ROOT" ] || { echo "Racine introuvable : $ROOT" >&2; exit 1; }
ROOT="$(cd "$ROOT" && pwd)"

# Un bloc plus recent que ces scripts : on refuse avant d'ecrire quoi que ce soit.
CTX_RACINE="$ROOT"
version_scripts || exit 1

DATE="$(ctx_aujourdhui)"
PROJECT_NAME="$(basename "$ROOT")"

# --- detection du profil ------------------------------------------------------
# Une entree de la racine, a la casse pres. Sur un systeme de fichiers insensible a la casse
# (macOS par defaut), `[ -d packages ]` repond oui pour le Packages/ d'un projet Unity.
a_entree() { # <racine> <nom>
  # Le glob rend les noms tels qu'ecrits sur le disque, la comparaison se fait donc a la casse pres.
  local e
  for e in "$1"/* "$1"/.[!.]*; do
    [ "${e##*/}" = "$2" ] && return 0
  done
  return 1
}

# Au moins un fichier de la racine qui suit le motif (glob shell).
a_motif() { # <racine> <motif>
  local f
  for f in "$1"/$2; do [ -e "$f" ] && return 0; done
  return 1
}

# L'ordre compte : du plus specifique au plus general. Un moteur de jeu ou une app mobile
# porte aussi un package.json ou un Cargo.toml, ils passent donc avant app et monorepo.
detect_profil() {
  local r="$1"
  if a_motif "$r" '.claude-plugin/plugin.json' || [ -f "$r/SKILL.md" ] || [ -d "$r/.claude/skills" ] \
     || [ -f "$r/plugin.json" ] || a_motif "$r" 'skills/*/SKILL.md'; then
    echo outillage-agent; return
  fi
  if [ -f "$r/ProjectSettings/ProjectVersion.txt" ] || [ -f "$r/project.godot" ] \
     || a_motif "$r" '*.uproject'; then
    echo jeu; return
  fi
  if [ -f "$r/pubspec.yaml" ] || { a_entree "$r" android && a_entree "$r" ios; } \
     || a_motif "$r" '*.xcodeproj' || [ -f "$r/app/src/main/AndroidManifest.xml" ]; then
    echo mobile; return
  fi
  if [ -f "$r/pnpm-workspace.yaml" ] || [ -f "$r/turbo.json" ] || [ -f "$r/go.work" ] \
     || [ -f "$r/nx.json" ] || [ -f "$r/lerna.json" ] || a_entree "$r" packages || a_entree "$r" apps; then
    echo monorepo; return
  fi
  if [ -d "$r/src-tauri" ] || { [ -f "$r/package.json" ] && grep -q '"electron"' "$r/package.json" 2>/dev/null; }; then
    echo desktop; return
  fi
  if a_entree "$r" terraform || a_entree "$r" ansible || a_entree "$r" k8s \
     || a_motif "$r" '*.tf' || [ -f "$r/Chart.yaml" ]; then
    echo infra; return
  fi
  if a_entree "$r" notebooks || [ -f "$r/dvc.yaml" ] || a_motif "$r" '*.ipynb'; then
    echo data; return
  fi
  # Une bibliotheque : un point d'entree de lib sans programme, ou un package qui exporte
  # sans se lancer.
  if { [ -f "$r/Cargo.toml" ] && [ -f "$r/src/lib.rs" ] && [ ! -f "$r/src/main.rs" ]; } \
     || { [ -f "$r/package.json" ] && grep -qE '"(exports|types)"[[:space:]]*:' "$r/package.json" 2>/dev/null \
          && ! grep -qE '"(start|dev)"[[:space:]]*:' "$r/package.json" 2>/dev/null; }; then
    echo lib; return
  fi
  if [ -f "$r/package.json" ] || [ -f "$r/pyproject.toml" ] || [ -f "$r/go.mod" ] \
     || [ -f "$r/Cargo.toml" ] || [ -f "$r/manage.py" ] || [ -f "$r/pom.xml" ] \
     || [ -f "$r/build.gradle" ] || [ -f "$r/build.gradle.kts" ] || [ -f "$r/composer.json" ] \
     || [ -f "$r/Gemfile" ] || [ -f "$r/mix.exs" ] || [ -f "$r/Package.swift" ] \
     || [ -f "$r/deno.json" ] || [ -f "$r/CMakeLists.txt" ] || a_motif "$r" '*.sln' \
     || a_motif "$r" '*.csproj' || [ -f "$r/requirements.txt" ]; then
    echo app; return
  fi
  if a_entree "$r" content || a_entree "$r" posts; then
    echo contenu; return
  fi
  echo non-technique
}

# --- taille du projet, en fichiers hors dependances ---------------------------
# Les memes exclusions que ctx-audit.sh, les deux doivent compter pareil.
detect_taille() {
  local r="$1" n
  # set -f : exclusions_prune rend des motifs que le shell ne doit pas developper. En elagage,
  # find ne descend pas dans un Library/ de moteur ou un node_modules.
  n="$(cd "$r" && set -f && find . $(exclusions_prune) -o -type f -print 2>/dev/null | wc -l | tr -d ' ')"
  if   [ "$n" -lt 150 ]; then echo "petite $n"
  elif [ "$n" -le 600 ]; then echo "moyenne $n"
  else echo "grande $n"; fi
}

[ -n "$PROFIL" ] || PROFIL="$(detect_profil "$ROOT")"
# La liste d'elagage se calcule une fois pour la racine visee, la taille et la ligne
# « elagage » plus bas la relisent en memoire.
CTX_RACINE="$ROOT" exclusions_charger
TAILLE_ET_NB="$(detect_taille "$ROOT")"
TAILLE="${TAILLE_ET_NB%% *}"
NB_FICHIERS="${TAILLE_ET_NB#* }"

# --- le terrain ---------------------------------------------------------------
# On se greffe sur ce qui existe. Un projet deja documente a son repertoire de
# doc, son porteur de regles et parfois une autre convention d'agent. Poser des
# gabarits vides a cote produirait deux sources de verite le premier jour.
DOCS_DIR=""
for d in docs doc documentation; do
  [ -d "$ROOT/$d" ] && { DOCS_DIR="$d"; break; }
done
DOCS_EXISTAIT=1
[ -n "$DOCS_DIR" ] || { DOCS_DIR="docs"; DOCS_EXISTAIT=0; }

ARCHIVES_DIR=""
for d in archives archive; do
  [ -d "$ROOT/$d" ] && { ARCHIVES_DIR="$d"; break; }
done
[ -n "$ARCHIVES_DIR" ] || ARCHIVES_DIR="archives"

# Le porteur des regles. CLAUDE.md si present, sinon AGENTS.md si present, sinon
# CLAUDE.md a creer. Un depot lu par Codex seul n'a pas a recevoir un CLAUDE.md.
REGLES="CLAUDE.md"
if [ ! -f "$ROOT/CLAUDE.md" ] && [ -f "$ROOT/AGENTS.md" ]; then
  REGLES="AGENTS.md"
fi

# Les quatre sous-repertoires de docs/ ne se creent que si le repertoire est neuf,
# vide, ou deja de cette forme. Sinon on laisse la structure existante tranquille.
CREER_SOUS_DOCS=1
if [ "$DOCS_EXISTAIT" -eq 1 ]; then
  CREER_SOUS_DOCS=0
  for d in modules features ops decisions; do
    [ -d "$ROOT/$DOCS_DIR/$d" ] && CREER_SOUS_DOCS=1
  done
  [ -z "$(ls -A "$ROOT/$DOCS_DIR" 2>/dev/null)" ] && CREER_SOUS_DOCS=1
fi

ADR_DIRS=""
for d in adr "$DOCS_DIR/adr" "$DOCS_DIR/decisions" "$DOCS_DIR/architecture/decisions"; do
  [ -d "$ROOT/$d" ] && ADR_DIRS="$ADR_DIRS $d"
done
CONCUR=""
for c in AGENTS.md GEMINI.md .cursorrules .clinerules .windsurfrules CONVENTIONS.md \
         .github/copilot-instructions.md .cursor/rules memory-bank .roo MEMORY.md; do
  [ "$c" = "$REGLES" ] && continue
  [ -e "$ROOT/$c" ] && CONCUR="$CONCUR $c"
done

# La ou vont les decisions : le repertoire existant s'il y en a un, sinon celui
# de la convention.
DECISIONS="$DOCS_DIR/decisions"
for d in $ADR_DIRS; do DECISIONS="$d"; break; done
RACINE_MD="$(cd "$ROOT" && find . -maxdepth 1 -name '*.md' 2>/dev/null | sed 's|^\./||' \
  | grep -vE '^(CODEMAP|TODOS|CHANGELOG|CLAUDE|AGENTS|README|MEMORY)\.md$' | sort | tr '\n' ' ' || true)"

# --- helpers ------------------------------------------------------------------
CREATED=0
SKIPPED=0

render() { # <source> <destination>
  local src="$1" dst="$2"
  if [ -e "$dst" ]; then
    printf '  = %-24s deja present, non touche\n' "${dst#$ROOT/}"
    SKIPPED=$((SKIPPED + 1))
    return
  fi
  printf '  + %-24s cree\n' "${dst#$ROOT/}"
  CREATED=$((CREATED + 1))
  [ "$DRY" -eq 1 ] && return
  mkdir -p "$(dirname "$dst")"
  sed -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
      -e "s|{{DATE}}|$DATE|g" \
      -e "s|{{PROFIL}}|$PROFIL|g" \
      -e "s|{{ZONE}}|$ZONE|g" \
      -e "s|{{DOCS}}|$DOCS_DIR/|g" \
      -e "s|{{ARCHIVES}}|$ARCHIVES_DIR/|g" \
      "$src" > "$dst"
}

mkdirp() { # <chemin>
  if [ -d "$1" ]; then return; fi
  printf '  + %-24s cree\n' "${1#$ROOT/}/"
  CREATED=$((CREATED + 1))
  [ "$DRY" -eq 1 ] && return
  mkdir -p "$1"
}

# --- mode zone ----------------------------------------------------------------
if [ -n "$ZONE" ]; then
  ZONE="${ZONE%/}"
  [ -d "$ROOT/$ZONE" ] || { echo "Zone introuvable : $ROOT/$ZONE" >&2; exit 1; }
  echo "Carte de zone"
  echo "  racine  : $ROOT"
  echo "  zone    : $ZONE"
  [ "$DRY" -eq 1 ] && echo "  mode    : simulation, rien ne sera ecrit"
  echo
  render "$TPL/CODEMAP-zone.md" "$ROOT/$ZONE/CODEMAP.md"
  if [ "$WITH_CLAUDE" -eq 1 ]; then
    render "$TPL/CLAUDE-zone.md" "$ROOT/$ZONE/CLAUDE.md"
  else
    echo "  . $ZONE/CLAUDE.md non cree, relance avec --with-claude si la zone a des regles a elle"
  fi
  cat <<EOF

A faire maintenant :
  1. Remplir $ZONE/CODEMAP.md depuis le code reel de la zone : entrees, flux, pieges.
  2. Descendre dans cette carte les zones sensibles du CODEMAP de la racine qui parlent de
     $ZONE, et les commandes propres a la zone. Laisser un pointeur, pas une copie.
  3. Ajouter la zone a la table « Zones » du CODEMAP de la racine.
EOF
  exit 0
fi

# --- execution ----------------------------------------------------------------
echo "Convention de contexte"
echo "  racine  : $ROOT"
echo "  projet  : $PROJECT_NAME"
echo "  profil  : $PROFIL"
echo "  taille  : $TAILLE, $NB_FICHIERS fichiers hors dependances"
# Un elagage se nomme : ce qui ne compte pas dans la taille ci-dessus, au-dela de la liste fixe.
EL_NOMS="$(exclusions_noms_groupes | awk -F'\t' '
  $1 == "plafond" { p = $3 " racine(s) de moteur au-dela du plafond de 20"; next }
  { k = $1 ($2 != "-" && $2 != "." ? " (" $2 "/)" : "")
    if (!(k in l)) { o[++n] = k; l[k] = $3 } else l[k] = l[k] ", " $3 }
  END { for (i = 1; i <= n; i++) printf "%s%s %s", (i > 1 ? " ; " : ""), o[i], l[o[i]]
        if (p != "") printf "%s%s", (n > 0 ? " ; " : ""), p }')"
[ -z "$EL_NOMS" ] || echo "  elagage : $EL_NOMS"
[ "$DRY" -eq 1 ] && echo "  mode    : simulation, rien ne sera ecrit"
echo

echo "Le terrain, ce sur quoi on se greffe"
if [ "$DOCS_EXISTAIT" -eq 1 ]; then
  echo "  = $DOCS_DIR/ existe deja, la convention l'adopte au lieu d'en creer un autre"
  [ "$CREER_SOUS_DOCS" -eq 0 ] \
    && echo "    sa structure n'est pas celle de la convention, les sous-repertoires ne seront pas crees"
else
  echo "  . aucune documentation existante, $DOCS_DIR/ va etre cree"
fi
echo "  . porteur des regles : $REGLES"
[ -n "$ADR_DIRS" ] && echo "  = decisions deja quelque part :$ADR_DIRS"
[ -n "$RACINE_MD" ] && echo "  = markdown a la racine, hors kit : $RACINE_MD"
if [ -n "$CONCUR" ]; then
  echo "  ! conventions ou memoires concurrentes :$CONCUR"
  echo "    a traiter, sinon deux sources de verite. Voir la fin de ce message."
fi
echo

echo "Piliers"
render "$TPL/CODEMAP.md"   "$ROOT/CODEMAP.md"
render "$TPL/TODOS.md"     "$ROOT/TODOS.md"
render "$TPL/CHANGELOG.md" "$ROOT/CHANGELOG.md"
if [ "$DRY" -eq 1 ] && [ ! -e "$ROOT/CODEMAP.md" ]; then
  echo "  bloc de convention que le CODEMAP recevra :"
  sed -n '/<!-- contexte:convention/,/^-->/p' "$TPL/CODEMAP.md" \
    | sed -e "s|{{PROFIL}}|$PROFIL|g" -e "s|{{DOCS}}|$DOCS_DIR/|g" \
          -e "s|{{ARCHIVES}}|$ARCHIVES_DIR/|g" -e 's/^/    /'
fi

echo
echo "Documentation"
if [ "$CREER_SOUS_DOCS" -eq 1 ]; then
  mkdirp "$ROOT/$DOCS_DIR/modules"
  mkdirp "$ROOT/$DOCS_DIR/features"
  mkdirp "$ROOT/$DOCS_DIR/ops"
  mkdirp "$ROOT/$DOCS_DIR/decisions"
else
  mkdirp "$ROOT/$DOCS_DIR"
  echo "  = sous-repertoires laisses tels quels, la structure existante fait foi"
fi
render "$TPL/docs/README.md" "$ROOT/$DOCS_DIR/README.md"

echo
echo "Archives"
render "$TPL/archives/README.md" "$ROOT/$ARCHIVES_DIR/README.md"

echo
echo "Regles projet"
if [ -f "$ROOT/$REGLES" ]; then
  if grep -q "Convention de contexte" "$ROOT/$REGLES" 2>/dev/null; then
    printf '  = %-24s contient deja la convention\n' "$REGLES"
    if ! grep -qE "(fstack|clawd-stack):orchestration" "$ROOT/$REGLES" 2>/dev/null \
       && grep -q "fstack:orchestration" "$TPL/CLAUDE-snippet.md" 2>/dev/null; then
      printf '  ~ %-24s trois lignes d orchestration ajoutees a la fin\n' "$REGLES"
      if [ "$DRY" -eq 0 ]; then
        printf '\n' >> "$ROOT/$REGLES"
        sed -n '/fstack:orchestration/,$p' "$TPL/CLAUDE-snippet.md" >> "$ROOT/$REGLES"
      fi
    fi
  elif [ "$WITH_CLAUDE" -eq 1 ]; then
    printf '  ~ %-24s bloc de convention ajoute a la fin\n' "$REGLES"
    if [ "$DRY" -eq 0 ]; then
      printf '\n' >> "$ROOT/$REGLES"
      sed -e '/^<!--$/,/^-->$/d' \
          -e "s|docs/README.md|$DOCS_DIR/README.md|g" \
          -e "s|docs/decisions/|$DOCS_DIR/decisions/|g" \
          -e "s|\`archives/\`|\`$ARCHIVES_DIR/\`|g" \
          "$TPL/CLAUDE-snippet.md" >> "$ROOT/$REGLES"
    fi
  else
    echo "  ! $REGLES existe mais ne mentionne pas la convention."
    echo "    Relance avec --with-claude, ou colle a la main le bloc de :"
    echo "    $TPL/CLAUDE-snippet.md"
  fi
else
  printf '  + %-24s cree\n' "$REGLES"
  CREATED=$((CREATED + 1))
  if [ "$DRY" -eq 0 ]; then
    {
      echo "# $REGLES, $PROJECT_NAME"
      echo
      sed -e '/^<!--$/,/^-->$/d' \
          -e "s|docs/README.md|$DOCS_DIR/README.md|g" \
          -e "s|docs/decisions/|$DOCS_DIR/decisions/|g" \
          -e "s|\`archives/\`|\`$ARCHIVES_DIR/\`|g" \
          "$TPL/CLAUDE-snippet.md"
    } > "$ROOT/$REGLES"
  fi
fi

echo
echo "Bilan : $CREATED cree(s), $SKIPPED conserve(s)."
cat <<EOF

A faire maintenant, les gabarits sont vides et ne servent a rien en l etat :
  1. Lire le projet avant d ecrire : arborescence, points d entree, build, CI, derniers commits.
EOF
if [ -n "$RACINE_MD" ] || [ "$DOCS_EXISTAIT" -eq 1 ]; then
  cat <<EOF
  2. Ranger la doc qui existe deja. Chaque document a un proprietaire dans la convention :
     une carte va au CODEMAP, un etat va a TODOS, un historique au CHANGELOG, une decision
     dans $DECISIONS/, le reste en fiche $DOCS_DIR/. Ce qui est faux part en archive,
     par ctx-archive.sh, jamais par une suppression.
  3. Remplir CODEMAP.md avec la carte reelle, en pointant vers ce qui existe au lieu de le recopier.
EOF
else
  cat <<EOF
  2. Verifier le bloc contexte:convention en tete du CODEMAP, le script a pose le profil
     et les chemins detectes. Ce bloc rend la convention auto-descriptive.
  3. Remplir CODEMAP.md avec la carte reelle.
EOF
fi
cat <<EOF
  4. Remplir TODOS.md avec l etat reel, puis le bloc "Etat a la reprise", 40 lignes au plus.
  5. Creer les fiches de $DOCS_DIR/ pour ce qui le merite, le critere est dans
     $SKILL_DIR/references/DOCS-SYSTEM.md. Pas de fiche vide, pas de fiche pour tout.
  6. Mettre dans $REGLES ce qui doit etre vrai a chaque instant, et rien d autre.
     Ni etat, ni recit, ni date d evenement. Cible 100 lignes.
EOF
if [ "$TAILLE" = grande ]; then
  cat <<EOF
  7. Le projet est GRAND. Le CODEMAP de la racine est un index qui pointe, pas une carte
     complete. Poser une carte par zone des maintenant, les candidates sont dans la section
     10 de l audit :
       bash $SCRIPT_DIR/ctx-audit.sh --budget
       bash $SCRIPT_DIR/ctx-init.sh --zone <repertoire>
EOF
fi
if [ -n "$CONCUR" ]; then
  cat <<EOF

Conventions concurrentes trouvees :$CONCUR
  Deux sources de verite divergent toujours, et rien ne le signale au moment ou ça arrive.
  Pour chacune, une seule question : qui fait foi ? Celle qui perd est archivee, avec sa raison.
  Cas particuliers. Un AGENTS.md a cote d un CLAUDE.md ne se lit pas par les memes agents,
  le raccord est une ligne @AGENTS.md en tete du CLAUDE.md. Un MEMORY.md vient d une version
  anterieure de cette convention, son contenu se repartit : decisions vers $DOCS_DIR/decisions/,
  pieges vers la fiche du module, preferences vers $REGLES, environnement vers le CODEMAP.
EOF
fi
echo
echo "Verifier la derive et le budget a tout moment : bash $SCRIPT_DIR/ctx-audit.sh"
echo "Chercher dans les archives sans les charger : bash $SCRIPT_DIR/ctx-archeo.sh <motif>"
