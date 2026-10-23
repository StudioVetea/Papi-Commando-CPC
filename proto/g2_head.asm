;==============================================================================
;  PROTOTYPE : SCROLLING VERTICAL FLUIDE - Papi Commando CPC
;  Programme separe du jeu. rasm proto/scroll.asm -o proto/scroll -eo   puis   RUN"SCROLL"
;
;  Principe (tout est fait avec le CRTC 6845, aucune recopie de l'ecran) :
;   - l'ecran est un tampon CIRCULAIRE de 2 Ko par plan (les bits MA10/MA11 du CRTC ne sont pas
;     cables a la RAM) : la rangee de carte m est toujours a (78*m) mod 2048 ; le CRTC demarre
;     simplement a la rangee r = cy/8 (registres R12/R13) : defilement de 8 lignes gratuit
;   - defilement fin (2 lignes) : la 1re rangee affichee ne fait que h = 8-s lignes (R9 = h-1,
;     ecrit au bon moment), la derniere 8-h lignes (R9 = 7-h), la somme reste 8 lignes : l'image
;     garde 192 lignes et la synchro verticale ne bouge pas
;   - la 1re rangee est redessinee chaque image depuis les tuiles (elle montre le BAS de la
;     rangee r), les rangees 1..24 sont dessinees une seule fois, quand elles entrent
;==============================================================================
        org #0200
        run boot

