;==============================================================================
;  ECRANS NOIRS DE MISSION : overlay lu en MENU_LOAD avant chaque mission (INTRO_N secteurs), puis appele.
;  Ecran noir, zone / numero / type de mission (src/intro_gfx.asm), ~2 s ; la mission se charge ensuite, texte toujours affiche.
;  Apres la derniere mission (zone_cur = NZONES) : "CONGRATULATIONS !!" avec le jingle de Zone Clear, puis le menu principal.
;==============================================================================
            jp intro_run                ; INTRO_LOAD : ecran de mission
            jp banner_entry             ; INTRO_LOAD+3 : bandeau du haut de l'ecran
; le bandeau (appele plus tard par new_game2) et ses donnees doivent rester dans #4000-#47FF : le reste de l'overlay est ecrase
; par la zone qui se charge en #4800
; mode demo (acc_zone bit 7, voir menu.asm) : pas d'ecran de mission (ecran noir seulement) ; apres le chargement de la zone, veh_on bit 7 branche le module de la demo (veh_mod.asm)
banner_entry:
            ld a,(acc_zone)
            rlca
            jr nc,draw_banner
            ld hl,veh_on
            set 7,(hl)
draw_banner:
            ld ix,banner_fill
            ld c,200
.fl         ld b,0
            call scr_addr               ; HL = ligne du bandeau, conserve BC, DE
            ld a,(ix+0)
            inc ix
            push bc
            ld d,h
            ld e,l
            inc de
            ld (hl),a
            ld bc,79
            ldir
            pop bc
            inc c
            ld a,c
            cp 216                      ; 200 + 16 lignes
            jr nz,.fl
            ld hl,banner_txt
.t          ld a,(hl)
            or a
            ret z
            ld (big_on),a
            inc hl
            ld b,(hl)
            inc hl
            ld c,205
            call print_big
            inc hl
            jr .t
banner_fill:
            ds 2,#0C                    ; 2 lignes rouge vif
            ds 2,#CF                    ; 2 lignes jaune vif
            ds 12,0
banner_txt: db #CF,6,'PAPI COMMANDO',0  ; couleur, x, texte : jaune vif ; "CPC" : C rouge, P vert, C bleu
            db #0C,62,'C',0
            db #30,66,'P',0
            db #FF,70,'C',0
            db 0
banner_end:
            assert banner_end<=#4800

intro_run:  call blackout
            ld a,(acc_zone)             ; mode demo : on ne montre pas l'ecran de mission
            rlca
            ret c
            ld a,(zone_cur)
            cp NZONES
            jr z,.fin
            ld a,(carry)                ; on vient de gagner la derniere mission d'une zone ? (1re mission d'une zone suivante)
            or a
            jr z,.go
            ld a,(zone_cur)
            ld hl,zone_start            ; premieres missions des zones 2, 3, ...
            ld de,intro_zend            ; fin de la zone 1, 2, ...
.zs         ld c,(hl)
            inc hl
            inc c
            jr z,.go                    ; fin de la liste : mission ordinaire
            dec c
            cp c
            jr z,.zend
            inc de
            inc de
            jr .zs
.zend       ex de,hl
            ld e,(hl)
            inc hl
            ld d,(hl)
            ex de,hl
            call .endscr
            call blackout
.go         ld a,(zone_cur)
            add a,a
            ld l,a
            ld h,0
            ld de,intro_tab
            add hl,de
            ld e,(hl)
            inc hl
            ld d,(hl)
            ex de,hl
            call .show                  ; "MISSION 0n" et l'objectif
            ld a,(zone_cur)
            add a,a
            add a,a
            ld e,a
            ld d,0
            ld hl,intro_missions
            add hl,de
            call items_init             ; HL = nom de la zone
            call .show
            call jn_init
            ld d,JN_FRAMES+4                    ; 2,4 secondes : les ennemis de la mission arrivent de la gauche et s'arretent au milieu, sous le texte
.anim       ld b,#F5
.va         in a,(c)
            rra
            jr c,.va
.vb         in a,(c)
            rra
            jr nc,.vb
            push de
            call jn_update              ; jingle de depart de niveau (a la place des bruitages : il a tout le AY)
            call items_step
            pop de
            dec d
            jr nz,.anim
            jp jn_stop
