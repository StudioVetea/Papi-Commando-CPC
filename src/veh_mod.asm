;==============================================================================
;  VEHICULES DE LA ZONE 4 "TWIN ROADS" (banque 7, assemble pour #4000 avec le code du boss)
;
;   Camion de troupes (ArmyTruck) et WarTruck : sprite 24 x 24 (12 octets x 24 lignes), un seul vehicule a la fois, qui roule sur l'une des deux
;   routes (rangees 6 et 18 de la carte), dans un sens ou dans l'autre tires au hasard, a 2 x la vitesse de Papi, puis ressort et revient
;   apres une pause. Il largue un ennemi toutes les 2 s (sur une place libre), les ennemis de la mission ne viennent que de lui.
;   Le WarTruck tire des rafales de 3 balles (classe de portee 5) dans les 4 directions, tour a tour (la tourelle tourne).
;   Les bidons explosifs (case de la grille = 7 : obstacle comme une caserne) explosent au bout de 3 balles ou sous une grenade : 3 degats autour,
;   puis deux flammes animees (case = 4) qui brulent quiconque les touche.
;
;   Mode 4 (zone 5) : bidons explosifs seulement, sans camion (ni contact, ni larguage d'ennemis).
;   Mode (veh_on) : 1 camion de troupes, points de vie propres (V_HP), +500 points, un autre revient (missions Z80 et chrono) ;
;                   2 camion, points de vie = kills_left (HUD en couleur), victoire normale ; 3 WarTruck, idem, fin de zone.
;   Le module ne voit pas le miroir (banque 1) : il efface par la rampe b1_restore et dessine par-dessus (ecran) ; b1_wtr dessine une tuile (ecran ET miroir).
;   Appele par veh_call (boss.asm) : A = 1 image, 2 balle de Papi (IX), 3 explosion de grenade, 4 case de bidon touchee (HL).  IX et IY conserves.
;==============================================================================
TW          equ 11              ; largeur du sprite en octets (22 pixels)
TH          equ 18              ; hauteur en lignes
TIMG        equ 2*TW*TH         ; taille d'une image (masque + donnee)
V_Y0        equ 112-TH              ; y du haut du camion sur la route (rangee 13 ; le bas du camion = le bas de la route : 8 x 14 - 24)
V_Y1        equ V_Y0              ; (une seule route : rangee 13)
V_SPEED     equ 128             ; 1 octet toutes les 2 images exactement (25 pas/s, regulier) : 0,5 octet par image (1,4 x Papi)
V_HP        equ 50              ; points de vie du camion de troupes quand ce n'est pas la mission du camion
V_DROP      equ 100             ; images entre deux unites larguees (2 s)
V_XMAX      equ 90              ; x + 12 : la valeur 90 = tout juste sorti par la droite ; 0 = tout juste sorti par la gauche
V_FLASH     equ 6               ; images de flash blanc quand le vehicule est touche
V_BURST     equ 1
V_BSPACE    equ 6
V_BDELAY    equ 23
NBAR        equ 8
BARSZ       equ 6               ; case du haut (2), coups, etat (1 bidon, 2 en flammes), phase de la flamme affichee
EXPL_DATA   equ TRUCK_DATA+10*TIMG

m_veh:      push ix
            push iy
            call mv_disp
            pop iy
            pop ix
            ret
mv_disp:    dec a
            jp z,mv_tick
            dec a
            jp z,mv_bullet
            dec a
            jp z,mv_gren
            dec a
            jp z,mv_barrel
            jp mv_late

mv_tick:    ld a,(p_state)
            cp 3
            ret z                       ; Papi entre : tout attend
            cp 2
            ret z                       ; scene figee
            ld a,(v_init)
            or a
            call z,mv_init
            call mv_flash
            ld a,(veh_on)               ; mode 4 : bidons explosifs seulement (zone 5), pas de camion
            cp 4
            call nz,mv_truck
            call mv_contact
            call mv_fx
            call mv_flames
            ld a,(frame)
            and 3
            ret nz
            jp mv_hazard

; le contact du camion est mortel : Papi (6 octets x 12 lignes) touche le rectangle du camion (12 x 24)
mv_contact: ld a,(v_act)
            or a
            ret z
            ld a,(p_state)
            or a
            ret nz
            ld a,(p_x)
            ld hl,v_xo
            sub (hl)
            add a,TW+5
            cp TW+5
            ret nc
            ld a,(p_y)
            ld hl,v_y
            sub (hl)
            add a,11
            cp TH+11
            ret nc
            jp player_hit

; (IX+1, IX+2) = (x, y) dans le rectangle du camion (C = xo, B = y) ? carry si oui
mv_ovl:     ld a,(ix+1)
            sub c
            add a,TW+5
            cp TW+5
            ret nc
            ld a,(ix+2)
            sub b
            add a,11
            cp TH+11
            ret

; fin d'image : si quelque chose a ete dessine sur le camion (ennemi, balle, explosion), on repeint le camion par-dessus
mv_late:    ld a,(v_ox)
            cp #FF
            ret z
            ld a,(v_xo)
            ld c,a
            ld a,(v_y)
            ld b,a
            ld ix,enemies
            ld de,ESIZE
            ld h,MAXENEMY
.e          ld a,(ix+E_STATE)
            or a
            jr z,.en
            call mv_ovl
            call c,mv_sub
.en         add ix,de
            dec h
            jr nz,.e
            ld ix,bullets
            ld de,BSIZE
            ld h,NBUL
.b          ld a,(ix+B_ON)
            or a
            jr z,.bn
            call mv_ovl
            call c,mv_sub
.bn         add ix,de
            dec h
            jr nz,.b
            ret

; repeint la partie du camion recouverte par l'element IX (ennemi ou balle : 6 octets x 12 lignes en (IX+1, IX+2)) ; conserve BC, DE, HL, IX
mv_sub:     push bc
            push de
            push hl
            call mv_sub1
            pop hl
            pop de
            pop bc
            ret
mv_sub1:    ld a,(v_of)
            inc a
            ret z
            ld a,(nw_lo)
            ld b,a
            ld a,(ix+1)
            cp b
            jr nc,.a
            ld a,b
.a          ld (sb_x),a                 ; x0 = max(x, bord gauche visible)
            ld d,a
            ld a,(ix+1)
            add a,6
            ld e,a
            ld a,(nw_hi)
            cp e
            jr nc,.b
            ld e,a                      ; x1 = min(x + 6, bord droit visible)
.b          ld a,e
            sub d
            ret z
            ret c
            ld (bl_n),a
            ld a,(v_y)
            ld b,a
            ld a,(ix+2)
            cp b
            jr nc,.c
            ld a,b
.c          ld (sb_y),a                 ; y0
            ld c,a
            ld a,(ix+2)
            add a,12
            ld e,a
            ld a,b
            add a,TH
            cp e
            jr nc,.d
            ld e,a                      ; y1
.d          ld a,e
            sub c
            ret z
            ret c
            ld (bl_h),a
            ld a,c
            sub b                       ; lignes sautees en haut de l'image
            ld hl,0
            jr z,.l0
            ld b,a
            ld de,2*TW
.l          add hl,de
            djnz .l
.l0         ld a,(v_xo)
            ld c,a
            ld a,(sb_x)
            add a,TW
            sub c
            add a,a                     ; 2 x (x0 + TW - xo) octets
            ld e,a
            ld d,0
            add hl,de
            ld a,(v_of)
            add a,a
            ld e,a
            push hl
            ld hl,mv_sprtab
            add hl,de
            ld e,(hl)
            inc hl
            ld d,(hl)
            pop hl
            add hl,de
            ex de,hl                    ; DE = source
            ld a,2*TW
            ld (bl_s),a
            ld a,(sb_x)
            ld b,a
            ld a,(sb_y)
            ld c,a
            ld a,(v_fl)
            or a
            jp z,mv_blit
            jp mv_blitw

; flash blanc du vehicule touche : v_fl images ; l'image est redessinee au debut et a la fin
mv_flash:   ld a,(v_fl)
            or a
            ret z
            dec a
            ld (v_fl),a
            ret nz
            ld a,#FF                    ; fin du flash : redessin normal
            ld (v_of),a
            ret

; preparation de la mission : variables, liste des bidons
mv_init:    ld a,1
            ld (v_init),a
            ld hl,mv_vars
            ld de,mv_vars+1
            ld bc,mv_vars_end-mv_vars-1
            ld (hl),0
            ldir
            ld a,#FF
            ld (v_ox),a
            ld a,V_HP
            ld (v_hpt),a
            ld a,120
            ld (v_wait),a
            ld a,60
            ld (v_bcd),a
            ld hl,GRID+16
            ld de,v_bar
            ld bc,384
.sc         ld a,(hl)
            and #1F                     ; bidon : bits 0-2 et 4 (les casernes n'ont pas le bit 4)
            cp #17
            jr nz,.nx
            push bc
            push hl
            ld bc,-16
            add hl,bc
            ld a,(hl)
            pop hl
            pop bc
            and #1F                     ; bidon : bits 0-2 et 4 (les casernes n'ont pas le bit 4)
            cp #17
            jr z,.nx                    ; la case du haut est aussi un bidon : celle-ci est le bas
            ld a,(v_nb)
            cp NBAR
            jr nc,.nx
            ld a,l                      ; entree : case du haut, coups = 0, etat 1, phase #FF
            ld (de),a
            inc de
            ld a,h
            ld (de),a
            inc de
            xor a
            ld (de),a
            inc de
            inc a
            ld (de),a
            inc de
            ld a,#FF
            ld (de),a
            inc de
            inc de
            ld a,(v_nb)
            inc a
            ld (v_nb),a
.nx         inc hl
            dec bc
            ld a,b
            or c
            jr nz,.sc
            ret


;------------------------------------------------------------------------------
; le vehicule
;------------------------------------------------------------------------------
mv_truck:   ld a,(v_act)
            or a
            jr nz,.run
            ld hl,v_wait                ; hors de l'ecran : attente avant le prochain passage
            ld a,(hl)
            or a
            jr z,.enter
            dec (hl)
            ret
.enter      call rand                   ; sens au hasard (une seule route)
            ld b,a
            ld a,V_Y0
            ld (v_y),a
            ld a,0                      ; du bord gauche vers la droite...
            ld c,0
            bit 1,b
            jr z,.d
            ld a,V_XMAX                 ; ... ou du bord droit vers la gauche
            ld c,1
.d          ld (v_xo),a
            ld a,c
            ld (v_dir),a
            ld a,1
            ld (v_act),a
            ld a,#FF
            ld (v_ox),a
            ld a,40
            ld (v_dtim),a
            xor a
            ld (v_acc),a
            ret
.run        ld a,(v_acc)
            add a,V_SPEED
            ld (v_acc),a
            jr nc,.mv                   ; (pas de pas cette image)
            ld a,(v_dir)
            or a
            ld a,(v_xo)
            jr nz,.left
            inc a
            ld (v_xo),a
            cp V_XMAX
            jr z,.leave
            jr .mv
.left       dec a
            ld (v_xo),a
            jr z,.leave
.mv         call mv_drawcheck
            ld a,(veh_on)
            and 7
            cp 3
            call z,mv_war
            ld a,(v_xo)                 ; largage : toutes les 2 s, quand le camion est entierement a l'ecran, Papi en vie
            cp TW
            ret c
            cp 79
            ret nc
            ld a,(p_state)
            or a
            ret nz
            ld hl,v_dtim
            ld a,(hl)
            or a
            jr z,.try
            dec (hl)
            ret
.try        xor a
            ld (v_got),a
            ld a,2
            ld (v_k),a
.dk         ld a,(v_k)                  ; 2 unites a la suite, derriere le camion (x : 0 a 72)
            dec a
            ld c,a
            add a,a
            add a,a
            add a,a
            sub c                       ; 7 x k
            ld c,a
            ld a,(v_dir)
            or a
            ld a,(v_xo)
            jr nz,.rl
            sub TW+6                    ; vers la droite : l'arriere est a gauche
            sub c
            jr c,.nk
            jr .xk
.rl         inc a                       ; vers la gauche : l'arriere est a droite
            add a,c
            cp 73
            jr nc,.nk
.xk         ld (v_dxx),a
            call mv_drop
            jr nc,.nk
            ld a,1
            ld (v_got),a
.nk         ld hl,v_k
            dec (hl)
            jr nz,.dk
            ld a,(v_got)
            or a
            ret z
            ld a,V_DROP
            ld (v_dtim),a
            ret
.leave      call mv_erase               ; sorti : il revient apres une pause
            xor a
            ld (v_act),a
            call rand
            and 63
            add a,40
            ld (v_wait),a
            ret

; numero d'image du camion : camion de troupes 0 (cap a gauche) ou 1 (cap a droite) ; WarTruck : 2 + cap x 4 + direction du canon
mv_image:   ld a,(v_dir)                ; 0 : roule vers la droite -> cap a droite
            xor 1
            ld c,a
            ld a,(veh_on)
            and 7
            cp 3
            ld a,c
            ret nz
            add a,a
            add a,a
            ld c,a
            ld a,(v_aim)
            add a,c
            add a,2
            ret

; octets visibles du camion dont x + 12 = A : B = bord gauche, C = bord droit (exclu), dans [0, 78]
mv_range:   ld c,a
            cp 79
            jr c,.h
            ld c,78
.h          sub TW
            jr nc,.l
            xor a
.l          ld b,a
            ret

; redessine le camion s'il a bouge ou si la tourelle a tourne
mv_drawcheck:
            call mv_image
            ld hl,v_of
            cp (hl)
            jr nz,mv_draw
            ld a,(v_ox)
            ld hl,v_xo
            cp (hl)
            ret z
; dessin : on efface l'union de l'ancien et du nouveau rectangle (visibles), puis on dessine par-dessus (b1_restore : decor du miroir)
mv_draw:    call mv_image
            ld (v_of),a
            ld a,(v_xo)
            call mv_range
            ld a,b
            ld (nw_lo),a
            ld a,c
            ld (nw_hi),a
            ld a,(v_ox)
            cp #FF
            jr z,.rest
            call mv_range               ; ancien rectangle ; union : plus petit bord gauche, plus grand bord droit
            ld a,(nw_lo)
            cp b
            jr nc,.a
            ld b,a
.a          ld a,(nw_hi)
            cp c
            jr c,.rest
            ld c,a
.rest       ld a,c
            sub b
            jr z,.nodraw
            jr c,.nodraw
            ld d,a
            ld a,(nw_hi)                ; camion encore visible : effacement et dessin ligne par ligne (peu de flicker)
            ld hl,nw_lo
            cp (hl)
            jr z,.full
            jr c,.full
            ld a,b
            ld (ud_x),a
            ld a,d
            ld (ud_w),a
            ld a,1
            ld (il_on),a
            jr .nodraw
.full       ld a,(v_y)
            ld c,a
            ld e,TH
            call b1_restore
.nodraw     ld a,(v_xo)
            ld (v_ox),a
            ld a,(v_y)
            ld (v_oy),a
mv_paint:   ld a,(nw_hi)                ; le sprite : colonnes visibles [nw_lo, nw_hi)
            ld hl,nw_lo
            sub (hl)
            ret z
            ret c
            ld (bl_n),a
            ld a,(v_xo)                 ; decalage dans l'image : 2 x (bord gauche visible + 12 - x0) octets
            ld c,a
            ld a,(nw_lo)
            add a,TW
            sub c
            add a,a
            ld c,a
            ld b,0
            ld a,(v_of)
            add a,a
            ld e,a
            ld d,0
            ld hl,mv_sprtab
            add hl,de
            ld e,(hl)
            inc hl
            ld d,(hl)
            ex de,hl
            add hl,bc
            ex de,hl                    ; DE = source
            ld a,2*TW
            ld (bl_s),a
            ld a,TH
            ld (bl_h),a
            ld a,(nw_lo)
            ld b,a
            ld a,(v_y)
            ld c,a
            ld hl,mv_blit
            ld a,(v_fl)
            or a
            jr z,.q
            ld hl,mv_blitw              ; flash : tous les pixels opaques en blanc
.q          ld a,(il_on)
            or a
            jr nz,mv_il
            jp (hl)

; effacement (union des rectangles) et dessin, une ligne a la fois : le decor n'est visible qu'un instant par ligne
mv_il:      ld (il_fn),hl
            xor a
            ld (il_on),a
            ld a,TH
            ld (il_n),a
.l          push bc
            push de
            ld a,(ud_w)
            or a
            jr z,.nr
            ld d,a
            ld a,(ud_x)
            ld b,a
            ld e,1
            call b1_restore
.nr         pop de
            pop bc
            ld a,1
            ld (bl_h),a
            ld hl,(il_fn)
            call .j
            ld hl,il_n
            dec (hl)
            jr nz,.l
            ret
.j          jp (hl)
            ret                         ; le camion est prioritaire : rien ne le recouvre (mv_late)

; efface le camion (rectangle affiche) et reveille les ennemis dessous
mv_erase:   ld a,(v_ox)
            cp #FF
            ret z
            push af
            call mv_range
            ld a,c
            sub b
            jr z,.n
            jr c,.n
            ld d,a
            ld a,(v_oy)
            ld c,a
            ld e,TH
            call b1_restore
.n          ld a,#FF
            ld (v_ox),a
            pop af
; ennemis qui recouvrent le camion (x + 12 = A) : ils se redessinent
mv_wake:    ld c,a
            ld a,(v_y)
            ld b,a
            ld ix,enemies
            ld de,ESIZE
            ld h,MAXENEMY
.w          ld a,(ix+E_STATE)
            or a
            jr z,.n
            ld a,(ix+E_X)
            sub c
            add a,TW+5
            cp TW+5
            jr nc,.n
            ld a,(ix+E_Y)
            sub b
            add a,11
            cp TH+11
            jr nc,.n
            ld (ix+E_LAST),#FF
.n          add ix,de
            dec h
            jr nz,.w
            ret

; image masquee (paires masque / donnee, sans zigzag) : DE = source, B = x, C = y, bl_n octets par ligne, bl_h lignes, bl_s = pas de la source
mv_blit:    push bc
            push de
            call scr_addr
            ex de,hl                    ; HL = source (masque, donnee), DE = ecran
            ld a,(bl_n)
            ld b,a
.b          ld a,(de)
            and (hl)
            inc hl
            or (hl)
            inc hl
            ld (de),a
            inc de
            djnz .b
            pop de
            ld a,(bl_s)
            add a,e
            ld e,a
            jr nc,.n
            inc d
.n          pop bc
            inc c
            ld hl,bl_h
            dec (hl)
            jr nz,mv_blit
            ret

; comme mv_blit, mais tous les pixels opaques (masque a 0) sont blancs
mv_blitw:   push bc
            push de
            call scr_addr
            ld a,(bl_n)
            ld b,a
.b          ld a,(de)
            inc de
            inc de
            ld c,a                      ; masque
            ld a,(hl)
            xor WHITE
            and c
            xor WHITE
            ld (hl),a
            inc hl
            djnz .b
            pop de
            ld a,(bl_s)
            add a,e
            ld e,a
            jr nc,.n
            inc d
.n          pop bc
            inc c
            ld hl,bl_h
            dec (hl)
            jr nz,mv_blitw
            ret

; larguer une unite : une place libre (a partir de la 3e : les deux premieres sont factices), devant le camion. Sortie : C = largue
mv_drop:    ld a,(nb_wanted)
            ld ix,enemies
            ld hl,bk_on
            ld b,a
            ld a,(hl)
            or a
            jr z,.fs
            ld ix,enemies+2*ESIZE       ; (barre de vie : les 2 premieres places sont factices)
            dec b
            dec b
.fs            ld de,ESIZE
.f          ld a,(ix+E_STATE)
            or a
            jr z,.free
            add ix,de
            djnz .f
            or a
            ret
.free       ld a,(v_dxx)
            ld b,a
            ld a,(v_y)
            add a,TH-12
            ld c,a
            call can_stand_e
            jr z,.ok
            or a
            ret
.ok         call enemy_place
            scf
            ret

;------------------------------------------------------------------------------
; WarTruck : rafales de 3 balles, canon dans les 4 directions tour a tour (0 droite, 1 gauche, 2 bas, 3 haut)
;------------------------------------------------------------------------------
mv_war:     ld a,(p_state)
            or a
            ret nz
            ld a,(v_xo)
            cp TW
            ret c
            cp 79
            ret nc
            call mv_aim
            ld a,(v_bn)
            or a
            jr nz,.in
            ld a,(v_bcd)
            or a
            jr z,.start
            dec a
            ld (v_bcd),a
            ret
.start      ld a,V_BURST                ; une rafale de 3 balles, un seul son
            ld (v_bn),a
            xor a
            ld (v_bt),a
            ld a,11
            call sfx
.in         ld a,(v_bt)
            or a
            jr z,.shoot
            dec a
            ld (v_bt),a
            ret
.shoot      ld a,V_BSPACE
            ld (v_bt),a
            ld hl,v_bn
            dec (hl)
            jr nz,mv_shoot
            ld a,V_BDELAY
            ld (v_bcd),a
            jp mv_shoot                 ; derniere balle de la rafale
; vise Papi dans les 4 directions : Papi a plus de 8 lignes sous le camion = bas, a plus de 8 au-dessus = haut,
; sinon horizontal (droite si Papi est a droite du camion, gauche sinon)
mv_aim:     ld a,(v_xo)
            sub TW/2
            ld b,a
            ld a,(p_x)
            sub b
            ld b,a                      ; dx
            ld a,(v_y)
            add a,TH/2
            ld c,a
            ld a,(p_y)
            add a,6
            sub c
            ld c,a                      ; dy
            add a,8
            cp 17
            jr nc,.v
            ld a,b
            rlca
            and 1
            ld (v_aim),a
            ret
.v          ld a,c
            rlca
            and 1
            add a,2
            ld (v_aim),a
            ret
; une balle depuis la tourelle, dans la direction v_aim (balle d'ennemi : classe de portee 5, infinie)
mv_shoot:   ld a,(v_aim)
            ld e,a
            ld d,0
            ld hl,mv_ktab
            add hl,de
            add hl,de
            ld a,(v_xo)
            sub TW
            add a,(hl)
            ld b,a                      ; H : x du camion + decalage (la balle part de decalage + shot_tab)
            inc hl
            ld a,(v_y)
            add a,(hl)
            ld c,a                      ; L
            ld a,(v_aim)
            cp 2
            jr c,.f
            ld a,(v_dir)                ; cap a droite : la tourelle est a gauche
            or a
            jr nz,.f
            ld a,b
            sub 5
            ld b,a
.f          push ix
            ld ix,bullets+4*BSIZE
            ld de,BSIZE
            ld a,NBUL-4
.find       ex af,af'
            ld a,(ix+B_ON)
            or a
            jr z,.ok
            add ix,de
            ex af,af'
            dec a
            jr nz,.find
            pop ix
            ret
.ok         ld a,5
            ld (shot_cls),a
            ld h,b
            ld l,c
            ld a,(v_aim)
            call bullet_start
            pop ix
            ret
mv_ktab:    db 5,2, 1,2, 5,6, 5,4      ; par direction : decalage x, y du point de depart de la balle (apres soustraction du decalage de shot_tab)

;------------------------------------------------------------------------------
; touches
;------------------------------------------------------------------------------
; balle de Papi (IX) : touche le camion ? (1 point de degat)
mv_bullet:  ld a,(v_act)
            or a
            ret z
            ld a,(ix+B_X)
            ld hl,v_xo
            sub (hl)
            add a,TW
            cp TW
            ret nc
            ld a,(ix+B_Y)
            ld hl,v_y
            sub (hl)
            add a,2
            cp TH+2
            ret nc
            ld (ix+B_ON),2
            ld a,1
; A = points de degat
mv_dmg:     ld c,a
            ld a,(veh_on)
            and 7
            cp 1
            jr z,.army
            ld hl,kills_left            ; modes 2 et 3 : les points de vie sont ceux du HUD
            ld a,(hl)
            sub c
            jr nc,.s
            xor a
.s          ld (hl),a
            ld hl,hud_dirty
            set 2,(hl)
            or a
            jp z,mv_die
            jr .hit
.army       ld hl,v_hpt
            ld a,(hl)
            sub c
            jr nc,.s2
            xor a
.s2         ld (hl),a
            or a
            jp z,mv_die1
.hit        ld a,V_FLASH
            ld (v_fl),a
            ld a,#FF                    ; redessin tout de suite (en blanc)
            ld (v_of),a
            ld a,3
            jp sfx

; coordonnees des deux explosions du camion : B = x gauche, D = x droit, C = y
mv_spots:   ld a,(v_xo)
            sub TW
            jr nc,.a
            xor a
.a          cp 73
            jr c,.b
            ld a,72
.b          ld b,a
            ld a,(v_xo)
            sub 6
            jr nc,.c
            xor a
.c          cp 73
            jr c,.d
            ld a,72
.d          ld d,a
            ld a,(v_y)
            add a,TH/2-6
            ld c,a
            ret

; modes 2 et 3 : le camion est detruit (kills_left = 0 : la boucle principale appelle 'victory', qui dessine les explosions sur les places 0 et 1 : bk_final)
mv_die:     call mv_erase
            xor a
            ld (v_act),a
            ld a,255
            ld (v_wait),a
            call mv_spots
            ld a,b
            ld (enemies+E_X),a
            ld a,c
            ld (enemies+E_Y),a
            ld a,d
            ld (enemies+ESIZE+E_X),a
            ld a,c
            ld (enemies+ESIZE+E_Y),a
            ret

; mode 1 : le camion est detruit : 500 points, explosions, un autre arrive plus tard
mv_die1:    ld b,50
.pt         push bc
            ld hl,score+4
            call add_score
            pop bc
            djnz .pt
            call mv_erase
            xor a
            ld (v_act),a
            call mv_spots
            push de
            ld e,9
            call mv_fxadd
            pop de
            ld b,d
            ld e,9
            call mv_fxadd
            ld a,V_HP
            ld (v_hpt),a
            ld a,150
            ld (v_wait),a
            ld a,6
            jp sfx

;------------------------------------------------------------------------------
; explosions (3 emplacements : x, y, temps restant 0..17) : 4 images de 4 images d'affichage
;------------------------------------------------------------------------------
NFX         equ 8
mv_fxadd:   ld hl,v_fxs+2               ; B = x, C = y, E = minuterie (9 = tout de suite, +1 par image de retard)
            ld a,NFX
.f          ex af,af'
            ld a,(hl)
            or a
            jr z,.free
            inc hl
            inc hl
            inc hl
            ex af,af'
            dec a
            jr nz,.f
            ret
.free       ld (hl),e
            dec hl
            ld (hl),c
            dec hl
            ld (hl),b
            ret

; explosions en chaine autour du bidon : decalage x (octets), decalage y (lignes), retard (images)
mv_chain:   ld hl,mv_ctab
            ld d,6
.c          ld a,(mx_c)
            add a,(hl)
            inc hl
            ld b,a
            cp 73
            jr nc,.skip                 ; hors de l'ecran (ou retour a zero) : pas d'explosion
            ld a,(my_c)
            add a,(hl)
            inc hl
            ld c,a
            cp 176
            jr nc,.skip2
            ld a,(hl)
            add a,9
            ld e,a
            push hl
            call mv_fxadd
            pop hl
.skip2      inc hl
            jr .nx
.skip       inc hl
            inc hl
.nx         dec d
            jr nz,.c
            ret
mv_ctab:    db 6,0,2, -6,0,3, 0,-10,4, 0,10,5, 5,-8,6, -5,8,7

mv_fx:      ld ix,v_fxs
            ld b,NFX
.l          ld a,(ix+2)
            or a
            jr z,.n
            dec a
            ld (ix+2),a
            push bc
            jr z,.end
            and 3
            jr nz,.pop
            ld a,(ix+2)                 ; image : 2 - t / 4  (t = 8, 4) ; t > 8 : explosion en retard, rien encore
            cp 9
            jr nc,.pop
            srl a
            srl a
            ld c,a
            ld a,2
            sub c
            ld hl,EXPL_DATA
            ld de,100
            or a
            jr z,.p
            ld b,a
.m          add hl,de
            djnz .m
.p          push hl
            ld b,(ix+0)
            ld c,(ix+1)
            ld de,#060C
            call b1_restore
            pop de                      ; DE = image
            ld a,5                      ; image de 10 x 10 pixels : 5 octets, 10 lignes
            ld (bl_n),a
            ld a,10
            ld (bl_s),a
            ld (bl_h),a
            ld b,(ix+0)
            ld c,(ix+1)
            inc c
            call mv_blit
            jr .pop
.end        ld b,(ix+0)                 ; fin : le decor revient, les ennemis dessous se redessinent
            ld c,(ix+1)
            ld de,#060C
            call b1_restore
            ld b,(ix+0)
            ld c,(ix+1)
            call wake_12
.pop        pop bc
.n          ld de,3
            add ix,de
            djnz .l
            ret

;------------------------------------------------------------------------------
; bidons explosifs
;------------------------------------------------------------------------------
; IY = bidon -> B = x (octets), C = y (lignes) de sa case du haut
mv_bxy:     ld a,(iy+0)
            and 15
            ld b,a
            add a,a
            add a,b
            add a,a
            ld b,a
            ld a,(iy+0)
            rrca
            rrca
            rrca
            rrca
            and 15
            ld c,a
            ld a,(iy+1)
            and 1
            rlca
            rlca
            rlca
            rlca
            or c
            dec a
            add a,a
            add a,a
            add a,a
            ld c,a
            ret

; HL = case de la grille touchee par une balle : un coup de plus sur ce bidon (3 coups : il explose)
mv_barrel:  ld a,(veh_on)
            or a
            ret z
            ld a,(v_init)
            or a
            ret z
            ld d,h
            ld e,l
            ld bc,-16
            add hl,bc
            ld a,(hl)
            and #1F                     ; bidon : bits 0-2 et 4 (les casernes n'ont pas le bit 4)
            cp #17
            jr z,.top                   ; la case du dessus est un bidon : HL est la case du haut
            ex de,hl
.top        ld a,(v_nb)
            or a
            ret z
            ld b,a
            ld iy,v_bar
            ld de,BARSZ
.f          ld a,(iy+0)
            cp l
            jr nz,.n
            ld a,(iy+1)
            cp h
            jr z,.found
.n          add iy,de
            djnz .f
            ret
.found      ld a,(iy+3)
            dec a
            ret nz                      ; deja en flammes
            inc (iy+2)
            ld a,(iy+2)
            cp 3
            ret c
            jp mv_explode

; explosion de grenade (g_ex, g_ey) : le camion et les bidons dans le souffle
mv_gren:    ld a,(v_init)
            or a
            ret z
            ld a,(v_act)
            or a
            jr z,.bar
            ld a,(g_ex)
            ld hl,v_xo
            sub (hl)
            add a,21
            cp 25
            jr nc,.bar
            ld a,(g_ey)
            ld hl,v_y
            sub (hl)
            add a,18
            cp 49
            jr nc,.bar
            ld a,3
            call mv_dmg
.bar        ld a,(v_nb)
            or a
            ret z
            ld b,a
            ld iy,v_bar
.l          ld a,(iy+3)
            dec a
            jr nz,.n
            push bc
            call mv_bxy
            ld a,(g_ex)
            sub b
            add a,9
            cp 19
            jr nc,.nb
            ld a,(g_ey)
            sub c
            add a,18
            cp 41
            jr nc,.nb
            call mv_explode
.nb         pop bc
.n          ld de,BARSZ
            add iy,de
            djnz .l
            ret

; IY = bidon : il explose. Les deux cases deviennent des flammes (case = 4), explosion, 3 points de degat autour (ennemis, Papi, camion)
mv_explode: ld (iy+3),2
            ld (iy+4),#FF
            ld l,(iy+0)
            ld h,(iy+1)
            ld a,(hl)
            and #E8
            or 4
            ld (hl),a
            ld de,16
            add hl,de
            ld a,(hl)
            and #E8
            or 4
            ld (hl),a
            ld d,0                      ; flammes : image 0, tout de suite (les explosions effacent depuis le miroir)
            call mv_fdraw
            call mv_bxy
            ld a,c
            add a,2
            ld c,a
            ld (my_c),bc                ; centre du souffle : my_c = y (C), mx_c = x (B) juste apres (voir la declaration)
            ld e,9
            call mv_fxadd
            call mv_chain               ; ... et la chaine d'explosions autour
            ld a,6
            call sfx
            ld ix,enemies
            ld b,MAXENEMY
.e          ld a,(ix+E_STATE)
            dec a
            jr nz,.en
            ld a,(mx_c)
            sub (ix+E_X)
            add a,9
            cp 19
            jr nc,.en
            ld a,(my_c)
            sub (ix+E_Y)
            add a,18
            cp 37
            jr nc,.en
            push bc
            ld b,5                      ; 5 points de degat (un par appel : s'arrete a la mort)
.dm         ld hl,enemy_killed          ; via la rampe : la mort d'un grenadier appelle gr_call (banque 7) et ne doit pas se faire depuis la banque 7
            call b1_kill
            ld a,(ix+E_STATE)
            dec a
            jr nz,.dd
            djnz .dm
.dd         pop bc
.en         ld de,ESIZE
            add ix,de
            djnz .e
            ld a,(p_state)
            or a
            jr nz,.t
            ld a,(mx_c)
            ld hl,p_x
            sub (hl)
            add a,9
            cp 19
            jr nc,.t
            ld a,(my_c)
            ld hl,p_y
            sub (hl)
            add a,18
            cp 37
            jr nc,.t
            call player_hit
.t          ld a,(v_act)
            or a
            ret z
            ld a,(mx_c)
            ld hl,v_xo
            sub (hl)
            add a,21
            cp 25
            ret nc
            ld a,(my_c)
            ld hl,v_y
            sub (hl)
            add a,18
            cp 49
            ret nc
            ld a,3
            jp mv_dmg

; IY = bidon, D = phase (0..3 : 0 1 2 1) : dessine les deux cases de flamme (ecran et miroir)
mv_fdraw:   ld a,d
            add a,a
            add a,a
            add a,a
            add a,a
            ld e,a
            ld hl,(wtr_img)
            push hl
            ld hl,(spawn_tab+30)        ; images de flamme de la zone (les 2 derniers octets de la table des points d'apparition)
            ld (wtr_img),hl
            ld l,(iy+0)
            ld h,(iy+1)
            push de
            call b1_wtr
            pop de
            ld a,(iy+3)
            dec a
            jr z,.top                   ; bidon intact : la case du haut seulement
            ld l,(iy+0)
            ld h,(iy+1)
            ld bc,16
            add hl,bc
            call b1_wtr
.top        pop hl
            ld (wtr_img),hl
            ret

; animation des flammes : un bidon par image (tour a tour), sauf si un ennemi est sur ses cases
mv_flames:  ld a,(v_nb)
            or a
            ret z
            ld a,(v_bi)
            inc a
            and 7
            ld (v_bi),a
            ld hl,v_nb
            cp (hl)
            ret nc
            ld c,a
            add a,a
            add a,c
            add a,a
            ld e,a
            ld d,0
            ld iy,v_bar
            add iy,de
            ld a,(iy+3)
            cp 3
            ret nc
            ld c,a                      ; c = 1 : bidon intact (seule la case du haut brule) ; 2 : en flammes (deux cases)
            ld a,(frame)
            rrca
            rrca
            rrca
            rrca
            and 3
            ld d,a
            cp (iy+4)
            ret z
            ld l,(iy+0)
            ld h,(iy+1)
            bit 6,(hl)
            ret nz
            dec c
            jr z,.one
            ld bc,16
            add hl,bc
            bit 6,(hl)
            ret nz
            ld (iy+4),d
            jp mv_fdraw
.one        ld (iy+4),d
            jp mv_fdraw

; les flammes brulent Papi et les ennemis qui les touchent (cases des pieds) : une image sur 4
mv_hazard:  ld a,(v_nb)
            or a
            ret z
            ld a,(p_state)
            or a
            jr nz,.en
            ld bc,(p_y)
            ld a,b
            add a,3
            ld b,a
            ld a,c
            add a,10
            ld c,a
            call cell_ptr
            ld a,(hl)
            and 7
            cp 4
            call z,player_hit
.en         ld ix,enemies
            ld b,MAXENEMY
.l          ld a,(ix+E_STATE)
            dec a
            jr nz,.n
            push bc
            ld a,(ix+E_X)
            add a,3
            ld b,a
            ld a,(ix+E_Y)
            add a,10
            ld c,a
            call cell_ptr
            ld a,(hl)
            and 7
            cp 4
            jr nz,.nk
            ld hl,enemy_kill_now
            call b1_kill
.nk         pop bc
.n          ld de,ESIZE
            add ix,de
            djnz .l
            ret

mv_sprtab:  dw TRUCK_DATA, TRUCK_DATA+TIMG, TRUCK_DATA+2*TIMG, TRUCK_DATA+3*TIMG, TRUCK_DATA+4*TIMG, TRUCK_DATA+5*TIMG, TRUCK_DATA+6*TIMG, TRUCK_DATA+7*TIMG, TRUCK_DATA+8*TIMG, TRUCK_DATA+9*TIMG

; variables du module (remises a zero au debut de chaque mission : mv_init)
mv_vars:
v_act       ds 1                ; 0 hors de l'ecran, 1 en route
v_xo        ds 1                ; x + 12 du camion (0 = tout juste sorti a gauche, 90 = a droite)
v_y         ds 1
v_dir       ds 1                ; 0 vers la droite, 1 vers la gauche
v_acc       ds 1                ; cumul de vitesse
v_ox        ds 1                ; xo affiche (#FF : rien)
v_oy        ds 1
v_of        ds 1                ; image affichee
v_wait      ds 1
v_dtim      ds 1
v_hpt        ds 1
v_aim       ds 1
v_bn        ds 1
v_bt        ds 1
v_bcd       ds 1
v_bi        ds 1
v_fl        ds 1
v_dxx       ds 1
v_k         ds 1
v_got       ds 1
v_late      ds 1
v_nb        ds 1
nw_lo       ds 1
nw_hi       ds 1
bl_n        ds 1
bl_s        ds 1
bl_h        ds 1
my_c        ds 1                ; (dans cet ordre : ld (my_c),bc range C en my_c et B en mx_c)
mx_c        ds 1
v_fxs       ds 3*NFX
v_bar       ds NBAR*BARSZ
sb_x        ds 1
sb_y        ds 1
il_on       ds 1
il_fn       ds 2
il_n        ds 1
ud_x        ds 1
ud_w        ds 1
mv_vars_end:
