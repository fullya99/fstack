#!/usr/bin/env bash
#
# ctx-demarrage.sh : hook SessionStart du plugin fstack, temoin de cloture et prompt de relance.
#
# Usage :
#   bash ctx-demarrage.sh                    au demarrage : imprime quinze lignes au plus
#   bash ctx-demarrage.sh --ecrire-temoin    a la fin d'une cloture : ecrit le temoin
#   bash ctx-demarrage.sh --ecrire-relance   lit un prompt de relance sur stdin et le range
#   bash ctx-demarrage.sh --lire-relance     imprime le prochain prompt de la file, avec sa fraicheur, et le marque joue
#   bash ctx-demarrage.sh --lister-relance   montre la file sans rien jouer
#   bash ctx-demarrage.sh --solder <entree>  marque une entree jouee sans l'imprimer
#   --plan <chemin>      avec --ecrire-relance : le prompt d'execution de ce plan, range a cote de la reprise
#   --apres <entree>     avec --plan : ce plan se joue apres celui-la
#   --nom <entree>       avec --lire-relance : joue cette entree plutot que la prochaine
#   --racine <chemin>    projet a lire, sinon $CLAUDE_PROJECT_DIR, sinon le repertoire courant
#   --donnees <dossier>  dossier de donnees du plugin, sinon $CLAUDE_PLUGIN_DATA
#
# Il ne bloque jamais une session : code 0 dans tous les cas, lecture seule sur le projet.
# Ce que Claude Code fait de la sortie : le texte de stdout d'un hook SessionStart entre dans
# le contexte de Claude, qui le voit et peut le relayer. Rien n'est ecrit sur stderr.
#
# Silencieux quand tout va bien : une ligne par defaut coute du contexte a chaque demarrage,
# reprise et compactage. Seul le temoin de cloture parle toujours, c'est l'info de continuite.
# Sans bloc de convention : silence si aucun des trois piliers n'existe, une ligne qui propose
# /fstack:migrer s'il en existe au moins un.
#
# Silencieux ne veut pas dire muet en cas de panne : un hook qui ne peut pas tourner le dit en
# une ligne, sinon une panne et un projet sain rendent la meme sortie vide.
#
# Le hook lit sur stdin le JSON de l'evenement, pour son champ `source` (startup, resume, clear,
# compact, fork). Apres un compactage, le corps d'un skill invoque revient tronque a ses 5 000
# premiers tokens et un fichier lu n'est plus qu'un resume (code.claude.com/docs/en/skills, section
# Skill content lifecycle, lue le 2026-11-02) : le hook rappelle de relire le fichier du mode.
#
# Le temoin : <donnees>/temoins/<nom stable>, lignes `cle=valeur` (commit, arbre, sale, date).
# Les prompts de relance : une file dans <donnees>/relance/<nom stable>/, decrite au-dessus de
# dossier_relance(). Une entree lue par --lire-relance devient <entree>.joue.md et le hook ne
# l'annonce plus.
# Le nom stable est le nom du dossier du projet, assaini, plus une somme de son chemin absolu :
# ni `/` ni espace, et deux clones du meme nom ne se melangent pas.
# Les variables CLAUDE_PLUGIN_* n'existent pas dans l'outil Bash : le mode cloture passe
# --donnees avec la valeur que le skill a recue par substitution.
set -f
# Jamais de bruit sur stderr, meme si un outil manque dans le PATH.
exec 2>/dev/null

case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
DIR="$(cd "$DIR" && pwd)"
SORTIE=""
SOURCE=""
# Echeances : une tache ouverte dont l'echeance tombe dans ce nombre de jours, ou est passee.
ECHEANCE_HORIZON=3

ligne() { # <texte> : ajoute une ligne a la sortie
  SORTIE="${SORTIE}[fstack] $1
"
  return 0
}

# Nom stable du projet pour le temoin.
nom_projet() { # <racine>
  local base somme
  base="$(basename "$1" | tr -c 'A-Za-z0-9._-' '-')"
  somme="$(printf '%s' "$1" | cksum | cut -d' ' -f1)"
  printf '%s-%s\n' "$base" "$somme"
  return 0
}

# Empreinte de l'arbre de travail : sort differemment si un fichier a bouge depuis.
empreinte_arbre() { # <racine>
  git -C "$1" status --porcelain 2>/dev/null | cksum | cut -d' ' -f1
  return 0
}

nb_sales() { # <racine> : nombre de fichiers non commites
  git -C "$1" status --porcelain 2>/dev/null | wc -l | tr -d ' '
  return 0
}

