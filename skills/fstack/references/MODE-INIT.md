# MODE-INIT : poser la convention sans rien écraser

> **Le contrat** : à la fin, le projet porte les trois piliers, un bloc `contexte:convention` en
> version 5 qui dit la vérité sur ses chemins, et trois lignes d'orchestration dans son
> `CLAUDE.md`. Rien d'existant n'a été écrasé ni dissous.

Le script détecte le terrain et l'annonce avant d'écrire. Le premier geste dépend de ce qu'il
trouve. Un gabarit vide ne sert à personne, le vrai travail est le remplissage depuis le code réel.

```bash
bash "$SKILL/scripts/ctx-init.sh" --dry-run   # montre ce qui serait créé, n'écrit rien
bash "$SKILL/scripts/ctx-init.sh"             # crée ce qui manque, n'écrase jamais l'existant
```

Options : `--root <chemin>`, `--profil <profil>` pour imposer le profil, `--with-claude` pour poser
aussi un `CLAUDE.md` de zone, `--zone <répertoire>` pour une carte de zone seule.

**Observable** : `--dry-run` liste les fichiers à créer et le profil détecté. Après le vrai
lancement, `bash "$SKILL/scripts/ctx-audit.sh"` ne rend aucun blocage.

## 1. Reconnaître le profil

Le détail de chaque profil (ce qu'on appelle module, ce qui se vérifie) est dans
`references/PROFILS-PROJETS.md`. Ici, seulement le geste d'entrée.

| Situation | Premier geste |
|---|---|
| Projet neuf | Le kit se pose, tu le remplis depuis le code qui existe. |
| Existant documenté autrement (`doc/`, `documentation/`, `adr/`) | Greffe. Le script adopte la doc et déclare ses vrais chemins dans le bloc, sans gabarit vide à côté. Chaque document reçoit un propriétaire, ce qui est faux part par `ctx-archive.sh`. Rien n'est dissous. |
| `AGENTS.md` sans `CLAUDE.md` | Le script écrit dans `AGENTS.md`. Si un `CLAUDE.md` naît ensuite, une ligne `@AGENTS.md` en tête le raccorde. |
| Convention concurrente (`memory-bank/`, `.clinerules`, `.cursor/rules`, `GEMINI.md`) | Une question à l'opérateur, qui fait foi. La perdante est archivée avec sa raison. |
| `MEMORY.md` d'une ancienne version | Le contenu se répartit chez les propriétaires, `MEMORY.md` ne se supprime jamais en silence. Voir `references/MODE-MIGRER.md`. |
| Projet inconnu, repris sans doc | Cartographie depuis le code et `git log`. Tu n'écris que ce que tu as vérifié, le reste porte « à vérifier » ou se demande. |
| Petit (moins de 150 fichiers) | Les trois piliers, aucune zone, quelques fiches au plus. |
| Moyen (150 à 600) | Une zone seulement là où le `CODEMAP.md` racine déborde. |
| Grand (plus de 600) | Le `CODEMAP.md` racine naît comme un index, chaque répertoire qui compte reçoit sa carte (étape 3). |
| Monorepo | Chaque unité autonome porte ses trois piliers, la racine pointe. Voir `references/ZONES.md`. |
| Parent à sous-modules | Chaque sous-module se clôture dans son dépôt, le parent le lit dans `.gitmodules` et pointe. |
| Plusieurs instances qui partagent un savoir | Le savoir commun vit dans `kb/socle/`, ce qui est propre à une instance dans `kb/contrib/`. Chaque instance pointe vers les deux. Voir `references/MULTI-DEPOTS.md`. |
| Projet en anglais | Le bloc déclare `langue: en`, la prose des piliers suit. Les noms de fichiers de la convention ne changent pas. |
| Projet hors code | Profil `non-technique`, le `CODEMAP.md` cartographie les documents et les procédures. |
| Gros projet déjà obèse | La greffe est une clôture. Pose le kit, mesure, puis va à la phase 5 de `references/MODE-CLOTURE.md`. |

## 2. Lire avant d'écrire

Arborescence, points d'entrée, `package.json` ou `pyproject.toml` ou `Makefile`, la CI, le README,
les dix derniers commits.

```bash
git log --oneline -10 && ls
```

**Observable** : chaque module que tu vas mettre dans la carte, tu l'as ouvert. Sinon il n'y entre
pas.

## 3. Remplir les piliers

1. `CODEMAP.md` : modules avec leur rôle en une ligne, points d'entrée, flux principal,
   dépendances externes, commandes qui marchent vraiment. Vérifie le bloc `contexte:convention` en
   tête, `ctx-init.sh` le remplit. Les clés sont dans `references/CONFIG-PROJET.md`, il doit
   porter `version: 5`.
2. `TODOS.md` : l'état réel, ce qui est en cours, ce qui est cassé, la dette visible.
3. `CHANGELOG.md` : une entrée d'amorçage. Tu ne réécris pas l'histoire passée.
4. `docs/` : une fiche par module qui en mérite une, un ADR pour une décision déjà prise qui
   engage la suite. Critère dans `references/DOCS-SYSTEM.md`. Ce que tu ne peux pas déduire se
   demande, il ne s'invente pas.
5. Grand projet, les zones :

   ```bash
   bash "$SKILL/scripts/ctx-audit.sh" --budget            # liste les zones candidates
   bash "$SKILL/scripts/ctx-init.sh" --zone src/<dir>     # pose la carte, --with-claude pour les règles
   ```

**Observable** : `bash "$SKILL/scripts/ctx-verite.sh"` ne rend aucune affirmation fausse sur ce
que tu viens d'écrire.

## 4. Brancher le projet sur la convention

Colle `templates/CLAUDE-snippet.md` dans le `CLAUDE.md` du projet, crée-le s'il n'existe pas. Le
bloc porte la convention de lecture et les trois lignes d'orchestration, que `ctx-init.sh` pose
déjà et ne duplique pas à un second lancement. Elles disent, en substance :

- la session principale garde le cadrage, l'arbitrage et la validation, et délègue le reste
  (`references/DELEGATION.md`)
- chaque tâche part au profil le moins cher qui tient son critère de fin
- un rapport de sous-agent tient en trois lignes, fait, reste, surpris

Chez Claude Code les profils s'appellent `fstack:<profil>`. Sans sous-agents, ces lignes se
lisent comme un découpage en étapes vérifiées.

**Observable** : `grep -c 'fstack:orchestration' CLAUDE.md` rend 1, y compris après un second lancement.

## 5. Finir

```bash
bash "$SKILL/scripts/ctx-audit.sh" --strict
```

Aucun blocage ne reste. Une alerte qu'on décide de garder se déclare dans `ecarts:` ou
`exceptions:` du bloc, avec sa raison. Si on t'avait demandé une clôture, enchaîne sur
`references/MODE-CLOTURE.md` sans redemander.
