#!/usr/bin/env python3
"""Genere assets/MusiqueMarche_AY.vgm : marche militaire originale (A mineur, 150 bpm, ~51 s) pour AY-3-8912 (1 MHz, 50 images/s).
  voie A : basse (marche, puis galop) + arpege rapide en pont ; voie B : melodie (attaque, decroissance, vibrato) ;
  voie C : batterie (grosse caisse, caisse claire, charleston) et, entre les coups, arpege rapide de l'accord.
Plan : intro 4 mesures, A (8), B (8), pont (4), A' (8, une octave plus haut).   Usage : python3 tools/gen_marche.py"""
import struct, math
CLK = 1000000; FR = 5; S = 16
NOTE = {'C':0,'D':2,'E':4,'F':5,'G':7,'A':9,'B':11}
def midi(n):
    o = int(n[-1]); a = 1 if '#' in n else 0
    return 12*(o+1)+NOTE[n[0]]+a
def per(m): return max(2, min(4095, round(CLK/(16*440*2**((m-69)/12)))))
def seq(s):
    t = s.split(); assert len(t) == S, (len(t), s); return t
CH = {'A':'A3 C4 E4','F':'F3 A3 C4','G':'G3 B3 D4','C':'C4 E4 G4','E':'E3 G#3 B3','Em':'E3 G3 B3'}
ROOT = {'A':'A2','F':'F2','G':'G2','C':'C3','E':'E2','Em':'E2'}
FIFTH = {'A':'E3','F':'C3','G':'D3','C':'G2','E':'B2','Em':'B2'}
def up(m, k): return m+k
A = [("A","A4 = = A4 C5 = E5 = A5 = = = E5 = = ="),
     ("A","D5 = = D5 C5 = B4 = C5 = = = A4 = = ="),
     ("F","F4 = = F4 A4 = C5 = F5 = = = C5 = = ="),
     ("G","D5 = = D5 B4 = G4 = B4 = D5 = G5 = = -"),
     ("A","A4 = = A4 C5 = E5 = A5 = G5 = E5 = C5 ="),
     ("Em","B4 = = B4 E5 = G5 = B5 = = = G5 = E5 ="),
     ("F","A4 = C5 = F5 = = = E5 = D5 = C5 = A4 ="),
     ("E","G#4 = B4 = E5 = = = D5 = B4 = G#4 = = -")]
B = [("A","E5 = E5 = A5 = A5 = G5 = E5 = D5 = C5 ="),
     ("C","C5 = C5 = E5 = G5 = C6 = = = G5 = E5 ="),
     ("G","D5 = D5 = G5 = G5 = F5 = D5 = B4 = D5 ="),
     ("Em","E5 = G5 = B5 = = = A5 = G5 = E5 = - -"),
     ("A","A5 = = G5 A5 = C6 = B5 = A5 = E5 = = ="),
     ("F","A5 = = G5 F5 = A5 = C6 = A5 = F5 = = ="),
     ("E","G#5 = B5 = E6 = = = D6 = B5 = G#5 = = ="),
     ("E","E5 - E5 - E5 - E5 - B4 - B4 - B4 B4 - -")]
P = [("F","C5 = = = = = = = A4 = = = = = = ="),
     ("G","B4 = = = = = = = D5 = = = = = = ="),
     ("A","C5 = = = E5 = = = A5 = = = G5 = = ="),
     ("E","G#5 = = = B5 = = = E6 = D6 = B5 = G#5 =")]
I = [("A","- - - - - - - - - - - - - - - -")]*4
plan = [('intro', I), ('A', A), ('B', B), ('P', P), ('A2', A[4:])]
bars = []
for sec, rows in plan:
    for i, (ch, mel) in enumerate(rows): bars.append((sec, i, ch, seq(mel)))
def bass_pat(sec, ch, bi):
    r = midi(ROOT[ch]); f = midi(FIFTH[ch]); o = r+12
    if sec in ('A', 'A2', 'intro'):      # marche
        return [r,None,r,None,o,None,r,None, r,None,r,None,f,None,o,None]
    if sec == 'B':                        # galop
        return [r,r,o,r, r,r,o,r, r,r,o,r, f,f,o,f]
    return [r]+[None]*15                  # pont : pedale tenue
