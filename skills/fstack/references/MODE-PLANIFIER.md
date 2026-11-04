# Mode PLANIFIER

> **Le contrat** : un plan ancré dans le terrain réel, sourcé sur du récent, validé par
> l'opérateur avant d'être écrit, passé par une contre-revue, suivi d'un prompt d'exécution qui
> pilote une équipe d'agents. Ce mode planifie, il n'exécute pas.

Avant d'écrire, charge le skill `style-redaction`. S'il manque, applique la langue déclarée par le
bloc `contexte:convention` du projet, ton direct, aucune tournure qui sent le texte généré.

## Quand ce mode s'applique

| Situation | Ce que tu fais |
|---|---|
| Idée à transformer en plan, sujet avec une vraie surface (code, infra, doc, migration, investigation) | Les six phases, dans l'ordre |
| Tâche en deux étapes et trois fichiers | Tu le dis, tu proposes de les ajouter à `TODOS.md`, pas de plan |
| Modification simple, question qui se répond en lisant un fichier | Tu réponds directement |
| Fin de session, mise au propre du dépôt | Mode CLÔTURE, pas celui-ci |

Si la demande n'entre dans aucune ligne, dis-le plutôt que de forcer un plan.

## Les six phases

### Phase 0. Triage

Deux minutes, sans lire de code.

- **Le type** : fonctionnalité, correctif, migration, refonte, infrastructure, documentation,
  investigation, hors code. Deux types possibles, prends le plus contraignant. Sections et pièges
  dans `references/plan/TYPES-DE-PLAN.md`.
- **L'environnement** : dépôt git ou non, stack par les manifestes (`package.json`,
  `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`, `*.csproj`...), commandes de test, lint et
  build réellement présentes, convention de contexte en place (`CLAUDE.md`, `AGENTS.md`,
  `CODEMAP.md`, `TODOS.md`, `docs/`). Terrain vierge, tu le notes et tu avances.
- **La surface externe** : lib, API, fournisseur, comportement qui a pu bouger. Sans surface, la
  phase 1 se saute et le plan l'écrit noir sur blanc.

**Fin de phase** : tu énonces en trois lignes le type, la stack et la surface externe.

### Phase 1. Recherche

Seulement si la surface externe est réelle. Un éventail de sous-agents `fstack:chercheur`,
un axe chacun, tous lancés dans le même tour, trois à cinq axes. Jamais un agent qui cherche tout.

Chaque affirmation repart avec son lien et sa date. Au-delà de six mois, elle se signale comme
peut-être périmée. Un agent qui ne trouve rien écrit « non trouvé », jamais une supposition.

**Ordre des sources.** La documentation officielle d'abord, puis la recherche web native, puis les
connecteurs MCP de recherche s'il y en a dans la session. Un serveur MCP n'est jamais un prérequis.
Un sous-agent ne voit pas toujours les outils du parent : sans eux, il passe par la recherche
native. L'agent écrit dans son rapport quel outil il a réellement utilisé, et le plan note
« recherche native » quand c'est le cas. Cascade complète et
contrat de sortie dans `references/plan/RECHERCHE.md`.

**Fin de phase** : chaque axe a rendu des faits avec lien et date, ou « non trouvé ».

### Phase 2. Exploration

Des agents `fstack:explorateur` sur les zones que le triage et la recherche ont désignées.
Ils rendent des chemins, des symboles et des faits, pas des impressions. Tu recoupes par une
commande (`ls`, `grep -n`, `wc -l`) tout chemin et tout chiffre qui entrera dans le plan. Sans
sous-agents, tu explores toi-même. Terrain vierge, tu lis seulement les conventions du langage.

**Fin de phase** : chaque chemin et symbole cité a été vu dans le dépôt réel.

### Phase 3. Questions

La phase que l'opérateur vit, elle reste légère.

- Cinq questions au plus, en une passe, chacune avec sa réponse par défaut annoncée. « ok pour
  tout » suffit.
- Langage normal, aucun jargon d'implémentation.
- Une question ne se pose que si la réponse change le plan. Sinon tu tranches et tu écris
  l'hypothèse.
- Une décision qui change le plan mais que personne ne peut trancher maintenant, parce qu'une
  information manque, ne s'invente pas et ne se reporte pas en silence. Elle s'écrit
  `DÉCISION À PRENDRE : <question> | options | ce qui en dépend` à l'endroit du plan qu'elle
  bloque. La contre-revue la referme avec l'opérateur.
