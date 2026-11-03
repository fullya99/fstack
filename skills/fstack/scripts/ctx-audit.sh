#!/usr/bin/env bash
#
# ctx-audit.sh : rapport de derive entre la documentation et la realite, et
# mesure du budget de contexte.
#
# Le script signale, il ne corrige rien et il ne juge pas. A toi de trancher.
# Usage :
#   bash ctx-audit.sh [--root <chemin>] [--peremption <jours>] [--strict] [--budget] [--json]
#
# --budget : ne lance que la section 10, la mesure du budget : tailles, cout de
#            reprise, cliquet ajourne. Rapide, pour la cloture et le hook de demarrage.
# --strict : sortie en code 1 s'il reste au moins une alerte (utile en CI).
# --json   : une liste JSON sur la sortie standard, un objet par alerte
#            {"section","niveau","fichier","message"}, et rien d'autre.
#
# set -f : sans ca, une portee du genre `src/auth/**` serait developpee par le shell
# au moment de la lire, et on comparerait des fichiers au lieu du motif.
set -euf

# Bibliotheque commune, chargee avant le cd vers la racine auditee.
DIR_SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPTS/ctx-commun.sh"

ROOT=""
PEREMPTION=120
STRICT=0
BUDGET_SEUL=0
JSON=0

while [ $# -gt 0 ]; do
  case "$1" in
    --root)       ROOT="${2:-}"; shift 2 ;;
    --peremption) PEREMPTION="${2:-120}"; shift 2 ;;
    --strict)     STRICT=1; shift ;;
    --budget)     BUDGET_SEUL=1; shift ;;
    --json)       JSON=1; shift ;;
    -h|--help)    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Option inconnue : $1" >&2; exit 2 ;;
  esac
done

APPEL="$(pwd)"
RACINE_DEDUITE=0
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  RACINE_DEDUITE=1
fi
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"

# Le bloc se lit une fois ici. Les conv_lire qui suivent, y compris dans un $(...), viennent
# de la memoire : sans ca chaque appel relance un find, un grep et un awk.
conv_charger

# Un bloc plus recent que ces scripts : on refuse de tourner plutot que de mal lire.
version_scripts || exit 1

# En mode --json, la sortie standard ne porte que la liste finale : tout le texte
# lisible part vers /dev/null, la liste sort par le descripteur 3.
if [ "$JSON" -eq 1 ]; then
  exec 3>&1 1>/dev/null
fi

# En texte, le rapport s'ecrit dans un fichier temporaire et ne sort qu'a la fin, par
# agreger_sortie : il faut le total de chaque nature d'alerte avant d'imprimer la premiere.
# La sortie se vide a la sortie du script, y compris sur une erreur ou un signal, pour qu'un
# arret en cours de route montre ce qui a deja ete dit. Sans fichier temporaire, le rapport
# s'imprime tel quel, sans agregation.
AGREG_TMP=""
ROT_SORTIE=""
ROT_PID=""
sortie_finale() {
  [ -z "$ROT_PID" ] || kill "$ROT_PID" 2>/dev/null || true
  [ -z "$ROT_SORTIE" ] || rm -f "$ROT_SORTIE"
  if [ -n "$AGREG_TMP" ]; then
    exec 1>&5 5>&-
    agreger_sortie < "$AGREG_TMP" || true
    rm -f "$AGREG_TMP"
  fi
  return 0
}
trap sortie_finale EXIT
if [ "$JSON" -eq 0 ]; then
  AGREG_TMP="$(mktemp "${TMPDIR:-/tmp}/ctx-audit.XXXXXX" 2>/dev/null)" || AGREG_TMP=""
  if [ -n "$AGREG_TMP" ]; then exec 5>&1 1>"$AGREG_TMP"; fi
fi

TODAY="$(ctx_aujourdhui)"
ALERTES=0
BLOCAGES=0
SEC=""
JSON_BRUT=""
TAB="$(printf '\t')"

# Les alertes s'accumulent en brut (section, niveau, fichier, message separes par le
# separateur d'unite, une alerte par separateur d'enregistrement) et s'echappent d'un coup
# a la fin, dans un seul awk. Un sous-processus par champ et par alerte coutait six
# millisecondes l'alerte, deux secondes pour trois cents. LC_ALL=C : un nom de fichier en
# Latin-1 est une suite d'octets invalide en UTF-8, et le sed BSD de macOS refuse la ligne.
# En C, un octet reste un octet. Les caracteres de controle sont supprimes, la tabulation
# devient \t, le saut de ligne une espace.
US="$(printf '\037')"
RS_="$(printf '\036')"
# La nature d'une alerte : son message sans les chemins ni les nombres. Deux alertes de meme
# nature disent la meme chose de fichiers differents (« pas d'en-tete de statut »). Un mot est
# un chemin s'il porte un / ou s'il se termine par une extension de fichier courante. Source
# awk, partagee par la sortie JSON et par l'agregation du texte.
NATURE_AWK='
function nature(m,   n, i, t, r, a) {
  n = split(m, a, " ")
  r = ""
  for (i = 1; i <= n; i++) {
    t = a[i]
    if (t ~ /\// || t ~ /^[`"\047(]*[A-Za-z0-9_.-]+\.(md|sh|json|jsonl|txt|yml|yaml|js|mjs|cjs|ts|py|toml|html|xml|csv|cfg|conf)[`"\047),.:;]*$/) continue
    gsub(/[0-9]+/, "", t)
    if (t == "") continue
    r = r (r == "" ? "" : " ") t
  }
  sub(/^[:,; ]+/, "", r)
  return r
}
'

json_sortie() { # <alertes brutes> : la liste JSON sur la sortie standard
  printf '%s' "$1" | LC_ALL=C awk "$NATURE_AWK"'BEGIN { RS = "\036"; FS = "\037"; n = 0 }
    function rep(s, de, par,   o, i) {
      o = ""
      while ((i = index(s, de)) > 0) { o = o substr(s, 1, i - 1) par; s = substr(s, i + length(de)) }
      return o s
    }
    function esc(s) {
      gsub(/\n/, " ", s)
      gsub(/[\001-\010\013-\037]/, "", s)
      s = rep(s, "\\", "\\\\")
      s = rep(s, "\"", "\\\"")
      return rep(s, "\t", "\\t")
    }
    NF >= 4 {
      m = $4
      for (k = 5; k <= NF; k++) m = m $k
      if (n++) printf ",\n"
      # nature avant message : ctx-demarrage.sh lit le message en coupant tout ce qui suit
      # `"message":"` jusqu a la fin de la ligne.
      printf "{\"section\":\"%s\",\"niveau\":\"%s\",\"fichier\":\"%s\",\"nature\":\"%s\",\"message\":\"%s\"}", esc($1), esc($2), esc($3), esc(nature(m)), esc(m)
    }
    END { if (n) printf "\n" }'
  return 0
}

# Agregation des alertes repetitives, sur le texte lisible seulement. Au-dela de 5 alertes de
# meme nature dans une section, les 3 premieres s'impriment telles quelles et une ligne dit
# combien d'autres suivent. Un blocage ne s'agrege jamais, le bilan et la liste JSON gardent
# toutes les alertes : seul l'affichage se resume. Le filtre lit la sortie entiere, il lui faut
# le total de chaque nature avant d'imprimer la premiere.
agreger_sortie() { # lit le texte du rapport sur l'entree standard
  LC_ALL=C awk "$NATURE_AWK"'
    { L[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (L[i] ~ /^[0-9]+b?\. /) { sec = L[i]; sub(/ .*/, "", sec) }
        if (substr(L[i], 1, 6) == "  [!] ") {
          K[i] = sec SUBSEP nature(substr(L[i], 7))
          T[K[i]]++
        }
      }
      for (i = 1; i <= NR; i++) {
        if (!(i in K)) { print L[i]; continue }
        k = K[i]; V[k]++
        if (T[k] <= 5 || V[k] <= 3) print L[i]
        if (T[k] > 5 && V[k] == 3) {
          n = k; sub(/^[^\034]*\034/, "", n)
          printf "  [!] ... et %d autres de meme nature (%s)\n", T[k] - 3, n
        }
      }
    }'
  return 0
}

# Le fichier vise par une alerte : ce qui precede " : ", ou le premier mot s'il
# ressemble a un chemin. Vide quand le message ne vise pas un fichier.
fichier_du_message() { # <message>
  local m="$1" t
  case "$m" in
    *" : "*) t="${m%% : *}"
             case "$t" in *" "*) ;; *) printf '%s' "$t"; return 0 ;; esac ;;
  esac
  t="${m%% *}"
  case "$t" in *[.,/]*) printf '%s' "${t%,}" ;; esac
  return 0
}

signaler() { # <niveau> <message> [<fichier>]
  local fic="${3:-}"
  ALERTES=$((ALERTES + 1))
  [ "$1" = blocage ] && BLOCAGES=$((BLOCAGES + 1))
  if [ "$JSON" -eq 1 ]; then
    [ -n "$fic" ] || fic="$(fichier_du_message "$2")"
    JSON_BRUT="$JSON_BRUT$SEC$US$1$US$fic$US$2$RS_"
  fi
  return 0
}
alerte()  { printf '  [!] %s\n' "$1"; signaler alerte "$@"; }
blocage() { printf '  [!!] %s\n' "$1"; signaler blocage "$@"; }
ok()      { printf '  [ok] %s\n' "$1"; }
info()    { printf '  ... %s\n' "$1"; }

# Age en jours d'une date, par ctx_jours_depuis, garde en memoire par date : des centaines
# de fiches partagent quelques dates, et chaque appel coute trois `date`. Le resultat est
# dans JOURS, vide quand la date est illisible.
AGES=""
JOURS=""
jours_depuis() { # <AAAA-MM-JJ> : pose JOURS
  JOURS=""
  [ -n "${1:-}" ] || return 0
  if valeur_liste "$AGES" "$1"; then JOURS="$VALEUR"; return 0; fi
  JOURS="$(ctx_jours_depuis "$1")"
  AGES="$AGES$NL$1=$JOURS"
  return 0
}
# wc rend un nombre cadre d'espaces sous BSD : l'arithmetique les avale, sans un tr de plus.
lignes() { local n; n="$(wc -l < "$1")"; printf '%s\n' "$((n + 0))"; }
# Caracteres d'un fichier, pas octets : en C, tr retire les octets de continuation UTF-8
# (0x80 a 0xBF), il reste un octet par caractere. Une doc en francais accentue pese 2 % de
# moins en caracteres, un tableau de symboles ou d'emojis beaucoup moins.
caracteres() { local n; n="$(LC_ALL=C tr -d '\200-\277' < "$1" | wc -c)"; printf '%s\n' "$((n + 0))"; }
# Meme mesure sur l'entree standard.
caracteres_stdin() { local n; n="$(LC_ALL=C tr -d '\200-\277' | wc -c)"; printf '%s\n' "$((n + 0))"; }

# mesure generique : <fichier> <libelle> <alerte> <blocage> [<blocage en caracteres>]
#                    [<cle de seuils>] [<alerte en caracteres>]
# Un budget en lignes ne voit pas un fichier de quelques lignes tres larges : le seuil en
# caracteres l'attrape. Il se surcharge par `seuils: car-<cle>=N` (alerte, le blocage suit).
mesure() {
  fmes="$1"; lmes="$2"; ames="$3"; bmes="$4"; omes="${5:-0}"; kmes="${6:-$1}"; acmes="${7:-0}"
  [ -f "$fmes" ] || return 0
  # Un fichier ajourne est juge par le cliquet, a la fin de la section 10.
  ajourne_de "$kmes"
  if [ -n "$AJ_N" ]; then return 0; fi
  seuils_de "$kmes" "$ames" "$bmes"
  ames="$SEUIL_A"; bmes="$SEUIL_B"
  qmes=0
  if [ "$omes" -gt 0 ]; then
    seuils_de "car-$kmes" "$acmes" "$omes"
    acmes="$SEUIL_A"; omes="$SEUIL_B"
    qmes="$(caracteres "$fmes")"
  fi
  nmes="$(lignes "$fmes")"
  if [ "$nmes" -gt "$bmes" ]; then
    blocage "$lmes : $nmes lignes, seuil de blocage $bmes"
  elif [ "$omes" -gt 0 ] && [ "$qmes" -gt "$omes" ]; then
    blocage "$lmes : $qmes caracteres, seuil de blocage $omes"
  elif [ "$nmes" -gt "$ames" ]; then
    alerte "$lmes : $nmes lignes, seuil d'alerte $ames"
  elif [ "$acmes" -gt 0 ] && [ "$qmes" -gt "$acmes" ]; then
    alerte "$lmes : $qmes caracteres, seuil d'alerte $acmes"
  else
    ok "$lmes : $nmes lignes"
  fi
}

