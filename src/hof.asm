;==============================================================================
;  HALL OF FAME : overlay lu en HOF_LOAD (#4000-#7FFF libre : ni jeu ni menu a ce moment), puis appele.  Son 'ret' revient a menu_enter
;  (l'appelant a empile menu_enter avant de charger l'overlay).
;
;  HOF_MODE (octet permanent) : 0 = le classement defile sous le bandeau (appele par le menu a la fin de la musique)
;                               1 = saisie du nom apres une partie dont le score entre dans le classement (appele par le game over
;                                   ou par l'ecran de fin de jeu)
;
;  La table (7 entrees de 15 octets : nom sur 10 caracteres complete par des points, 5 chiffres du score) est rangee dans les
;  16 octets libres qui terminent chaque trou de la page A (HOF_E0 + n x #800) : ni le jeu, ni les overlays n'y touchent, et le
;  code permanent n'a pas grossi d'un octet.  Elle est creee par le menu au 1er passage (hof_init) ; deux octets magiques.
;
;  Saisie : Papi (spritesheet d'origine, dos tourne) marche en bas, gauche / droite = colonne, haut / bas = rangee, tir = la balle
;  monte et touche la lettre entouree de rouge : elle pivote (3 tours) et s'ajoute au nom ; "<" efface, "OK" valide.
;==============================================================================
HV          equ #7C00                   ; variables
hv_px       equ HV                      ; x de Papi (octets)
hv_an       equ HV+1                    ; image de marche
hv_at       equ HV+2
hv_len      equ HV+3                    ; lettres du nom
hv_rank     equ HV+4                    ; rang de la nouvelle entree (255 : aucune)
hv_row      equ HV+5                    ; rangee voulue 0..2
hv_sel      equ HV+6                    ; case entouree (255 : aucune)
hv_bon      equ HV+7                    ; balle en vol
hv_bx       equ HV+8
hv_by       equ HV+9
hv_bty      equ HV+10                   ; la balle s'arrete quand son y <= hv_bty
hv_bit      equ HV+11                   ; case visee
hv_spi      equ HV+12                   ; case qui pivote (255 : aucune)
hv_spt      equ HV+13                   ; images restantes du pivotement
hv_pj       equ HV+14                   ; touches de l'image precedente
hv_pen      equ HV+15
hv_gm       equ HV+16                   ; mode du glyphe : 0 normal, 1 de profil, 2 en miroir
hv_ry0      equ HV+17                   ; y de la 1re ligne du classement
hv_i        equ HV+18
hv_odd      equ HV+19
hv_cnt      equ HV+20
hv_y        equ HV+21
hv_r        equ HV+22
hv_cp       equ HV+23                   ; (2)
hv_p        equ HV+26                   ; 5 chiffres du nouveau score
hv_buf      equ HV+32                   ; 4 octets d'une ligne de glyphe
hv_ox       equ HV+36
hv_ci       equ HV+37
hv_sg       equ HV+38
hv_done     equ HV+39
hv_ed       equ HV+40                   ; touches enfoncees depuis l'image precedente
hv_jy       equ HV+41
hv_old      equ HV+42
hv_pit      equ HV+43                   ; pas du classement (lignes)
HVN_LEN      equ 48
CANVAS      equ #6000                   ; copie du classement (112 lignes de 60 octets) pour le defilement : #6000-#7A3F

BAN_Y       equ 2                       ; bandeau Papi Commando
RK_Y0       equ 31                      ; classement (saisie)
RK_X        equ 9
TXT_Y       equ 116
GY0         equ 129                     ; rangees de la grille
GY1         equ 142
GY2         equ 155
PAPI_Y      equ 180
HYEL          equ #CF                     ; jaune
HRED        equ #0C                     ; rouge
SPIN_N      equ 24

            jp hof_main                 ; HOF_LOAD : point d'entree
            include 'hof_gfx.asm'       ; bandeau, police, cercles (genere par tools/convert.py)

hof_main:   di
            ld hl,HV
            ld de,HV+1
            ld bc,HVN_LEN-1
            ld (hl),0
            ldir
            call blackout
            ld hl,palette_hw
            call hof_pal
            ld a,(HOF_MODE)
            or a
            jp nz,hof_entry
            jp hof_scroll

hof_pal:    xor a                       ; HL = 17 octets (16 encres + bordure)
.p          ld b,#7F
            out (c),a
            ld e,(hl)
            out (c),e
            inc hl
            inc a
            cp 17
            jr nz,.p
            ret

hof_vs:     ld b,#F5
.a          in a,(c)
            rra
            jr c,.a
.b          in a,(c)
            rra
            jr nc,.b
            ret

; A = rang -> HL = entree dans la page A
h_ent:      ld hl,HOF_MODE
            bit 1,(hl)
            jr z,.t
            ld hl,code_buf              ; saisie d'un code d'acces : le tampon du code remplace l'entree du classement
            ret
.t          add a,a
            add a,a
            add a,a
            add a,#87
            ld h,a
            ld l,#50
            ret

; bandeau : TITLE_H lignes de 78 octets en y = BAN_Y
hof_banner: ld hl,hof_title
            ld c,BAN_Y
            ld a,TITLE_H
.r          push af
            push bc
            push hl
            ld b,0
            call scr_addr
            ex de,hl
            pop hl
            ld bc,78
            ldir
            pop bc
            inc c
            pop af
            dec a
            jr nz,.r
            ret

;------------------------------------------------------------------------------
; texte : A = caractere, B = x (octets), C = y, (hv_pen) = octet allume, (hv_gm) = mode.  Caractere double : 3 octets de 2 pixels + 1 de blanc,
; 10 lignes.  Conserve BC, DE, HL
;------------------------------------------------------------------------------
draw_glyph: push bc
            push de
            push hl
            sub 32
            cp 64
            jr c,.ok
            xor a
.ok         ld l,a
            ld h,0
            ld d,h
            ld e,l
            add hl,hl
            add hl,hl
            add hl,de                   ; x 5
            ld de,hof_font
            add hl,de
            ld a,5
            ld (hv_cnt),a
.row        ld a,(hl)
            inc hl
            push hl
            ld e,a                      ; E = 3 colonnes (bits 7..5)
            ld a,(hv_gm)
            or a
            jr z,.go
            dec a
            jr z,.nar
            ld d,0                      ; miroir : bits 7 et 5 echanges
            bit 7,e
            jr z,.m1
            set 5,d
.m1         bit 5,e
            jr z,.m2
            set 7,d
.m2         bit 6,e
            jr z,.m3
            set 6,d
.m3         ld e,d
            jr .go
.nar        ld a,e                      ; de profil : une seule colonne (celle du milieu)
            and #E0
            jr z,.go
            ld e,#40
.go         ld a,(hv_pen)
            ld d,a
            ld a,e
            ld hl,hv_buf
            ld (hl),0
            rla
            jr nc,.a
            ld (hl),d
.a          inc hl
            ld (hl),0
            rla
            jr nc,.b
            ld (hl),d
.b          inc hl
            ld (hl),0
            rla
            jr nc,.c
            ld (hl),d
.c          inc hl
            ld (hl),0
            call h_put4
            inc c
            call h_put4
            inc c
            pop hl
            ld a,(hv_cnt)
            dec a
            ld (hv_cnt),a
            jr nz,.row
            pop hl
            pop de
            pop bc
            ret

h_put4:     call scr_addr
            push bc
            ex de,hl
            ld hl,hv_buf
            ldi
            ldi
            ldi
            ldi
            pop bc
            ret

; HL = texte (fin : 0), B = x, C = y
hof_text:   ld a,(hl)
            or a
            ret z
            call draw_glyph
            inc hl
            ld a,b
            add a,4
            ld b,a
            jr hof_text

; efface un rectangle : B = x, C = y, D = largeur (octets), E = hauteur (lignes)
hof_clr:    call scr_addr
            ld a,d
.w          ld (hl),0
            inc hl
            dec a
            jr nz,.w
            inc c
            dec e
            jr nz,hof_clr
            ret

; pose (OU) un dessin : IX = octets, B = x, C = y, D = largeur, E = hauteur
hof_or:     call scr_addr
            ld a,d
.w          ex af,af'
            ld a,(ix+0)
            or (hl)
            ld (hl),a
            inc hl
            inc ix
            ex af,af'
            dec a
            jr nz,.w
            inc c
            dec e
            jr nz,hof_or
            ret

;------------------------------------------------------------------------------
; une ligne du classement : A = rang.  Nom (jaune, blanc pour la nouvelle entree) puis score (rouge, sans zeros de tete)
;------------------------------------------------------------------------------
hof_line:   ld (hv_i),a
            ld e,a
            ld a,(hv_ry0)
            ld c,a
            ld a,(hv_pit)
            ld d,a
            inc e
            jr .y1
.y0         ld a,c
            add a,d
            ld c,a
.y1         dec e
            jr nz,.y0                   ; y = ry0 + pas x rang
            ld a,(hv_i)
            call h_ent
            ld b,RK_X
            ld a,(HOF_MODE)
            cp 2
            jr nz,.nm
            ld b,19                     ; code d'acces : centre
.nm         ld a,(hv_rank)
            ld d,a
            ld a,(hv_i)
            cp d
            ld a,HYEL
            jr nz,.p
            ld a,WHITE
.p          ld (hv_pen),a
            ld d,10
.n          ld a,(hl)
            call draw_glyph
            inc hl
            ld a,b
            add a,4
            ld b,a
            dec d
            jr nz,.n
            ld a,(HOF_MODE)
            cp 2
            ret z                       ; code d'acces : pas de score
            ld a,HRED
            ld (hv_pen),a
            ld e,0                      ; zeros de tete (4 au plus)
            push hl
.cz         ld a,e
            cp 4
            jr z,.cd
            ld a,(hl)
            or a
            jr nz,.cd
            inc hl
            inc e
            jr .cz
.cd         pop hl
            ld d,0
.sp         ld a,d
            cp e
            ld a,(hl)
            jr nc,.dg
            ld a,' '
            jr .pr
.dg         add a,'0'
.pr         call draw_glyph
            inc hl
            ld a,b
            add a,4
            ld b,a
            inc d
            ld a,d
            cp 5
            jr nz,.sp
            ret

hof_ranks:  xor a
.l          push af
            call hof_line
            pop af
            inc a
            cp 7
            jr nz,.l
            ret

;------------------------------------------------------------------------------
; nouveau score : rang, decalage des entrees suivantes, nouvelle entree (nom : 10 points)
;------------------------------------------------------------------------------
hof_insert: ld hl,score+1               ; les 4 chiffres du score puis le zero fixe
            ld de,hv_p
            ld bc,4
            ldir
            xor a
            ld (de),a
            xor a
.f          ld (hv_rank),a
            call h_ent
            ld de,10
            add hl,de
            call hof_gt
            jr c,.found
            ld a,(hv_rank)
            inc a
            cp 7
            jr nz,.f
            ld a,6                      ; (ne devrait pas arriver : le game over a verifie que le score entre)
            ld (hv_rank),a
.found      ld a,6
.s          ld (hv_i),a
            ld hl,hv_rank
            cp (hl)
            jr z,.ins
            call h_ent
            ex de,hl                    ; DE = entree i
            ld a,(hv_i)
            dec a
            call h_ent                  ; HL = entree i-1
            ld bc,15
            ldir
            ld a,(hv_i)
            dec a
            jr .s
.ins        ld a,(hv_rank)
            call h_ent
            ld b,10
            ld a,'.'
.n          ld (hl),a
            inc hl
            djnz .n
            ex de,hl
            ld hl,hv_p
            ld bc,5
            ldir
            ret

; HL = 5 chiffres d'une entree : C si le nouveau score (hv_p) est plus grand
hof_gt:     ld de,hv_p
            ld b,5
.c          ld a,(de)
            cp (hl)
            jr c,.no
            jr nz,.yes
            inc hl
            inc de
            djnz .c
.no         and a
            ret
.yes        scf
            ret

;------------------------------------------------------------------------------
; SAISIE DU NOM
;------------------------------------------------------------------------------
; case A (0..27) -> B = x, C = y, D = largeur (7 ou 14 octets), E = rangee
h_geom:     ld d,7
            cp 11
            jr nc,.n1
            ld e,0
            ld c,GY0
            jr .cx
.n1         cp 22
            jr nc,.n2
            sub 11
            ld e,1
            ld c,GY1
            jr .cx
.n2         ld c,GY2
            ld e,2
            cp 26
            jr c,.l2
            jr z,.arr
            ld d,14                     ; OK : 2 cases de large
            ld a,5
            jr .cx
.arr        ld a,4
            jr .cx
.l2         sub 22
.cx         ld b,a
            add a,a
            add a,a
            add a,a
            sub b
            ld b,a                      ; x = 7 x colonne
            ret

; dessine la case A : fond noir, cercle rouge si c'est la case (hv_sel), lettre jaune (qui pivote si c'est (hv_spi))
draw_cell:  push bc
            push de
            push hl
            push ix
            ld (hv_ci),a
            call h_geom
            push bc
            push de
            dec c
            ld e,12
            call hof_clr
            pop de
            pop bc
.nc          ld a,HYEL
            ld (hv_pen),a
            ld a,(hv_ci)
            ld l,a
            ld a,(hv_spi)
            cp l
            ld a,0
            jr nz,.g
            ld a,(hv_sg)
.g          ld (hv_gm),a
            ld a,(hv_ci)
            cp 27
            jr z,.ok
            cp 26
            jr nz,.l
            ld a,'<'
            jr .pl
.l          add a,'A'
.pl         inc b
            inc b
            call draw_glyph
            jr .end
.ok         inc b
            inc b
            inc b
            ld a,'O'
            call draw_glyph
            ld a,b
            add a,4
            ld b,a
            ld a,'K'
            call draw_glyph
.end        xor a
            ld (hv_gm),a
            ld a,(hv_ci)
            ld l,a
            ld a,(hv_sel)
            cp l
            jr nz,.nc2
            ld a,l
            call h_geom                 ; (B a bouge pendant le dessin de la lettre)
            push bc
            push de
            dec c
            ld a,d
            cp 14
            jr z,.w9
            inc b
            ld ix,circ5
            ld d,5
            jr .oc
.w9         inc b
            inc b
            ld ix,circ9
            ld d,9
.oc         ld e,12
            call hof_or
            pop de
            pop bc
.nc2        pop ix
            pop hl
            pop de
            pop bc
            ret

; case visee d'apres la position de Papi et la rangee voulue -> A
hof_cur:    ld a,(hv_px)
            add a,3                     ; centre de Papi
            ld c,0
.d          cp 7
            jr c,.k
            sub 7
            inc c
            jr .d
.k          ld a,c
            cp 11
            jr c,.k2
            ld c,10
.k2         ld a,(hv_row)
            cp 2
            jr nz,.rr
            ld a,c
            cp 7
            ld a,2
            jr c,.rr                    ; colonnes 0..6 : la 3e rangee existe
            dec a
.rr         or a
            jr z,.r0
            dec a
            jr z,.r1
            ld a,c
            cp 4
            jr c,.a22
            jr z,.i26
            ld a,27
            ret
.i26        ld a,26
            ret
.a22        add a,22
            ret
.r1         ld a,c
            add a,11
            ret
.r0         ld a,c
            ret

; Papi en (hv_px, PAPI_Y), image 12 + hv_an (dos tourne) ; efface l'ancienne position
hof_papi:   ld a,(hv_ox)
            ld b,a
            ld c,PAPI_Y
            ld de,6*256+12
            call hof_clr
            ld a,(hv_px)
            ld (hv_ox),a
            ld b,a
            ld c,PAPI_Y
            ld a,(hv_an)
            add a,12                    ; images 12 a 15 : Papi dos tourne (direction haut), quel que soit le sens de la marche
            ld hl,papi_frames
            call frame_ptr
            ld a,12
            ld (hv_cnt),a
            xor a
            ld (hv_odd),a
.l          push hl
            call scr_addr
            ex de,hl
            pop hl
            ld a,(hv_odd)
            or a
            jr nz,.o
            repeat 6
              ld a,(de)
              and (hl)
              inc hl
              or (hl)
              inc hl
              ld (de),a
              inc de
            rend
            jr .nx
.o          ld a,e                      ; lignes impaires : de droite a gauche
            add a,5
            ld e,a
            jr nc,.o2
            inc d
.o2         repeat 6
              ld a,(de)
              and (hl)
              inc hl
              or (hl)
              inc hl
              ld (de),a
              dec de
            rend
.nx         ld a,(hv_odd)
            xor 1
            ld (hv_odd),a
            inc c
            ld a,(hv_cnt)
            dec a
            ld (hv_cnt),a
            jr nz,.l
            ret

; balle : 4 lignes jaunes en (hv_bx, hv_by), dessinees / effacees par OU exclusif
h_bul:      ld a,(hv_bx)
            ld b,a
            ld a,(hv_by)
            ld c,a
            ld d,4
.l          call scr_addr
            ld a,(hl)
            xor HYEL
            ld (hl),a
            inc c
            dec d
            jr nz,.l
            ret

hof_entry:  ld a,(HOF_MODE)
            cp 2
            call nz,hof_insert
            ld a,33
            ld (hv_px),a
            ld (hv_ox),a
            ld a,1
            ld (hv_row),a
            ld a,255
            ld (hv_sel),a
            ld (hv_spi),a
            ld a,#1F
            ld (hv_pj),a                ; tir deja enfonce : pas de balle avant qu'il soit relache
            call hof_banner
            ld a,(HOF_MODE)
            cp 2
            jr z,.code
            ld a,RK_Y0
            ld (hv_ry0),a
            ld a,12
            ld (hv_pit),a
            call hof_ranks
            ld a,HYEL
            ld (hv_pen),a
            ld hl,txt_enter
            ld b,9
            ld c,TXT_Y
            call hof_text
            jr .grid
.code       call code_setup
.grid       xor a
.g          ld (hv_i),a
            call draw_cell
            ld a,(hv_i)
            inc a
            cp 28
            jr nz,.g
            call hof_papi
.loop       call hof_vs
            call sound_update
            call keyscan
            ld a,(joy)
            ld e,a
            ld a,(hv_pj)
            cpl
            and e
            ld (hv_ed),a                ; touches enfoncees depuis l'image precedente
            ld a,e
            ld (hv_pj),a
            ld (hv_jy),a
            ; --- rangee ---
            ld a,(hv_ed)
            ld e,a
            bit 0,e
            jr z,.nu
            ld a,(hv_row)
            or a
            jr z,.nu
            dec a
            ld (hv_row),a
.nu         bit 1,e
            jr z,.nd
            ld a,(hv_row)
            cp 2
            jr nc,.nd
            inc a
            ld (hv_row),a
.nd         ; --- Papi marche ---
            ld a,(hv_jy)
            ld e,a
            ld a,(hv_px)
            ld d,a
            bit 2,e
            jr z,.nl
            or a
            jr z,.nl
            dec a
.nl         bit 3,e
            jr z,.nr
            cp 72
            jr nc,.nr
            inc a
.nr         ld (hv_px),a
            cp d
            jr z,.nm
            ld hl,hv_at
            inc (hl)
            ld a,(hl)
            cp 4
            jr c,.dr
            ld (hl),0
            ld hl,hv_an
            ld a,(hl)
            inc a
            and 3
            ld (hl),a
.dr         call hof_papi
.nm         ; --- case entouree ---
            call hof_cur
            ld hl,hv_sel
            cp (hl)
            jr z,.same
            ld c,a
            ld a,(hl)
            ld (hv_old),a
            ld (hl),c
            ld a,(hv_old)
            cp 255
            call nz,draw_cell
            ld a,(hv_sel)
            call draw_cell
.same       ; --- tir ---
            ld a,(hv_ed)
            bit 4,a
            jr z,.nf
            ld a,(hv_bon)
            or a
            jr nz,.nf
            ld a,(hv_sel)
            ld (hv_bit),a
            call h_geom
            ld a,c
            add a,10
            ld (hv_bty),a
            ld a,(hv_px)
            add a,3
            ld (hv_bx),a
            ld a,PAPI_Y-5
            ld (hv_by),a
            ld a,1
            ld (hv_bon),a
            call h_bul
            ld a,1
            call sfx
.nf         ; --- balle ---
            ld a,(hv_bon)
            or a
            jr z,.nb
            call h_bul
            ld a,(hv_by)
            sub 5
            ld (hv_by),a
            ld hl,hv_bty
            cp (hl)
            jr c,.hit
            jr z,.hit
            call h_bul
            jr .nb
.hit        xor a
            ld (hv_bon),a
            call h_apply
.nb         ; --- pivotement ---
            ld a,(hv_spt)
            or a
            jr z,.nsp
            dec a
            ld (hv_spt),a
            and 1
            jr nz,.nsp
            ld a,(hv_spt)
            rrca
            and 3
            ld e,a
            ld d,0
            ld hl,h_seq
            add hl,de
            ld a,(hl)
            ld (hv_sg),a
            ld a,(hv_spi)
            call draw_cell
            ld a,(hv_spt)
            or a
            jr nz,.nsp
            ld a,255
            ld (hv_spi),a
.nsp        ld a,(hv_done)
            or a
            jp z,.loop
            ld a,(HOF_MODE)
            cp 2
            jr nz,.nm2
            call code_check             ; code d'acces : bon (NZ : fanfare puis menu) ou mauvais (message WRONG CODE, puis retour au menu principal)
            jr nz,.end
            ret
.nm2            ; --- fin : un nom vide devient PAPI ; fanfare, puis retour au menu ---
            ld a,(hv_len)
            or a
            jr nz,.end
            ld a,(hv_rank)
            call h_ent
            ld (hl),'P'
            inc hl
            ld (hl),'A'
            inc hl
            ld (hl),'P'
            inc hl
            ld (hl),'I'
            ld a,(hv_rank)
            call hof_line
.end        ld a,10
            call sfx
            ld a,130
            ld (hv_cnt),a
.w          call hof_vs
            call sound_update
            ld hl,hv_cnt
            dec (hl)
            jr nz,.w
            ret

; la balle touche la case hv_bit : elle pivote, et son effet (lettre / effacer / valider)
h_apply:    ld a,(hv_spi)
            cp 255
            jr z,.f
            xor a
            ld (hv_sg),a
            ld a,(hv_spi)
            call draw_cell              ; l'ancienne case qui pivait redevient normale
.f          ld a,(hv_bit)
            ld (hv_spi),a
            ld a,SPIN_N
            ld (hv_spt),a
            ld a,7
            call sfx
            ld a,(hv_bit)
            cp 27
            jr z,.ok
            cp 26
            jr z,.back
            ld a,(hv_len)               ; une lettre
            cp 10
            ret nc
            ld e,a
            ld d,0
            ld a,(hv_rank)
            call h_ent
            add hl,de
            ld a,(hv_bit)
            add a,'A'
            ld (hl),a
            ld hl,hv_len
            inc (hl)
            jr .redraw
.back       ld a,(hv_len)               ; effacer
            or a
            ret z
            dec a
            ld (hv_len),a
            ld e,a
            ld d,0
            ld a,(hv_rank)
            call h_ent
            add hl,de
            ld (hl),'.'
            jr .redraw
.ok         ld a,1
            ld (hv_done),a
            ret
.redraw     ld a,(hv_rank)
            jp hof_line

h_seq:      db 0,1,2,1

;------------------------------------------------------------------------------
; ACCESS CODE : saisie d'un code (meme ecran que la saisie du nom), tampon code_buf (10 caracteres, '.' = vide)
;------------------------------------------------------------------------------
code_buf    equ HV+48
CODE_Y      equ 48
MSG_Y       equ 76
code_setup: ld hl,code_buf
            ld de,code_buf+1
            ld bc,9
            ld (hl),'.'
            ldir
            ld a,CODE_Y
            ld (hv_ry0),a
            xor a
            ld (hv_rank),a
            call hof_line               ; le code (blanc)
            ld a,HYEL
            ld (hv_pen),a
            ld hl,txt_code
            ld b,5
            ld c,TXT_Y
            jp hof_text

; compare le code saisi (hv_len lettres) a access_tab.  Bon : acc_zone = zone, message ACCESS ZONE x GRANTED !, retour NZ.
; Mauvais : message WRONG CODE !, le code est efface, retour Z
code_check: ld hl,access_tab
.e          ld c,(hl)                   ; numero de zone (0 : fin de la table)
            ld a,c
            or a
            jr z,.bad
            inc hl
            ld de,code_buf
.c          ld a,(hl)
            or a
            jr z,.fin
            ld b,a
            ld a,(de)
            cp b
            jr nz,.skip
            inc hl
            inc de
            jr .c
.fin        inc hl                      ; le code finit : le tampon doit finir ici aussi
            ld a,(de)
            cp '.'
            jr z,.ok
            jr .e
.skip       ld a,(hl)                   ; passe a l'entree suivante
            inc hl
            or a
            jr nz,.skip
            jr .e
.ok         ld a,c
            add a,'0'
            ld (txt_acc+12),a
            sub '1'
            ld (acc_zone),a
            ld a,HYEL
            ld (hv_pen),a
            ld hl,txt_acc
            ld b,13
            ld c,MSG_Y
            call hof_text
            ld hl,txt_gr
            ld b,21
            ld c,MSG_Y+14
            call hof_text
            or 1                        ; NZ
            ret
.bad        ld a,HRED
            ld (hv_pen),a
            ld hl,txt_bad
            ld b,15
            ld c,MSG_Y
            call hof_text
            ld a,3
            call sfx
            ld a,70
            ld (hv_cnt),a
.w          call hof_vs
            call sound_update
            ld hl,hv_cnt
            dec (hl)
            jr nz,.w
            ld b,15
            ld c,MSG_Y
            ld d,48
            ld e,10
            call hof_clr
            ld hl,code_buf              ; code efface
            ld de,code_buf+1
            ld bc,9
            ld (hl),'.'
            ldir
            xor a
            ld (hv_rank),a
            call hof_line
            xor a                       ; Z
            ret
txt_code:   db 'ENTER ACCESS CODE',0
txt_acc:    db 'ACCESS ZONE 2',0
txt_gr:     db 'GRANTED !',0
txt_bad:    db 'WRONG CODE !',0
            include 'access.inc'
txt_enter:  db 'ENTER YOUR NAME',0
txt_hof:    db 'HALL OF FAME',0

;------------------------------------------------------------------------------
; DEFILEMENT : le classement monte vite sous le bandeau, s'arrete juste dessous, 5 s, retour au menu
;------------------------------------------------------------------------------
hof_scroll: ld a,255
            ld (hv_rank),a
            call hof_banner
            ld a,RK_Y0+14
            ld (hv_ry0),a
            ld a,14
            ld (hv_pit),a
            call hof_ranks
            ld a,WHITE
            ld (hv_pen),a
            ld hl,txt_hof
            ld b,15
            ld c,RK_Y0
            call hof_text
            ld hl,CANVAS                ; copie des 112 lignes (60 octets) dans le tampon...
            ld (hv_cp),hl
            ld c,RK_Y0
            ld a,112
            ld (hv_cnt),a
.cp         ld b,RK_X
            call scr_addr
            ld de,(hv_cp)
            push bc
            ld bc,60
            ldir
            pop bc
            ld (hv_cp),de
            inc c
            ld hl,hv_cnt
            dec (hl)
            jr nz,.cp
            ld c,BAN_Y+27               ; ...puis le dessous du bandeau est efface
.cl         ld b,RK_X
            call scr_addr
            ld d,h
            ld e,l
            inc de
            ld (hl),0
            push bc
            ld bc,59
            ldir
            pop bc
            inc c
            ld a,c
            cp 192
            jr nz,.cl
            ld a,192
            ld (hv_y),a
.sl         call hof_vs
            call h_blit
            ld a,(hv_y)
            cp RK_Y0
            jr z,.wait
            sub 4
            cp RK_Y0
            jr nc,.k
            ld a,RK_Y0
.k          ld (hv_y),a
            jr .sl
.wait       ld a,250                    ; 5 secondes (tir : on passe)
            ld (hv_cnt),a
.w5         call hof_vs
            call keyscan
            ld a,(joy)
            bit 4,a
            ret nz
            ld hl,hv_cnt
            dec (hl)
            jr nz,.w5
            ret

; le tampon est pose en y = hv_y (88 lignes, puis 4 lignes noires qui effacent la trace de la montee), coupe en bas de l'ecran
h_blit:     ld hl,CANVAS
            ld (hv_cp),hl
            ld a,(hv_y)
            ld c,a
            xor a
            ld (hv_r),a
.r          ld a,c
            cp 192
            ret nc
            ld b,RK_X
            call scr_addr
            ex de,hl
            ld hl,(hv_cp)
            push bc
            ld a,(hv_r)
            cp 112
            jr nc,.blk
            ld bc,60
            ldir
            ld (hv_cp),hl
            jr .nx
.blk        ex de,hl
            ld d,h
            ld e,l
            inc de
            ld (hl),0
            ld bc,59
            ldir
.nx         pop bc
            inc c
            ld hl,hv_r
            inc (hl)
            ld a,(hl)
            cp 116
            jr c,.r
            ret
