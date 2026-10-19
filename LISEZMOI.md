# Papi Commando CPC — moteur « beaucoup d'ennemis »

Amstrad CPC 464 / 664 / 6128 (64 Ko), MODE 0, 100 % assembleur Z80 (RASM).
**Version 09 : écran en OVERSCAN VERTICAL (232 lignes, bandeau en haut), soldats et OFFICIERS (zone 1 : 8 unités, 75 % / 25 %, 25 ennemis à abattre) — voir les deux dernières sections.**

L'archive d'origine ne contenait pas le code source du jeu, seulement les
graphismes, les sons, la carte Tiled et RASM. Ceci est donc une **réécriture
complète** à partir de ces fichiers, pensée dès le départ pour qu'un grand
nombre d'ennemis ne fasse jamais tomber le jeu en dessous de 50 images par
seconde. Ce n'est pas une correction du code existant : c'est un exemple
complet et commenté dont on peut reprendre les idées une par une.

## Lancer

- `build/PAPICPC.dsk` : insérer la disquette puis `RUN"PAPICPC"`
- `build/papicpc.sna` : instantané à charger directement dans un émulateur
- `doc/demo_8_16_24_ennemis.mp4` : vidéo de la v02 (HUD en bas, jusqu'à 24 ennemis) ; elle ne montre plus le jeu actuel

| Action | Joystick | Clavier |
|---|---|---|
| Se déplacer (8 directions) | manette | flèches |
| Tirer | bouton 1 | ESPACE ou COPY |
| Grenade | bouton 2 | RETURN |
| Nombre d'ennemis : 2, 4, 6, 8, 10, 12 | | touches 1 à 6 |
| Jauge de charge dans la bordure | | M |

La jauge colore la bordure en rouge tant que le Z80 travaille et la remet en
noir quand il attend l'image suivante : la hauteur de rouge est le temps
consommé. C'est l'outil le plus utile pour savoir où part le temps.

## Ce que ça donne

Mesures faites dans un émulateur CPC 464 exact au cycle, piloté sans écran
(`tools/cpcrun.c`), avec un joueur automatique qui bouge, tire et lance des
grenades pendant 3000 images (une minute) :

| Ennemis | Boucles de jeu par seconde | Temps machine moyen par image | Pire image |
|---:|---:|---:|---:|
| 2 | 50 | 5,5 ms | 10,5 ms |
| 4 | 50 | 7,7 ms | 16,7 ms |
| 6 | 50 | 9,7 ms | 17,7 ms |
| 8 | 50 | 12,2 ms | 18,4 ms |
| 10 | 50 | 14,2 ms | 19,2 ms |
| 12 | 50 | 15,5 ms | 19,1 ms |

(Mesures de la v04, 6128 émulé ; le 464 émulé donne les mêmes chiffres à 6 et 12 ennemis. Marge sur la pire image : environ 0,8 ms.)

Une image dure 19,97 ms. Papi, ses balles et la grenade sont toujours traités
à 50 Hz. Quand il y a trop d'ennemis pour tous les traiter à chaque image, ce
sont eux qui seraient rafraîchis moins souvent (le maximum est maintenant de 12),
sans que leur vitesse à l'écran change.

## Pourquoi un jeu CPC rame quand les ennemis se multiplient

Sur un CPC, l'IA proprement dite pèse peu. Ce qui coûte :

1. **L'affichage.** Un sprite de 12×12 pixels MODE 0, c'est 72 octets à
   composer avec le décor : environ 0,9 ms dans ce moteur, souvent 2 à 3 ms
   avec une routine classique (effacer, puis masquer, puis écrire). À 3 ms par
   sprite, 7 ennemis suffisent à remplir une image.
2. **Tout ce qui est fait « pour chaque ennemi, à chaque image »** : comparer
   chaque ennemi à tous les autres, recalculer une direction, appeler le
   système.
3. **Les multiplications et divisions**, que le Z80 n'a pas.

## Les sept idées du moteur (et où les trouver dans `src/papicpc.asm`)

**1. Un budget de temps, pas un nombre fixe d'ennemis par image** —
`enemies_update`, `int_handler`.
L'interruption du CPC (300 fois par seconde) ne sert que d'horloge : elle
compte les sixièmes d'image. Papi, les balles et le reste passent d'abord ;
ensuite on traite les ennemis à tour de rôle et on s'arrête dès que le
cinquième top est passé (16,8 ms). L'image suivante reprend là où on s'était
arrêté. Résultat : jamais d'image sautée, quel que soit le nombre d'ennemis.

**2. Chaque ennemi rattrape le temps qu'il a attendu** — `dt_tab`.
Un ennemi sait combien d'images ont passé depuis son dernier tour (1 à 4) et
avance d'autant, en virgule fixe. Sa vitesse à l'écran ne dépend donc pas de
la charge.

**3. Une seule écriture par octet d'écran** — `draw_sprite`, `comp_c`,
`comp_l`, `comp_r`.
Une copie du décor (le « miroir », en #8000) a exactement la même disposition
que l'écran. Pour afficher un sprite on écrit directement
`(décor ET masque) OU sprite`. On ne remet le décor que sur la bande d'un
octet ou d'une ligne que le sprite vient de quitter. Comme aucun octet n'est
d'abord effacé puis redessiné, il n'y a ni scintillement ni double tampon.
La routine lit ses données avec `POP` (deux octets en 3 µs) et balaie l'écran
en aller-retour pour ne pas avoir à revenir en début de ligne.

**4. Ne pas redessiner ce qui n'a pas changé** — `enemy_draw`.
Un ennemi immobile dont l'image n'a pas changé coûte 0,2 ms au lieu de 1,2 ms.

**5. Le chemin vers Papi est calculé une fois pour tout le monde** —
`flow_update`.
Une inondation en largeur part de la case de Papi et note dans chaque case sa
distance. Elle est étalée sur plusieurs images (6 cases par image, 0,75 ms) et
se refait en boucle, à peu près une fois par seconde. Chaque ennemi se
contente de regarder ses quatre cases voisines et va vers la plus petite
valeur : il contourne les murs et trouve la porte tout seul, pour le prix de
quatre lectures.

**6. L'IA réfléchit trois fois par seconde, pas cinquante** — `enemy_think`.
Toutes les 16 images, à des moments décalés d'un ennemi à l'autre, un ennemi
choisit sa direction et décide s'il tire. Entre deux réflexions il ne fait
qu'avancer.

**7. Aucune comparaison ennemi contre ennemi** — `can_stand_e`,
`enemy_claim`, `enemy_free`.
Chaque ennemi réserve dans la grille les cases de 6×8 que son sprite touche.
Avant d'avancer il vérifie que les cases d'arrivée sont libres : même test,
même table que pour les murs. Deux ennemis ne se superposent jamais et le coût
ne dépend pas de leur nombre.

Et partout : aucune multiplication ni division (tables `COLTAB`, `MOD6`,
`SCR_LO/SCR_HI`, décalages), aucun appel au système pendant le jeu.

## Règles du décor

Elles viennent des pastilles de couleur de `TileSet1Obstacle.png`, lues par
`tools/convert.py` :

| Pastille | Effet |
|---|---|
| verte | case libre |
| rouge | bloque la marche et arrête les balles |
| bleue (barbelés) | bloque la marche, les balles passent |
| jaune | avant-plan : Papi et les ennemis passent **derrière** (sprite caché), mais balles et grenades passent devant |

La grenade passe par-dessus tout (portée +25 % depuis la v03). Si ces règles ne sont pas celles voulues,
c'est le dictionnaire `KIND` de `convert.py` qu'il faut changer.

## Reconstruire

```
build.bat            (Windows, rasm.exe dans le PATH ou dans le dossier)
./build.sh           (Linux / macOS)
```

`src/gfx.asm` est produit à partir des PNG et de la carte par
`python tools/convert.py` (Python 3 + Pillow). Il est fourni tout fait : RASM
seul suffit tant qu'on ne touche pas aux graphismes.

Réglages utiles en tête de `papicpc.asm` : `MAXENEMY`, `NEAR` (distance à
laquelle un ennemi s'arrête pour tirer), `TICK_STOP` (budget de temps),
`FF_CELLS` (vitesse de recalcul des chemins). La fréquence de tir des ennemis
est dans `enemy_think` (`and 7` en marche, `and 3` à l'arrêt).

## Ce qui a été vérifié, et ce qui ne l'a pas été

Vérifié, sur 51 parties automatiques de 700 à 2500 images :

- 50 boucles de jeu par seconde dans tous les cas du tableau ;
- aucun octet « fantôme » : hors des sprites, l'écran est identique au décor ;
- chaque sprite d'ennemi comparé octet par octet à ce qu'il doit être, y
  compris derrière les murs : zéro écart ;
- changement du nombre d'ennemis en cours de partie, partie perdue puis
  relancée ;
- démarrage par `RUN"PAPICPC"` depuis l'image disque (CPC 6128 émulé, AMSDOS).

Pas vérifié :

- **aucun essai sur une vraie machine**, ni dans WinAPE, Caprice ou CPCEC.
  Sur l'ensemble des essais, la pire image a pris 19,2 ms pour 19,97 : la
  marge est de moins d'une milliseconde, et un émulateur ou un CRTC dont le
  minutage diffère un peu pourrait la réduire. Si une image saute, baisser
  `TICK_STOP` à 4.
- le jeu n'a été joué que par un robot : l'équilibrage (fréquence de tir,
  vitesse des ennemis, vies) est à régler manette en main.

## Limites connues

- Papi se déplace horizontalement d'un octet (2 pixels MODE 0) toutes les deux
  images, comme le prévoyait le README de la V0.1. Un déplacement au pixel
  demanderait des sprites pré-décalés.
- Papi peut marcher sur un ennemi (il perd alors une vie) ; pendant ce
  recouvrement l'un des deux sprites peut être rogné un instant.
- Les sons sont des bruitages du AY ; TirSon et GrenadeSon sont des
  approximations calculées d'après l'analyse des WAV (un WAV 44,1 kHz ne se joue pas
  tel quel sur CPC) ; les autres WAV de l'archive ne sont
  pas utilisés.
- Une seule carte, sans défilement.

## Contenu

```
build/      PAPICPC.dsk, papicpc.sna, papicpc.sym (adresses des étiquettes)
src/        papicpc.asm (le jeu), gfx.asm (graphismes convertis)
assets/     les PNG et la carte Tiled utilisés
doc/        vidéo et capture
tools/      convert.py   PNG + carte -> gfx.asm
            cpcrun.c     émulateur CPC sans écran : profils, captures, robot
            prof.sh      temps par routine pour 2 à 12 ennemis
            ghost.py     test d'intégrité de l'affichage
            walk.py      scénarios de déplacement avec captures
```

`cpcrun.c` s'appuie sur les émulateurs de puces « chips » de floooh (licence
zlib, https://github.com/floooh/chips et chips-test pour les ROM) :

```
cc -O2 -I chips -I chips-test/examples/roms tools/cpcrun.c -o tools/cpcrun -lm
```

## Changements de la v03 (cahier des charges du 5 octobre 2026)

- HUD en haut de l'écran (lignes 0 à 7) ; la carte est décalée de 8 lignes.
- 12 ennemis au plus (`MAXENEMY`) ; touches 1 à 6 = 2, 4, 6, 8, 10, 12.
- Grenade : 30 images de vol au lieu de 24 (`G_FLIGHT`), portée mesurée de 16 à 20 octets.
- Début de carte : Papi apparaît en bas (y=180) et avance de 8 lignes (`player_enter`,
  état 3) ; pendant ce temps, pas de tir, pas de grenade, pas d'ennemis. Ensuite les
  ennemis arrivent par le haut et les côtés (pas dans le tiers du bas : `convert.py`).
- Animation des ennemis deux fois plus rapide.
- (v03b) Vitesse de marche des soldats réduite de 30 % : 8,8 octets/s en horizontal (12,5 avant), 17,6 lignes/s en vertical (25 avant), dans `dt_tab`. L'animation est liée aux pas ; elle est recalculée (3 x dt par pas, image tous les 8) pour garder le rythme de la v03.
- Décor jaune : cache Papi et les ennemis, mais plus les balles ni les grenades.
- Balle horizontale : testée dans la ligne de cases des pieds du tireur, donc plus
  arrêtée par un mur rouge qui longe le corps.
- Soldat : 1 point de vie, 10 points (`score+4`) ; tir inchangé.
- Sons : TirSon (tir de Papi) et GrenadeSon (lancer) refaits sur le AY d'après les WAV.

À vérifier à l'oreille et à la manette : les deux sons, l'équilibrage (12 ennemis),
et le rythme de l'animation des soldats. La pire image dure 19,1 ms pour 19,97.

## Changements de la v04 (puis v04b : diagonales -5 %)

- **Balles ennemies plus lentes (-40 %)** : elles avancent 154 images sur 256 (`EBUL_SPEED`)
  d'un pas moitié moins long (`enemy_shoot`). Mesuré : 46 -> 29 octets/s en horizontal,
  137 -> 85 lignes/s en vertical.
- **Son de tir des ennemis** : `TirSon` est joué à chaque tir d'un ennemi (`enemy_shoot`).
  À 12 ennemis cela fait environ 4 sons par seconde.
- **Hi-score** : affiché à côté du score, conservé d'une partie à l'autre (`hiscore`, hors de
  `vars`). Il est perdu à l'extinction ou au reset : le jeu ne fait aucun appel au système, donc
  aucune écriture sur disque.
- **Bandeau** : `SCORE 000000 HI 000000 VIES 3 EN 08-08` (39 glyphes, toute la largeur ;
  « ENNEMIS » abrégé en « EN » faute de place).
- **Diagonale des ennemis** : les deux axes avancent ensemble, à raison de 1 octet pour 4 lignes
  (`dt_diag`). Un pixel MODE 0 est environ deux fois plus large que haut : 1 octet pour 2 lignes
  donnait une pente de 17 à 27 degrés à l'écran, 1 pour 4 donne 45. Mesuré sur carte vide :
  4,1 lignes par octet, 46 degrés (17 avant). v04b : vitesse diagonale réduite de 5 % (`dt_diag`,
  118 -> 112 sur 256 par image).
- **Bug corrigé dans `can_stand_e`** (présent depuis la v02) : la macro `TESTROW` se terminait par
  `dec l`, qui écrase le drapeau Z. Un sprite à cheval sur deux colonnes de tuiles était donc
  toujours refusé aux lignes `y mod 8 = 5, 6, 7` : les ennemis restaient bloqués jusqu'à ce que
  leur x retombe sur une colonne, d'où la marche en escalier. Conséquence : ils avancent
  maintenant sans ces blocages, donc arrivent plus vite sur Papi à vitesse nominale égale.

## Overscan vertical (v05, à titre d'essai)

L'écran fait **32 rangées de 8 lignes = 256 lignes** (200 avant) : un bandeau de 7 rangées (56 lignes)
au-dessus du HUD et de la carte. Réglages CRTC dans `crtc_tab` : R6 = 32 rangées, R7 = 34 (position
verticale ; 35 monte l'image de 8 lignes), R12/R13 = `#2EE8` (écran de 32 Ko : page A `#8000`, page B `#C000`).

**Nouvelle carte mémoire** (le moteur garde un miroir du décor de la même taille que l'écran) :

| Adresses | Contenu |
|---|---|
| `#0000-#01FF` | pile (vers le bas depuis `#0200`) ; `#0038` : vecteur d'interruption |
| `#0200-#02BF` | fiches des 12 ennemis (en tête de fichier : alignées sur une page, sans trou) |
| `#02C0-#31B5` | code, graphismes, variables |
| `#3200-#3770` | tables (COLTAB, MOD6, OCCY, file d'inondation), 74 octets libres avant, 144 après |
| `#3800-#3FFF` | grille et champs de distances, table des adresses de lignes (y = 0..255) |
| `#4000-#7FFF` | miroir du décor : adresse miroir = adresse écran - `#8000` (`res 7,h`) |
| `#8000-#BFFF` | page vidéo A : le bandeau occupe les 560 derniers octets de chaque bloc de 2 Ko ; les 1488 premiers contiennent 10 images de sprites chacun |
| `#C000-#FFFF` | page vidéo B : HUD + carte, disposition inchangée |

Les 76 images de sprites sont en fin de fichier (`gfx_spr.asm`) et **recopiées au démarrage** dans les
trous de la page A (`start`), puis le bloc source est écrasé par les tables et le miroir. Le bandeau
est dessiné par `draw_banner` (lignes 200..255 de la table des lignes) : bandes de couleur
(`banner_fill`) et gros caractères doublés (`print_big`, textes `txt_t1` et `txt_t2`).

Pour un autre bandeau : modifier `banner_fill`, `txt_t1`/`txt_t2` ou remplacer `draw_banner`. Le bandeau
est à écrire dans la page A, aux adresses données par `scr_addr` pour y = 200 + ligne.

Points d'attention : la mémoire est comptée à l'octet près (74 octets libres avant `COLTAB`) ;
RASM divise en virgule flottante (voir `papi_frames`) ; `ghost.py` lit maintenant le miroir en
`adresse - #8000`.

## v06/v07 : l'officier C++ et le bandeau réduit

**Officier** (`OfficierC++_12x12.png`, 36 images comme le soldat) : 1 point de vie, même vitesse de marche
et mêmes balles que le soldat (il utilise exactement le même code), **20 points** (à régler dans
`enemy_killed`). Il lance une **grenade** vers Papi toutes les 8 à 13 s (10 à 15 s en v06 ; `officers_update`, `add a,100`) (`officers_update`,
`off_tmr`) : vol de 32 images en cloche, atterrissage à l'endroit où se trouvait Papi au lancer,
explosion de 16 images qui lui fait perdre une vie s'il est dans la zone (comme la grenade de Papi,
mais elle ne touche pas les autres ennemis). Une seule grenade ennemie à la fois.

**25 % d'officiers** (v07 ; 15 % en v06) : ce sont les derniers de la liste (`off_from`, `ofs_tab`) : 1, 1, 2, 2, 3, 3
officiers pour 2, 4, 6, 8, 10, 12 ennemis (50, 25, 33, 25, 30, 25 %). Un officier qui meurt réapparaît
officier.

**Mémoire** (c'est ce qui a coûté le plus cher) :
- le bleu de l'officier est le stylo 14 de la palette (c'était un doublon de noir, inutilisé) ;
- les images **identiques** de chaque feuille ne sont gardées qu'une fois (90 images uniques sur 112) ;
- elles ne tiennent dans les trous de la page `#8000` qu'avec **4 rangées de bandeau** (32 lignes au
  lieu de 56) : l'écran fait maintenant 29 rangées = 232 lignes (R6 = 29, R7 = 33, R12/R13 = `#2F60`) ;
- le code de démarrage (copie des sprites, CRTC, palette, tables, dessin du bandeau) est **en fin de
  fichier** et s'écrase lui-même ensuite (`boot`) ;
- la grille de collision est calculée d'après la carte (`tkind`, 36 octets) au lieu d'être stockée (416).

Il reste environ 298 octets libres avant `COLTAB` et 6 emplacements d'images dans la page `#8000` :
de quoi ajouter une petite unité de 6 images, pas une de plus.

## v08 : grenade des officiers plus lente et plus courte, renforts plus espacés

- **Grenade des officiers** : vol de **64 images** au lieu de 32 (`EG_FLIGHT`), donc deux fois plus lente :
  Papi a environ 1,3 s pour s'éloigner de la zone (9 octets / 18 lignes). La cloche (`arc_tab`) est
  lue une entrée sur deux.
- **Portée limitée à celle de la grenade de Papi** (`EG_RANGEX` = 20 octets, `EG_RANGEY` = 60 lignes,
  soit 30 images x 2 lignes) : si Papi est plus loin, la grenade retombe à cette distance, dans sa
  direction (`egrenade_throw`, `.clamp`). Mesuré : 20 octets / 59 lignes au plus, et moins de 2 lignes
  d'écart quand Papi est à portée.
- **Renforts** : un ennemi tué est remplacé 120 à 247 images plus tard (2,4 à 4,9 s), contre 40 à 103
  (0,8 à 2,1 s) avant (`enemy_dying`, `.gone`). Mesuré avec le robot : 1,6 s en moyenne avant, 3,6 s
  après. L'arrivée initiale des ennemis (toutes les 9 images) n'a pas changé.

## v09 : cahier des charges du 5 octobre (suite)

**Commandes** : les touches 1 à 6 (nombre d'ennemis) n'existent plus, le nombre d'unités vient des
paramètres de zone. Reste la touche M (jauge de charge dans la bordure).

**Paramètres de zone** (`map1_params`, constantes `MAP1_*` à copier pour chaque nouvelle zone) :
nombre d'unités simultanées (8), ennemis à abattre (25), et pour chaque type d'unité son pourcentage
(1 = soldat 75 %, 2 = officier 25 %). Le nombre d'officiers est calculé **à l'assemblage**
(`MAP1_NOFF` = 2, arrondi au plus proche) et occupe les dernières places. Seuls les types 1 et 2
existent : un troisième type demandera sa propre IA, ses sprites et une table « type par place ».
Le bandeau affiche `EN` et le nombre restant d'ennemis à abattre ; à zéro, la partie est gagnée
(message VICTOIRE ! provisoire, la suite — zone suivante — est à définir).

**Papi** : marche à 17,5 octets/s et 34,5 lignes/s (25 et 50 avant, `PSPEED_X/Y`) ; ses balles à
68 octets/s (100 avant, `PBUL_SPEED`) ; invincibilité après une mort de 138 images (120, +15 %).
Une vie de plus tous les 1000 points (3 chiffres de gauche du score, `check_life`), avec un petit
arpège montant (`sfx 8`), 9 vies au plus.

**Ennemis** : même vitesse dans les 8 directions, **mesurée en pixels** (un octet = 2 pixels, une ligne = 1 pixel) et
10 % sous l'ancienne vitesse horizontale et verticale de la v08 (17,6 pixels/s) : 16,0 en horizontal (8 octets/s), 15,8 en
vertical, 15,9 en diagonale (`dt_tab`, `dt_diag`). Mesuré sans obstacle : 16,7 / 16,7 / 16,4 (la mesure est arrondie au pas
près). La diagonale de la v08 allait à 22 pixels/s ; elle avance 1 octet pour 4 lignes ensemble (45 degrés à l'écran).
*(Une première version de la v09 avait aligné les vitesses « à l'écran » : le vertical montait de 50 %, l'horizontal baissait de 27 % — retiré.)*
Délai de réapparition 147 à 274 images (2,9 à
5,5 s ; +15 %), arrivée initiale toutes les 10 images, retry 14 (`E_TICK` sert d'octet fort).
Les balles ennemies sont visibles dès leur départ (`B_AGE` : elles étaient cachées par les cases
réservées de leur propre tireur, d'où un départ décalé) : 1,3 image cachée en moyenne contre 4,9.
Grenades ennemies : zone de dégâts d'un bloc de carte (6 octets, 8 lignes ; 9 et 18 avant).

**Fin de partie** : `GAME OVER !` (ou `VICTOIRE !`) en gros caractères au premier plan, par-dessus la
carte et les sprites (`end_game`). La scène est **figée** pendant ce message, sinon les sprites
effaceraient le texte ; tir pour recommencer.

**Bandeau** : `PAPI COMMANDO` en jaune puis `CPC` (C rouge, P vert, C bleu — stylo 15 = bleu vif),
l'espace du dessous est libre. **Correctifs de mise au point** : la chaîne du bandeau (`txt_hud`) doit faire exactement 39 glyphes (deux de trop débordaient sur la 1re rangée du terrain) ; une balle ennemie qui sort du corps de son tireur fait redessiner les ennemis qu'elle recouvrait (`wake_enemies`) ; `ghost.py` ignore la zone du message de fin d'écran. **Mémoire** : police à 5 lignes par glyphe (la 6e était vide), glyphe `!`
ajouté, balles sur 9 octets (`B_AGE`), calcul de la répartition à l'assemblage : **32 octets libres** avant `COLTAB`.

## v10 : bandeau réduit à 2 rangées

Les deux bandes sous le titre (et l'espace libre) sont retirées : le bandeau fait **2 rangées = 16 lignes**
(bandes rouge et jaune du haut, puis `PAPI COMMANDO CPC`). L'écran fait 27 rangées = 216 lignes
(R6 = 27, R7 = 32, R12/R13 = `#2FB0`, `BANNER` = `#8760`). Chaque trou de la page `#8000` fait alors
1888 octets, soit **13 images de sprites** (`SPRSLOT`) : 104 emplacements, dont **14 libres** (6 avant).
Mémoire du programme inchangée : 32 octets libres avant `COLTAB`.

**Diffusion** : version disquette uniquement (664 et 6128, ou émulateur) ; le jeu doit rester jouable sur
un CPC de 64 Ko. Pas de dépendance à la RAM supplémentaire du 6128.

## v11 : cadence de tir des ennemis, grenade de Papi sur la touche de tir

**Tir des ennemis** (`enemy_try_fire`) : au lieu d'un tir au hasard à chaque réflexion, chaque ennemi tire à
cadence fixe selon son type : soldat 240 images (4,8 s), officier 144 images (3 s ; mesuré 4,80 s et 2,98 s).
Le compte part de l'arrivée de l'ennemi (`FIRE_LAST`, une case par ennemi). Les seuils sont des multiples
de la réflexion (16 images) et restent sous 256 pour tenir sur 8 bits (`FIRE_SOLDIER`, `FIRE_OFFICER`).

**Grenade de Papi** : plus de touche Entrée ni de 2e bouton de joystick. Un appui long sur **tir**
(`GRENADE_HOLD` = 75 images = 1,5 s) lance la grenade ; ce même appui coupe le tir jusqu'au relâchement
(`p_hold`, `p_lock`). Pendant les 1,5 s d'appui, le tir automatique continue (environ 8 balles).

**Mémoire** : la table des balles (90 octets) et `FIRE_LAST` (12 octets) sont dans des trous libres de la
grille (`#39A0`, `#3BA0`) : 26 octets libres avant `COLTAB`.

## v12 : tir « une balle par appui » et grenade à 0,7 s

Papi tire **une balle à chaque appui** sur la touche de tir (plus de tir automatique : `p_cool` supprimé).
Un appui qui dure **35 images (0,7 s**, `GRENADE_HOLD` ; 1,5 s en v11) lance la grenade, et ce même appui
coupe le tir jusqu'au relâchement (`p_hold`, `p_lock`). Mesuré : 1 balle à l'appui, grenade à 0,70 s,
aucune balle après la grenade, 1 balle au nouvel appui, 1 balle et pas de grenade pour un appui court.
26 octets libres avant `COLTAB`. Le robot de test (`bot:1`) maintient souvent la touche : il tire donc
moins et lance des grenades, ce qui change un peu les parties simulées.

## v13 : séparation moteur / zone, cover, grenade à 0,5 s

**Le jeu est maintenant en deux parties.** Le *moteur* (code, police, sprites de Papi et des explosions) reste
résident. La *zone* (tuiles, carte, types de tuiles, points d'apparition, paramètres, tables d'images et sprites
des unités) est un fichier de **secteurs bruts** lu sur la disquette par le lecteur du jeu (`fdc_*`, `load_data`,
`load_zone_data` ; prototype validé séparément). Résultat : la partie permanente du moteur passe de `#31B6` à
`#2A86`, soit **1914 octets libres** avant `COLTAB` (26 avant), et la zone 1 n'occupe plus que la disquette.

**Démarrage** (`boot`) : `RUN"PAPICPC"` charge le fichier AMSDOS ; le code coupe les ROM, met la palette de la
cover, copie les sprites résidents, construit les tables, puis lit la **cover** (16 Ko, piste 10) directement dans
l'écran `#C000` : elle s'affiche pendant son chargement. La zone se charge ensuite (piste 14) pendant que la cover
reste à l'écran ; un appui sur **tir** (espace, copy ou bouton de joystick) lance la partie. À chaque nouvelle partie
(après GAME OVER ou VICTOIRE) la zone est relue (environ 1,5 s sur une vraie machine, moteur de lecteur compris).

**Disquette** : fichiers AMSDOS sur les pistes 0 à 9 ; cover pistes 10 à 13 ; zone 1 pistes 14 à 16 (`src/layout.inc`,
généré). `build.sh` enchaîne `tools/convert.py` (PNG/TMX -> `src/*.asm`, `*.inc`, `build/cover.bin`, `build/zone1.bin`),
RASM, puis `tools/mkdisk.py` (écrit cover et zone dans l'image DSK). **Il n'y a plus de .sna** (la mémoire d'un
snapshot ne représente pas une disquette) : les outils de test (`ghost.py`, `prof.sh`, `walk.py`) démarrent le DSK
(`RUN"PAPICPC"`, puis tir) et ne tournent que sur 6128 (le 464 n'a pas de lecteur).

**Zone de préparation** `#4800-#7100` : la zone est lue là (région du miroir, libre avant `init_screen`). `init_screen`
construit le miroir EN DERNIER, car il l'écrase. Les points d'apparition et les tables d'images sont recopiés dans des
trous libres des tables (`spawn_tab` `#34C0`, `soldat_frames` `#3770`, `officer_frames` `#37B8`). Les sprites des unités
vont dans les trous de la page `#8000`, à partir de l'emplacement 34 (0 à 29 Papi, 30 à 33 explosions).
**Le bloc de sprites résidents doit rester le dernier du fichier** (les tables l'écrasent après la copie), et le code de
démarrage doit finir avant `COLTAB` (`#3200`) : vérifier `SPR_PAPI` dans `build/papicpc.sym`.

**Assets mis à jour** : `TileSet1.png`, `TileSet1Obstacle.png`, `ZoneTest.tmx` (nouvelle carte, 38 tuiles). Dans la
feuille d'obstacles, la tuile 6 (os/crâne) a encore l'ancien dessin : seul son marqueur (vert = libre) est pris en
compte (`build_zone` ne lit que les couleurs de marquage). `GeneralC___12x12.png` est rangé dans `assets/` mais pas
encore utilisé. **Grenade de Papi** : appui long de 25 images = 0,5 s (`GRENADE_HOLD`).

**Test sous Caprice32** : ne pas séparer les commandes automatiques par des espaces (`-a "CAP32_DELAY CAP32_DELAY"`) :
les espaces sont tapés comme des touches Espace et valident l'écran de la cover. Passer un `-a` par commande.

## v14 : chargement compressé, plusieurs zones, types d'unités, Général C++

**Chargement plus rapide.** La cover et chaque zone sont compressées (format maison proche de LZ4, `lz_compress` dans
`tools/convert.py`, décompresseur `unpack` d'une centaine d'octets). Cover : 16384 -> 5279 octets (11 secteurs au lieu de 32) ;
zone 1 : 10712 -> 4228 octets (9 secteurs au lieu de 21). Deux fois et demie moins de secteurs à lire. La zone est lue
**sur place** : les données compressées sont posées à la fin de la zone de préparation, de façon que le décompresseur
n'écrase jamais ce qu'il n'a pas encore lu (décalage calculé et vérifié par l'outil, `inplace_offset`). Le moteur du lecteur
reste en marche entre la cover et la zone, et démarre dès la fin d'une partie (GAME OVER / VICTOIRE) : il a pris son régime
quand on rappuie sur tir, donc pas d'attente de lancement au redémarrage.

**Plusieurs zones.** `ZONES` (dans `tools/convert.py`) liste les zones ; `src/zones.inc` (généré) est leur répertoire :
piste, secteur, nombre de secteurs, adresse de lecture. Chaque zone a son tileset, sa carte, ses unités, ses paramètres.
Variable `zone_cur` ; après une **victoire**, tir charge la zone suivante (la dernière est suivie de la première) ; après un
GAME OVER, la même zone recommence. Pour l'instant une nouvelle zone repart de zéro (score et vies remis). La zone 2 est une
**zone d'essai** : même carte et même tileset que la zone 1, mais avec des soldats (75 %) et des généraux (25 %), 15 ennemis à abattre.
Pour tester une zone sans gagner : pendant la cover, mettre `zone_cur` à la valeur voulue avant d'appuyer sur tir.

**Types d'unités.** Le moteur ne connaît plus « soldat » et « officier » : chaque place d'ennemi a sa fiche, copiée de l'en-tête
du fichier de zone (`slot_type`, `slot_spd`, `slot_fire`, `slot_pts`, `slot_hp0`, `slot_gren`, `slot_hp`, en `#2E00-#2E53`).
Les caractéristiques d'un type se règlent dans `UNITS` (`tools/convert.py`) : cadence de tir, points de vie, points, vitesse
(tables normales ou rapides), lancer de grenades. Les tables d'images des 3 types sont en `#2F00`, `#2F48`, `#2F90`.

**Général C++** (`GeneralC___12x12.png`) : 2 points de vie, 50 points, tire toutes les 80 images (1,6 s : l'ennemi réfléchit toutes
les 16 images, 1,5 s n'est pas atteignable ; mesuré 1,58 s minimum), 15 % plus rapide (tables `dt_tab_fast` / `dt_diag_fast`).
Une balle lui retire un point de vie (bruit d'impact, il reste debout), la grenade de Papi le tue d'un coup. Son vert vif n'est
pas dans les 16 stylos du jeu : il est remplacé par le citron vert (`SUBST` dans `tools/convert.py`). Il occupe 28 images
uniques comme les autres unités : **deux types d'unités par zone** au plus (70 emplacements d'images libres).

**Mémoire** : les tables par zone vivent en `#2E00-#2FFF`, dans l'ancien bloc de sprites de démarrage (libre dès sa copie) ; les
« trous » entre les tampons de distances ne conviennent PAS (`init_screen` les remplit de 255). Les données (`type_ptr`,
`zone_dir`) ne doivent jamais être placées devant une routine dans laquelle le code précédent « tombe ».

## v15 : score conservé, grenades limitées + caisses, clignotement blanc, bandeau à 4 chiffres, ZONE CLEAR !

- **Score conservé** d'une zone à la suivante (`score_keep`, `carry`, restauration dans `init_game`). Les vies, les
  grenades et le nombre d'ennemis à abattre repartent à leur valeur de départ. Les milliers déjà franchis ne redonnent pas de vie.
- **Score et hi-score sur 4 chiffres** : 9990 au plus (`add_score` plafonne ; le dernier chiffre affiché est le zéro fixe).
  Bandeau : `SCORE 0000 HI 0000 VIES 3 GR 05 EN 25`.
- **Grenades** : `GREN_START` = 5 au départ d'une zone (à régler), `GREN_MAX` = 10 au plus, une de moins à chaque lancer,
  aucun lancer à zéro. Compteur `GR` dans le bandeau.
- **Caisses de grenades** : un officier tué laisse une caisse une fois sur deux (`enemy_kill_now`), une seule caisse à la fois ;
  Papi la ramasse en la touchant (+`CRATE_GREN` = 5, plafonné à 10). L'image de la caisse est un **visuel provisoire**
  (`assets/Caisse_12x12.png`, 12 x 12, magenta = transparent) : à remplacer par le tien. Elle est redessinée toutes les 16 images.
- **Clignotement blanc** : un ennemi à plus d'un point de vie touché par une balle sans mourir clignote en blanc pendant
  `FLASH_N` = 10 images (`make_white` : image blanche fabriquée à la volée à partir de l'image normale, sans emplacement de sprite en plus).
- **ZONE CLEAR !** remplace VICTOIRE !.
- **Mémoire** : le bloc de sprites résidents est maintenant AVANT le code de démarrage ; les tables par zone sont en `#3000-#31FF`
  (`slot_*`, `FIRE_LAST`, `spawn_tab`, tables d'images) ; la cover compressée est lue en `#5000`. La caisse est le 35e sprite résident :
  les unités de zone commencent à l'emplacement 35 (69 emplacements libres pour les unités).
- **Pas encore fait** : tir en couverture (ennemis et joueur), à préciser avec le propriétaire du projet.

**Combien d'unités différentes par zone ?** Le budget est de 104 emplacements d'images (13 par trou x 8 trous de la page `#8000`), dont
35 résidents (Papi 30, explosions 4, caisse 1) : il en reste **69** pour les unités. Soldat, officier et général ont chacun
28 images uniques : **deux types par zone** (56), avec 13 emplacements de reste. Un troisième type demande de tenir en
13 images (69 - 56) ou que chaque type en ait au plus 23.

## v16 : tir en couverture (ennemis et Papi)

Règle commune : **un tireur collé à un obstacle rouge peut tirer à travers lui** ; sinon, les obstacles rouges arrêtent les balles comme avant.
- **Balles** : un champ de plus, `B_PASS` (`BSIZE` = 10, table `bullets` en `#2F00`). Tant qu'une balle est dans un mur rouge et que sa fenêtre
  est ouverte (`B_PASS` > 0), elle n'est pas arrêtée ; dans le mur la fenêtre reste ouverte (un obstacle épais est traversé en entier),
  hors du mur elle se referme en quelques pas (`.cp1` dans `bullets_update`).
- **Papi** (`bullet_cover`, appelée par `player_fire`) : si la case voisine de son corps, dans la direction du tir (`adj_tab`), est un mur rouge,
  c'est-à-dire s'il est collé à l'obstacle, sa balle le traverse. À 2 lignes de distance : balle arrêtée (mesuré : collé -> la balle passe de y = 164 à 134,
  à 2 ou 6 lignes -> arrêtée aussitôt).
- **Ennemis** : 25 % des unités (hors lanceurs de grenades) ont le bit 1 de leur fiche `slot_gren` (réparties par `tools/convert.py`, paramètre `cover` de la zone ;
  zone 1 : places 1 et 4). À sa réflexion (`enemy_think`), un tel ennemi se met **en couverture** s'il est collé à un obstacle rouge (case juste sous ses pieds)
  ET debout sur une case verte uniquement (ni jaune, ni bleue), ET si Papi est au moins 16 lignes plus bas que lui : il s'arrête, se tourne vers Papi et
  tire (cadence de son type) ; sa balle traverse son obstacle (`cov_now`). Dès que Papi arrive à moins de 16 lignes, il reprend sa marche ; il se remet en
  couverture s'il est de nouveau collé à un obstacle valable quand Papi est de nouveau 16 lignes plus bas. Mesuré : l'ennemi reste posté, sa balle traverse
  le mur de 16 lignes ; il quitte son poste dès l'image suivante quand Papi est à son niveau.
- **Attention mémoire** : la partie permanente du moteur ne doit pas dépasser `#2F00` (début de la table des balles) ; marge actuelle : voir `VARS_END` dans `build/papicpc.sym`.

**Redessin à la disparition de Papi** : `player_hide` (mort de Papi, ZONE CLEAR) fait redessiner les ennemis que l'effacement de Papi recouvre, et la fin de partie
laisse les ennemis se mettre à jour 4 images avant de figer la scène (`fz_n`) : sans cela, un soldat collé à Papi pouvait garder des octets effacés sur l'écran figé.
Mesuré après correction : 18 cas sur 18 sans octet faux, en mode par défaut comme en `-seq`.

## v17 : les ennemis à couvert cherchent un poste proche

Un ennemi à couvert (bit 1 de `slot_gren`) qui n'est pas encore posté, avec Papi au moins 16 lignes plus bas, cherche un poste dans un petit rayon autour de
ses pieds (`cover_seek`, table `seek_tab`) : 3 rangées vers le bas et 2 colonnes de chaque côté ; poste = case verte uniquement avec un mur rouge juste dessous.
Il s'en approche (droite, gauche ou bas, et tire en marchant) puis se pose dès qu'il est collé à l'obstacle. Une réflexion sur 4 laisse la main au champ de
distances normal, pour ne jamais rester bloqué devant un poste inatteignable. L'adjacence se mesure comme le moteur : la case des pieds est celle de la ligne y + 10,
et l'ennemi est « collé » à 2 lignes au plus du bas de cette case (`(y + 10) and 7 >= 6`).
Mesuré : Papi immobile en bas, 3000 images de jeu libre : 0 image en couverture en v16, 242 en v17. Depuis un départ à 2 rangées au-dessus d'un poste, l'ennemi s'y
rend (`x = 12, y = 149`) et s'y pose. Limites : il ne cherche pas au-delà de 3 rangées ; il ne vérifie pas que le chemin vers le poste est libre.
Marge mémoire : la partie permanente finit à `#2EA6`, le début de la table des balles est `#2F00` (90 octets de marge).

## v18 : caisses parachutées, tuiles 8x8 dans le bandeau, PV officiers/généraux, officiers à couvert

- **Caisses de grenades parachutées** (`crate_update`) : quand Papi a **moins de 2 grenades** et qu'aucune caisse n'est en jeu,
  une caisse tombe du ciel `CRATE_DELAY` = 100 images (2 s) plus tard, avec le **bruit de grenade** (son 7). Elle part du haut
  de la carte et descend de 37 lignes/s vers une **case d'arrivée tirée au hasard** : une case de la grille dont la case et celle
  du dessous sont « vertes » (`(case OR case dessous) AND #C3 = 0` : ni bleu, ni rouge, ni jaune, ni ennemi), colonnes 0..12,
  rangées 2..21. Le tirage se fait une fois par image jusqu'à réussite. Au sol, Papi la ramasse en la touchant (+5 grenades,
  plafond 10) ; les officiers n'en laissent plus. Une seule caisse à la fois. Sprite : `assets/CaisseGrenade_12x12.png`.
- **Caisses détruites par les explosions** (`crate_blast`) : la grenade de Papi **et** celle des officiers détruisent une caisse
  posée à moins de 9 octets / 18 lignes du centre de l'explosion (comme pour les ennemis). Si Papi a toujours moins de 2 grenades,
  une autre caisse est commandée (délai de 2 s). Une caisse encore en l'air n'est pas touchée.
- **Tuiles 8x8 dans le bandeau** : `GR` devient la tuile `GrenadeChar8x8.png` et `EN` la tuile `MissionKillChar8x8.png`
  (mission « tuer des ennemis »). Elles se gèrent comme du texte : dans `txt_hud`, le caractère `^` désigne la tuile grenade et
  `$` la tuile mission ; `print_text` les reconnaît, les dessine sur 4 octets x 8 lignes (`put_tile`, ligne 192 : une ligne au-dessus
  du texte) et avance de 4 octets. Les données sont dans `glyph_tiles` (généré par `convert.py`, 32 octets par tuile, l'ordre
  des tuiles = `^`, `$`). Pour un futur type de mission : ajouter la tuile dans `convert.py` et un caractère dans `print_text`
  (ex. `&`).
- **Police compactée** : les caractères 3x5 sont stockés sur 15 bits (2 octets au lieu de 10) et dépaquetés par `expand_glyph`
  au moment de l'affichage (`put_glyph`, `big_glyph`) : environ 280 octets de mémoire permanente gagnés.
- **Points de vie** : officier **2**, général **3** (la grenade tue toujours d'un coup) ; le clignotement blanc s'applique à chaque
  impact qui ne tue pas. Fiche dans `UNITS` (`tools/convert.py`).
- **Officiers à couvert** : les officiers peuvent désormais faire partie des 25 % d'unités qui tirent en couverture (en zone 1 :
  l'officier de la place 6). Ils lancent leurs grenades depuis leur poste.
- **Mémoire** : la table des balles passe de `#2F00` à `#3080` (puis `#308C` en v19) ; `spawn_tab` est en `#306C` : la partie
  permanente peut maintenant aller jusqu'à `#3000` (`assert vars_end<=#3000`). `vars_end` = `#2EC6` : 314 octets libres.
- Vérifications : `ghost.py` (18 cas) et `ghost.py -seq` sans aucun octet fantôme ; 50,1 boucles/s à 8 et 12 ennemis, pire image 18,9 ms.
  Scénarios (`tools/scen.py`) : parachutage, ramassage, destruction par grenade de Papi et d'officier, nouvelle caisse après destruction.

## v19 : nouvelles images, points d'apparition par zone

- Nouvelles images : `CaisseGrenade_12x12.png` et `GrenadeChar8x8.png` (tuile de la grenade du bandeau).
- **Correction de l'apparition des ennemis** : en v18 la table des points d'apparition avait été placée en `#3DC0`, dans la région que
  `init_screen` remplit de `#FF` (champs de distances) : elle était écrasée à chaque lancement de zone, d'où des ennemis qui
  sortaient tous du même endroit. Elle est désormais en `#306C` (16 points, 32 octets) et la table des balles en `#308C`.
- **Propriété de zone `spawn`** (`tools/convert.py`, `ZONES`) : liste de `(colonne de tuile, y)`, 16 points au plus ; la conversion
  vérifie que la case des pieds (`y + 10`) est verte (type 0). L'en-tête de zone contient leur nombre (octet 4) ; le moteur
  (`enemy_absent`) les parcourt **tour à tour** (`spawn_ix`), de sorte que les ennemis arrivent de tous les points (plus de tirage au
  hasard). Zone d'essai (`SPAWN_TEST`) : haut au milieu (colonnes 6 et 7, y = 0), haut des côtés à 3 rangées du bord (colonnes 0 et 12,
  y = 20), bas des côtés au-dessus de Papi (colonnes 0 et 12, y = 108). Un point trop près de Papi (14 octets / 40 lignes) est sauté.
- Vérifications : `ghost.py` 18 cas sans octet fantôme ; 50,1 boucles/s, pire image 19,3 ms ; observation des 8 premières
  apparitions : tous les points servent.

## v20 : son de la grenade récupérée, caisse au premier plan

- **Son** : `assets/GrenadeRecuperee.wav` (analysé : 3 rafales de bruit blanc de 80 ms, chacune s'éteignant en 4 images, 0,2 s en tout).
  Reproduit sur le AY (`sfx 9`, canal B en bruit, période de bruit 6, volumes `pick_vol` : 15,13,10,6 répétés) et joué **quand Papi
  ramasse la caisse** (il remplace l'arpège « vie en plus », qui reste utilisé pour les vies gagnées). Le bruit de grenade (lancer)
  accompagne toujours le parachutage.
- **Priorité haute de la caisse** (`crate_draw`) : elle est dessinée **en dernier** dans l'image, après Papi, les ennemis et les
  balles, et **sans respecter les murs « devant »** (jaunes) : elle passe donc par-dessus tout. En descente elle est redessinée à
  chaque image (on ne remet que la ligne quittée) ; posée, toutes les 16 images. Pour garder 50 images/s, les ennemis arrêtent leur
  tour un top plus tôt pendant la descente (`tick_lim`). Vérifié octet par octet (33 instants de la chute, dont le passage devant le
  mur blanc) : aucun octet de la caisse n'est faux ; `ghost.py` (18 cas, et `-seq`) sans fantôme ; 50,1 boucles/s, pire image 19,7 ms.

## v21 : écran « ZONE CLEAR ! » noir avec jingle

- Quand le quota est atteint (`victory`) : la **carte est effacée** (`clear_map`, 192 lignes ; le bandeau et le HUD restent, le score
  reste lisible), **fond noir**, `ZONE CLEAR !` en jaune au centre et le **jingle** (`assets/ZoneClear.wav`). Plus aucun ennemi ni sprite
  n'est redessiné sur l'écran noir (`freeze_redraw` n'est plus appelé que pour GAME OVER). Tir pour passer à la zone suivante.
- **Jingle** (`sfx 10`, canal A, 64 images de 20 ms) : reproduit d'après l'analyse du WAV (1,28 s) : une introduction (270 Hz qui
  descend à 185 Hz), puis 4 glissandos montants de 185 Hz à ~1 kHz, d'amplitude 15, 14, 13, 11 puis silence. Les hauteurs sont dans
  `zc_per` (généré par `zclear_table()` dans `tools/convert.py`, période / 2) ; mesuré en rejouant la sortie sonore de l'émulateur :
  fréquences et durée conformes au WAV.
- **Mémoire** : les variables de la partie (`vars` .. `vars_end`, 198 octets) ne sont plus dans le fichier : elles sont en mémoire
  basse `#0040-#0106` (la pile, sous `#0200`, ne descend pas sous `#01E0`, mesuré). Ce sont des `equ` (`VARBASE`) ; comme RASM
  n'écrit pas les `equ` dans le fichier de symboles, `tools/symvars.py` les y ajoute (appelé par `build.sh` / `build.bat`). On gagne
  ~200 octets ; la dessin de grenade (Papi / officier) est factorisé (`draw_gren`) et `player_hide` utilise `wake_12`.
  Partie permanente : fin `#2F06` (limite `#3000`, `assert`), soit environ 250 octets libres.
- `build.bat` mis à jour (conversion, symboles, disquette ; plus de .sna).
- Vérifications : `ghost.py` 18 cas et `-seq` sans fantôme, 50,1 boucles/s, pire image 19,7 ms ; passage à la zone suivante depuis
  l'écran noir testé.

## v22 : menu principal, écrans de zone, réapparition sur place

- **Écran « ZONE CLEAR ! » entièrement noir** : `blackout` efface tout l'écran visible (bandeau, HUD et carte, 216 lignes). Le bandeau
  est redessiné au début de chaque zone (`draw_banner`, désormais dans la partie permanente), le HUD par `init_game`.
- **Papi réapparaît là où il est mort** (même position et même direction), avec les 138 images d'invincibilité pour s'enfuir.
- **Enchaînement** : cover (10 s, sans attendre le tir) → **menu principal** → écran noir « nom de la zone / type de mission » →
  jeu → (Zone Clear → écran noir de la zone suivante) … ; **Game Over → retour au menu** (nouvelle partie à la zone 1, score à zéro).
- **Menu principal = overlay chargé depuis la disquette** (`src/menu.asm`, assemblé en `#5000`, écrit par RASM dans `build/menu.bin`,
  posé par `mkdisk.py` sur la piste 15 ; `menu_enter` le lit à chaque retour au menu, puis `call MENU_LOAD`). Il ne prend donc rien dans
  la partie permanente. Déroulement : le titre (`assets/Titre.png`, converti par `tools/convert.py` en `src/menu_gfx.asm`, palette du
  jeu) **monte du bas de l'écran** (4 lignes par image) ; **32 explosions** (les images d'explosion du jeu, agrandies 2 fois, bruit
  d'explosion `sfx 6`) tout autour et sur le titre ; puis **« START GAME ! » jaune clignotant** au milieu et, tout en bas, le
  **bandeau défilant de 8 x 8 pixels** (police 8 x 8 de la ROM du CPC copiée au lancement, défilement d'un octet = 2 pixels toutes les
  2 images) avec le texte demandé, en boucle. Tir : la partie commence.
- **Écran de zone** : `zone_intro` charge la zone sur l'écran noir puis affiche en gros caractères le **nom** (jaune) et le **type de
  mission** (blanc) lus dans l'en-tête de la zone (`Z_TEXT`, 32 octets ; texte et centrage générés par `convert.py` : propriété
  `title` de chaque zone dans `ZONES`, mission « KILL n ENEMIES. » avec n = quota de la zone), pendant 3 s. J'ai écrit **ENEMIES**
  (orthographe anglaise) ; le point final est ajouté à la police (`.`).
- Les scripts de test (`ghost.py`, `scen.py`, `walk.py`, `prof.sh`) attendent maintenant la cover (1000 images), appuient sur tir au
  menu, puis laissent passer l'écran de zone (260 images).
- **Mémoire** : partie permanente jusqu'à `#2FCC` (limite `#3000`) : **52 octets libres seulement** ; le prochain gros ajout devra
  aller dans un overlay. Vérifications : `ghost.py` 18 cas et `-seq` sans fantôme, 50,1 boucles/s, pire image 18,95 ms ; Zone Clear
  noir, passage à la zone 2, Game Over → menu, réapparition sur place testés dans l'émulateur.

## v23 : projectiles ennemis -15 %, poursuite dans le menu

- **Projectiles ennemis 15 % plus lents** : balles `EBUL_SPEED` 154 -> 131 (/256 par image) ; grenades des officiers : elles n'avancent
  plus que 218 images sur 256 (`eg_acc`), la portée et la trajectoire restent identiques. Réglages à ajuster aux tests.
- **Menu : poursuite au-dessus du titre** (`chase_step`, `draw_act` dans `src/menu.asm`) : pendant « START GAME ! », Papi (12 x 12)
  poursuit 2 ou 3 ennemis ou est poursuivi par eux, d'un bout à l'autre de l'écran, dans un sens puis dans l'autre, pour chaque type
  d'unité : soldat, officier, général (6 scènes, table `scenes`, boucle). Les sprites (Papi + 3 unités, droite/gauche, 4 images de pas)
  sont convertis par `convert.py` dans `menu_spr` (données seules, 72 octets) ; ils sont posés sur le noir avec une colonne noire de
  chaque côté (pas d'effacement). Une image sur deux : la poursuite avance d'un octet ; l'autre : le texte défile.
  L'overlay passe à 13 secteurs (`MENU_N`), police / tables / variables en `#6C00`-`#7100`.
- Les contours noirs des sprites se confondent avec le fond noir du menu (ex. le képi de l'officier).
- Mémoire permanente : 43 octets libres (fin `#2FD5`). Tests : `ghost.py` 18 cas sans fantôme, 50,1 boucles/s.

## v24 : système de missions (zone 1 « OUTPOST C-01 », 10 missions)

- **Dix missions = dix fichiers de zone** (`zone01`..`zone10`, `ZONES` dans `convert.py`, fonction `_m(n, unités, mix, kills, count, time)`).
  Même carte, même nom de zone ; changent le nombre maxi d'unités à l'écran, le mélange de types et l'objectif :
  | n | objectif | unités | mélange |
  |---|----------|--------|---------|
  | 1 | tuer 15 soldats | 5 | 100 % soldats |
  | 2 | tuer 25 soldats | 6 | 90 % S / 10 % O |
  | 3 | **Time Attack** survivre 30 s | 6 | 80 % S / 20 % O |
  | 4 | tuer 10 officiers | 6 | 60 % S / 40 % O |
  | 5 | tuer 35 ennemis | 7 | 75 % S / 25 % O |
  | 6 | **Time Attack** survivre 45 s | 7 | 75 % S / 25 % O |
  | 7 | tuer 20 officiers | 7 | 60 % S / 40 % O |
  | 8 | tuer 5 généraux | 8 | 75 % S / 25 % G |
  | 9 | **Time Attack** survivre 50 s | 6 | 50 % O / 50 % G |
  | 10 | tuer 50 ennemis | 8 | 60 % O / 40 % G |
  (Ton énoncé avait deux fois « Mission 03 » : j'ai pris la seconde pour la mission 06.)
- Les types sont attribués par place, **arrondis** : ex. mission 2 = 5 soldats + 1 officier, mission 4 = 4 + 2, mission 8 = 6 + 2
  généraux, mission 10 = 5 officiers + 3 généraux. Les places « du type visé » comptent pour le quota (bit 2 de `slot_gren`) :
  tuer un soldat à la mission « 10 officiers » ne fait pas avancer le compteur (les points sont quand même gagnés).
- **Time Attack** : octet 5 de l'en-tête de zone (`mtime`). `kills_left` contient alors les **secondes** ; `time_tick` les décompte
  (50 images = 1 s, seulement tant que Papi est vivant) et la victoire arrive à 0. Les kills ne changent pas le compteur. Dans le HUD,
  la tuile **horloge** (`MissionTimeChar8x8.png`, caractère `&`) remplace la tuile « kill ».
- **Une vie de plus tous les 500 points** (`check_life`, sur les chiffres du score ; son de vie), maximum 9 vies.
- **Écran de mission** (overlay `intro.asm`, piste 27, chargé en `#4000` : nom de zone jaune, « MISSION 0n » blanc, objectif) ; après la
  mission 10 : écran noir **« CONGRATULATIONS !! / YOU CLEARED THE / FIRST C++ ZONE ! »** avec le jingle Zone Clear, puis retour au menu
  (nouvelle partie à la mission 1). Game Over -> menu comme avant.
- **Mémoire** : partie permanente quasi pleine (~12 octets libres) ; le texte d'intro et le bandeau ont été déplacés dans l'overlay.
- Tests : enchaînement des 10 missions (kills_left forcé à 0), horloge 30/45/50 s, vie à 500 points, congratulations + retour menu,
  `ghost.py` 18 cas sans fantôme, 50,1 boucles/s, pire image 18,9 ms.

## v25 : musique du menu et bandeau défilant dans la police du jeu

- **Musique du menu** : `assets/MusiqueMenu_AY.vgm` (traduction AY de la version SMS, 2016 images à 50 Hz = 40,3 s, boucle) est jouée
  **après la montée du titre et les explosions**, quand « START GAME ! » se met à clignoter. Elle s'arrête quand on appuie sur tir
  (`mu_stop` coupe le AY, le jeu reprend `sound_update`).
- **Format** (`tools/mkmusic.py` -> `src/menu_music.asm`, appelé par `convert.py`) : état des registres R0..R12 à chaque image, codé en
  flux « delta » (masque de 2 octets + valeurs des registres modifiés ; la 1re image les écrit tous), 7589 octets, puis compressé en
  **1755 octets** par un LZ maison (fenêtre 2 Ko). Le lecteur Z80 (`mu_get`, `mu_update`, ~330 octets dans l'overlay du menu)
  décompresse à la volée dans un anneau de 2 Ko en `#4800` (variables en `#4700`, zone libre pendant le menu), une image par `vsync`.
  Le bit 6 du mélangeur est forcé à 0 (lecture du clavier par le port A).
- **Vérifié** dans l'émulateur : les registres du AY sont identiques, image par image, à ceux du VGM (2400 images, dont le passage
  de boucle) ; aucune image perdue (50 boucles/s dans le menu).
- **Bandeau défilant** : même police 3×5 que le bandeau de jeu (`FONT` de `convert.py`, même stylo 13), 4 pixels par lettre.
  Lettres absentes du bandeau de jeu, ajoutées pour le menu seulement : `B`, `J`, `,`, `&` et `©` (en 2 caractères `@[` dans le texte).
  Majuscules uniquement : le texte est écrit en minuscules dans `txt_scroll`, lu en majuscules.
  Texte : « Papi Commando CPC !! A game by Studio Vetea - GFX, SFX, Design by Vetea - Music by Jon Something - Code by Vetea & Claude IA - © 2026 Studio Vetea ».
- **Mémoire du menu** : l'overlay passe de 11 à 17 secteurs (`MENU_N 17`, 16,4 Ko max : piste 25-26) ; la copie de la police de la ROM disparaît ;
  tables d'agrandissement en `#7800`, variables en `#7A00`.
- `cpcrun` : nouvelle commande `ay` (affiche les registres du AY).

## v26 : ZONE CLEAR automatique, ennemis dans l'écran de mission, cœur des vies

- **ZONE CLEAR !** passe seul à la mission suivante au bout de **3 s** (150 images ; `end_game` reçoit la durée dans D). GAME OVER attend toujours le tir (1,2 s de verrou).
- **Écran de mission** : les ennemis de l'objectif arrivent de la gauche, en file, et s'arrêtent ensemble au milieu, sous le texte
  (`units_step` / `sp_draw` dans `intro.asm`, 1 octet par image, 4 images de marche, 2,4 s en tout).
  « Tuer un type » -> 3 unités de ce type (soldat / officier / général) ; « tuer des ennemis » et Time Attack -> un de chaque type
  du mélange de la zone (calculé par `convert.py`, table `intro_units`). Le nom de la zone n'est plus répété dix fois (`intro_title0`).
  L'overlay (`INTRO_N 4`) est plein : 2 Ko = `#4000-#47FF`.
- **Cœur rouge** à la place de « VIES » dans le bandeau (tuile 8x8 : code 4 de `print_text`). Les quatre tuiles 8x8 du bandeau
  (grenade 1, tuer 2, Time Attack 3, cœur 4) ne sont plus dans la partie permanente mais dans un emplacement de sprite libre de la page A
  (`TILE_BASE`, emplacement 35 ; les sprites de zone commencent à 36) : -96 octets permanents. Les lettres `X` et `%`
  (jamais utilisées par le jeu) sont retirées de la police du jeu.
- **Correction** : le meilleur score (`HI`) n'était jamais mis à jour (`check_hi` n'était plus appelée) ; il l'est maintenant à la fin
  d'une zone et au game over.
- Tests : 18 cas `ghost.py` sans fantôme, 50,1 boucles/s, enchaînement ZONE CLEAR -> mission 03/04 (captures).

## v27 : images de toute taille dans l'écran de mission (boss, bâtiments en tuiles)

- L'écran de mission affiche maintenant une **liste d'images** par mission (`intro_items` dans `convert.py`, `items_step` / `sp_draw` dans `intro.asm`).
  Les ennemis de l'objectif en font partie (mêmes règles qu'en v26) ; on peut en ajouter avec l'argument `art=[...]` de `_m(...)` :
  - `dict(png='Boss.png', fw=36, fh=36, frames=4, x=30, y=110, walk=True)` : image PNG de **n'importe quelle taille** (largeur paire,
    80 pixels maxi), 1, 2 ou 4 images de marche/animation côte à côte, couleurs = les 16 stylos du jeu (comme les sprites) ;
  - `dict(tiles=[[8, 9, 10], [12, 13, 14]], x=4, y=110)` : **bloc de tuiles** du décor (12 x 8 pixels, numéros du TileSet de la zone) ;
  - `x` en octets (défaut : centré), `y` en lignes (défaut : sous le texte), `walk=True` : arrive de la gauche et s'arrête avec les ennemis
    (tout ce qui marche arrive en même temps) ; `show_units=False` retire les ennemis automatiques.
- Les images **fixes sont redessinées à chaque image et passent devant** ceux qui marchent (un boss peut passer derrière un bâtiment).
  Transparence : le pixel noir/transparent écrase le fond (écran noir), donc pas de chevauchement entre deux images qui marchent.
- **Mémoire** : seul le bandeau (`draw_banner` et ses données) doit rester dans `#4000-#47FF` (assert) ; le reste de l'overlay peut
  dépasser, il est recopié depuis la disquette à chaque mission et écrasé ensuite par la zone. `INTRO_N` est calculé automatiquement
  (6 secteurs aujourd'hui) : chaque image ajoutée allonge un peu le chargement entre deux missions (~0,05 s par 512 octets).
- Testé avec un boss de 36 x 36 pixels (4 images) qui traverse l'écran et deux bâtiments de 3 x 2 et 2 x 2 tuiles (puis retiré : le jeu
  livré n'a pas de nouvelle image, il attend tes assets).

## v28 : jingle de départ de niveau dans l'écran de mission

- `assets/MusiqueNiveau_AY.vgm` (3,9 s, 195 images) joue pendant l'écran de mission, pendant que les ennemis arrivent ; l'écran dure
  maintenant la durée du jingle (`JN_FRAMES + 4` images). Flux « delta » **non compressé** (906 octets, `tools/mkmusic.py build_raw` ->
  `src/jingle_level.asm`), lu par `jn_update` (~60 octets, dans l'overlay des missions). Le jingle a tout le AY (le bruitage `sound_update`
  n'est pas appelé pendant l'écran) ; `jn_stop` coupe le son en sortant.
- Vérifié : les 13 registres du AY sont identiques au VGM pour les 195 images, puis silence ; la partie démarre ensuite normalement.
- Overlay des missions : 8 secteurs (`INTRO_N` automatique), seul le bandeau reste dans `#4000-#47FF`.
- Le compteur interne d'animation de l'écran est plafonné à 100 (sinon `x = t - retard` devenait négatif après 127 images).

## v29 : jingle de game over, retour automatique au menu, explosions du titre plus courtes

- **Game over** : 0,4 s après l'affichage de « GAME OVER ! », le jeu lit l'overlay `gameover.asm` (piste 28, `GO_N` secteurs, chargé en `#4000`
  sur la copie du décor : la scène est figée) qui joue `assets/MusiqueGameOver_AY.vgm` (5,8 s, 290 images, flux delta non compressé de
  1200 octets, même lecteur que le jingle de niveau avec un compteur 16 bits), puis le jeu **repart tout seul sur le menu principal**
  (le tir n'est plus attendu). Vérifié : les 290 images de registres AY sont identiques au VGM, puis le menu démarre.
- **Menu** : 18 explosions du titre au lieu de 32, une toutes les 3 images au lieu de 4 (~1,1 s au lieu de ~2,7 s).
- Disque : intro piste 27, game over piste 28.
- `tools/prof.sh` : le script attend maintenant 420 images (au lieu de 260) avant de forcer le nombre d'ennemis, car l'écran de mission dure plus longtemps depuis le jingle ; sans ça le profil mesurait une autre situation (9-10 ms au lieu de 5-6 ms de moyenne, sans que le jeu ait changé).

## v30 : écran de chargement (cover) deux fois plus court

- La cover du début (première image « Papi Commando » avant le menu) reste à l'écran **5 s au lieu de 10 s** (`ld bc,50*5` dans `boot`).
- (Une première lecture de la demande avait raccourci l'écran de mission et accéléré le jingle : annulé, l'écran de mission et son jingle sont ceux de la v29.)

## v31 : zone 1 « OUTPOST C-01 » en 5 missions et boss Caporal Garatonku

**Missions** (cahier des charges de la zone 1, `ZONES` dans `tools/convert.py`) : 1 tuer 15 soldats (5 unités), 2 survivre 30 s (5), 3 tuer 25 soldats (6), 4 survivre 50 s (7),
5 tuer le boss (6 unités : le boss, qui compte pour une unité de type soldat mais occupe 2 places d'ennemi, + 4 soldats ; v31e : un garde de moins). Les zones 6 à 10 de test disparaissent.

**Boss Caporal Garatonku** (`src/boss.asm`, planche `assets/BossCaporal_12x24.png`, 48 x 216 : 8 directions x 4 images, la dernière rangée n'est pas utilisée dans le jeu)
- Sprite 12 x 24 = **deux places d'ennemi** empilées : le *corps* (place 0, 12 lignes du bas) pense, marche et esquive comme un soldat (mêmes routines, même
  vitesse, même champ de distances, même tir à couvert) ; la *tête* (place 1) recopie sa direction, son pas, son clignotement, réserve ses cases dans la grille
  et se redessine comme n'importe quel ennemi. Le corps n'apparaît qu'à 12 lignes ou plus du haut (`ymin` dans `can_stand_e`), pour que la tête tienne au-dessus.
- **25 points de vie** = le compteur de la mission (`kills_left`) : une balle de Papi en retire 1, une grenade 3 (`BK_GDMG`) ; corps et tête sont dans le même
  souffle mais ne comptent qu'une fois (`b_gi`). Touché : le sprite clignote en blanc (10 images, comme les autres) avec le bruit d'impact.
- **Rafale de 3 balles** toutes les 2 s (`BK_BURST` = 100 images depuis la fin de la rafale ; une balle toutes les 5 images, `BK_SPACE`), même vitesse de balle que le soldat ;
  **grenade** (celle des officiers : vol de 64 images, même portée) toutes les 2 s (`BK_GREN`), avec le son de grenade. Il ne tire que quand Papi est en jeu.
- **Son « Tir Boss »** : `assets/TirBoss.wav` = 0,28 s de bruit blanc à enveloppe plate (rafale de 3 coups) ; rendu sur le canal A (bruit, période 6), volumes mesurés image par
  image (`boss_vol`, 14 images), joué une fois par rafale (`sfx 11`).
- **Barre de vie** : l'icône de mission est `MissionKillBossChar8x8.png` (chargée avec la zone : fiche de 32 octets en tête de fichier, copiée sur la tuile « tuer »),
  suivie des points de vie en **vert** (100-75 %), **jaune** (75-50 %), **orange** (50-25 %), **rouge** (< 25 %) : seuils 19 / 13 / 7 pour 25 PV (en-tête de zone, octets 8 à 10).
  Les glyphes de la police s'écrivent avec des octets immédiats (`expand_glyph`) que `hud_kills` modifie le temps d'un nombre.
- **Mort** : `victory` détecte le boss (`bk_on` = seuil non nul) et passe à `bk_final` : 64 images (1,3 s) d'explosions sur la tête et le corps (la scène est figée), 250 points,
  puis directement l'écran de fin (sans passer par ZONE CLEAR).
- Mémoire : 2 images de plus par direction et par moitié = 73 images d'unités pour cette mission ; 68 tiennent dans les trous de la page A, les 5 autres dans 7 emplacements
  de 144 octets réservés dans la partie permanente (`XSLOT_BASE` = `#2C10`, `NXS` = 7), chargés avec la zone. Pour libérer la place (environ 2,1 Ko), les routines de composition
  `comp_c/l/r` et `comp_safe` sont maintenant des boucles (2 ou 4 lignes par tour) au lieu de lignes dépliées : profil identique à ±0,1 ms par image.

**Écran de fin** : « CONGRATULATIONS !! YOU CLEARED THE OUTPOST C-01 ! » avec une **fanfare de victoire** (`assets/MusiqueVictoire_AY.vgm`, 4,4 s, 220 images, flux delta non
compressé de 1119 octets, lue par le lecteur de jingle de l'overlay `intro.asm`) puis retour automatique au menu principal.
Le morceau a été composé avec `jingles.py` (arpèges de do majeur, basse pompée, caisse claire, cymbale finale) ; un aperçu WAV est fourni à part.

**Vérifications** (émulateur) : mission 5 chargée (icône, 25 en vert, seuils 19/13/7), corps + tête à l'écran, rafales (b_n/b_t/b_cd) et grenades toutes les 2 s, registres AY
du son Tir Boss, couleurs du HUD pour 25/19/18/13/12/7/6/1, grenade de Papi : 25 → 22 puis 22 → 19 (une seule fois par souffle), mort (explosions, CONGRATULATIONS, fanfare, menu).
`tools/ghost.py` : 18/18 sans octet fantôme sur les missions 1 à 4 ; avec `ZONE=4` (mission du boss) 0 octet faux pour 8 et 12 places (avec 4 places le script force `nb_wanted`
sous la valeur du tourniquet, ce qui n'a plus de sens). Profil (`ZONE=4 tools/prof_zone.sh 4`) : moyenne 13,8 ms, maximum 19,6 ms, 50,1 images/s tenues.

**Choix à confirmer** : le boss compte comme une des 6 unités ; v31e : 4 gardes + lui, 6 places d'ennemi, soit `_m(5, 6, ...)` ; boss à 250 points ; le boss tire à couvert comme les soldats concernés (il reste derrière un
obstacle une fois posté : `cov.append(0)` dans `build_zone` pour le retirer) ; le déplacement du corps ne vérifie pas que la place de la tête est libre (un soldat peut la chevaucher un instant).

### v31b : le boss ne reste plus planqué
Cycle du boss : à couvert, il tire ; après **10 s** (`BK_COVER` = 500 images, `boss.asm`) il repart vers Papi pendant **3 s** (`BK_ADV` = 150 images) sans chercher de couvert, puis
s'il trouve un obstacle à portée il se replanque, et ainsi de suite. (`b_cin` = images à couvert, `b_cno` = images d'avance ; hook dans `enemy_think`.) Vérifié : 12,93 → 23,114 → 30,117 puis nouvelle planque.

### v31c : code secret de beta test
Dans le **menu principal**, les touches **1 à 5** (rangée du haut du clavier) lancent directement la mission correspondante (`zone_cur` = n - 1, sans passer par « START GAME ! »).
Aucune indication à l'écran. Code dans la boucle du menu (`src/menu.asm`, étiquette `.kq`) : à retirer avant la diffusion.

### v31d : le boss remonte vers Papi
Cause du « sur place » quand Papi est au-dessus : les cases réservées par la **tête** du boss barraient le **corps** (le test de place regarde les cases occupées au-dessus des pieds). Le corps libère maintenant
celles de la tête avant de bouger (`bk_unhead`) et la tête réserve à chaque tour ses cases puis celles du corps (`bk_head`). Vérifié : Papi en haut au milieu / à droite / à gauche, le boss monte jusqu'à portée de tir ;
ghost.py (mission du boss, 8 et 12 places) : 0 octet fantôme, 0 octet faux.

### v31f : boss à 30 points de vie
`hp=30` / `kills=30` pour la mission 5 (seuils de couleur 23 / 15 / 8 calculés automatiquement) ; 4 gardes + le boss (6 places) inchangés.

### v31g : le boss rapporte 250 points
`bk_final` : 25 x 10 points (au lieu de 20 x 10).

### v31h : les vies passent d'une mission a la suivante
- Les vies ne sont plus remises a 3 au debut de chaque mission (comme le score) ; les grenades repartent toujours a 5.
- Nouvelle partie (menu ou apres Game Over) : 3 vies.
- v31i : vie bonus tous les 250 points.

### v32 : Zone 2 "THE LOST BARRACKS" (missions 6 a 10 du jeu, 5 missions ; le boss viendra apres)
- Nouveaux assets : TileSet3.png, TileSet3Obstacles.png, Zone2.tmx, Z80_12x12.png. ZINFO (tools/convert.py) decrit chaque zone (titre, carte, tuiles) ; `_m(n, ..., zn=2)`.
- Tuile violette (128,0,255) des obstacles : obstacle normal + sortie des casernes : l'ennemi apparait sur la case libre juste sous la pile de tuiles violettes (3 points : colonnes 6, 1 et 12).
- Couleurs des tuiles : le bleu ciel (0,128,255) devient le bleu vif, le cyan (0,255,255) devient le blanc (le jeu n'a que 16 stylos).
- Menu : touche `+` (en fait la touche ; +) = zone suivante, "ZONE n" s'affiche sous START GAME ; tir = 1re mission de la zone, touches 1 a 5 = mission n de la zone choisie. A retirer avant diffusion.
- Fin de zone : ecran CONGRATULATIONS + fanfare (nom de la zone), puis la zone suivante enchaine ; le numero de mission recommence a 1 a chaque zone. Le B est ajoute a la police.
- Mission "Find the Z80" : apres 20 kills (tous types), le Z80 tombe de l'ennemi abattu en dernier (objet au sol, insensible aux explosions) ; le compteur repasse a 1 ; le ramasser = victoire.
- Zone 2 : M1 tuer 20 soldats (80/20, 5 unites) ; M2 survivre 45 s (80/20, 6) ; M3 tuer 15 officiers (70/30, 6) ; M4 Z80 (60/40, 6) ; M5 tuer 25 officiers (60/40, 6).
- v32b : icone 8x8 de la mission Z80 (assets/MissionZ80Char8x8.png, bandeau : icone + kills a faire, puis 1 une fois le Z80 tombe) ; zone 2 : au debut seule la caserne la plus haute fait sortir les ennemis, au bout de 15 s toutes (hdr[4] = points au debut, hdr[7] = points ensuite, spawn_tick) ; son du Z80 qui apparait : double arpege montant (snd_u = 64). Le porteur ne clignote pas.
- v32c : les casernes (tuile violette, kind #07) ne sont plus des abris : un ennemi colle a une caserne ne tire pas "a couvert" (sa balle ne la traverse plus) et n'y cherche pas d'abri (bit 2 de la grille).
- v32d : les casernes sont pleines pour TOUS les tirs : tout le bloc d'obstacles qui touche une tuile violette (hors tuiles aussi utilisees ailleurs, comme les caisses) est marque 'caserne' (kind #07) ; le tir a couvert de Papi (bullet_cover) ne les traverse plus non plus.
- v32e : vie gagnee : le nombre de vies clignote 3 s dans le HUD (life_bl, life_blink). NXS passe de 7 a 6 (le boss garde 1 image de marge) : 144 octets de code libres de plus.
- v32f : une balle qui entre dans une caserne (bit 2 de la grille) est toujours arretee, meme celle d'un tireur a couvert (B_PASS ignore) : l'officier poste contre la caserne ne tire plus a travers.
- v32g : mission Z80 : ecran de mission "FIND THE Z80 !" seul, le Z80 entoure de soldats et d'officiers (art : unit=1/2, sans donnees en plus) ; HUD : 0 puis 1 quand le Z80 apparait (le quota de 20 kills reste interne) ; zone 2 : les casernes du bas s'ouvrent au bout de 5 s (spawn_tick, 63 x 4 images).

### v33 : mission finale de la Zone 2 : Capitaine DanTaGoul (mission 6)
- assets/BossCapitaine_12x24.png ; `boss=dict(hp=35, sheet=..., spd=32, burst=1, delay=50, cover=250)` : 35 PV, +15 % de vitesse (tables rapides), un tir par seconde (son Tir Boss a chaque tir), grenade toutes les 2 s, 5 s a couvert (250 images) puis il avance vers Papi ; garde : 4 officiers ; mission 'KILL CAPTAIN DANTAGOUL !', ecran de mission : le boss entre 2 officiers.
- Parametres propres a chaque boss dans l'en-tete de la zone (octets 12-15) : bk_cov (images a couvert), bk_nb (balles par rafale), bk_dl (delai entre rafales) ; le boss de la zone 1 garde 3 balles / 2 s / 10 s a couvert.
- Memoire : la table d'images du corps du boss utilise celle des generals (un boss n'a pas de generals) -> 72 octets de code libres ; NXS = 7 emplacements de sprites supplementaires (75 images pour cette zone) ; l'overlay des missions (images du boss) grossit : le game over est range en #C000.
- A la mort du boss : explosions, 250 points, puis CONGRATULATIONS "YOU CLEARED THE LOST BARRACKS !" et la fanfare de victoire (la meme que la zone 1), puis le menu.
- Menu secret : la touche 6 lance la mission finale (+ pour changer de zone).
- v33b : points du boss par zone (boss=dict(pts=...), hdr[11] = points/10, bk_pts) : Caporal 250, Capitaine DanTaGoul 350.
- v33c : bug : apres la mission Z80 les caisses de grenades gardaient l'image du Z80 ; load_zone_data remet crate_frame = CRATE_IMG a chaque mission.
- v33d : Zone2.tmx mise a jour (nouvelle carte de Vetea, 11/10).

### v34 : Hall of Fame
- Nouvel overlay `hof.asm` (build/hof.bin, piste HOF_TRK) : **saisie du nom** et **classement qui defile**. Bandeau Papi Commando (celui du menu) en haut ; police du HUD (3x5 doublee), avec J, Q, W et la fleche ajoutes a la police.
- Classement initial : Vetea 10000, ShiningBZH 8000, Kaot 7500, Fonzie 6666, Touko 5000, VBT 2500, Nessia 1000 (`HOF_INIT` dans tools/convert.py ; noms en majuscules, 10 caracteres au plus).
- Apres un game over (ou la fin du jeu apres le boss de la zone 2) dont le score est plus grand que le dernier du classement : ecran de saisie. Papi (spritesheet d'origine) marche en bas : gauche / droite = colonne, haut / bas = rangee, tir = la balle monte et touche la lettre entouree de rouge ; la lettre **pivote** (de face, de profil, en miroir, 3 tours) et s'ajoute au nom ; `<` efface, `OK` valide (fanfare ZONE CLEAR). Nom vide : PAPI. Le nouveau score est insere au bon rang (a egalite, apres les anciens) ; le dernier sort du classement.
- Menu : a la fin de la musique, avant qu'elle reboucle, ecran du Hall of Fame : le classement monte vite sous le bandeau, s'arrete juste dessous, 5 s (tir = on passe), puis retour au menu (le cycle recommence).
- Memoire : la table (7 x 15 octets) est rangee dans les 16 octets libres qui terminent chaque trou de la page A (HOF_E0 + n x #800, octets magiques en #875F / #8F5F) : 0 octet de code permanent en plus. Elle est creee par le menu au 1er passage (`hof_init`) et vit tant que la machine n'est pas eteinte (pas de sauvegarde sur disquette).
- Le score du jeu est plafonne a 9990 (HUD sur 4 chiffres) : la 1re place (10000) ne peut donc pas etre battue pour l'instant.
- v34b : la saisie du nom se declenche des que le score **atteint ou depasse le minimum du classement** (le dernier, 1000 au depart), sans tenir compte du rang general ; le score est ensuite insere a son rang (a egalite avec le minimum, il remplace le dernier).
- v34c : la saisie du nom depend d'un **score minimum en jeu** fixe (`HOF_MIN` dans papicpc.asm, en milliers : 1 = 1000 points), et non plus du classement. Des que le score de la partie l'atteint, saisie du nom puis insertion au bon rang (si le score est plus bas que tout le classement, il prend la derniere place).
- v34d : classement initial : Vetea 9000, ShiningBZH 7500, Fonzie 6666, Kaot 5000, Touko 2500, Nessia 1000, VBT 500.
- v34e : score minimum du Hall of Fame **libre de 0 a 9999 points** : `HOF_MIN equ 500` en haut de la zone "Hall of Fame" de src/papicpc.asm (le score va de 10 en 10). Le jeu compare les chiffres milliers / centaines / dizaines du score a ceux de HOF_MIN (HM_K, HM_H, HM_T calcules par l'assembleur).
- v34f : saisie du nom : Papi reste dos tourne (direction haut, images 12 a 15) quel que soit le sens de la marche ; Zone2.tmx mise a jour (nouveau spot d'apparition en haut a gauche : il devient la 1re caserne ouverte, les 3 autres s'ouvrent au bout de 5 s ; 4 points d'apparition : (0,2) (36,50) (6,146) (72,154)).

### v35 : version de diffusion (sans codes secrets) / version de test
- `./build.sh` (ou `build.bat`) = version de **diffusion** : plus de touche `+` ni de touches 1 a 6 dans le menu, plus de touche M (jauge de charge). Tir = mission 1 de la zone 1.
- `./build.sh debug` (ou `build.bat debug`) = version de **test** (RASM -DCHEATS=1) : codes secrets conserves pour les futures zones (`+` change de zone, 1 a 6 lancent la mission n de la zone choisie, M = jauge). Les outils tools/ghost.py, scen.py, prof*.sh supposent cette version : les lancer apres `./build.sh debug`.
- Hall of Fame : `HOF_MIN` (score minimum) et `HOF_INIT` (classement initial, tools/convert.py) restent reglables.


### v36 : Zone 3 « HIDDEN HEADQUARTER » (missions 11 a 14) et eau animee
- Nouvelle zone : TileSet2 + Zone3.tmx (le decor et les obstacles se composent avec le TileSet1, comme pour la zone 2). 4 missions : 25 officiers (80/20, 6 unites), survivre 45 s (70 % soldats / 30 generaux, 6), trouver le Z80 apres 20 kills (60/40, 6), 20 generaux (60/40, 7). La mission 5 (Falzar) attend le boss.
- Obstacle rose (255,0,210) des PNG d'obstacles = EAU. Tuile animee sur 3 images (1 2 3 2), `assets/Eau_3frames_12x8.png`. Les couleurs de l'eau sont ramenees sur la palette CPC (bleu vif, bleu fonce, blanc, bleu-vert).
- Regles : les ennemis n'y entrent pas (champ de distances et can_stand_e) ; Papi la franchit, 25 % plus lent, sprite coupe a 12 x 6 (pas de jambes) ; balles et grenades passent au-dessus ; Papi reste touchable et lance ses grenades depuis l'eau.
- Moteur : l'animation redessine au plus 3 cases par image (balayage de 32 cases). Aucune place prise dans la partie permanente (variables deplacees en #0117-#0134, routines de l'eau dans les trous de la memoire). Limite : l'eau utilise 2 emplacements d'images, une zone avec boss et eau est limitee a 73 images d'unites.

### v36b : TileSet2Obstacles modifie
- Tuile 65 du TileSet2 (le dessus blanc des murs) : rouge (obstacle) -> jaune (premier plan : Papi et les ennemis passent derriere).

### v37 : eau a 40 % et tir des ennemis dans le sens de la marche
- Papi dans l'eau : vitesse = 40 % de la normale (WSLOW_X 36 / WSLOW_Y 72 dans src/water.asm).
- Un ennemi qui marche tire dans la direction de sa marche (E_DIR) ; quand il s'arrete (assez pres, ou a couvert), il se tourne vers Papi et tire vers lui, comme avant. Les boss ne changent pas.

### v38 : un tir ne traverse plus un obstacle surmonte de son tile d'avant-plan
- Dans bullets_update, une balle sur une case d'avant-plan (jaune) dont la case juste dessous arrete les balles (obstacle rouge) est arretee comme par l'obstacle : le dessus du mur fait partie du mur. Sous un linteau sans obstacle dessous (zone 3, ligne des 7 tuiles blanches entre les deux piliers), les balles passent toujours.
- (Place gagnee dans la partie permanente : 11 `jp cc` devenus `jr cc`.)

### v39 : plus de tempo d'ouverture des casernes (zones 2 et 3)
- Les points d'apparition (portes violettes) servent tous des le debut de la mission : fini le premier point seul pendant 5 s (spawn_tick, spawn_full et le parametre 'first' du convertisseur supprimes). Les ennemis sortent a tour de role par chaque porte, un toutes les 10 images au depart, puis un renfort 3 a 5,5 s apres chaque mort (inchange).
- tools/ghost.py : variable KEYS (ex. KEYS=4,6) ; ne plus utiliser la touche 2 (4 ennemis) sur une zone a 6 unites : baisser l'effectif en cours de partie plante le moteur (artefact du test, ca n'arrive pas en jeu).

### v40 : ACCESS CODE
- Menu principal : deux options, START GAME ! et ACCESS CODE (haut / bas pour choisir, l'option choisie clignote en jaune, tir pour valider).
- ACCESS CODE ouvre l'ecran de saisie du Hall of Fame (HOF_MODE = 2, meme overlay, HOF_N passe a 10 secteurs). Bon code : "ACCESS ZONE x / GRANTED !" + fanfare, retour au menu ; mauvais code : "WRONG CODE !" en rouge, le code s'efface et on recommence.
- Codes (tools/convert.py, ACCESS -> src/access.inc) : zone 2 FONZIE, zone 3 MAMIE. START GAME demarre a la zone choisie (acc_zone, variable permanente PVARS+30) ; sans code : zone 1.
- Fin de zone : sous le message, "ACCESS CODE ZONE 2" et FONZIE (apres la zone 1), "... ZONE 3" et MAMIE (apres la zone 2).
- Version de test : la touche + du menu part de la zone choisie par le code ; m_z / m_zk deplaces en MV+91 / MV+92 (ils etaient ecrases par xbuf).


### v41 : Zone 3, mission 5 « KILL GENERAL FALZAR » (boss final)
- Mission 16 (zone 3, mission 5) : 5 unites (corps + tete du boss + 3 generaux, 100 % generaux), 45 PV, rafales de 3 balles, 1 s entre deux rafales (Tir Boss), 5 s a couvert puis il avance vers Papi, pathfinding et balles des officiers, clignotement blanc a chaque coup, explosions a sa mort. Sprite : assets/BossFalzar_12x24.png. Ecran de mission : Falzar entre 2 generaux. Il ne lance pas de grenade (le cahier des charges n'en prevoit pas : le boss est sans grenade des que ses points sont >= 500, pts=50 dans convert.py).
- Vitesse : troisieme jeu de tables de pas (dt_tab + 64), 15 % au-dessus des generaux (spd=64).
- Victoire : « CONGRATULATIONS !! YOU CLEARED HIDDEN HEADQUARTER! » + fanfare inedite de 4,5 s (tools/mkvictory.py : melodie, arpege et basse/caisse claire, Do majeur, ecrite directement en registres AY ; src/jingle_victory3.asm), puis Hall of Fame (score >= 500) et menu. Les zones 1 et 2 gardent leur fanfare.
- Disquette : les zones sont maintenant rangees secteur par secteur (le chargeur sait partir d'un secteur quelconque) : la disquette ne depasse plus 40 pistes. Overlay des missions : 18 secteurs ; les overlays Game Over et Hall of Fame sont assembles plus haut (#D000, #E000).
- Place dans la partie permanente : 5 `jp` devenus `jr`.

### v41b : generaux de la garde de Falzar
- Les generaux de la mission 5 utilisaient la table d'images du corps du boss (la table des generals est partagee avec lui) : tetes coupees. Dans une mission de boss a garde de generaux, convert.py range maintenant les images des generaux dans la table des soldats (index 0) ; aucun changement du moteur.

### v41c : Falzar sans grenade (vraiment) + nouvelle carte de la zone 3
- Le test « pas de grenade » du boss (points >= 500) n'avait pas ete pris en compte dans la v41 (remplacement rate dans boss.asm) : Falzar lancait une grenade toutes les 2 s. Corrige et verifie en jeu (EG_STATE reste a 0 pendant tout le combat).
- assets/Zone3.tmx remplace par la nouvelle carte (missions 11 a 15).

### v41d : pathfinding : les postes de couverture ne sont plus dans l'eau
- Cause du blocage de Falzar (et des autres ennemis) pres des rivieres : cover_seek acceptait comme "poste de couverture" une case d'EAU (bits 1 et 0 a zero = "verte") avec un mur rouge dessous, p. ex. la case d'eau juste au-dessus d'une berge. L'ennemi fonçait tout droit vers ce poste, butait sur la berge, et se tortillait sans trouver le gue. Le masque passe de #83 a #8B (eau exclue) : aucun octet de code en plus.
- Mesure (Papi en bas a droite) : Falzar restait bloque a y = 93 avant, il franchit maintenant la riviere (y = 141 en 1500 images). Il peut encore attendre derriere un general qui occupe un couloir d'une case : embouteillage normal, il repart quand le general bouge.

### v41e : « MISSION DONE ! »
- L'ecran de fin de mission affiche « MISSION DONE ! » (txt_win) au lieu de « ZONE CLEAR ! » ; le jingle ne change pas. Les fins de zone (CONGRATULATIONS...) ne changent pas non plus.
- Deux octets gagnes dans la partie permanente pour la version de test : touche M en `cpl`, et `dec a` a la place de `cp 1` dans le comptage des images d'appui sur tir (seuil de la grenade : GRENADE_HOLD-1).

### v41f : tuiles d'eau parasites sur l'ecran de fin de mission
- Cause : wtr_tick (animation de l'eau) tournait aussi quand la partie est finie (p_state = 2) : apres le blackout de MISSION DONE ! (et sous le message GAME OVER !), les tuiles d'eau dont l'image changeait etaient redessinees par-dessus l'ecran noir. wtr_tick rend maintenant la main des que p_state = 2.
- Verifie : scene figee en zone 3, l'ecran ne change plus d'un pixel (avant : les tuiles d'eau continuaient de s'animer).

### v41g : la grenade des officiers ne depasse plus sa portee
- Cause : l'ecart vertical lanceur/Papi etait calcule sur un octet signe. Au-dela de 127 lignes (officier en haut, Papi en bas : cas frequent, l'ecran fait 200 lignes), l'ecart « passait en negatif » : la grenade partait dans le mauvais sens, avec la portee maximale, et sortait de l'ecran. Le signe est maintenant lu dans la retenue du `sub` (.clamp) : plus fiable, et 2 octets de moins.
- Mesure : toutes les grenades atterrissent a 20 octets / 60 lignes au plus du lanceur (avant : jusqu'a 197 lignes).
