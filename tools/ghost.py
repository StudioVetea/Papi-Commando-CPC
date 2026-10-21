#!/usr/bin/env python3
"""Test anti-fantomes : apres une partie jouee par le robot, tout octet de l'ecran
qui n'est pas sous un sprite actif doit etre identique au decor (miroir)."""
import subprocess, sys, os
MODEL = os.environ.get('CPCMODEL','6128')   # la disquette n'existe pas sur 464
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sym = {l.split()[0]: int(l.split()[1][1:], 16) for l in open(root + '/build/papicpc.sym') if ' #' in l}
sym["OCCY"] = 0x3400
sym["BULLETS"] = 0x308C
sym["SOLDAT_FRAMES"] = 0x3100      # tables d'images des unites : en memoire libre, chargees avec la zone
sym["OFFICER_FRAMES"] = 0x3148
sym["GENERAL_FRAMES"] = 0x3190
sym["SLOT_TYPE"] = 0x3000
sym["SLOT_FLASH"] = 0x3054
ZONE = int(os.environ.get('ZONE', '0'))         # ZONE=4 : mission du boss
def run(key, seed, frames):
    cmds = [MODEL, root + '/build/PAPICPC.dsk', 'idle:%X:%X' % (sym['MAIN_LOOP'], sym['WAIT_END']), 'seed:%d' % seed, 'type:RUN"PAPICPC"~', 'run:1000'] + ([] if ZONE else ['key:0x20', 'run:4', 'keyup:0x20']) + (sum([['key:0x3b', 'run:4', 'keyup:0x3b', 'run:4'] for _ in range(max(z for z in range(4) if (0, 5, 10, 15)[z] <= ZONE))], []) + ['key:0x%x' % (0x31 + ZONE - (0, 5, 10, 15)[max(z for z in range(4) if (0, 5, 10, 15)[z] <= ZONE)]), 'run:4', 'keyup:0x%x' % (0x31 + ZONE - (0, 5, 10, 15)[max(z for z in range(4) if (0, 5, 10, 15)[z] <= ZONE)]), 'run:30'] if ZONE else []) + ['run:420', 'poke:%X:%d' % (sym['NB_WANTED'], 2 * key), 'run:4',
            'poke:%X:99' % sym['KILLS_LEFT'], 'poke:%X:200' % sym['LIVES'], 'bot:1', 'run:%d' % frames]
    if '-seq' in sys.argv:      # partie perdue, nouvelle partie (les changements d'effectif en cours de partie n'existent plus)
        cmds += ['poke:%X:1' % sym['LIVES'], 'run:900']
    cmds += ['sync', 'dump:/tmp/_ram_' + MODEL + '.bin']
    subprocess.run([root + '/tools/cpcrun'] + cmds, check=True, stdout=subprocess.DEVNULL)
    return open('/tmp/_ram_' + MODEL + '.bin', 'rb').read()