# Ou en est un commit par rapport a HEAD : "meme", "N" commits ajoutes depuis, ou "absent".
ecart_commit() { # <racine> <sha>
  local racine="$1" sha="$2" head n
  head="$(git -C "$racine" rev-parse -q --verify HEAD 2>/dev/null || true)"
  [ -n "$head" ] || { printf 'absent\n'; return 0; }
  if [ "$head" = "$sha" ]; then
    printf 'meme\n'
  elif git -C "$racine" cat-file -e "$sha^{commit}" 2>/dev/null \
       && git -C "$racine" merge-base --is-ancestor "$sha" "$head" 2>/dev/null; then
    n="$(git -C "$racine" rev-list --count "$sha..$head" 2>/dev/null || true)"
    printf '%s\n' "${n:-plusieurs}"
  else
    printf 'absent\n'
  fi
  return 0
}

ecrire_temoin() { # <racine> <donnees>
  local racine="$1" donnees="$2" dest commit
  if [ -z "$donnees" ]; then
    ligne "Temoin de cloture non ecrit : CLAUDE_PLUGIN_DATA absent. Le mode cloture le passe avec --donnees."
    return 0
  fi
  commit="$(git -C "$racine" rev-parse -q --verify HEAD 2>/dev/null || true)"
  if [ -z "$commit" ]; then
    ligne "Temoin de cloture non ecrit : pas de commit dans ce depot."
    return 0
  fi
  dest="$donnees/temoins/$(nom_projet "$racine")"
  if mkdir -p "$donnees/temoins" 2>/dev/null \
     && printf 'commit=%s\narbre=%s\nsale=%s\ndate=%s\n' "$commit" "$(empreinte_arbre "$racine")" \
          "$(nb_sales "$racine")" "$(ctx_aujourdhui)" > "$dest" 2>/dev/null; then
    ligne "Temoin de cloture ecrit : commit $(printf '%s' "$commit" | cut -c1-7)."
  else
    ligne "Temoin de cloture non ecrit : $donnees/temoins n'est pas accessible en ecriture."
  fi
  return 0
}

# Rend 0 si un temoin a ete lu, 1 sinon (pour decider du repli heuristique).
lire_temoin() { # <racine> <donnees>
  local racine="$1" donnees="$2" f tc ta ts td c7 e
  [ -n "$donnees" ] || return 1
  f="$donnees/temoins/$(nom_projet "$racine")"
  [ -f "$f" ] || return 1
  tc="$(sed -n 's/^commit=//p' "$f" | sed -n '1p')"
  ta="$(sed -n 's/^arbre=//p' "$f" | sed -n '1p')"
  ts="$(sed -n 's/^sale=//p' "$f" | sed -n '1p')"
  td="$(sed -n 's/^date=//p' "$f" | sed -n '1p')"
  [ -n "$tc" ] || return 1
  c7="$(printf '%s' "$tc" | cut -c1-7)"
  e="$(ecart_commit "$racine" "$tc")"
  case "$e" in
    meme)
      if [ -n "$ta" ] && [ "$ta" != "$(empreinte_arbre "$racine")" ]; then
        ligne "Derniere cloture le $td au commit $c7, le meme commit, mais des fichiers ont change depuis."
      elif [ -n "$ts" ] && [ "$ts" -gt 0 ] 2>/dev/null; then
        ligne "La session repart de la derniere cloture (le $td, commit $c7), qui a laisse $ts fichier(s) non commite(s)."
      else
        ligne "La session repart bien de la derniere cloture (le $td, commit $c7)."
      fi
      ;;
    absent) ligne "Derniere cloture le $td au commit $c7, absent de cette branche (rebase ou autre branche)." ;;
    *)      ligne "Derniere cloture le $td au commit $c7, $e commit(s) ajoute(s) depuis." ;;
  esac
  return 0
}

# Repli sans temoin : beaucoup de fichiers non commites et aucune entree recente au journal.
cloture_oubliee() { # <racine>
  local racine="$1" n dj d
  n="$(nb_sales "$racine")"
  [ "${n:-0}" -ge 5 ] 2>/dev/null || return 0
  [ -f "$racine/CHANGELOG.md" ] || return 0
  # La date la plus recente parmi les titres, quel que soit le format ou l'ordre du journal :
  # `## 2026-11-02`, `## [1.2.0] - 2026-11-02`, `[2026-11-02] [FIX]`, du plus ancien au plus recent.
  dj="$(grep -E '^(#|\[)' "$racine/CHANGELOG.md" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | sed -n '$p')"
  d="$(ctx_jours_depuis "$dj")"
  if [ -z "$d" ] || [ "$d" -gt 1 ]; then
    ligne "$n fichier(s) non commite(s) et aucune entree recente au CHANGELOG : une cloture a peut-etre ete oubliee."
  fi
  return 0
}

