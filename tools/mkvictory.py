#!/usr/bin/env python3
"""Fanfare de victoire de la zone 3 (composee ici, AY-3-8912, 50 images/s) : images R0..R12 -> utilise par convert.py (mkmusic.write_raw).
   Do majeur, 187 pulsations/min : melodie (canal A), arpege rapide (B), basse + caisse claire (C)."""
E8 = 8                      # une croche = 8 images (0,16 s)
def hz(m): return 440.0 * 2 ** ((m - 69) / 12)
def per(m): return max(1, min(4095, round(1000000 / (16 * hz(m)))))
C, D, E, F, G, A, B = 0, 2, 4, 5, 7, 9, 11
def n(o, k): return 12 * (o + 1) + k
# melodie : (hauteur MIDI ou None, croches)
MEL = [(n(5,C),1),(n(5,E),1),(n(5,G),2),(n(5,E),1),(n(5,G),1),(n(6,C),2),            # Do
       (n(5,A),1),(n(6,C),1),(n(6,F),2),(n(6,E),1),(n(6,D),1),(n(5,B),2),            # Fa -> Sol
       (n(5,G),1),(n(6,C),1),(n(6,E),2),(n(6,G),2),(n(6,E),1),(n(6,C),1)]            # Do : fin tenue
MEL += [(n(6,C),4)]
# accords (notes de l'arpege) et basse : une entree par croche
CH = {'C': [n(4,C), n(4,E), n(4,G)], 'F': [n(4,F), n(4,A), n(5,C)], 'G': [n(4,G), n(4,B), n(5,D)]}
BASS = {'C': n(2,C), 'F': n(2,F), 'G': n(2,G)}
PROG = ['C']*8 + ['F']*4 + ['G']*4 + ['C']*8
PROG += ['C']*4
def frames():
    total = sum(d for _, d in MEL) * E8
    out = []
    # temps absolu -> note melodie
    mel = []
    for m, d in MEL: mel += [(m, i) for i in range(d * E8)] 
    for t in range(total):
        e8, ft = divmod(t, E8)
        ch = PROG[min(e8, len(PROG) - 1)]
        r = [0] * 13
        # canal A : melodie, volume qui retombe sur chaque note
        m, i = mel[t]
        pa = per(m); r[0], r[1] = pa & 255, pa >> 8
        last = t >= total - 4 * E8
        va = 13 if i < 4 else 11 if i < 8 else 9
        if last: va = max(0, 13 - (t - (total - 4 * E8)) // 4)
        r[8] = va
        # canal B : arpege rapide (1 note par image), caisse claire (bruit) sur les temps faibles
        arp = CH[ch][t % 3]
        pb = per(arp + 12); r[2], r[3] = pb & 255, pb >> 8
        snare = (e8 % 2 == 1 and ft < 3) and not last
        r[9] = 8 if not last else max(0, 9 - (t - (total - 4 * E8)) // 5)
        # canal C : basse (octave grave, staccato) sur les temps forts, grosse caisse
        pc = per(BASS[ch]); r[4], r[5] = pc & 255, pc >> 8
        r[10] = (12 - 2 * ft if ft < 6 else 0) if e8 % 2 == 0 else (6 if ft < 2 else 0)
        if last: r[10] = max(0, 12 - (t - (total - 4 * E8)) // 4)
        r[6] = 12 if snare else 6
        r[7] = 0b101010 if snare else 0b111000              # bits 0-2 : tons (0 = ouvert), bits 3-5 : bruit ; caisse claire : bruit seul sur B
        if snare: r[9] = 13
        out.append(tuple(r))
    return out
if __name__ == '__main__':
    f = frames(); print(len(f), 'images', len(f) / 50, 's')