- Tu proposes, l'opérateur décide, tu n'élargis jamais le périmètre seul.
- Tu termines par cinq lignes de reformulation. **Rien ne s'écrit avant le oui.**

**Fin de phase** : un oui explicite, ou des corrections que tu intègres puis re-soumets.

### Phase 4. Le plan

**Emplacement.** Le dossier déclaré par le bloc `contexte:convention` (clé `plans:` si elle y est),
sinon `plans/<slug>.md` à la racine du projet, slug en minuscules et tirets. Jamais en dehors du
projet. Sur une petite tâche, propose d'ajouter les étapes au suivi existant.

Rédige depuis `templates/plan.md`. Ossature, format d'une tâche et interdits (« TBD », chemin
inventé, étape sans vérification) dans `references/plan/PLAN.md`, sections propres au type dans
`references/plan/TYPES-DE-PLAN.md`.

**Le registre des écarts est obligatoire.** Toute porte préalable forcée y a son entrée avec sa
raison. Rien de forcé, la section dit « aucun écart » et reste dans le plan.

**La porte neuve, vérifier avant d'écrire.** Toute hypothèse de découpage du type « ces lots ne
partagent aucun fichier » se prouve par la liste réelle des fichiers de chaque lot, puis par
l'intersection :

```bash
comm -12 <(sort lot-a.txt) <(sort lot-b.txt)
```

Une sortie vide autorise le parallèle. Une sortie non vide met les deux lots en série, ou ces
fichiers passent dans un lot à eux. L'affirmation « aucun fichier commun » n'entre dans le plan
qu'avec cette vérification faite.

**Un profil par lot.** Chaque lot du découpage porte un profil `fstack:<profil>` parmi
`explorateur`, `controleur`, `executant`, `developpeur`, `chercheur`, `expert`, `relecteur`. Tu
prends le plus bas qui tient le critère de fin du lot et tu écris la raison en une ligne si tu
montes. Règles de graduation, de reprise après échec et de brief dans `references/DELEGATION.md`.
Au plus cinq agents en parallèle, jamais deux sur les mêmes fichiers. Sans sous-agents sur la
plateforme, le découpage devient une suite d'étapes vérifiées, un lot à la fois.

**La contre-revue, avant de rendre le plan.** Un `fstack:relecteur` en contexte neuf relit
le plan et challenge ses hypothèses. Sans sous-agents, tu fais la passe toi-même en relisant le
plan comme un étranger. Méthode :

1. Extraire les hypothèses challengeables : versions et flags de lib, comportements d'API ou de
   service, compatibilités, estimations de ressources et de coût, points marqués « à confirmer »,
   décisions du type « X ne supporte pas Y ». Noter la section source de chacune.
2. Les vérifier par recherche, jamais de mémoire : source primaire (doc officielle, issue,
   changelog), en parallèle, avec la dégradation de la phase 1. Les hypothèses sur le dépôt se
   vérifient par commande.
3. Classer chaque constat :

| Niveau | Critère |
|---|---|
| Bloquant | Hypothèse fausse qui casse le plan tel quel ou viole une contrainte irréversible |
| Majeur | Non vérifiée ou partiellement fausse, redesign ou bug probable |
| Modéré | Alternative plus simple ou précision à apporter, ne bloque pas |
| Validé | Confirmée par une source primaire |

Un constat tient en une entrée : identifiant `F-01`, sévérité, ce qui est faux, source avec lien,
action concrète. Pas de constat de goût, pas d'issue marginale pour gonfler la liste, pas de
« Validé » sans source.

4. Annoter le plan : une section `Contre-revue` avec le tableau des constats non validés. Chaque
   constat est **intégré** (la section du plan change, tu la cites) ou **rejeté** (raison écrite).
   Un constat sans décision écrite interdit de rendre le plan. Les validés se listent en une ligne.

**Fin de phase** : le fichier du plan existe à l'emplacement prévu,
`grep -nE 'TBD|TODO|à voir|DÉCISION À PRENDRE'` n'y trouve rien, la contre-revue n'a aucun
Bloquant ou Majeur sans décision écrite, les interfaces se bouclent dans les deux sens
(`references/plan/PLAN.md`, section 2), et chaque lot a son profil.

### Phase 5. Le prompt