# Echeances de TODOS.md : `- [ ] (echeance AAAA-MM-JJ) texte`, passees ou proches.
# Un seul `date` par ligne et 200 lignes au plus : le hook a 10 secondes en tout, et un TODOS.md
# enorme est justement le cas qu'il doit pouvoir signaler.
echeances() { # <racine>
  local f="$1/TODOS.md" l e0 eb d txt n=0 total dues="" re c
  [ -f "$f" ] || return 0
  e0="$(ctx_epoch "$(ctx_aujourdhui)")"
  [ -n "$e0" ] || return 0
  re='(échéance|echeance) ([0-9]{4}-[0-9]{2}-[0-9]{2})'
  total="$(grep -cE '^[[:space:]]*- \[ \] .*(échéance|echeance) [0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" 2>/dev/null)"
  [ "${total:-0}" -gt 0 ] 2>/dev/null || return 0
  while IFS= read -r l; do
    [[ $l =~ $re ]] || continue
    eb="$(ctx_epoch "${BASH_REMATCH[2]}")"
    [ -n "$eb" ] || continue
    d="$(ctx_jours_entre "$e0" "$eb")"
    [ "$d" -ge $(( -ECHEANCE_HORIZON )) ] || continue
    n=$((n + 1))
    txt="${l#*- \[ \] }"
    txt="${txt:0:140}"
    if [ "$d" -gt 0 ]; then
      dues="${dues}${d}	  depassee de $d j : $txt
"
    elif [ "$d" -eq 0 ]; then
      dues="${dues}0	  aujourd'hui : $txt
"
    else
      dues="${dues}${d}	  dans $(( -d )) j : $txt
"
    fi
  done <<FIN
$(grep -E '^[[:space:]]*- \[ \] .*(échéance|echeance) [0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" 2>/dev/null | sed -n '1,200p')
FIN
  [ "$n" -gt 0 ] || return 0
  c=""
  [ "$total" -gt 200 ] && c=" (sur les 200 premieres lues, $total en tout)"
  ligne "$n echeance(s) passee(s) ou dans les $ECHEANCE_HORIZON jours dans TODOS.md$c. A trancher : faire, reporter avec une date neuve, ou archiver."
  # La plus en retard d'abord : la troncature a quatre lignes ne doit pas cacher un retard.
  while IFS= read -r c; do
    [ -n "$c" ] && ligne "${c#*	}"
  done <<FIN
$(printf '%s' "$dues" | sort -t '	' -k1,1nr | sed -n '1,4p')
FIN
  return 0
}

# --- la file de relance -------------------------------------------------------------------
# Un dossier par projet, <donnees>/relance/<nom stable>/, une entree par fichier :
#   reprise.md       le prompt de la cloture (ou de /fstack:relance prompt), un seul, reecrit
#   plan-<slug>.md   le prompt d'execution d'un plan, un par plan, range par le mode planifier
# Une entree jouee devient <entree>.joue.md. Premiere ligne de chaque entree :
#   <!-- relance commit=<sha> date=<AAAA-MM-JJ> ordre=<n> [plan=<chemin> empreinte=<cksum>] [apres=<entree>] -->
# Ordre de jeu : la reprise d'abord, elle decrit l'etat le plus frais et sait ce qui attend.
# Puis les plans dans l'ordre d'ecriture, un plan dont la dependance attend encore passe son tour.

dossier_relance() { # <racine> <donnees>
  printf '%s/relance/%s\n' "$2" "$(nom_projet "$1")"
  return 0
}

champ_tete() { # <fichier> <cle> : valeur d'un champ de la premiere ligne
  sed -n '1p' "$1" | sed -n "s/.* $2=\([^ ]*\).*/\1/p"
  return 0
}

empreinte_fichier() { # <fichier>
  cksum < "$1" | cut -d' ' -f1
  return 0
}

assainir() { # <texte> : rien d'autre que lettres, chiffres, point, tiret et souligne
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'
  return 0
}

# Le nom d'une entree depuis ce qu'on tape (--nom, --apres) : reprise, plan-x, x ou plans/x.md.
# Toujours assaini : il entre dans un nom de fichier et dans l'en-tete.
nom_entree() { # <saisie>
  local s="$1"
  case "$s" in
    */*|*.md) s="${s##*/}"; s="plan-${s%.md}" ;;
    reprise|plan-*) ;;
    *) s="plan-$s" ;;
  esac
  printf '%s\n' "$(assainir "$s")"
  return 0
}