# Profondeur de titres. GitLab est le seul guide a publier une regle chiffree de
# decoupe : au-dela de cinq niveaux, ce sont plusieurs sujets, pas un seul.
# Un seul awk pour tous les fichiers donnes (un par ligne sur l'entree standard) : sort
# `profondeur<TAB>chemin` pour ceux qui atteignent cinq niveaux, titres hors blocs de code.
profondeurs_titres() {
  local liste
  liste="$(cat)"
  [ -n "$liste" ] || return 0
  printf '%s\n' "$liste" | sed 's|^|./|' | tr '\n' '\000' | xargs -0 awk -v T="$TAB" '
    function fin() { if (f != "" && max >= 5) { sub(/^\.\//, "", f); print max T f } }
    FNR == 1 { fin(); f = FILENAME; fence = 0; max = 0 }
    /^```/ { fence = !fence; next }
    !fence && /^#+ / { n = index($0, " ") - 1; if (n > max) max = n }
    END { fin() }' 2>/dev/null || true
  return 0
}

# Chemin declare dans le bloc (`docs:`, `archives:`), sans le / final. `aucune`
# (ou `non`, `-`) eteint la surface, une ligne absente vaut le defaut.
chemin_declare() { # <cle> <defaut>
  local v
  v="$(conv_lire "$1")"
  case "$v" in
    aucun|aucune|non|none|-) return 0 ;;
    '') v="$2" ;;
  esac
  v="${v%%[[:space:],]*}"
  while [ "${v%/}" != "$v" ]; do v="${v%/}"; done
  printf '%s' "$v"
  return 0
}
DOCS_DIR="$(chemin_declare docs docs)"
ARCH_DIR="$(chemin_declare archives archives)"
# Repertoire des plans, cle optionnelle `plans:` (plans/ par defaut), sans ./ initial.
PLANS_DIR="$(chemin_declare plans plans)"
while [ "${PLANS_DIR#./}" != "$PLANS_DIR" ]; do PLANS_DIR="${PLANS_DIR#./}"; done
# Les plans executes (section 11) se lisent dans la sortie de ctx-rotation.sh --plans
# --dry-run, qui prend plus d'une seconde sur un depot de plusieurs dizaines de plans. Il
# ne depend que de la racine : il tourne en tache de fond pendant les sections 0 a 10, et la
# section 11 reprend sa sortie. Le fichier se supprime a la sortie, et la tache s'arrete avec
# le script. Sans fichier temporaire, la section 11 le lance elle-meme, comme avant.
if [ "$BUDGET_SEUL" -eq 0 ] && [ -n "$PLANS_DIR" ] && [ -d "$PLANS_DIR" ] && [ -f "$DIR_SCRIPTS/ctx-rotation.sh" ]; then
  ROT_SORTIE="$(mktemp "${TMPDIR:-/tmp}/ctx-audit.XXXXXX" 2>/dev/null)" || ROT_SORTIE=""
  if [ -n "$ROT_SORTIE" ]; then
    bash "$DIR_SCRIPTS/ctx-rotation.sh" --plans --dry-run --root "$ROOT" >"$ROT_SORTIE" 2>/dev/null 3>&- 5>&- &
    ROT_PID=$!
  fi
fi
LANGUE="$(conv_lire langue)"
case "$LANGUE" in
  en*) RE_REPRISE='la reprise|resume|handoff|hand-off|restart'
       RE_BLOC='reprise|resume|handoff|hand-off|restart'
       LIB_REPRISE='Resume state'
       RE_STATUT='Statut|Status'
       RE_PORTEE='Port|Scope'
       RE_REMPL='Remplac|Replace|Supersed'
       RE_ORIGINE='Origine|Origin' ;;
  *)   RE_REPRISE='la reprise'
       RE_BLOC='reprise'
       LIB_REPRISE='Etat a la reprise'
       RE_STATUT='Statut'
       RE_PORTEE='Port'
       RE_REMPL='Remplac'
       RE_ORIGINE='Origine' ;;
esac

# Repertoires qui ne comptent jamais, ni dans la doc, ni dans la taille du projet : le genere
# lourd et la cle `ignorer:`, jamais ce que le .gitignore exclut. Calcule une fois ici, les
# $(exclusions_find) qui suivent lisent la memoire. La section 10 nomme chaque elagage.
exclusions_charger
EXCLUS="$(exclusions_find)"
if [ -n "$ARCH_DIR" ] && [ "$ARCH_DIR" != archives ]; then
  EXCLUS="$EXCLUS -not -path ./$ARCH_DIR/*"
fi
# La meme liste, en elagage : find ne descend plus du tout dans .git, node_modules ou dist
# au lieu de les parcourir pour jeter chaque fichier. Sur un depot de 150 000 fichiers dont
# 100 000 dans .git, c'est un parcours sept fois plus court pour la meme liste. Elle se
# derive de exclusions_find par exclusions_prune, une seule source : chaque `-not -path X/*`
# devient `-path X`. Le dossier d'archives declare, s'il n'est pas archives/, s'ajoute.
if [ -n "$ARCH_DIR" ] && [ "$ARCH_DIR" != archives ]; then
  PRUNE=( $(exclusions_prune -not -path "./$ARCH_DIR/*") )
else
  PRUNE=( $(exclusions_prune) )
fi
trouver() { # <debut> <tests de find...> : find hors des repertoires exclus, chemins sur la sortie
  local debut="$1"
  shift
  find "$debut" "${PRUNE[@]}" -o "$@" -print 2>/dev/null
  return 0
}
SOUS_MODULES="$(sous_modules)"
# Le bloc est lu une fois, ici. Les exceptions, les seuils et les ajournements se cherchent
# ensuite en memoire, sans un sous-processus par fichier : sur un depot de plusieurs
# centaines de fiches, un conv_seuil par fiche (deux sed par entree) coutait des secondes.
NL='
'
TRIM=""
trim() { # <texte> : pose TRIM, sans les blancs de tete et de fin
  TRIM="${1#"${1%%[![:space:]]*}"}"
  TRIM="${TRIM%"${TRIM##*[![:space:]]}"}"
  return 0
}
# Entrees `nom=valeur` d'une liste du bloc, une par ligne, precedees chacune d'un saut de
# ligne pour qu'on les retrouve par "$NL$nom=". <valeur numerique> garde celles dont la
# valeur est un entier, <libre> garde tout ce qui porte un =.
entrees_du_bloc() { # <cle> <numerique|libre>
  local e nom val liste=""
  while IFS= read -r e; do
    case "$e" in *=*) ;; *) continue ;; esac
    trim "${e%%=*}"; nom="${TRIM#./}"
    trim "${e#*=}"; val="$TRIM"
    [ -n "$nom" ] || continue
    if [ "$2" = numerique ]; then
      case "$val" in ''|*[!0-9]*) continue ;; esac
    fi
    liste="$liste$NL$nom=$val"
  done <<FIN
$(conv_lire "$1" | tr ',' '\n')
FIN
  printf '%s' "$liste"
  return 0
}
# Valeur de `cle=valeur` dans une liste de lignes `\ncle=valeur`, posee dans VALEUR. Code 1 si la
# cle n'y est pas. Le test `case *"cle="*` est rapide, mais `${liste#*"cle="}` ne l'est pas : sur
# trois cents entrees, deux secondes. La valeur se lit donc par la longueur du prefixe.
VALEUR=""
valeur_liste() { # <liste> <cle>
  local liste="$1" cle="$2" avant reste
  VALEUR=""
  case "$liste" in
    *"$NL$cle="*)
      avant="${liste%%"$NL$cle="*}"
      reste="${liste:$((${#avant} + ${#cle} + 2))}"
      VALEUR="${reste%%"$NL"*}"
      return 0 ;;
  esac
  return 1
}
EXCEPTIONS="$(conv_lire exceptions)"
EXC_LISTE=""
if [ -n "$EXCEPTIONS" ]; then EXC_LISTE="$(entrees_du_bloc exceptions libre)"; fi
exception_de() { # <type> <chemin> : code 0 si `exceptions: type=motif` couvre le chemin (glob shell)
  local type="$1" chemin="${2#./}" e motif IFS="$NL"
  [ -n "$EXC_LISTE" ] || return 1
  for e in $EXC_LISTE; do
    case "$e" in "$type="*) ;; *) continue ;; esac
    motif="${e#*=}"
    [ -n "$motif" ] || continue
    # dans un case, * couvre aussi les /, donc ** et * se valent ici
    # shellcheck disable=SC2254
    case "$chemin" in $motif) return 0 ;; esac
  done
  return 1
}

# Seuils du bloc : `seuils: <fichier>=N` fixe le seuil d'ALERTE du fichier a N. Le
# seuil de blocage suit dans le meme rapport que les valeurs par defaut de BUDGET.md,
# arrondi a l'entier.
SEUILS_DECL="$(conv_lire seuils)"
SEUILS_LISTE=""
if [ -n "$SEUILS_DECL" ]; then SEUILS_LISTE="$(entrees_du_bloc seuils numerique)"; fi
SEUIL_A=0; SEUIL_B=0
seuils_de() { # <cle> <alerte par defaut> <blocage par defaut> : pose SEUIL_A et SEUIL_B
  local n="$2"
  SEUIL_A="$2"; SEUIL_B="$3"
  if valeur_liste "$SEUILS_LISTE" "${1#./}"; then n="$VALEUR"; fi
  if [ "$n" != "$2" ] && [ "$2" -gt 0 ]; then
    SEUIL_A="$n"
    SEUIL_B=$(( ($3 * n + $2 / 2) / $2 ))
  fi
  return 0
}

# Seuils par defaut d'un fichier de la convention, ceux de BUDGET.md. DA vaut 0 pour
# un fichier que le budget ne connait pas.
DA=0; DB=0
defauts_de() { # <fichier> : pose DA et DB
  DA=0; DB=0
  case "$1" in
    CLAUDE.md)    DA=150; DB=200 ;;
    CODEMAP.md)   DA=300; DB=400 ;;
    TODOS.md)     DA=200; DB=300 ;;
    CHANGELOG.md) DA=1000; DB=1500 ;;
    */CODEMAP.md) DA=200; DB=250 ;;
    */CLAUDE.md)  DA=40; DB=60 ;;
  esac
  if [ "$DA" -eq 0 ] && [ -n "$DOCS_DIR" ]; then
    case "$1" in "$DOCS_DIR"/*.md) DA=250; DB=300 ;; esac
  fi
  return 0
}

# Cliquet `ajourne: <fichier>=N@AAAA-MM-JJ` : un depassement gele a sa valeur et a sa date.
# AJ_LISTE garde `fichier=N` par entree lisible, N vide quand il n'est pas un entier.
AJOURNE="$(conv_lire ajourne)"
AJ_N=""
AJ_LISTE=""
if [ -n "$AJOURNE" ]; then
  while IFS= read -r e; do
    trim "$e"; e="${TRIM#./}"
    case "$e" in *=*@*) ;; *) continue ;; esac
    trim "${e%%=*}"; nom="$TRIM"
    trim "${e#*=}"; trim "${TRIM%%@*}"; val="$TRIM"
    case "$val" in ''|*[!0-9]*) val="" ;; esac
    AJ_LISTE="$AJ_LISTE$NL$nom=$val"
  done <<FIN
$(printf '%s\n' "$AJOURNE" | tr ',' '\n')
FIN
fi
ajourne_de() { # <fichier> : pose AJ_N (les lignes gelees), vide sans entree lisible
  AJ_N=""
  if valeur_liste "$AJ_LISTE" "${1#./}"; then AJ_N="$VALEUR"; fi
  return 0
}

# Chemin sans les segments . et .., sans rien lire sur le disque. Le resultat est
# dans NORM, pas sur la sortie : un sous-shell par lien coute cher sur un gros depot.
NORM=""
normaliser() { # <chemin>
  local IFS=/ seg out=""
  for seg in $1; do
    case "$seg" in
      ''|.) ;;
      ..) case "$out" in
            ''|..|*/..) out="${out:+$out/}.." ;;
            */*) out="${out%/*}" ;;
            *) out="" ;;
          esac ;;
      *) out="${out:+$out/}$seg" ;;
    esac
  done
  NORM="$out"
  return 0
}

# Un chemin sous un sous-module jamais initialise ne se resout pas, et ce n'est pas
# un defaut de la doc : le lien vaut des qu'on fait `git submodule update`.
sous_module_vide() { # <chemin normalise> : code 0 s'il est sous un sous-module non initialise
  local p IFS="$NL"
  for p in $SOUS_MODULES; do
    case "$1" in
      "$p"|"$p"/*) if [ ! -e "$p/.git" ]; then return 0; fi ;;
    esac
  done
  return 1
}

# Un markdown sans ses blocs de code, ses commentaires HTML, ses spans de code et son code
# indente : ce qu'ils contiennent est un exemple, jamais un lien ou un chemin de la doc.
# Un bloc indente de quatre espaces ou d'une tabulation ne vaut comme code que s'il suit une
# ligne vide et ne vit pas dans une liste : une sous-liste indentee reste de la doc.
# Le meme programme sert aux deux usages : le texte nettoye d'un fichier (liens = 0), ou les
# liens `](cible)` de plusieurs fichiers d'un coup, un par ligne `fichier<US>cible` (liens = 1).
AWK_MD='
  BEGIN { vide = 1 }
  FNR == 1 { fence = 0; com = 0; code = 0; liste = 0; vide = 1 }
  /^[ \t]*```/ { fence = !fence; next }
  fence { next }
  {
    ind = ($0 ~ /^(    |\t)/)
    if ($0 ~ /^[ \t]*$/) { vide = 1; if (!code && !liens) print; next }
    if (ind && (code || (vide && !liste))) { code = 1; vide = 0; next }
    code = 0
    if ($0 ~ /^ ? ? ?([-*+]|[0-9]+[.)])[ \t]/) liste = 1
    else if (vide && $0 ~ /^[^ \t]/) liste = 0
    vide = 0
    l = $0; out = ""
    while (length(l) > 0) {
      if (com) {
        i = index(l, "-->")
        if (i == 0) { l = "" } else { l = substr(l, i + 3); com = 0 }
      } else {
        i = index(l, "<!--")
        if (i == 0) { out = out l; l = "" }
        else { out = out substr(l, 1, i - 1); l = substr(l, i + 4); com = 1 }
      }
    }
    res = ""
    while ((i = index(out, "`")) > 0) {
      rest = substr(out, i + 1)
      j = index(rest, "`")
      if (j == 0) break
      res = res substr(out, 1, i - 1)
      out = substr(rest, j + 1)
    }
    if (!liens) { print res out; next }
    t = res out
    f = FILENAME; sub(/^\.\//, "", f)
    while (match(t, /\]\([^)#][^)]*\)/)) {
      print f U substr(t, RSTART + 2, RLENGTH - 3)
      t = substr(t, RSTART + RLENGTH)
    }
  }'
md_sans_code() { # <fichier>
  awk -v liens=0 "$AWK_MD" "$1" 2>/dev/null
  return 0
}
# Les liens de tous les fichiers d'une liste (un chemin par ligne sur l'entree standard),
# un seul awk au lieu d'un sous-processus par fichier. Rend `fichier<US>cible`.
liens_tous() {
  local liste
  liste="$(cat)"
  [ -n "$liste" ] || return 0
  printf '%s\n' "$liste" | sed 's|^|./|' | tr '\n' '\000' | xargs -0 awk -v liens=1 -v U="$US" "$AWK_MD" 2>/dev/null || true
  return 0
}

# Les liens relatifs d'un markdown, un par ligne, ancre et exemples exclus.
liens_de() { # <fichier>
  md_sans_code "$1" | grep -oE '\]\([^)#][^)]*\)' | sed 's/^](//; s/)$//' || true
  return 0
}

# Un lien qui ne mene pas a un chemin du depot : un schema (http:, https:, mailto:, tel:,
# ftp:, sms:...), un lien relatif au schema (//cdn.exemple.fr/x.js), une ancre seule, un
# emplacement a remplir d'un gabarit. Le schema compte deux lettres au moins, pour ne pas
# prendre un chemin Windows pour un schema. `http-api.md` est un fichier, pas un schema.
RE_SCHEMA='^[A-Za-z][A-Za-z0-9+.-]+:'
lien_externe() { # <lien> : code 0 si ce n'est pas un chemin du depot
  case "$1" in
    '#'*|//*|*'<'*|*'{{'*) return 0 ;;
  esac
  if [[ "$1" =~ $RE_SCHEMA ]]; then return 0; fi
  return 1
}

# La cible d'un lien markdown : `[a](x.md "titre")` pointe vers x.md, le titre n'en fait pas
# partie. Le resultat est dans CIBLE, ancre retiree.
SQ="'"
CIBLE=""
cible_du_lien() { # <texte entre parentheses>
  local l="$1"
  case "$l" in
    *' "'*) l="${l%% \"*}" ;;
    *" $SQ"*) l="${l%% $SQ*}" ;;
  esac
  CIBLE="${l%%#*}"
  return 0
}

# Fiches atteintes depuis l'index par des liens, trois sauts au plus.
fiches_atteintes() { # <index> -> un chemin par ligne
  local front="$1" tous="$1" suivants f dir lien cible i=0
  while [ "$i" -lt 3 ] && [ -n "$front" ]; do
    suivants=""
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      dir="$(dirname "$f")"
      while IFS= read -r lien; do
        [ -n "$lien" ] || continue
        if lien_externe "$lien"; then continue; fi
        cible_du_lien "$lien"; cible="$CIBLE"
        [ -n "$cible" ] || continue
        normaliser "$dir/$cible"
        cible="$NORM"
        case "$cible" in *.md) ;; *) continue ;; esac
        if grep -qxF "$cible" <<<"$tous"; then continue; fi
        tous="$tous
$cible"
        suivants="${suivants:+$suivants
}$cible"
      done <<FIN2
$(liens_de "$f")
FIN2
    done <<FIN
$front
FIN
    front="$suivants"
    i=$((i + 1))
  done
  printf '%s\n' "$tous"
  return 0
}

# CLAUDE.md et AGENTS.md sont-ils deja raccordes ? Lien symbolique dans un sens ou
# dans l'autre, ou ligne `@AGENTS.md` dans le CLAUDE.md.
agents_raccorde() {
  if [ -L CLAUDE.md ] || [ -L AGENTS.md ]; then
    if [ CLAUDE.md -ef AGENTS.md ]; then return 0; fi
  fi
  if grep -qE '^[[:space:]]*@(\./)?AGENTS\.md[[:space:]]*$' CLAUDE.md 2>/dev/null; then return 0; fi
  return 1
}

# Le fichier qui porte vraiment les regles quand CLAUDE.md n'est qu'un renvoi : sa
# cible s'il est lien symbolique, le premier import s'il ne contient que des
# imports. Vide quand CLAUDE.md porte ses propres regles ou n'existe pas.
claude_renvoi() {
  local autres premier
  [ -f CLAUDE.md ] || return 0
  if [ -L CLAUDE.md ]; then
    readlink CLAUDE.md
    return 0
  fi
  autres="$(grep -m1 -vE '^[[:space:]]*(@[^[:space:]]+[[:space:]]*)?$' CLAUDE.md || true)"
  premier="$(grep -m1 -E '^[[:space:]]*@' CLAUDE.md || true)"
  if [ -z "$autres" ] && [ -n "$premier" ]; then
    premier="${premier#"${premier%%[![:space:]]*}"}"
    premier="${premier#@}"
    printf '%s\n' "${premier%%[[:space:]]*}"
  fi
  return 0
}
CLAUDE_RENVOI="$(claude_renvoi)"

# Une valeur de test evidente dans un fichier de test : la fixture d'un scanner
# anti-fuite, pas une cle qui a fuite. Les deux conditions ensemble, une vraie
# valeur dans un fichier de test reste signalee.
secret_factice() { # <ligne de git grep : chemin:ligne:contenu>
  local chemin="${1%%:*}" contenu
  case "/$chemin" in
    */tests/*|*/test/*|*/__tests__/*|*/fixtures/*|*/spec/*|*/test_*|*_test.*|*.test.*|*.spec.*) ;;
    *) return 1 ;;
  esac
  contenu="${1#*:}"; contenu="${contenu#*:}"
  grep -qiE 'factice|fake|dummy|example|exemple|placeholder|changeme|redacted|xxxx|0000|(.)\1\1\1\1\1\1' <<<"$contenu"
}