Un seul bloc, jamais dans un fichier du projet. Il s'adresse à une session neuve, sans résidu
de l'exploration, ce que chaque plateforme permet à sa façon (chez Claude Code, une nouvelle
session ou `/clear`). Ordre, contexte long d'abord : le plan à lire en entier, les décisions
verrouillées restatées, ce qu'on ne touche pas, les invariants, l'équipe, les étapes avec leur
porte de vérification, le démarrage en dernier. Balises `<plan>`, `<decisions>`,
`<ne_pas_toucher>`, `<invariants>`, `<equipe>`, `<etapes>`, `<demarrage>`.

L'équipe reprend les profils du découpage. Anatomie, formulation et exemple dans
`references/plan/PROMPT.md`.

**Le prompt va dans la file de relance, pas dans le chat.** Chez Claude Code, tu le ranges par la
commande « prompt d'un plan » de la rubrique « Témoin de clôture et prompt de relance » du
`SKILL.md`, avec le chemin du plan. Il prend place à côté de la reprise de clôture sans l'écraser,
le hook l'annonce au prochain démarrage et `/fstack:relance open` le joue. Le chat ne reçoit
qu'une ligne : le nom de l'entrée et la consigne « redémarre le contexte, puis
`/fstack:relance open` ». Le bloc ne s'affiche en entier que si l'opérateur le demande, ou si
le script répond qu'il n'a rien rangé (`CLAUDE_PLUGIN_DATA` absent, autre plateforme).

**Plateformes sans prompt à coller.** Elles lisent le plan lui-même. La section Reprise du plan
suffit alors à redémarrer, le prompt de la phase 5 est facultatif.

**Fin de phase** : le script a répondu « range dans la file de relance » avec le nom de l'entrée,
ou le bloc est dans le chat, et ses sept balises sont présentes.

## Plusieurs plans dans la même session

Chaque plan passe ses six phases et finit dans sa propre entrée de la file. Le plan suivant
repart de la phase 0. La recherche et l'exploration déjà faites se réutilisent quand elles
couvrent le sujet, les questions de la phase 3 se reposent pour lui seul.

- **Un plan, une session d'exécution.** Le prompt d'un plan ne pilote que ce plan. Jamais un
  prompt qui enchaîne deux plans : la session d'exécution chargerait les deux et perdrait le
  bénéfice du contexte neuf.
- **L'ordre.** La file joue les plans dans l'ordre où ils ont été rangés. Un plan qui consomme ce
  qu'un autre livre se range avec `--apres <plan>` : tant que l'autre attend, il passe son tour.
  Le plan l'écrit dans sa section État actuel, avec ce qu'il attend de l'autre.
- **Aucun fichier commun sans le dire.** Deux plans qui touchent les mêmes fichiers se rangent en
  dépendance, jamais côte à côte. La vérification `comm -12` de la phase 4 vaut aussi entre plans.
- **Le compte rendu final** liste les entrées rangées, dans l'ordre où elles se joueront.

## Reprise, tenue par l'exécutant

La section Reprise du plan n'est pas figée à l'écriture. L'exécutant la met à jour à la fin de
chaque lot : état actuel, prochaine tâche non cochée, ce qui est validé et ne se refait pas,
commande d'état du terrain. Les cases d'étapes se cochent au même moment. Le prompt de la phase 5
le demande en clair dans chaque étape.

## Invariants, jamais négociables

- ❌ Rien ne s'écrit avant le oui de l'opérateur en fin de phase 3.
- ❌ Aucun chemin ni symbole qui n'a pas été vérifié dans le vrai dépôt.
- ❌ Aucune étape sans critère de vérification.
- ❌ Aucune affirmation « ces lots ne partagent aucun fichier » sans la liste réelle des fichiers.
- ❌ Aucun plan rendu avec un constat Bloquant ou Majeur sans décision écrite.
- ❌ Aucun outil MCP en prérequis, on dégrade et on le dit dans le plan.
- ❌ Aucun commit, aucun push. Ce mode ne modifie aucun fichier du projet hors du plan. La file
  de relance vit hors du dépôt.
- ❌ Aucun plan en dehors du projet.

## Références, à charger au besoin

| Fichier | Quand le lire |
|---|---|
| `references/plan/RECHERCHE.md` | Cascade des serveurs, dégradation, axes, contrat de sortie |
| `references/plan/TYPES-DE-PLAN.md` | Les huit types, leurs sections et leur piège |
| `references/plan/PLAN.md` | Ossature, format d'une tâche, interdits |
| `references/plan/PROMPT.md` | Anatomie du prompt, équipe, exemple |
| `references/DELEGATION.md` | Profils, graduation, règles de brief et de parallélisme |
| `templates/plan.md` | Gabarit de la phase 4 |
