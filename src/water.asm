;==============================================================================
; EAU ANIMEE (zone 3 "Hidden Headquarter") : tuile d'eau sur 3 images (1 2 3 2) et regles de l'eau
;
;   Aucun octet de plus dans la partie permanente (qui est pleine) : ces routines sont rangees ici (a la fin du programme),
;   recopiees au demarrage (boot) en memoire basse (WTR_ZP, libre : les variables finissent en #0117 et la pile ne descend
;   pas sous #01E0) et dans un trou de la grille (WTR_HI). Le moteur ne contient que 4 appels :
;     wtr_tick  (boucle principale, avant Papi), wtr_frame (image de Papi), wtr_load (chargement de la zone) et le
;     bit 3 de la grille que le champ de distances et can_stand_e refusent aux ennemis.
;
;   REGLES (cahier des charges, echanges du 12/10) :
;     - l'eau (carre rose des obstacles) = bit 3 de la grille, sans le bit 0 : Papi peut la franchir (can_stand_p ne teste que le bit 0),
;       les ennemis non (can_stand_e et le champ de distances testent aussi le bit 3) ;
;     - les balles et les grenades (ennemis comme Papi) passent au-dessus (elles ne testent que le bit 1) ;
;     - Papi dans l'eau : 25 % plus lent (operandes de PSPEED_X / PSPEED_Y modifies) et sprite 12 x 6 (image sans les jambes) ;
;       il reste touchable (zone de touche inchangee) ; il lance ses grenades depuis l'eau.
;
;   ANIMATION : la grille balayee par WTR_SCAN cases a chaque image ; une case d'eau dont l'image n'est pas celle du moment
;   ((frame / 16 + ligne + colonne) mod 4, memorisee dans les bits 4-5 de la case) est redessinee (ecran ET miroir),
;   au plus WTR_MAXD cases par image (environ 2000 cycles chacune). Une case touchee par un sprite d'ennemi
;   (bit 6 : cases reservees) est sautee ; les balles sont redessinees a chaque image, Papi apres l'eau (ordre de la boucle).
;==============================================================================
WTR_HI      equ #39A0                   ; bloc 2 (wtr_draw) : trou libre de la grille (#39A0-#39FF)
WTR_LO      equ #31E3                   ; bloc 3 (wtr_load) : trou libre des tables (#31E3-#31FF ; lz_off occupe #31E1-#31E2)
wtr_img     equ #31D8                   ; variables : 7 octets recopies de l'en-tete de zone (hdr[88..94]) + wtr_n
wtr_buf     equ #31DA
wtr_ptr     equ #31DC
wtr_in      equ #31DE
wtr_n       equ #31DF
WTR_SCAN    equ 32                      ; cases de la grille examinees par image (384 cases : un balayage en 12 images)
WTR_MAXD    equ 3                       ; cases redessinees au plus par image
WSLOW_X     equ 36                      ; PSPEED_X x 0,40
WSLOW_Y     equ 72                      ; PSPEED_Y x 0,40
            assert (PSPEED_X==90)       ; (WSLOW_X/Y a refaire si la vitesse de Papi change)
            assert (PSPEED_Y==179)

water_src:
            org WTR_ZP,water_src
wzp_start:

; appelee a chaque image, avant player_update
wtr_tick:
            ld hl,(wtr_img)
            ld a,h
            or l
            ret z                       ; pas d'eau dans cette zone
            ld a,(p_state)
            cp 2
            ret z                       ; fin de mission / game over : l'ecran est fige ou noir, plus aucune tuile d'eau a redessiner
            ld bc,(p_y)                 ; la case des pieds de Papi est-elle de l'eau ?
            ld a,b
            add a,3
            ld b,a
            ld a,c
            add a,10
            ld c,a
            call cell_ptr
            ld a,(hl)
            and 8
            ld (wtr_in),a
            ld hl,PSPEED_X+256*PSPEED_Y
            jr z,.sp
            ld hl,WSLOW_X+256*WSLOW_Y
.sp         ld a,l
            ld (psx),a
            ld a,h
            ld (psy),a
            ld a,(frame)
            rrca
            rrca
            rrca
            rrca
            and 3
            ld d,a                      ; D = phase (change toutes les 16 images)
            ld hl,(wtr_ptr)
            ld bc,WTR_SCAN*256+WTR_MAXD ; B = cases a examiner, C = redessins permis
.sc         ld a,(hl)
            and #48                     ; eau (bit 3) et pas d'ennemi dessus (bit 6)
            cp 8
            jr nz,.nx
            ld a,l                      ; image voulue n = (phase + ligne + colonne) mod 4, avec L = 16 x (ligne+1) + colonne
            rrca
            rrca
            rrca
            rrca
            ld e,a
            ld a,l
            add a,e
            dec a
            add a,d
            and 3
            rlca
            rlca
            rlca
            rlca
            ld e,a                      ; E = n x 16 : les bits 4-5 de la case
            ld a,(hl)
            xor e
            and #30
            jr z,.nx                    ; deja a jour
            ld a,(hl)
            and #CF
            or e
            ld (hl),a
            push bc
            push de
            push hl
            call wtr_draw
            pop hl
            pop de
            pop bc
            dec c
            jr z,.done
.nx         inc hl
            ld a,l
            cp #90                      ; fin de la grille : GRID + 400 = #3990
            jr nz,.nw
            ld a,h
            cp #39
            jr nz,.nw
            ld hl,GRID+16
.nw         djnz .sc
.done       ld (wtr_ptr),hl
            ret

; HL = image de Papi (144 octets) -> HL = image a dessiner : dans l'eau, une copie dont les 6 dernieres lignes sont transparentes
wtr_frame:
            ld a,(wtr_in)
            or a
            ret z
            ld de,(wtr_buf)
            push de
            ld bc,144
            ldir
            pop hl
            push hl
            ld de,72                    ; lignes 6 a 11 (12 octets par ligne) : masque #FF, donnee 0 = le decor
            add hl,de
            ld b,36
.b          ld (hl),#FF
            inc hl
            ld (hl),0
            inc hl
            djnz .b
            pop hl
            ret

wzp_end:
water_zp_len equ wzp_end-wzp_start
            assert wzp_end<=#01E0       ; la pile descend jusqu'a #01E0 au plus

            org WTR_HI,water_src+water_zp_len
whi_start:
; HL = case de la grille, E = n x 16 : dessine l'image (1 2 3 2 -> 0 1 2 1) de la tuile, a l'ecran et dans le miroir
wtr_draw:
            ld a,e
            cp #30                      ; n = 3 -> image 1 (sequence 1 2 3 2)
            jr nz,.f
            ld a,#10
.f          ld c,a
            add a,a
            add a,c                     ; 48 x image
            ld e,a
            ld d,0
            push hl
            ld hl,(wtr_img)
            add hl,de
            ex de,hl                    ; DE = donnees
            pop hl
            ld a,l                      ; x = 6 x colonne
            and 15
            ld c,a
            add a,a
            add a,c
            add a,a
            ld b,a
            ld a,l                      ; y = 8 x ligne
            rrca
            rrca
            rrca
            rrca
            and 15
            bit 0,h
            jr z,.y
            add a,16
.y          dec a
            add a,a
            add a,a
            add a,a
            ld c,a
            call scr_addr               ; HL = ecran (BC, DE conserves)
            ex de,hl                    ; HL = donnees, DE = ecran
            push hl
            push de
            call .cp                    ; ecran
            pop de
            pop hl
            res 7,d                     ; puis miroir
.cp         ld a,8
            ld (wtr_n),a
.ln         push de
            repeat 6
              ldi
            rend
            pop de
            ld a,d                      ; ligne suivante (une rangee de tuiles = une rangee de caracteres : jamais de retenue)
            add a,8
            ld d,a
            ld a,(wtr_n)
            dec a
            ld (wtr_n),a
            jr nz,.ln
            ret
whi_end:
water_hi_len equ whi_end-whi_start
            assert whi_end<=#3A00       ; le trou finit avant le 1er champ de distances

            org WTR_LO,water_src+water_zp_len+water_hi_len
wlo_start:
; chargement de la zone (fin de load_zone_data) : parametres de l'eau lus dans l'en-tete du fichier de zone
wtr_load:
            ld hl,ZSTAGE+88             ; img, buf, ptr, in
            ld de,wtr_img
            ld bc,7
            ldir
            ld a,PSPEED_X
            ld (psx),a
            ld a,PSPEED_Y
            ld (psy),a
            ret
wlo_end:
water_lo_len equ wlo_end-wlo_start
            assert wlo_end<=#3200

            org water_src+water_zp_len+water_hi_len+water_lo_len
