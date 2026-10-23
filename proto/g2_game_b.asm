
; --- le faisceau est-il loin du rectangle ? ---
; HL = ligne de carte du haut du rectangle, E = hauteur -> A = 1 si on peut y toucher sans risque de scintillement
; (sp_tmp = ligne de carte du haut de l'ecran affiche, sp_tmp2 = ligne d'ecran de la derniere interruption)
rect_safe:
        ld bc,(sp_tmp)
        or a
        sbc hl,bc               ; HL = ligne d'ecran du haut (signee)
        push hl
        ld d,0
        add hl,de               ; HL = ligne du bas + 1
        bit 7,h
        jr nz,.ok
        ld a,h
        or l
        jr z,.ok                ; bas <= 0 : hors ecran
        ld de,6
        add hl,de
        ex de,hl                ; DE = bas + marge
        ld hl,(sp_tmp2)
        or a
        sbc hl,de               ; faisceau - (bas + marge)
        jr z,.ok
        bit 7,h
        jr z,.ok                ; le faisceau est deja passe sous le rectangle
        pop hl
        push hl                 ; HL = haut
        ld de,192
        or a
        sbc hl,de
        jr z,.ok
        bit 7,h
        jr z,.ok                ; haut >= 192 : hors ecran
        pop hl
        ld de,(sp_tmp2)
        ex de,hl                ; HL = faisceau, DE = haut
        ld bc,92
        add hl,bc               ; faisceau + 92 (prochaine interruption + duree du travail)
        ex de,hl                ; HL = haut, DE = faisceau + 92
        or a
        sbc hl,de
        jr z,.ok2
        bit 7,h
        jr z,.ok2               ; le haut est loin sous le faisceau
        xor a
        ret
.ok     pop hl
.ok2    ld a,1
        ret

; IX -> A = 1 si l'ancien et le nouveau rectangle du sprite sont loin du faisceau
sprite_safe:
        ld a,(ix+S_DR)
        or a
        jr z,.nold
        ld l,(ix+S_OYL)
        ld h,(ix+S_OYH)
        ld e,(ix+S_H)
        call rect_safe
        or a
        ret z
.nold   ld a,(ix+S_ACT)
        or a
        jr z,.yes
        ld l,(ix+S_YL)
        ld h,(ix+S_YH)
        ld e,(ix+S_H)
        jp rect_safe
.yes    ld a,1
        ret

JOBLIM  equ 4
beamtab:
        dw -26,26,78,130,182,234

; traite les sprites sales, un par un, quand le faisceau est loin ; rend la main quand l'image suivante commence
spr_job:
.top    ld a,(frame_flag)
        or a
        ret nz
        ld a,(icnt)
        cp JOBLIM
        ret nc                  ; trop tard dans l'image : le reste attend l'image suivante
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
        ld (sp_tmp),hl
        ld a,(icnt)
        add a,a
        ld e,a
        ld d,0
        ld hl,beamtab
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (sp_tmp2),de
        ld ix,SPR_TAB
        ld b,SPRN
        ld c,0
.sc     ld a,(ix+S_DIRTY)
        or a
        jr z,.nx
        inc c
        push bc
        call sprite_safe
        pop bc
        or a
        jr z,.nx
        call spr_process
        or a
        jr nz,.top
        jr .nx
.nx     ld de,SPSZ
        add ix,de
        djnz .sc
        ld a,c
        or a
        ret z
        call idle_halt
        jr .top

;------------------------------------------------------------------------------
; Papi -> sprite 0
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

papi_sync:
        ld ix,SPR_TAB
        ld c,1
        ld a,(invuln)
        and 4
        jr z,.s
        ld c,0
.s      ld a,(ix+S_ACT)
        cp c
        jr z,.a
        ld (ix+S_ACT),c
        ld (ix+S_DIRTY),1
.a      ld a,(px)
        cp (ix+S_X)
        jr z,.b
        ld (ix+S_X),a
        ld (ix+S_DIRTY),1
.b      ld hl,(py)
        ld a,l
        cp (ix+S_YL)
        jr nz,.c
        ld a,h
        cp (ix+S_YH)
        jr z,.d
.c      ld (ix+S_YL),l
        ld (ix+S_YH),h
        ld (ix+S_DIRTY),1
.d      call papi_frame
        ld a,l
        cp (ix+S_IMGL)
        jr nz,.e
        ld a,h
        cp (ix+S_IMGH)
        ret z