# fichiers markdown de doc, hors archives et hors dependances
docs_md() {
  trouver . -name '*.md' | sed 's|^\./||' | sort
}

# Un journal est un markdown a entrees datees. Le CHANGELOG porte le format que le
# bloc declare, ou celui que `journal_detecter` trouve. Les autres journaux de la
# doc sont lus en `## ...AAAA-MM-JJ`, le format le plus courant.
MOTIF_DATE_TITRE="$(journal_motif date-titre)"
JMOTIF=""
motif_du_journal() { # <fichier> : pose JMOTIF, vide si le journal n'a aucun format reconnu
  if [ "$1" = CHANGELOG.md ]; then
    JMOTIF="$(journal_motif "$(journal_detecter CHANGELOG.md)")"
  else
    JMOTIF="$MOTIF_DATE_TITRE"
  fi
  return 0
}
nb_entrees_datees() { # <fichier> -> nombre d'entrees datees
  motif_du_journal "$1"
  if [ -n "$JMOTIF" ]; then grep -cE "$JMOTIF" "$1" 2>/dev/null || true; else echo 0; fi
  return 0
}

# Longueur du bloc « Etat a la reprise » : du titre qui contient « reprise » au
# prochain titre de niveau 2.
bloc_reprise_lignes() { # <TODOS.md> -> nombre de lignes, 0 si absent
  awk -v re="$RE_BLOC" 'BEGIN{n=0; dans=0}
       /^## /{ if (dans) exit; if (tolower($0) ~ re) dans=1 }
       dans{n++}
       END{print n}' "$1" 2>/dev/null || echo 0
}

# Section la plus longue d'un markdown, en lignes, avec son titre.
section_max() { # <fichier> -> "N titre"
  awk '/^## /{ if (t != "") print n, t; t=$0; n=0 } { n++ } END{ if (t != "") print n, t }' "$1" 2>/dev/null \
    | sort -rn | sed -n '1p'
}

# Les entrees d'un journal dans l'ordre du fichier, une ligne "N titre" chacune.
entrees_du_journal() { # <fichier>
  local f="$1" total
  motif_du_journal "$f"
  [ -n "$JMOTIF" ] || return 0
  total="$(awk 'END{print NR}' "$f")"
  grep -nE "$JMOTIF" "$f" 2>/dev/null | awk -F: -v total="$total" '
    { n = $1; t = substr($0, length($1) + 2)
      if (p) print n - p, pt
      p = n; pt = t }
    END { if (p) print total - p + 1, pt }' || true
  return 0
}

# Entree la plus longue d'un journal, en lignes.
entree_max() { # <fichier> -> "N titre"
  entrees_du_journal "$1" | sort -rn | sed -n '1p'
  return 0
}

# Les en-tetes des fiches, lus d'un coup : un awk pour toutes au lieu d'un head et de deux grep
# par fiche. Une ligne par fiche, `chemin<US>statut<US>date<US>portee` : la ligne de statut
# dans les six premieres lignes, la premiere date qu'elle porte, la ligne de portee dans les
# huit premieres. Une fiche vide n'a pas de ligne, l'appelant la traite a part.
entetes_fiches() { # <fiches, une par ligne, sur l'entree standard>
  local liste
  liste="$(cat)"
  [ -n "$liste" ] || return 0
  printf '%s\n' "$liste" | sed 's|^|./|' | tr '\n' '\000' \
    | xargs -0 awk -v rs="$RE_STATUT" -v rp="$RE_PORTEE" -v U="$US" '
        function fin() { if (f != "") { sub(/^\.\//, "", f); print f U st U da U po } }
        FNR == 1 { fin(); f = FILENAME; st = ""; da = ""; po = "" }
        FNR <= 6 && st == "" && $0 ~ rs {
          st = $0
          if (match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) da = substr($0, RSTART, RLENGTH)
        }
        FNR <= 8 && po == "" && $0 ~ rp { po = $0 }
        END { fin() }' 2>/dev/null || true
  return 0
}

echo "=============================================="
echo " Audit de contexte : $(basename "$ROOT")"
echo " $TODAY"
echo "=============================================="

PROFIL="$(conv_lire profil)"
TAILLE_DECLAREE="$(conv_lire taille)"
BLOC_V="$(conv_version)"

# Les zones : un CODEMAP.md seul dans un sous-repertoire, sans TODOS ni
# CHANGELOG a cote. Un niveau autonome porte les trois piliers.
NIVEAUX=""
ZONES=""
for c in $(trouver . -name CODEMAP.md -path './*/*' | sort); do
  d="${c%/CODEMAP.md}"; d="${d#./}"
  grep -q '{{' "$c" 2>/dev/null && continue
  if [ -f "$d/TODOS.md" ] && [ -f "$d/CHANGELOG.md" ]; then
    NIVEAUX="$NIVEAUX $d"
  else
    ZONES="$ZONES $d"
  fi
done

if [ "$BUDGET_SEUL" -eq 0 ]; then

# --- 0. le terrain ------------------------------------------------------------
# Ce que le projet porte deja. Un projet neuf n'a rien, un projet existant a
# souvent une doc rangee autrement, et parfois une autre convention d'agent qui
# ferait une seconde source de verite. On se greffe sur l'existant, on ne pose
# pas des gabarits vides a cote.
echo
echo "0. Le terrain"
SEC=0

KIT_COMPLET=1
for f in CODEMAP.md TODOS.md CHANGELOG.md; do
  [ -f "$f" ] || KIT_COMPLET=0
done

# Documentation deja presente, hors kit
DOC_DIRS=""
for d in docs doc documentation wiki .claude/docs notes; do
  [ -d "$d" ] && DOC_DIRS="$DOC_DIRS $d"
done
ADR_DIRS=""
for d in adr docs/adr doc/adr docs/decisions docs/architecture/decisions; do
  [ -d "$d" ] && ADR_DIRS="$ADR_DIRS $d"
done
RACINE_MD="$(find . -maxdepth 1 -name '*.md' 2>/dev/null | sed 's|^\./||' \
  | grep -vE '^(CODEMAP|TODOS|CHANGELOG|CLAUDE|AGENTS|README|MEMORY)\.md$' | sort || true)"

[ -n "$DOC_DIRS" ] && info "documentation existante :$DOC_DIRS"
[ -n "$ADR_DIRS" ] && info "decisions existantes :$ADR_DIRS"
if [ -n "$RACINE_MD" ]; then
  info "markdown a la racine, hors kit : $(printf '%s ' $RACINE_MD)"
  [ "$KIT_COMPLET" -eq 0 ] && info "  chacun a un proprietaire dans la convention, voir references/PROFILS-PROJETS.md"
fi

# Conventions d'agent concurrentes. Deux sources de verite divergent toujours,
# et rien ne le signale au moment ou ça arrive.
CONCUR=""
for c in AGENTS.md GEMINI.md .cursorrules .clinerules .windsurfrules CONVENTIONS.md \
         .github/copilot-instructions.md .cursor/rules memory-bank .roo; do
  [ -e "$c" ] && CONCUR="$CONCUR $c"
done
if [ -n "$CONCUR" ]; then
  for c in $CONCUR; do
    case "$c" in
      AGENTS.md)
        if [ -f CLAUDE.md ] && agents_raccorde; then
          info "AGENTS.md est raccorde a CLAUDE.md (lien symbolique ou @AGENTS.md), une seule source de regles"
        elif [ -f CLAUDE.md ]; then
          alerte "AGENTS.md et CLAUDE.md coexistent. Claude Code ne lit pas AGENTS.md, Codex ne lit pas CLAUDE.md. Sans raccord, deux sources divergent en silence. Le raccord est une ligne @AGENTS.md en tete du CLAUDE.md, ou un lien symbolique"
        else
          info "AGENTS.md present, c'est le porteur des regles ici. La convention s'y greffe au lieu de creer un CLAUDE.md"
        fi ;;
      memory-bank|.roo)
        alerte "$c present, c'est une convention de memoire d'agent concurrente. Elle porte le meme savoir que les piliers, et deux copies divergent. Choisir laquelle fait foi et archiver l'autre" ;;
      *)
        info "$c present, autre convention d'agent. Verifier qu'elle ne redit pas les piliers" ;;
    esac
  done
fi

# Version du bloc. Un bloc sans ligne `version:` ou en version ancienne vient d'un
# skill plus vieux : le mode migrer du skill le remet d'aplomb. Sans bloc du tout, la
# section 1 le dit et ctx-init.sh le pose, il n'y a rien a migrer.
case "$BLOC_V" in
  0) ;;
  ''|*[!0-9]*)
    alerte "le bloc contexte:convention porte une version illisible ($BLOC_V). Lancer le mode migrer du skill" "$(conv_trouver)" ;;
  *)
    if [ "$BLOC_V" -lt "$CTX_VERSION" ]; then
      if [ -z "$(conv_lire version)" ]; then
        alerte "le bloc contexte:convention n'a pas de ligne version:, il vient d'une version ancienne du skill (la courante est la $CTX_VERSION). Lancer le mode migrer du skill" "$(conv_trouver)"
      else
        alerte "le bloc contexte:convention est en version $BLOC_V, la courante est la $CTX_VERSION. Lancer le mode migrer du skill" "$(conv_trouver)"
      fi
    fi ;;
esac

if [ "$KIT_COMPLET" -eq 1 ] && [ -z "$CONCUR" ]; then
  ok "un seul porteur de convention, rien qui concurrence les piliers"
elif [ "$KIT_COMPLET" -eq 0 ]; then
  info "le kit est incomplet, voir la section 1. Le mode INIT se greffe sur ce qui existe"
fi

# --- 1. presence du kit -------------------------------------------------------
echo
echo "1. Kit de contexte"
SEC=1
for f in CODEMAP.md TODOS.md CHANGELOG.md; do
  if [ -f "$f" ]; then ok "$f"; else alerte "$f manquant"; fi
done
if [ ! -f CLAUDE.md ]; then
  info "CLAUDE.md absent, les regles du projet n'ont pas de support"
elif [ -n "$CLAUDE_RENVOI" ]; then
  info "CLAUDE.md se reduit a un renvoi vers $CLAUDE_RENVOI, c'est ce fichier qui porte les regles"
  # Un renvoi qui ne mene a rien, ou a un fichier vide : aucune regle n'est chargee.
  if [ ! -f "$CLAUDE_RENVOI" ]; then
    alerte "CLAUDE.md renvoie vers $CLAUDE_RENVOI, qui n'existe pas. Aucune regle de projet n'est chargee" CLAUDE.md
  elif ! grep -q '[^[:space:]]' "$CLAUDE_RENVOI" 2>/dev/null; then
    alerte "CLAUDE.md renvoie vers $CLAUDE_RENVOI, qui est vide. Aucune regle de projet n'est chargee" CLAUDE.md
  fi
elif ! grep -q '[^[:space:]]' CLAUDE.md 2>/dev/null; then
  alerte "CLAUDE.md est vide. Les regles du projet n'ont aucun support, ou un renvoi @AGENTS.md si un autre fichier les porte" CLAUDE.md
else
  ok "CLAUDE.md"
fi
# Vestige d'une convention a quatre piliers. Le contenu a un proprietaire ailleurs
# maintenant, le laisser en place cree deux sources de verite.
# Un projet qui s'en sert volontairement le declare dans ecarts: (MEMORY.md=<justification>) :
# l'alerte devient une information qui cite la justification.
if [ -f MEMORY.md ]; then
  ECART_MEMORY=""
  case "$(conv_lire ecarts)" in
    *MEMORY.md=*)
      ECART_MEMORY="$(conv_lire ecarts | sed -e 's/^.*MEMORY\.md=//' -e 's/,[[:space:]]*[A-Za-z][A-Za-z0-9._-]*=.*$//' -e 's/[[:space:]]*$//')"
      ;;
  esac
  if [ -n "$ECART_MEMORY" ]; then
    info "MEMORY.md commite a la racine, ecart declare dans ecarts: $ECART_MEMORY"
  else
    alerte "MEMORY.md present, la convention n'a plus de pilier memoire. Declarer l'ecart dans la ligne ecarts: du bloc (MEMORY.md=<justification>), ou drainer le fichier : decisions vers docs/decisions/, pieges vers la fiche du module ou les zones sensibles du CODEMAP, preferences vers CLAUDE.md"
  fi
fi
if [ -z "$DOCS_DIR" ]; then
  info "le bloc declare docs: aucune, pas de fiches dans ce projet"
elif [ -d "$DOCS_DIR" ]; then
  ok "$DOCS_DIR/"
  [ -f "$DOCS_DIR/README.md" ] || alerte "$DOCS_DIR/README.md manquant, l'index est obligatoire"
else
  alerte "$DOCS_DIR/ manquant"
fi
if [ -z "$ARCH_DIR" ]; then
  info "le bloc declare archives: aucune, rien n'est archive dans ce projet"
elif [ -d "$ARCH_DIR" ]; then
  ok "$ARCH_DIR/"
  [ -f "$ARCH_DIR/README.md" ] || alerte "$ARCH_DIR/README.md manquant, l'index est obligatoire"
else
  alerte "$ARCH_DIR/ manquant"
fi

BLOC_FIC="$(conv_trouver)"
if [ -n "$PROFIL" ]; then
  info "profil declare : $PROFIL"
elif [ -n "$BLOC_FIC" ]; then
  info "bloc contexte:convention lu dans $BLOC_FIC, sans profil declare"
else
  info "aucun bloc contexte:convention, chemins par defaut"
fi

# Sans --root, la racine se deduit de git, donc appeler le script depuis un
# sous-projet audite le PARENT et pas le sous-projet. Silencieux et couteux.
if [ "$RACINE_DEDUITE" -eq 1 ] && [ "$APPEL" != "$ROOT" ]; then
  alerte "appele depuis ${APPEL#"$ROOT"/}, mais c'est $ROOT qui est audite. La racine est deduite de git. Pour auditer le sous-projet : ctx-audit.sh --root ${APPEL#"$ROOT"/}"
fi

# Le contexte hors git. Un .md ignore par git (notes locales, context-input/, CLAUDE.local.md)
# reste du contexte, l'audit le lit comme le reste. Mais il ne voyage ni vers un collegue ni
# vers une autre machine : une information, jamais une alerte. Ce qui est sous un dossier
# elague (node_modules, un Library/ de moteur, `ignorer:`) ne compte pas. Un seul awk filtre
# la liste de git contre les motifs d'elagage, sans un sous-processus par chemin.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  HG="$(git -c core.quotepath=off ls-files -o -i --exclude-standard -- '*.md' 2>/dev/null | LC_ALL=C awk -v ex="$EXCLUS" '
    BEGIN {
      n = split(ex, mots, " ")
      for (i = 1; i <= n; i++) {
        if (mots[i] == "-not" || mots[i] == "-path") continue
        p = mots[i]
        gsub(/[][\\.+?(){}|^$]/, "\\\\&", p)
        gsub(/\*/, ".*", p)
        motifs[++k] = "^" p "$"
      }
    }
    {
      q = "./" $0; sauter = 0
      for (i = 1; i <= k; i++) if (q ~ motifs[i]) { sauter = 1; break }
      if (sauter) next
      nb++
      if (nb <= 3) ex3 = ex3 (nb > 1 ? ", " : "") $0
    }
    END { if (nb > 0) printf "%d\t%s\n", nb, ex3 }' || true)"
  if [ -n "$HG" ]; then
    info "${HG%%"$TAB"*} fichier(s) .md de contexte ignores par git : ils ne voyagent ni vers un collegue ni vers une autre machine (exemples : ${HG#*"$TAB"})"
  fi