STACK       equ #0200
VARS        equ #3F00
icnt        equ VARS+0          ; numero de l'interruption (0..5) dans l'image
cy          equ VARS+1          ; camera : ligne de carte tout en haut de l'ecran (16 bits)
s_cur       equ VARS+3          ; cy mod 8 de l'image affichee (0,2,4,6)
r_cur       equ VARS+4
s_nxt       equ VARS+5          ; idem pour l'image suivante
r_nxt       equ VARS+6
drawn_r     equ VARS+7          ; rangee r pour laquelle les rangees 1..24 sont dessinees
py          equ VARS+8          ; Papi : ligne de carte (16 bits)
px          equ VARS+10         ; Papi : octet (0..72)
opx         equ VARS+11
opy         equ VARS+12         ; (16 bits)
ofrm        equ VARS+14         ; image dessinee (adresse, 16 bits)
anim        equ VARS+16
dir         equ VARS+17
inp         equ VARS+18
dyn_r       equ VARS+19
dyn_s       equ VARS+20
row_ys6     equ VARS+21         ; (16 bits) 6 x ligne source de depart
row_n       equ VARS+23         ; nombre de lignes a copier
mapp        equ VARS+24         ; (16 bits) pointeur dans la rangee de la carte
colcnt      equ VARS+26
slow_dst    equ VARS+27         ; (16 bits)
spr_ptr     equ VARS+29         ; (16 bits)
rofp        equ VARS+31         ; (16 bits) pointeur dans rowoff
yy          equ VARS+33
nline       equ VARS+34
spl         equ VARS+35         ; (16 bits) adresse de la ligne de sprite en cours
tm          equ VARS+37
tc          equ VARS+38
keymap      equ VARS+48         ; 10 octets
nfrm        equ VARS+60         ; (16 bits) image de Papi a dessiner
force       equ VARS+62         ; 1 = redessiner Papi (une rangee vient d'etre dessinee)
er_row      equ VARS+63
er_bot      equ VARS+64
er_c        equ VARS+65
er_c0       equ VARS+66
er_c1       equ VARS+67
dr_c0       equ VARS+68         ; premiere colonne a dessiner (draw_row)
dr_n        equ VARS+69         ; nombre de colonnes
dyn_late    equ VARS+70         ; 1 = colonnes 8..12 de la rangee du haut encore a dessiner
dyn_row     equ VARS+71
ready       equ VARS+72         ; 1 = l'image suivante est prete (publiee par la boucle principale)
pub_r       equ VARS+73
pub_s       equ VARS+74
pub_hi      equ VARS+75         ; R12/R13 de l'image suivante
pub_lo      equ VARS+76
frame_flag  equ VARS+77         ; mis a 1 par l'interruption au debut de chaque image
past        equ VARS+78         ; mis a 1 quand le faisceau est passe sous l'image (ligne ~195)
w_r         equ VARS+79         ; etat de travail (image suivante)
w_s         equ VARS+80
miss        equ VARS+92         ; compteur d'images sans publication (retard)
total       equ VARS+93
misspc      equ VARS+94
past3       equ VARS+96
dbg0        equ VARS+106
pre_h       equ VARS+107        ; 0 rien, 1 colonnes 0..6 faites, 2 rangee complete
dbg1        equ VARS+103
dbg2        equ VARS+104
dbg3        equ VARS+105
pre_r       equ VARS+102        ; rangee deja pre-dessinee dans l'espace libre (#FF = aucune)
bgp         equ VARS+97
dsttp       equ VARS+99
bgv         equ VARS+101        ; 1 = fond sauvegarde valide
bgbuf       equ #3F80           ; 12 lignes x 6 octets
bgdst       equ #3FD0           ; 12 adresses ecran         ; faisceau passe la ligne 130
ent         equ VARS+81         ; copie de l'entree ab_tab (10 octets)
; --- moteur de sprites / jeu (g2) ---
tickf       equ VARS+110        ; parite de l'image (le jeu avance une image sur deux)
rnd         equ VARS+111        ; (16 bits) generateur pseudo-aleatoire
kills       equ VARS+113        ; (16 bits)
hits        equ VARS+115        ; (16 bits)
invuln      equ VARS+117        ; images d'invulnerabilite de Papi
pcool       equ VARS+118        ; delai de tir de Papi
spawn_t     equ VARS+119        ; delai avant la prochaine apparition
cyd         equ VARS+120        ; (16 bits) ligne de carte du haut de l'ecran AFFICHE
sp_tmp      equ VARS+122        ; (16 bits)
sp_tmp2     equ VARS+124        ; (16 bits)
jobs        equ VARS+126        ; sprites traites (compteur)
nsafe       equ VARS+127
tw_x        equ VARS+128        ; collision : case a tester
tw_y        equ VARS+129        ; (16 bits)
dbgn        equ VARS+131
sp_dmin     equ VARS+132
bk_c0       equ VARS+133
bk_c1       equ VARS+134
bk_r0       equ VARS+135
bk_r1       equ VARS+136
SPRN        equ 16
SPSZ        equ 24
SPR_TAB     equ #4000           ; SPRN x 24 octets
BG_BASE     equ #4400           ; SPRN x 128 octets : fond (72) + adresses ecran (24)

; ---- reperes de synchro (lignes de l'image, 0 = haut de l'affichage) : voir calibrage ----
DBG         equ 0               ; 1 = traits de couleur sur la bordure aux instants des ecritures du CRTC

boot:   di
        ld sp,STACK
        ld bc,#7F8C
        out (c),c
        ld hl,palette
        call set_palette
        ld hl,#C000
        ld de,#C001
        ld bc,#3FFF
        ld (hl),0
        ldir
        ld hl,VARS
        ld de,VARS+1
        ld bc,#7F
        ld (hl),0
        ldir
        ld hl,crtc_tab
        ld d,0
.crt    ld bc,#BC00
        out (c),d
        ld b,#BD
        ld a,(hl)
        out (c),a
        inc hl
        inc d
        ld a,d
        cp 14
        jr nz,.crt
        ld a,#C3
        ld (#38),a
        ld hl,isr
        ld (#39),hl
        im 1
        ; --- etat initial : camera en bas de la carte, Papi au milieu de la bande ---
        ld hl,CYMAX
        ld (cy),hl
        ld hl,CYMAX+100
        ld (py),hl
        ld a,33
        ld (px),a
        ld hl,#ACE1
        ld (rnd),hl
        call cam_split          ; A = r, C = s
        ld (r_nxt),a
        ld (r_cur),a
        ld (drawn_r),a
        ld a,c
        ld (s_nxt),a
        ld (s_cur),a
        ld a,#FF
        ld (dyn_r),a
        ld (pre_r),a
        xor a
        ld (pre_h),a
        ; rangees persistantes r+1 .. r+24
        ld a,(r_cur)
        inc a
        ld b,24
.ini    push af
        push bc
        call full_row
        pop bc
        pop af
        inc a
        djnz .ini
        call dyn_early          ; rangee du haut (image affichee)
        call spr_init           ; table des sprites (Papi, ennemis)
        ; --- etat publie = etat affiche ; synchronisation sur la fin du balayage (VSYNC) ---
        ld a,(r_cur)
        ld (pub_r),a
        ld a,(s_cur)
        ld (pub_s),a
        call set_start_pub
        ei
        ld b,#F5
.v1     in a,(c)
        rra
        jr c,.v1
.v2     in a,(c)
        rra
        jr nc,.v2
        xor a
        ld (icnt),a             ; VSYNC vient de commencer : l'interruption de la ligne 234 (2 lignes apres) arrive
.v3     ld a,(icnt)
        or a
        jr z,.v3
        ld a,5
        ld (icnt),a             ; c'etait la numero 5 : la suivante (ligne 286) est la numero 0
        jp mainloop

dlyhl:  dec hl                  ; HL iterations de 7 NOPs
        ld a,h
        or l
        jr nz,dlyhl
        ret

; ecrit la valeur A dans le registre CRTC C (non critique)
crtc_w: ld b,#BC
        out (c),c
        ld b,#BD
        out (c),a
        ret

set_palette:
        ld c,#7F
        xor a
.p      ld b,#7F
        out (c),a
        ld e,(hl)
        out (c),e
        inc hl
        inc a
        cp 17
        jr nz,.p
        ret

;------------------------------------------------------------------------------
; cy -> A = r = cy/8, C = s = cy mod 8
cam_split:
        ld hl,(cy)
        ld a,l
        and 7
        ld c,a
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        ld a,l
        ret

; R12/R13 de la rangee pub_r (calcule dans pub_hi/pub_lo)
set_start_pub:
        ld a,(pub_r)
        call calc_start
        ld a,(pub_hi)
        ld c,12
        call crtc_w
        ld a,(pub_lo)
        ld c,13
        jp crtc_w

calc_start:                     ; A = rangee -> pub_hi, pub_lo
        add a,a
        ld l,a
        ld h,0
        ld de,rowoff
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        srl d
        rr e                    ; DE = decalage en mots
        ld a,d
        or #30
        ld (pub_hi),a
        ld a,e
        ld (pub_lo),a
        ret

;------------------------------------------------------------------------------
; copie d'une tuile : HL = source, DE = destination (plan 0), (row_n) lignes de 6 octets
copy_tile:
        ld a,(row_n)
        ld iyl,a
        ld a,d
        and 7
        cp 7
        jr nz,.fast
        ld a,e
        cp #FB
        jr nc,.slow
.fast   ld bc,#7FFF
.fl     ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ld a,e
        sub 6
        ld e,a
        ld a,d
        sbc a,0
        add a,8
        ld d,a
        dec iyl
        jr nz,.fl
        ret
.slow   ld (slow_dst),de
        ld c,0
.sl     ld a,(slow_dst+1)
        add a,c
        ld d,a
        and #F8
        ld ixh,a
        ld a,(slow_dst)
        ld e,a
        ld b,6
.sb     ld a,(hl)
        ld (de),a
        inc hl
        inc de
        ld a,d
        and 7
        or ixh
        ld d,a
        djnz .sb
        ld a,c
        add a,8
        ld c,a
        dec iyl
        jr nz,.sl
        ret

; dessine les tuiles dr_c0 .. dr_c0+dr_n-1 de la rangee A de la carte : lignes row_ys6/6 ... (row_n lignes) -> plans 0...
draw_row:
        add a,a
        ld l,a
        ld h,0
        push hl
        ld de,rowptr
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld a,(dr_c0)
        ld e,a
        ld d,0
        add hl,de
        ld (mapp),hl
        pop hl
        ld de,rowoff
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)               ; DE = decalage de la rangee
        ld a,(dr_c0)
        ld l,a
        add a,a
        add a,l
        add a,a                 ; 6 x colonne de depart
        add a,e
        ld e,a
        jr nc,.o1
        inc d
.o1     ld a,d
        cp 8
        jr c,.o2
        sub 8
        ld d,a
.o2     ld a,d
        or #C0
        ld d,a
        ld a,(dr_n)
        ld (colcnt),a
.col    push de
        ld hl,(mapp)
        ld a,(hl)
        inc hl
        ld (mapp),hl
        add a,a
        ld l,a
        ld h,0
        ld bc,tile_addr
        add hl,bc
        ld c,(hl)
        inc hl
        ld b,(hl)
        ld hl,(row_ys6)
        add hl,bc
        call copy_tile
        pop de
        ld hl,6
        add hl,de
        bit 3,h
        jr z,.nw
        res 3,h
.nw     ex de,hl
        ld a,(colcnt)
        dec a
        ld (colcnt),a
        jr nz,.col
        ret

; la rangee du haut de l'image suivante : le bas de la rangee r_nxt (lignes s .. 7).
; dyn_early : colonnes 0..7 (ou 0..12 si on ne risque rien), dyn_finish : colonnes 8..12 (apres le balayage du bas de l'ecran)
dyn_early:
        xor a
        ld (dyn_late),a
        ld a,(r_nxt)
        ld b,a
        ld a,(s_nxt)
        ld c,a
        or a
        jr nz,.nsk
        ld a,(r_cur)            ; on avance d'une rangee pile : la rangee r_cur+1 est deja complete (persistante) -> rien a dessiner
        inc a
        cp b
        jr nz,.nsk
        ld a,b
        ld (dyn_r),a
        xor a
        ld (dyn_s),a
        ret
.nsk    ld a,c
        ld a,(dyn_r)
        cp b
        jr nz,.go
        ld a,(dyn_s)
        cp c
        ret z
.go     ld a,b
        ld (dyn_r),a
        ld a,c
        ld (dyn_s),a
        ld e,a                  ; s
        add a,a
        add a,e
        add a,a                 ; 6 x s
        ld l,a
        ld h,0
        ld (row_ys6),hl
        ld a,8
        sub e
        ld (row_n),a
        xor a
        ld (dr_c0),a
        ld a,13
        ld (dr_n),a
.all    ld a,(r_nxt)
        jp draw_row

dyn_finish:
        ld a,(dyn_late)
        or a
        ret z
        xor a
        ld (dyn_late),a
        ld a,8
        ld (dr_c0),a
        ld a,5
        ld (dr_n),a
        ld a,(r_nxt)
        jp draw_row

; colonnes B .. B+C-1 de la rangee A (lignes completes)
row_cols:
        cp MAPH
        ret nc
        ld hl,0
        ld (row_ys6),hl
        ld d,a
        ld a,8
        ld (row_n),a
        ld a,b
        ld (dr_c0),a
        ld a,c
        ld (dr_n),a
        ld a,d
        jp draw_row

; rangee persistante : toutes les lignes
full_row:
        cp MAPH
        ret nc
        ld hl,0
        ld (row_ys6),hl
        ld b,a
        ld a,8
        ld (row_n),a
        xor a
        ld (dr_c0),a
        ld a,13
        ld (dr_n),a
        ld a,b
        jp draw_row

;------------------------------------------------------------------------------
; une tuile (A = rangee de carte, C = colonne) en entier : sert a effacer Papi
draw_tile:
        ld b,a
        ld a,(r_nxt)            ; seulement dans les rangees persistantes (r+1 .. r+24)
        inc a
        ld e,a
        ld a,b
        cp e
        ret c
        ld a,(r_nxt)
        add a,24
        cp b
        ret c
        ld a,b
        cp MAPH
        ret nc
        ld (tm),a
        ld a,c
        ld (tc),a
        ld a,b
        add a,a
        ld l,a
        ld h,0
        push hl
        ld de,rowptr
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld a,(tc)
        ld e,a
        ld d,0
        add hl,de
        ld a,(hl)               ; indice de tuile
        add a,a
        ld l,a
        ld h,0
        ld bc,tile_addr
        add hl,bc
        ld c,(hl)
        inc hl
        ld b,(hl)               ; BC = tuile
        pop hl
        ld de,rowoff
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)               ; DE = decalage de la rangee
        ld a,(tc)
        ld l,a
        add a,a
        add a,l
        add a,a                 ; 6 x colonne
        add a,e
        ld e,a
        jr nc,.nc
        inc d
.nc     ld a,d
        cp 8
        jr c,.nw
        sub 8
        ld d,a
.nw     ld a,d
        or #C0
        ld d,a
        ld h,b
        ld l,c
        ld a,8
        ld (row_n),a
        jp copy_tile