# Le nom d'entree d'un plan range : plan-<nom du fichier>, jamais `reprise`. Si ce nom est deja
# pris par un autre plan (meme nom de fichier, autre dossier), le chemin entier le distingue.
nom_plan() { # <dossier de la file> <chemin relatif du plan>
  local n autre f
  n="plan-$(assainir "$(basename "$2" .md)")"
  for f in "$1/$n.md" "$1/$n.joue.md"; do
    [ -f "$f" ] || continue
    autre="$(champ_tete "$f" plan)"
    if [ -n "$autre" ] && [ "$autre" != "$2" ]; then
      n="plan-$(assainir "${2%.md}")"
      break
    fi
  done
  printf '%s\n' "$n"
  return 0
}

# L'ancien emplacement, un fichier unique <nom stable>.md a cote du dossier, devient sa reprise.
migrer_ancien() { # <racine> <donnees>
  local d
  d="$(dossier_relance "$1" "$2")"
  [ -f "$d.md" ] || [ -f "$d.joue.md" ] || return 0
  mkdir -p "$d" 2>/dev/null || return 0
  if [ -f "$d.md" ] && [ ! -f "$d/reprise.md" ]; then mv -f "$d.md" "$d/reprise.md" 2>/dev/null; fi
  if [ -f "$d.joue.md" ] && [ ! -f "$d/reprise.joue.md" ]; then mv -f "$d.joue.md" "$d/reprise.joue.md" 2>/dev/null; fi
  return 0
}

# Les entrees en attente, une par ligne, dans l'ordre de jeu (la reprise d'abord).
en_attente() { # <dossier>
  local f n o
  [ -d "$1" ] || return 0
  find "$1" -maxdepth 1 -type f -name '*.md' ! -name '*.joue.md' 2>/dev/null | while IFS= read -r f; do
    n="${f##*/}"
    n="${n%.md}"
    o="$(champ_tete "$f" ordre)"
    [ "$n" = reprise ] && o=0
    case "$o" in ''|*[!0-9]*) o=0 ;; esac
    printf '%s\t%s\n' "$o" "$n"
  done | sort -t "$(printf '\t')" -k1,1n -k2,2 | cut -f2
  return 0
}

# La dependance d'une entree, si elle attend encore. Vide sinon.
dependance_en_attente() { # <dossier> <entree>
  local a
  a="$(champ_tete "$1/$2.md" apres)"
  if [ -n "$a" ] && [ -f "$1/$a.md" ]; then printf '%s\n' "$a"; fi
  return 0
}

# La prochaine entree a jouer : la premiere dont la dependance n'attend plus, sinon la premiere.
prochaine_entree() { # <dossier>
  local liste n
  liste="$(en_attente "$1")"
  [ -n "$liste" ] || return 0
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    if [ -z "$(dependance_en_attente "$1" "$n")" ]; then
      printf '%s\n' "$n"
      return 0
    fi
  done <<FIN
$liste
FIN
  printf '%s\n' "$liste" | sed -n '1p'
  return 0
}

