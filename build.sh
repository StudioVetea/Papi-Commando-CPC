#!/bin/sh
# Assemble le jeu : produit build/PAPICPC.dsk (RUN"PAPICPC").  Il n'y a plus de .sna : la zone et la cover se
# chargent depuis la disquette (secteurs bruts), ce que l'image de memoire d'un .sna ne peut pas representer.
# RASM=/chemin/vers/rasm ./build.sh   si rasm n'est pas dans le PATH
set -e
cd "$(dirname "$0")"
RASM=${RASM:-rasm}
# ./build.sh        : version de DIFFUSION (sans codes secrets)
# ./build.sh debug  : version de TEST (touche + et 1-6 du menu, touche M) -> build/PAPICPC.dsk aussi
DEF=
if [ "$1" = debug ]; then DEF=-DCHEATS=1; fi
mkdir -p build
python3 tools/convert.py
rm -f build/PAPICPC.dsk
$RASM $DEF src/papicpc.asm -Isrc/ -o build/papicpc -s -eo
python3 tools/symvars.py
python3 tools/mkdisk.py build/PAPICPC.dsk
