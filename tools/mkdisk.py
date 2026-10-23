#!/usr/bin/env python3
"""Ecrit la cover et les zones (compressees) en secteurs bruts dans l'image DSK etendue produite par RASM.
   usage : mkdisk.py build/PAPICPC.dsk"""
import sys, os, json
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = sys.argv[1]
d = bytearray(open(path, 'rb').read())
ntr = d[0x30]; sizes = [d[0x34 + i] * 256 for i in range(ntr * d[0x31])]
def extend(n):
    """RASM ne formate que les pistes utilisees par le fichier : on ajoute des pistes (copie de la derniere : 9 secteurs de 512, remplis de #E5) jusqu'a la piste n incluse (42 pistes au plus)"""
    global sizes, off
    last = max(i for i, v in enumerate(sizes) if v)
    global ntr
    maxtrk = int(os.environ.get('PAPI_MAXTRK', '44'))          # 44 pistes depuis la zone 5 (un lecteur CPC 3 pouces en lit 42) ; PAPI_MAXTRK=42 pour verifier la limite
    assert n < max(maxtrk, ntr * d[0x31]), 'la disquette depasse %d pistes' % max(maxtrk, ntr * d[0x31])
    if n >= ntr * d[0x31]:
        sizes += [0] * (n + 1 - len(sizes)); ntr = n + 1; d[0x30] = ntr
    while last < n:
        last += 1
        blk = bytearray(d[off[last - 1]:off[last - 1] + sizes[last - 1]])
        blk[0x10] = last
        for k in range(9): blk[0x18 + 8 * k] = last          # C des identificateurs de secteur = numero de piste
        for k in range(9): blk[0x100 + k * 512:0x100 + (k + 1) * 512] = bytes([0xE5]) * 512
        d[0x34 + last] = sizes[last - 1] // 256
        sizes[last] = sizes[last - 1]
        d[off[last]:off[last]] = blk              # (les pistes suivantes sont vides : off[last] = fin du fichier)
        off = [0x100]
        for sz in sizes: off.append(off[-1] + sz)
off = [0x100]
for s in sizes: off.append(off[-1] + s)
def put(track, data, sec0=0):
    for i in range(0, len(data), 512):
        t, sec = track + (sec0 + i // 512) // 9, (sec0 + i // 512) % 9
        blk = off[t]; assert d[blk + 0x15] == 9
        base = blk + 0x100 + sec * 512
        d[base:base + 512] = data[i:i + 512].ljust(512, b'\0')
lay = json.load(open(os.path.join(ROOT, 'build', 'layout.json')))
extend(max(e['track'] + (e.get('sector', 0) + -(-e['data'] // 512) - 1) // 9 for e in lay.values()))
for name, e in lay.items():
    fn = 'cover.bin' if name == 'cover' else name + '.bin'
    if name == 'boss':                  # image de la banque 7 = code (RASM) + voix + images des vehicules, aux decalages VOICE_OFF et TRUCK_OFF (convert.py)
        sys.path.insert(0, os.path.join(ROOT, 'tools'))
        import convert as cv
        code = open(os.path.join(ROOT, 'build', 'boss_code.bin'), 'rb').read()
        voice = open(os.path.join(ROOT, 'build', 'voice.bin'), 'rb').read(); trucks = open(os.path.join(ROOT, 'build', 'trucks.bin'), 'rb').read()
        assert len(code) <= cv.VOICE_OFF and len(voice) == cv.VOICE_LEN
        img = code.ljust(cv.VOICE_OFF, b'\0') + voice
        img = img.ljust(cv.TRUCK_OFF, b'\0') + trucks
        assert len(img) <= 0x4000
        open(os.path.join(ROOT, 'build', 'boss.bin'), 'wb').write(img)
    data = open(os.path.join(ROOT, 'build', fn), 'rb').read()
    if name == 'boss':                  # banque 7 : image compressee (decompressee sur place au demarrage, voir ovlb_load) ; lue en BOSS_LOAD + BOSS_PAD
        sys.path.insert(0, os.path.join(ROOT, 'tools'))
        import convert as cv
        comp = cv.lz_compress(data); assert cv.lz_decompress(comp) == data
        pad = cv.inplace_offset(comp, len(data))
        assert pad <= cv.BOSS_PAD and len(comp) <= cv.BOSS_N * 512, 'banque 7 : %d octets compresses, decalage %d (maxi %d / %d)' % (len(comp), pad, cv.BOSS_N * 512, cv.BOSS_PAD)
        print('banque 7 : %d -> %d octets compresses, decalage sur place %d' % (len(data), len(comp), pad))
        data = comp
    put(e['track'], data, e.get('sector', 0))
    print('disquette : %-6s piste %2d, %2d secteurs' % (name, e['track'], -(-len(data) // 512)))
open(path, 'wb').write(d)