regs = [-1]*14; out = bytearray(); tot = 0
def w(r, v):
    v &= 255
    if regs[r] != v: regs[r] = v; out.extend((0xA0, r, v))
for bn, (sec, bi, ch, mel) in enumerate(bars):
    bp = bass_pat(sec, ch, bi)
    arp = [midi(n) for n in CH[ch].split()]
    lead_oct = 12 if sec == 'A2' else 0
    # melodie : note courante et age (en images)
    notes = []; cur = None; start = 0
    for st, t in enumerate(mel):
        if t == '=': pass
        elif t == '-': cur = None; start = st
        else: cur = midi(t)+lead_oct; start = st
        notes.append((cur, start))
    for st in range(S):
        for fr in range(FR):
            t = (st*FR+fr)                                  # image dans la mesure
            gf = bn*S*FR + t                                # image globale
            mix = 0b111111
            # --- voie A : basse
            b = bp[st]
            if sec == 'P':
                # pont : arpege rapide sur l'accord, volume qui respire
                m = arp[fr % 3]+12; p = per(m); w(0, p); w(1, p >> 8); w(8, 9 if (st & 3) else 11); mix &= ~1
            elif sec == 'intro' and bi < 2:
                p = per(midi('A2')); w(0, p); w(1, p >> 8); w(8, 11 if st % 4 else 13); mix &= ~1
            elif b:
                p = per(b); w(0, p); w(1, p >> 8); w(8, (14, 12, 11, 11, 11)[fr]); mix &= ~1
            else:
                w(8, 0)
            # --- voie B : melodie
            cur, s0 = notes[st]
            if cur is not None:
                age = (st-s0)*FR+fr
                p = per(cur)
                if age > 14:                                 # vibrato sur les notes tenues
                    p += (0, 1, 0, -1)[(age >> 1) & 3] * (1 + p // 400)
                vol = 14 if age < 3 else 12
                if sec == 'P': vol = 11 if age > 8 else 14
                # decroissance lente sur les longues tenues
                
                w(2, p); w(3, p >> 8); w(9, vol); mix &= ~2
            else: w(9, 0)
            # --- voie C : batterie / arpege
            kick = st in (0, 8) or (sec == 'B' and st == 10)
            snare = st in (4, 12)
            hat = (sec == 'B' and st % 2 == 1) or (sec in ('A', 'A2') and st in (2, 6, 10, 14))
            roll = (bi % 4 == 3 and st >= 12) or (sec == 'intro' and bi >= 2 and st % 2 == 1) or (sec == 'intro' and bi < 2 and bi == 1 and st >= 8 and st % 2 == 0)
            if sec == 'P' and not (bi == 3 and st >= 8): kick = snare = hat = roll = False
            if sec == 'intro' and bi < 2 and not roll: kick = snare = hat = False
            done = False
            if roll and fr < 3:
                w(6, 9+fr*2); w(10, 13-fr*3); mix &= ~32; done = True
            elif snare and fr < 4:
                w(6, 12+fr*3); w(10, (15, 13, 9, 6)[fr]); mix &= ~32; done = True
            elif kick and fr < 3:
                p = 90+fr*70; w(4, p); w(5, p >> 8); w(10, (15, 13, 9)[fr]); mix &= ~4; done = True
            elif hat and fr < 1:
                w(6, 2); w(10, 8); mix &= ~32; done = True
            if not done:
                m = arp[fr % 3]+12; p = per(m)
                if sec in ('P',): w(10, 0)
                else:
                    w(4, p); w(5, p >> 8); w(10, 6); mix &= ~4
            w(7, mix)
            out.append(0x63); tot += 882
out.append(0x66)
hdr = bytearray(open('assets/MusiqueNiveau_AY.vgm', 'rb').read()[:0x100])
f = bytearray(bytes(hdr)+bytes(out))
struct.pack_into('<I', f, 4, len(f)-4)
struct.pack_into('<I', f, 0x18, tot)
open('assets/MusiqueMarche_AY.vgm', 'wb').write(bytes(f))
print(len(f), 'octets', tot/44100, 's', tot//882, 'images')
