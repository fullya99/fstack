# Anatomie du prompt d'exécution

## 1. La forme

Un seul bloc de texte, jamais écrit dans un fichier du projet. Il est joué dans une session neuve,
sans résidu de l'exploration qui précède. Chaque plateforme a sa façon d'en ouvrir une, chez
Claude Code une nouvelle session ou `/clear`.

Chez Claude Code, le bloc se range dans la file de relance, une entrée par plan, et
`/fstack:relance open` le joue après le redémarrage. Ailleurs, il est produit dans le chat et
l'opérateur le colle. Dans les deux cas il se suffit à lui-même : il ne suppose ni la reprise de
clôture ni le prompt d'un autre plan.

## 2. L'ordre des morceaux

La doc de prompting d'Anthropic mesure jusqu'à 30% de qualité en plus quand le contexte long
arrive en haut du prompt et les instructions en bas. Un modèle qui lit d'abord ce qu'il doit
savoir, et seulement ensuite ce qu'il doit faire, s'appuie sur ce savoir au moment d'agir. Dans
l'autre sens, l'instruction arrive avant le contexte qui la justifie et le modèle la traite à
moitié à vide.

Ordre imposé :

1. le chemin du plan, désigné comme source de vérité, à lire en entier avant toute chose
2. les décisions verrouillées, restatées en clair, pas seulement citées par référence
3. la liste de ce qu'on ne touche pas
4. les invariants
5. la composition de l'équipe et le rôle de chacun
6. les étapes et leurs portes de vérification
7. le démarrage, en dernier, explicite

## 3. La formulation

Dire ce qu'il faut faire plutôt que ce qu'il ne faut pas faire. « Regroupe le résultat dans un
état court en trois lignes » porte mieux que « ne rends pas un pavé de texte ». Quand une
interdiction est vraiment nécessaire, elle vient toujours avec sa raison : un interdit sec se
respecte moins qu'un interdit justifié, l'exécutant comprend le risque et ne cherche pas de
contournement. Éviter le registre « CRITIQUE, tu DOIS », qui pousse le modèle à une prudence
excessive sur tout le reste du prompt, pas seulement sur le point visé.

## 4. Les balises

Séparer les morceaux par des balises XML nommées, cohérentes d'un bout à l'autre du prompt :
`<plan>`, `<decisions>`, `<ne_pas_toucher>`, `<invariants>`, `<equipe>`, `<etapes>`, `<demarrage>`.
Une balise par section de la partie 2, dans le même ordre.

## 5. L'équipe

Trois à cinq agents, pas plus. Au-delà, le pilote passe plus de temps à coordonner qu'à avancer.

- **Le pilote.** La session principale qui lit le prompt. Il séquence les lots, ouvre les portes
  de vérification, ne code pas lui-même les gros lots pour garder son attention sur l'ordonnancement.
- **Les implémenteurs.** Un par lot indépendant, chacun en contexte frais. La demande de fond est
  un exécutant capable et appliqué, dont le modèle se règle par le mécanisme propre à la
  plateforme. Chez Claude Code, ça passe par un profil du plugin, `fstack:developpeur` ou
  `fstack:expert` selon le lot, le plus bas qui tient le critère de fin. Ailleurs, la même
  exigence se formule en clair dans le prompt.
- **Le relecteur.** En contexte frais, il ne voit que le diff produit et les critères de la tâche
  concernée, jamais l'historique de la conversation qui l'a fait naître. Son mandat s'arrête à ce
  qui casse la correction du code ou une exigence écrite dans le plan. Le style et la préférence
  personnelle restent hors de son mandat, sinon il en trouve toujours et l'exécution part en
  sur-ingénierie pour satisfaire des remarques qui ne comptaient pas.

## 6. La règle de parallélisme

Deux lots qui touchent les mêmes fichiers ne partent jamais dans le même tour. Le plan a déjà
tranché ce découpage dans sa section dédiée, le prompt ne fait que le restater pour que le pilote
n'ait pas à relire tout le plan pour retrouver l'information au moment d'agir.

## 7. Les portes de vérification

Une porte par étape, reprise du plan. Elles s'écrivent ici, dans le prompt d'exécution, jamais
dans le skill lui-même. Le skill tourne sur un modèle qui se vérifie déjà de lui-même, lui
redemander une vérification explicite ne fait que gaspiller des tokens en narration de
correction. Les implémenteurs, eux, tournent sur un modèle qui gagne à se l'entendre dire, donc
la consigne « avant de conclure, vérifie que [critère] » se met à chaque étape du prompt.

## 8. Ce qui remonte

Un sous-agent ne renvoie que son résultat final, le pilote ne voit jamais son fil de travail. Le
prompt demande donc à chaque implémenteur de terminer par un état court, trois lignes : ce qui
est fait, ce qui reste, ce qui a surpris. Sans cette consigne le pilote enchaîne les lots à
l'aveugle. Il leur demande aussi de mettre à jour la section Reprise du plan et de cocher les
étapes à la fin de leur lot. Ce sont les deux seules zones du plan qu'un exécutant modifie, et le
prompt le dit : les décisions, la conception et les critères ne se réécrivent pas en cours de
route. Un critère qui se révèle faux remonte au pilote, il ne s'assouplit pas pour devenir vert.

## 9. Exemple

Cas simple, un plan qui ajoute un champ `archived` à un modèle et l'expose dans une route.

```
<plan>
Lis en entier plans/ajout-champ-archived.md avant de commencer. C'est la source de vérité,
au-dessus de tout ce qui suit dans ce message.
</plan>

<decisions>
1. Le champ s'appelle `archived`, booléen, défaut false. Pas de champ `archivedAt`, la date
   n'a pas d'usage identifié aujourd'hui.
2. La route GET filtre les archivés par défaut, un paramètre `?archived=true` les inclut.
</decisions>

<ne_pas_toucher>
La table `users` et la route d'authentification. Le sujet est le modèle `Task` seul.
</ne_pas_toucher>

<invariants>
La suite de tests existante passe à chaque étape. Aucune migration destructrice, la colonne
s'ajoute avec un défaut, elle ne remplace rien.
</invariants>

<equipe>
Toi, le pilote : tu séquences les deux lots ci-dessous et tu ouvres les portes.
Implémenteur A : lot migration et modèle, profil fstack:developpeur.
Implémenteur B : lot route et tests d'intégration, profil fstack:developpeur, démarre
après le lot A puisqu'il consomme le champ qu'il ajoute.
Relecteur : profil fstack:relecteur, contexte frais, il voit uniquement le diff final et les critères de la tâche 2 du
plan. Il ne remonte que ce qui romprait le filtre par défaut ou la migration.
</equipe>

<etapes>
1. Lot A : migration et modèle. Avant de conclure, vérifie que la migration s'applique sur une
   base vide et que le test existant `tests/models/task.test.js` passe toujours.
2. Lot B : route et tests. Avant de conclure, vérifie que `GET /tasks` masque les archivés par
   défaut et les inclut avec `?archived=true`.
3. Relecture du diff complet par le relecteur en contexte frais.
</etapes>

<demarrage>
Commence par lire plans/ajout-champ-archived.md en entier, puis lance le lot A.
</demarrage>
```
