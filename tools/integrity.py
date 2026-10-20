#!/usr/bin/env python3
"""Controle d'integrite des images de sprites en memoire (a lancer apres chaque build) :
   compare, octet par octet, les images de Papi / explosions / caisse residentes en memoire (apres FR images de jeu)
   avec les donnees generees par convert.py (src/gfx_spr.asm, adresses de src/frames.asm).
   Detecte tout ce qui ecrase une image : code copie dans un « trou » qui tombe dans le bloc spr_papi, table mal placee, etc.
   usage : ZONE=n FR=images tools/integrity.py     (code de sortie 1 si une image est abimee ; affiche l'image, l'adresse,
   et pour chaque ecart l'octet attendu / trouve, avec le symbole le plus proche du debut de l'ecart dans build/papicpc.sym)"""
import os, re, subprocess, sys
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sym = {}
for l in open(root + '/build/papicpc.sym'):
    p = l.split()
    if len(p) > 1 and p[1].startswith('#') and '.' not in p[0]: sym[p[0]] = int(p[1][1:], 16)
ZONE = int(os.environ.get('ZONE', '0')); FR = int(os.environ.get('FR', '500'))
cmds = ['6128', root + '/build/PAPICPC.dsk', 'idle:%X:%X' % (sym['MAIN_LOOP'], sym['WAIT_END']), 'seed:1', 'type:RUN"PAPICPC"~', 'run:1000', 'key:0x20', 'run:4', 'keyup:0x20']
if ZONE: cmds += ['run:30', 'poke:%X:%d' % (sym['ZONE_CUR'], ZONE), 'key:0x20', 'run:4', 'keyup:0x20']
cmds += ['run:%d' % FR, 'sync', 'dump:/tmp/_integrity.bin']
subprocess.run([root + '/tools/cpcrun'] + cmds, check=True, stdout=subprocess.DEVNULL)
m = open('/tmp/_integrity.bin', 'rb').read()
data = []
for l in open(root + '/src/gfx_spr.asm'):
    l = l.strip()
    if l.startswith('db'): data += [int(x.strip().lstrip('#'), 16) for x in l[2:].split(',')]
frames = open(root + '/src/frames.asm').read()
ptrs = [int(x, 16) for x in re.findall(r'#([0-9A-F]{4})', frames.split('papi_frames:')[1])]     # papi, explosions, puis la caisse
uniq = []
for a in ptrs:
    if a not in uniq: uniq.append(a)
n = len(data) // 144
names = sorted(sym.items(), key=lambda kv: kv[1])
def near(a):
    best = None
    for k, v in names:
        if v <= a: best = (k, v)
    return '%s+%d' % (best[0], a - best[1]) if best else '?'
bad = 0
for k, a in enumerate(uniq[:n]):
    src, ram = data[k * 144:(k + 1) * 144], list(m[a:a + 144])
    if src != ram:
        bad += 1
        diff = [i for i in range(144) if src[i] != ram[i]]
        print('IMAGE %d en #%04X abimee : %d octets differents (decalages %d a %d)' % (k, a, len(diff), diff[0], diff[-1]))
        s0 = sym['SPR_PAPI'] + k * 144 + diff[0]            # adresse de ces octets dans le bloc source (copie ensuite vers #8000...)
        print('   premier ecart : attendu %02X, trouve %02X. Dans le bloc source spr_papi (copie au demarrage), ces octets sont en #%04X (%s) :'
              % (src[diff[0]], ram[diff[0]], s0, near(s0)))
        print('   chercher qui ECRIT en #%04X-#%04X (code, table ou donnees copies AVANT la copie des sprites dans boot) : tools/cpcrun watch:%X' % (s0, sym['SPR_PAPI'] + k * 144 + diff[-1], s0))
print('images verifiees : %d, abimees : %d (zone %d, apres %d images)' % (min(n, len(uniq)), bad, ZONE, FR))
sys.exit(1 if bad else 0)
