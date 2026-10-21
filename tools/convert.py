#!/usr/bin/env python3
"""Convertit les PNG / la carte Tiled en donnees MODE 0 : fichiers de RASM (src/*.asm, *.inc) et fichiers
de donnees chargees depuis la disquette (build/cover.bin, build/zone1.bin).

    python3 tools/convert.py

Entrees (dossier assets/) : PapiCPC_12x12.png, SoldatC++_12x12.png, TileSet1.png,
TileSet1Obstacle.png, Explosion12x12.png, Grenade_4x6.png, Balle2x6.png, ZoneTest.tmx
Necessite Pillow (pip install pillow).
"""
import os, re, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, 'assets')
OUT = os.path.join(ROOT, 'src', 'gfx.asm')
import json
BUILD = os.path.join(ROOT, 'build')

# numero de couleur firmware -> numero materiel du Gate Array
HW = [0x54,0x44,0x55,0x5C,0x58,0x5D,0x4C,0x45,0x4D,0x56,0x46,0x57,0x5E,0x40,0x5F,
      0x4E,0x47,0x4F,0x52,0x42,0x53,0x5A,0x59,0x5B,0x4A,0x43,0x4B]
# encres du jeu : stylo -> couleur firmware (14 couleurs utilisees par les assets)
PENS = [0, 3, 6, 7, 9, 10, 12, 13, 15, 16, 21, 24, 25, 26, 1, 2]   # stylo 14 = bleu (officier), 15 = bleu vif (bandeau)
TRANSP = (255, 0, 210)

def fw_of(rgb):
    lv = {0: 0, 128: 1, 255: 2}
    r, g, b = rgb
    return lv[b] + 3 * lv[r] + 9 * lv[g]

SUBST = {18: 21, 11: 2, 20: 26, 23: 26, 5: 2, 14: 13}      # vert vif (General) -> citron vert : le jeu n'a que 16 stylos, tous utilises

def load(name):
    """-> grille [y][x] de stylos (None = transparent)"""
    im = Image.open(os.path.join(A, name)).convert('RGB')
    w, h = im.size
    px = im.load()
    out = []
    for y in range(h):
        row = []
        for x in range(w):
            c = px[x, y]
            if c == TRANSP:
                row.append(None)
            else:
                fw = fw_of(c)
                if fw in SUBST and fw not in PENS: fw = SUBST[fw]
                if fw not in PENS:
                    sys.exit(f'{name}: couleur firmware {fw} absente de PENS')
                row.append(PENS.index(fw))
        out.append(row)
    return out

def enc(p0, p1):
    """2 pixels MODE 0 -> 1 octet ecran"""
    b = 0
    if p0 & 1: b |= 0x80
    if p0 & 2: b |= 0x08
    if p0 & 4: b |= 0x20
    if p0 & 8: b |= 0x02
    if p1 & 1: b |= 0x40
    if p1 & 2: b |= 0x04
    if p1 & 4: b |= 0x10
    if p1 & 8: b |= 0x01
    return b

def opaque(g, x0, y0, wpx, h):
    out = []
    for y in range(h):
        for x in range(0, wpx, 2):
            out.append(enc(g[y0 + y][x0 + x] or 0, g[y0 + y][x0 + x + 1] or 0))
    return out

def masked(g, x0, y0, wpx, h, zigzag=False):
    """-> paires (masque, donnee) : ecran = (fond AND masque) OR donnee
    zigzag : les lignes impaires sont rangees de droite a gauche (la routine
    d'affichage balaie l'ecran en aller-retour pour ne jamais "revenir a la ligne")"""
    out = []
    for y in range(h):
        line = []
        for x in range(0, wpx, 2):
            p0, p1 = g[y0 + y][x0 + x], g[y0 + y][x0 + x + 1]
            m = (0xAA if p0 is None else 0) | (0x55 if p1 is None else 0)
            line.append([m, enc(p0 or 0, p1 or 0)])
        if zigzag and (y & 1):
            line.reverse()
        for pr in line:
            out += pr
    return out

def db(f, data, per=16):
    for i in range(0, len(data), per):
        f.write(' db ' + ','.join('#%02X' % v for v in data[i:i + per]) + '\n')

# ---------------------------------------------------------------- police 3x5
FONT = {
 '0':'111101101101111','1':'010110010010111','2':'111001111100111','3':'111001111001111',
 '4':'101101111001001','5':'111100111001111','6':'111100111101111','7':'111001010010010',
 '8':'111101111101111','9':'111101111001111',' ':'000000000000000',
 'A':'111101111101101','C':'111100100100111','E':'111100110100111','G':'111100101101111',
 'I':'111010010010111','M':'101111111101101','N':'111101101101101','O':'111101101101111',
 'P':'111101111100100','R':'111101110101101','S':'111100111001111','V':'101101101101010',
 'U':'101101101101111','T':'111010010010010','F':'111100110100100','L':'100100100100111',
 'D':'110101101101110','-':'000000111000000','H':'101101111101101','K':'101101110101101',
 'X':'101101010101101','%':'101001010100101','Z':'111001010100111','!':'010010010000010','.':'000000000000010','Y':'101101010010010','+':'000010111010000','B':'110101110101110',
 'J':'001001001101010','Q':'010101101101011','W':'101101101111101','<':'010100111100010',
}
HEART = [[0, 2, 2, 0, 0, 2, 2, 0],
         [2, 13, 2, 2, 2, 2, 2, 1],
         [2, 2, 2, 2, 2, 2, 2, 1],
         [2, 2, 2, 2, 2, 2, 1, 1],
         [0, 2, 2, 2, 2, 2, 1, 0],
         [0, 0, 2, 2, 2, 1, 0, 0],
         [0, 0, 0, 2, 1, 0, 0, 0],
         [0, 0, 0, 0, 0, 0, 0, 0]]
FONT_ORDER = "0123456789 ACEGIMNOPRSVUTFLD-HKZ!.Y+BQW"   # (X et % : plus utilises par le jeu, restent dans FONT pour le bandeau du menu)


# ---------------------------------------------------------------- compression (format maison, proche de LZ4)
#  sequence = jeton (nibble haut : octets litteraux, nibble bas : longueur de copie - 4 ; 15 = suite en octets,
#  chacun ajoute jusqu'a un octet different de 255), les litteraux, puis decalage sur 2 octets (poids faible d'abord)
#  et suite eventuelle de la longueur. Un decalage nul termine le flux.  Decompresseur : unpack (src/papicpc.asm).
def lz_compress(data):
    n = len(data); out = bytearray(); chains = {}
    def ext(v):
        b = bytearray()
        while v >= 255: b.append(255); v -= 255
        b.append(v); return b
    def best(pos):
        if pos + 4 > n: return (0, 0)
        key = bytes(data[pos:pos + 4]); bl, bo = 0, 0
        for cand in reversed(chains.get(key, [])):
            if pos - cand > 65535: break
            l = 0
            while pos + l < n and data[cand + l] == data[pos + l]: l += 1
            if l > bl: bl, bo = l, pos - cand
        return (bl, bo)
    mt = [(0, 0)] * (n + 1)
    for i in range(n):
        mt[i] = best(i)
        if i + 4 <= n: chains.setdefault(bytes(data[i:i + 4]), []).append(i)
    # parcours optimal (programmation dynamique) : cout en octets, litteral = 1, copie = 3 (jeton + decalage) + 1 par 255 de longueur > 19
    INF = 1 << 60
    cost = [INF] * (n + 1); cost[n] = 0; nxt = [None] * (n + 1)
    for i in range(n - 1, -1, -1):
        cost[i] = cost[i + 1] + 1; nxt[i] = (1, 0)
        l, o = mt[i]
        for L in range(4, l + 1):
            c = cost[i + L] + 3 + (L - 4 - 15) // 255 + 1 if L - 4 >= 15 else cost[i + L] + 3
            if c <= cost[i]: cost[i] = c; nxt[i] = (L, o)
    def emit(lits, mlen, moff):
        tok = (min(len(lits), 15) << 4) | (0 if mlen == 0 else min(mlen - 4, 15))
        out.append(tok)
        if len(lits) >= 15: out.extend(ext(len(lits) - 15))
        out.extend(lits)
        out.append(moff & 255); out.append(moff >> 8)
        if mlen and mlen - 4 >= 15: out.extend(ext(mlen - 4 - 15))
    i = 0; lit0 = 0
    while i < n:
        L, o = nxt[i]
        if L == 1: i += 1; continue
        emit(data[lit0:i], L, o); i += L; lit0 = i
    emit(data[lit0:n], 0, 0)
    return bytes(out)

def lz_decompress(comp, expect=None):
    out = bytearray(); p = 0
    def ln(v):
        nonlocal p
        if v == 15:
            while True:
                b = comp[p]; p += 1; v += b
                if b != 255: break
        return v
    while True:
        tok = comp[p]; p += 1
        lit = ln(tok >> 4); out += comp[p:p + lit]; p += lit
        off = comp[p] | (comp[p + 1] << 8); p += 2
        if off == 0: break
        m = ln(tok & 15) + 4
        for _ in range(m): out.append(out[-off])
    return bytes(out)

def inplace_offset(comp, raw_len):
    """decalage P (octets apres le debut de la destination) ou placer les donnees compressees pour que le
    decompresseur n'ecrase jamais ce qu'il n'a pas encore lu : produit <= consomme a chaque fin de sequence"""
    p = 0; prod = 0; need = 0
    def ln(v):
        nonlocal p
        if v == 15:
            while True:
                b = comp[p]; p += 1; v += b
                if b != 255: break
        return v
    while True:
        tok = comp[p]; p += 1
        lit = ln(tok >> 4); p += lit; prod += lit
        off = comp[p] | (comp[p + 1] << 8); p += 2
        if off == 0: need = max(need, prod - p); break
        prod += ln(tok & 15) + 4
        need = max(need, prod - p)
    assert prod == raw_len
    return max(0, need) + 4