.fin        ld hl,(intro_zend+2*NZG-2)  ; fin de la derniere zone : message et fanfare de victoire (la sienne : jw_data), puis retour au menu principal
            ld de,jw_data
            ld a,JW_FRAMES
            call .endsc2
            ld a,(score+1)              ; Hall of Fame : score minimum en jeu (HOF_MIN points) atteint ?  (chiffres milliers, centaines, dizaines)
            or a
            jr nz,.hin
            ld hl,score+2
            ld a,(hl)
            cp HM_K
            jp c,menu_enter
            jr nz,.hin
            inc hl
            ld a,(hl)
            cp HM_H
            jp c,menu_enter
            jr nz,.hin
            inc hl
            ld a,(hl)
            cp HM_T
            jp c,menu_enter
.hin        ld a,1
            ld (HOF_MODE),a
            ld hl,menu_enter            ; l'overlay HOF rend la main au menu principal
            push hl
            jp ovl_hof
; HL = message de fin de zone : fanfare de victoire (4,4 s) puis un court silence
.endscr     ld de,jv_data
            ld a,JV_FRAMES
.endsc2     push de                     ; DE = jingle, A = nombre d'images
            push af
            call .show
            pop af
            pop hl
            ld (jn_src),hl
            ld (jn_n),a
            add a,25
            ld d,a
.fl         ld b,#F5
.fa         in a,(c)
            rra
            jr c,.fa
.fb         in a,(c)
            rra
            jr nc,.fb
            push de
            call jn_update
            pop de
            dec d
            jr nz,.fl
            jp jn_stop

; lignes : x, y, couleur, texte, 0 ... ; x = 0 : fin
.show       ld a,(hl)
            or a
            ret z
            ld b,a
            inc hl
            ld c,(hl)
            inc hl
            ld a,(hl)
            ld (big_on),a
            inc hl
            call print_big
            inc hl
            jr .show

.wait       ld b,#F5
.a          in a,(c)
            rra
            jr c,.a
.b          in a,(c)
            rra
            jr nc,.b
            push de
            call sound_update
            pop de
            dec d
            jr nz,.wait
            ret

IV          equ #7A00           ; variables de l'ecran de mission (zone libre : le decor est reconstruit apres)
iv_u        equ IV              ; (2) liste d'images de la mission : nombre, puis 11 octets par image
iv_t        equ IV+2            ; images ecoulees
iv_n        equ IV+3            ; images restantes dans la liste
iv_p        equ IV+4            ; (2) image en cours
sp_src      equ IV+6            ; (2)
sp_x        equ IV+8
sp_y        equ IV+9
sp_cs       equ IV+10
sp_n        equ IV+11
sp_vx       equ IV+12
sp_l        equ IV+13
sp_w        equ IV+14
sp_h        equ IV+15
jn_src      equ IV+64           ; (2) jingle : octet suivant du flux
jn_n        equ IV+66           ; images restantes
jn_r        equ IV+67
sp_buf      equ IV+16           ; 1 + largeur octets : colonne noire a gauche + une ligne de l'image (41 octets maxi)

; jingle de depart de niveau : par image, un masque de 2 octets (bit i = registre i change) puis les valeurs (voir tools/mkmusic.py)
jn_init:    ld hl,jn_data
            ld (jn_src),hl
            ld a,JN_FRAMES
            ld (jn_n),a
            ret

jn_update:  ld a,(jn_n)
            or a
            ret z
            dec a
            ld (jn_n),a
            ld hl,(jn_src)
            ld e,(hl)
            inc hl
            ld d,(hl)
            inc hl
            xor a
            ld (jn_r),a
.lp         srl d
            rr e
            jr nc,.nx
            ld c,(hl)
            inc hl
            ld a,(jn_r)
            cp 7
            jr nz,.w
            ld a,c
            and #3F                     ; melangeur : bits 6 et 7 a 0 (clavier lu par le port A du AY)
            ld c,a
            ld a,7
.w          push hl
            push de
            call ay_write
            pop de
            pop hl
.nx         ld a,(jn_r)
            inc a
            ld (jn_r),a
            cp 13
            jr nz,.lp
            ld (jn_src),hl
            ret

jn_stop:    ld c,#3F                    ; silence : le jeu reprend le AY
            ld a,7
            call ay_write
            ld c,0
            ld a,8
            call ay_write
            ld c,0
            ld a,9
            call ay_write
            ld c,0
            ld a,10
            jp ay_write

