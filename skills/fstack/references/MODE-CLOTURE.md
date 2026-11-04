# MODE-CLOTURE : rendre le dépôt complet, exact et lisible

> **Le contrat** : à la fin, une session neuve sans cette conversation reprend au bon endroit,
> sans payer un contexte qu'elle n'utilisera pas. Le but n'est pas de résumer la session.

Question à te reposer à chaque phase : un lecteur à froid, avec le bloc de reprise, le `CODEMAP.md`,
`CLAUDE.md` et les fiches de sa zone, comprend-il l'état réel, sait-il quoi faire, et combien ça
lui coûte à lire ?

Style : charge `style-redaction` avant d'écrire. S'il manque, la prose suit la langue déclarée par
`langue:` dans le bloc `contexte:convention`, ton direct, aucune tournure qui sent le texte généré.

Sans le kit, fais `references/MODE-INIT.md` puis reviens ici, sans demander. Pour un simple
dégraissage, les phases 0, 1, 5 et 8 suffisent.

## Phase 0. Cadrer et mesurer

```bash
git status -s && git diff --stat && git log --oneline -10
bash "$SKILL/scripts/ctx-audit.sh" --budget
```

1. **Périmètre.** Ce qui a changé, y compris hors git : fichiers non trackés, ressources externes
   créées (service, base, DNS, clé), effets de bord système.
2. **Niveaux.** Une session démarrée dans un sous-répertoire touche souvent au-dessus, et peut
   avoir traversé plusieurs projets. Un dossier qui porte les trois piliers est un niveau
   autonome, il se clôture séparément et le parent pointe vers lui. Un dossier qui ne porte qu'un
   `CODEMAP.md` est une zone, elle se met à jour ici. La section 1b de l'audit les liste.
3. **Budget.** La section 10 dit ce qui déborde, la phase 5 le traite. Un blocage ne se reporte pas.
4. **Proportion.** Petite session : CHANGELOG court, TODOS, et toujours les phases 4 et 5. Session
   conséquente : toutes les phases. Annonce le plan en une ligne, puis exécute.

**Observable** : la liste des niveaux touchés est écrite, et la sortie de `--budget` est lue.

## Lire un contrôle sans perdre son code

Vaut pour chaque contrôle des phases qui suivent. Le code se lit sur la commande elle-même, jamais
derrière un tube : `ctx-verite.sh --strict | tail -3` rend le code de `tail`, donc 0 sur un rouge.

```bash
bash "$SKILL/scripts/ctx-verite.sh" --strict > <scratchpad>/verite.txt 2>&1; echo "code $?"
```

Puis lis le fichier. Un contrôle qui n'a rien regardé (code 2, aucun fichier trouvé, dépendance
absente) n'est pas un vert, il se rejoue sur le bon périmètre ou se nomme au compte rendu.

## Phase 1. Auditer le réel, sans croire la doc

```bash
bash "$SKILL/scripts/ctx-audit.sh"                       # le niveau courant
bash "$SKILL/scripts/ctx-audit.sh" --root packages/api   # un niveau imbriqué
```

Une passe par niveau touché, sans `--root` le script prend la racine de git. Vérifie sur le terrain ce que la session a touché (service, ressource, test, chemin
cité). Note chaque écart sous la forme « la doc dit X, la réalité est Y ». Chaque écart a une issue
et une seule : corrigé en phase 2 ou 3, ou archivé en phase 4.

**Observable** : la liste des écarts est faite, aucun n'est sans issue.

## Phase 2. Synchroniser les trois piliers

| Pilier | Ce que tu y fais |
|---|---|
| `CHANGELOG.md` | En haut, `## AAAA-MM-JJ, titre` : quoi, pourquoi, rollback. 25 lignes au plus, le gros lot pointe vers `docs/`. |
| `CODEMAP.md` | Reflète la structure : module ajouté, retiré ou renommé, point d'entrée, dépendance, commande. Retire ce qui n'existe plus. Un piège va dans la carte de sa zone ou la fiche de son module. Date et cartes de zone à jour. |
| `TODOS.md` | Coche le fait puis supprime-le, supprime l'obsolète, ajoute les tâches découvertes. Un travail différé porte son échéance, `- [ ] (échéance AAAA-MM-JJ) description`, que le hook de démarrage remonte. Puis réécris le bloc « État à la reprise » depuis l'état courant, jamais en éditant le précédent. |

