#!/usr/bin/env bash
#
# ctx-commun.sh : bibliotheque sourcee par les scripts ctx-*.sh. Ne s'execute pas seule.
#
# Usage : . "$(dirname "$0")/ctx-commun.sh"
# Les fonctions lisent depuis le repertoire courant, ou depuis $CTX_RACINE si elle est posee.
# Le bloc lu est celui de <!-- contexte:convention ... -->, une ligne `cle: valeur` a la fois.
#
#   conv_trouver              chemin du premier .md racine qui porte le bloc, ou rien
#   conv_lire <cle>           valeur brute de la ligne `cle: valeur`, ou rien
#   conv_version              0 sans bloc, 4 pour un bloc sans version:, sinon la valeur
#   conv_seuil <fic> <def>    seuil de `seuils: A=600, B=250` pour <fic>, sinon <def>
#   conv_exception <t> <chem> code 0 si `exceptions: t=motif, ...` couvre <chem> (glob shell)
#   conv_journal_format       valeur de `journal:`, ou rien
#   journal_motif <format>    motif ERE d'un titre d'entree : date-titre, keep-a-changelog, crochets
#   journal_detecter <fic>    format declare par `journal:`, sinon celui trouve dans <fic>, ou rien
#   exclusions_find           repertoires elagues, sous forme d'arguments pour find : le genere lourd
#                             (liste, CACHEDIR.TAG, moteurs de jeu) et `ignorer:`, jamais le gitignore
#   exclusions_charger        calcule cette liste une fois dans le shell principal (les $(...) la relisent)
#   exclusions_noms           ce qui s'elague en plus de la liste fixe : `categorie<TAB>racine<TAB>detail`
#   exclusions_noms_groupes   les memes noms, un par moteur et par racine, avec leurs dossiers
#   exclusions_compter_ignorer <glob>   nombre de fichiers qu'un glob de `ignorer:` fait sauter
#   sous_modules              chemins des sous-modules, lus dans .gitmodules
#   version_scripts           code 1 et message si le bloc est plus recent que CTX_VERSION
#   conv_charger              lit le bloc une fois et le garde en memoire pour les appels suivants
#   ctx_aujourdhui            date du jour AAAA-MM-JJ, ou $CTX_AUJOURDHUI si elle est posee (tests)
#   ctx_epoch <AAAA-MM-JJ>    secondes depuis 1970, BSD d'abord puis GNU, rien si illisible
#   ctx_jours_depuis <date>   jours entre <date> et ctx_aujourdhui, rien si illisible
#
# Les fonctions rendent toujours 0 sauf conv_exception et version_scripts, pour ne pas
# tuer un appelant sous set -e.

CTX_VERSION=5

_ctx_racine() {
  printf '%s\n' "${CTX_RACINE:-.}"
}

# Bloc de convention : les lignes entre l'ouverture et la fermeture. Apres conv_charger,
# le bloc vient de la memoire : un audit qui interroge le bloc par fiche ne relit plus le
# fichier a chaque appel. La variable traverse les sous-shells $(...), c'est voulu.
_conv_bloc() {
  if [ "${CTX_BLOC_CHARGE:-0}" = 1 ]; then
    if [ -n "${CTX_BLOC_CACHE:-}" ]; then printf '%s\n' "$CTX_BLOC_CACHE"; fi
    return 0
  fi
  _conv_bloc_lire
}

conv_charger() {
  CTX_BLOC_CHARGE=0
  CTX_BLOC_CACHE="$(_conv_bloc_lire)"
  CTX_BLOC_CHARGE=1
  return 0
}

_conv_bloc_lire() {
  local f
  f="$(conv_trouver)"
  if [ -n "$f" ]; then
    # Un bloc ouvert et ferme sur la meme ligne est vide, on ne lit pas la suite du fichier.
    awk '/<!-- contexte:convention/ { if ($0 ~ /contexte:convention.*-->/) exit; dedans=1; next }
         dedans && /-->/ {exit}
         dedans {print}' "$f"
  fi
  return 0
}

# Liste `a=b, c=d` en une entree par ligne.
_conv_entrees() { # <cle>
  conv_lire "$1" | tr ',' '\n'
  return 0
}

