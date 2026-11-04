# fstack

Une seule stack de contexte pour tous les projets. Si une information ne vit que dans la
conversation, elle n'existe pas : le dépôt seul doit suffire à reprendre le travail, après un
`/clear` comme après trois semaines.

Le plugin installe une convention à trois piliers, `CODEMAP.md`, `TODOS.md` et `CHANGELOG.md`, plus
`docs/` pour la connaissance longue et `archives/` pour ce qui est devenu faux. Chaque fichier tient
dans un budget, et ce qui déborde descend d'un étage.

Il remplace `cloture-session`, `deep-plan` et `clawd-audit-md`. Retire-les s'ils sont installés,
deux skills sur le même cycle se disputent le déclenchement.

## Les commandes

| Commande | Quand |
|---|---|
| `/fstack:init` | Une fois, pour installer la convention dans un projet |
| `/fstack:planifier` | Pour cadrer une idée en plan sourcé. Son prompt d'exécution part dans la file de relance, un par plan, plusieurs plans par session si besoin |
| `/fstack:cloture` | En fin de session, avant un `/clear`. Range la reprise de la session suivante, sauf avec `sans-relance`, sans toucher aux prompts de plan |
| `/fstack:relance` | Après un `/clear`, pour retrouver le fil en dix lignes. `open` joue la prochaine entrée de la file, la reprise d'abord puis les plans dans l'ordre, `open <plan>` en choisit une |
| `/fstack:audit` | Pour vérifier `CLAUDE.md` et `AGENTS.md` contre le code et les raccourcir |
| `/fstack:migrer` | Pour remettre une ancienne convention à jour, sur une branche, en simulation d'abord |

## Installation

```
/plugin marketplace add fullya99/fstack
/plugin install fstack@fstack
```

Ou à la main, en copiant le dossier du skill et non celui du plugin :

```bash
mkdir -p ~/.claude/skills
cp -r skills/fstack ~/.claude/skills/
```

Sur Codex d'OpenAI, même dossier, autre chemin de scan :

```bash
cp -r skills/fstack .agents/skills/      # portée dépôt
cp -r skills/fstack ~/.agents/skills/    # portée utilisateur
```

Par ces deux voies les commandes slash ne suivent pas, elles n'existent qu'en installation plugin
chez Claude Code. Le skill se déclenche quand même sur une demande en français.

## Ce qu'il ne fait pas

Il ne commite pas, ne pousse pas, et ne devine pas. Ce qu'il ne peut pas déduire du projet, il le
demande. Bash et git suffisent, aucun serveur MCP n'est requis.
