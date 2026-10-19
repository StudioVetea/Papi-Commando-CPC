#!/usr/bin/env python3
"""Deplace Papi (invincible) selon un scenario et prend des captures : outil de test.
   usage: walk.py out.png "R40 U60 S L26 U14 S ..."   (R/L/U/D + frames, S = capture, F = tir on/off, Kx = touche)"""
import subprocess, sys, re, os
MODEL = os.environ.get('CPCMODEL','6128')
from PIL import Image
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sym = {l.split()[0]: l.split()[1][1:] for l in open(root + '/build/papicpc.sym') if ' #' in l}
inv = sym['P_INV']
cmds = [MODEL, root + '/build/PAPICPC.dsk', 'type:RUN"PAPICPC"~', 'run:1000', 'key:0x20', 'run:4', 'keyup:0x20', 'run:260']
dirs = {'R': 8, 'L': 4, 'U': 1, 'D': 2, 'N': 0, 'A': 9, 'B': 5, 'C': 10, 'E': 6}
fire = 0; shots = []
for tok in sys.argv[2].split():
    if tok == 'S':
        fn = '/tmp/_w%d.ppm' % len(shots); shots.append(fn); cmds.append('shot:' + fn)
    elif tok == 'F': fire ^= 16
    elif tok[0] == 'K':
        cmds += ['key:0x%02x' % ord(tok[1]), 'run:4', 'keyup:0x%02x' % ord(tok[1])]
    elif tok[0] == 'P':
        a, v = tok[1:].split('='); cmds.append('poke:%s:%s' % (sym[a], v))
    else:
        n = int(tok[1:]); cmds.append('joy:%d' % (dirs[tok[0]] | fire))
        while n > 0:
            k = min(4, n); cmds += ['poke:%s:251' % inv, 'run:%d' % k]; n -= k
subprocess.run([root + '/tools/cpcrun'] + cmds, check=True)
ims = [Image.open(f).crop((60, 0, 708, 544)) for f in shots]
cols = 2 if len(ims) > 1 else 1
rows = (len(ims) + cols - 1) // cols
o = Image.new('RGB', (cols * 652, rows * 548))
for i, im in enumerate(ims): o.paste(im, ((i % cols) * 652, (i // cols) * 548))
o.save(sys.argv[1])