_conv_trim() {
  sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

conv_trouver() {
  local r f
  r="$(_ctx_racine)"
  for f in CODEMAP.md CLAUDE.md AGENTS.md; do
    if [ -f "$r/$f" ] && grep -q '<!-- contexte:convention' "$r/$f" 2>/dev/null; then
      if [ "$r" = "." ]; then printf '%s\n' "$f"; else printf '%s\n' "$r/$f"; fi
      return 0
    fi
  done
  # find et non un glob : les appelants tournent sous set -f, ou ./*.md resterait litteral.
  for f in $(find "$r" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sed 's|.*/||' | LC_ALL=C sort); do
    case "$f" in CODEMAP.md|CLAUDE.md|AGENTS.md) continue ;; esac
    if grep -q '<!-- contexte:convention' "$r/$f" 2>/dev/null; then
      if [ "$r" = "." ]; then printf '%s\n' "$f"; else printf '%s\n' "$r/$f"; fi
      return 0
    fi
  done
  return 0
}

conv_lire() { # <cle>
  local cle="$1"
  _conv_bloc | awk -v k="$cle" '
    !vu && index($0, k ":") == 1 {
      v = substr($0, length(k) + 2)
      sub(/^[ \t]+/, "", v); sub(/[ \t\r]+$/, "", v)
      print v; vu = 1
    }'
  return 0
}

conv_version() {
  local f v
  f="$(conv_trouver)"
  if [ -z "$f" ]; then echo 0; return 0; fi
  v="$(conv_lire version)"
  if [ -z "$v" ]; then echo 4; else echo "$v"; fi
  return 0
}

conv_seuil() { # <fichier> <defaut>
  local fic="$1" defaut="$2" e nom val
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    nom="$(printf '%s' "${e%%=*}" | _conv_trim)"
    val="$(printf '%s' "${e#*=}" | _conv_trim)"
    case "$val" in ''|*[!0-9]*) continue ;; esac
    if [ "$nom" = "$fic" ]; then echo "$val"; return 0; fi
  done <<FIN
$(_conv_entrees seuils)
FIN
  echo "$defaut"
  return 0
}

conv_exception() { # <type> <chemin>
  local type="$1" chemin="${2#./}" e t motif
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    t="$(printf '%s' "${e%%=*}" | _conv_trim)"
    motif="$(printf '%s' "${e#*=}" | _conv_trim)"
    [ "$t" = "$type" ] || continue
    [ -n "$motif" ] || continue
    # dans un case, * couvre aussi les /, donc ** et * se valent ici
    # shellcheck disable=SC2254
    case "$chemin" in $motif) return 0 ;; esac
  done <<FIN
$(_conv_entrees exceptions)
FIN
  return 1
}

conv_journal_format() {
  conv_lire journal
  return 0
}

# Les trois formats de journal reconnus. date-titre est le plus large, il couvre aussi
# un titre keep-a-changelog, c'est voulu : un journal mixte se lit comme date-titre.
# Ni antislash ni intervalle {n} : le meme motif sert a grep -E, a awk -v, a gawk qui
# mange les \[, et aux awk anciens sans intervalles. [[] et []] valent un crochet.
journal_motif() { # <format>
  local d='[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
  case "${1:-}" in
    date-titre)       printf '%s\n' "^## .*${d}" ;;
    keep-a-changelog) printf '%s\n' "^## [[][^]]*[]] - ${d}" ;;
    crochets)         printf '%s\n' "^[[]${d}[]] " ;;
  esac
  return 0
}

# Le bloc decide s'il declare `journal:`. Sinon on compte les titres de chaque format hors
# blocs de code, et le plus specifique gagne quand il couvre tout le journal.
journal_detecter() { # <fichier>
  local f="${1:-}" decl dt kac cr
  decl="$(conv_journal_format)"
  if [ -n "$decl" ]; then
    printf '%s\n' "$decl"
    return 0
  fi
  [ -f "$f" ] || return 0
  _journal_compter() {
    M="$1" awk '/^```/ {code = !code; next} !code && $0 ~ ENVIRON["M"] {n++} END {print n + 0}' "$f"
  }
  dt="$(_journal_compter "$(journal_motif date-titre)")"
  kac="$(_journal_compter "$(journal_motif keep-a-changelog)")"
  cr="$(_journal_compter "$(journal_motif crochets)")"
  if [ "$cr" -gt "$dt" ]; then
    printf '%s\n' crochets
  elif [ "$kac" -gt 0 ] && [ "$kac" -eq "$dt" ]; then
    printf '%s\n' keep-a-changelog
  elif [ "$dt" -gt 0 ]; then
    printf '%s\n' date-titre
  fi
  return 0
}