.e      ld (ix+S_IMGL),l
        ld (ix+S_IMGH),h
        ld (ix+S_DIRTY),1
        ret

; Papi ne traverse pas les murs : on essaie x ancien / y ancien
papi_collide:
        ld a,(px)
        ld hl,(py)
        call blocked
        ret nc
        ld a,(opx)
        ld hl,(py)
        call blocked
        jr c,.t2
        ld a,(opx)
        ld (px),a
        ret
.t2     ld a,(px)
        ld hl,(opy)
        call blocked
        jr c,.t3
        ld hl,(opy)
        ld (py),hl
        ret
.t3     ld a,(opx)
        ld (px),a
        ld hl,(opy)
        ld (py),hl
        ret

; tir, delais, invulnerabilite (chaque image)
papi_actions:
        ld a,(invuln)
        or a
        jr z,.i
        dec a
        ld (invuln),a
.i      ld a,(pcool)
        or a
        jr z,.f
        dec a
        ld (pcool),a
        ret
.f      ld a,(inp)
        bit 4,a
        ret z
        ld a,9
        call get_spr
        ld b,4
.s      ld a,(ix+S_ACT)
        or a
        jr z,.free
        ld de,SPSZ
        add ix,de
        djnz .s
        ret
.free   ld a,(px)
        add a,2
        ld (ix+S_X),a
        ld hl,(py)
        ld de,3
        add hl,de
        ld (ix+S_YL),l
        ld (ix+S_YH),h
        ld a,(dir)
        ld (ix+S_DIR),a
        ld (ix+S_TMR),16
        ld (ix+S_ACT),1
        ld (ix+S_DIRTY),1
        ld a,8
        ld (pcool),a
        ret

papi_hurt:
        ld hl,(hits)
        inc hl
        ld (hits),hl
        ld a,60
        ld (invuln),a
        ret

;------------------------------------------------------------------------------
; le jeu : ennemis, balles (25 Hz)
kill_spr:
        ld (ix+S_ACT),0
        ld (ix+S_DIRTY),1
        ret

; ennemi IX : apparition a une distance de Papi (sp_dmin .. sp_dmin+63 lignes), sur une case libre
spawn_enemy:
        ld c,4
.try    push bc
        call rand
        ld a,l
        and 127
        cp 73
        jr c,.xo
        sub 73
.xo     ld b,a                  ; x
        ld a,h
        and 63
        ld e,a
        ld a,(sp_dmin)
        add a,e
        ld e,a
        ld d,0                  ; DE = distance
        call rand
        ld a,l
        and 1
        ld hl,(py)
        jr z,.dn
        or a
        sbc hl,de
        jr .ck
.dn     add hl,de
.ck     push hl
        push bc
        ld a,b
        call blocked
        pop bc
        pop hl
        jr c,.fail
        ld (ix+S_X),b
        ld (ix+S_YL),l
        ld (ix+S_YH),h
        ld (ix+S_ACT),1
        ld (ix+S_DIRTY),1
        ld (ix+S_ANIM),0
        ld (ix+S_TMR),0
        call rand
        ld a,l
        and 3
        ld (ix+S_DIR),a
        ld a,h
        and 31
        add a,16
        ld (ix+S_COOL),a
        pop bc
        ret
.fail   pop bc
        dec c
        jr nz,.try
        ld (ix+S_TMR),3
        ret

enemies_tick:
        ld a,1
        call get_spr
        ld b,NENM
.e      push bc
        ld a,(tickf)
        xor (ix+S_IDX)
        and 1
        jr nz,.nx
        ld a,(ix+S_ACT)
        or a
        jr nz,.al
        ld a,(ix+S_TMR)
        or a
        jr z,.sp
        dec (ix+S_TMR)
        jr nz,.nx
.sp     call spawn_enemy
        jr .nx
.al     call enemy_think
        call enemy_contact
.nx     pop bc
        ld de,SPSZ
        add ix,de
        djnz .e
        ret

enemy_contact:
        ld a,(invuln)
        or a
        ret nz
        ld a,(px)
        sub (ix+S_X)
        jr nc,.p
        neg
.p      cp 5
        ret nc
        ld hl,(py)
        ld e,(ix+S_YL)
        ld d,(ix+S_YH)
        or a
        sbc hl,de
        bit 7,h
        jr z,.q
        ld a,l
        cpl
        ld l,a
        ld a,h
        cpl
        ld h,a
        inc hl