; HL = fiche de la mission (intro_missions + 4 x numero) -> HL = nom de la zone ; la liste d'images est memorisee
items_init: ld e,(hl)
            inc hl
            ld d,(hl)
            inc hl
            ld a,(hl)
            ld (iv_u),a
            inc hl
            ld a,(hl)
            ld (iv_u+1),a
            xor a
            ld (iv_t),a
            ld (sp_buf),a
            ex de,hl
            ret

; une image de l'animation.  Image d'une liste : donnees (2), taille d'une image (2), largeur, hauteur, masque d'images - 1,
;   x final, y, drapeaux (bit 0 : arrive de la gauche, 1 octet par image-ecran), retard.  Une image a l'arret n'est dessinee qu'une fois.
items_step: ld hl,(iv_u)
            ld a,(hl)
            or a
            jr z,.end
            ld (iv_n),a
            inc hl
            ld (iv_p),hl
.it         ld ix,(iv_p)
            ld a,(iv_t)
            rrca
            rrca
            and (ix+6)
            ld c,a                      ; C = numero d'image (marche ou animation)
            bit 0,(ix+9)
            jr nz,.walk
            ld b,(ix+7)                 ; fixe : dessine au debut (et a chaque image s'il est anime ou s'il doit passer devant les ennemis)
            ld a,(iv_t)
            or a
            jr z,.draw
            bit 1,(ix+9)
            jr nz,.draw
            ld a,(ix+6)
            or a
            jr nz,.draw
            jr .next
.walk       ld a,(iv_t)
            sub (ix+10)
            ld b,a                      ; B = x (signe : negatif = pas encore entre)
            or a
            jp m,.draw
            cp (ix+7)
            jr c,.draw
            jr nz,.next                 ; deja arrive et dessine
            ld c,0                      ; arrive : image fixe, une seule fois
.draw       ld l,(ix+0)
            ld h,(ix+1)
            ld a,c
            or a
            jr z,.g
            ld e,(ix+2)
            ld d,(ix+3)
.m          add hl,de
            dec a
            jr nz,.m
.g          ld a,(ix+4)
            ld (sp_w),a
            ld a,(ix+5)
            ld (sp_h),a
            ld c,(ix+8)
            call sp_draw
.next       ld hl,(iv_p)
            ld de,11
            add hl,de
            ld (iv_p),hl
            ld hl,iv_n
            dec (hl)
            jr nz,.it
.end        ld hl,iv_t                  ; (de 96 a 127 en boucle : x = t - retard reste positif quand l'image est arrivee ; 32 images = un cycle complet de l'animation des snipers)
            ld a,(hl)
            inc a
            cp 128
            jr c,.sv
            ld a,96
.sv         ld (hl),a
            ret

; image de largeur sp_w (octets) x sp_h lignes (HL, donnees seules) en B = x (signe), C = y.  La colonne de gauche est noire :
; elle efface la trace du pas.  Ce qui sort de l'ecran est coupe.
sp_draw:    ld (sp_src),hl
            ld a,b
            ld (sp_x),a
            ld a,c
            ld (sp_y),a
            ld a,(sp_w)
            inc a
            ld e,a                      ; E = colonnes (noire + image)
            ld a,b
            ld c,0
            or a
            jp p,.pos
            neg
            cp e
            ret nc                      ; entierement a gauche de l'ecran
            ld c,a                      ; colonnes coupees a gauche
            ld a,e
            sub c
            jr .set
.pos        ld a,79
            sub b
            ret c
            ret z
            cp e
            jr c,.set
            ld a,e
.set        ld (sp_n),a
            ld a,c
            ld (sp_cs),a
            ld a,(sp_x)
            add a,c
            ld (sp_vx),a
            ld a,(sp_h)
.ln         ld (sp_l),a
            ld hl,(sp_src)
            ld de,sp_buf+1
            ld a,(sp_w)
            ld c,a
            ld b,0
            ldir
            ld (sp_src),hl
            ld a,(sp_y)
            ld c,a
            ld b,0
            call scr_addr
            ld a,(sp_vx)
            ld e,a
            ld d,0
            add hl,de
            ex de,hl
            ld hl,sp_buf
            ld a,(sp_cs)
            ld c,a
            ld b,0
            add hl,bc
            ld a,(sp_n)
            ld c,a
            ld b,0
            ldir
            ld hl,sp_y
            inc (hl)
            ld a,(sp_l)
            dec a
            jr nz,.ln
            ret

            include 'intro_gfx.asm'
            include 'jingle_level.asm'
            include 'jingle_victory.asm'
            include 'jingle_victory3.asm'
