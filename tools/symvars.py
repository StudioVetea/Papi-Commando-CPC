#!/usr/bin/env python3
"""RASM n'ecrit pas les 'equ' dans le fichier de symboles : on y ajoute les variables du jeu (bloc VARBASE de src/papicpc.asm),
que les outils de test (ghost.py, scen.py, walk.py, prof.sh) lisent par leur nom."""
import re, os
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
s = open(root + '/src/papicpc.asm').read()
base = int(re.search(r'^VARBASE\s+equ\s+#([0-9A-Fa-f]+)', s, re.M).group(1), 16)
out = []
for m in re.finditer(r'^(\w+)\s+equ VARBASE\+(\d+)', s, re.M):
    out.append('%s #%X B0 L' % (m.group(1).upper(), base + int(m.group(2))))
pv = base + int(re.search(r"^PVARS\s+equ VARBASE\+(\d+)", s, re.M).group(1))
for m in re.finditer(r'^(\w+)\s+equ PVARS(?:\+(\d+))?\b', s, re.M):
    out.append('%s #%X B0 L' % (m.group(1).upper(), pv + int(m.group(2) or 0)))
m = re.search(r'^vars_end\s+equ VARBASE\+(\d+)', s, re.M)
open(root + '/build/papicpc.sym', 'a').write('\n'.join(out) + '\n')
