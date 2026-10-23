#!/usr/bin/env python3
"""Genere proto/data.inc : palette, tuiles, carte haute (72 rangees), images de Papi (masque, donnee)."""
import os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import convert as cv
A = os.path.join(ROOT, 'assets') + '/'

def tmx(name, gid0, base):
    s = open(A + name).read()
    rows = re.search(r'<data encoding="csv">(.*?)</data>', s, re.S).group(1).strip().split('\n')
    return [[base + (int(v) - gid0) % 40 for v in r.strip().strip(',').split(',')] for r in rows]

# 80 tuiles : 0-39 = TileSet1 (zone 1), 40-79 = TileSet4 (zone 4)
tiles = []
for ts in ('TileSet1.png', 'TileSet4.png'):
    g = cv.load(ts)
    for t in range(40):
        tiles.append(cv.opaque(g, (t % 4) * 12, (t // 4) * 8, 12, 8))     # 48 octets : 8 lignes de 6 octets
z4 = tmx('Zone4.tmx', 117, 40)
z1 = tmx('ZoneTest.tmx', 1, 0)
# carte de haut en bas : zone 4, zone 1, zone 4 (72 rangees = 576 lignes)
MAP = z4 + z1 + z4
MAPH = len(MAP)
if os.environ.get('TESTMAP'):                      # carte de test : chaque ligne de carte a sa couleur (cycle de 15)
    tiles = []
    for t in range(80):
        tt = []
        for y in range(8):
            pen = (y + 1) if os.environ.get('TESTMAP')=='2' else ((8 * t + y) % 15) + 1
            tt += [cv.enc(pen, pen)] * 6
        tiles.append(tt)
    MAP = [[m % 15] * 13 for m in range(72)]
assert MAPH == 72 and all(len(r) == 13 for r in MAP)
papi = cv.load('PapiCPC_12x12.png')
ROWS = {'down': 0, 'right': 1, 'up': 3, 'left': 4}          # rangees de la planche : 4 images chacune
order = ['up', 'down', 'left', 'right']
with open(os.path.join(ROOT, 'proto', 'data.inc'), 'w') as f:
    f.write('; --- genere par proto/gen_data.py ---\nMAPH equ %d\nCYMAX equ %d\n' % (MAPH, MAPH * 8 - 192))
    f.write('palette:\n'); cv.db(f, [cv.HW[p] for p in cv.PENS] + [cv.HW[0]])
    f.write('tile_addr:\n')
    for i in range(0, 80, 8): f.write(' dw ' + ','.join('tiles+%d' % (48 * k) for k in range(i, i + 8)) + '\n')
    f.write('tiles:\n')
    for t in tiles: cv.db(f, t, 12)
    f.write('map:\n')
    for r in MAP: cv.db(f, r, 13)
    f.write('rowptr:\n')
    for i in range(0, MAPH, 8): f.write(' dw ' + ','.join('map+%d' % (13 * k) for k in range(i, min(i + 8, MAPH))) + '\n')
    f.write('rowoff:                  ; decalage de chaque rangee dans le tampon circulaire de 2 Ko par plan\n')
    for i in range(0, MAPH, 8): f.write(' dw ' + ','.join('%d' % ((78 * k) & 0x7FF) for k in range(i, min(i + 8, MAPH))) + '\n')
    f.write('papi_tab:\n')
    k = 0
    for d in order:
        f.write(' dw ' + ','.join('papi_img+%d' % (144 * (4 * order.index(d) + j)) for j in range(4)) + '\n')
    f.write('papi_img:\n')
    for d in order:
        for j in range(4):
            cv.db(f, cv.masked(papi, j * 12, ROWS[d] * 12, 12, 12), 12)
print('data.inc ok :', MAPH, 'rangees')
