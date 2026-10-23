;------------------------------------------------------------------------------
; Papi
; image courante (dir, anim) -> HL
papi_frame:
        ld a,(dir)
        add a,a
        add a,a
        ld b,a
        ld a,(anim)
        rrca
        rrca
        and 3
        add a,b
        add a,a
        ld l,a
        ld h,0
        ld de,papi_tab
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret

; dessine Papi (HL = image) en (px, py) : masque, 12 lignes de 6 octets
draw_papi:
        ld (spr_ptr),hl
        ld hl,bgbuf
        ld (bgp),hl
        ld hl,bgdst
        ld (dsttp),hl
        ld hl,(py)
        ld a,l
        and 7
        ld (yy),a
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l                    ; L = rangee
        ld a,l
        add a,a
        ld l,a
        ld h,0
        ld de,rowoff
        add hl,de
        ld (rofp),hl
        ld a,12
        ld (nline),a
.line   ld hl,(rofp)
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (rofp),hl
        ld a,(px)
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
        ld b,a                  ; bits de plan
        or d
        ld d,a
        ld hl,(dsttp)           ; adresse ecran de la ligne
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (dsttp),hl
        ld a,d
        and 7
        cp 7
        jr nz,.sf
        ld a,e
        cp #FB
        jr nc,.ss
.sf     ld h,d                  ; sauvegarde du fond (cas normal) : HL = ecran, DE = tampon
        ld l,e
        ld de,(bgp)
        push bc
        ld bc,#7FFF
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        pop bc
        ld (bgp),de
        ld hl,(dsttp)
        dec hl
        ld d,(hl)
        dec hl
        ld e,(hl)
        jr .sv
.ss     push de                 ; sauvegarde du fond (ligne a cheval sur le bout du tampon)
        ld hl,(bgp)
        ld c,6
.ssl    ld a,(de)
        ld (hl),a
        inc hl
        inc de
        ld a,d
        and 7
        or b
        ld d,a
        dec c
        jr nz,.ssl
        ld (bgp),hl
        pop de
.sv     ld hl,(spr_ptr)
        ld a,d
        and 7
        cp 7
        jr nz,.fast
        ld a,e
        cp #FB
        jr nc,.slow
.fast   ld c,6
.fb     ld a,(de)
        and (hl)
        inc hl
        or (hl)
        inc hl
        ld (de),a
        inc de
        dec c
        jr nz,.fb
        jr .nl
.slow   ld c,6
.sbb    ld a,(de)
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
        jr nz,.sbb
.nl     ld (spr_ptr),hl
        ld a,(yy)
        inc a
        cp 8
        jr c,.ok
        xor a
.ok     ld (yy),a
        jr nz,.nr
        jr .nr2                 ; rangee suivante : rofp pointe deja sur rowoff[m+1]
.nr     ld hl,(rofp)            ; meme rangee : revenir sur le meme decalage
        dec hl
        dec hl
        ld (rofp),hl
.nr2    ld hl,nline
        dec (hl)
        jp nz,.line
        ld a,1
        ld (bgv),a
        ret

; efface Papi : restaure le fond sauvegarde
erase_papi:
        ld a,(bgv)
        or a
        ret z
        ld hl,bgbuf
        ld ix,bgdst
        ld a,12
        ld iyl,a
.rl     ld e,(ix+0)
        ld d,(ix+1)
        inc ix
        inc ix
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
.n      dec iyl
        jr nz,.rl
        ret

div6:   ld c,0                  ; A / 6 -> A
.d      cp 6
        jr c,.e
        sub 6
        inc c
        jr .d
.e      ld a,c
        ret

sprites:
        call papi_frame
        ld (nfrm),hl
        ld a,(force)
        or a
        jr nz,.go
        ld a,(px)
        ld hl,opx
        cp (hl)
        jr nz,.go
        ld hl,(py)
        ld de,(opy)
        or a
        sbc hl,de
        jr nz,.go
        ld hl,(nfrm)
        ld de,(ofrm)
        or a
        sbc hl,de
        ret z
.go     call erase_papi
        ld hl,(nfrm)
        call draw_papi
        ld a,(px)
        ld (opx),a
        ld hl,(py)
        ld (opy),hl
        ld hl,(nfrm)
        ld (ofrm),hl
        xor a
        ld (force),a
        ret

