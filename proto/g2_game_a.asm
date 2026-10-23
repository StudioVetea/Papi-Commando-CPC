;==============================================================================
;  PROTOTYPE 2 : scrolling vertical + ennemis, tirs, collisions
;  Moteur de sprites : chaque sprite memorise le fond qu'il recouvre (sauvegarde / restauration),
;  il est (re)dessine seulement quand le faisceau d'ecran n'est pas dessus (pas de clignotement).
;  Le jeu (ennemis, tirs) avance une image sur deux (25 Hz) ; le defilement et Papi restent a 50 Hz.
;==============================================================================
S_ACT   equ 0
S_DR    equ 1
S_X     equ 2
S_YL    equ 3
S_YH    equ 4
S_IMGL  equ 5
S_IMGH  equ 6
S_W     equ 7
S_H     equ 8
S_DIRTY equ 9
S_TROW  equ 10
S_OYL   equ 11
S_OYH   equ 12
S_DIR   equ 13
S_ANIM  equ 14
S_TMR   equ 15
S_COOL  equ 16
S_KIND  equ 18
S_IDX   equ 19
S_OX    equ 20          ; x dessine
S_SEQL  equ 21          ; numero d'ordre de dessin (16 bits) : l'effacement se fait en ordre inverse
S_SEQH  equ 22
NENM    equ 8                   ; ennemis : sprites 1..8 ; balles de Papi : 9..12 ; balles ennemies : 13..15

;------------------------------------------------------------------------------
spr_init:
        ld hl,SPR_TAB
        ld de,SPR_TAB+1
        ld bc,SPRN*SPSZ-1
        ld (hl),0
        ldir
        ld ix,SPR_TAB
        ld c,0
.i      ld (ix+S_IDX),c
        ld a,c
        or a
        jr z,.papi
        cp 9
        jr c,.enemy
        cp 13
        jr c,.pb
        ld (ix+S_KIND),3
        jr .bul
.pb     ld (ix+S_KIND),2
.bul    ld (ix+S_W),1
        ld (ix+S_H),6
        ld hl,bul_img
        ld (ix+S_IMGL),l
        ld (ix+S_IMGH),h
        jr .nx
.papi   ld (ix+S_KIND),0
        jr .big
.enemy  ld (ix+S_KIND),1
.big    ld (ix+S_W),6
        ld (ix+S_H),12
.nx     ld de,SPSZ
        add ix,de
        inc c
        ld a,c
        cp SPRN
        jr c,.i
        ; Papi
        ld ix,SPR_TAB
        ld (ix+S_ACT),1
        ld (ix+S_DIRTY),1
        call papi_sync
        ; ennemis : proches de Papi au depart
        ld a,40
        ld (sp_dmin),a
        ld ix,SPR_TAB+SPSZ
        ld b,NENM
.e      push bc
        call spawn_enemy
        pop bc
        ld de,SPSZ
        add ix,de
        djnz .e
        ld a,110
        ld (sp_dmin),a
        ret

; A = indice -> IX
get_spr:
        ld l,a
        ld h,0
        ld d,h
        ld e,l
        add hl,hl
        add hl,de               ; x 3
        add hl,hl
        add hl,hl
        add hl,hl               ; x 24
        ld de,SPR_TAB
        add hl,de
        push hl
        pop ix
        ret

; HL = adresse du tampon de fond de IX (donnees : +0, adresses ecran : +72)
bg_ptr:
        ld a,(ix+S_IDX)
        ld h,a
        ld l,0
        srl h
        rr l                    ; indice x 128
        ld a,h
        add a,BG_BASE/256
        ld h,a
        ret

;------------------------------------------------------------------------------
; nombre pseudo-aleatoire : HL (A = H)
rand:   ld hl,(rnd)
        ld a,h
        rra
        ld a,l
        rra
        xor h
        ld h,a
        ld a,l
        rra
        ld a,h
        rra
        xor l
        ld l,a
        xor h
        ld h,a
        ld (rnd),hl
        ret

; A / 6 -> A (E detruit)
div6:   ld e,0
.d      cp 6
        jr c,.e
        sub 6
        inc e
        jr .d
.e      ld a,e
        ret

; HL >> 3 -> A
shr3:   srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        ld a,l
        ret

