#!/usr/bin/env python3
"""Ecrit la cover et les zones (compressees) en secteurs bruts dans l'image DSK etendue produite par RASM.
   usage : mkdisk.py build/PAPICPC.dsk"""
import sys, os, json
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = sys.argv[1]
d = bytearray(open(path, 'rb').read())
ntr = d[0x30]; sizes = [d[0x34 + i] * 256 for i in range(ntr * d[0x31])]
off = [0x100]
for s in sizes: off.append(off[-1] + s)
def put(track, data, sec0=0):
    for i in range(0, len(data), 512):
        t, sec = track + (sec0 + i // 512) // 9, (sec0 + i // 512) % 9
        blk = off[t]; assert d[blk + 0x15] == 9
        base = blk + 0x100 + sec * 512
        d[base:base + 512] = data[i:i + 512].ljust(512, b'\0')
lay = json.load(open(os.path.join(ROOT, 'build', 'layout.json')))
for name, e in lay.items():
    fn = 'cover.bin' if name == 'cover' else name + '.bin'
    data = open(os.path.join(ROOT, 'build', fn), 'rb').read()
    put(e['track'], data, e.get('sector', 0))
    print('disquette : %-6s piste %2d, %2d secteurs' % (name, e['track'], -(-len(data) // 512)))
open(path, 'wb').write(d)
