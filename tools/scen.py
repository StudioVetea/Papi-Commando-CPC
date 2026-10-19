#!/usr/bin/env python3
"""Banc de scenarios : lance cpcrun avec des commandes, renvoie les lignes 'peek'.
   usage (en module) : from scen import run, sym"""
import subprocess, os, re
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SYM = {}
for l in open(ROOT + '/build/papicpc.sym'):
    p = l.split()
    if len(p) >= 2 and p[1].startswith('#') and '.' not in p[0]: SYM[p[0]] = int(p[1][1:], 16)
def sym(n): return SYM[n.upper()]
def run(cmds, model='6128'):
    start = ['type:RUN"PAPICPC"~', 'run:1000', 'key:0x20', 'run:4', 'keyup:0x20', 'run:260']
    out = subprocess.run([ROOT + '/tools/cpcrun', model, ROOT + '/build/PAPICPC.dsk'] + start + cmds, check=True, capture_output=True, text=True).stdout
    res = []
    for l in out.splitlines():
        m = re.match(r'^([0-9A-F]{4}):((?: [0-9A-F]{2})+)$', l)
        if m: res.append(bytes(int(x, 16) for x in m.group(2).split()))
        elif l.strip(): print(l)
    return res
def peek(name, n=1): return 'peek:%X:%d' % (sym(name), n)
def poke(name, v, off=0): return 'poke:%X:%d' % (sym(name) + off, v)