# --- elagage : ce que les scripts ne parcourent pas ----------------------------
#
# Principe : le gitignore n'est PAS une source d'elagage. Un fichier ignore par git (notes
# locales, context-input/, livrables, CLAUDE.local.md) est du contexte, la liste ne vient donc
# jamais de `git ls-files`. On n'elague, pour la vitesse, que le genere lourd, reconnu a sa
# nature, et chaque elagage se nomme (exclusions_noms, que l'audit imprime).
#
# Une seule liste, a donner a find SANS guillemets, dans un contexte ou le shell ne
# developpe pas les motifs (set -f) : find . $(exclusions_find)
# Elle se compose de quatre sources :
#   1. les dossiers generes sans ambiguite, par nom, a toute profondeur ;
#   2. tout dossier qui porte un CACHEDIR.TAG de signature verifiee (Cargo en pose un) ;
#   3. les dossiers d'un moteur de jeu, seulement si le marqueur du moteur est a la racine :
#      Unity (ProjectSettings/ProjectVersion.txt), Unreal (*.uproject), Godot (project.godot).
#      Un `Library/` de projet ordinaire reste parcouru ;
#   4. la cle `ignorer:` du bloc, des globs relatifs a la racine, pour ce que git suit mais qui
#      ne fait pas partie du projet (un ancien depot importe tel quel).
# Les noms avec espace ou joker ne se representent pas dans une liste de mots : ils ne s'elaguent pas.
_EXCL_STATIQUE='-not -path ./.git/* -not -path ./archives/* -not -path */node_modules/* -not -path */vendor/* -not -path */.venv/* -not -path */venv/* -not -path */dist/* -not -path */build/* -not -path */target/* -not -path */.next/* -not -path */__pycache__/* -not -path */.cache/* -not -path */.gradle/* -not -path */Pods/* -not -path */.dart_tool/* -not -path */.nuxt/* -not -path */.svelte-kit/* -not -path */.turbo/* -not -path */.parcel-cache/* -not -path */.terraform/* -not -path */.pytest_cache/* -not -path */.mypy_cache/* -not -path */.tox/*'
CTX_CACHEDIR_SIGNATURE='Signature: 8a477f597d28d172789f06886806bc55'

# Un nom que find -path et la liste de mots portent sans le deformer.
_excl_nom_sain() { # <nom>
  case "$1" in ''|*[[:space:]]*|*'*'*|*'?'*|*'['*|*'\'*) return 1 ;; esac
  return 0
}

# Dossiers generes d'un moteur dans <racine>/<rel>, `type<TAB>rel<TAB>dossier`, seulement ceux
# qui existent. <rel> vaut . pour la racine.
_excl_dirs_moteur() { # <racine> <rel> <type>
  local r="$1" rel="$2" t="$3" d dirs p
  case "$t" in
    Unity)           dirs="Library Temp Logs obj UserSettings" ;;
    Unreal)          dirs="Intermediate Binaries DerivedDataCache Saved" ;;
    'Unreal plugin') dirs="Intermediate Binaries" ;;
    Godot)           dirs=".godot" ;;
    *) return 0 ;;
  esac
  for d in $dirs; do
    if [ "$rel" = . ]; then p="$d"; else p="$rel/$d"; fi
    if [ -d "$r/$p" ]; then printf '%s\t%s\t%s\n' "$t" "$rel" "$d"; fi
  done
  return 0
}