.q      ld a,h
        or a
        ret nz
        ld a,l
        cp 9
        ret nc
        jp papi_hurt

enemy_think:
        ld a,(ix+S_COOL)
        or a
        jr z,.tf
        dec (ix+S_COOL)
        jr .dr
.tf     call align_dir
        cp #FF
        jr z,.dr
        call enemy_fire
        call rand
        ld a,l
        and 31
        add a,28
        ld (ix+S_COOL),a
.dr     ld a,(ix+S_TMR)
        or a
        jr z,.pick
        dec (ix+S_TMR)
        jr .move
.pick   call choose_dir
.move   ld a,(ix+S_X)
        ld b,a
        ld l,(ix+S_YL)
        ld h,(ix+S_YH)
        ld a,(ix+S_DIR)
        or a
        jr nz,.d1
        dec hl
        dec hl
        jr .try
.d1     cp 1
        jr nz,.d2
        inc hl
        inc hl
        jr .try
.d2     cp 2
        jr nz,.d3
        dec b
        jr .try
.d3     inc b
.try    ld a,b
        push hl
        push bc
        call blocked
        pop bc
        pop hl
        jr c,.stuck
        ld a,b
        ld (ix+S_X),a
        ld (ix+S_YL),l
        ld (ix+S_YH),h
        inc (ix+S_ANIM)
        ld (ix+S_DIRTY),1
        jr .img
.stuck  ld (ix+S_TMR),0
.img    ld a,(ix+S_DIR)
        add a,a
        add a,a
        ld b,a
        ld a,(ix+S_ANIM)
        rrca
        and 3
        add a,b
        add a,a
        ld l,a
        ld h,0
        ld de,sold_tab
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld a,e
        cp (ix+S_IMGL)
        jr nz,.si
        ld a,d
        cp (ix+S_IMGH)
        ret z
.si     ld (ix+S_IMGL),e
        ld (ix+S_IMGH),d
        ld (ix+S_DIRTY),1
        ret

choose_dir:
        call rand
        ld a,l
        and 3
        jr z,.rnd
        ld hl,(py)
        ld e,(ix+S_YL)
        ld d,(ix+S_YH)
        or a
        sbc hl,de               ; dy
        ld c,0
        bit 7,h
        jr z,.dp
        ld c,1
        ld a,l
        cpl
        ld l,a
        ld a,h
        cpl
        ld h,a
        inc hl
.dp     ld a,(px)
        sub (ix+S_X)
        ld b,0
        jr nc,.xp
        ld b,1
        neg
.xp     add a,a
        ld e,a                  ; |dx| en pixels
        ld a,h
        or a
        jr nz,.rnd
        ld a,l
        cp 140
        jr nc,.rnd
        ld a,e
        cp l
        jr c,.vert
        ld a,2
        bit 0,b
        jr nz,.set
        ld a,3
        jr .set
.vert   ld a,1
        bit 0,c
        jr z,.set
        xor a
        jr .set
.rnd    call rand
        ld a,h
        and 3
.set    ld (ix+S_DIR),a
        call rand
        ld a,l
        and 7
        add a,6
        ld (ix+S_TMR),a
        ret

; direction de tir si Papi est aligne et a portee, sinon #FF
align_dir:
        ld hl,(py)
        ld e,(ix+S_YL)
        ld d,(ix+S_YH)
        or a
        sbc hl,de
        ld c,0
        bit 7,h
        jr z,.p1
        ld c,1
        ld a,l
        cpl
        ld l,a
        ld a,h
        cpl
        ld h,a
        inc hl
.p1     ld a,h
        or a
        jr nz,.no
        ld a,l
        cp 120
        jr nc,.no
        ld b,l
        ld a,(px)
        sub (ix+S_X)
        ld d,0
        jr nc,.p2
        ld d,1
        neg
.p2     cp 3
        jr nc,.hz
        ld a,1
        bit 0,c
        ret z
        xor a
        ret
.hz     ld a,b
        cp 8
        jr nc,.no
        ld a,3
        bit 0,d
        ret z
        ld a,2
        ret
.no     ld a,#FF
        ret

; A = direction : l'ennemi IX tire
enemy_fire:
        ld c,a
        push ix
        ld a,13
        call get_spr
        ld b,3