Le bloc tient en 40 lignes, quatre champs plus une ligne `Vérifier le terrain` : la commande qui
confirme que le dépôt est dans l'état décrit, copiable telle quelle (tests, `git status -s`, ce que
le projet a de plus rapide). Avant de retirer quoi que ce soit du bloc, classe : un événement est
déjà au CHANGELOG, un piège va dans la carte de sa zone ou la fiche de son module, une tâche dans la
liste avec son ancrage, une décision en ADR. Le récit ne se garde pas.

Chaque fait du bloc dit d'où il vient, pour que la reprise sache quoi revérifier : `(vu : <commande>)`
quand une commande l'a montré cette session, `(lu : <fichier>)` quand il est recopié, `(supposé)`
sinon. Un fait qui commande la prochaine étape ne reste pas `(supposé)` : il se mesure maintenant ou
devient la première tâche de la reprise.

**Échéances passées.** Chaque tâche du périmètre touché dont l'échéance est passée se tranche ici :
faite, reportée avec une date neuve et sa raison, ou archivée parce que les faits l'ont dépassée.
Aucune ne reste en rappel. Un rappel qui revient à chaque démarrage sans être tranché ne se lit plus.

Les faits durables vont chez leur propriétaire, jamais dans un pilier. La question : qui est
propriétaire de cette phrase ? Si tu ne sais pas, elle n'a probablement pas à être écrite.
Spécification complète dans `references/CONVENTION.md`.

### Drainage de la mémoire automatique