; A = rangee, C = colonne -> A = 1 si la tuile est pleine (BC conserve)
solid_at:
        add a,a
        ld l,a
        ld h,0
        ld de,rowptr
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld d,0
        ld e,c
        add hl,de
        ld e,(hl)
        ld hl,tsolid
        add hl,de
        ld a,(hl)
        ret

; A = x (octet), HL = y (ligne) : CF = 1 si la boite des pieds (x+1..x+4, y+5..y+11) touche une tuile pleine ou sort de la carte
blocked:
        ld b,a
        bit 7,h
        jr nz,.yes
        push hl
        ld de,5
        add hl,de
        call shr3
        ld (bk_r0),a
        pop hl
        ld de,11
        add hl,de
        call shr3
        ld (bk_r1),a
        cp MAPH
        jr nc,.yes
        ld a,b
        cp 73
        jr nc,.yes
        inc a
        call div6
        ld (bk_c0),a
        ld a,b
        add a,4
        call div6
        ld (bk_c1),a
        ld a,(bk_r0)
        ld hl,(bk_c0)           ; L = c0, H = c1
        ld c,l
        call solid_at
        or a
        jr nz,.yes
        ld a,(bk_r0)
        ld hl,(bk_c0)
        ld c,h
        call solid_at
        or a
        jr nz,.yes
        ld a,(bk_r1)
        ld hl,(bk_c0)
        ld c,l
        call solid_at
        or a
        jr nz,.yes
        ld a,(bk_r1)
        ld hl,(bk_c0)
        ld c,h
        call solid_at
        or a
        jr nz,.yes
        or a                    ; CF = 0
        ret
.yes    scf
        ret

;------------------------------------------------------------------------------
; efface le sprite IX : restaure le fond sauvegarde
spr_erase:
        ld a,(ix+S_DR)
        or a
        ret z
        xor a
        ld (ix+S_DR),a
        ld a,(ix+S_TROW)        ; la rangee du haut (dynamique) est redessinee si le sprite l'a touchee
        ld hl,r_cur
        cp (hl)
        jr nc,.nd
        ld a,#FF
        ld (dyn_r),a
.nd     call bg_ptr
        ld a,(ix+S_W)
        cp 6
        jr nz,.one
        push hl
        ld de,72
        add hl,de
        push hl
        pop iy                  ; IY = table des adresses ecran
        pop hl                  ; HL = fond
        ld a,12
        ld (nline),a
.rl     ld e,(iy+0)
        ld d,(iy+1)
        inc iy
        inc iy
        ld a,d
        and 7
        cp 7
        jr nz,.f
        ld a,e
        cp #FB
        jr nc,.s
.f      ld bc,#7FFF
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        jr .n
.s      ld a,d
        and #F8
        ld c,a
        ld b,6
.sl     ld a,(hl)
        ld (de),a
        inc hl
        inc de
        ld a,d
        and 7
        or c
        ld d,a
        djnz .sl
.n      ld a,(nline)
        dec a
        ld (nline),a
        jr nz,.rl
        ret
.one    push hl                 ; balle : 1 octet x 6 lignes
        ld de,72
        add hl,de
        push hl
        pop iy
        pop hl
        ld b,6
.ol     ld e,(iy+0)
        ld d,(iy+1)
        inc iy
        inc iy
        ld a,(hl)
        ld (de),a
        inc hl
        djnz .ol
        ret

;------------------------------------------------------------------------------
; dessine le sprite IX (il n'est pas dessine) : calcule les adresses, sauvegarde le fond, melange
spr_draw:
        call bg_ptr
        ld (bgp),hl
        push hl
        ld de,72
        add hl,de
        ld (dsttp),hl
        pop hl
        ; --- table des adresses ecran (une par ligne) ---
        ld l,(ix+S_YL)
        ld h,(ix+S_YH)
        ld a,l
        and 7
        ld (yy),a               ; ligne dans la rangee
        call shr3               ; A = rangee
        ld (ix+S_TROW),a
        add a,a
        ld l,a
        ld h,0
        ld de,rowoff
        add hl,de
        ld (rofp),hl
        ld a,(ix+S_H)
        ld (nline),a
        ld iy,(dsttp)
.seg    ld hl,(rofp)
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (rofp),hl
        ld a,(ix+S_X)
        add a,e
        ld e,a
        jr nc,.n1
        inc d
.n1     ld a,d
        cp 8
        jr c,.n2
        sub 8
        ld d,a
.n2     ld a,(yy)
        add a,a
        add a,a
        add a,a
        or #C0
        or d
        ld d,a                  ; DE = adresse de la 1re ligne de ce segment
        ld a,8
        ld hl,yy
        sub (hl)                ; lignes restantes dans la rangee
        ld b,a
        ld a,(nline)
        cp b
        jr nc,.s2
        ld b,a                  ; moins de lignes que la place : on s'arrete avant la fin de la rangee
.s2     ld c,b                  ; c = lignes de ce segment
.sl     ld (iy+0),e
        ld (iy+1),d
        inc iy
        inc iy
        ld a,d
        add a,8
        ld d,a
        djnz .sl
        ld a,(nline)
        sub c
        ld (nline),a
        jr z,.tdone
        xor a
        ld (yy),a               ; les lignes suivantes commencent en haut de la rangee suivante
        jr .seg
.tdone  ; --- sauvegarde du fond ---
        ld a,(ix+S_W)
        cp 6
        jp nz,.draw1
        ld iy,(dsttp)
        ld de,(bgp)
        ld bc,#7FFF
        ld a,12
        ld (nline),a
.sv     ld l,(iy+0)
        ld h,(iy+1)
        inc iy
        inc iy
        ld a,h
        and 7
        cp 7
        jr nz,.sf
        ld a,l
        cp #FB
        jr nc,.ss
.sf     ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        jr .sn
.ss     ld a,h                  ; ligne a cheval sur la fin du tampon
        and #F8
        ld (spl),a
        ld c,6
.ssl    ldi
        ld a,h
        and 7
        ld b,a
        ld a,(spl)
        or b
        ld h,a
        ld a,c
        or a
        jr nz,.ssl
        ld bc,#7FFF
.sn     ld a,(nline)
        dec a
        ld (nline),a
        jr nz,.sv
        ; --- melange (masque, donnee) ---
        ld iy,(dsttp)
        ld l,(ix+S_IMGL)
        ld h,(ix+S_IMGH)
        ld a,12
        ld (nline),a
.bl     ld e,(iy+0)
        ld d,(iy+1)
        inc iy
        inc iy
        ld a,d
        and 7
        cp 7
        jr nz,.bf
        ld a,e
        cp #FB
        jr nc,.bs
.bf     ld a,(de)
        and (hl)
        inc hl
        or (hl)
        inc hl
        ld (de),a
        inc de
        ld a,(de)
        and (hl)
        inc hl
        or (hl)
        inc hl
        ld (de),a
        inc de
        ld a,(de)
        and (hl)
        inc hl
        or (hl)
        inc hl
        ld (de),a
        inc de
        ld a,(de)
        and (hl)
        inc hl
        or (hl)
        inc hl
        ld (de),a
        inc de
        ld a,(de)
        and (hl)
        inc hl
        or (hl)
        inc hl
        ld (de),a
        inc de
        ld a,(de)
        and (hl)
        inc hl
        or (hl)
        inc hl
        ld (de),a
        jr .bn
.bs     ld a,d
        and #F8
        ld b,a
        ld c,6
.bsl    ld a,(de)
        and (hl)
        inc hl
        or (hl)
        inc hl
        ld (de),a
        inc de
        ld a,d
        and 7
        or b
        ld d,a
        dec c
        jr nz,.bsl
.bn     ld a,(nline)
        dec a
        ld (nline),a
        jr nz,.bl
        ret
.draw1  ; balle : 1 octet x 6 lignes
        ld iy,(dsttp)
        ld de,(bgp)
        ld l,(ix+S_IMGL)
        ld h,(ix+S_IMGH)
        ld b,6
.d1     push bc
        ld c,(iy+0)
        ld b,(iy+1)
        inc iy
        inc iy
        ld a,(bc)
        ld (de),a               ; fond
        inc de
        and (hl)
        inc hl
        or (hl)
        inc hl
        ld (bc),a
        pop bc
        djnz .d1
        ret

;------------------------------------------------------------------------------
; le sprite IX est-il affichable : actif et entierement dans les rangees persistantes r+1 .. r+23 ? -> A = 1 / 0
vis_calc:
        ld a,(ix+S_ACT)
        or a
        ret z
        ld l,(ix+S_YL)
        ld h,(ix+S_YH)
        call shr3
        ld c,a
        ld a,(r_cur)
        inc a
        cp c
        jr z,.t2
        jr nc,.no               ; r_cur+1 > rangee du haut
.t2     ld l,(ix+S_YL)
        ld h,(ix+S_YH)
        ld e,(ix+S_H)
        ld d,0
        add hl,de
        dec hl
        call shr3
        ld c,a
        ld a,(r_cur)
        add a,23
        cp c
        jr c,.no                ; rangee du bas > r_cur+23
        ld a,1
        ret
.no     xor a
        ret

; marque 'sale' les sprites dont la visibilite a change
vis_scan:
        ld ix,SPR_TAB
        ld b,SPRN
.v      push bc
        call vis_calc
        ld c,a
        ld a,(ix+S_DR)
        cp c
        jr z,.nx
        ld (ix+S_DIRTY),1
.nx     pop bc
        ld de,SPSZ
        add ix,de
        djnz .v
        ret

;------------------------------------------------------------------------------
; recouvrement des rectangles dessines de IX et IY -> CF = 1 s'ils se recouvrent
overlap:
        ld a,(iy+S_OX)
        sub (ix+S_OX)
        jr nc,.px
        neg
        cp (iy+S_W)
        jr nc,.no
        jr .y
.px     cp (ix+S_W)
        jr nc,.no
.y      ld l,(iy+S_OYL)
        ld h,(iy+S_OYH)
        ld e,(ix+S_OYL)
        ld d,(ix+S_OYH)
        or a
        sbc hl,de
        ld a,h
        or a
        jr z,.pos
        inc a
        jr nz,.no
        ld a,l
        or a
        jr z,.no
        neg
        cp (iy+S_H)
        jr nc,.no
        scf
        ret
.pos    ld a,l
        cp (ix+S_H)
        jr nc,.no
        scf
        ret
.no     or a
        ret

; parcourt les sprites dessines apres IX qui le recouvrent (recursif) ; mode 0 : verifie le faisceau, 1 : efface
chain:
        ld iy,SPR_TAB
        ld b,SPRN
.l      push bc
        ld a,(iy+S_DR)
        or a
        jr z,.nx
        push iy
        pop de
        push ix
        pop hl
        or a
        sbc hl,de
        jr z,.nx
        ld l,(iy+S_SEQL)
        ld h,(iy+S_SEQH)
        ld e,(ix+S_SEQL)
        ld d,(ix+S_SEQH)
        or a
        sbc hl,de
        jr z,.nx
        bit 7,h
        jr nz,.nx               ; dessine avant IX
        call overlap
        jr nc,.nx
        push iy
        push ix
        push iy
        pop ix
        call chain
        call child_post
        pop ix
        pop iy
.nx     pop bc
        ld de,SPSZ
        add iy,de
        djnz .l
        ret

child_post:
        ld a,(cmode)
        or a
        jr nz,.er
        call sprite_safe
        or a
        ret nz
        ld a,1
        ld (cunsafe),a
        ret
.er     call spr_erase
        ld (ix+S_DIRTY),1
        ret

cmode   db 0
cunsafe db 0
seqc    dw 0

;------------------------------------------------------------------------------
; traite le sprite IX : efface (apres les sprites dessines par-dessus) puis redessine -> A = 1 fait, 0 differe
spr_process:
        ld a,(ix+S_DR)
        or a
        jr z,.nc
        xor a
        ld (cmode),a
        ld (cunsafe),a
        call chain
        ld a,(cunsafe)
        or a
        jr z,.go
        xor a
        ret
.go     ld a,1
        ld (cmode),a
        call chain
.nc     call spr_erase
        call vis_calc
        or a
        jr z,.end
        call spr_draw
        ld (ix+S_DR),1
        ld a,(ix+S_YL)
        ld (ix+S_OYL),a
        ld a,(ix+S_YH)
        ld (ix+S_OYH),a
        ld a,(ix+S_X)
        ld (ix+S_OX),a
        ld hl,(seqc)
        inc hl
        ld (seqc),hl
        ld (ix+S_SEQL),l
        ld (ix+S_SEQH),h
.end    ld (ix+S_DIRTY),0
        ld hl,jobs
        inc (hl)
        ld a,1
        ret