ecrire_relance() { # <racine> <donnees> <plan> <apres> : le prompt arrive sur stdin
  local racine="$1" donnees="$2" plan="$3" apres="$4" dossier nom dest commit contenu ordre tete n
  contenu="$(head -c 20001)"
  if [ "${#contenu}" -gt 20000 ]; then
    contenu="${contenu:0:20000}"
    ligne "Prompt de relance tronque a 20 000 caracteres : raccourcis-le, la fin est perdue."
  fi
  if [ -z "$donnees" ]; then
    ligne "Prompt de relance non range : CLAUDE_PLUGIN_DATA absent. Il reste dans le chat."
    return 0
  fi
  if [ -z "$(printf '%s' "$contenu" | tr -d '[:space:]')" ]; then
    ligne "Prompt de relance non range : rien recu sur stdin."
    return 0
  fi
  nom=reprise
  if [ -n "$plan" ]; then
    case "$plan" in "$racine"/*) plan="${plan#"$racine"/}" ;; esac
    plan="${plan#./}"
    case "$plan" in
      /*|*..*|*[!A-Za-z0-9._/-]*)
        ligne "Prompt de plan non range : le chemin $plan doit etre relatif au projet, sans espace ni '..'."
        return 0
        ;;
    esac
    if [ ! -f "$racine/$plan" ]; then
      ligne "Prompt de plan non range : $plan introuvable dans le projet. Ecris le plan avant son prompt."
      return 0
    fi
  fi
  migrer_ancien "$racine" "$donnees"
  dossier="$(dossier_relance "$racine" "$donnees")"
  [ -n "$plan" ] && nom="$(nom_plan "$dossier" "$plan")"
  dest="$dossier/$nom.md"
  if ! mkdir -p "$dossier" 2>/dev/null; then
    ligne "Prompt de relance non range : $dossier n'est pas accessible en ecriture."
    return 0
  fi
  # Un plan reecrit garde sa place dans la file, un nouveau prend la suivante.
  ordre=""
  [ -f "$dest" ] && ordre="$(champ_tete "$dest" ordre)"
  case "$ordre" in ''|*[!0-9]*)
    ordre="$(find "$dossier" -maxdepth 1 -type f -name '*.md' 2>/dev/null | while IFS= read -r f; do champ_tete "$f" ordre; done \
             | grep -E '^[0-9]+$' | sort -n | sed -n '$p')"
    ordre=$(( ${ordre:-0} + 1 ))
    ;;
  esac
  commit="$(git -C "$racine" rev-parse -q --verify HEAD 2>/dev/null || true)"
  tete="<!-- relance commit=${commit:-aucun} date=$(ctx_aujourdhui) ordre=$ordre"
  [ -n "$plan" ] && tete="$tete plan=$plan empreinte=$(empreinte_fichier "$racine/$plan")"
  [ -n "$plan" ] && [ -n "$apres" ] && tete="$tete apres=$(nom_entree "$apres")"
  tete="$tete -->"
  if printf '%s\n%s\n' "$tete" "$contenu" > "$dest" 2>/dev/null; then
    rm -f "$dossier/$nom.joue.md" 2>/dev/null
    if [ -n "$plan" ]; then
      n="$(en_attente "$dossier" | wc -l | tr -d ' ')"
      ligne "Prompt d'execution de $plan range dans la file de relance sous le nom $nom ($n en attente). Apres le redemarrage de contexte : /fstack:relance open."
    else
      ligne "Prompt de relance range pour la prochaine session : $dest"
    fi
  else
    ligne "Prompt de relance non range : $dossier n'est pas accessible en ecriture."
  fi
  return 0
}

# Fraicheur d'un prompt range, en une phrase.
fraicheur_relance() { # <racine> <fichier>
  local racine="$1" f="$2" tete pc pd pp pe e d c7 phrase
  tete="$(sed -n '1p' "$f")"
  # Sept caracteres hexadecimaux au moins : `commit=aucun` commence par un `a`.
  pc="$(sed -n 's/.*commit=\([0-9a-f]\{7,\}\).*/\1/p' <<<"$tete")"
  pd="$(sed -n 's/.*date=\([0-9-]*\).*/\1/p' <<<"$tete")"
  c7="$(printf '%s' "$pc" | cut -c1-7)"
  if [ -z "$pc" ]; then
    phrase="produit le ${pd:-?}, sans commit"
  else
    e="$(ecart_commit "$racine" "$pc")"
    case "$e" in
      meme)   phrase="produit le $pd au commit $c7, rien de commite depuis" ;;
      absent) phrase="produit le $pd au commit $c7, absent de cette branche" ;;
      *)      phrase="produit le $pd au commit $c7, $e commit(s) depuis" ;;
    esac
  fi
  d="$(ctx_jours_depuis "$pd")"
  if [ -n "$d" ] && [ "$d" -gt 14 ]; then
    phrase="$phrase, il y a $d jours, peut-etre perime"
  fi
  # Le plan n'est pas encore commite quand son prompt se range : le commit ne le couvre pas.
  pp="$(champ_tete "$f" plan)"
  pe="$(champ_tete "$f" empreinte)"
  if [ -n "$pp" ]; then
    if [ ! -f "$racine/$pp" ]; then
      phrase="$phrase, plan introuvable : $pp"
    elif [ -n "$pe" ] && [ "$pe" != "$(empreinte_fichier "$racine/$pp")" ]; then
      phrase="$phrase, $pp modifie depuis"
    fi
  fi
  printf '%s\n' "$phrase"
  return 0
}

annoncer_relance() { # <racine> <donnees>
  local dossier liste n nom dep i=0 prochain
  [ -n "$2" ] || return 0
  migrer_ancien "$1" "$2"
  dossier="$(dossier_relance "$1" "$2")"
  liste="$(en_attente "$dossier")"
  [ -n "$liste" ] || return 0
  n="$(printf '%s\n' "$liste" | wc -l | tr -d ' ')"
  if [ "$n" -eq 1 ]; then
    ligne "Un prompt de relance attend ($liste, $(fraicheur_relance "$1" "$dossier/$liste.md")). /fstack:relance open pour le reprendre."
    return 0
  fi
  prochain="$(prochaine_entree "$dossier")"
  ligne "$n prompts de relance attendent. /fstack:relance open joue $prochain, /fstack:relance open <nom> en choisit un :"
  while IFS= read -r nom; do
    [ -n "$nom" ] || continue
    i=$((i + 1))
    [ "$i" -le 4 ] || continue
    dep="$(dependance_en_attente "$dossier" "$nom")"
    ligne "  $nom : $(fraicheur_relance "$1" "$dossier/$nom.md")${dep:+, apres $dep}"
  done <<FIN
$liste
FIN
  [ "$n" -gt 4 ] && ligne "  et $((n - 4)) autre(s)"
  return 0
}

