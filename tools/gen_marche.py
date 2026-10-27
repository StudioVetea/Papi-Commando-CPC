#!/usr/bin/env python3
"""Genere assets/MusiqueMarche_AY.vgm : marche militaire originale (A mineur, 150 bpm) pour AY-3-8912, dans l'esprit des musiques d'action CPC de 1985.
Usage : python3 tools/gen_marche.py"""
import struct
CLK=1000000; FR=5   # 1 double-croche = 5 images (150 bpm)
N={'C':0,'D':2,'E':4,'F':5,'G':7,'A':9,'B':11}
def hz(n):
    p=n[0]; o=int(n[-1]); a=1 if '#' in n else 0
    m=12*(o+1)+N[p]+a
    return 440*2**((m-69)/12)
def per(n): return max(1,min(4095,round(CLK/(16*hz(n)))))
def seq(s): return [None if t=='-' else t for t in s.split()]
S=16
# progression (1 mesure = 16 pas) : racine de basse, puis accord pour l'arpege
prog=[('A2','A'),('A2','A'),('F2','F'),('G2','G'),('A2','A'),('A2','A'),('E2','E'),('E2','E')]
chords={'A':['A3','C4','E4'],'F':['F3','A3','C4'],'G':['G3','B3','D4'],'E':['E3','G#3','B3']}
def bass(root):
    r=root; f=root[0]+'3' if False else None
    o=int(root[-1]); fifth={'A':'E','F':'C','G':'D','E':'B'}[root[0]]+str(o+(0 if root[0] in 'AFG' and fifth_ok(root) else 0))
    return r,fifth
def fifth_ok(r): return True
def bar_bass(root):
    n=root[0]; o=int(root[-1])
    fif={'A':'E3','F':'C3','G':'D3','E':'B2'}[n]
    oct_=n+str(o+1)
    p=[root,None,root,None,oct_,None,root,None, root,None,root,None,fif,None,oct_,None]
    return p
# melodie : 8 mesures (A) puis 8 mesures (B) ; '-' = silence, '=' = tenue
A=["A4 - - A4 C5 - E5 -  D5 - C5 - A4 - - -",
   "A4 - - A4 C5 - E5 -  G5 - E5 - C5 - - -",
   "F4 - - F4 A4 - C5 -  B4 - A4 - F4 - - -",
   "G4 - - G4 B4 - D5 -  E5 - D5 - B4 - G4 -",
   "A4 - - A4 C5 - E5 -  D5 - C5 - A4 - - -",
   "C5 - - C5 E5 - A5 -  G5 - E5 - C5 - - -",
   "B4 - B4 - E5 - E5 -  G#5 - E5 - B4 - - -",
   "E5 - - - D5 - C5 - B4 - - - - - - -"]
B=["E5 - E5 - E5 D5 C5 - A4 - A4 - A4 B4 C5 -",
   "D5 - D5 - D5 C5 B4 - G4 - G4 - G4 A4 B4 -",
   "C5 - C5 - C5 B4 A4 - F4 - F4 - A4 - C5 -",
   "D5 - D5 - E5 - F5 - G5 - - - D5 - B4 -",
   "E5 - E5 - E5 D5 C5 - A4 - A4 - A4 B4 C5 -",
   "A5 - - G5 - - E5 - C5 - D5 - E5 - - -",
   "G#5 - G#5 - B5 - G#5 - E5 - - - B4 - - -",
   "A4 A4 - A4 A4 - A4 - A4 - - - - - - -"]
def lead(rows):
    out=[]
    for r in rows:
        t=seq(r); assert len(t)==S,(len(t),r); out+=t
    return out
# frames
frames=[]
def arp(ch,b):
    c=chords[ch]; return [c[(b//1)%3] if True else None]
nbar=16
lead_a=lead(A); lead_b=lead(B)
for bar in range(nbar):
    root,ch=prog[bar%8]
    bs=bar_bass(root)
    L=(lead_a if bar<8 else lead_b)[(bar%8)*S:(bar%8+1)*S]
    # percussion : grosse caisse pas 0 et 8, caisse claire pas 4 et 12, roulement en fin de mesure 3/7
    for st in range(S):
        ev=dict(bass=bs[st],lead=L[st],arp=chords[ch][st%3],step=st,bar=bar)
        for fr in range(FR):
            frames.append((ev,fr))
regs=[0]*14
out=bytearray()
def w(r,v):
    global out
    if regs[r]!=v or r==13:
        regs[r]=v; out+=bytes([0xA0,r,v])
regs=[-1]*14
tot=0
for ev,fr in frames:
    # voie A : basse (carre) ; voie B : melodie avec petit vibrato ; voie C : percussion + arpege entre les temps
    b=ev['bass']; l=ev['lead']; st=ev['step']; bar=ev['bar']
    mix=0b111111  # 1 = coupe ; bits 0-2 tons A,B,C ; bits 3-5 bruit A,B,C
    if b:
        p=per(b); w(0,p&255); w(1,p>>8); vol=12-min(fr,4)*1; w(8,max(8,vol)); mix&=~1
    else: w(8,0)
    if l:
        base=per(l); p=base+(1 if (fr>=2 and (fr&1)) else 0)*0
        # vibrato leger sur les notes tenues longtemps : desaccord de 1 sur images paires
        p=base+(((fr+st)&1) if base>40 else 0)
        w(2,p&255); w(3,p>>8); v=13 if fr<3 else 11; w(9,v); mix&=~2
    else: w(9,0)
    perc=None
    if st in (0,8): perc='kick'
    elif st in (4,12): perc='snare'
    elif bar%4==3 and st>=12: perc='roll'
    elif st%2==1: perc='tick'
    if perc=='kick':
        p=60+fr*40; w(4,p&255); w(5,p>>8); w(10,15-fr*3 if fr<5 else 0); mix&=~4
    elif perc=='snare':
        w(6,10+fr*2); w(10,max(0,14-fr*3)); mix&=~32
    elif perc=='roll':
        w(6,8); w(10,10 if fr%2==0 else 6); mix&=~32
    elif perc=='tick':
        w(6,3); w(10,6 if fr<1 else 0); mix&=~32
    else: w(10,0)
    w(7,mix)
    out+=b'\x63'
    tot+=882
out+=b'\x66'
hdr=bytearray(open('assets/MusiqueNiveau_AY.vgm','rb').read()[:0x100])
data=bytes(out)
file=bytes(hdr)+data
file=bytearray(file)
struct.pack_into('<I',file,4,len(file)-4)
struct.pack_into('<I',file,0x18,tot)
struct.pack_into('<I',file,0x1c,0x100+0*0-0x1c) if False else None
open('assets/MusiqueMarche_AY.vgm','wb').write(bytes(file))
print(len(file),'octets',tot/44100,'s')