Si le projet a une mémoire automatique (index `MEMORY.md` hors dépôt de l'outil), chaque entrée se
traite avant la fin : promue vers son propriétaire (ADR, fiche, `CLAUDE.md`, CODEMAP) ou supprimée.
Aucune ne reste en place par défaut. Le geste et les cas limites sont dans
`references/MEMOIRE-AUTO.md`. Un `MEMORY.md` à la racine d'un projet qui l'utilise comme pilier ne
se dissout jamais ici, voir `references/MODE-MIGRER.md`.

**Observable** : `awk '/^## /{n++} n<=1' TODOS.md | wc -l` rend 40 ou moins, et l'index de mémoire
automatique ne garde aucune entrée non traitée.

## Phase 3. Documenter les modules dans `docs/`

Pour chaque module touché sérieusement : la fiche existe, corrige-la et passe son en-tête à
`à jour, vérifié le AAAA-MM-JJ`. Elle n'existe pas et le sujet la mérite, crée-la depuis
`templates/docs/`. Le sujet a disparu, direction `archives/` en phase 4. Elle dépasse 250 lignes,
scinde-la ou sors son récit. Le critère « mérite une fiche » (plusieurs fichiers coopèrent, une API
consommée ailleurs, un invariant peu évident, une procédure rejouable, une décision structurante)
est dans `references/DOCS-SYSTEM.md`. Mets `docs/README.md` à jour dans le même geste.

**Observable** : chaque fiche touchée porte la date du jour, et figure dans l'index.

## Phase 4. Purger l'obsolète vers `archives/`

Jamais sautée. Passe en revue fiches, procédures, scripts, plans et propositions abandonnées. Arbre
de décision et en-tête dans `references/ARCHIVAGE.md`.

```bash
bash "$SKILL/scripts/ctx-archive.sh" --verifier <chemin>
bash "$SKILL/scripts/ctx-archive.sh" <chemin> --raison "..." --remplace-par "..."
```

Le critère porte sur les références entrantes : un lien vivant est opératif, il bloque. Un plan
exécuté garde sa place sous forme de résumé, `ctx-rotation.sh --plans` s'en charge (il appelle `ctx-archive.sh --resume`).
Une section fausse dans un fichier encore utile se corrige sur place et
le correctif va au CHANGELOG. Une règle durable devenue fausse dans `CLAUDE.md` se supprime, et
laisse une ligne au CHANGELOG si sa disparition compte. Un pilier ne s'archive pas, le script le
refuse.

### Passe mécanique et passe contradicteur

**Mécanique.** Confie la vérification des affirmations au profil `fstack:controleur` (sans
sous-agents, lance-la toi-même) :

```bash
bash "$SKILL/scripts/ctx-verite.sh"            # chemins, scripts, options, commandes, comptages
bash "$SKILL/scripts/ctx-verite.sh" --info     # ajoute les affirmations à relire
bash "$SKILL/scripts/ctx-verite.sh" --strict   # code 1 s'il reste une affirmation fausse
```

Le contrôleur rend la sortie brute, sans la commenter. Chaque ligne a une issue : corrigée, ou
couverte par `exceptions: verite=<motif>` dans le bloc avec sa raison.

**Contradicteur.** Pour les seules fiches dont la portée a bougé (l'audit dit lesquelles), lance
`fstack:relecteur` en contexte neuf : il reçoit les fiches et le diff, rien de la
conversation, et liste les phrases fausses ou périmées avec la preuve. Sans sous-agents, relis la
fiche à froid contre le diff, après avoir fermé ce que tu en sais. **L'orchestrateur tranche** :
une phrase listée n'est fausse qu'une fois que tu l'as vérifiée toi-même. Le profil le plus bas qui
tient le critère, voir `references/DELEGATION.md`.

**Observable** : `ctx-verite.sh --strict` rend 0. Aucune affirmation connue-fausse ne subsiste dans
les piliers, `CLAUDE.md` ni `docs/`, et aucune suppression silencieuse.

## Phase 5. Tenir le budget

```bash
bash "$SKILL/scripts/ctx-audit.sh" --budget
```

Chaque `[!]` se traite maintenant, ou reçoit une tâche datée dans TODOS une seule fois : une alerte
qui revient à la clôture suivante est un blocage. Chaque `[!!]` se traite maintenant. Seuils et
pourquoi dans `references/BUDGET.md`.

| Ce qui déborde | Le geste |
|---|---|
| bloc de reprise | réécrire depuis l'état courant, classer ce qui sort |
| TODOS.md | supprimer les cases cochées, sortir les récits de session au CHANGELOG, dégraisser les tâches sans ancrage |
| journal à entrées datées | `ctx-rotation.sh` (ci-dessous), puis raccourcir les entrées de plus de 25 lignes |
| CODEMAP.md racine | créer les zones avec `ctx-init.sh --zone`, y descendre leurs pièges et commandes, pointer depuis la table « Zones » |
| CLAUDE.md | voir « Auto-amélioration de `CLAUDE.md` » plus bas |
| une fiche `docs/` | scinder en deux sujets, ou sortir le récit vers `archives/` |
| une carte de zone | scinder la zone en deux |

### Rotation des journaux et cycle de vie des plans

```bash
bash "$SKILL/scripts/ctx-rotation.sh" --dry-run                       # CHANGELOG.md, annonce sans écrire
bash "$SKILL/scripts/ctx-rotation.sh" --fichier <journal> --garder 30 --plafond 1500
bash "$SKILL/scripts/ctx-rotation.sh" --plans --dry-run               # plans exécutés
bash "$SKILL/scripts/ctx-rotation.sh" --plans
```

Toujours `--dry-run` d'abord, lis ce qu'il annonce. La rotation range du froid, elle n'archive pas
du faux. Un journal du plus ancien au plus récent est refusé (code 3), remets-le dans l'ordre. Un
plan exécuté de plus de 20 lignes devient un résumé de 20 lignes, son texte intégral part en
archive. Le script reconnaît l'exécuté à la marque `Statut : termine` ou à une ligne de `TODOS.md`
qui le cite, sans case ouverte.

### Auto-amélioration de `CLAUDE.md`

Borné par son budget, jamais en plus. Une règle apprise cette session et vraie à chaque instant
s'ajoute, et en échange une ligne sort. Chaque ligne passe le test « la retirer ferait-il faire
une erreur ? ». L'état va dans TODOS, le récit dans la fiche, la règle de zone dans
`<zone>/CLAUDE.md` ou `.claude/rules/<zone>.md`. Au-delà du budget, `references/MODE-AUDIT.md`.

Sur une grande codebase, le dégraissage se découpe par zone entre profils (`references/DELEGATION.md`).
Tu gardes le bloc de reprise et toute décision d'archivage.

**Observable** : `bash "$SKILL/scripts/ctx-audit.sh" --budget` ne rend aucun `[!!]`, chaque `[!]` a
son geste ou sa tâche.

## Phase 6. Test « prêt pour un contexte neuf »

Bloquant, checklist complète dans `references/HANDOFF.md`. Les points qui échouent le plus :
chaque niveau touché a sa passe, les piliers ne se contredisent pas (relis TODOS et CODEMAP côte à
côte), tout travail en cours a sa tâche écrite, aucun secret dans un fichier tracké, `CLAUDE.md` ne
porte ni état ni récit.

## Phase 7. Retour d'expérience, commit, témoin

1. **Retour d'expérience.** Une ligne chiffrée dans l'entrée du jour du CHANGELOG, par exemple
   `Séance : 3 fiches corrigées, 2 archivées, 4 alertes d'audit avant, 1 après, 2 relectures
   contradicteur, 1 phrase fausse trouvée.` Des nombres mesurés, pas une impression.
2. **Commit.** Jamais sans demande explicite, tu proposes et tu attends. Sur demande : une branche
   de travail, un message qui dit le quoi et le pourquoi. Tu ajoutes par chemins explicites,
   jamais `git add -A` : une autre session dans le même dossier partage l'index git, et un commit
   peut porter le titre de l'une et les fichiers de l'autre. Juste après, `git log -1 --stat`, et
   la liste doit être celle de la clôture. Sur demande de push, il n'a atterri que si
   `git rev-parse HEAD` et `git rev-parse @{u}` rendent la même valeur.
3. **Témoin.** Après le commit s'il a lieu, pour que le témoin porte le bon `commit`. Lance la
   commande de la rubrique « Témoin de clôture et prompt de relance » du `SKILL.md`. Elle y est écrite en entier parce
   que `CLAUDE_PLUGIN_DATA` n'est substituée que dans le corps d'un skill, d'une commande ou d'un
   agent, pas dans ce fichier, et n'existe pas dans l'outil Bash. Hors Claude Code elle est vide et
   le script sort sans témoin.
4. **Contrôle final.** Tout ce que la clôture a touché est dans le commit :

   ```bash
   git status --porcelain
   ```

   La sortie est vide, ou ne liste que ce que tu as décidé de laisser et que tu peux nommer.
   Un fichier de la clôture encore listé est un oubli. Le témoin vit hors du dépôt, il n'y figure pas.
5. **Défaire.** Une clôture ratée se défait par `git revert <commit>`, jamais par une édition à la
   main. C'est pourquoi la clôture tient dans un seul commit et que le CHANGELOG porte son rollback.
6. **Passation.** Sauf si la note de clôture contient `sans-relance`, rédige le prompt de
   redémarrage (format dans `references/MODE-RELANCE.md`, rubrique « Le prompt de redémarrage ») et
   range-le pour la session suivante par la commande de la rubrique « Témoin de clôture et prompt de relance » du
   `SKILL.md`. Le hook l'annoncera au prochain démarrage avec sa fraîcheur, et
   `/fstack:relance open` le jouera. Hors Claude Code, rien n'est rangé et le prompt reste
   dans le compte rendu. Ce prompt remplace la reprise précédente, jamais le prompt d'un plan.
   Avant de le rédiger, liste la file (`--lister-relance`, même rubrique) : si la prochaine
   étape est un plan qui attend, le démarrage du prompt renvoie vers son entrée. Un plan que
   la session a exécuté sans passer par la file garde son entrée en attente : solde-la
   (`--solder <entrée>`, même rubrique) pour qu'elle ne se rejoue pas, et dis-le dans le compte
   rendu.

## Phase 8. Compte rendu

Texte simple, jamais d'artifact : ce qui a été fait en 1 à 3 lignes, puis une ligne chacun pour les
piliers, `docs/` (fiches ajoutées, corrigées, ADR), `archives/` (éléments et raison), la vérité
(corrections de `ctx-verite.sh`, phrases fausses du contradicteur), la mémoire automatique
(promues, supprimées), le budget (tailles avant et après), `CLAUDE.md`, les niveaux mis à jour, et
le reste à faire avec un pointeur vers `TODOS.md`, et le prompt de relance (rangé, ou pourquoi
non). Chaque contrôle cité porte son code nu. Il se termine par « Prêt pour un contexte neuf »
seulement si la phase 6 passe.