# ---------------------------------------------------------------- disposition de la disquette
COVER_TRK = 10                        # pistes de donnees brutes (les fichiers AMSDOS occupent les pistes 0 a 9)
ZSTAGE = 0x4800                       # zone de preparation de la zone en RAM (libre avant la construction du miroir)
COVER_LOAD = 0x5000                   # la cover compressee est lue ici (apres le code de demarrage), puis decompressee dans l'ecran
SPRSLOT = 13                          # images de sprites par trou de la page video A
SLOT0_ZONE = 36                       # emplacements 0..34 : Papi (30), explosions (4) et caisse de grenades (1), residents
# disposition fixe d'un fichier de zone (decompresse)
H_SIZE, Z_SPAWN, Z_TILEMAP, Z_TKIND, Z_FRAMES, Z_TILES = 96, 96, 160, 472, 512, 872   # 5 tables d'images (soldat, officier, general, boss : corps, tete)
Z_ICON = Z_SPAWN + 32                  # 32 octets : tuile 8x8 de l'icone de mission (remplace celle de 'tuer')
NXS = 7                                # emplacements d'images supplementaires, dans la partie permanente (voir XSLOT_BASE) : 144 octets chacun
XSLOT_BASE = 0x3000 - NXS * 144
INTRO_LOAD = 0x4000                    # overlay des ecrans de mission et du bandeau
INTRO_N = 4                            # secteurs de l'overlay des ecrans de mission
MENU_LOAD = 0x5000                     # overlay du menu principal (lu sur la disquette)
MENU_N = 18                            # secteurs reserves a l'overlay (code, titre, sprites de la poursuite)
Z_SPR = Z_TILES + 40 * 48             # 2648 : les tuiles occupent toujours 40 emplacements

# types d'unites : fiche de caracteristiques (le moteur ne connait plus que ces nombres)
#   fire : images entre deux tirs (multiples de 16 : l'ennemi reflechit toutes les 16 images, et 8 bits) ; hp : points de vie ;
#   pts : points / 10 ; spd : decalage dans les tables de vitesse (0 normal, 32 rapide) ; gren : lance des grenades
UNITS = {
    1: dict(name='soldat',   sheet='SoldatC++_12x12.png',  fire=240, hp=1, pts=1, spd=0,  gren=0, cls=1),
    2: dict(name='officier', sheet='OfficierC___12x12.png', fire=144, hp=2, pts=2, spd=0,  gren=1, cls=2),
    3: dict(name='general',  sheet='GeneralC___12x12.png', fire=80,  hp=3, pts=5, spd=32, gren=0, cls=3),
    # BOSS (12 x 24) : deux places d'ennemi empilees. 4 = le corps (pieds : c'est lui qui reflechit, marche et tire), 5 = la tete,
    # collee au-dessus (12 lignes plus haut). La planche fait 12 x 24 par image ; les 4 images de mort sont des explosions.
    4: dict(name='boss_corps', sheet='BossCaporal_12x24.png', half=1, fire=96, hp=30, pts=20, spd=0, gren=0, cls=4),
    5: dict(name='boss_tete',  sheet='BossCaporal_12x24.png', half=0, fire=240, hp=30, pts=0, spd=0, gren=0, cls=4),
}
# apparition des ennemis : (colonne de tuile, y en lignes). Zone d'essai : haut au milieu (y = 0), haut des cotes a 3 rangees
# du bord (y = 20), puis beaucoup plus bas de chaque cote mais bien au-dessus de Papi (y = 108)
SPAWN_TEST = [(6, 0), (7, 0), (0, 20), (12, 20), (0, 108), (12, 108)]
ZINFO = {1: dict(title='OUTPOST C-01', tmx='ZoneTest.tmx', tileset='TileSet1.png', obstacle='TileSet1Obstacle.png', spawn=None),
         2: dict(title='THE LOST BARRACKS', tmx='Zone2.tmx', tileset='TileSet3.png', obstacle='TileSet3Obstacles.png', spawn='auto', first=1),
         # zone 3 : 2 tilesets (numeros de tuile 1-40 : TileSet1, 41-80 : TileSet2) ; l'eau (carre rose des obstacles) s'anime sur 3 images (1 2 3 2)
         3: dict(title='HIDDEN HEADQUARTER', tmx='Zone3.tmx', tileset=['TileSet1.png', 'TileSet2.png'], obstacle=['TileSet1Obstacle.png', 'TileSet2Obstacles.png'],
                 spawn='auto', first=1, water='Eau_3frames_12x8.png'),
         # zone 4 : 1 tileset (numeros de tuile 117-156 dans le TMX), eau, bidons explosifs (carre blanc) et routes (carre noir) ; les ennemis viennent des vehicules (veh)
         4: dict(title='TWIN ROADS', tmx='Zone4.tmx', tileset='TileSet4.png', obstacle='TileSet4Obstacles.png', spawn='auto', first=1, water='Eau_3frames_12x8.png',
                 gid0=117, flame='Flamme_3frames_12x8_Z4.png')}
def _m(n, units, mix, kills=None, count=(), time=None, art=(), show_units=True, boss=None, text=None, zn=1, z80=0, veh=0, hp=None):
    zi = ZINFO[zn]
    if veh >= 2: units += 2                     # vehicule a barre de vie : 2 places d'ennemi factices (0 et 1, jamais utilisees : elles font cesser les hooks du boss) + les unites transportees
    z = dict(name='zone%02d' % n, zn=zn, spawn_first=zi.get('first', 0), mnum=n, z80=z80, title=zi['title'], units=units, kills=time if time else kills, mix=mix, count=set(count), time=bool(time),
             art=list(art), units_shown=show_units, cover=25, spawn=zi['spawn'] or SPAWN_TEST, tmx=zi['tmx'], tileset=zi['tileset'], obstacle=zi['obstacle'], boss=boss, water=zi.get('water'), veh=veh, hp=hp, gid0=zi.get('gid0', 1), flame=zi.get('flame'))
    if time: z['text'] = ['TIME ATTACK !', 'SURVIVE %d S.' % time]
    else:
        noun = {(1,): 'SOLDIERS', (2,): 'OFFICERS', (3,): 'GENERALS'}.get(tuple(sorted(count)), 'ENEMIES')
        z['text'] = ['KILL %d %s.' % (kills, noun)]
    if text: z['text'] = text
    return z