fi

# --- 1b. niveaux imbriques et zones -------------------------------------------
# Un monorepo porte plusieurs kits, chacun est un niveau autonome a cloturer a
# part. Une zone ne porte qu'une carte, l'etat et le journal restent a la racine.
# Dans les deux cas le parent pointe, il n'absorbe pas.
echo
echo "1b. Niveaux imbriques et zones"
SEC=1b
if [ -n "$NIVEAUX" ]; then
  for n in $NIVEAUX; do
    alerte "$n porte son propre kit, c'est un niveau a auditer et a cloturer a part : ctx-audit.sh --root $n"
    grep -q "$n" CODEMAP.md 2>/dev/null \
      || alerte "$n n'est cite nulle part dans le CODEMAP de la racine, le parent doit pointer vers lui"
  done
else
  ok "aucun kit imbrique, un seul niveau a tenir"
fi
if [ -n "$ZONES" ]; then
  for z in $ZONES; do
    info "zone : $z ($(lignes "$z/CODEMAP.md") lignes de carte$([ -f "$z/CLAUDE.md" ] && printf ', CLAUDE.md de %s lignes' "$(lignes "$z/CLAUDE.md")"))"
    grep -q "$z" CODEMAP.md 2>/dev/null \
      || alerte "la zone $z n'est pas citee dans le CODEMAP de la racine, il doit pointer vers elle"
  done
else
  info "aucune zone, le CODEMAP de la racine porte toute la carte"
fi
# Un CLAUDE.md de sous-repertoire sans carte a cote : il se charge quand on touche
# un fichier du sous-arbre, mais rien ne dit ou est la carte de cette zone.
for c in $(trouver . -name CLAUDE.md -path './*/*' -not -path './.claude/*' | sort); do
  d="${c%/CLAUDE.md}"; d="${d#./}"
  [ -f "$d/CODEMAP.md" ] || info "$d porte un CLAUDE.md sans CODEMAP.md, une zone sans carte"
done

# --- 2. fraicheur -------------------------------------------------------------
echo
echo "2. Fraicheur"
SEC=2
# Le format du journal vient du bloc, sinon de ce que le CHANGELOG contient. La date
# de la derniere entree se lit avec le motif de ce format, hors blocs de code.
CL_FORMAT="$(journal_detecter CHANGELOG.md)"
CL_DATE=""
if [ -f CHANGELOG.md ] && [ -n "$CL_FORMAT" ]; then
  CL_DATE="$(awk '/^[ \t]*```/{c=!c; next} !c' CHANGELOG.md \
             | grep -E "$(journal_motif "$CL_FORMAT")" | sed -n '1p' \
             | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sed -n '1p' || true)"
  if [ -n "$(conv_journal_format)" ]; then
    info "journal CHANGELOG.md : format $CL_FORMAT, declare par le bloc"
  else
    info "journal CHANGELOG.md : format $CL_FORMAT, trouve dans le fichier"
  fi
fi
if [ -n "$CL_DATE" ]; then
  jours_depuis "$CL_DATE"; d="$JOURS"
  if [ -n "$d" ] && [ "$d" -gt 30 ]; then
    alerte "derniere entree CHANGELOG le $CL_DATE, soit $d jours"
  else
    ok "derniere entree CHANGELOG le $CL_DATE"
  fi
else
  alerte "aucune entree datee dans CHANGELOG.md (formats reconnus : ## AAAA-MM-JJ, ## [x] - AAAA-MM-JJ, [AAAA-MM-JJ] [TYPE])"
fi

# La date de la carte : sa ligne de mise a jour, hors du bloc contexte:convention (une date
# de chemin dans `exceptions:` n'est pas la sienne). Sans cette ligne, la premiere date hors
# du bloc. Une ligne de piege datee plus haut ne passe devant que dans ce repli.
CM_DATE=""
if [ -f CODEMAP.md ]; then
  CM_HORS_BLOC="$(awk '/<!-- contexte:convention/{b=1} !b{print} b && /-->/{b=0}' CODEMAP.md)"
  CM_DATE="$(printf '%s\n' "$CM_HORS_BLOC" \
             | grep -iE '(mise +[^ ]+ +jour|last +updated)' \
             | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sed -n '1p' || true)"
  [ -n "$CM_DATE" ] || CM_DATE="$(printf '%s\n' "$CM_HORS_BLOC" \
             | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sed -n '1p' || true)"
fi
[ -n "$CM_DATE" ] && info "CODEMAP date du $CM_DATE" || alerte "CODEMAP.md sans date de mise a jour"

if [ -f TODOS.md ]; then
  if grep -qiE "$RE_REPRISE" TODOS.md; then
    # La date du bloc, du titre qui contient « reprise » au titre suivant : une date de tete
    # de fichier ou d'une section plus haute n'est pas celle de l'etat.
    TD_DATE="$(awk -v re="$RE_BLOC" '/^## /{ if (dans) exit; if (tolower($0) ~ re) dans=1 } dans{print}' TODOS.md \
               | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sed -n '1p' || true)"
    jours_depuis "${TD_DATE:-}"; d="$JOURS"
    if [ -n "$d" ] && [ "$d" -gt 14 ]; then
      alerte "bloc Etat a la reprise date du $TD_DATE, soit $d jours"
    else
      ok "bloc Etat a la reprise present (${TD_DATE:-sans date})"
    fi
  else
    alerte "TODOS.md n'a pas de bloc '$LIB_REPRISE', un redemarrage a froid perdrait le fil"
  fi
fi

# --- 3. perimetre modifie -----------------------------------------------------
echo
echo "3. Perimetre modifie depuis la derniere entree CHANGELOG"
SEC=3
MODIFS="$( { git status --porcelain -uall 2>/dev/null | sed 's/^...//' ;
             if [ -n "$CL_DATE" ]; then
               # L'heure explicite : une date seule est completee par l'heure courante,
               # et la liste des fichiers touches varierait a la seconde.
               git log --since="${CL_DATE}T00:00:00" --name-only --pretty=format: 2>/dev/null
             else
               git log -20 --name-only --pretty=format: 2>/dev/null
             fi ; } | grep -v '^$' | sort -u || true)"
NB_MODIFS="$(printf '%s\n' "$MODIFS" | grep -c . || true)"
if [ "${NB_MODIFS:-0}" -eq 0 ]; then
  ok "rien de modifie"
else
  info "$NB_MODIFS fichier(s) touche(s)"
  head -15 <<<"$MODIFS" | sed 's/^/       /'
  [ "$NB_MODIFS" -gt 15 ] && printf '       ... et %s de plus\n' "$((NB_MODIFS - 15))"
fi

# --- 4. etat des fiches docs/ -------------------------------------------------
echo
echo "4. Fiches $DOCS_DIR/"
SEC=4
if [ -n "$DOCS_DIR" ] && [ -d "$DOCS_DIR" ]; then
  NB_FICHES=0
  INDEX_DOCS="$DOCS_DIR/README.md"
  ATTEINTES=""
  INDEX_TXT=""
  if [ -f "$INDEX_DOCS" ]; then
    ATTEINTES="$(fiches_atteintes "$INDEX_DOCS")"
    INDEX_TXT="$(cat "$INDEX_DOCS")"
  fi
  # Le awk ne rend rien pour une fiche vide : elle se traite apres, comme un en-tete absent.
  LISTE_FICHES="$(find "$DOCS_DIR" -name '*.md' -not -name 'README.md' 2>/dev/null | sort)"
  VIDES="$(find "$DOCS_DIR" -name '*.md' -not -name 'README.md' -empty 2>/dev/null | sort)"
  while IFS="$US" read -r f entete vdate portee; do
    [ -n "$f" ] || continue
    NB_FICHES=$((NB_FICHES + 1))
    # Un jugement deja rendu, ecrit dans `exceptions: fiche=<chemin>`
    if [ -n "$EXCEPTIONS" ] && exception_de fiche "$f"; then continue; fi
    if [ -z "$entete" ]; then
      alerte "$f : pas d'en-tete de statut"
      continue
    fi
    case "$entete" in
      *"🔴"*) alerte "$f : marquee obsolete, a deplacer vers archives/ maintenant" ;;
      *"🟡"*) alerte "$f : marquee a verifier" ;;
    esac
    if [ -z "$vdate" ]; then
      alerte "$f : en-tete sans date de verification"
    else
      jours_depuis "$vdate"; d="$JOURS"
      if [ -n "$d" ] && [ "$d" -gt "$PEREMPTION" ]; then
        alerte "$f : verifiee il y a $d jours (seuil $PEREMPTION)"
      fi
    fi
    # la portee recoupe-t-elle un fichier modifie ? Une fiche verifiee aujourd'hui
    # a deja ete relue, la signaler ferait du bruit a chaque cloture. Et un ADR ne
    # se redate jamais, il se supersede, donc sa portee n'a pas a etre surveillee.
    case "$f" in *fecisions/*|*decisions/*|*/adr/*) portee="" ;; esac
    if [ -n "$portee" ] && [ "${NB_MODIFS:-0}" -gt 0 ] && [ "${vdate:-}" != "$TODAY" ]; then
      while IFS= read -r p; do
        prefixe="${p%%\**}"
        prefixe="${prefixe%/}"
        [ -n "$prefixe" ] || continue
        if grep -q "^$prefixe" <<<"$MODIFS"; then
          alerte "$f : sa portee ($p) a bouge, relire la fiche"
          break
        fi
      done <<FIN2
$(printf '%s' "$portee" | grep -oE '`[^`]+`' | tr -d '`' || true)
FIN2
    fi
    # indexee ? Citee dans l'index par son nom, ou atteinte depuis lui par des liens,
    # trois sauts au plus (index racine, sous-index de zone, fiche).
    base="${f##*/}"
    if [ -f "$INDEX_DOCS" ]; then
      case "$INDEX_TXT" in *"$base"*) ;; *)
        case "$NL$ATTEINTES$NL" in *"$NL$f$NL"*) ;; *)
          alerte "$f : absente de l'index $INDEX_DOCS" ;;
        esac ;;
      esac
    fi
  done <<FIN
$(printf '%s\n' "$LISTE_FICHES" | entetes_fiches)
FIN
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    NB_FICHES=$((NB_FICHES + 1))
    if [ -n "$EXCEPTIONS" ] && exception_de fiche "$f"; then continue; fi
    alerte "$f : pas d'en-tete de statut"
  done <<FIN
$VIDES
FIN
  [ "$NB_FICHES" -eq 0 ] && info "aucune fiche pour l'instant" \
                         || info "$NB_FICHES fiche(s) examinee(s)"
fi

# --- 5. modules sans fiche ----------------------------------------------------
echo
echo "5. Modules sans fiche"
SEC=5
SRC=""
for d in src lib app packages apps internal cmd services; do [ -d "$d" ] && SRC="$SRC $d"; done
if [ -n "$SRC" ]; then
  trouve=0
  for base in $SRC; do
    for m in $(find "$base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort); do
      nom="$(basename "$m")"
      case "$nom" in .*|__pycache__|node_modules|test|tests) continue ;; esac
      # Un sous-projet qui porte son propre kit n'est pas un module du parent. Lui
      # reclamer une fiche ici pousserait a dupliquer sa doc, ce que la convention
      # interdit. Il est signale en section 1b comme niveau a part. Une zone qui
      # porte sa carte est deja documentee par elle.
      [ -f "$m/CODEMAP.md" ] && continue
      if [ ! -f "${DOCS_DIR:-docs}/modules/$nom.md" ]; then
        info "$m : pas de fiche ${DOCS_DIR:-docs}/modules/$nom.md"
        trouve=$((trouve + 1))
      fi
    done
  done
  [ "$trouve" -eq 0 ] && ok "chaque module de premier niveau a sa fiche ou sa carte de zone"
  [ "$trouve" -gt 0 ] && info "toutes ne meritent pas une fiche, voir references/DOCS-SYSTEM.md"
else
  info "pas de repertoire source standard detecte"
fi