# Marque une entree jouee sans l'imprimer : un plan execute autrement que par la file.
solder_relance() { # <racine> <donnees> <entree>
  local racine="$1" donnees="$2" nom dossier
  [ -n "$donnees" ] || { ligne "Rien a solder : CLAUDE_PLUGIN_DATA absent."; return 0; }
  [ -n "$3" ] || { ligne "--solder attend le nom d'une entree."; return 0; }
  migrer_ancien "$racine" "$donnees"
  dossier="$(dossier_relance "$racine" "$donnees")"
  nom="$(nom_entree "$3")"
  if [ -f "$dossier/$nom.md" ] && mv -f "$dossier/$nom.md" "$dossier/$nom.joue.md" 2>/dev/null; then
    ligne "Entree $nom soldee : marquee jouee sans etre lue."
  else
    ligne "Aucune entree $nom en attente."
  fi
  return 0
}

# Imprime le prompt sur stdout, en clair, puis le marque joue.
lire_relance() { # <racine> <donnees> [entree]
  local racine="$1" donnees="$2" cible="$3" dossier nom f j dep reste dernier
  [ -n "$donnees" ] || { ligne "Aucun prompt de relance : CLAUDE_PLUGIN_DATA absent."; return 0; }
  migrer_ancien "$racine" "$donnees"
  dossier="$(dossier_relance "$racine" "$donnees")"
  if [ -n "$cible" ]; then
    nom="$(nom_entree "$cible")"
    if [ ! -f "$dossier/$nom.md" ]; then
      if [ -f "$dossier/$nom.joue.md" ]; then
        ligne "Le prompt $nom a deja ete joue ($(fraicheur_relance "$racine" "$dossier/$nom.joue.md")). Il est dans $dossier/$nom.joue.md."
      else
        ligne "Aucun prompt $nom en attente."
      fi
      reste="$(en_attente "$dossier" | tr '\n' ' ' | sed 's/ $//')"
      [ -n "$reste" ] && ligne "En attente : $reste."
      return 0
    fi
  else
    nom="$(prochaine_entree "$dossier")"
    if [ -z "$nom" ]; then
      dernier="$(find "$dossier" -maxdepth 1 -type f -name '*.joue.md' 2>/dev/null | while IFS= read -r f; do
                   printf '%s\t%s\n' "$(champ_tete "$f" ordre)" "$f"; done | sort -n | sed -n '$p' | cut -f2)"
      if [ -n "$dernier" ]; then
        ligne "Le dernier prompt de relance a deja ete joue ($(fraicheur_relance "$racine" "$dernier")). Il est dans $dernier."
      else
        ligne "Aucun prompt de relance range pour ce projet."
      fi
      return 0
    fi
  fi
  f="$dossier/$nom.md"
  j="$dossier/$nom.joue.md"
  dep="$(dependance_en_attente "$dossier" "$nom")"
  [ -n "$dep" ] && ligne "Attention : $nom passe normalement apres $dep, qui attend encore."
  ligne "Prompt de relance $nom $(fraicheur_relance "$racine" "$f")."
  reste="$(en_attente "$dossier" | grep -vxF "$nom" | tr '\n' ' ' | sed 's/ $//')"
  if [ -n "$reste" ]; then
    ligne "Restent en attente : $reste. Chaque plan se joue dans sa propre session neuve."
  fi
  SORTIE="${SORTIE}$(sed '1d' "$f")
"
  mv -f "$f" "$j" 2>/dev/null
  return 0
}

