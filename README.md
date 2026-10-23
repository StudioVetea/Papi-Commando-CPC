# Papi Commando CPC

Jeu d'action en vue de dessus pour **Amstrad CPC 6128 (128 Ko)**, MODE 0, 100 % assembleur Z80 ([RASM](https://github.com/EdouardBERGE/rasm)).
Une *branche* **v42-64K** a été faite pour garder l'ancienne version 64Ko, j'ai migré vers 128Ko en prévision de la finalisation du jeu avec les nombreux ajouts restants à faire.

Le jeu est compatible avec tous les modèles CPC d'origine, par contre vu la caractéristique de son moteur avec ses accès disques, la version .rom n'est pas actuellement disponible pour les modèles GX4000/CPC+. A envisager par la suite pour profiter de l'upgrade HW du matériel, mais cela nécessitera une refonte complète du jeu.


Papi, vétéran en mission commando, traverse des zones remplies de soldats, d'officiers et de généraux, jusqu'au boss final de la Zone 3 : le général Falzar.
D'autres zones seront proposées et réalisées par la suite.
A chaques nouvelles mise à jour, un commit sera effectué ! 

Je rappelle que Claude IA est utilisé pour l'assistance du code z80 du projet, tout le reste est géré et crée par moi-même.

## Jouer
- `dist/PAPICPC_v42_DIFFUSION.dsk` : version finale. Dans un émulateur (ou sur CPC), `RUN"PAPICPC"`.
- `dist/PAPICPC_v42_TEST.dsk` : version de test avec codes secrets (choix de la zone dans le menu, etc.).

| Action | Joystick | Clavier |
|---|---|---|
| Déplacement (8 directions) | manette | flèches |
| Tirer | bouton 1 | ESPACE ou COPY |
| Grenade (maintenir pour la portée) | bouton 2 | RETURN |

## Compiler
Prérequis : `rasm` dans le PATH, Python 3 (avec Pillow).
```
./build.sh          # version de diffusion -> build/PAPICPC.dsk
./build.sh debug    # version de test
```

## Contenu
- `src/` : code Z80 (moteur, boss, eau, intro, musique)
- `assets/` : sprites, tuiles, cartes Tiled
- `tools/` : conversion des assets, génération de la disquette, tests automatiques
- `LISEZMOI.md` : notes techniques détaillées, version par version

Studio Vetea.

## Prototype 2 (scrolling vertical + ennemis)
Sources dans `proto/` (`g2_head.asm`, `g2_game_a.asm`, `g2_game_b.asm`, `build_g2.py`, `gen_data.py`).
Construire : `python3 proto/build_g2.py` (donne `GAME2.BIN` / `game2.dsk`, lancer avec `RUN"GAME2"`).
Scroll CRTC 50 Hz, 8 soldats, tirs, collisions décor/balles ; 0 image ratée mesurée sur émulateur (4 parcours aléatoires x 250 images).