# --- 6. liens relatifs morts --------------------------------------------------
echo
echo "6. Liens morts"
SEC=6
morts=0
# Les blocs de code, les commentaires HTML, les spans de code et le code indente sont retires
# avant de chercher les liens : ce qu'ils montrent est un exemple, pas un lien de la doc.
while IFS="$US" read -r f lien; do
  [ -n "$lien" ] || continue
  case "$f" in */*) dir="${f%/*}" ;; *) dir=. ;; esac
  # on ignore l'externe et les emplacements a remplir des gabarits
  if lien_externe "$lien"; then continue; fi
  cible_du_lien "$lien"; cible="$CIBLE"
  [ -n "$cible" ] || continue
  case "$cible" in URL|url|LIEN|lien|link|chemin|path) continue ;; esac
  normaliser "$dir/$cible"
  norm="$NORM"
  # Un jugement deja rendu, ecrit dans `exceptions: lien=<chemin>`. Il couvre la cible
  # telle qu'elle est ecrite, la cible depuis la racine, ou la page qui porte le lien.
  if [ -n "$EXCEPTIONS" ]; then
    if exception_de lien "$cible" || exception_de lien "$norm" || exception_de lien "$f"; then continue; fi
  fi
  if [ ! -e "$dir/$cible" ] && [ ! -e "$cible" ]; then
    if sous_module_vide "$norm"; then continue; fi
    alerte "$f : lien mort vers $cible"
    morts=$((morts + 1))
  else
    # Un lien qui resout DANS les archives est un defaut d'un autre genre : le
    # lien marche, et il envoie le lecteur vers du faux ou du froid. La
    # convention l'interdit, et rien ne le voyait.
    if [ -n "$ARCH_DIR" ]; then
      case "$norm" in
        "$ARCH_DIR"/*|*/"$ARCH_DIR"/*)
          alerte "$f : lie vers l'archive $cible. Une fiche vivante ne cite pas une archive, retirer le lien ou le reformuler en prose"
          morts=$((morts + 1)) ;;
      esac
    fi
  fi
done <<FIN
$(docs_md | liens_tous)
FIN
[ "$morts" -eq 0 ] && ok "aucun lien relatif casse"

# --- 7. coherence des archives ------------------------------------------------
# Quatre defauts eprouves sur un depot d'essai, aucun n'etait vu avant :
# l'index cherche par nom de base, un remplacant qui ne resout plus, un archive
# recree en vivant au meme chemin, et l'index lui-meme jamais mesure ni relu.
echo
echo "7. Archives"
SEC=7
if [ -n "$ARCH_DIR" ] && [ -d "$ARCH_DIR" ]; then
  nb=0
  # Un seul awk lit l'en-tete de toutes les archives, la boucle ne lance plus rien par
  # fichier : sur 250 archives, une douzaine de head et de grep chacune coutaient 2,7 s.
  # Un enregistrement par fichier, champs separes par US : le chemin, l'en-tete ARCHIVE
  # present dans les 6 premieres lignes, les chemins en backticks de la ligne « Remplace
  # par » puis de la ligne « Origine » (separes par RS_), une rotation ou un jugement dit
  # en prose dans les 8 premieres lignes, le nombre de lignes lues. L'index se lit une
  # fois : un chemin n'a pas de saut de ligne, chercher dans le texte vaut chercher
  # ligne a ligne.
  ARCH_INDEX=""
  if [ -f "$ARCH_DIR/README.md" ]; then ARCH_INDEX="$(cat "$ARCH_DIR/README.md")"; fi
  ARCH_ENR="$(find "$ARCH_DIR" -name '*.md' -not -name 'README.md' 2>/dev/null | sort | awk -v remp="$RE_REMPL" -v orig="$RE_ORIGINE" '
    function jetons(s,   t, r) {
      r = ""
      while (match(s, /`[^`]+`/)) {
        t = substr(s, RSTART + 1, RLENGTH - 2)
        r = r (r == "" ? "" : "\036") t
        s = substr(s, RSTART + RLENGTH)
      }
      return r
    }
    $0 != "" {
      f = $0; n = 0; e6 = 0; rot = 0; rem = ""; ori = ""; vrem = 0; vori = 0
      while ((getline l < f) > 0) {
        n++
        if (n > 8) continue
        if (n <= 6 && (index(l, "ARCHIV") > 0 || tolower(l) ~ /^[[:space:]]*>.*archiv/)) e6 = 1
        if (!vrem && l ~ remp) { vrem = 1; rem = l }
        if (!vori && l ~ orig) { vori = 1; ori = l }
        if (l !~ orig && l !~ remp && tolower(l) ~ /rotation|jugement|volontaire|deliber|intentionn/) rot = 1
      }
      close(f)
      printf "%s\037%d\037%s\037%s\037%d\037%d\n", f, e6, jetons(rem), jetons(ori), rot, n
    }')"
  while IFS="$US" read -r f e6 cibles origines rotation nlu; do
    [ -n "$f" ] || continue
    nb=$((nb + 1))
    # Un jugement deja rendu, ecrit dans `exceptions: archive=<chemin>`
    if [ -n "$EXCEPTIONS" ] && exception_de archive "$f"; then continue; fi
    # L'en-tete s'ecrit en capitales ou non : une citation en tete qui parle
    # d'archive suffit. Un mot « archive » dans le texte ne compte pas.
    if [ "$e6" -eq 0 ]; then
      alerte "$f : pas d'en-tete ARCHIVE"
    fi
    # Index cherche par CHEMIN COMPLET. Par nom de base, un nom present dans la
    # colonne « Remplace par » d'une autre ligne suffisait a passer.
    if [ -f "$ARCH_DIR/README.md" ]; then
      case "$ARCH_INDEX" in *"$f"*) ;; *) alerte "$f : absent de l'index $ARCH_DIR/README.md" ;; esac
    fi
    # Le remplacant resout-il encore ? C'est le champ qui fait la valeur de
    # l'en-tete, et il pourrit sans bruit.
    if [ -n "$cibles" ]; then
      while IFS= read -r cible; do
        case "$cible" in *' '*|*aucun*|*'<'*|*'{{'*|'') continue ;; esac
        # Un chemin porte un / et ne finit pas par un /. « SKILL.md » ou
        # « references/ » nomment une partie d'un paquet, pas un fichier du depot.
        case "$cible" in */) continue ;; esac
        case "$cible" in */*) : ;; *) continue ;; esac
        [ -e "$cible" ] || alerte "$f : son remplacant $cible n'existe plus"
      done <<FIN3
${cibles//$RS_/$NL}
FIN3
    fi
    # Un vivant au meme chemin que l'origine : deux verites en face, dont une
    # marquee fausse.
    orig="${origines//$RS_/$NL}"
    # Une rotation ou un jugement ecrit en prose dans l'en-tete (recreation voulue) :
    # la coexistence est deja tranchee, l'alerte reviendrait a chaque audit sans rien dire.
    # Les lignes `Origine :` et `Remplace par :` ne comptent pas : elles portent des chemins,
    # et `docs/modules/rotation.md` n'est pas un jugement.
    # Un resume pose par ctx-rotation.sh --plans (via ctx-archive.sh --resume) porte le
    # marqueur plan-resume : le vivant est le geste prevu, pas une recreation.
    resume=0
    if [ -n "$orig" ] && [ -f "$orig" ] && grep -qF 'plan-resume' "$orig"; then resume=1; fi
    if [ -n "$orig" ] && [ -e "$orig" ] && [ "$rotation" -eq 0 ] && [ "$resume" -eq 0 ]; then
      alerte "$f : $orig existe aussi en vivant. Un archive recree au meme chemin laisse deux verites en face"
    fi
    # Taille d'un fichier d'archive. Les bots d'archivage de Wikipedia plafonnent
    # une page a 200 Ko, pour la meme raison : au-dela on ne fouille plus, on subit.
    # awk compte une derniere ligne sans saut de ligne que wc ne compte pas : wc tranche
    # des que awk depasse le seuil.
    if [ "$nlu" -gt 1500 ]; then
      n="$(lignes "$f")"
      if [ "$n" -gt 1500 ]; then alerte "$f : $n lignes. Au-dela de 1500 une archive se coupe, par mois ou par sujet"; fi
    fi
  done <<FIN
$ARCH_ENR
FIN
  # L'index est le SEUL fichier des archives qu'on lit vraiment, en archeologie.
  # Il n'etait ni mesure ni relu, et il a porte une affirmation fausse 25 jours.
  if [ -f "$ARCH_DIR/README.md" ]; then
    mesure "$ARCH_DIR/README.md" "index $ARCH_DIR/README.md" 250 400
    while IFS= read -r p; do
      # Les emplacements a remplir des gabarits ne sont pas des chemins.
      case "$p" in *'<'*|*'{{'*|*'>'*) continue ;; esac
      case "$p" in "$ARCH_DIR"/*) [ -e "$p" ] || alerte "index des archives : $p n'existe pas" ;; esac
    done <<FIN
$(grep -oE '`[^`]+`' "$ARCH_DIR/README.md" 2>/dev/null | tr -d '`' | sort -u || true)
FIN
  fi
  [ "$nb" -eq 0 ] && info "archives vides" || info "$nb element(s) archive(s)"
  info "pour y chercher quelque chose : ctx-archeo.sh <motif>, jamais un grep nu"
elif [ -z "$ARCH_DIR" ]; then
  info "le bloc declare archives: aucune, rien a controler ici"
fi

# --- 8. marqueurs laisses dans le code ----------------------------------------
echo
echo "8. Marqueurs dans le code"
SEC=8
MARQ="$(grep -rIn --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=archives \
        --exclude-dir=.venv --exclude-dir=dist --exclude-dir=build \
        -E '(TODO|FIXME|HACK|XXX)[:( ]' . 2>/dev/null | grep -vc '^$' || true)"
if [ "${MARQ:-0}" -gt 0 ]; then
  info "${MARQ} marqueur(s) TODO/FIXME/HACK. Ceux qui comptent doivent etre dans TODOS.md"
else
  ok "aucun marqueur"
fi

# --- 9. secrets, heuristique legere -------------------------------------------
echo
echo "9. Secrets"
SEC=9
SUSPECT="$(git grep -InE '(api[_-]?key|secret|token|password|passwd)[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9_/+-]{16,}' \
           -- . 2>/dev/null | grep -v -E '(\.example|\.sample|templates/|references/)' || true)"
# Deux jugements ne se refont pas a chaque audit : les chemins de `exceptions: secret=<chemin>`,
# et la valeur de test evidente dans un fichier de test (fixture d'un scanner anti-fuite).
FILTRE=""
if [ -n "$SUSPECT" ]; then
  while IFS= read -r l; do
    if [ -n "$EXCEPTIONS" ] && exception_de secret "${l%%:*}"; then continue; fi
    if secret_factice "$l"; then continue; fi
    FILTRE="$FILTRE$l
"
  done <<FIN
$SUSPECT
FIN
fi
if [ -n "$FILTRE" ]; then
  PREMIERS="$(printf '%s' "$FILTRE" | sed -n '1,5p' | cut -d: -f1 | sort -u | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  alerte "valeurs qui ressemblent a des secrets dans des fichiers trackes : $PREMIERS" "${PREMIERS%%,*}"
  printf '%s' "$FILTRE" | sed -n '1,5p' | sed 's/^/       /'
else
  ok "rien de suspect dans les fichiers trackes"
fi

fi # fin des sections 1 a 9, sautees par --budget

# --- 10. budget de contexte ---------------------------------------------------
# Une doc vraie mais trop longue pour etre lue est une doc perdue. Chaque surface
# a une cible, un seuil d'alerte et un seuil de blocage. Les chiffres sont ceux de
# references/BUDGET.md, ils se changent la-bas et ici en meme temps.
echo
echo "10. Budget de contexte"
SEC=10

# taille du projet, en fichiers
NB_FICHIERS="$(trouver . -type f | wc -l | tr -d ' ')"
if   [ "$NB_FICHIERS" -lt 150 ]; then TAILLE=petite
elif [ "$NB_FICHIERS" -le 600 ]; then TAILLE=moyenne
else TAILLE=grande; fi
info "taille mesuree : $TAILLE, $NB_FICHIERS fichiers hors dependances"
# Un elagage se nomme toujours. Au-dela de la liste fixe (node_modules, dist, target...),
# trois sources peuvent sauter des fichiers : un moteur de jeu reconnu a son marqueur a la
# racine, un dossier qui porte un CACHEDIR.TAG, la cle `ignorer:` du bloc.
# Un moteur se reconnait a son marqueur, a la racine ou jusqu'a la profondeur 3 : chaque racine
# trouvee a sa ligne, avec son dossier.
EL_CACHE=""; EL_IGN=""; EL_PLAFOND=""
while IFS= read -r _l; do
  [ -n "$_l" ] || continue
  _c="${_l%%"$TAB"*}"; _d="${_l#*"$TAB"}"; _r="${_d%%"$TAB"*}"; _d="${_d#*"$TAB"}"
  case "$_c" in
    Unity|Unreal|Godot|'Unreal plugin')
      _m=""; _v="ne comptent"
      if [ "$_r" = . ]; then
        case "$_c" in
          Unity)  _m="elagage Unity, reconnu a ProjectSettings/ProjectVersion.txt a la racine" ;;
          Unreal) _m="elagage Unreal, reconnu a un fichier .uproject a la racine" ;;
          Godot)  _m="elagage Godot, reconnu a project.godot a la racine"; _v="ne compte" ;;
        esac
      else
        case "$_c" in
          Unity)           _m="elagage Unity ($_r/), reconnu a $_r/ProjectSettings/ProjectVersion.txt" ;;
          Unreal)          _m="elagage Unreal ($_r/), reconnu a un fichier .uproject dans $_r/" ;;
          'Unreal plugin') _m="elagage Unreal plugin ($_r/), reconnu a son fichier .uplugin" ;;
          Godot)           _m="elagage Godot ($_r/), reconnu a $_r/project.godot"; _v="ne compte" ;;
        esac
      fi
      info "$_m : ${_d//, //, }/ $_v ni dans la taille ni dans les controles" ;;
    CACHEDIR.TAG) EL_CACHE="${_d//, //, }/" ;;
    ignorer)      _n="$(exclusions_compter_ignorer "$_d")"
                  EL_IGN="${EL_IGN:+$EL_IGN, }$_d ($_n)"
                  EL_IGN_N=$(( ${EL_IGN_N:-0} + _n )) ;;
    plafond)      EL_PLAFOND="$_d" ;;
  esac
done <<FIN
$(exclusions_noms_groupes)
FIN
[ -z "$EL_CACHE" ]   || info "elagage par CACHEDIR.TAG, signature verifiee : $EL_CACHE ne comptent ni dans la taille ni dans les controles"
[ -z "$EL_IGN" ]     || info "la cle ignorer: du bloc fait sauter ${EL_IGN_N:-0} fichier(s) : $EL_IGN"
[ -z "$EL_PLAFOND" ] || info "$EL_PLAFOND racine(s) de moteur de jeu au-dela du plafond de 20 : leurs dossiers generes ne sont pas elagues"
# La mesure fait foi. `taille-forcee:` l'impose a la main et les controles suivent alors
# la valeur forcee. Une ligne `taille:` n'est plus lue depuis la version 5.
TAILLE_FORCEE="$(conv_lire taille-forcee)"
case "$TAILLE_FORCEE" in
  '') ;;
  petite|moyenne|grande)
    if [ "$TAILLE_FORCEE" != "$TAILLE" ]; then
      info "le bloc force « taille-forcee: $TAILLE_FORCEE », la mesure donne $TAILLE ($NB_FICHIERS fichiers). Les controles suivent la valeur forcee. La retirer si la mesure convient" "$(conv_trouver)"
    fi
    TAILLE="$TAILLE_FORCEE" ;;
  *) info "taille-forcee: $TAILLE_FORCEE n'est pas une taille connue (petite, moyenne, grande), la mesure est gardee" ;;
esac
case "$BLOC_V" in ''|*[!0-9]*) ;; *)
  if [ "$BLOC_V" -ge 5 ] && [ -n "$TAILLE_DECLAREE" ]; then
    info "la ligne taille: n'est plus lue depuis la version 5, la taille se mesure ($TAILLE). La retirer, ou la passer en taille-forcee:" "$(conv_trouver)"
  fi ;;
esac

# CLAUDE.md de la racine : ni etat, ni recit. Un fichier qui porte beaucoup de
# dates a absorbe de l'histoire, et l'histoire a un autre proprietaire.
# Un CLAUDE.md reduit a un renvoi ne porte rien lui-meme : on mesure le fichier qui
# porte les regles, et on ne dit pas « ok » sur un fichier d'une ligne.
CLAUDE_LU=""
# Un CLAUDE.md vide est dit en section 1, le mesurer « ok » le contredirait.
if [ -f CLAUDE.md ] && grep -q '[^[:space:]]' CLAUDE.md 2>/dev/null; then
  if [ -z "$CLAUDE_RENVOI" ]; then
    mesure CLAUDE.md "CLAUDE.md" 150 200 40000
    CLAUDE_LU=CLAUDE.md
  elif [ -f "$CLAUDE_RENVOI" ] && grep -q '[^[:space:]]' "$CLAUDE_RENVOI" 2>/dev/null; then
    mesure "$CLAUDE_RENVOI" "$CLAUDE_RENVOI (porte les regles de CLAUDE.md)" 150 200 40000 CLAUDE.md
    CLAUDE_LU="$CLAUDE_RENVOI"
  fi
fi
if [ -n "$CLAUDE_LU" ]; then
  nd="$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$CLAUDE_LU" | wc -l | tr -d ' ')"
  [ "$nd" -gt 8 ] && alerte "CLAUDE.md porte $nd dates, un etat ou un recit s'y est glisse. L'etat va dans TODOS, l'histoire au CHANGELOG"
  grep -qiE '^\*\*(etat|état)|^#+ .*(etat|état)' "$CLAUDE_LU" \
    && alerte "CLAUDE.md porte un paragraphe d'etat. Il appartient au bloc de reprise de TODOS.md"
  # Heuristique prudente, en info : une ligne qui porte une date ET un verbe d'etat ou
  # de recit. Un fichier de regles dit ce qui est vrai tout le temps, pas ce qui s'est passe.
  RE_DATE_LIBRE='[0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{1,2}(er)? (janvier|fevrier|février|mars|avril|mai|juin|juillet|aout|août|septembre|octobre|novembre|decembre|décembre) [0-9]{4}'
  RE_RECIT='(etat|état|statut|status)[^.]{0,30}( au | le | du | depuis |as of)|en cours|derni(e|è)re (session|cl(o|ô)ture|mise)|livr(e|é)|termin(e|é)|session du|nous avons|on a |j.ai |a (e|é)t(e|é)|reste (a|à) |prochaine (session|etape|étape)'
  recit="$(md_sans_code "$CLAUDE_LU" | grep -E "$RE_DATE_LIBRE" | grep -iE "$RE_RECIT" || true)"
  nr="$(printf '%s' "$recit" | grep -c . || true)"
  if [ "${nr:-0}" -ge 2 ]; then
    info "CLAUDE.md : $nr ligne(s) portent une date et un verbe d'etat ou de recit, par exemple « $(head -1 <<<"$recit" | cut -c1-70) ». L'etat va dans le bloc de reprise de TODOS, le recit au CHANGELOG" CLAUDE.md
  fi
fi

# Consigne de demarrage non bornee : un CLAUDE.md ou un AGENTS.md qui ordonne de lire en
# entier un fichier plus long que son seuil de blocage. « lis TODOS.md » charge tout le
# fichier, « lis le bloc de reprise de TODOS.md » n'en charge qu'une partie.
RE_ORDRE='(^|[^[:alpha:]])(lis|lire|lisez|read|ouvre|ouvrir|ouvrez|consulte|consulter)([^[:alpha:]]|$)'
RE_NEG="(^|[^[:alpha:]])(ne|n')[^.]{0,25}(pas|jamais|plus)|jamais|sans lire|do not|don't|never|inutile|pas besoin"
# Une lecture bornee limite la portee : « le bloc de reprise de X », « la section Y de X »,
# « les 40 premieres lignes », « head -n », « only the resume block », « jusqu'a ... ». Un mot
# isole ne borne rien : « en premier », « first », « pour la derniere session » ne disent pas
# quelle partie lire, et le fichier se charge en entier. L'ancre `X.md#titre` borne aussi, elle
# se teste a part dans consignes_non_bornees.
# Le debut d'un mot s'ecrit (^|[^[:alpha:]]) : « partir de » ne contient pas « partie ».
AV='(^|[^[:alpha:]])'
RE_BORNE="${AV}(bloc|block|section|rubrique|chapitre|paragraphe|partie|heading|titre)[^.]{0,40}( de | du | d'| of | in | dans | from )"
RE_BORNE="$RE_BORNE|${AV}(uniquement|seulement|only)[^.]{0,30}${AV}(bloc|block|section|rubrique|partie|part|lignes|lines|header|heading|resume|reprise)"
RE_BORNE="$RE_BORNE|[0-9]+[[:space:]]+(premi|derni|first|last)|${AV}(premi[eè]res?|derni[eè]res?|first|last|top)[[:space:]]+[0-9]+"
RE_BORNE="$RE_BORNE|${AV}(head|tail)[[:space:]]+-|${AV}sed[[:space:]]+-n|[0-9]+[[:space:]]+(lignes|entrees|entrées|lines|entries)"
RE_BORNE="$RE_BORNE|${AV}(haut|debut|début|top|beginning|start)[[:space:]]+(de|du|of)[[:space:]]+(la |le |l'|the )?[A-Za-z0-9_./-]*[.]md"
RE_BORNE="$RE_BORNE|jusqu|${AV}(until|up to)${AV}|§"
# Les lignes d'un fichier hors blocs de code, chacune precedee de son numero et de « : ».
lignes_numerotees() { # <fichier>
  awk '/^[ \t]*```/ { f = !f; next } !f { print NR ":" $0 }' "$1"
  return 0
}
consignes_non_bornees() { # <fichier>
  local f="$1" l num txt tok n vu=""
  [ -f "$f" ] || return 0
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    num="${l%%:*}"; txt="${l#*:}"
    if grep -qiE "$RE_NEG" <<<"$txt"; then continue; fi
    if grep -qiE "$RE_BORNE" <<<"$txt"; then continue; fi
    for tok in $(printf '%s\n' "$txt" | grep -oE '[A-Za-z0-9_./-]+\.md' | sort -u || true); do
      tok="${tok#./}"
      case "$txt" in *"$tok#"*) continue ;; esac
      [ -f "$tok" ] || continue
      case " $vu " in *" $tok "*) continue ;; esac
      vu="$vu $tok"
      defauts_de "$tok"
      if [ "$DA" -eq 0 ]; then DA=250; DB=300; fi
      seuils_de "$tok" "$DA" "$DB"
      n="$(lignes "$tok")"
      if [ "$n" -gt "$SEUIL_B" ]; then
        alerte "$f : ordonne de lire $tok sans borner la lecture (ligne $num), or il fait $n lignes, seuil de blocage $SEUIL_B. Nommer la partie a lire, par exemple « le bloc de reprise de $tok »" "$f"
      fi
    done
  done <<FIN
$(lignes_numerotees "$f" | grep -iE "$RE_ORDRE" || true)
FIN
  return 0
}
consignes_non_bornees CLAUDE.md
if [ -f AGENTS.md ] && ! [ CLAUDE.md -ef AGENTS.md ]; then consignes_non_bornees AGENTS.md; fi

# CODEMAP de la racine, et sa section la plus lourde
if [ -f CODEMAP.md ]; then
  mesure CODEMAP.md "CODEMAP.md" 300 400 40000 CODEMAP.md 30000
  sm="$(section_max CODEMAP.md)"
  [ -n "$sm" ] && [ "${sm%% *}" -gt 60 ] \
    && info "section la plus lourde du CODEMAP : ${sm#* }, ${sm%% *} lignes. Au-dessus de 60, elle appelle une zone ou une fiche"
fi

# TODOS : le fichier, le bloc de reprise, et ce qui n'a rien a y faire
if [ -f TODOS.md ]; then
  mesure TODOS.md "TODOS.md" 200 300 30000 TODOS.md 20000
  nb="$(bloc_reprise_lignes TODOS.md)"
  seuils_de reprise 50 80
  if   [ "$nb" -gt "$SEUIL_B" ]; then blocage "bloc Etat a la reprise : $nb lignes, seuil de blocage $SEUIL_B. Il se reecrit depuis l'etat courant, il ne s'empile pas"
  elif [ "$nb" -gt "$SEUIL_A" ]; then alerte "bloc Etat a la reprise : $nb lignes, seuil d'alerte $SEUIL_A"
  elif [ "$nb" -gt 0 ];  then ok "bloc Etat a la reprise : $nb lignes"; fi
  nc="$(grep -c '^- \[x\]' TODOS.md || true)"
  [ "${nc:-0}" -gt 0 ] && alerte "TODOS.md garde $nc tache(s) cochee(s). Une tache faite se supprime, le fait vit au CHANGELOG"
  ns="$(grep -ciE '^## .*(session|séance|seance)' TODOS.md || true)"
  [ "${ns:-0}" -gt 0 ] && alerte "TODOS.md porte $ns section(s) de compte-rendu de session. C'est du CHANGELOG, TODOS ne garde que le futur"
fi

# CHANGELOG et tout autre journal : nombre d'entrees, longueur, entree la plus longue
journal() { # <fichier> <libelle>
  local f="$1" lib="$2" ne n em ja jb ea eb
  [ -f "$f" ] || return 0
  ne="$(nb_entrees_datees "$f")"; n="$(lignes "$f")"
  # `seuils: <journal>=N` fixe l'alerte en lignes, le nombre d'entrees suit dans le meme rapport.
  seuils_de "$f" 1000 1500
  ja="$SEUIL_A"; jb="$SEUIL_B"
  ea=$(( 40 * ja / 1000 )); eb=$(( 60 * jb / 1500 ))
  ajourne_de "$f"
  if [ -n "$AJ_N" ]; then
    : # un journal ajourne est juge par le cliquet, a la fin de la section 10
  elif [ "${ne:-0}" -ge "$eb" ] || [ "$n" -gt "$jb" ]; then
    blocage "$lib : $ne entrees, $n lignes. Seuil de blocage $eb entrees ou $jb lignes. Faire tourner : ctx-rotation.sh --fichier $f"
  elif [ "${ne:-0}" -ge "$ea" ] || [ "$n" -gt "$ja" ]; then
    alerte "$lib : $ne entrees, $n lignes. Seuil d'alerte $ea entrees ou $ja lignes. Faire tourner : ctx-rotation.sh --fichier $f"
  else
    ok "$lib : $ne entrees, $n lignes"
  fi
  # Le plafond de 25 lignes par entree vaut A L'ECRITURE. Un journal est
  # append-only, on ne reecrit pas le passe, donc une vieille entree trop longue
  # est une information et pas une alerte. Seules les trois plus recentes sont
  # encore les nôtres a corriger.
  em="$(entrees_du_journal "$f" | sed -n '1,3p' | sort -rn | sed -n '1p')"
  if [ -n "$em" ] && [ "${em%% *}" -gt 40 ]; then
    alerte "$lib : entree recente de ${em%% *} lignes (${em#* }). Une entree tient en 25 lignes, le detail va dans une fiche"
  else
    ev="$(entree_max "$f")"
    # if et pas une chaine [ ] && : la fonction doit rendre 0, sinon set -e tue l'audit
    # sur le cas le plus sain, un journal sans entree ancienne de plus de 40 lignes.
    if [ -n "$ev" ] && [ "${ev%% *}" -gt 40 ]; then
      info "$lib : la plus longue entree du journal fait ${ev%% *} lignes, mais elle est ancienne. Un journal ne se reecrit pas, le plafond de 25 lignes vaut a l'ecriture"
    fi
  fi
  return 0
}
journal CHANGELOG.md "CHANGELOG.md"

# Les tailles des markdown, mesurees d'un coup : un wc et un grep pour tous les fichiers au
# lieu de plusieurs sous-processus par fichier. Une ligne par fichier, `lignes<TAB>entrees
# datees<TAB>chemin`. Les mesures fines (profondeur de titres) ne se lancent ensuite que sur
# les fichiers qui depassent un seuil bas.
tailles_md() { # <liste de chemins, un par ligne, sur l'entree standard>
  local liste wc_out gr_out
  liste="$(cat)"
  [ -n "$liste" ] || return 0
  # Une variable ne garde pas les octets nuls : la liste reste en lignes, xargs -0 les recoit
  # par un tr a chaque usage. Le ./ devant chaque chemin evite qu'un nom comme `a=b.md` soit lu
  # comme une option, et que `total` se confonde avec la ligne de total de wc.
  wc_out="$(printf '%s\n' "$liste" | sed 's|^|./|' | tr '\n' '\000' | xargs -0 wc -l 2>/dev/null || true)"
  gr_out="$(printf '%s\n' "$liste" | sed 's|^|./|' | tr '\n' '\000' | xargs -0 grep -cHE "$MOTIF_DATE_TITRE" 2>/dev/null || true)"
  { printf '%s\n' "$wc_out"; printf '@@GREP\n'; printf '%s\n' "$gr_out"; } | awk -v T="$TAB" '
    /^@@GREP$/ { gr = 1; next }
    !gr {
      sub(/^[ \t]+/, ""); i = index($0, " ")
      if (i == 0) next
      p = substr($0, i + 1)
      if (p == "total") next
      sub(/^\.\//, "", p); n[p] = substr($0, 1, i - 1); ordre[++k] = p
      next
    }
    {
      i = length($0)
      while (i > 0 && substr($0, i, 1) != ":") i--
      if (i == 0) next
      p = substr($0, 1, i - 1); sub(/^\.\//, "", p); e[p] = substr($0, i + 1)
    }
    END { for (j = 1; j <= k; j++) { p = ordre[j]; print n[p] T (p in e ? e[p] : 0) T p } }'
  return 0
}
TAB_MD="$(docs_md | tailles_md)"
JOURNAUX=""
# Les fichiers a dix entrees datees ou plus : le filtre se fait en awk, une boucle shell sur
# plusieurs milliers de lignes coute plus qu'elle ne rapporte.
while IFS="$TAB" read -r n ne f; do
  [ -n "$f" ] || continue
  case "$f" in CHANGELOG.md|TODOS.md|CODEMAP.md|CLAUDE.md) continue ;; esac
  JOURNAUX="$JOURNAUX$NL$f"
  journal "$f" "journal $f"
done <<FIN
$(printf '%s\n' "$TAB_MD" | awk -F "$TAB" '$2 + 0 >= 10')
FIN

# fiches docs/ trop longues. Un journal a deja ete mesure comme journal, sa
# reponse est la rotation et pas la scission.
if [ -n "$DOCS_DIR" ] && [ -d "$DOCS_DIR" ]; then
  while IFS="$TAB" read -r n ne f; do
    [ -n "$f" ] || continue
    case "$JOURNAUX" in *"$NL$f"*) continue ;; esac
    ajourne_de "$f"
    if [ -n "$AJ_N" ]; then continue; fi
    seuils_de "$f" 250 300
    if   [ "$n" -gt "$SEUIL_B" ]; then blocage "$f : $n lignes, seuil de blocage $SEUIL_B. Scinder en deux sujets"
    elif [ "$n" -gt "$SEUIL_A" ]; then alerte "$f : $n lignes, seuil d'alerte $SEUIL_A"; fi
  done <<FIN
$(find "$DOCS_DIR" -name '*.md' -not -name 'README.md' 2>/dev/null | sort | tailles_md)
FIN
fi

# Profondeur de titres. Un fichier a cinq niveaux ou plus porte plusieurs sujets,
# c'est la seule regle de decoupe chiffree qu'un guide de style publie. Signale
# seulement au-dela de la cible, sinon c'est du bruit : on ne lit que les fichiers de plus
# de 150 lignes.
GROS="$(printf '%s\n' "$TAB_MD" | awk -F "$TAB" '$1 + 0 > 150 { print $3 }')"
while IFS="$TAB" read -r d f; do
  [ -n "$f" ] || continue
  n="$(lignes "$f")"
  info "$f : $d niveaux de titres sur $n lignes. Au-dela de quatre, ce sont souvent plusieurs sujets a scinder"
done <<FIN
$(printf '%s\n' "$GROS" | profondeurs_titres)
FIN

# zones existantes
for z in $ZONES; do
  mesure "$z/CODEMAP.md" "carte de zone $z" 200 250 25000 "$z/CODEMAP.md" 20000
  [ -f "$z/CLAUDE.md" ] && mesure "$z/CLAUDE.md" "CLAUDE.md de zone $z" 40 60
done
for c in $(trouver . -name CLAUDE.md -path './*/*' -not -path './.claude/*' | sort); do
  d="${c%/CLAUDE.md}"; d="${d#./}"
  [ -f "$d/CODEMAP.md" ] || mesure "$c" "CLAUDE.md de zone $d" 40 60
done

# Longueur de LIGNE dans les fichiers d'etat. Un budget compte en lignes ne voit pas une
# cellule de tableau qui a avale une preuve entiere. Au-dela du seuil (800 par defaut,
# `seuils: ligne=N`), une alerte par fichier. Les blocs de code ``` ne comptent pas.
seuils_de ligne 800 0
SEUIL_LIGNE="$SEUIL_A"
lignes_longues() { # <fichier> : « nombre numero longueur » des lignes hors bloc de code au-dela du seuil
  # La longueur se compte en caracteres : avec mawk, length compte des octets, et une ligne de
  # 508 caracteres accentues passait pour une ligne de plus de 800. En C, tr retire les octets
  # de continuation UTF-8 (0x80 a 0xBF), il ne reste qu'un octet par caractere. Le filtre se
  # fait avant awk et non dans awk : un awk qui lit l'UTF-8 lui-meme lirait l'intervalle comme
  # des points de code. Les sauts de ligne restent, la numerotation est intacte.
  LC_ALL=C tr -d '\200-\277' < "$1" | LC_ALL=C awk -v s="$SEUIL_LIGNE" '
    /^[ \t]*```/ { f = !f; next }
    !f && length($0) > s { n++; if (length($0) > m) { m = length($0); l = NR } }
    END { if (n > 0) print n, l, m }'
  return 0
}
LL_VUS=" "
for f in TODOS.md CODEMAP.md CLAUDE.md CHANGELOG.md \
  $(for z in $ZONES; do printf '%s\n' "$z/CODEMAP.md" "$z/CLAUDE.md"; done) \
  $(trouver . -name CLAUDE.md -path './*/*' -not -path './.claude/*' | sed 's|^\./||' | sort); do
  [ -f "$f" ] || continue
  case "$LL_VUS" in *" $f "*) continue ;; esac
  LL_VUS="$LL_VUS$f "
  ll="$(lignes_longues "$f")"
  [ -n "$ll" ] || continue
  read -r ll_n ll_num ll_max <<<"$ll"
  alerte "$f : $ll_n ligne(s) de plus de $SEUIL_LIGNE caracteres, la plus longue est la ligne $ll_num ($ll_max caracteres). Sortir la preuve vers une fiche docs/ ou archives/, la ligne garde le fait, sa date et un pointeur" "$f"
done

# zones candidates : un repertoire de code de 25 fichiers ou plus, sans carte.
# Simple information tant que le CODEMAP de la racine tient son budget ou que le
# projet est petit, alerte des qu'il deborde sur un projet moyen ou grand, parce
# que c'est la sortie naturelle de ce qui deborde.
CM_LIGNES=0; [ -f CODEMAP.md ] && CM_LIGNES="$(lignes CODEMAP.md)"
BASES=""
for d in src lib app packages apps internal cmd services; do [ -d "$d" ] && BASES="$BASES $d"; done
[ -n "$BASES" ] || BASES="."
candidats=0
for base in $BASES; do
  # En elagage : un dossier que la liste elague (Library/ d'un Unity, dist/, un CACHEDIR.TAG)
  # n'est pas un candidat, `-not -path X/*` ne retire que son contenu et pas lui.
  for m in $(find "$base" -mindepth 1 -maxdepth 1 "${PRUNE[@]}" -o -type d -print 2>/dev/null | sort); do
    nom="${m#./}"
    case "$(basename "$nom")" in .*|docs|"${DOCS_DIR##*/}"|archives|tests|test|scripts|node_modules|__pycache__) continue ;; esac
    [ -f "$nom/CODEMAP.md" ] && continue
    nf="$(trouver "$nom" -type f | wc -l | tr -d ' ')"
    [ "$nf" -ge 25 ] || continue
    mentions="$(grep -c "$(basename "$nom")" CODEMAP.md 2>/dev/null || true)"
    candidats=$((candidats + 1))
    if [ "$TAILLE" != petite ] && { [ "$CM_LIGNES" -gt 300 ] || [ "$TAILLE" = grande ]; }; then
      alerte "zone candidate : $nom, $nf fichiers, cite ${mentions:-0} fois dans le CODEMAP. Lui donner sa carte : ctx-init.sh --zone $nom"
    else
      info "zone possible : $nom, $nf fichiers, cite ${mentions:-0} fois dans le CODEMAP"
    fi
  done