# Zone 1 "Outpost C-01" : 5 missions (cahier des charges de la zone 1).  units = unites maxi a l'ecran ; mix = (type, %) ; count = types qui comptent pour le quota
#   types : 1 soldat, 2 officier, 3 general ; Time Attack : survivre (secondes), les kills ne comptent pas.
#   Mission du boss : boss=dict(...) ; 'units' compte le corps et la tete du boss (2 places) + sa garde (le reste) ; 'kills' = ses points de vie,
#   que le bandeau affiche (vert > jaune > orange > rouge selon le pourcentage restant) ; le quota est atteint quand il tombe a 0.
BOSS_PNG = 'BossCaporal_12x24.png'
ZONES = [
    _m(1, 5, [(1, 100)], kills=15, count=(1,)),
    _m(2, 5, [(1, 100)], time=30),
    _m(3, 6, [(1, 100)], kills=25, count=(1,)),
    _m(4, 7, [(1, 100)], kills=15, count=(1,), z80=1, text=['FIND THE Z80 !'], show_units=False,
       art=[dict(unit=1, x=16),
            dict(unit=1, x=26),
            dict(png='Z80_12x12.png', fw=12, fh=12, frames=1, x=36, walk=True),
            dict(unit=1, x=46),
            dict(unit=1, x=56)]),
    _m(5, 6, [(1, 100)], kills=30, show_units=False, boss=dict(hp=30), text=['KILL CAPORAL', 'GARATONKU !'],
       art=[dict(png='SoldatC++_12x12.png', fw=12, fh=12, frames=4, x=24, y=148, walk=True),
            dict(png=BOSS_PNG, fw=12, fh=24, frames=4, x=36, y=136, walk=True),
            dict(png='SoldatC++_12x12.png', fw=12, fh=12, frames=4, x=48, y=148, walk=True)]),
    # Zone 2 "The Lost Barracks" (cahier des charges de la zone 2) ; mission 4 : z80=nombre de kills apres lequel le Z80 apparait
    _m(1, 5, [(1, 80), (2, 20)], kills=25, count=(1,), zn=2),
    _m(2, 6, [(1, 80), (2, 20)], time=45, zn=2),
    _m(3, 6, [(1, 70), (2, 30)], kills=15, count=(2,), zn=2),
    _m(4, 6, [(1, 60), (2, 40)], kills=20, count=(1, 2), zn=2, z80=1, text=['FIND THE Z80 !'], show_units=False,
       art=[dict(unit=1, x=16),
            dict(unit=2, x=26),
            dict(png='Z80_12x12.png', fw=12, fh=12, frames=1, x=36, walk=True),
            dict(unit=1, x=46),
            dict(unit=2, x=56)]),
    # Mission finale : Capitaine DanTaGoul (35 PV, +15 % de vitesse, un tir par seconde, 5 s a couvert) + 3 officiers
    _m(5, 5, [(2, 100)], kills=35, show_units=False, zn=2, text=['KILL CAPTAIN', 'DANTAGOUL !'],
       boss=dict(hp=35, sheet='BossCapitaine_12x24.png', spd=32, burst=1, delay=50, cover=250, pts=35),
       art=[dict(unit=2, x=26, y=148, walk=True),
            dict(png='BossCapitaine_12x24.png', fw=12, fh=24, frames=4, x=36, y=136, walk=True),
            dict(unit=2, x=46, y=148, walk=True)]),
    # Zone 3 "Hidden Headquarter" (cahier des charges de la zone 3) 
    _m(1, 6, [(2, 80), (3, 20)], kills=25, count=(2,), zn=3),
    _m(2, 6, [(1, 70), (3, 30)], time=45, zn=3),
    _m(3, 6, [(2, 60), (3, 40)], kills=25, count=(2, 3), zn=3, z80=1, text=['FIND THE Z80 !'], show_units=False,
       art=[dict(unit=2, x=16),
            dict(unit=3, x=26),
            dict(png='Z80_12x12.png', fw=12, fh=12, frames=1, x=36, walk=True),
            dict(unit=2, x=46),
            dict(unit=3, x=56)]),
    _m(4, 7, [(2, 60), (3, 40)], kills=20, count=(3,), zn=3),
    # Mission finale : General Falzar (45 PV, +15 % de plus que les generaux, rafales de 3 balles, pas de grenade) + 4 generaux
    _m(5, 5, [(3, 100)], kills=45, show_units=False, zn=3, text=['KILL GENERAL', 'FALZAR !'],
       boss=dict(hp=45, sheet='BossFalzar_12x24.png', spd=64, burst=3, delay=50, cover=250, pts=50),
       art=[dict(unit=3, x=26, y=148, walk=True),
            dict(png='BossFalzar_12x24.png', fw=12, fh=24, frames=4, x=36, y=136, walk=True),
            dict(unit=3, x=46, y=148, walk=True)]),
    # Zone 4 "Twin roads" (cahier des charges de la zone 4) : les ennemis sortent des vehicules (veh : 1 = camion de troupes, mission a quota ou chrono ; 2 = camion, barre de vie, victoire
    #   normale ; 3 = WarTruck, barre de vie, rafales, fin de zone). 'units' = unites transportees au maximum a l'ecran ; hp = points de vie du vehicule (kills = hp pour les modes 2 et 3)
    _m(1, 5, [(1, 100)], kills=50, zn=4, veh=2, hp=50, text=['DESTROY THE', 'ARMY TRUCK !'], show_units=False,
       art=[dict(unit=1, x=16, y=148, walk=True), dict(unit=1, x=26, y=148, walk=True),
            dict(png='ArmyTruck_24x24.png', fw=24, fh=24, frames=1, flip=True, x=34, y=136, walk=True),
            dict(unit=1, x=48, y=148, walk=True), dict(unit=1, x=58, y=148, walk=True)]),
    _m(2, 5, [(2, 100)], kills=15, count=(2,), zn=4, veh=1, z80=1, text=['FIND THE Z80 !'], show_units=False,
       art=[dict(unit=2, x=14, y=148, walk=True), dict(unit=2, x=24, y=148, walk=True),
            dict(png='ArmyTruck_24x24.png', fw=24, fh=24, frames=1, flip=True, x=33, y=136, walk=True),
            dict(png='Z80_12x12.png', fw=12, fh=12, frames=1, x=47, y=148, walk=True),
            dict(unit=2, x=56, y=148, walk=True)]),
    _m(3, 5, [(2, 100)], time=40, zn=4, veh=1, show_units=False,
       art=[dict(unit=2, x=16, y=148, walk=True), dict(unit=2, x=26, y=148, walk=True),
            dict(png='ArmyTruck_24x24.png', fw=24, fh=24, frames=1, flip=True, x=34, y=136, walk=True),
            dict(unit=2, x=48, y=148, walk=True), dict(unit=2, x=58, y=148, walk=True)]),
    # Mission finale : le WarTruck (60 PV, rafales de 3 balles dans les 4 directions) + ses soldats
    _m(4, 5, [(1, 100)], kills=60, zn=4, veh=3, hp=60, text=['DESTROY THE', 'WAR TRUCK !'], show_units=False,
       art=[dict(unit=1, x=16, y=148, walk=True), dict(unit=1, x=26, y=148, walk=True),
            dict(png='WarTruck_24x96.png', fw=24, fh=24, frames=1, flip=True, x=34, y=136, walk=True),
            dict(unit=1, x=48, y=148, walk=True), dict(unit=1, x=58, y=148, walk=True)]),
    # Images supplementaires de l'ecran de mission (boss, batiments...) : ajouter a _m(...) un argument  art=[...]  (et show_units=False pour ne pas afficher les ennemis) dont chaque element est
    #   dict(png='Boss.png', fw=36, fh=36, frames=4, x=30, y=110, walk=True)   image(s) cote a cote, fw x fh pixels (paire, 80 pixels maxi), 1, 2 ou 4 images
    #   dict(tiles=[[8, 9, 10], [12, 13, 14]], x=4, y=110)                       bloc de tuiles du decor (12 x 8 pixels), numeros du TileSet
    # x en octets (2 pixels ; defaut : centre), y en lignes (defaut : sous le texte), walk=True : arrive de la gauche avec les ennemis ;
    # les images fixes passent devant ; show_units=False supprime les ennemis automatiques. Chaque image fait grossir l'overlay (INTRO_N automatique).

]
 
for _i, _z in enumerate(ZONES): _z['name'] = 'zone%02d' % (_i + 1)       # noms de fichiers uniques (le numero de mission recommence a 1 a chaque zone)
ZSTART = [min(i for i, z in enumerate(ZONES) if z['zn'] == k) for k in sorted(ZINFO)]          # premiere mission de chaque zone
for _k in ZINFO: assert sum(1 for z in ZONES if z['zn'] == _k) >= (4 if _k == 4 else 5), "chaque zone doit avoir au moins 5 missions (4 pour la zone 4 : touches secretes 1 a 6)"

# jingle "ZONE CLEAR !" (assets/ZoneClear.wav, analyse du WAV) : 64 images de 20 ms, une hauteur par image sur un canal du AY.
# Introduction 0-280 ms (270 Hz qui descend a 185 Hz), puis 4 glissandos montants (x1,166 par image : 185 Hz -> ~1 kHz).
# On stocke periode / 2 (periode AY = 62500 / frequence) ; le volume (15, 14, 13, 11, puis silence) est dans le moteur.
def zclear_table():
    fr = [190, 270, 270, 268, 265, 260, 255, 250, 245, 238, 230, 220, 210, 200]       # images 0..13
    for cyc in range(4):
        start = 185 - 3 * cyc
        n = 12 if cyc < 3 else 12
        fr += [start * 1.166 ** j for j in range(n)]
    fr += [1000, 1000]
    assert len(fr) == 64, len(fr)
    return [min(255, int(round(31250 / f))) for f in fr]

def boss_vol_table():
    """son 'Tir Boss' (assets/TirBoss.wav) : bruit blanc d'environ 0,28 s (rafale de 3 coups), enveloppe plate puis coupee.
       Volume AY par image de 20 ms (fenetre decalee de 15 ms, comme le WAV demarre apres un court silence) : 15 + 2 log2(rms / rms max)"""
    import wave, array, math
    w = wave.open(os.path.join(A, 'TirBoss.wav')); fr = w.getframerate(); ch = w.getnchannels()
    d = array.array('h'); d.frombytes(w.readframes(w.getnframes()))
    if ch > 1: d = d[::ch]
    N = int(fr * 0.02); out = []
    for i in range(int(0.015 * fr), len(d) - N + 1, N):
        out.append(math.sqrt(sum(x * x for x in d[i:i + N]) / N))
    m = max(out); vol = [max(0, min(15, round(15 + 2 * math.log2(max(r / m, 1e-4))))) for r in out]
    n = 0
    while n < len(vol) and vol[n] >= 3: n += 1
    return vol[:n]

def tile_bytes():
    """tuiles 8x8 du bandeau (4 octets x 8 lignes) : 1 grenade, 2 mission "tuer", 3 mission "Time Attack", 4 coeur (vies) ;
       rangees dans l'emplacement TILE_SLOT de la page video A (144 octets), pas dans la partie permanente"""
    out = []
    for nm in ('GrenadeChar8x8.png', 'MissionKillChar8x8.png', 'MissionTimeChar8x8.png'):
        out += opaque(load(nm), 0, 0, 8, 8)
    for row in HEART:
        out += [enc(row[i], row[i + 1]) for i in range(0, 8, 2)]
    assert len(out) == 128
    return out + [0] * 16