.f      ld a,(ix+S_ACT)
        or a
        jr z,.free
        ld de,SPSZ
        add ix,de
        djnz .f
        pop ix
        ret
.free   pop iy
        ld a,(iy+S_X)
        add a,2
        ld (ix+S_X),a
        ld l,(iy+S_YL)
        ld h,(iy+S_YH)
        ld de,3
        add hl,de
        ld (ix+S_YL),l
        ld (ix+S_YH),h
        ld (ix+S_DIR),c
        ld (ix+S_TMR),20
        ld (ix+S_ACT),1
        ld (ix+S_DIRTY),1
        push iy
        pop ix
        ret

; HL = difference de lignes (balle - cible) : A = 1 si la balle (6 lignes) touche une cible de 12 lignes
dy_hit: bit 7,h
        jr z,.p
        ld a,h
        inc a
        jr nz,.n
        ld a,l
        cp #FB
        jr c,.n
        ld a,1
        ret
.p      ld a,h
        or a
        jr nz,.n
        ld a,l
        cp 12
        jr nc,.n
        ld a,1
        ret
.n      xor a
        ret

bullets_tick:
        ld a,9
        call get_spr
        ld b,7
.b      push bc
        ld a,(tickf)
        xor (ix+S_IDX)
        and 1
        jr nz,.bn
        ld a,(ix+S_ACT)
        or a
        call nz,bullet_step
.bn     pop bc
        ld de,SPSZ
        add ix,de
        djnz .b
        ret

bullet_step:
        ld a,(ix+S_TMR)
        dec a
        jp z,kill_spr
        ld (ix+S_TMR),a
        ld b,(ix+S_X)
        ld l,(ix+S_YL)
        ld h,(ix+S_YH)
        ld a,(ix+S_DIR)
        or a
        jr nz,.u1
        ld de,6
        or a
        sbc hl,de
        jr .m
.u1     cp 1
        jr nz,.u2
        ld de,6
        add hl,de
        jr .m
.u2     cp 2
        jr nz,.u3
        ld a,b
        sub 3
        jp c,kill_spr
        ld b,a
        jr .m
.u3     ld a,b
        add a,3
        ld b,a
        cp 77
        jp nc,kill_spr
.m      bit 7,h
        jp nz,kill_spr
        push hl
        ld de,MAPH*8-6
        or a
        sbc hl,de
        pop hl
        jp nc,kill_spr
        ld (ix+S_X),b
        ld (ix+S_YL),l
        ld (ix+S_YH),h
        ld (ix+S_DIRTY),1
        push hl                 ; tuile pleine au point (x, y+3) ?
        ld de,3
        add hl,de
        call shr3
        pop hl
        ld d,a                  ; rangee
        ld a,b
        call div6
        ld c,a
        ld a,d
        call solid_at
        or a
        jp nz,kill_spr
        ld a,(ix+S_KIND)
        cp 2
        jr nz,.eb
        ; balle de Papi : touche-t-elle un ennemi ?
        push ix
        ld iy,SPR_TAB+SPSZ
        ld b,NENM
.he     ld a,(iy+S_ACT)
        or a
        jr z,.hn
        ld a,(ix+S_X)
        sub (iy+S_X)
        jr c,.hn
        cp 6
        jr nc,.hn
        ld l,(ix+S_YL)
        ld h,(ix+S_YH)
        ld e,(iy+S_YL)
        ld d,(iy+S_YH)
        or a
        sbc hl,de
        call dy_hit
        or a
        jr z,.hn
        ld (iy+S_ACT),0
        ld (iy+S_DIRTY),1
        call rand
        ld a,l
        and 15
        add a,20
        ld (iy+S_TMR),a
        ld hl,(kills)
        inc hl
        ld (kills),hl
        pop ix
        jp kill_spr
.hn     ld de,SPSZ
        add iy,de
        djnz .he
        pop ix
        ret
.eb     ; balle ennemie : touche-t-elle Papi ?
        ld a,(invuln)
        or a
        ret nz
        ld a,(ix+S_X)
        ld hl,px
        sub (hl)
        ret c
        cp 6
        ret nc
        ld l,(ix+S_YL)
        ld h,(ix+S_YH)
        ld de,(py)
        or a
        sbc hl,de
        call dy_hit
        or a
        ret z
        call papi_hurt
        jp kill_spr

game_tick:
        call enemies_tick
        jp bullets_tick