;------------------------------------------------------------------------------
; clavier / manette
readkeys:
        ld hl,keymap
        ld bc,#F782
        out (c),c
        ld bc,#F40E
        ld e,b
        out (c),c
        ld bc,#F6C0
        ld d,b
        out (c),c
        ld c,0
        out (c),c
        ld bc,#F792
        out (c),c
        ld a,#40
        ld c,#4A
.k      ld b,d
        out (c),a
        ld b,e
        ini
        inc a
        cp c
        jr c,.k
        ld bc,#F782
        out (c),c
        ld a,(keymap+9)
        cpl
        and #1F
        ld c,a
        ld a,(keymap+0)
        cpl
        ld b,a
        bit 0,b
        jr z,.a
        set 0,c
.a      bit 2,b
        jr z,.b
        set 1,c
.b      bit 1,b
        jr z,.c
        set 3,c
.c      ld a,(keymap+1)
        cpl
        bit 0,a
        jr z,.d
        set 2,c
.d      ld a,(keymap+5)
        cpl
        and #80
        jr z,.e
        set 4,c
.e      ld a,c
        ld (inp),a
        ret

; deplacement de Papi + camera
update:
        call readkeys
        ld a,(inp)
        ld c,a
        ld e,2                  ; vitesse verticale : 2 lignes par image (4 avec TIR)
        bit 4,c
        jr z,.sp
        ld e,4
.sp     ld a,c
        and 15
        jr z,.idle
        ld hl,anim
        inc (hl)
        jr .mv
.idle   xor a
        ld (anim),a
.mv     ld hl,(py)
        bit 0,c
        jr z,.nu
        ld d,0
        or a
        sbc hl,de
        xor a
        ld (dir),a              ; 0 = haut
.nu     bit 1,c
        jr z,.nd
        ld d,0
        add hl,de
        ld a,1
        ld (dir),a              ; 1 = bas
.nd     ld (py),hl
        ld a,(px)
        bit 2,c
        jr z,.nl
        or a
        jr z,.nl
        dec a
        ld b,2
        ld (px),a
        ld a,b
        ld (dir),a              ; 2 = gauche
        ld a,(px)
.nl     bit 3,c
        jr z,.nr
        cp 72
        jr nc,.nr
        inc a
        ld (px),a
        ld a,3
        ld (dir),a              ; 3 = droite
.nr     ; limites de la carte
        ld hl,(py)
        bit 7,h
        jr z,.p1
        ld hl,0
.p1     ld de,MAPH*8-12
        or a
        sbc hl,de
        add hl,de
        jr c,.p3
        ld hl,MAPH*8-12
.p3     ld (py),hl
        ; camera : Papi reste entre 72 et 104 lignes du haut de l'ecran
        ld de,(cy)
        or a
        sbc hl,de               ; HL = py - cy
        ld a,h
        or a
        jr nz,.below
        ld a,l
        cp 72
        jr c,.tophi
        cp 105
        jr c,.cyok
.below  ld hl,(py)
        ld de,104
        or a
        sbc hl,de
        ld de,CYMAX
        or a
        sbc hl,de
        add hl,de
        jr c,.setcy
        ld hl,CYMAX
        jr .setcy
.tophi  ld hl,(py)
        ld de,72
        or a
        sbc hl,de
        jr nc,.setcy
        ld hl,0
.setcy  ld (cy),hl
.cyok   ld hl,(py)              ; Papi reste a au moins 8 lignes des bords de l'ecran
        ld de,(cy)
        or a
        sbc hl,de
        bit 7,h
        jr nz,.lo
        ld a,h
        or a
        jr nz,.hi2
        ld a,l
        cp 8
        jr c,.lo
        cp 173
        jr c,.done
.hi2    ld hl,(cy)
        ld de,172
        add hl,de
        ld (py),hl
        ret
.lo     ld hl,(cy)
        ld de,8
        add hl,de
        ld (py),hl
.done   ret