# Les moteurs dont le marqueur est a la racine, `type<TAB>.` : un test direct, sans parcours.
# Ils servent a ne pas descendre dans leur Library/ pour chercher les moteurs imbriques.
_excl_moteurs_racine() { # <racine>
  local r="$1" u f
  if [ -f "$r/ProjectSettings/ProjectVersion.txt" ]; then printf 'Unity\t.\n'; fi
  # un glob en sous-shell, set +f : les appelants tournent sous set -f
  u="$( set +f; for f in "$r"/*.uproject; do if [ -f "$f" ]; then echo oui; break; fi; done )"
  if [ -n "$u" ]; then printf 'Unreal\t.\n'; fi
  if [ -f "$r/project.godot" ]; then printf 'Godot\t.\n'; fi
  return 0
}

# Un moteur et sa racine <rel> : ajoute ses dossiers generes a la liste et aux noms. Plafond de
# 20 racines de moteur, les suivantes sont comptees et dites. Les variables _EX_* sont celles
# de _exclusions_calculer, qui tourne dans le shell appelant : pas de sous-shell ici.
_EX_BASE=""; _EX_NOMS=""; _EX_SEEN=""; _EX_N=0; _EX_PLAFOND=0; _EX_DIRS=""
_excl_ajouter_moteur() { # <racine> <rel> <type>
  local r="$1" rel="$2" t="$3" l d p tab
  tab="$(printf '\t')"
  case "$_EX_SEEN" in *"|$t|$rel|"*) return 0 ;; esac
  _excl_nom_sain "$rel" || return 0
  if [ "$_EX_N" -ge 20 ]; then _EX_PLAFOND=$((_EX_PLAFOND + 1)); return 0; fi
  _EX_SEEN="$_EX_SEEN|$t|$rel|"
  _EX_N=$((_EX_N + 1))
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    d="${l##*"$tab"}"
    if [ "$rel" = . ]; then p="$d"; else p="$rel/$d"; fi
    _EX_BASE="$_EX_BASE -not -path ./$p/*"
    _EX_DIRS="$_EX_DIRS ./$p/"
    _EX_NOMS="${_EX_NOMS}${l}
"
  done <<FIN
$(_excl_dirs_moteur "$r" "$rel" "$t")
FIN
  return 0
}

# Les globs de `ignorer:`, un par ligne, sans ./ de tete. Une valeur avec blanc est ignoree.
_excl_ignorer_globs() {
  local e g
  # sans la cle, rien a lire : on ne lance ni tr ni sed
  [ -n "$(conv_lire ignorer)" ] || return 0
  while IFS= read -r e; do
    g="$(printf '%s' "$e" | _conv_trim)"
    while [ "${g#./}" != "$g" ]; do g="${g#./}"; done
    _excl_nom_sain_glob "$g" || continue
    printf '%s\n' "$g"
  done <<FIN
$(_conv_entrees ignorer)
FIN
  return 0
}
_excl_nom_sain_glob() { # un glob garde ses jokers, pas ses blancs
  case "$1" in ''|*[[:space:]]*|*'\'*|/*) return 1 ;; esac
  return 0
}

# Un glob de `ignorer:` en arguments find. Un sous-arbre (`d/**`, `d/*`, `d/`) donne
# `-not -path ./d/*`, le reste le chemin lui-meme et son contenu. `**/x` vaut x a toute profondeur.
_excl_ignorer_args() { # <glob>
  local g="$1" out
  out="$(_excl_ancre './' "$g")"
  case "$g" in
    '**/'*) g="${g#\*\*/}"; out="$(_excl_ancre './' "$g") $(_excl_ancre '*/' "$g")" ;;
  esac
  printf '%s\n' "$out"
  return 0
}
# Un glob ancre : un sous-arbre (`d/**`, `d/*`, `d/`) ne garde que son contenu, le reste
# le chemin lui-meme et son contenu.
_excl_ancre() { # <ancre> <glob>
  local a="$1" g="$2" d
  case "$g" in '**/'*) g="${g#\*\*/}" ;; esac
  case "$g" in
    *'/**') d="${g%/\*\*}"; printf '%s\n' "-not -path $a$d/*" ;;
    *'/*')  d="${g%/\*}";   printf '%s\n' "-not -path $a$d/*" ;;
    */)     d="${g%/}";     printf '%s\n' "-not -path $a$d/*" ;;
    *)      printf '%s\n' "-not -path $a$g -not -path $a$g/*" ;;
  esac
  return 0
}