def addr(x, y): return 0xC000 + ((y >> 3) + 1) * 80 + (y & 7) * 0x800 + 1 + x      # decor decale de 8 lignes : le HUD est en haut
bad_total = 0
import itertools
SEEDS = (int(os.environ['ONE']),) if os.environ.get('ONE') else (1, 2, 3) if '-long' not in sys.argv else range(10, 15)
FRAMES = tuple(int(f) for f in os.environ['FR'].split(',')) if os.environ.get('FR') else (700, 1500) if '-long' not in sys.argv else (2500,)
for key in tuple(int(k) for k in os.environ.get('KEYS', '2,4,6').split(',')):
    for seed in SEEDS:
        for frames in FRAMES:
            m = run(key, seed, frames)
            covered = set()
            def rect(x, y, w, h):
                for j in range(h):
                    for i in range(w):
                        if 0 <= x + i < 78 and 0 <= y + j < 192: covered.add(addr(x + i, y + j))
            if m[sym['P_STATE']] == 2: rect(16, 83, 48, 12)     # ecran de fin : le message est dessine a l'ecran, sans passer par le miroir
            py, px = m[sym['P_OY']], m[sym['P_OX']]
            if px != 0xFF: rect(px, py, 6, 12)
            for e in range(12):
                b = sym['ENEMIES'] + e * 16
                if m[b + 3] != 0xFF: rect(m[b + 3], m[b + 4], 6, 12)
            for k in range(10):
                b = sym["BULLETS"] + k * 11
                if m[b + 3] != 0xFF: rect(m[b + 3], m[b + 4], 2 if m[b] == 3 else 1, 6)      # etat 3 : eclat (2 octets)
            if m[sym['CRATE_ST']] in (1, 2) and m[sym['CRATE_OX']] != 0xFF: rect(m[sym['CRATE_OX']], m[sym['CRATE_OY']], 6, 12)   # caisse de grenades
            if m[sym['G_OX']] != 0xFF: rect(m[sym['G_OX']], m[sym['G_OY']], 2, 6)                       # grenade
            if m[sym['EG_OX']] != 0xFF: rect(m[sym['EG_OX']], m[sym['EG_OY']], 2, 6)                       # grenade ennemie
            if m[sym['G_STATE']] == 2 and m[sym['G_EOX']] != 0xFF: rect(m[sym['G_EOX']], m[sym['G_EOY']], 6, 12)   # explosion
            if m[sym['EG_STATE']] == 2 and m[sym['EG_EOX']] != 0xFF: rect(m[sym['EG_EOX']], m[sym['EG_EOY']], 6, 12)   # explosion ennemie
            bad = [(x, y) for y in range(192) for x in range(78)
                   if addr(x, y) not in covered and m[addr(x, y)] != m[addr(x, y) - 0x8000]]
            alive = sum(1 for e in range(12) if m[sym['ENEMIES'] + e * 16] == 1)
            # chevauchements entre sprites, et integrite de chaque sprite isole
            rects = []
            if px != 0xFF: rects.append((px, py, 6, 12, None))
            for e in range(12):
                b = sym['ENEMIES'] + e * 16
                if m[b + 3] != 0xFF: rects.append((m[b + 3], m[b + 4], 6, 12, m[b + 9], e))
            for k in range(10):
                b = sym["BULLETS"] + k * 11
                if m[b + 3] != 0xFF: rects.append((m[b + 3], m[b + 4], 2 if m[b] == 3 else 1, 6, None))
            if m[sym['CRATE_ST']] in (1, 2) and m[sym['CRATE_OX']] != 0xFF: rects.append((m[sym['CRATE_OX']], m[sym['CRATE_OY']], 6, 12, None))
            if m[sym['G_OX']] != 0xFF: rects.append((m[sym['G_OX']], m[sym['G_OY']], 2, 6, None))
            if m[sym['EG_OX']] != 0xFF: rects.append((m[sym['EG_OX']], m[sym['EG_OY']], 2, 6, None))
            if m[sym['G_STATE']] == 2 and m[sym['G_EOX']] != 0xFF: rects.append((m[sym['G_EOX']], m[sym['G_EOY']], 6, 12, None))
            if m[sym['EG_STATE']] == 2 and m[sym['EG_EOX']] != 0xFF: rects.append((m[sym['EG_EOX']], m[sym['EG_EOY']], 6, 12, None))
            def inter(a, b):
                w = min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0]); h = min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1])
                return w > 0 and h > 0
            over = sum(1 for i in range(len(rects)) for j in range(i) if rects[i][2] == 6 and rects[j][2] == 6 and inter(rects[i], rects[j]))
            wrong = 0; checked = 0
            for i, r in enumerate(rects):
                if r[4] is None or r[4] > 35: continue
                if m[sym['SLOT_FLASH'] + r[5]]: continue          # il clignote en blanc : image volontairement differente
                if any(inter(r, q) for j, q in enumerate(rects) if j != i): continue
                ft = (sym['SOLDAT_FRAMES'], sym['OFFICER_FRAMES'], sym['GENERAL_FRAMES'], sym['GENERAL_FRAMES'], sym['BOSS_FRAMES'])[m[sym['SLOT_TYPE'] + r[5]]] + 2 * r[4]
                d = m[ft] + 256 * m[ft + 1]
                checked += 1
                for ln in range(12):
                    for bt in range(6):
                        k = bt if ln % 2 == 0 else 5 - bt
                        mask, val = m[d + ln * 12 + 2 * k], m[d + ln * 12 + 2 * k + 1]
                        a = addr(r[0] + bt, r[1] + ln)
                        hidden = m[0x3800 + (((r[1] + ln) >> 3) + 1) * 16 + (r[0] + bt) // 6] & 0x80
                        if a in covered and m[sym['P_STATE']] == 2: continue
                        if hidden: mask, val = 0xFF, 0      # derriere un mur : on doit voir le decor
                        if m[a] != ((m[a - 0x8000] & mask) | val):
                            wrong += 1
                            if '-v' in sys.argv: print('      faux: sprite en (%d,%d) image %d, octet (%d,%d) ecran=%02X fond=%02X' % (r[0], r[1], r[4], bt, ln, m[a], m[a - 0x8000]))
            nocc = sum(1 for r in rects if r[4] is not None and m[sym['OCCY'] + r[1]])
            print('   sprites qui se chevauchent : %d paire(s) ; sprites verifies octet par octet : %d (dont %d pres des murs), octets faux : %d' % (over, checked, nocc, wrong))
            bad_total += wrong
            print('touche %d graine %d images %4d : ennemis en jeu %2d, octets fantomes %d %s' % (key, seed, frames, alive, len(bad), bad[:6]))
            bad_total += len(bad)
sys.exit(1 if bad_total else 0)
