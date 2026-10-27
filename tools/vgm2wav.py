#!/usr/bin/env python3
"""Apercu approximatif d'un VGM AY (50 Hz) en WAV : python3 tools/vgm2wav.py in.vgm out.wav"""
import sys, wave, array, struct
d = open(sys.argv[1], 'rb').read(); i = 0x34 + struct.unpack_from('<I', d, 0x34)[0]
R = [0]*16; SR = 44100; out = array.array('h')
vol = [0, .008, .012, .017, .024, .034, .048, .068, .097, .137, .194, .275, .389, .55, .778, 1.0]
st = [0]*3; cnt = [0.0]*3; nc = 0.0; no = 1; lf = 1
def frame():
    global nc, no, lf
    for _ in range(882):
        s = 0
        for c in range(3):
            p = (R[c*2] | (R[c*2+1] & 15) << 8) or 1
            cnt[c] += (1000000/16/p)/SR
            while cnt[c] >= 1: cnt[c] -= 1; st[c] ^= 1
            if (st[c] or (R[7] >> c) & 1) and (no or (R[7] >> (c+3)) & 1): s += vol[R[8+c] & 15]
        nc += (1000000/16/((R[6] & 31) or 1))/SR
        if nc >= 1:
            nc -= 1; b = (lf ^ (lf >> 3)) & 1; lf = (lf >> 1) | (b << 16); no = lf & 1
        out.append(int(s*3500)-5000)
while True:
    c = d[i]
    if c == 0xA0: R[d[i+1] & 15] = d[i+2]; i += 3
    elif c == 0x63: frame(); i += 1
    else: break
w = wave.open(sys.argv[2], 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(out.tobytes()); w.close()