# Un seul parcours cherche les marqueurs des moteurs et les CACHEDIR.TAG, chemins `./...` tries.
# Il saute ce que les autres sources elaguent deja (liste fixe, `ignorer:`, dossiers des moteurs
# de la racine), il ne descend pas dans un Library/ pour le trouver.
_excl_decouverte() { # <racine> <mots deja elagues>
  local r="$1"
  shift
  # shellcheck disable=SC2046
  ( cd "$r" 2>/dev/null && set -f && \
      find . $(_excl_prune_args "$@") -o -type f \( -name CACHEDIR.TAG -o -name project.godot \
        -o -name '*.uproject' -o -name '*.uplugin' -o -path '*/ProjectSettings/ProjectVersion.txt' \) -print 2>/dev/null
  ) | LC_ALL=C sort
  return 0
}

# Les arguments `-not -path X/*` d'une liste, en prefixe de prune pour find :
# `( -type d ( -path X -o ... ) -prune )`. Rend les mots, a donner sans guillemets.
# Un chemin qui ne se termine pas par /* (un glob de `ignorer:` qui vise un fichier) s'elague
# sans condition de type : `( ( ( -type d ( ... ) ) -o ( -path F ) ) -prune )`.
_excl_prune_args() { # <mots de exclusions>
  local w d="" f=""
  for w in "$@"; do
    case "$w" in
      -not|-path) ;;
      */\*) d="$d${d:+ -o }-path ${w%/\*}" ;;
      *)    f="$f${f:+ -o }-path $w" ;;
    esac
  done
  if [ -z "$f" ]; then
    printf '( -type d ( %s ) -prune )\n' "$d"
  else
    printf '( ( ( -type d ( %s ) ) -o ( %s ) ) -prune )\n' "$d" "$f"
  fi
  return 0
}

# La meme liste en elagage, a donner a find SANS guillemets sous set -f, avant `-o` et le test :
#   find . $(exclusions_prune) -o -type f -print
# find ne descend plus dans un Library/ de 20 000 fichiers au lieu de les parcourir pour jeter
# chacun. Les mots donnes en argument s'ajoutent a la liste (`-not -path ./x/*`). Le dossier
# elague lui-meme ne sort pas, il est vrai pour le prefixe : pour le lister aussi,
# `find . \( $(exclusions_prune) -print \) -o ...`.
exclusions_prune() { # [<mots de exclusions en plus>]
  # sous-shell sous set -f : les mots de la liste portent des jokers, quel que soit l'appelant
  # shellcheck disable=SC2046
  ( set -f; _excl_prune_args $(exclusions_find) "$@" )
  return 0
}

# Calcule la liste et les noms. Pose CTX_EXCL_BASE (statique, moteurs, CACHEDIR.TAG), CTX_EXCL_IGN
# (les globs de `ignorer:`), CTX_EXCL_LISTE (les deux) et CTX_EXCL_NOMS, une ligne par dossier :
# `type<TAB>racine<TAB>dossier` pour un moteur (Unity, Unreal, Unreal plugin, Godot, racine . pour
# celle du projet), `CACHEDIR.TAG<TAB>-<TAB>dossier`, `ignorer<TAB>-<TAB>glob`, `plafond<TAB>-<TAB>N`.
# Un moteur se reconnait a son marqueur, a la racine ou jusqu'a la profondeur 3 : Unity
# ProjectSettings/ProjectVersion.txt, Unreal *.uproject, Godot project.godot, et pour Unreal un
# plugin (Plugins/*/*.uplugin, profondeur 5). Ses dossiers generes se lisent depuis sa racine.
_exclusions_calculer() {
  local r l g a t rel p d x tab ign="" trouves caches="" prof lim sous
  tab="$(printf '\t')"
  r="$(_ctx_racine)"
  _EX_BASE="$_EXCL_STATIQUE"; _EX_NOMS=""; _EX_SEEN=""; _EX_N=0; _EX_PLAFOND=0; _EX_DIRS=""
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    a="$(_excl_ignorer_args "$g")"
    ign="$ign $a"
    _EX_NOMS="${_EX_NOMS}ignorer${tab}-${tab}${g}
"
  done <<FIN
$(_excl_ignorer_globs)
FIN
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    _excl_ajouter_moteur "$r" "${l#*"$tab"}" "${l%%"$tab"*}"
  done <<FIN
$(_excl_moteurs_racine "$r")
FIN
  # shellcheck disable=SC2086
  trouves="$(set -f; _excl_decouverte "$r" $_EX_BASE$ign)"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    t=""; rel=""; lim=3
    case "$p" in
      */CACHEDIR.TAG) caches="$caches$p
