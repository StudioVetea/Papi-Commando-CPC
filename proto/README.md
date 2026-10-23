# Prototype scrolling vertical (CPC 6128, MODE 0)

Test technique, hors jeu. Zone 4 + zone de test + zone 4 (72 rangees de 13 tuiles), Papi masque, camera verticale.

Build : `python3 proto/gen_data.py && cat proto/scroll_head.asm proto/scroll_tail.asm > proto/scroll.asm && rasm proto/scroll.asm -o proto/scroll -eo -s` -> SCROLL.BIN (dsk non versionne).
Lancer : `RUN"SCROLL"`. Fleches/joystick 1 pour bouger, Fire/Espace = course (4 lignes par image).

Principe : tampon circulaire de 2 Ko par plan (pas de rangee 78 octets, R1=39), R12/R13 = rangee de depart,
defilement fin de 2 lignes par R9 raccourci sur la rangee du haut (A/B) et du bas (C/D), ecritures chronometrees
dans les interruptions. Rangee du haut redessinee a chaque image, rangee r+25 pre-dessinee dans l'espace libre.
Verifie uniquement sur emulateur (tools/cpcrun.c : crtclog, vshot, vbl).
