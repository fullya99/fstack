<!--
Bloc à coller dans le CLAUDE.md (ou AGENTS.md) du projet, à la fin.
Crée le fichier s'il n'existe pas. Adapte les chemins si le projet en utilise d'autres.
Garde-le court : CLAUDE.md est chargé à chaque session, c'est la surface la plus coûteuse.
-->

## Convention de contexte

Ce projet est documenté pour qu'un redémarrage à froid ne coûte jamais d'information. Le dépôt est
la source de vérité, pas la conversation.

**À lire en début de session, dans cet ordre**

1. `TODOS.md`, le bloc « État à la reprise » d'abord, et rien d'autre du fichier. C'est le point
   d'ancrage.
2. `CODEMAP.md`, son plan puis la section utile, pour localiser ce qu'on va toucher. Si la zone
   concernée porte sa propre carte, c'est elle qu'on lit.
3. `CHANGELOG.md`, les 2 ou 3 dernières entrées seulement.
4. Les fiches `docs/` des seuls modules concernés par la tâche. `docs/README.md` est l'index.
   `docs/decisions/` porte les choix déjà tranchés et leur pourquoi.

**Ne jamais lire `archives/` en reprise.** C'est du contenu faux ou froid par construction, gardé
pour l'historique. Pour y chercher quelque chose, passe par le skill `fstack` : son mode relance
résout le chemin du script de recherche, qui rend la provenance avec l'extrait sans charger les
fichiers. Un grep nu rend la ligne sans son en-tête.

**En fin de session, avant tout redémarrage à froid** : lancer `/fstack:cloture`, ou simplement demander
de ranger le projet. Ça resynchronise les 3 piliers, met à jour les fiches `docs/` des modules
touchés, déplace vers `archives/` tout ce qui est devenu faux, et remet chaque fichier dans son
budget.

**Les règles qui tiennent l'ensemble**

- Aucune suppression silencieuse. Ce qui est obsolète va dans `archives/`, avec sa raison.
- Aucune affirmation connue-fausse laissée dans les docs ou dans les piliers.
- Une règle durable devenue fausse est supprimée tout de suite, elle n'est pas archivée.
- Un savoir a un propriétaire et un seul : décision en ADR, piège dans la fiche du module ou la
  carte de sa zone, préférence durable ici, contrainte d'environnement dans le CODEMAP.
- Aucun travail en cours sans une tâche écrite dans `TODOS.md`.
- Chaque surface a un budget. Ce fichier vise 100 lignes et ne porte ni état ni récit, le bloc de
  reprise tient en 40 lignes, le CHANGELOG tourne. Une doc vraie mais trop longue est une doc perdue.
- Jamais de secret dans un fichier tracké. On dit où est la clé, pas ce qu'elle vaut.

**Style de rédaction** : français, ton direct. Pas de tiret cadratin, pas de point-virgule, pas
de tournure qui sent le texte généré. La règle complète est dans le skill `style-redaction`, à
charger avant d'écrire un document.

<!-- fstack:orchestration -->
## Orchestration

- La session principale orchestre et garde le jugement : cadrage, arbitrage, décision irréversible, validation.
- Chaque tâche part au profil `fstack:<profil>` le moins cher qui tient son critère de fin.
- Le détail est dans la référence `DELEGATION.md` du skill `fstack`.
