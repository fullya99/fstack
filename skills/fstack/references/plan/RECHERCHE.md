# Recherche, quand et comment

## Quand chercher, quand ne pas chercher

La surface externe décide. Une refonte interne pure, un correctif dans du code qu'on possède, un
renommage : pas de recherche, le plan l'écrit noir sur blanc plutôt que de se remplir de notes
hors sujet.

Une lib externe, l'API d'un fournisseur, une version récente, un comportement susceptible d'avoir
bougé, un choix technologique à trancher : recherche.

## L'ordre des sources

1. La documentation officielle de l'outil ou du service, à la version visée. C'est la source de
   vérité et elle évite l'API inventée.
2. La recherche web native de la plateforme, pour les faits datés, les retours de terrain et les
   pages à lire en entier.
3. Les connecteurs MCP de recherche, s'il y en a dans la session. Ils sont parfois différés au
   démarrage : charge-les avec `ToolSearch` avant de conclure qu'ils manquent, et retrouve leur
   nom réel par cette recherche, ne le code jamais en dur.

## La dégradation

Aucun connecteur n'est un prérequis. Absents, ou invisibles au sous-agent qui n'hérite pas des
outils du parent, la recherche native fait le travail, moins bien, et le sous-agent le note dans son
rapport. Le plan écrit « recherche native » dans ce cas.

## Le découpage en axes

Un sous-agent par axe, tous lancés dans le même tour. Trois à cinq axes suffisent, rarement plus.
Axes types :

- l'outil ou la lib visée et sa version courante
- l'état de l'art de la pratique
- les pièges et retours de terrain
- la contrainte réglementaire ou de plateforme, quand il y en a une

Ne donne jamais deux axes au même sous-agent. Un chercheur qui doit couvrir deux sujets en couvre
un bien et l'autre mal, et rien ne dit lequel.

## Le contrat de sortie d'un chercheur

Des notes brutes, pas un rapport mis en forme. Chaque affirmation part avec son lien et sa date.
Une source de plus de six mois se marque comme peut-être périmée. Ce qui est contesté entre deux
sources se signale comme tel plutôt que d'être tranché à la place de l'opérateur. Rien de trouvé
sur un point s'écrit « non trouvé », jamais une supposition habillée en fait, et jamais nu : il
porte les requêtes lancées, les sources consultées et la date, sinon personne ne sait si le point a
été cherché.

Deux pièges reviennent. Une procédure reconstituée à partir de deux pages générales passe à côté
de la page qui nomme les deux technologies ensemble, d'où une première requête qui les cite toutes
les deux, dans les termes de l'éditeur. Et une page extraite se juge sur son code de statut avant
son contenu : derrière un 401 ou une page de connexion, l'extraction rend quand même du texte, et
un modèle en tire une procédure inventée.

Pas d'introduction, pas de conclusion. Le sous-agent qui synthétise avant de rendre perd la
traçabilité que ces notes existent pour donner.

## Ce qui entre dans le plan

Seulement ce qui a façonné une décision. Une note de recherche que le plan n'utilise pas ne s'y
recopie pas, elle reste dans les notes du sous-agent. Un plan encombré de recherche non exploitée
est plus dur à relire qu'un plan qui va droit aux décisions qu'elle a produites.
