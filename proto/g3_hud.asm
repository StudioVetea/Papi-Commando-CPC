;==============================================================================
;  PROTOTYPE 3 : bandeau HUD (score, vies, ennemis restants) sans rupture d'ecran
;  Le bandeau (8 lignes x 78 octets) est recopie CHAQUE image dans les 8 premieres lignes de l'ecran :
;  rangee du haut (plans 0..h-1) + debut de la rangee suivante (plans 0..s-1).
;  Quand la fenetre remonte, les 2 lignes qu'elle libere sont redessinees depuis les tuiles.
;==============================================================================
hudbuf      equ #4C00           ; 8 lignes de 78 octets
hud_dirty   equ VARS+140        ; bit0 score, bit1 vies, bit2 ennemis restants
hud_force   equ VARS+141
hud_r       equ VARS+142        ; #FF = rien de dessine
hudc        equ VARS+144        ; (16 bits) ligne de carte du haut de la fenetre dessinee en dernier
score       equ VARS+146        ; 3 chiffres (centaines, dizaines, unites) : x10 points
lives       equ VARS+149
kleft       equ VARS+150
p_state     equ VARS+151        ; 0 = jeu, 1 = fin de partie
p_timer     equ VARS+152
dr_pl       equ VARS+153        ; decalage de plan pour draw_row (0 en general)
hl_l        equ VARS+154        ; (16 bits)
hl_nc       equ VARS+156        ; (16 bits)
hl_n        equ VARS+158
hb_j        equ VARS+159
hb_h        equ VARS+160
hb_src      equ VARS+161        ; (16 bits)

hud_init:
        ld hl,hud_tpl
        ld de,hudbuf
        ld bc,624
        ldir
        xor a
        ld (score),a
        ld (score+1),a
        ld (score+2),a
        ld (p_state),a
        ld (p_timer),a
        ld (dr_pl),a
        ld (hud_force),a
        ld (hudc),a
        ld (hudc+1),a
        ld a,3
        ld (lives),a
        ld a,25
        ld (kleft),a
        ld a,#FF
        ld (hud_r),a
        ld a,7
        ld (hud_dirty),a
        jp hud_do

; A = chiffre (0..10), DE = destination (octet de gauche, ligne 1 de la cellule 2 x 5) ; conserve BC, DE, HL
hud_glyph:
        push bc
        push de
        push hl
        ld l,a
        ld h,0
        ld c,l
        ld b,h
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,bc
        add hl,bc               ; 10 x A
        ld bc,hud_font
        add hl,bc
        repeat 5
          ld a,(hl)
          ld (de),a
          inc hl
          inc de
          ld a,(hl)
          ld (de),a
          inc hl
          ld a,e
          add a,77
          ld e,a
          jr nc,$+3
          inc d
        rend
        pop hl
        pop de
        pop bc
        ret

; redessine dans hudbuf les champs modifies
hud_render:
        ld a,(hud_dirty)
        or a
        ret z
        ld c,a
        xor a
        ld (hud_dirty),a
        inc a
        ld (hud_force),a
        bit 0,c
        jr z,.n1
        ld hl,score
        ld de,hudbuf+78+12
        ld b,3
.sd     ld a,(hl)
        call hud_glyph
        inc hl
        inc de
        inc de
        djnz .sd
        xor a
        call hud_glyph          ; zero fixe (les points vont de 10 en 10)
.n1     bit 1,c
        jr z,.n2
        ld a,(lives)
        ld de,hudbuf+78+48
        call hud_glyph
.n2     bit 2,c
        ret z
        ld a,(kleft)
        ld b,0
.t      cp 10
        jr c,.u
        sub 10
        inc b
        jr .t
.u      push af
        ld a,b
        ld de,hudbuf+78+69
        call hud_glyph
        pop af
        ld de,hudbuf+78+71
        jp hud_glyph