main() {
  local mode=lire racine="" donnees="${CLAUDE_PLUGIN_DATA:-}" base top v ligne_version entree
  local out rc nb na reprise d date_r msgs c l piliers=0 plan="" apres="" cible=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --ecrire-temoin)  mode=ecrire; shift ;;
      --ecrire-relance) mode=ecrire_relance; shift ;;
      --lire-relance)   mode=lire_relance; shift ;;
      --lister-relance) mode=lister_relance; shift ;;
      --solder)        mode=solder; cible="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      --plan)          plan="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      --apres)         apres="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      --nom)           cible="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      --racine)        racine="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      --donnees)       donnees="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      *) shift ;;
    esac
  done

  # Le JSON de l'evenement, seulement en mode hook et seulement s'il y a un tube.
  # read -t garde ce qu'il a lu, la ou `timeout head` perd son tampon quand stdin reste ouvert.
  # Le JSON tient d'ordinaire sur une ligne : on s'arrete des que `source` est passe.
  if [ "$mode" = lire ] && [ ! -t 0 ]; then
    entree=""
    c=0
    while [ "$c" -lt 50 ]; do
      l=""
      if IFS= read -r -t 1 l; then entree="$entree$l"; else entree="$entree$l"; break; fi
      c=$((c + 1))
      case "$l" in *'"source"'*) break ;; esac
    done
    SOURCE="$(grep -oE '"source"[[:space:]]*:[[:space:]]*"[a-z_]+"' <<<"$entree" | sed -n '1p' | sed -E 's/.*"([a-z_]+)"$/\1/')"
  fi
  # Les commandes qui suivent ne lisent jamais stdin, sauf le prompt de relance.
  [ "$mode" = ecrire_relance ] || exec </dev/null

  # Pas de depot git (ou pas de git) : ce n'est pas un projet, on ne dit rien.
  base="${racine:-${CLAUDE_PROJECT_DIR:-$PWD}}"
  [ -d "$base" ] || return 0
  top="$(git -C "$base" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -z "$top" ]; then
    # En hook, le silence. Un geste d'ecriture demande, lui, doit dire pourquoi rien n'est range.
    [ "$mode" = lire ] || ligne "Pas un depot git ($base) : rien ecrit ni lu."
    return 0
  fi
  racine="$(cd "$top" && pwd -P)" || return 0

  CTX_RACINE="$racine"
  export CTX_RACINE
  # shellcheck source=ctx-commun.sh
  if ! . "$DIR/ctx-commun.sh"; then
    ligne "Hook inoperant : ctx-commun.sh introuvable dans $DIR. Reinstalle le plugin."
    return 0
  fi

  case "$mode" in
    ecrire)         ecrire_temoin "$racine" "$donnees"; return 0 ;;
    ecrire_relance) ecrire_relance "$racine" "$donnees" "$plan" "$apres"; return 0 ;;
    lire_relance)   lire_relance "$racine" "$donnees" "$cible"; return 0 ;;
    solder)         solder_relance "$racine" "$donnees" "$cible"; return 0 ;;
    lister_relance)
      if [ -z "$donnees" ]; then
        ligne "Aucune file de relance : CLAUDE_PLUGIN_DATA absent."
      else
        annoncer_relance "$racine" "$donnees"
        [ -n "$SORTIE" ] || ligne "Aucun prompt de relance en attente."
      fi
      return 0
      ;;
  esac

  for c in CODEMAP.md TODOS.md CHANGELOG.md; do
    [ -f "$racine/$c" ] && piliers=$((piliers + 1))
  done

  v="$(conv_version)"
  if [ "$v" = 0 ]; then
    # Le plugin est installe pour tous les depots, forks compris : sans bloc et sans aucun
    # pilier, ce n'est pas un projet de la convention, silence complet. Avec au moins un
    # pilier, quelqu'un a commence, une ligne propose de poser le bloc.
    if [ "$piliers" -gt 0 ]; then
      ligne "Piliers de contexte presents mais pas de bloc de convention. /fstack:migrer pour le poser."
    fi
    return 0
  fi

  # Compactage : la premiere ligne, c'est celle qui evite de continuer un mode sans sa procedure.
  if [ "$SOURCE" = compact ]; then
    ligne "Compactage : seul le debut du SKILL.md revient, les fichiers de mode lus ne sont plus qu'un resume. Un mode fstack en cours se poursuit en relisant son references/MODE-*.md."
  fi

  # Version du bloc.
  case "$v" in
    ''|*[!0-9]*)
      ligne "Version du bloc contexte:convention illisible ($v). /fstack:migrer pour la remettre d'aplomb."
      ;;
    *)
      if [ "$v" -lt "$CTX_VERSION" ]; then
        ligne_version=""
        [ -n "$(conv_lire version)" ] || ligne_version=", sans ligne version:"
        ligne "Bloc de convention en version $v${ligne_version}, la courante est la $CTX_VERSION. /fstack:migrer"
      elif [ "$v" -gt "$CTX_VERSION" ]; then
        ligne "Bloc de convention en version $v, plus recent que les scripts du plugin (version $CTX_VERSION). Mets le plugin a jour."
      fi
      ;;
  esac

  # Le plugin s'appelait clawd-stack jusqu'a la 1.0.0-rc.3. Un fichier d'instructions qui cite
  # encore ses commandes ou son marqueur d'orchestration se remet a jour par migrer.
  for c in CLAUDE.md AGENTS.md; do
    if [ -f "$racine/$c" ] && grep -q "clawd-stack:" "$racine/$c" 2>/dev/null; then
      ligne "$c cite encore l'ancien nom clawd-stack. /fstack:migrer pour le renommer."
      break
    fi
  done

  # Continuite d'abord, elle ne doit pas etre coupee par la troncature a quinze lignes.
  # Apres un compactage, la session continue : ni temoin, ni relance, ni echeances.
  if [ "$SOURCE" != compact ]; then
    if ! lire_temoin "$racine" "$donnees"; then
      case "$SOURCE" in startup|'') cloture_oubliee "$racine" ;; esac
    fi
    case "$SOURCE" in startup|clear|'') annoncer_relance "$racine" "$donnees" ;; esac
  fi

  # Bloc de reprise de TODOS.md : la date de son titre.
  if [ -f "$racine/TODOS.md" ]; then
    reprise="$(grep -iE '^#+ .*(reprise|resume state)' "$racine/TODOS.md" 2>/dev/null | sed -n '1p' || true)"
    if [ -n "$reprise" ]; then
      date_r="$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' <<<"$reprise" | sed -n '1p' || true)"
      d="$(ctx_jours_depuis "$date_r")"
      if [ -n "$d" ] && [ "$d" -gt 14 ]; then
        ligne "Le bloc de reprise de TODOS.md date du $date_r, soit $d jours. Il est peut-etre perime."
      fi
    fi
  fi

  [ "$SOURCE" = compact ] || echeances "$racine"

  # Audit du budget, sauf si le bloc est plus recent que les scripts : il refuserait de tourner.
  if [ "$v" -le "$CTX_VERSION" ] 2>/dev/null; then
    rc=0
    if command -v timeout >/dev/null 2>&1; then
      out="$(timeout 7 bash "$DIR/ctx-audit.sh" --root "$racine" --budget --json 2>/dev/null)" || rc=$?
    else
      out="$(bash "$DIR/ctx-audit.sh" --root "$racine" --budget --json 2>/dev/null)" || rc=$?
    fi
    case "$out" in
      "["*)
        if [ "$rc" -eq 0 ]; then
          nb="$(printf '%s\n' "$out" | grep -o '"niveau":"blocage"' | wc -l | tr -d ' ')"
          na="$(printf '%s\n' "$out" | grep -o '"niveau":"alerte"' | wc -l | tr -d ' ')"
          if [ "${nb:-0}" -gt 0 ] || [ "${na:-0}" -gt 0 ]; then
            ligne "${nb:-0} blocage(s) et ${na:-0} alerte(s) sur le budget de contexte. /fstack:cloture pour les ranger."
            msgs="$(printf '%s\n' "$out" | grep '"niveau":"blocage"' | sed -e 's/.*"message":"//' -e 's/"}*,*$//' -e 's/\\"/"/g' | sed -n '1,3p' | cut -c1-200 || true)"
            if [ -n "$msgs" ]; then
              while IFS= read -r c; do
                [ -n "$c" ] && ligne "  blocage : $c"
              done <<FIN