def slot_addr(u):
    if u >= 8 * SPRSLOT:                # au-dela des trous de la page A : emplacements supplementaires de la partie permanente
        assert u < 8 * SPRSLOT + NXS, 'trop d images de sprites : %d (maxi %d)' % (u - SLOT0_ZONE + 1, 8 * SPRSLOT + NXS - SLOT0_ZONE)
        return XSLOT_BASE + (u - 8 * SPRSLOT) * 144
    return 0x8000 + (u // SPRSLOT) * 0x800 + (u % SPRSLOT) * 144

def build_cover(png='CoverMode0.png'):
    im = Image.open(os.path.join(A, png)).convert('RGB')
    assert im.size == (160, 200), 'cover attendue : 160 x 200'
    px = im.load()
    from collections import Counter
    cnt = Counter(px[x, y] for y in range(200) for x in range(160))
    assert len(cnt) <= 16, 'cover : 16 couleurs au plus'
    order = [c for c, _ in cnt.most_common()]
    pen = {c: i for i, c in enumerate(order)}
    data = bytearray(16384)
    for y in range(200):
        for xb in range(80):
            data[(y >> 3) * 80 + (y & 7) * 0x800 + xb] = enc(pen[px[2 * xb, y]], pen[px[2 * xb + 1, y]])
    pal = [HW[fw_of(c)] for c in order] + [HW[0]] * (16 - len(order)) + [HW[0]]
    return bytes(data), pal, order

PRES_TEXT = 'PRESENTS'
PRES_X = 24          # octet de depart du mot "PRESENTS" sous le logo (centre : 40 - 4 * lettres / 2) ; a ajuster si le logo change
PRES_Y = 112         # ligne de depart (le mot fait 10 lignes de haut)
def build_logo_text(order):
    """le mot PRESENTS (police 3x5 doublee : 6 x 10 pixels, case de 8 pixels) en octets MODE 0 : (adresse ecran, 32 octets) par ligne.
       Fond : stylo du noir du logo ; lettres : stylo du blanc (ou du plus clair)"""
    lum = lambda c: sum(c)
    bg = min(range(len(order)), key=lambda i: lum(order[i]))
    fg = max(range(len(order)), key=lambda i: lum(order[i]))
    n = len(PRES_TEXT)
    rows = []
    for y in range(10):
        px = []
        for ch in PRES_TEXT:
            g = FONT[ch]
            for gx in range(3):
                v = fg if g[(y // 2) * 3 + gx] == '1' else bg
                px += [v, v]
            px += [bg, bg]
        data = [enc(px[i], px[i + 1]) for i in range(0, len(px), 2)]
        yy = PRES_Y + y
        rows.append((0xC000 + (yy >> 3) * 80 + (yy & 7) * 0x800 + PRES_X, data))
    return rows

def _stack(names, tag):
    """un ou plusieurs PNG 48 x 80 (40 tuiles chacun) empiles verticalement -> nom du PNG a lire (tuile n de la pile : colonne n % 4, ligne n // 4)"""
    if not isinstance(names, list): return names
    ims = [Image.open(os.path.join(A, n)).convert('RGB') for n in names]
    out = Image.new('RGB', (48, 80 * len(ims)))
    for i, im in enumerate(ims):
        assert im.size == (48, 80), '%s : 48 x 80 attendu' % names[i]
        out.paste(im, (0, 80 * i))
    p = os.path.join(BUILD, tag + '.png'); os.makedirs(BUILD, exist_ok=True); out.save(p)
    return p

# palette de l'eau : le jeu n'a que 16 stylos (tous pris) ; les bleus clairs du dessin sont ramenes aux bleus existants en gardant le contraste :
#   bleu ciel (fond) -> bleu vif, bleu vif (ondulations) -> bleu fonce, cyan et cyan clair (reflets) -> blanc ; (0,128,128) et (0,0,128) sont deja des stylos
WATER_FW = {(0, 128, 255): 2, (0, 0, 255): 1, (0, 255, 255): 26, (128, 255, 255): 26, (0, 128, 128): 10, (0, 0, 128): 1}
def load_expl():
    """Explosion10x10.png (4 images de 10 x 10) -> grille 48 x 12 : chaque image est centree dans une case de 12 x 12 (transparente autour)"""
    g = load('Explosion10x10.png')
    out = [[None] * 48 for _ in range(12)]
    for fr in range(4):
        for y in range(10):
            for x in range(10):
                out[y + 1][fr * 12 + x + 1] = g[y][fr * 10 + x]
    return out

def load_water(name):
    im = Image.open(os.path.join(A, name)).convert('RGB')
    w, h = im.size; px = im.load()
    return [[PENS.index(WATER_FW[px[x, y]]) for x in range(w)] for y in range(h)]

def build_zone(z):
    ts_name, nts = _stack(z['tileset'], z['name'] + '_ts'), len(z['tileset']) if isinstance(z['tileset'], list) else 1
    ob_name = _stack(z['obstacle'], z['name'] + '_ob')
    a = Image.open(os.path.join(A, ts_name)).convert('RGB')
    b = Image.open(os.path.join(A, ob_name)).convert('RGB')
    KIND = {(0, 128, 0): 0x00, (255, 0, 0): 0x03, (0, 128, 255): 0x01, (255, 255, 0): 0x80, (128, 0, 255): 0x07,    # violet : obstacle normal (bits 0-1 comme le rouge) mais pas un abri (bit 2), sortie des casernes
            (255, 0, 210): 0x08, (255, 255, 255): 0x17}                                                                                     # rose : EAU (bit 3) : seuls les ennemis ne la franchissent pas (voir water.asm)
    PURPLE = (128, 0, 255)
    tpurple = set(); twater = set()
    tiles_img = load(ts_name)
    tkind = []
    for t in range(40 * nts):
        tx, ty = (t % 4) * 12, (t // 4) * 8
        k = 0
        for y in range(8):
            for x in range(12):
                pb = b.getpixel((tx + x, ty + y))
                if pb != a.getpixel((tx + x, ty + y)) and pb in KIND:
                    k = KIND[pb]
                    if pb == PURPLE: tpurple.add(t)
                    if k == 0x08: twater.add(t)
        tkind.append(k)
    wframes = None
    if z.get('water'):                                  # l'eau : 3 images 12 x 8 (1 2 3 2) ; la 1re remplace l'image de la tuile d'eau du tileset (palette de l'eau : voir load_water)
        assert len(twater) == 1, 'zone %s : une seule tuile d eau attendue (carre rose des obstacles), trouve %s' % (z['name'], sorted(twater))
        wg = load_water(z['water'])
        assert len(wg) == 8 and len(wg[0]) == 36
        wt = next(iter(twater)); tx0, ty0 = (wt % 4) * 12, (wt // 4) * 8
        for y in range(8):
            for x in range(12): tiles_img[ty0 + y][tx0 + x] = wg[y][x]
        wframes = [v for f in range(3) for v in opaque(wg, 12 * f, 0, 12, 8)]
        assert len(wframes) == 144
    else:
        assert not twater, 'zone %s : tuile d eau sans animation (cle water de la zone)' % z['name']
    s = open(os.path.join(A, z['tmx'])).read()
    W = int(re.search(r'<layer[^>]* width="(\d+)"', s).group(1))
    Hh = int(re.search(r'<layer[^>]* height="(\d+)"', s).group(1))
    rows = re.search(r'<data encoding="csv">(.*?)</data>', s, re.S).group(1).strip().split('\n')
    tmap = [[(int(v) - z['gid0']) % (40 * nts) for v in r.strip().strip(',').split(',')] for r in rows]
    assert W == 13 and Hh == 24, 'carte attendue : 13 x 24 tuiles'
    if tpurple:        # casernes : le bloc d'obstacles qui touche une tuile violette ; ses tuiles (si elles ne servent qu'a ca) ne sont pas des abris (bit 2)
        comp = set(); todo = [(r, c) for r in range(24) for c in range(13) if tmap[r][c] in tpurple]
        while todo:
            r, c = todo.pop()
            if (r, c) in comp or not (0 <= r < 24 and 0 <= c < 13) or not (tkind[tmap[r][c]] & 2): continue
            comp.add((r, c)); todo += [(r + 1, c), (r - 1, c), (r, c + 1), (r, c - 1)]
        outside = {tmap[r][c] for r in range(24) for c in range(13) if (tkind[tmap[r][c]] & 2) and (r, c) not in comp}
        for t in {tmap[r][c] for r, c in comp} - outside: tkind[t] |= 4
    grid = [[0x03] * 16]
    for r in range(24): grid.append([tkind[t] for t in tmap[r]] + [0x03] * 3)
    grid.append([0x03] * 16)
    def free(r, c): return 0 <= r < 24 and 0 <= c < 13 and (grid[r + 1][c] & 1) == 0
    # points d'apparition : propriete de la zone ('spawn' = liste de (colonne de tuile, y)) ; le moteur les parcourt
    # tour a tour, de sorte que les ennemis arrivent de tous les points. Chaque point doit etre en zone verte :
    # la case des pieds (y + 10) de la colonne est de type 0 (ni bleu, ni rouge, ni jaune)
    spawns = []
    if z['spawn'] == 'auto':           # points d'apparition = case libre juste sous chaque pile de tuiles violettes (portes des casernes)
        z = dict(z); z['spawn'] = []
        for r in range(23):
            for c in range(13):
                if tmap[r][c] in tpurple and tmap[r + 1][c] not in tpurple: z['spawn'].append((c, 8 * (r + 1) - 6))
        assert z['spawn'], 'carte sans tuile violette'
    for c, y in z['spawn']:
        r = (y + 10) >> 3
        if z.get('veh'): spawns.append((c * 6, y)); continue
        assert 0 <= c < 13 and 0 <= r < 24 and tkind[tmap[r][c]] == 0, 'zone %s : point d apparition (%d,%d) pas en zone verte' % (z['name'], c, y)
        spawns.append((c * 6, y))
    assert 1 <= len(spawns) <= (15 if z.get('flame') else 16)
    nspawn = len(spawns)
    spawns += [spawns[i % nspawn] for i in range(16 - nspawn)]
    used = sorted({t for row in tmap for t in row})
    assert len(used) <= 40
    remap = {t: i for i, t in enumerate(used)}
    tmap_out = [v for row in tmap for v in [remap[t] for t in row]]
    # repartition des unites : le premier type recoit le reste, les autres leur pourcentage arrondi ; les types se suivent
    #   (boss : ses deux places d'abord, puis la garde)
    units = z['units']; mix = sorted(z['mix']); assert sum(p for _, p in mix) == 100 and units <= 12
    boss = z.get('boss'); veh = z.get('veh', 0); nb = 2 if (boss or veh >= 2) else 0
    ng = units - nb
    cnt = {t: (ng * p + 50) // 100 for t, p in mix[1:]}
    cnt[mix[0][0]] = ng - sum(cnt.values())
    slot_types = ([4, 5] if boss else [mix[0][0]] * 2 if veh >= 2 else []) + [t for t, _ in mix for _ in range(cnt[t])]
    assert len(slot_types) == units
    def uk(t):             # fiche du type t ; le boss de la zone peut avoir sa planche et sa vitesse (cle 'boss')
        u = UNITS[t]
        if boss and t in (4, 5): u = dict(u, sheet=boss.get('sheet', u['sheet']), spd=boss.get('spd', u['spd']))
        return u
    # sprites des unites : images identiques gardees une seule fois, emplacements a partir de SLOT0_ZONE
    uniq, index, tables = [], {}, {}
    def intern(d):
        key = tuple(d)
        if key not in index: index[key] = len(uniq); uniq.append(d)
        return slot_addr(SLOT0_ZONE + index[key])
    for t in [t for t, _ in mix] + ([4, 5] if boss else []):
        u = uk(t); g = load(u['sheet']); ptrs = []
        for fr in range(36):
            if 'half' in u:                  # boss : planche de 12 x 24 ; moitie haute (tete) ou basse (corps)
                if fr >= 32: ptrs.append(EXPLO_PTRS[fr - 32]); continue          # mort : explosions (images deja residentes)
                d = masked(g, (fr % 4) * 12, (fr // 4) * 24 + 12 * u['half'], 12, 12, True)
            else:
                d = masked(g, (fr % 4) * 12, (fr // 4) * 12, 12, 12, True)
            ptrs.append(intern(d))
        tables[t] = ptrs
    z80img = intern(masked(load('Z80_12x12.png'), 0, 0, 12, 12, True)) if z.get('z80') else 0      # mission Z80 : image du Z80 (objet ramasse)
    wimg = intern(wframes) if wframes else 0                        # eau : les 3 images (144 octets) et le tampon de l'image de Papi sans jambes (144 octets) : 2 places d'images
    wbuf = intern([0] * 144) if wframes else 0
    flimg = 0
    if z.get('flame'):                                              # flammes des bidons explosifs : 3 images de tuile 12 x 8 (144 octets : une place d'image)
        fg = load(z['flame']); assert len(fg) == 8 and len(fg[0]) == 36
        flimg = intern([v for f in range(3) for v in opaque(fg, 12 * f, 0, 12, 8)])
    nspr = len(uniq)
    assert SLOT0_ZONE + nspr <= 8 * SPRSLOT + NXS, 'trop d images pour les trous de la page A et les emplacements supplementaires (%d)' % (SLOT0_ZONE + nspr)
    npa = min(nspr, 8 * SPRSLOT - SLOT0_ZONE)          # images rangees dans la page A ; les autres dans XSLOT_BASE
    hdr = bytearray(H_SIZE)
    hdr[0], hdr[1], hdr[2], hdr[3], hdr[4] = units, z['kills'], npa, len(mix), nspawn
    hdr[7] = nspawn                                    # points d'apparition au bout de 15 s (hdr[4] : au debut)
    hdr[5] = 1 if z.get('time') else 0                 # 1 : mission Time Attack (kills = secondes a survivre)
    hdr[6] = nspr - npa                                # images supplementaires (partie permanente)
    if z.get('z80'): hdr[11], hdr[12], hdr[13] = 1, z80img & 255, z80img >> 8      # mission Z80 : drapeau et adresse de l'image
    if boss:                                           # barre de vie : seuils de couleur (vert, jaune, orange ; en dessous : rouge)
        hp = boss['hp']
        hdr[8], hdr[9], hdr[10] = -(-hp * 3 // 4), -(-hp // 2), -(-hp // 4)
        hdr[11] = boss.get('pts', 25)   # points du boss / 10 (>= 50 : pas de grenade)
        cov = boss.get('cover', 500)                  # images a couvert avant de repartir vers Papi (octets 12, 13 : poids faible d'abord)
        hdr[12], hdr[13] = cov & 255, cov >> 8
        hdr[14], hdr[15] = boss.get('burst', 3), boss.get('delay', 100)    # balles par rafale, images entre deux rafales
    if veh:                                            # vehicule : mode (1 camion de troupes + quota, 2 barre de vie + victoire normale, 3 barre de vie, rafales, fin de zone) ; seuils de la barre ; rafales du WarTruck
        hdr[95] = veh
        if veh >= 2:
            hp = z['hp']
            hdr[8], hdr[9], hdr[10] = -(-hp * 3 // 4), -(-hp // 2), -(-hp // 4)
        if veh == 2: hdr[11] = 50                      # ArmyTruck : 500 points
        if veh == 3: hdr[11], hdr[14], hdr[15] = z.get('pts', 75), 3, 50
    hdr[88], hdr[89], hdr[90], hdr[91] = wimg & 255, wimg >> 8, wbuf & 255, wbuf >> 8
    hdr[92], hdr[93], hdr[94] = 0x10, 0x38, 0      # ptr = GRID+16, in = 0 ; eau : adresse des 3 images et du tampon (0 : pas d'eau), lues par wtr_load
    ext = slot_types + [mix[0][0]] * (12 - units)      # places au-dela de la zone (essais avec plus d'ennemis) : comme le 1er type
    def arr(k, f):
        for s_ in range(12): hdr[16 + 12 * k + s_] = f(uk(ext[s_]))
    arr(0, lambda u: 0); [hdr.__setitem__(16 + s_, (0 if (boss and ext[s_] == 3) else ext[s_] - 1)) for s_ in range(12)]                   # type 0..4
    arr(1, lambda u: u['spd']); arr(2, lambda u: u['fire']); arr(3, lambda u: u['pts']); arr(4, lambda u: u['hp']); arr(5, lambda u: u['gren'] | (u['cls'] << 4))
    # bit 2 de la fiche : cette place compte pour le quota (les types a abattre) ; Time Attack : aucune
    for s_ in range(12): hdr[16 + 12 * 5 + s_] |= 4 if (not z.get('time') and ext[s_] in z['count']) else 0
    # tir en couverture : une part des unites (officiers compris), reparties dans la liste ; bit 1 de la fiche 'gren'
    cands = list(range(nb, units))
    ncov = (len(cands) * z.get('cover', 0) + 50) // 100
    cov = [cands[int((i + 0.5) * len(cands) / ncov)] for i in range(ncov)] if ncov and cands else []
    if boss: cov.append(0)                              # le boss sait tirer a couvert (comme le soldat)
    for s_ in cov: hdr[16 + 12 * 5 + s_] |= 2
    zb = bytearray(hdr)
    if flimg: spawns[15] = (flimg & 255, flimg >> 8)   # (zone a vehicules : aucun point d'apparition) les 2 derniers octets de la table donnent l'adresse des images de flamme
    assert len(zb) == Z_SPAWN; zb += bytes(v for xy in spawns for v in xy)               # 16 points d'apparition
    icon = 'MissionKillCar8x8.png' if z.get('veh', 0) >= 2 else 'MissionKillBossChar8x8.png' if boss else 'MissionZ80Char8x8.png' if z.get('z80') else 'MissionKillChar8x8.png'          # icone de la mission : remplace la tuile "tuer" du bandeau
    assert len(zb) == Z_ICON; zb += bytes(opaque(load(icon), 0, 0, 8, 8))
    assert len(zb) == Z_TILEMAP; zb += bytes(tmap_out)
    assert len(zb) == Z_TKIND; zb += bytes(tkind[t] for t in used) + bytes(40 - len(used))
    assert len(zb) == Z_FRAMES
    if boss and any(t == 3 for t, _ in mix): assert all(t == 3 for t, _ in mix), 'boss + generaux : garde 100 % generaux'      # leurs images prennent la place de la table des soldats (la table des generals sert au corps du boss)
    order = ((3 if any(t == 3 for t, _ in mix) else 1), 2, 4, 5, 0) if boss else (1, 2, 3, 0, 0)      # boss : son corps prend la place de la table des generals (le moteur ne les distingue pas) ; la tete suit
    for t in order:
        for p in tables.get(t, [0] * 36): zb += bytes([p & 255, p >> 8])
    assert len(zb) == Z_TILES
    for t in used: zb += bytes(opaque(tiles_img, (t % 4) * 12, (t // 4) * 8, 12, 8))
    zb += bytes(Z_SPR - len(zb))
    for d in uniq: zb += bytes(d)
    return bytes(zb), nspr, len(used), slot_types

def pad_sectors(b):
    return b + bytes((-len(b)) % 512)


# ---------------------------------------------------------------- menu principal (overlay)
TITLE_Y = 30          # position finale du titre (ligne de la carte)
def build_menu():
    """src/menu_gfx.asm : le titre (assets/Titre.png) en octets MODE 0, lignes de 78 octets (carte), centre ; stylos du jeu"""
    im = Image.open(os.path.join(A, 'Titre.png')).convert('RGB')
    w, h = im.size
    cols = {0: (0, 0, 0), 7: (128, 128, 128), 13: (255, 255, 255), 1: (128, 0, 0), 2: (255, 0, 0)}   # stylo -> RVB
    def near(c):
        return min(cols, key=lambda k: sum((a - b) ** 2 for a, b in zip(c, cols[k])))
    w2 = w + (w & 1)
    assert w2 // 2 <= 78, 'titre trop large'
    x0 = (78 - w2 // 2) // 2
    rows = []
    for y in range(h):
        line = [0] * x0
        for x in range(0, w2, 2):
            p0 = near(im.getpixel((x, y)))
            p1 = near(im.getpixel((x + 1, y))) if x + 1 < w else 0
            line.append(enc(p0, p1))
        line += [0] * (78 - len(line))
        rows.append(line)
    title_rows = list(rows)
    with open(os.path.join(ROOT, 'src', 'menu_gfx.asm'), 'w') as f:
        f.write('; --- genere par tools/convert.py : titre du menu (%d lignes de 78 octets), octets du texte defilant ---\n' % h)
        f.write('TITLE_H     equ %d\nTITLE_Y     equ %d\n' % (h, TITLE_Y))
        f.write('MENU_NZG    equ %d\nmenu_zstart: db %s       ; premiere mission de chaque zone (touche + du menu)\n' % (len(ZSTART), ','.join(str(v) for v in ZSTART)))
        f.write('title_data:\n')
        for r in rows: db(f, r, 39)
        # sprites de la poursuite : Papi, soldat, officier, general ; direction 0 droite, 1 gauche ; 4 images ; 72 octets (6 x 12, donnees seules)
        f.write('menu_spr:   ; (type * 2 + direction) * 4 + image, 72 octets chacune\n')
        for nm in ('PapiCPC_12x12.png', 'SoldatC++_12x12.png', 'OfficierC___12x12.png', 'GeneralC___12x12.png'):
            g = load(nm)
            for d in (0, 1):
                for a in range(4):
                    x0, y0 = a * 12, d * 12
                    data = []
                    for y in range(12):
                        for x in range(0, 12, 2):
                            data.append(enc(g[y0 + y][x0 + x] or 0, g[y0 + y][x0 + x + 1] or 0))
                    db(f, data, 6)
        f.write('pentab:     ; 2 pixels du texte defilant (pixel gauche, pixel droit) -> octet ecran, stylo 13\n')
        db(f, [0, enc(0, 13), enc(13, 0), enc(13, 13)])
        # police du bandeau = celle du bandeau de jeu (3 x 5, FONT), 5 octets par caractere ASCII 32..95 (minuscules lues en majuscules) ;
        # bits 7..4 = 4 colonnes (la 4e = espace entre lettres).  Absents du HUD, ajoutes ici : B J , & et le (c) en 2 morceaux '@' '['
        extra = {'B': '110101110101110', 'J': '001001001101010', ',': '000000000010100', '&': '010101010101011'}
        copy_l = ['0111', '1011', '1010', '1011', '0111']
        copy_r = ['1100', '1010', '0010', '1010', '1100']
        f.write('scroll_font: ; caracteres 32..95 x 5 lignes\n')
        for code in range(32, 96):
            ch = chr(code)
            if ch == '@': rows = copy_l
            elif ch == '[': rows = copy_r
            else:
                g = FONT.get(ch) or extra.get(ch) or '0' * 15
                rows = [g[r * 3:r * 3 + 3] + '0' for r in range(5)]
            db(f, [int(r, 2) << 4 for r in rows], 5)
        # --- Hall of Fame : table initiale (7 x : nom 10 caracteres complete par des points, 5 chiffres du score), copiee dans la page A au 1er passage
        f.write('hof_init_data: ; nom (10), score (5 chiffres)\n')
        for nm, sc in HOF_INIT:
            f.write(' db "%s"\n' % nm.upper().ljust(10, '.')[:10])
            f.write(' db %s\n' % ','.join(str(int(c)) for c in '%05d' % sc))
    build_hof(title_rows)

HOF_INIT = [('Vetea', 9000), ('ShiningBZH', 7500), ('Fonzie', 6666), ('Kaot', 5000), ('Touko', 2500), ('Nessia', 1000), ('VBT', 500)]
HOF_N = 10                            # secteurs reserves a l'overlay du Hall of Fame (code, titre, police, cercles)
VOICE_RATE = 6000                      # voix numerisee de l'intro : 6 kHz, 4 bits (niveaux de volume du PSG)
VOICE_OFF = 0xC40                      # la voix commence 3 Ko apres le debut de la banque 7 (code du boss et des vehicules)
def build_voice():
    """assets/PapiCommandoCPC_voix.wav -> build/voice.bin : echantillons 4 bits (2 par octet, poids fort d'abord) = indices de volume du
    PSG (canal A, registre 8). Les niveaux du PSG ne sont pas lineaires : on choisit, pour chaque echantillon, le niveau le plus proche."""
    import numpy as np
    from scipy.io import wavfile
    from scipy.signal import resample_poly
    from math import gcd
    r, x = wavfile.read(os.path.join(ROOT, 'assets', 'PapiCommandoCPC_voix.wav'))
    x = x.astype(float)
    if x.ndim > 1: x = x.mean(axis=1)
    x -= x.mean()
    g = gcd(VOICE_RATE, r)
    x = resample_poly(x, VOICE_RATE // g, r // g)
    x /= abs(x).max()
    loud = np.nonzero(abs(x) > 0.05)[0]                         # silences de debut et de fin retires
    x = x[max(loud[0] - 300, 0):loud[-1] + 300]
    x = np.tanh(2.2 * x) / np.tanh(2.2)                          # compression douce : voix plus forte
    lv = np.array([0, 0.0137, 0.0205, 0.0291, 0.0423, 0.0618, 0.0847, 0.1369, 0.1691, 0.2647, 0.3527, 0.4499, 0.5704, 0.6873, 0.8482, 1.0])
    t = x * 0.5 + 0.5                                           # 0..1 autour du niveau median
    t = t * (lv[15] - lv[0]) + lv[0]
    q = np.zeros(len(t), int)                                   # quantification avec diffusion d'erreur (niveaux du PSG tres inegaux)
    e = 0.0
    for i in range(len(t)):
        v = t[i] + 0.7 * e
        q[i] = int(np.abs(lv - v).argmin())
        e = v - lv[q[i]]
    n = (len(q) + 1023) // 1024 * 1024                          # multiple de 512 octets
    q = np.concatenate([q, np.full(n - len(q), np.abs(lv - 0.5).argmin())])
    packed = bytes(int(a) << 4 | int(b) for a, b in zip(q[0::2], q[1::2]))
    open(os.path.join(BUILD, 'voice.bin'), 'wb').write(packed)
    print('voix : %d echantillons (%.2f s), %d octets' % (len(q), len(q) / VOICE_RATE, len(packed)))
    global VOICE_FR
    VOICE_FR = len(q) * 50 // VOICE_RATE
    return len(packed)
os.makedirs(os.path.join(ROOT, 'build'), exist_ok=True)
VOICE_LEN = build_voice()
TRUCK_OFF = VOICE_OFF + VOICE_LEN   # images des camions : apres la voix (banque 7)
BOSS_N = 16                            # secteurs de la banque 7 SUR LA DISQUETTE : l'image (code, voix, camions : 16 Ko au plus) y est compressee (mkdisk.py) et decompressee au demarrage
BOSS_PAD = 0x4000 - BOSS_N * 512                      # elle est lue en BOSS_LOAD + BOSS_PAD (derniers 8 Ko de la fenetre) puis decompressee sur place

def build_trucks():
    """build/trucks.bin : images masquees 24 x 24 (12 octets x 24 lignes, paires masque/donnee : 576 octets) des vehicules.
       ArmyTruck : 2 images (0 = vers la gauche, comme dessine, 1 = miroir) ; WarTruck : 8 images, (cap * 4 + direction du canon) avec
       direction 0 droite, 1 gauche, 2 bas, 3 haut (planche : canon a gauche, a droite, en haut, en bas) ; vers la droite : miroir de l'image de la direction opposee"""
    def mirror(g): return [row[::-1] for row in g]
    def img(g, y0): return masked(g, 0, y0, 22, 18)
    out = []
    a = load('ArmyTruck_22x18.png')
    out += img(a, 0) + img(mirror(a), 0)
    w = load('WarTruck_22x72.png')
    frame = {1: 0, 0: 1, 3: 2, 2: 3}          # direction du canon -> image de la planche (vers la gauche) : planche = canon W, E, N, S
    for facing in (0, 1):                     # 0 : vers la gauche (cap), 1 : vers la droite (miroir)
        for aim in range(4):
            if facing == 0: out += img(w, 18 * frame[aim])
            else:
                opp = {0: 1, 1: 0, 2: 2, 3: 3}[aim]
                out += img(mirror(w), 18 * frame[opp])
    assert len(out) == 10 * 396
    ex = load_expl()                       # 4 images d'explosion 12 x 12, memes octets que celles du moteur mais SANS l'ordre en zigzag (le module des vehicules les affiche ligne par ligne)
    for fr in (0, 2): out += masked(ex, fr * 12, 0, 12, 12)
    assert len(out) == 10 * 396 + 2 * 144
    open(os.path.join(BUILD, 'trucks.bin'), 'wb').write(bytes(out))

def build_hof(title_rows):
    """src/hof_gfx.asm : titre (bandeau), police 3 x 5 (ASCII 32..95, 5 octets : bits 7..5), cercles rouges de selection"""
    red = enc(2, 2)
    def ring(w, h=12):
        cx = (w - 1) / 2; cy = (h - 1) / 2; a = w / 2; b = h / 2
        rows = []
        for y in range(h):
            r = []
            for x in range(w):
                d = ((x - cx) / a) ** 2 + ((y - cy) / b) ** 2
                r.append(1 if 0.55 <= d <= 1.0 else 0)
            rows.append(r)
        return rows
    with open(os.path.join(ROOT, 'src', 'hof_gfx.asm'), 'w') as f:
        f.write('; --- genere par tools/convert.py : Hall of Fame ---\nhof_title:\n')
        for r in title_rows: db(f, r, 39)
        f.write('hof_font: ; ASCII 32..95 x 5 lignes (bits 7..5 = 3 colonnes)\n')
        for code in range(32, 96):
            g = FONT.get(chr(code)) or '0' * 15
            db(f, [int(g[r * 3:r * 3 + 3], 2) << 5 for r in range(5)], 5)
        for nm, w in (('circ5', 10), ('circ9', 18)):
            f.write('%s: ; %d x 12 pixels\n' % (nm, w))
            for r in ring(w):
                db(f, [red if (r[x] and r[x + 1]) else (enc(2, 0) if r[x] else (enc(0, 2) if r[x + 1] else 0)) for x in range(0, w, 2)], 16)

# ---------------------------------------------------------------- ecrans de mission (overlay)
ACCESS = {2: 'FONZIE', 3: 'MAMIE', 4: 'SUGAR'}      # codes d'acces des zones (numero de zone -> code), saisis dans le menu (ACCESS CODE)
def build_access():
    with open(os.path.join(ROOT, 'src', 'access.inc'), 'w') as f:
        f.write('; --- genere par tools/convert.py : codes d acces : numero de zone, code, 0 ; fin : 0 ---\naccess_tab:\n')
        for z in sorted(ACCESS): f.write(" db %d,'%s',0\n" % (z, ACCESS[z]))
        f.write(' db 0\n')
def build_intro():
    """src/intro_gfx.asm : textes des ecrans noirs de chaque mission (x centre, y, couleur, texte) + ecran de fin"""
    def line(t, y, col):
        assert len(t) <= 19 and all(c in FONT_ORDER for c in t), t
        return ' db %d,%d,#%02X,"%s",0\n' % ((78 - 4 * len(t)) // 2, y, col, t)
    YEL, WHT = 0xCF, enc(13, 13)
    with open(os.path.join(ROOT, 'src', 'intro_gfx.asm'), 'w') as f:
        f.write('; --- genere par tools/convert.py : textes des ecrans de mission : x, y, couleur, texte ; x = 0 : fin ---\n')
        f.write('intro_tab:\n dw ' + ','.join('intro_%d' % i for i in range(len(ZONES))) + '\n')
        for i, z in enumerate(ZONES):
            f.write('intro_%d:\n' % i)
            f.write(line('MISSION %02d' % z['mnum'], 64, WHT))
            for k, t in enumerate(z['text']): f.write(line(t, 96 + 20 * k, YEL if t.startswith('TIME') else WHT))
            f.write(' db 0\n')
        titles = sorted(set(z['title'] for z in ZONES))
        for k, t in enumerate(titles): f.write('intro_title%d:\n' % k + line(t, 40, YEL) + ' db 0\n')
        zt = [ZINFO[k]['title'] for k in sorted(ZINFO)]
        f.write('NZG equ %d\nzone_start: db %s,255\n' % (len(zt), ','.join(str(v) for v in ZSTART[1:]) if len(zt) > 1 else '255'))
        f.write('intro_zend: dw ' + ','.join('intro_end%d' % k for k in range(len(zt))) + '\n')
        for k, t in enumerate(zt):
            acc = ''
            if k + 2 in ACCESS: acc = line('ACCESS CODE ZONE %d' % (k + 2), 140, YEL) + line(ACCESS[k + 2], 158, WHT)      # le code de la zone suivante
            f.write('intro_end%d:\n' % k + line('CONGRATULATIONS !!', 56, YEL) + line('YOU CLEARED', 92, WHT) + line(('%s !' if len(t) <= 17 else '%s!') % t, 112, WHT) + acc + ' db 0\n')
        # ---- images de l'ecran de mission : ennemis de l'objectif + decor / boss optionnels (cle 'art' de la zone)
        titles_idx = {t: i for i, t in enumerate(titles)}
        items, blobs = intro_items()
        f.write('intro_missions:  ; mission : (nom de la zone, liste d images)\n')
        for i, z in enumerate(ZONES): f.write(' dw intro_title%d,intro_it%d\n' % (titles_idx[z['title']], i))
        f.write('; image : donnees (2), taille d une image (2), largeur en octets, hauteur en lignes, masque d images - 1, x final, y, drapeaux (bit 0 = arrive de la gauche, bit 1 = redessine a chaque image : decor devant les ennemis), retard\n')
        for i, z in enumerate(ZONES):
            f.write('intro_it%d: db %d\n' % (i, len(items[i])))
            for it in items[i]:
                f.write(' dw %s,%d\n db %d,%d,%d,%d,%d,%d,%d\n' % (it['label'], it['fsize'], it['w'], it['h'], it['nf'] - 1, it['x'], it['y'], (1 if it['walk'] else 0) | (2 if it['redraw'] else 0), it['k']))
        for lab, data in blobs:
            f.write('%s:\n' % lab)
            db(f, data, 16)

ART_FRAME_MAX = 40       # largeur maxi d'une image (octets)
def _png_frames(nm, fw, fh, nf, flip=False):
    """image(s) PNG -> (octets de toutes les images, largeur en octets, hauteur) ; fw, fh en pixels (defaut : toute l'image), nf images cote a cote"""
    g = load(nm)
    H, Wd = len(g), len(g[0])
    fw = fw or Wd // nf; fh = fh or H
    assert fw % 2 == 0 and fw // 2 <= ART_FRAME_MAX, '%s : largeur d image %d px (paire, %d octets maxi)' % (nm, fw, ART_FRAME_MAX)
    data = []
    for a in range(nf):
        for y in range(fh):
            row = g[y][a * fw:(a + 1) * fw]
            if flip: row = row[::-1]                      # miroir (vehicules : l'image est dessinee vers la gauche, ils arrivent vers la droite)
            for x in range(0, fw, 2):
                data.append(enc(row[x] or 0, row[x + 1] or 0))
    return data, fw // 2, fh

def _tile_block(tileset, rows):
    """bloc de tuiles du decor (12 x 8 pixels chacune, numerotees comme dans le fichier de zone) -> octets, largeur, hauteur"""
    g = load(tileset)
    data = []
    for tr in rows:
        for y in range(8):
            for t in tr:
                tx, ty = (t % 4) * 12, (t // 4) * 8
                for x in range(0, 12, 2):
                    data.append(enc(g[ty + y][tx + x] or 0, g[ty + y][tx + x + 1] or 0))
    return data, 6 * len(rows[0]), 8 * len(rows)

_ITEMS = None
def intro_items():
    """-> ([liste d'images par mission], [(etiquette, octets)]).  Tout ce qui arrive de la gauche s'arrete en meme temps (instant T)."""
    global _ITEMS
    if _ITEMS: return _ITEMS
    blobs, per = [], []
    unit_png = {1: 'SoldatC++_12x12.png', 2: 'OfficierC___12x12.png', 3: 'GeneralC___12x12.png'}
    for t, nm in unit_png.items():
        d, w, h = _png_frames(nm, 12, 12, 4)
        blobs.append(('intro_unit%d' % t, d))
    for zi, z in enumerate(ZONES):
        ytxt = 96 + 20 * len(z['text'])                 # 1re ligne libre sous le texte
        its = []
        if z['units_shown']:
            types = sorted(z['count']) if (z['count'] and not z['time']) else sorted(t for t, _ in z['mix'])
            if len(types) == 1: types = types * 3
            n = len(types)
            for i, t in enumerate(types):
                its.append(dict(label='intro_unit%d' % t, fsize=72, w=6, h=12, nf=4, x=41 - 5 * n + 10 * i, y=ytxt, walk=True))
        for ai, a in enumerate(z.get('art', [])):
            if 'unit' in a:                              # un ennemi deja en memoire (soldat 1, officier 2, general 3) : pas de donnees en plus
                x = a['x'] if a.get('x') is not None else 36
                its.append(dict(label='intro_unit%d' % a['unit'], fsize=72, w=6, h=12, nf=4, x=x, y=a['y'] if a.get('y') is not None else ytxt, walk=True)); continue
            if 'tiles' in a:
                d, w, h = _tile_block(_stack(z['tileset'], z['name'] + '_ts'), a['tiles']); nf = 1
            else:
                nf = a.get('frames', 1)
                d, w, h = _png_frames(a['png'], a.get('fw'), a.get('fh'), nf, a.get('flip', False))
            lab = 'intro_art%d_%d' % (zi, ai)
            blobs.append((lab, d))
            x = a['x'] if a.get('x') is not None else (79 - w) // 2          # centre par defaut
            y = a['y'] if a.get('y') is not None else ytxt
            assert 0 <= x and x + w <= 79 and y + h <= 200, 'zone %d, image %d : hors ecran' % (zi + 1, ai)
            its.append(dict(label=lab, fsize=w * h, w=w, h=h, nf=nf, x=x, y=y, walk=bool(a.get('walk'))))
        walkers = [it for it in its if it['walk']]
        T = max([it['x'] + it['w'] + 1 for it in walkers] + [0])
        assert T <= 95, 'mission %d : trop d images a faire arriver (%d)' % (zi + 1, T)
        its.sort(key=lambda it: not it['walk'])          # les images fixes en dernier : elles passent devant les ennemis qui marchent
        for it in its: it['k'] = T - it['x'] if it['walk'] else 0
        for it in its: it['redraw'] = bool(walkers) and not it['walk']
        per.append(its)
    _ITEMS = (per, blobs)
    return _ITEMS

JINGLE_BYTES = 1200 + 1400 + 1000      # (+ jingles de victoire de zone)
JV_UNUSED = 0      # place reservee pour le jingle de depart de niveau (verifiee par l'assert de l'assemblage)
def intro_sectors():
    per, blobs = intro_items()
    return max(4, -(-(2600 + JINGLE_BYTES + sum(len(d) for _, d in blobs)) // 512))

def main():
    global INTRO_N
    INTRO_N = intro_sectors()
    os.makedirs(BUILD, exist_ok=True)
    papi = load('PapiCPC_12x12.png'); expl = load_expl()
    gren = load('Grenade_4x6.png'); ball = load('Balle2x6.png'); ecl = load('EclatBalle_4x6.png')
    with open(OUT, 'w') as f:
        f.write('; --- genere par tools/convert.py : ne pas modifier a la main ---\n\n')
        f.write('palette_hw:            ; 16 encres + bordure (numeros materiels)\n')
        db(f, [HW[p] for p in PENS] + [HW[0]])
        f.write('\nspr_grenade:           ; 3 images 2x6\n')
        for fr in range(3): db(f, masked(gren, fr * 4, 0, 4, 6), 4)
        f.write('\nspr_eclat:             ; eclat d une balle en fin de portee : 3 images 2x6\n')
        for fr in range(3): db(f, masked(ecl, fr * 4, 0, 4, 6), 4)
        f.write('\nspr_balle:             ; 1 image 1x6\n')
        db(f, masked(ball, 0, 0, 2, 6), 2)
        f.write('\nfont:                  ; glyphes 3x5 compactes : 2 octets (poids faible d abord) = 15 bits, ligne du haut en tete, ordre "%s"\n' % FONT_ORDER)
        for ch in FONT_ORDER:
            v = int(FONT[ch], 2) << 1
            db(f, [v & 255, v >> 8], 2)
        # couleurs de la barre de vie du boss (stylos du jeu) : vert (lime), jaune, orange, rouge ; par couleur : octet du pixel gauche, du pixel droit
        f.write('\nhp_pens:               ; barre de vie du boss : (pixel gauche, pixel droit) pour vert, jaune, orange, rouge\n')
        db(f, [v for fwc in (21, 24, 15, 6) for v in (enc(PENS.index(fwc), 0), enc(0, PENS.index(fwc)))], 2)
        bv = boss_vol_table()
        f.write('\nSND_BOSS_LEN equ %d\nboss_vol:              ; son Tir Boss : volume par image\n' % len(bv))
        db(f, bv, 16)
        f.write('\nzc_per:                ; jingle ZONE CLEAR : periode / 2 par image de 20 ms (64 images)\n')
        db(f, zclear_table(), 16)
    crate = load('CaisseGrenade_12x12.png')
    uniq, index, ptr = [], {}, {'papi': [], 'explo': [], 'crate': []}
    for name, g, n in (('papi', papi, 36), ('explo', expl, 4), ('crate', crate, 1)):
        for fr in range(n):
            d = masked(g, (fr % 4) * 12, (fr // 4) * 12, 12, 12, True) if name == 'papi' else masked(g, fr * 12, 0, 12, 12, True)
            key = tuple(d)
            if key not in index: index[key] = len(uniq); uniq.append(d)
            ptr[name].append(slot_addr(index[key]))
    global EXPLO_PTRS
    EXPLO_PTRS = ptr['explo']             # les images de mort du boss sont les explosions (deja residentes)
    assert len(uniq) == SLOT0_ZONE - 1, 'Papi + explosions : %d images uniques, %d attendues' % (len(uniq), SLOT0_ZONE - 1)
    uniq.append(tile_bytes())             # emplacement 35 : les tuiles 8x8 du bandeau
    with open(os.path.join(ROOT, 'src', 'gfx_spr.asm'), 'w') as f:
        f.write('; --- genere par tools/convert.py ---\nspr_papi:                 ; %d images uniques (Papi puis explosions), recopiees au demarrage\n' % len(uniq))
        for d in uniq: db(f, d, 12)
    with open(os.path.join(ROOT, 'src', 'frames.asm'), 'w') as f:
        f.write('; --- genere par tools/convert.py ---\n')
        for name in ('papi', 'explo'):
            f.write('%s_frames:\n' % name)
            for i in range(0, len(ptr[name]), 12): f.write(' dw ' + ','.join('#%04X' % v for v in ptr[name][i:i + 12]) + '\n')
        f.write('CRATE_IMG equ #%04X\ncrate_frame: dw CRATE_IMG\n' % ptr['crate'][0])
    # ---- cover (compressee), zones (compressees, sur place)
    cover, cpal, order = build_cover()
    ccomp = lz_compress(cover); assert lz_decompress(ccomp) == cover
    cfile = pad_sectors(ccomp)
    with open(os.path.join(ROOT, 'src', 'cover.inc'), 'w') as f:
        f.write('; --- genere par tools/convert.py ---\ncover_pal:  ; 16 encres + bordure (numeros materiels)\n')
        db(f, cpal)
    logo, lpal, lorder = build_cover('Logo.png')
    lcomp = lz_compress(logo); assert lz_decompress(lcomp) == logo
    lfile = pad_sectors(lcomp)
    with open(os.path.join(ROOT, 'src', 'cover.inc'), 'a') as f:
        f.write('logo_pal:   ; logo du studio (affiche avant la cover)\n')
        db(f, lpal)
        f.write('logo_text:  ; "%s" : 10 lignes de (adresse ecran, 32 octets)\n' % PRES_TEXT)
        for ad, data in build_logo_text(lorder):
            f.write(' dw #%04X\n' % ad); db(f, data, 32)
    trk = COVER_TRK
    layout = {'cover': dict(track=trk, data=len(cfile))}
    open(os.path.join(BUILD, 'cover.bin'), 'wb').write(cfile)
    cover_trk, cover_n = trk, len(cfile) // 512
    trk += (cover_n + 8) // 9
    layout['logo'] = dict(track=trk, data=len(lfile))
    open(os.path.join(BUILD, 'logo.bin'), 'wb').write(lfile)
    logo_trk, logo_n = trk, len(lfile) // 512
    trk += (logo_n + 8) // 9
    zdir = []; info = []
    zpos = trk * 9                                   # les zones sont rangees a la suite, secteur par secteur (le chargeur sait partir d'un secteur quelconque)
    for zi, z in enumerate(ZONES):
        raw, nspr, ntil, slot_types = build_zone(z)
        comp = lz_compress(raw); assert lz_decompress(comp) == raw
        pad = inplace_offset(comp, len(raw)); zf = pad_sectors(comp)
        load_addr = ZSTAGE + pad
        assert load_addr + len(zf) <= 0x8000, 'zone %d : trop volumineuse pour la zone de preparation' % zi
        open(os.path.join(BUILD, '%s.bin' % z['name']), 'wb').write(zf)
        open(os.path.join(BUILD, '%s.raw' % z['name']), 'wb').write(raw)
        trk, zsec = divmod(zpos, 9)
        zdir.append((trk, zsec, len(zf) // 512, load_addr))
        layout[z['name']] = dict(track=trk, sector=zsec, data=len(zf))
        info.append('zone %d (%s) : %d -> %d octets (%d secteurs, piste %d), %d tuiles, %d images d unites, types %s, couverture : places %s' % (
            zi + 1, z['name'], len(raw), len(comp), len(zf) // 512, trk, ntil, nspr, slot_types[:z['units']], [i for i in range(z['units']) if raw[16 + 60 + i] & 2]))
        zpos += len(zf) // 512
    trk = (zpos + 8) // 9
    layout['menu'] = dict(track=trk, data=MENU_N * 512)         # overlay du menu : build/menu.bin (ecrit par RASM)
    menu_trk = trk
    trk += (MENU_N + 8) // 9
    layout['intro'] = dict(track=trk, data=INTRO_N * 512)       # overlay des ecrans de mission : build/intro.bin
    intro_trk = trk
    trk += (INTRO_N + 8) // 9
    import mkmusic
    gf, gb = mkmusic.build_raw('MusiqueGameOver_AY.vgm', 'game over', os.path.join(ROOT, 'src', 'jingle_gameover.asm'), 'go')
    GO_N = -(-(400 + gb) // 512)
    layout['gover'] = dict(track=trk, data=GO_N * 512)          # overlay du game over : build/gover.bin
    gover_trk = trk
    print('jingle de game over : %d images, %d octets, %d secteurs' % (gf, gb, GO_N))
    trk += (GO_N + 8) // 9
    layout['hof'] = dict(track=trk, data=HOF_N * 512)           # overlay du Hall of Fame : build/hof.bin
    hof_trk = trk
    trk += (HOF_N + 8) // 9
    layout['boss'] = dict(track=trk, data=BOSS_N * 512)         # code du boss (banque 7) : build/boss.bin
    boss_trk = trk
    json.dump(layout, open(os.path.join(BUILD, 'layout.json'), 'w'))
    build_menu()
    build_trucks()
    fr, dl, cp = mkmusic.build(os.path.join(ROOT, 'src', 'menu_music.asm'))
    jf, jb = mkmusic.build_raw('MusiqueNiveau_AY.vgm', 'depart de niveau', os.path.join(ROOT, 'src', 'jingle_level.asm'))
    print('jingle de niveau : %d images, %d octets' % (jf, jb))
    vf, vb = mkmusic.build_raw('MusiqueVictoire_AY.vgm', 'victoire de zone', os.path.join(ROOT, 'src', 'jingle_victory.asm'), 'jv')
    print('jingle de victoire : %d images, %d octets' % (vf, vb)); assert vf <= 230 and jb + vb <= JINGLE_BYTES
    import mkvictory
    wf, wb = mkmusic.write_raw(mkvictory.frames(), 'victoire de la zone 3', os.path.join(ROOT, 'src', 'jingle_victory3.asm'), 'jw')
    print('jingle de victoire (zone 3) : %d images, %d octets' % (wf, wb)); assert wf <= 230
    print('musique du menu : %d images, %d octets compresses' % (len(fr), len(cp)))
    build_intro()
    build_access()
    with open(os.path.join(ROOT, 'src', 'layout.inc'), 'w') as f:
        f.write('; --- genere par tools/convert.py : disposition de la disquette et de la zone de preparation ---\n')
        f.write('COVER_TRK    equ %d\nCOVER_SEC    equ 0\nCOVER_N      equ %d\nCOVER_LOAD   equ #%04X\n' % (cover_trk, cover_n, COVER_LOAD))
        f.write('LOGO_TRK     equ %d\nLOGO_N       equ %d\n' % (logo_trk, logo_n))
        f.write('NZONES       equ %d\nZSTAGE       equ #%04X\n' % (len(ZONES), ZSTAGE))
        f.write('Z_SPAWN      equ %d\nZ_TILEMAP    equ %d\nZ_TKIND      equ %d\nZ_FRAMES     equ %d\nZ_TILES      equ %d\nZ_SPR        equ %d\n' % (Z_SPAWN, Z_TILEMAP, Z_TKIND, Z_FRAMES, Z_TILES, Z_SPR))
        f.write('TILE_BASE    equ #%04X\nZSPR_DST     equ #%04X\nZSPR_C       equ %d\nWHITE        equ #%02X\n' % (slot_addr(SLOT0_ZONE - 1), slot_addr(SLOT0_ZONE), SPRSLOT - SLOT0_ZONE % SPRSLOT, enc(13, 13)))
        f.write('MENU_TRK     equ %d\nMENU_N       equ %d\nMENU_LOAD    equ #%04X\nINTRO_TRK    equ %d\nINTRO_N      equ %d\nINTRO_LOAD   equ #%04X\nGO_TRK       equ %d\nGO_N         equ %d\nGO_LOAD      equ #5400\nHOF_TRK      equ %d\nHOF_N        equ %d\nHOF_LOAD     equ #4000\nBOSS_TRK     equ %d\nBOSS_N       equ %d\nBOSS_LOAD    equ #4000\nVOICE_FR     equ %d\nVOICE_OFF    equ #%X\nVOICE_LEN    equ %d\nTRUCK_OFF    equ #%X\nBOSS_PAD     equ #%X\n' % (menu_trk, MENU_N, MENU_LOAD, intro_trk, INTRO_N, INTRO_LOAD, gover_trk, GO_N, hof_trk, HOF_N, boss_trk, BOSS_N, VOICE_FR, VOICE_OFF, VOICE_LEN, TRUCK_OFF, BOSS_PAD))
        f.write('XSLOT_BASE   equ #%04X\nNXS          equ %d\nZ_ICON       equ %d\n' % (XSLOT_BASE, NXS, Z_ICON))
        f.write('tiles        equ ZSTAGE+Z_TILES\ntilemap      equ ZSTAGE+Z_TILEMAP\ntkind        equ ZSTAGE+Z_TKIND\n')
    with open(os.path.join(ROOT, 'src', 'zones.inc'), 'w') as f:
        f.write('; --- genere par tools/convert.py : repertoire des zones (piste, secteur, nombre de secteurs, adresse de lecture) ---\nzone_dir:\n')
        for t, sc, n, la in zdir: f.write(' db %d,%d,%d\n dw #%04X\n db 0\n' % (t, sc, n, la))
    print('logo : 16384 -> %d octets (%d secteurs, piste %d)' % (len(lcomp), logo_n, logo_trk))
    print('cover : 16384 -> %d octets (%d secteurs, piste %d)' % (len(ccomp), cover_n, cover_trk))
    for l in info: print(l)
    print('residents : %d images (Papi + explosions)' % len(uniq))

if __name__ == '__main__':
    main()