; copie 78 octets HL -> DE (ligne d'un plan de l'anneau de 2 Ko : la fin de l'anneau reboucle)
copy78:
        ld a,d
        and 7
        cp 7
        jr nz,.fast
        ld a,e
        cp #B3
        jp nc,.slow
.fast   ld bc,#7FFF
        repeat 78
          ldi
        rend
        ret
.slow   ld a,d
        and #F8
        ld c,a
        ld b,78
.sl     ld a,(hl)
        ld (de),a
        inc hl
        inc de
        ld a,d
        and 7
        or c
        ld d,a
        djnz .sl
        ret

; recopie le bandeau dans la fenetre de l'image suivante (r_nxt, s_nxt)
hud_blit:
        ld a,(s_nxt)
        ld b,a
        ld a,8
        sub b
        ld (hb_h),a
        xor a
        ld (hb_j),a
        ld hl,hudbuf
        ld (hb_src),hl
.bl     ld a,(hb_j)
        ld c,a
        ld a,(hb_h)
        ld b,a
        ld a,c
        cp b
        jr c,.top
        sub b
        ld e,a                  ; plan
        ld a,(r_nxt)
        inc a                   ; rangee r+1
        jr .addr
.top    ld e,a
        ld a,(r_nxt)
.addr   add a,a
        ld l,a
        ld h,0
        ld bc,rowoff
        add hl,bc
        ld c,(hl)
        inc hl
        ld b,(hl)               ; BC = decalage de la rangee
        ld a,e
        add a,a
        add a,a
        add a,a                 ; 8 x plan
        add a,b
        or #C0
        ld d,a
        ld e,c
        ld hl,(hb_src)
        call copy78
        ld hl,(hb_src)
        ld bc,78
        add hl,bc
        ld (hb_src),hl
        ld hl,hb_j
        inc (hl)
        ld a,(hl)
        cp 8
        jr nz,.bl
        ret

; appelee apres le calcul des rangees de l'image suivante, avant la publication
hud_overlay:
        ld a,(icnt)
        or a
        jr nz,hud_do
.w      halt                    ; le faisceau doit avoir depasse le bandeau de l'image affichee (ligne 26)
        ld a,(icnt)
        or a
        jr z,.w
hud_do:
        call hud_render
        ld a,(r_nxt)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,(s_nxt)
        ld e,a
        ld d,0
        add hl,de               ; HL = ligne de carte du haut de la fenetre suivante
        ld (hl_nc),hl
        ld a,(hud_r)
        inc a
        jp z,.blit              ; rien de dessine : pas de restauration
        ld de,(hudc)
        or a
        sbc hl,de
        jr nz,.moved
        ld a,(hud_force)
        or a
        ret z                   ; meme fenetre, bandeau inchange
        jp .blit
.moved  jp nc,.blit             ; la fenetre descend : les lignes quittent l'ecran par le haut
        ; la fenetre monte : les lignes max(oc, nc+8) .. oc+7 redeviennent de la carte
        ld hl,(hl_nc)
        ld de,8
        add hl,de
        ld de,(hudc)
        or a
        sbc hl,de
        jr c,.useoc
        add hl,de
        jr .go
.useoc  ex de,hl
.go     ld (hl_l),hl
        ld hl,(hudc)
        ld de,8
        add hl,de
        ld de,(hl_l)
        or a
        sbc hl,de
        ld a,l
        ld (hl_n),a
.rl     ld hl,(hl_l)
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        ld a,l
        push af                 ; rangee de carte
        ld a,(hl_l)
        and 7
        ld (dr_pl),a
        ld c,a
        add a,a
        add a,c
        add a,a
        ld l,a
        ld h,0
        ld (row_ys6),hl
        ld a,1
        ld (row_n),a
        xor a
        ld (dr_c0),a
        ld a,13
        ld (dr_n),a
        pop af
        call draw_row
        xor a
        ld (dr_pl),a
        ld hl,(hl_l)
        inc hl
        ld (hl_l),hl
        ld hl,hl_n
        dec (hl)
        jr nz,.rl
.blit   call hud_blit
        ld hl,(hl_nc)
        ld (hudc),hl
        ld a,(r_nxt)
        ld (hud_r),a
        xor a
        ld (hud_force),a
        ret

; nombre de lignes (0..12) du haut du sprite IX (position dessinee) qui tombent dans la fenetre du bandeau
hud_skip:
        xor a
        ld (esk),a
        ld hl,(hudc)
        ld de,8
        add hl,de
        ld e,(ix+S_OYL)
        ld d,(ix+S_OYH)
        or a
        sbc hl,de
        ret c
        ret z
        ld a,h
        or a
        jr nz,.all
        ld a,l
        cp 12
        jr c,.s
.all    ld a,12
.s      ld (esk),a
        ret
esk     db 0

; ennemi abattu : score +1 (x10 points), un ennemi de moins a abattre
hud_kill:
        ld hl,score+2
        inc (hl)
        ld a,(hl)
        cp 10
        jr c,.ok
        ld (hl),0
        dec hl
        inc (hl)
        ld a,(hl)
        cp 10
        jr c,.ok
        ld (hl),0
        dec hl
        inc (hl)
        ld a,(hl)
        cp 10
        jr c,.ok
        ld a,9
        ld (score),a
        ld (score+1),a
        ld (score+2),a
.ok     ld a,(kleft)
        or a
        jr z,.nk
        dec a
        ld (kleft),a
.nk     ld hl,hud_dirty
        ld a,(hl)
        or 5
        ld (hl),a
        ret

; Papi touche : une vie de moins ; plus de vie = fin de partie
hud_life:
        ld a,(lives)
        or a
        ret z
        dec a
        ld (lives),a
        ld hl,hud_dirty
        set 1,(hl)
        ret nz
        ld a,1
        ld (p_state),a
        xor a
        ld (p_timer),a
        ret

; fin de partie : la scene est figee ; tir (apres 2 s) = nouvelle partie
game_over_tick:
        call readkeys
        ld a,(p_timer)
        cp 255
        jr z,.w
        inc a
        ld (p_timer),a
.w      cp 100
        ret c
        ld a,(inp)
        bit 4,a
        ret z
        di
        jp boot

; rangee A (r+1, l'ancienne rangee du haut) : seules les lignes s_nxt .. 7 sont a redessiner (les autres sont couvertes par le bandeau)
part_row:
        push af
        ld a,(s_nxt)
        ld (dr_pl),a
        ld e,a
        add a,a
        add a,e
        add a,a
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
        pop af
        call draw_row
        xor a
        ld (dr_pl),a
        ret