$msgs
FIN
            fi
          fi
        elif [ "$rc" -eq 124 ]; then
          ligne "L'audit du budget a depasse 7 secondes et n'a rien rendu. /fstack:audit pour le lire en clair."
        else
          ligne "L'audit du budget a rendu le code $rc. /fstack:audit pour le lire en clair."
        fi
        ;;
      *)
        if [ "$rc" -eq 124 ]; then
          ligne "L'audit du budget a depasse 7 secondes et n'a rien rendu. /fstack:audit pour le lire en clair."
        else
          ligne "L'audit du budget n'a rien rendu (code $rc). /fstack:audit pour le lire en clair."
        fi
        ;;
    esac
  fi

  return 0
}

# main ne parle que par SORTIE. En mode hook, on l'imprime tronquee a quinze lignes. Le prompt de
# relance lu par --lire-relance sort en entier, c'est le livrable.
MODE_ARG=lire
for a in "$@"; do [ "$a" = --lire-relance ] && MODE_ARG=lire_relance; done
main "$@" >/dev/null 2>&1 || ligne "Hook en panne (code $?). Lance bash $DIR/ctx-demarrage.sh a la main pour voir."
if [ "$MODE_ARG" = lire_relance ]; then
  printf '%s' "$SORTIE"
else
  printf '%s' "$SORTIE" | sed -n '1,15p' | cut -c1-240
fi
exit 0