done
[ "$candidats" -eq 0 ] && [ -n "$ZONES" ] && ok "chaque repertoire de code assez gros porte sa carte"

# Regles `.claude/rules/*.md`. Une regle sans `paths:` se charge a chaque session, au meme
# titre que le CLAUDE.md racine : son poids compte. Une regle en `globs:` ne se charge
# jamais par chemin, seul `paths:` est lu, elle tombe donc dans le cas precedent.
fm_cle() { # <fichier> <cle> : code 0 si l'en-tete YAML du fichier porte la cle
  awk -v k="$2" 'NR == 1 { if ($0 !~ /^---[ \t\r]*$/) exit; dedans = 1; next }
       dedans && /^---[ \t\r]*$/ { exit }
       dedans && index($0, k ":") == 1 { t = 1; exit }
       END { exit t ? 0 : 1 }' "$1" 2>/dev/null
}
REGLES_LIGNES=0
REGLES_CARS=0
REGLES_NB=0
REGLES_LISTE=""
if [ -d .claude/rules ]; then
  for r in $(find .claude/rules -type f -name '*.md' 2>/dev/null | LC_ALL=C sort); do
    if fm_cle "$r" globs; then
      alerte "$r : declare globs:, que Claude Code ne lit pas. Seul paths: la charge quand un fichier concerne est touche. Telle quelle elle se charge a chaque session" "$r"
    fi
    if ! fm_cle "$r" paths; then
      n="$(lignes "$r")"
      REGLES_LIGNES=$((REGLES_LIGNES + n))
      REGLES_CARS=$((REGLES_CARS + $(caracteres "$r")))
      REGLES_NB=$((REGLES_NB + 1))
      REGLES_LISTE="${REGLES_LISTE:+$REGLES_LISTE, }${r#.claude/rules/} ($n)"
    fi
  done
