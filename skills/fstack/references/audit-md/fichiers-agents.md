# Les fichiers d'agents

Chargé en phase 2, quand le dépôt déclare des sous-agents. Vérifié le 2026-08-23 sur la
documentation Claude Code, sur `docs.openclaw.ai` et sur `agentskills.io/specification`.

Ces fichiers cassent différemment du `CLAUDE.md`. Un `CLAUDE.md` faux se charge quand même et fait
faire des bêtises. Un fichier d'agent mal formé **ne se charge pas du tout**, sans erreur, sans
avertissement. L'agent n'apparaît simplement pas, et celui qui l'a écrit croit qu'il tourne.

## Où ils vivent

| Emplacement | Portée | Tu y touches ? |
|---|---|---|
| `.claude/agents/*.md`, récursif | le projet | oui |
| `agents/` d'un plugin installé | là où le plugin est actif | non, ce n'est pas ton dépôt |
| `~/.claude/agents/*.md` | toutes les machines de la personne | non, tu signales |
| réglages gérés de la machine | l'organisation | non, tu signales |

Quand deux définitions portent le même nom, celle qui est le plus près du répertoire de travail
gagne. Deux fichiers du **même** répertoire avec le même `name` : un seul se charge, et rien ne
dit lequel.

## Les quatre disparitions silencieuses

C'est ce que le script cherche en premier.

1. **Pas de frontmatter.** Le fichier est traité comme de la documentation.
2. **Pas de `name`.** Ignoré, la trace part dans le journal de débogage.
3. **`name` avec un deux-points, ou qui commence par un tiret.** Rejeté au chargement.
4. **Pas de `description`.** Ignoré, même silence.

Un YAML qui ne parse pas peut tomber dans le même trou. Le cas le plus fréquent chez nous : une
`description` non quotée qui contient `": "`. Elle peut être refusée par un parseur strict, quote la
valeur. Claude Code, lui, la charge quand même.

## Les clés, et ce qui arrive à une valeur fausse

Une valeur hors liste n'est pas refusée, elle est **ignorée**. L'agent tourne, avec le défaut, et
personne ne voit passer la consigne.

| Clé | Obligatoire | Valeurs |
|---|---|---|
| `name` | oui | minuscules et tirets, pas de deux-points |
| `description` | oui | texte. C'est elle seule qui décide de la délégation automatique |
| `tools` | non | liste blanche. Absente, l'agent hérite de tout |
| `disallowedTools` | non | liste noire, appliquée avant `tools` |
| `model` | non | `sonnet`, `opus`, `haiku`, `fable`, `inherit`, ou un identifiant complet |
| `permissionMode` | non | `default`, `acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`, `plan`, `manual` |
| `maxTurns` | non | entier positif |
| `skills` | non | noms de skills préchargés au démarrage |
| `mcpServers` | non | noms de serveurs, ou définitions en ligne |
| `hooks` | non | `PreToolUse`, `PostToolUse`, `Stop` |
| `memory` | non | `user`, `project`, `local` |
| `background` | non | `true`, `false` |
| `effort` | non | `low`, `medium`, `high`, `xhigh`, `max` |
| `isolation` | non | `worktree` |
| `color` | non | `red`, `blue`, `green`, `yellow`, `purple`, `orange`, `pink`, `cyan` |
| `initialPrompt` | non | texte, soumis au premier tour quand l'agent est la session principale |

**Une clé absente de cette table est ignorée en silence.** Une faute de frappe sur un nom de clé
désactive l'option sans rien dire, et c'est un des défauts les plus durs à voir à l'oeil.

## Ce que le script ne sait pas voir

Trois choses, et elles demandent de lire.

**La description déclenche-t-elle ?** Elle seule décide. Une description de trois mots ne se
déclenche jamais. Une description qui dit ce que fait l'agent sans dire quand l'appeler non plus.
La forme qui marche donne les deux : le métier, puis les situations en mots réels.

**Deux agents se marchent-ils dessus ?** Deux descriptions proches, et le mauvais gagne une fois
sur deux. C'est une contradiction, elle part en phase 4, tu ne la tranches pas.

**Le corps redit-il le `CLAUDE.md` ?** Un sous-agent hérite déjà des instructions du projet. Ce
qu'il répète est payé deux fois, et diverge à la première modification d'un des deux.

## La règle qui ne bouge pas

**Tu ne réécris jamais le corps d'un fichier d'agent.** Un frontmatter cassé se corrige, la valeur
juste est vérifiable dans la table ci-dessus. Le prompt, lui, est un choix de son auteur. Tu
signales qu'il redit le `CLAUDE.md`, tu proposes la coupe, et tu attends le oui.

## Chez les autres lecteurs

Hermes et OpenClaw n'ont pas de fichier de définition de sous-agent équivalent. Chez Hermes,
chaque skill installé devient une commande, et l'identité de l'agent vit dans `SOUL.md`. Chez
OpenClaw, un sous-agent est un lancement de session en arrière-plan, configuré dans
`openclaw.json`, pas dans un markdown.

Ce que ces deux plateformes ont à la place, et qui mérite le même audit, ce sont leurs catalogues
de skills. Hermes en écrit tout seul et les retouche à l'usage, OpenClaw a un atelier où l'agent
propose des skills à valider. Doublons, chevauchements, skills périmés : même travail, même
méthode.
