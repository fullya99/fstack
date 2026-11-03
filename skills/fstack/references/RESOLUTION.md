# RESOLUTION : pourquoi la boucle `$SKILL` cherche là, dans cet ordre

Lis cette page quand la boucle rend vide alors que le skill est installé sur la machine, ou
quand elle résout une version qui n'est pas la bonne.

## L'ordre des candidats

L'ordre est voulu. `CLAUDE_PLUGIN_ROOT` d'abord quand le skill tourne comme plugin, puis la
portée projet chez Claude Code et chez Codex, puis la portée utilisateur des deux, puis les
copies de plugin de Claude Code.

## Les deux répertoires utilisateur de Codex

Codex a deux répertoires de portée utilisateur, `~/.codex/skills/` où son installeur dépose, et
`~/.agents/skills/` du standard ouvert. Les deux sont scannés, vérifié le 2026-08-14. Le premier
passe avant parce qu'il porte la version que l'utilisateur a réellement installée, quand l'autre
peut garder une copie posée à la main et devenue vieille.

## Les deux copies d'un plugin Claude Code

Un plugin installé existe en deux copies. `cache/<marketplace>/<plugin>/<version>/` porte la
version réellement installée, `marketplaces/<marketplace>/` porte la pointe de `master` du
dépôt. On cherche le cache d'abord, et le `sort -r` prend la version la plus haute quand
plusieurs sont en cache. Sans cet ordre, un `find` unique renvoie les deux et prend celle que le
parcours donne en premier, ce qui choisit au hasard dès que le dépôt a avancé au-delà de la
version installée.

Le test porte sur la présence de `scripts/ctx-audit.sh`, ce qui écarte au passage les
répertoires homonymes.

## La remontée des ancêtres

Codex n'a pas d'équivalent de `CLAUDE_PLUGIN_ROOT`, cette boucle est son seul mécanisme de
résolution. Il remonte l'arborescence pour trouver `.agents/skills/`, et `$ANCETRES` fait la
même chose avant la boucle, en testant chaque ancêtre du répertoire courant. Un skill posé à la
racine d'un dépôt pendant qu'on travaille dans un sous-dossier est donc trouvé. Vérifié sur un
banc d'essai Codex du 2026-08-14.

## Symptôme, cause, geste

| Symptôme | Cause probable | Ce qu'on fait |
|---|---|---|
| Boucle vide en installation plugin | `CLAUDE_PLUGIN_ROOT` non posé | on passe par la portée utilisateur |
| Vieille version résolue | le clone du marketplace a gagné sur le cache | on relance `claude plugin update` |
| Codex ne trouve rien | le skill est dans `~/.claude/skills` et pas dans `~/.agents/skills` | on copie |
