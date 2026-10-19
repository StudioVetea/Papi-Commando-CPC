# Papi Commando CPC

Jeu d'action en vue de dessus pour **Amstrad CPC 464 / 664 / 6128 (64 Ko)**, MODE 0, 100 % assembleur Z80 ([RASM](https://github.com/EdouardBERGE/rasm)).

Papi, vétéran en mission commando, traverse des zones remplies de soldats, d'officiers et de généraux, jusqu'au boss final : le général Falzar.

## Jouer
- `dist/PAPICPC_v41g_DIFFUSION.dsk` : version finale. Dans un émulateur (ou sur CPC), `RUN"PAPICPC"`.
- `dist/PAPICPC_v41g_TEST.dsk` : version de test avec codes secrets (choix de la zone dans le menu, etc.).

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