;------------------------------------------------------------------------------
; boucle d'images, pilotee par l'interruption (les ecritures chronometrees du CRTC sont faites DANS l'interruption :
; elles restent exactes meme si la boucle principale est en retard)
;  interruptions (lignes de l'image) : 0 = 286, 1 = 26, 2 = 78, 3 = 130, 4 = 182, 5 = 234
OVA     equ 220                 ; NOPs entre l'interruption et l'ecriture A (entree d'interruption, recopie...)
OVB     equ 14
OVC     equ 220
OVD     equ 14
FIXA    equ -61
FIXB    equ 0
FIXC    equ 0
FIXD    equ 0

; par s = 2, 4, 6 (h = 6, 4, 2) : R9 de A (h-1), delai A, delai B, R9 de C (7-h), delai C, delai D
ab_tab:
        db 5
        dw ((33*64+6*32-OVA)/7)+FIXA
        dw ((6*64-OVB)/7)+FIXB
        db 1
        dw ((13*64+6*32-OVC)/7)+FIXC-73
        dw (((8-6)*64-OVD)/7)+FIXD
        db 3
        dw ((33*64+4*32-OVA)/7)+FIXA
        dw ((4*64-OVB)/7)+FIXB
        db 3
        dw ((13*64+4*32-OVC)/7)+FIXC-55
        dw (((8-4)*64-OVD)/7)+FIXD
        db 1
        dw ((33*64+2*32-OVA)/7)+FIXA
        dw ((2*64-OVB)/7)+FIXB
        db 5
        dw ((13*64+2*32-OVC)/7)+FIXC-37
        dw (((8-2)*64-OVD)/7)+FIXD

get_entry:                      ; recopie l'entree de ab_tab de s_cur (2, 4 ou 6) dans ent
        ld a,(s_cur)
        srl a
        dec a
        ld l,a
        ld h,0
        add hl,hl
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,de               ; x 10
        ld de,ab_tab
        add hl,de
        ld de,ent
        ld bc,10
        ldir
        ret

isr:    push af
        push bc
        push de
        push hl
        ld a,(icnt)
        inc a
        cp 6
        jr c,.o
        xor a
.o      ld (icnt),a
        or a
        jp z,isr0
        cp 4
        jp z,isr4
        cp 3
        jp z,isr3
.out    pop hl
        pop de
        pop bc
        pop af
        ei
        ret

; interruption 0 (ligne 286) : l'image suivante commence dans 26 lignes
isr0:   ld hl,total
        inc (hl)
        ld a,(ready)
        or a
        jr nz,.pub
        ld hl,miss
        inc (hl)
        ld hl,8
        add hl,sp
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (misspc),de
        jr .nopub
.pub
        xor a
        ld (ready),a
        ld a,(pub_r)
        ld (r_cur),a
        ld a,(pub_s)
        ld (s_cur),a
        ld a,(pub_hi)           ; R12/R13 : le CRTC les relit au debut de l'image
        ld c,12
        call crtc_w
        ld a,(pub_lo)
        ld c,13
        call crtc_w
.nopub  ld a,1
        ld (frame_flag),a
        xor a
        ld (past),a
        ld (past3),a
        ld a,(s_cur)
        or a
        jp z,.aligned
        call get_entry
        ld bc,#BC09
        out (c),c
        ld b,#BD
        ld a,(ent)
        ld e,a
        ld hl,(ent+1)
        call dlyhl
        out (c),e               ; <<< A : R9 <- h-1
        ld e,7
        ld hl,(ent+3)
        call dlyhl
        out (c),e               ; <<< B : R9 <- 7
        ld a,39                 ; R4 = 39 (40 rangees), R6 = 25, R7 = 30
        ld c,4
        call crtc_w
        ld a,25
        ld c,6
        call crtc_w
        ld a,30
        ld c,7
        call crtc_w
        jp isr.out
.aligned:
        ld hl,((33+12)*64-OVA)/7
        call dlyhl
        ld a,38                 ; image alignee : 24 rangees entieres (R9 reste 7)
        ld c,4
        call crtc_w
        ld a,24
        ld c,6
        call crtc_w
        ld a,29
        ld c,7
        call crtc_w
        jp isr.out

isr3:   ld a,1
        ld (past3),a
        jp isr.out

; interruption 4 (ligne 182) : derniere rangee raccourcie (C) puis retour a 8 lignes (D)
isr4:   ld a,(s_cur)
        or a
        jr z,.np
        call get_entry
        ld bc,#BC09
        out (c),c
        ld b,#BD
        ld a,(ent+5)
        ld e,a
        ld hl,(ent+6)
        call dlyhl
        out (c),e               ; <<< C : R9 <- 7-h
        ld e,7
        ld hl,(ent+8)
        call dlyhl
        out (c),e               ; <<< D : R9 <- 7
.np     ld a,1
        ld (past),a
        jp isr.out

;------------------------------------------------------------------------------
; boucle principale : attend le debut d'une image, prepare la suivante
wait_flag:                      ; attend que (HL) soit non nul
wf_a:   halt
        ld a,(hl)
        or a
        jr z,wf_a
wf_e:   ret

mainloop:
.wf     ld hl,frame_flag
        call wait_flag
        xor a
        ld (frame_flag),a
        call update
        call cam_split
        ld (r_nxt),a
        ld a,c
        ld (s_nxt),a
        ld a,(r_nxt)
        ld hl,drawn_r
        cp (hl)
        jr z,.nr
        jr c,.back
        ld (hl),a               ; on avance : la rangee r+24 entre (deja pre-dessinee, au moins en partie ?)
        add a,24
        ld b,a
        ld a,(pre_r)
        cp b
        jr nz,.full
        ld a,(pre_h)
        cp 2
        jr z,.skfr
        cp 1
        jr nz,.full
        ld a,b                  ; il reste les colonnes 7..12
        ld b,7
        ld c,6
        call row_cols
        jr .skfr
.full   ld a,b
        call full_row
.skfr   ld a,#FF
        ld (pre_r),a
        jr .forced
.back   ld (hl),a               ; on recule : la rangee r+1 (l'ancienne rangee du haut) devient persistante
        inc a
        call full_row
        ld a,#FF
        ld (pre_r),a
.forced ld a,1
        ld (force),a
        jr .nr2
.nr     ld a,(s_nxt)            ; pas de changement de rangee : on pre-dessine la rangee r+25 (espace libre), en deux moities
        cp 4
        jr c,.nr2
        ld a,(r_nxt)
        add a,25
        ld b,a
        ld a,(pre_r)
        cp b
        jr z,.same
        ld a,b
        ld (pre_r),a
        xor a
        ld (pre_h),a
.same   ld a,(pre_h)
        cp 2
        jr z,.nr2
        or a
        jr nz,.right
        ld a,1
        ld (pre_h),a
        ld a,(pre_r)
        ld b,0
        ld c,7
        call row_cols
        jr .nr2
.right  ld a,2
        ld (pre_h),a
        ld a,(pre_r)
        ld b,7
        ld c,6
        call row_cols
.nr2    call dyn_early
        ld a,(icnt)
        ld (dbg0),a
        ; Papi : si son rectangle (ancien et nouveau) est au-dessus de la ligne ~124, on peut commencer des que le faisceau a passe la ligne 130
        ld hl,(opy)
        ld de,(py)
        or a
        sbc hl,de
        ld hl,(opy)
        jr nc,.mx
        ld hl,(py)
.mx     ld de,11
        add hl,de
        ld a,l
        or 7
        ld l,a
        inc hl                  ; bas des tuiles couvertes (coordonnee carte)
        push hl
        ld a,(r_cur)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,(s_cur)
        ld e,a
        ld d,0
        add hl,de
        ex de,hl
        pop hl
        or a
        sbc hl,de               ; ligne ecran du bas du rectangle
        ld de,past
        jr c,.early
        ld a,h
        or a
        jr nz,.late
        ld a,l
        cp 129
        jr nc,.late
.early  ld de,past3
.late   ex de,hl
.wp     call wait_flag
        ld a,(icnt)
        ld (dbg1),a
        call sprites            ; Papi : pendant que le faisceau est sous l'image
        ld a,(icnt)
        ld (dbg2),a
        call dyn_finish
        ld a,(r_nxt)
        call calc_start
        di
        ld a,(r_nxt)
        ld (pub_r),a
        ld a,(s_nxt)
        ld (pub_s),a
        ld a,(icnt)
        ld (dbg3),a
        ld a,1
        ld (ready),a
        ei
        jp mainloop

crtc_tab:   db 63, 39, 46, #8E, 39, 0, 25, 30, 0, 7, 0, 0, #30, 0

        include 'data.inc'
        save 'SCROLL.BIN',#0200,$-#0200,DSK,'proto/scroll.dsk'