"; continue ;;
      */ProjectSettings/ProjectVersion.txt) t=Unity; rel="${p%/ProjectSettings/ProjectVersion.txt}" ;;
      */project.godot) t=Godot; rel="${p%/project.godot}" ;;
      */Plugins/*/*.uplugin) t='Unreal plugin'; rel="${p%/*}"; lim=5 ;;
      *.uproject) t=Unreal; rel="${p%/*}" ;;
      *) continue ;;
    esac
    rel="${rel#./}"
    prof=0
    if [ "$rel" != . ]; then x="${rel//[!\/]/}"; prof=$(( ${#x} + 1 )); fi
    [ "$prof" -le "$lim" ] || continue
    _excl_ajouter_moteur "$r" "$rel" "$t"
  done <<FIN
$trouves
FIN
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    d="${p%/CACHEDIR.TAG}"; d="${d#./}"
    # le CACHEDIR.TAG de la racine n'elague pas le projet entier
    [ -n "$d" ] && [ "$d" != "." ] && [ "$d" != "$p" ] || continue
    _excl_nom_sain "$d" || continue
    case "$_EX_BASE$ign" in *" -not -path ./$d/*"*) continue ;; esac
    sous=0
    for x in $_EX_DIRS; do
      case "./$d/" in "$x"*) sous=1; break ;; esac
    done
    [ "$sous" -eq 0 ] || continue
    l=""
    IFS= read -r l < "$r/$p" 2>/dev/null || true
    case "$l" in "$CTX_CACHEDIR_SIGNATURE"*) ;; *) continue ;; esac
    _EX_BASE="$_EX_BASE -not -path ./$d/*"
    _EX_DIRS="$_EX_DIRS ./$d/"
    _EX_NOMS="${_EX_NOMS}CACHEDIR.TAG${tab}-${tab}${d}
"
  done <<FIN
$caches
FIN
  if [ "$_EX_PLAFOND" -gt 0 ]; then
    _EX_NOMS="${_EX_NOMS}plafond${tab}-${tab}${_EX_PLAFOND}
"
  fi
  CTX_EXCL_BASE="$_EX_BASE"
  CTX_EXCL_IGN="$ign"
  CTX_EXCL_LISTE="$_EX_BASE$ign"
  CTX_EXCL_NOMS="$_EX_NOMS"
  return 0
}

# A appeler une fois dans le shell principal : les appels suivants, y compris dans des $(...),
# lisent la memoire au lieu de refaire un parcours pour les CACHEDIR.TAG.
exclusions_charger() {
  CTX_EXCL_CHARGE=0
  _exclusions_calculer
  CTX_EXCL_CHARGE=1
  return 0
}

exclusions_find() {
  if [ "${CTX_EXCL_CHARGE:-0}" != 1 ]; then _exclusions_calculer; fi
  printf '%s\n' "$CTX_EXCL_LISTE"
  return 0
}

# Ce qui s'elague au-dela de la liste statique, une ligne `categorie<TAB>racine<TAB>detail` chacune :
# `Unity<TAB>game<TAB>Library`, `CACHEDIR.TAG<TAB>-<TAB>target`, `ignorer<TAB>-<TAB>projets/*/context-input/**`.
exclusions_noms() {
  if [ "${CTX_EXCL_CHARGE:-0}" != 1 ]; then _exclusions_calculer; fi
  printf '%s' "$CTX_EXCL_NOMS"
  return 0
}

# Les noms regroupes, `categorie<TAB>racine<TAB>liste` : un moteur par racine (la liste de ses
# dossiers separes par des virgules), tous les CACHEDIR.TAG ensemble, un `ignorer` par glob, et
# `plafond` quand des racines de moteur depassent les 20 reconnues. racine vaut - hors moteur.
exclusions_noms_groupes() {
  exclusions_noms | awk -F'\t' '
    { k = ($1 == "ignorer" || $1 == "plafond" ? $1 "\t" $2 "\t" $3 : $1 "\t" $2)
      if (!(k in l)) { ordre[++n] = k; l[k] = $3 } else if ($1 != "ignorer" && $1 != "plafond") l[k] = l[k] ", " $3 }
    END { for (i = 1; i <= n; i++) { k = ordre[i]; if (k ~ /^(ignorer|plafond)\t/) print k; else print k "\t" l[k] } }'
  return 0
}

# Combien de fichiers un glob de `ignorer:` fait sauter. Les dossiers que les autres sources
# elaguent ne se parcourent pas, et le glob compte n'elague pas sa propre cible.
exclusions_compter_ignorer() { # <glob>
  local g="$1" r n="" a
  r="$(_ctx_racine)"
  if [ "${CTX_EXCL_CHARGE:-0}" != 1 ]; then _exclusions_calculer; fi
  a="$(_excl_ignorer_args "$g")"
  # Tout dans un sous-shell sous set -f : les jokers du glob restent litteraux, quel que soit l'appelant.
  # shellcheck disable=SC2046,SC2086
  n="$( cd "$r" && set -f && {
      motifs=""; ou=""
      for w in $a; do
        # (motif) avec parenthese ouvrante : bash 3.2 ferme sinon le $( au premier motif) du case.
        case "$w" in (-not|-path) ;; (*) motifs="$motifs${ou:+ -o }-path $w"; ou=1 ;; esac
      done
      find . $(_excl_prune_args $CTX_EXCL_BASE) -o -type f \( $motifs \) -print 2>/dev/null | wc -l | tr -d ' '
    } )"
  printf '%s\n' "${n:-0}"
  return 0
}

sous_modules() {
  local r
  r="$(_ctx_racine)"
  if [ -f "$r/.gitmodules" ]; then
    sed -n 's/^[[:space:]]*path[[:space:]]*=[[:space:]]*//p' "$r/.gitmodules" | sed 's/[[:space:]]*$//'
  fi
  return 0
}

