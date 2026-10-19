#!/usr/bin/env python3
"""Musique du menu : assets/MusiqueMenu_AY.vgm (AY-3-8912, une image = 882 echantillons = 50 Hz) -> src/menu_music.asm
   1) etat des registres R0..R12 a chaque image (R13 inutilise) ; 2) flux "delta" : par image, 2 octets de masque (bit i = R_i change)
      puis les valeurs des registres changes ; la 1re image ecrit tous les registres (la boucle repart de zero)
   3) compression LZ maison, fenetre de 2048 octets (relue dans un anneau en #4800-#4FFF par le lecteur du menu) :
        0nnnnnnn           : n+1 octets litteraux (1..128)
        1LLLLooo oooooooo  : copie de LLLL+2 octets (3..17), distance ooo.oooooooo + 1 (1..2048)"""
import struct, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NREG = 13
WINDOW = 2048

def frames_from_vgm(fn):
    d = open(fn, 'rb').read()
    assert d[:4] == b'Vgm '
    pos = 0x34 + struct.unpack_from('<I', d, 0x34)[0]
    regs = [0] * 16
    frames = []
    samples = 0
    def tick(n):
        nonlocal samples
        samples += n
        while samples >= 882:
            samples -= 882
            frames.append(tuple(regs[:NREG]))
    while pos < len(d):
        c = d[pos]
        if c == 0xA0: regs[d[pos + 1] & 15] = d[pos + 2]; pos += 3
        elif c == 0x61: tick(struct.unpack_from('<H', d, pos + 1)[0]); pos += 3
        elif c == 0x62: tick(735); pos += 1
        elif c == 0x63: tick(882); pos += 1
        elif c == 0x66: break
        else: raise ValueError('commande VGM %02X' % c)
    return frames

def delta_stream(frames):
    prev = None; out = bytearray()
    for f in frames:
        mask = 0; vals = []
        for i in range(NREG):
            if prev is None or f[i] != prev[i]:
                mask |= 1 << i; vals.append(f[i])
        prev = f
        out += bytes([mask & 255, mask >> 8]) + bytes(vals)
    return bytes(out)

def lz_pack(data):
    n = len(data); INF = 1e18
    best = [INF] * (n + 1); best[0] = 0; ch = [None] * (n + 1)
    for i in range(n):
        c = best[i] + 1 + 1 / 16
        if c < best[i + 1]: best[i + 1] = c; ch[i + 1] = ('L', i)
        for o in range(1, min(WINDOW, i) + 1):
            l = 0
            while l < 17 and i + l < n and data[i + l - o] == data[i + l]: l += 1
            for k in range(3, l + 1):
                if best[i] + 2 < best[i + k]: best[i + k] = best[i] + 2; ch[i + k] = ('M', i, o, k)
    toks = []; p = n
    while p > 0:
        t = ch[p]; toks.append(t); p = t[1]
    toks.reverse()
    out = bytearray(); lits = bytearray()
    def flush():
        nonlocal lits
        while lits:
            c = lits[:128]; lits = lits[128:]
            out.append(len(c) - 1); out.extend(c)
    for t in toks:
        if t[0] == 'L': lits.append(data[t[1]])
        else:
            flush(); o = t[2] - 1
            out.append(0x80 | ((t[3] - 2) << 3) | (o >> 8)); out.append(o & 255)
    flush()
    return bytes(out)

def lz_unpack(c, n):                    # meme algorithme que le lecteur Z80 : sert a verifier
    out = bytearray(); i = 0
    while len(out) < n:
        t = c[i]; i += 1
        if t < 128:
            out += c[i:i + t + 1]; i += t + 1
        else:
            L = ((t >> 3) & 15) + 2; o = (((t & 7) << 8) | c[i]) + 1; i += 1
            for _ in range(L): out.append(out[-o])
    return bytes(out)

def build(path_out):
    frames = frames_from_vgm(os.path.join(ROOT, 'assets', 'MusiqueMenu_AY.vgm'))
    d = delta_stream(frames); c = lz_pack(d)
    assert lz_unpack(c, len(d)) == d
    with open(path_out, 'w') as f:
        f.write('; --- genere par tools/mkmusic.py : ne pas modifier a la main ---\n')
        f.write('; musique du menu : %d images (%.1f s), flux delta de %d octets, compresse en %d\n' % (len(frames), len(frames) / 50, len(d), len(c)))
        f.write('MUS_FRAMES equ %d\nmus_data:\n' % len(frames))
        for i in range(0, len(c), 16):
            f.write(' db ' + ','.join('#%02X' % b for b in c[i:i + 16]) + '\n')
        f.write('mus_end:\n')
    return frames, d, c

def build_raw(vgm, label, path_out, prefix='jn'):
    """jingle court : flux delta NON compresse (lu tel quel par le lecteur de l'ecran de mission) -> .asm ; rend (images, octets)"""
    return write_raw(frames_from_vgm(os.path.join(ROOT, 'assets', vgm)), label, path_out, prefix)

def write_raw(frames, label, path_out, prefix='jn'):
    d = delta_stream(frames)
    assert len(frames) < 65536
    with open(path_out, 'w') as f:
        f.write('; --- genere par tools/mkmusic.py : jingle %s : %d images (%.1f s), %d octets (flux delta non compresse) ---\n' % (label, len(frames), len(frames) / 50, len(d)))
        f.write('%s_FRAMES   equ %d\n%s_data:\n' % (prefix.upper(), len(frames), prefix))
        for i in range(0, len(d), 16):
            f.write(' db ' + ','.join('#%02X' % b for b in d[i:i + 16]) + '\n')
    return len(frames), len(d)

if __name__ == '__main__':
    fr, d, c = build(os.path.join(ROOT, 'src', 'menu_music.asm'))
    print(len(fr), 'images', len(d), '->', len(c))