fi
if [ "$REGLES_NB" -gt 0 ]; then
  seuils_de regles-sans-paths 150 200
  if   [ "$REGLES_LIGNES" -gt "$SEUIL_B" ]; then
    blocage "regles sans paths : $REGLES_LIGNES lignes chargees d'office a chaque session, seuil de blocage $SEUIL_B ($REGLES_LISTE). Leur donner un paths:" .claude/rules
  elif [ "$REGLES_LIGNES" -gt "$SEUIL_A" ]; then
    alerte "regles sans paths : $REGLES_LIGNES lignes chargees d'office a chaque session, seuil d'alerte $SEUIL_A ($REGLES_LISTE). Leur donner un paths:" .claude/rules
  else
    info "$REGLES_NB regle(s) sans paths, $REGLES_LIGNES lignes chargees d'office a chaque session : $REGLES_LISTE"
  fi
fi

# Imports `@fichier` d'un fichier : ce qu'il charge en plus de lui-meme. Les blocs de code
# et les spans de code n'importent rien. Chemins relatifs au fichier qui importe.
imports_de() { # <fichier> -> chemins existants depuis la racine, un par ligne
  local f="$1" dir t
  dir="$(dirname "$f")"
  for t in $(md_sans_code "$f" | grep -oE '(^|[[:space:]])@[A-Za-z0-9_./-]+' | sed 's/^[[:space:]]*@//' || true); do
    t="${t%[.,]}"
    case "$t" in */*|*.*) ;; *) continue ;; esac
    case "$t" in /*|~*) continue ;; esac
    normaliser "$dir/$t"
    if [ -f "$NORM" ]; then printf '%s\n' "$NORM"; fi
  done
  return 0
}
# Tous les imports atteints depuis un fichier, quatre sauts au plus, sans doublon.
imports_atteints() { # <fichier>
  local front="$1" tous="$1" suivants f c i=0
  while [ "$i" -lt 4 ] && [ -n "$front" ]; do
    suivants=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      for c in $(imports_de "$f"); do
        if grep -qxF "$c" <<<"$tous"; then continue; fi
        tous="$tous
$c"
        suivants="${suivants:+$suivants
}$c"
      done
    done <<FIN
$front
FIN
    front="$suivants"
    i=$((i + 1))
  done
  printf '%s\n' "$tous" | sed 1d
  return 0
}

# Cout total de reprise : tout ce qu'une session charge avant la premiere question.
# CLAUDE.md, ses imports, les regles sans paths, le bloc de reprise, la carte racine et
# les trois dernieres entrees du journal.
c_claude=0; c_imports=0; c_reprise=0; c_carte=0; c_journal=0
# Le meme cout en caracteres : k_* est a c_* ce que les caracteres sont aux lignes.
k_claude=0; k_imports=0; k_reprise=0; k_carte=0; k_journal=0
if [ -f CLAUDE.md ]; then
  c_claude="$(lignes CLAUDE.md)"; k_claude="$(caracteres CLAUDE.md)"
  for f in $(imports_atteints CLAUDE.md); do
    c_imports=$((c_imports + $(lignes "$f")))
    k_imports=$((k_imports + $(caracteres "$f")))
  done
elif [ -f AGENTS.md ]; then
  c_claude="$(lignes AGENTS.md)"; k_claude="$(caracteres AGENTS.md)"
  for f in $(imports_atteints AGENTS.md); do
    c_imports=$((c_imports + $(lignes "$f")))
    k_imports=$((k_imports + $(caracteres "$f")))
  done
fi
if [ -f TODOS.md ]; then
  c_reprise="$(bloc_reprise_lignes TODOS.md)"
  if [ "$c_reprise" -gt 0 ]; then
    k_reprise="$(awk -v re="$RE_BLOC" '/^## /{ if (dans) exit; if (tolower($0) ~ re) dans=1 } dans' TODOS.md 2>/dev/null | caracteres_stdin)"
  fi
fi
if [ -f CODEMAP.md ]; then c_carte="$(lignes CODEMAP.md)"; k_carte="$(caracteres CODEMAP.md)"; fi
if [ -f CHANGELOG.md ]; then
  for n in $(entrees_du_journal CHANGELOG.md | sed -n '1,3p' | awk '{print $1}'); do
    c_journal=$((c_journal + n))
  done
  # Les trois premieres entrees du fichier, de la premiere ligne datee sur c_journal lignes.
  if [ "$c_journal" -gt 0 ]; then
    motif_du_journal CHANGELOG.md
    jdeb="$(grep -nE "$JMOTIF" CHANGELOG.md 2>/dev/null | sed -n '1p' | cut -d: -f1 || true)"
    if [ -n "$jdeb" ]; then
      k_journal="$(sed -n "${jdeb},$((jdeb + c_journal - 1))p" CHANGELOG.md | caracteres_stdin)"
    fi
  fi
fi
c_total=$((c_claude + c_imports + REGLES_LIGNES + c_reprise + c_carte + c_journal))
k_total=$((k_claude + k_imports + REGLES_CARS + k_reprise + k_carte + k_journal))
c_detail="CLAUDE.md $c_claude, imports $c_imports, regles sans paths $REGLES_LIGNES, bloc de reprise $c_reprise, carte racine $c_carte, trois dernieres entrees du journal $c_journal"
seuils_de cout-reprise 600 900
if   [ "$c_total" -gt "$SEUIL_B" ]; then
  blocage "cout de reprise : $c_total lignes chargees avant la premiere question, seuil de blocage $SEUIL_B ($c_detail)" CLAUDE.md
elif [ "$c_total" -gt "$SEUIL_A" ]; then
  alerte "cout de reprise : $c_total lignes chargees avant la premiere question, seuil d'alerte $SEUIL_A ($c_detail)" CLAUDE.md
else
  ok "cout de reprise : $c_total lignes ($c_detail)"
fi
# Meme somme en caracteres : cent par ligne de budget, donc 60 000 et 90 000. Une carte de
# 191 lignes qui pese 126 000 caracteres passe le budget en lignes sans passer celui-ci. Les
# tokens (caracteres / 4, arrondi) ne sont qu'un ordre de grandeur, dans le message seulement.
k_detail="CLAUDE.md $k_claude, imports $k_imports, regles sans paths $REGLES_CARS, bloc de reprise $k_reprise, carte racine $k_carte, trois dernieres entrees du journal $k_journal"
k_tokens=$(((k_total + 2) / 4))
seuils_de car-cout-reprise 60000 90000
if   [ "$k_total" -gt "$SEUIL_B" ]; then
  blocage "cout de reprise : $k_total caracteres (environ $k_tokens tokens) charges avant la premiere question, seuil de blocage $SEUIL_B ($k_detail)" CLAUDE.md
elif [ "$k_total" -gt "$SEUIL_A" ]; then
  alerte "cout de reprise : $k_total caracteres (environ $k_tokens tokens) charges avant la premiere question, seuil d'alerte $SEUIL_A ($k_detail)" CLAUDE.md
fi

# Cliquet `ajourne:`. Le fichier ne doit plus grossir au-dela de sa valeur gelee, et
# l'entree doit sortir des qu'il repasse sous son seuil d'alerte.
if [ -n "$AJOURNE" ]; then
  while IFS= read -r e; do
    trim "$e"; e="${TRIM#./}"
    [ -n "$e" ] || continue
    ajf=""; ajn=""; ajd=""
    case "$e" in
      *=*@*)
        trim "${e%%=*}"; ajf="$TRIM"
        trim "${e#*=}"; reste="$TRIM"
        trim "${reste%%@*}"; ajn="$TRIM"
        trim "${reste#*@}"; ajd="$TRIM" ;;
    esac
    case "$ajn" in ''|*[!0-9]*) ajn="" ;; esac
    if [ -z "$ajf" ] || [ -z "$ajn" ] || [ -z "$ajd" ]; then
      alerte "ajourne : l'entree « $e » est illisible, la forme est fichier=lignes@AAAA-MM-JJ" "$(conv_trouver)"
      continue
    fi
    if [ ! -f "$ajf" ]; then
      alerte "ajourne : $ajf n'existe pas, retirer l'entree $ajf=$ajn@$ajd" "$ajf"
      continue
    fi
    # Un CLAUDE.md reduit a un renvoi ne porte rien : l'ajournement vise les regles, donc le
    # fichier cible, comme la mesure de plus haut.
    ajm="$ajf"; ajnote=""
    if [ "$ajf" = CLAUDE.md ] && [ -n "$CLAUDE_RENVOI" ] && [ -f "$CLAUDE_RENVOI" ]; then
      ajm="$CLAUDE_RENVOI"; ajnote=" Fichier mesure : $CLAUDE_RENVOI, qui porte les regles de CLAUDE.md."
    fi
    n="$(lignes "$ajm")"
    defauts_de "$ajf"
    seuils_de "$ajf" "$DA" "$DB"
    if [ "$n" -gt "$ajn" ]; then
      blocage "$ajf : $n lignes, plus que son ajournement ($ajn lignes depuis le $ajd). Un depassement gele ne grossit plus. Couper au moins jusqu'a $ajn lignes.$ajnote" "$ajf"
    elif [ "$DA" -gt 0 ] && [ "$n" -le "$SEUIL_A" ]; then
      alerte "$ajf : $n lignes, repasse sous son seuil d'alerte ($SEUIL_A). Retirer l'entree ajourne $ajf=$ajn@$ajd.$ajnote" "$ajf"
    else
      jours_depuis "$ajd"; jr="$JOURS"
      info "$ajf : $n lignes, ajourne a $ajn depuis le $ajd${jr:+ ($jr jours)}. Il ne doit plus grossir.$ajnote" "$ajf"
    fi
  done <<FIN
$(printf '%s\n' "$AJOURNE" | tr ',' '\n')
FIN
fi

if [ "$BUDGET_SEUL" -eq 0 ]; then

# --- 11. structure et hygiene du contexte -------------------------------------
# Ce que la section 10 ne mesure pas en lignes : les plans finis, les resumes qui
# derivent, la memoire automatique, les sous-modules, les pieges, les agents.
echo
echo "11. Structure et hygiene"
SEC=11

# Valeur d'une cle de l'en-tete YAML d'un fichier, sans guillemets. Vide si absente.
fm_valeur() { # <fichier> <cle>
  awk -v k="$2" 'NR == 1 { if ($0 !~ /^---[ \t\r]*$/) exit; dedans = 1; next }
       dedans && /^---[ \t\r]*$/ { exit }
       dedans && index($0, k ":") == 1 {
         v = substr($0, length(k) + 2)
         gsub(/"/, "", v); gsub(/\047/, "", v)
         sub(/^[ \t]+/, "", v); sub(/[ \t\r]+$/, "", v)
         print v; exit
       }' "$1" 2>/dev/null
  return 0
}

# Plans executes. La regle d'un plan « termine » est celle de ctx-rotation.sh --plans, on
# l'appelle en simulation au lieu de la recopier. Un plan fini qui garde des cases ouvertes
# ou depasse 300 lignes n'a pas ete compresse.
if [ -n "$PLANS_DIR" ] && [ -d "$PLANS_DIR" ] && [ -f "$DIR_SCRIPTS/ctx-rotation.sh" ]; then
  if [ -n "$ROT_SORTIE" ]; then
    wait "$ROT_PID" 2>/dev/null || true
    ROT_PID=""
    sortie_plans="$(cat "$ROT_SORTIE")"
  else
    sortie_plans="$(bash "$DIR_SCRIPTS/ctx-rotation.sh" --plans --dry-run --root "$ROOT" 2>/dev/null || true)"
  fi
  nbp=0; mauvais=0
  while IFS= read -r l; do
    case "$l" in "  - "*) ;; *) continue ;; esac
    p="${l#  - }"; p="${p%% *}"
    [ -f "$p" ] || continue
    nbp=$((nbp + 1))
    n="$(lignes "$p")"
    o="$(grep -c '\[ \]' "$p" || true)"
    if [ "${o:-0}" -gt 0 ] || [ "$n" -gt 300 ]; then
      mauvais=$((mauvais + 1))
      alerte "$p : plan execute qui reste lourd ($n lignes, ${o:-0} case(s) [ ] ouverte(s), plafond 300 lignes). A compresser puis archiver : ctx-rotation.sh --plans" "$p"
    fi
  done <<FIN
$sortie_plans
FIN
  if [ "$mauvais" -eq 0 ]; then
    ok "aucun plan execute a compresser"
  fi
fi

# Resumes recalculables. La section « Archive recemment » de docs/README.md resume l'index
# des archives, qui est la source. Une ligne du resume absente de la source est fausse.
if [ -n "$DOCS_DIR" ] && [ -f "$DOCS_DIR/README.md" ] && [ -n "$ARCH_DIR" ] && [ -f "$ARCH_DIR/README.md" ]; then
  RESUME="$(awk '/^#+ / { dans = ($0 ~ /[Aa]rchiv/); next } dans' "$DOCS_DIR/README.md")"
  nres=0; faux=0
  while IFS= read -r l; do
    d="$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' <<<"$l" | sed -n '1p' || true)"
    [ -n "$d" ] || continue
    toks="$(printf '%s' "$l" | grep -oE '`[^`]+`' | tr -d '`' || true)"
    [ -n "$toks" ] || continue
    nres=$((nres + 1))
    trouve=0
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      if [ -n "$(grep -F -- "$d" "$ARCH_DIR/README.md" | grep -F -- "$t" || true)" ]; then trouve=1; fi
    done <<FIN
$toks
FIN
    if [ "$trouve" -eq 0 ]; then
      faux=$((faux + 1))
      alerte "$DOCS_DIR/README.md : la ligne archivee du $d ($(head -1 <<<"$toks")) ne se retrouve pas dans $ARCH_DIR/README.md. Le resume se recalcule depuis l'index des archives" "$DOCS_DIR/README.md"
    fi
  done <<FIN
$RESUME
FIN
  # La plus recente archive qui n'est pas une rotation de journal doit figurer au resume.
  recente="$(awk -F'|' '/^\|---/ { t = 1; next }
      t && NF >= 6 {
        d = $2; o = $3; r = $6
        gsub(/^[ \t]+|[ \t]+$/, "", d); gsub(/^[ \t]+|[ \t]+$/, "", o); gsub(/^[ \t]+|[ \t]+$/, "", r)
        if (d !~ /^[0-9][0-9][0-9][0-9]-/) next
        if (o == r) next
        print d "|" o; exit
      }' "$ARCH_DIR/README.md")"
  if [ -n "$recente" ] && [ "$nres" -gt 0 ]; then
    rd="${recente%%|*}"; ro="${recente#*|}"
    ro="$(grep -oE '`[^`]+`' <<<"$ro" | sed -n '1p' | tr -d '`' || true)"
    if [ -n "$ro" ] && ! grep -qF -- "$ro" <<<"$RESUME" && ! grep -qF -- "$(basename "$ro")" <<<"$RESUME"; then
      info "$DOCS_DIR/README.md : le resume « archive recemment » n'a pas la derniere archive, du $rd ($ro). Le recalculer depuis $ARCH_DIR/README.md" "$DOCS_DIR/README.md"
    fi
  fi
  if [ "$nres" -gt 0 ] && [ "$faux" -eq 0 ]; then
    ok "le resume des archives de $DOCS_DIR/README.md se retrouve dans $ARCH_DIR/README.md"
  fi
fi

# Memoire automatique du projet. Claude Code range l'index sous
# ~/.claude/projects/<chemin du projet, tout caractere non alphanumerique en tiret>/memory/MEMORY.md
# et ne charge que ses 200 premieres lignes. Absente, il n'y a rien a dire.
memoire_auto_index() { # -> chemin du MEMORY.md de ce projet, rien s'il n'existe pas
  local base c
  base="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/projects"
  for c in "$(printf '%s' "$ROOT" | sed 's/[^A-Za-z0-9]/-/g')" "$(printf '%s' "$ROOT" | sed 's|/|-|g')"; do
    if [ -f "$base/$c/memory/MEMORY.md" ]; then printf '%s\n' "$base/$c/memory/MEMORY.md"; return 0; fi
  done
  return 0
}
# Texte en minuscules ASCII, tout le reste en espaces simples : deux phrases qui ne
# different que par la ponctuation ou la casse deviennent identiques.
norm_txt() {
  LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed 's/[^a-z0-9]/ /g' | LC_ALL=C tr -s ' '
}
MEM="$(memoire_auto_index)"
if [ -n "$MEM" ]; then
  nm="$(lignes "$MEM")"
  seuils_de memoire-auto 150 200
  if [ "$nm" -gt "$SEUIL_A" ]; then
    alerte "index de la memoire automatique : $nm lignes, seuil d'alerte $SEUIL_A ($MEM). Claude Code ne charge que les 200 premieres lignes, le reste est invisible. Fusionner ou drainer les entrees dont le contenu a un proprietaire dans le depot" "$MEM"
  else
    ok "index de la memoire automatique : $nm lignes"
  fi
  # Entrees qui recopient CLAUDE.md : une regle de projet vit dans CLAUDE.md, la memoire
  # garde ce qui n'a pas d'autre proprietaire. Egalite apres normalisation, 50 caracteres au moins.
  if [ -f CLAUDE.md ]; then
    BLOB="$( { cat CLAUDE.md; if [ -n "$CLAUDE_RENVOI" ] && [ -f "$CLAUDE_RENVOI" ]; then cat "$CLAUDE_RENVOI"; fi; } | norm_txt | tr '\n' ' ' | tr -s ' ')"
    memdir="$(dirname "$MEM")"
    nrec=0
    for ef in $(grep -oE '\]\([^)#:]+\.md\)' "$MEM" | sed 's/^](//; s/)$//' | sort -u || true); do
      [ -f "$memdir/$ef" ] || continue
      copie=""
      # Un seul awk par entree : il saute l'en-tete, normalise chaque ligne comme norm_txt
      # (minuscules ASCII, tout le reste en espace, espaces serres, bords retires) et ne rend
      # que les segments de 50 caracteres au moins. En C, comme norm_txt : un octet reste un
      # octet, et tout octet hors a-z0-9 tombe dans l'espace.
      while IFS= read -r seg; do
        case "$BLOB" in *"$seg"*) copie="$seg"; break ;; esac
      done <<FIN
$(LC_ALL=C awk 'NR == 1 && /^---/ { fm = 1; next } fm && /^---/ { fm = 0; next }
     !fm { if (++n > 200) next
           s = tolower($0); gsub(/[^a-z0-9]/, " ", s); gsub(/  +/, " ", s)
           sub(/^ /, "", s); sub(/ $/, "", s)
           if (length(s) >= 50) print s }' "$memdir/$ef")
FIN
      if [ -n "$copie" ]; then
        nrec=$((nrec + 1))
        alerte "memoire automatique : l'entree $ef recopie CLAUDE.md (« $(printf '%s' "$copie" | cut -c1-60) »). Une regle de projet vit dans CLAUDE.md, pas en double dans la memoire" "$MEM"
      fi
    done
    if [ "$nrec" -eq 0 ]; then ok "aucune entree de la memoire automatique ne recopie CLAUDE.md"; fi
  fi
fi

# Parent et sous-modules. Un enfant qui a son propre kit n'est pas decrit comme sans kit
# par la carte du parent, et le pointeur du parent ne retarde pas sur l'etat de l'enfant.
# Le chemin d'un sous-module apparait-il dans la ligne comme un mot ? Un sous-module `ops` ou
# `lib` ne doit pas se retrouver dans « workshops » ou « lib.rs » ni dans « docs/ops ». Avant :
# debut de ligne, ou un caractere qui n'est ni lettre, ni chiffre, ni _ . / -. Apres : fin de
# ligne, ou un caractere qui n'est ni lettre, ni chiffre, ni _ -, un point final restant permis.
# Les backticks, les espaces, la ponctuation et le / d'un dossier bornent donc le chemin.
mot_dans_ligne() { # <chemin> <ligne> : code 0 si le chemin y figure comme un mot
  local p="$1" rest="$2" pre="" avant apres cb ca c2
  while :; do
    case "$rest" in *"$p"*) ;; *) return 1 ;; esac
    avant="${rest%%"$p"*}"; apres="${rest#*"$p"}"
    pre="$pre$avant"
    cb="${pre: -1}"; ca="${apres:0:1}"; c2="${apres:1:1}"
    case "$cb" in
      ''|[![:alnum:]_./-]) 
        case "$ca" in
          ''|[![:alnum:]_.-]) return 0 ;;
          .) case "$c2" in ''|[![:alnum:]_]) return 0 ;; esac ;;
        esac ;;
    esac
    pre="$pre$p"; rest="$apres"
  done
}

RE_SANS_KIT="(sans|pas de|aucun|aucune|n'a pas|ne porte pas|ne possede pas|ni )[^|.]{0,40}(kit|pilier|CODEMAP|TODOS|CHANGELOG)|no (own )?kit|without (its|a) own"
while IFS= read -r p; do
  [ -n "$p" ] || continue
  [ -e "$p/.git" ] || continue
  if [ -f "$p/CODEMAP.md" ] && [ -f "$p/TODOS.md" ] && [ -f "$p/CHANGELOG.md" ]; then
    contre=""
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      txt="${l#*:}"; txt="${txt#*:}"
      mot_dans_ligne "$p" "$txt" || continue
      if grep -qiE "$RE_SANS_KIT" <<<"$txt"; then contre="$l"; break; fi
    done <<FIN2
$(grep -nF -- "$p" CODEMAP.md CLAUDE.md 2>/dev/null || true)
FIN2
    if [ -n "$contre" ]; then
      alerte "$p porte son propre kit (CODEMAP, TODOS, CHANGELOG), mais ${contre%%:*} ligne $(printf '%s' "$contre" | cut -d: -f2) dit le contraire. Corriger la carte du parent" "${contre%%:*}"
    fi
  fi
  sha="$(git ls-tree HEAD -- "$p" 2>/dev/null | awk '$2 == "commit" && !vu { print $3; vu = 1 }')"
  if [ -n "$sha" ] && git -C "$p" cat-file -e "$sha^{commit}" 2>/dev/null; then
    dptr="$(git -C "$p" show -s --format=%ci "$sha" 2>/dev/null | cut -c1-10)"
    dstat="$(git -C "$p" log -1 --format=%ci -- TODOS.md 2>/dev/null | cut -c1-10)"
    if [ -n "$dptr" ] && [ -n "$dstat" ] && [[ "$dstat" > "$dptr" ]]; then
      info "$p : le pointeur du parent date du $dptr, le dernier changement de statut de l'enfant (TODOS.md) du $dstat. Avancer le pointeur : git add $p" "$p"
    fi
  fi
done <<FIN
$SOUS_MODULES
FIN

# Pieges marques. Un piege a un proprietaire : la fiche du module, la carte de sa zone, la
# carte racine quand il n'y a pas de zone, ou docs/pieges/ pour ceux qui n'ont pas de module.
# Un piege laisse dans TODOS.md sera perdu avec le bloc de reprise.
P_FICHE=0; P_ZONE=0; P_RACINE=0; P_PIEGES=0; P_CLAUDE=0; P_TODOS=0; P_AUTRE=0; P_AUTRES=""
MARQUES="$(find . "${PRUNE[@]}" -o -name '*.md' -exec grep -cHF '🪤' {} + 2>/dev/null | grep -v ':0$' || true)"
while IFS= read -r l; do
  [ -n "$l" ] || continue
  f="${l%:*}"; f="${f#./}"; c="${l##*:}"
  case "$f" in
    CHANGELOG.md) ;;
    "$PLANS_DIR"/*) ;;
    TODOS.md) P_TODOS=$((P_TODOS + c)) ;;
    CLAUDE.md) P_CLAUDE=$((P_CLAUDE + c)) ;;
    CODEMAP.md) P_RACINE=$((P_RACINE + c)) ;;
    */CODEMAP.md) P_ZONE=$((P_ZONE + c)) ;;
    "$DOCS_DIR"/pieges/*) P_PIEGES=$((P_PIEGES + c)) ;;
    "$DOCS_DIR"/modules/*|"$DOCS_DIR"/features/*) P_FICHE=$((P_FICHE + c)) ;;
    *) P_AUTRE=$((P_AUTRE + c)); P_AUTRES="${P_AUTRES:+$P_AUTRES, }$f" ;;
  esac
done <<FIN
$MARQUES
FIN
P_TOTAL=$((P_FICHE + P_ZONE + P_RACINE + P_PIEGES + P_CLAUDE + P_TODOS + P_AUTRE))
if [ "$P_TOTAL" -gt 0 ]; then
  info "$P_TOTAL piege(s) marque(s) 🪤 : $P_FICHE en fiche de module, $P_ZONE en carte de zone, $P_RACINE en carte racine, $P_PIEGES dans $DOCS_DIR/pieges/, $P_CLAUDE dans CLAUDE.md, $P_TODOS dans TODOS.md, $P_AUTRE ailleurs"
  if [ "$P_TODOS" -gt 0 ]; then
    alerte "TODOS.md porte $P_TODOS piege(s) 🪤 sans proprietaire. Un piege va dans la fiche du module, la carte de sa zone, ou $DOCS_DIR/pieges/ s'il n'a pas de module" TODOS.md
  fi
  if [ "$P_AUTRE" -gt 0 ]; then
    info "piege(s) 🪤 hors proprietaire reconnu : $P_AUTRES"
  fi
fi
if [ -n "$DOCS_DIR" ] && [ -d "$DOCS_DIR/pieges" ]; then
  info "$DOCS_DIR/pieges/ : proprietaire des pieges qui n'ont pas de module ($P_PIEGES piege(s) marque(s))"
fi

# Agents du projet. Un `model:` en identifiant fige ne suit pas la derniere version de sa
# famille, un agent sans `model:` herite du modele de la session principale, souvent Opus.
if [ -d .claude/agents ]; then
  nag=0; bad=0
  for a in $(find .claude/agents -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort); do
    if [ -n "$EXCEPTIONS" ] && exception_de agent "$a"; then continue; fi
    nag=$((nag + 1))
    m="$(fm_valeur "$a" model)"
    if [ -z "$m" ]; then
      bad=$((bad + 1))
      alerte "$a : pas de model:, l'agent herite du modele de la session principale, souvent Opus. Poser un alias : haiku, sonnet ou opus" "$a"
    elif grep -qiE 'claude-.*[0-9]|anthropic\.claude' <<<"$m"; then
      bad=$((bad + 1))
      case "$m" in
        *[Hh]aiku*) al=haiku ;;
        *[Ss]onnet*) al=sonnet ;;
        *[Oo]pus*) al=opus ;;
        *) al="haiku, sonnet ou opus" ;;
      esac
      alerte "$a : model: $m est un identifiant fige, il ne suit pas la derniere version de sa famille. Poser l'alias : $al" "$a"
    fi
  done
  if [ "$nag" -gt 0 ] && [ "$bad" -eq 0 ]; then ok "$nag agent(s) du projet avec un model: en alias"; fi
fi

fi # fin de la section 11, sautee par --budget

# --- bilan --------------------------------------------------------------------
echo
echo "=============================================="
if [ "$ALERTES" -eq 0 ]; then
  echo " Aucune alerte. La doc et le depot sont d'accord, et tout tient dans son budget."
else
  echo " $ALERTES alerte(s), dont $BLOCAGES blocage(s). Chacune se termine par une correction,"
  echo " un deplacement vers archives/, ou une rotation. Un blocage ne se reporte pas."
fi
echo "=============================================="

if [ "$JSON" -eq 1 ]; then
  if [ -z "$JSON_BRUT" ]; then
    printf '[]\n' >&3
  else
    { printf '[\n'; json_sortie "$JSON_BRUT"; printf ']\n'; } >&3
  fi
fi

if [ "$STRICT" -eq 1 ] && [ "$ALERTES" -gt 0 ]; then exit 1; fi
exit 0
