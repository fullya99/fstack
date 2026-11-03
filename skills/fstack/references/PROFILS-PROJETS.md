# PROFILS-PROJETS : adapter la convention à un projet

> La convention est la même partout, son remplissage change. Un profil dit ce qu'INIT pose et ce
> que le bloc `contexte:convention` doit déclarer. La taille se mesure à part, elle ne dépend pas
> du profil.

## Détecter le profil

Sans bloc dans `CODEMAP.md`, INIT déduit le profil des fichiers présents, prend le dominant et
note les autres dans le bloc. En cas de doute, il demande.

`ctx-init.sh` teste dans cet ordre, du plus spécifique au plus général : un moteur de jeu ou une
app mobile porte aussi un `package.json` ou un dossier `Packages/`, il passe donc avant app et
monorepo. Les noms de dossier se comparent à la casse près, parce que macOS répond oui à
`packages/` pour le `Packages/` d'Unity. Le banc `tests/test-ctx-init.sh` fixe chaque ligne.

| Indices | Profil |
|---|---|
| `.claude-plugin/plugin.json`, `skills/*/SKILL.md`, `SKILL.md`, `.claude/skills/` | outillage-agent |
| `ProjectSettings/ProjectVersion.txt` (Unity), `project.godot`, `*.uproject` (Unreal) | jeu |
| `pubspec.yaml` (Flutter), `android/` et `ios/` ensemble, `*.xcodeproj`, `app/src/main/AndroidManifest.xml` | mobile |
| `pnpm-workspace.yaml`, `turbo.json`, `go.work`, `nx.json`, `lerna.json`, `packages/`, `apps/` | monorepo |
| `src-tauri/`, `electron` dans `package.json` | desktop |
| `terraform/`, `ansible/`, `k8s/`, `*.tf`, `Chart.yaml` | infra |
| `notebooks/`, `*.ipynb`, `dvc.yaml` | data |
| `Cargo.toml` avec `src/lib.rs` sans `src/main.rs`, `package.json` qui exporte sans script `start` ni `dev` | lib |
| `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `manage.py`, `pom.xml`, `build.gradle`, `composer.json`, `Gemfile`, `mix.exs`, `Package.swift`, `deno.json`, `CMakeLists.txt`, `*.sln`, `*.csproj`, `requirements.txt` | app |
| `content/`, `posts/` | contenu |
| `.gitmodules` avec des enfants équipés | parent à sous-modules |
| aucun code, documents et suivi | non technique |

## La taille

Comptée en fichiers, hors dépendances, builds et `archives/`. L'audit la mesure, `ctx-init.sh` ne l'écrit pas.
Seule `taille-forcee:` existe, posée par la migration quand l'opérateur garde une valeur qui
diffère de la mesure (voir `CONFIG-PROJET.md`).

| Taille | Fichiers | INIT pose |
|---|---|---|
| petite | moins de 150 | un seul niveau, aucune zone |
| moyenne | 150 à 600 | des zones là où la carte racine déborde |
| grande | plus de 600 | des zones d'emblée, la carte racine n'est qu'un index |

## Profils de nature

**Projet neuf.** Aucun code, aucun historique. INIT pose les gabarits courts et le bloc, rien
d'autre. Les cartes se remplissent au fil des sessions, pas par anticipation.

**Existant documenté autrement.** README, wiki, dossier `memory-bank`. INIT greffe les trois piliers à
côté et fait pointer le bloc vers l'existant. Rien n'est dissous, ce qui est déjà en place reste
tant que l'opérateur n'a pas tranché.

**Reprise d'un projet inconnu.** INIT cartographie depuis le code et l'historique git. Il
n'écrit que ce qu'une commande a confirmé, le reste part en questions dans `TODOS.md`.

**App.** Module : une couche ou un domaine. Le bloc déclare la commande de démarrage et celle des
tests. La carte insiste sur les points d'entrée, le flux d'une requête et les variables d'environnement.

**Lib.** Module : un sous-ensemble de l'API publique. Le journal est un livrable public, format
Keep a Changelog, ce que la clé `journal:` déclare. La carte donne la surface exportée.

**Infra.** Module : un composant déployé. L'état vit hors du dépôt, donc le bloc déclare la
source d'autorité à interroger (état du provisioning, console). `docs/ops/` est le cœur, et
chaque entrée de journal porte son retour arrière. Jamais une valeur de secret, seulement son
emplacement.

**Data.** Module : une étape de pipeline. La carte donne le lignage et l'emplacement des
artefacts. Tout chiffre cité porte la date de son run.

**Contenu.** Module : une rubrique ou un canal. Le ton et le positionnement vont dans
`CLAUDE.md`, les angles abandonnés dans `archives/`.

**Jeu.** Module : un système de jeu (combat, inventaire, interface, IA) ou une scène majeure, pas
un dossier d'assets. Le bloc déclare la version exacte du moteur (`ProjectSettings/ProjectVersion.txt`,
`project.godot`, le `.uproject`) et la commande de build sans éditeur (Unity en `-batchmode`,
Godot en `--headless --export-release`, Unreal par `RunUAT BuildCookRun`). Les assets binaires
sont hors budget et hors relecture : la carte donne leurs dossiers, le pipeline d'import et ce que
`.gitattributes` met en LFS. Les scènes et prefabs sont du texte généré par l'éditeur : un piège
classique, à écrire dans la carte, est de les éditer à la main l'éditeur ouvert. Les caches du
moteur (`Library/`, `Temp/`, `Intermediate/`, `DerivedDataCache/`, `.godot/`) ne sont jamais du
contexte.

**Mobile.** Module : un écran ou une fonctionnalité, rarement une plateforme. La carte sépare le
code partagé de ce qui vit sous `android/` et `ios/`. Le bloc déclare les versions minimales de
SDK et la commande de build de chaque plateforme. Certificats, profils de provisioning et
keystores ne vivent jamais dans le dépôt : la carte donne leur emplacement.

**Desktop.** Module : un processus (principal et rendu chez Electron, cœur Rust et vue web chez
Tauri) ou une fenêtre. La carte nomme la frontière entre les deux et ce qui la traverse (IPC,
commandes). La signature de code et la mise à jour automatique sont des procédures, elles vont
dans `docs/`.

**Monorepo.** Chaque package équipé garde son kit, la racine pointe sans recopier. Le bloc liste
les packages et les zones. Voir `ZONES.md`.

**Parent à sous-modules et instances qui partagent un savoir.** INIT ne touche que le parent et
liste les enfants. Voir `MULTI-DEPOTS.md`.

**Outillage d'agent.** Module : un skill, une commande ou un script. Le projet applique sa propre
convention. La vérification porte sur les chemins cités depuis le skill et sur les scripts
exécutables.

**Projet en anglais.** Le bloc déclare `langue: en`, INIT pose les gabarits avec des en-têtes
anglais et l'audit ne cherche pas les français.

**Projet hors code.** Module : un chantier. `docs/decisions/` porte l'essentiel, chaque arbitrage
et la position des parties prenantes valent un ADR. Le journal tient lieu de compte rendu.

## Adapter sans casser

Trois libertés, toutes déclarées dans le bloc : renommer (les rôles comptent, pas les noms),
fusionner sur un très petit projet (la fusion se défait dès qu'une section dépasse une page),
étendre par un pilier de plus s'il répond à une question qu'aucun autre ne couvre.

Jamais adapté, quel que soit le profil : le bloc d'état à la reprise, l'archivage au lieu de la
suppression, l'interdiction de lire `archives/` comme source de vérité, aucune affirmation
connue fausse après une clôture.

Aucun outil externe n'est requis. Une recherche web ou un outil de projet accélère une
vérification, une étape de clôture n'échoue jamais faute d'eux.