version_scripts() {
  local v
  v="$(conv_version)"
  case "$v" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$v" -gt "$CTX_VERSION" ]; then
    printf 'Le bloc contexte:convention est en version %s, ces scripts ne connaissent que la %s.\n' \
      "$v" "$CTX_VERSION" >&2
    printf 'Mets a jour le plugin fstack avant de relancer.\n' >&2
    return 1
  fi
  return 0
}

ctx_aujourdhui() {
  printf '%s\n' "${CTX_AUJOURDHUI:-$(date +%Y-%m-%d)}"
  return 0
}

# date -j -f d'abord : le date BSD de macOS prend -d pour autre chose et peut rendre
# l'heure courante avec un code 0. Sur GNU, -j echoue proprement et -d prend le relais.
# Une entree qui n'a pas la forme AAAA-MM-JJ rend vide : GNU `date -d ""` rendrait minuit du jour,
# et une date absente se lirait comme une date d'aujourd'hui.
ctx_epoch() { # <AAAA-MM-JJ>
  case "${1:-}" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) return 0 ;;
  esac
  date -j -f '%Y-%m-%d' "${1:-}" +%s 2>/dev/null || date -d "${1:-}" +%s 2>/dev/null || true
  return 0
}

# Jours entiers entre deux instants, arrondis au plus proche (les 43200 absorbent l'heure d'ete).
# Positif dans le passe, negatif dans le futur. La division de bash tronque vers zero, ce qui
# rendrait 0 pour demain : le negatif s'arrondit a part.
ctx_jours_entre() { # <epoch maintenant> <epoch date>
  local x=$(( $1 - $2 + 43200 ))
  if [ "$x" -lt 0 ]; then
    printf '%s\n' $(( (x - 86399) / 86400 ))
  else
    printf '%s\n' $(( x / 86400 ))
  fi
  return 0
}

ctx_jours_depuis() { # <AAAA-MM-JJ>
  local a b
  a="$(ctx_epoch "$(ctx_aujourdhui)")"
  b="$(ctx_epoch "${1:-}")"
  if [ -n "$a" ] && [ -n "$b" ]; then
    ctx_jours_entre "$a" "$b"
  fi
  return 0
}
