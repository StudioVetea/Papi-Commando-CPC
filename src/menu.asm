;==============================================================================
;  MENU PRINCIPAL : overlay lu sur la disquette (MENU_N secteurs) en MENU_LOAD par menu_enter, puis appele.
;  Il peut utiliser les routines du programme (scr_addr, print_big, sfx, sound_update, keyscan...) mais
;  son code et ses donnees disparaissent des que la 1re zone se charge.  Appel : di, pile en STACK.
;
;  Deroulement : 1) le titre monte du bas de l'ecran, 2) 16 explosions tout autour du titre (avec bruitage),
;                3) "START GAME !" jaune clignotant au milieu et bandeau defilant de 8 x 8 pixels tout en bas ;
;                   tir : la partie commence.
;==============================================================================
MUV         equ #4700           ; variables du lecteur de musique (sous l'overlay des missions, libre pendant le menu)
MU_RING     equ #4800           ; anneau de 2 Ko (alignee) : octets deja decompresses de la musique
MV          equ #7A00           ; variables de l'overlay
m_y         equ MV              ; ligne du titre pendant la montee
m_left      equ MV+1            ; explosions qui restent a lancer
m_cool      equ MV+2            ; images avant la prochaine
m_pos       equ MV+3            ; prochaine position
m_tail      equ MV+4
m_bl        equ MV+5            ; phase du clignotement
m_ph        equ MV+6            ; une image sur deux fait defiler le texte
m_sh        equ MV+7            ; decalage du pixel a lire dans le glyphe : 6, 4, 2, 0
m_ptr       equ MV+8            ; (2) caractere du texte defilant
m_gp        equ MV+10           ; (2) glyphe de ce caractere
m_gr        equ MV+12           ; (2) ligne du glyphe en cours
ex_tab      equ MV+16           ; NSLOT x (temps restant, x, y) : explosions en cours
m_ly        equ MV+36
m_bx        equ MV+37
m_by        equ MV+38
m_s         equ MV+39
m_odd       equ MV+40
m_pc        equ MV+41
m_t0        equ MV+42
m_t1        equ MV+43
m_t2        equ MV+44
m_ip        equ MV+45           ; (2)
m_sel       equ MV+88           ; option du menu : 0 = START GAME !, 1 = ACCESS CODE
m_jk        equ MV+89           ; haut / bas a l'image precedente
m_ey        equ MV+90
m_z         equ MV+91           ; zone choisie avec la touche + (beta test) : 0 = zone 1
m_zk        equ MV+92           ; etat de la touche + a l'image precedente
xbuf        equ MV+48           ; 12 paires (masque, donnee) de la ligne agrandie : 24 octets
TAB_L       equ #78             ; tables d agrandissement (#7800 et #7900)
NSLOT       equ 5
a_src       equ MV+56           ; (2) poursuite : image en cours de dessin
a_col       equ MV+58
a_y         equ MV+59
a_kmin      equ MV+60
a_n         equ MV+61
m_sc        equ MV+62           ; scene de poursuite en cours
m_t         equ MV+63           ; avancee de la scene (octets)
m_an        equ MV+64           ; animation des pas
c_i         equ MV+65
c_x         equ MV+66
lbuf        equ MV+80           ; 8 colonnes : [0] et [7] restent noires (elles effacent la trace d'un pas), [1..6] = l'image
CHASE_Y     equ 14              ; ligne des sprites de la poursuite (juste au-dessus du titre)
MV_LEN      equ 96

            jp menu_run                 ; point d'entree : MENU_LOAD
            include 'menu_gfx.asm'      ; le titre
menu_run:
            di                          ; (la pile est celle de menu_enter : l'adresse de retour y est)
            call hof_init               ; classement : cree au 1er passage
            ld hl,vars                  ; son remis a zero
            ld de,vars+1
            ld bc,vars_end-vars-1
            ld (hl),0
            ldir
            ld hl,MV
            ld de,MV+1
            ld bc,MV_LEN-1
            ld (hl),0
            ldir
            ld a,(acc_zone)             ; zone choisie par un code d'acces (la touche + du menu de test part de la)
            ld (m_z),a
            call blackout
            call mk_tab
            ld hl,palette_hw            ; palette du jeu (les explosions sont celles du jeu)
            call m_pal
            ; --- 1) le titre monte du bas de l'ecran : 4 lignes par image ---
            ld a,190
            ld (m_y),a
.up         call vsync
            ld a,(m_y)
            call blit_title
            ld a,(m_y)
            sub 4
            ld (m_y),a
            cp TITLE_Y
            jr nc,.up
            ; --- 2) explosions tout autour ---
            ld a,18                     ; 18 explosions (le titre ne doit pas rester trop longtemps a exploser)
            ld (m_left),a
.ex         call vsync
            call sound_update
            call spawn
            call expl_step
            ld a,(m_left)
            or a
            jr nz,.ex
            ld a,14                     ; la derniere explosion s'acheve
            ld (m_tail),a
.tl         call vsync
            call sound_update
            call expl_step
            ld hl,m_tail
            dec (hl)
            jr nz,.tl
            ; --- 3) START GAME ! clignotant et bandeau defilant ---
            ld hl,txt_scroll
            ld (m_ptr),hl
            ld a,' '
            call set_glyph
            ld a,6
            ld (m_sh),a
            call mu_init                ; la musique demarre ici : apres le titre et les explosions
            ld a,WHITE                  ; 2e option, fixe tant qu'elle n'est pas choisie
            call acc_txt
.ml         call vsync
            ld hl,(mu_n)                ; fin du morceau : avant qu'il reboucle, ecran du Hall of Fame (l'overlay rend la main a menu_enter : le cycle recommence)
            ld a,h
            or l
            jp z,hof_go
            call mu_update              ; (remplace sound_update : le melangeur du AY est a la musique)
            call keyscan
            ld a,(joy)                  ; haut / bas : change d'option
            and 3
            ld b,a
            ld a,(m_jk)
            ld c,a
            ld a,b
            ld (m_jk),a
            xor c
            and b
            jr z,.nj
            xor a
            call sel_txt                ; efface l'option choisie, bascule, l'autre s'affiche en blanc, la nouvelle clignote
            ld a,(m_sel)
            xor 1
            ld (m_sel),a
            ld a,WHITE
            call unsel_txt
            xor a
            ld (m_bl),a
.nj         ld a,(m_ph)                 ; une image sur deux : le texte defile, l'autre : la poursuite avance
            xor 1
            ld (m_ph),a
            jr z,.sc
            call chase_step
            jr .nsc
.sc         call scroll_step
.nsc
            ld a,(m_bl)
            or a
            jr nz,.nb
            ld a,#CF                    ; allume : jaune vif
            call sel_txt
            jr .nx
.nb         cp 28
            jr nz,.nx
            xor a                       ; eteint
            call sel_txt
.nx         ld a,(m_bl)
            inc a
            cp 40
            jr c,.ok
            xor a
.ok         ld (m_bl),a
            ifdef CHEATS                ; version de TEST seulement (build.sh debug) : codes secrets du menu
            ; touche + (beta test) : zone suivante, son numero s'affiche sous START GAME ! ; la partie commence dans cette zone
            ld a,(keymap+3)             ; ligne 3 bit 4 = touche ; +  (0 = appuyee)
            cpl
            and 16
            ld b,a
            ld a,(m_zk)
            ld c,a
            ld a,b
            ld (m_zk),a
            or a
            jr z,.nz
            cp c
            jr z,.nz                    ; touche deja tenue
            ld a,(m_z)
            inc a
            cp MENU_NZG
            jr c,.z1
            xor a
.z1         ld (m_z),a
            add a,'1'
            ld (txt_zone+5),a
            ld a,WHITE
            ld (big_on),a
            ld hl,txt_zone
            ld bc,27*256+114
            call print_big
.nz         ; code secret (beta test) : touches 1 a 6 = lancer directement la mission correspondante
            ld a,(keymap+8)             ; matrice du clavier : 1, 2 = ligne 8 bits 0, 1 ; 3, 4 = ligne 7 bits 1, 0 ; 5 = ligne 6 bit 1 (0 = appuyee)
            ld b,1
            bit 0,a
            jr z,.kq
            inc b
            bit 1,a
            jr z,.kq
            ld a,(keymap+7)
            inc b
            bit 1,a
            jr z,.kq
            inc b
            bit 0,a
            jr z,.kq
            ld a,(keymap+6)
            inc b
            bit 1,a
            jr z,.kq
            inc b
            bit 0,a                     ; touche 6 : mission finale
            jr z,.kq
            ld a,(joy)
            bit 4,a
            jp z,.ml
            ld a,(m_sel)
            or a
            jp nz,acc_go
            ld b,1                      ; tir : 1re mission de la zone choisie
.kq         ld a,(m_z)
            ld e,a
            ld d,0
            ld hl,menu_zstart
            add hl,de
            ld a,(hl)
            add a,b
            dec a
            ld (zone_cur),a
            jp mu_stop
            else                        ; version de diffusion : tir = on commence a la mission 1 de la zone 1
            ld a,(joy)
            bit 4,a
            jp z,.ml
            ld a,(m_sel)
            or a
            jp nz,acc_go
            ld a,(acc_zone)             ; la partie commence a la zone choisie par un code d'acces (zone 1 par defaut)
            ld e,a
            ld d,0
            ld hl,menu_zstart
            add hl,de
            ld a,(hl)
            ld (zone_cur),a
            jp mu_stop
            endif

acc_go:     call mu_stop                ; option ACCESS CODE : l'ecran de saisie du Hall of Fame, en mode 2
            ld a,2
            jr hof_go2
hof_go:     call mu_stop
            xor a
hof_go2:    ld (HOF_MODE),a
            ld hl,menu_enter
            push hl
            jp ovl_hof

; classement (Hall of Fame) : au 1er passage, les 7 entrees initiales sont recopiees dans les 16 octets libres de la page A
hof_init:   ld a,(HOF_MAG1)
            cp #A5
            jr nz,.go
            ld a,(HOF_MAG2)
            cp #5A
            ret z
.go         ld hl,hof_init_data
            ld de,HOF_E0
            ld b,7
.l          push bc
            push de
            ld bc,15
            ldir
            pop de
            pop bc
            ld a,d
            add a,8
            ld d,a
            djnz .l
            ld a,#A5
            ld (HOF_MAG1),a
            ld a,#5A
            ld (HOF_MAG2),a
            ret

; option choisie (m_sel) : A = couleur (0 : efface) ; l'autre : unsel_txt
sel_txt:    ld d,a
            ld a,(m_sel)
            or a
            ld a,d
            jr nz,acc_txt
            jr start_txt
unsel_txt:  ld d,a
            ld a,(m_sel)
            or a
            ld a,d
            jr z,acc_txt
start_txt:  ld hl,txt_start
            ld bc,15*256+96
            jr item_txt
acc_txt:    ld hl,txt_access
            ld bc,17*256+118
item_txt:   or a
            jr nz,.on
            ld a,c                      ; eteint : 10 lignes de 48 octets effacees d'un coup
            add a,10
            ld (m_ey),a
.e          ld b,15
            call scr_addr
            ld d,h
            ld e,l
            inc de
            ld (hl),0
            push bc
            ld bc,47
            ldir
            pop bc
            inc c
            ld a,(m_ey)
            cp c
            jr nz,.e
            ret
.on         ld (big_on),a
            jp print_big

; attend le debut du prochain retour de balayage
vsync:      ld b,#F5
.a          in a,(c)
            rra
            jr c,.a
.b          in a,(c)
            rra
            jr nc,.b
            ret

m_pal:      xor a                       ; HL = 17 octets (16 encres + bordure)
.p          ld b,#7F
            out (c),a
            ld e,(hl)
            out (c),e
            inc hl
            inc a
            cp 17
            jr nz,.p
            ret

;------------------------------------------------------------------------------
; le titre : TITLE_H lignes de 78 octets en y = A, suivies de 4 lignes noires (elles effacent la trace de la montee)
;------------------------------------------------------------------------------
blit_title:
            ld c,a
            ld hl,title_data
            ld a,TITLE_H
.r          push af
            call row_copy
            inc c
            pop af
            dec a
            jr nz,.r
            ld a,4
.z          push af
            ld a,c
            cp 192
            jr nc,.zn
            ld b,0
            call scr_addr
            ld d,h
            ld e,l
            inc de
            ld (hl),0
            push bc
            ld bc,77
            ldir
            pop bc
.zn         inc c
            pop af
            dec a
            jr nz,.z
            ret

row_copy:   ld a,c                      ; ligne y = C <- 78 octets en HL (HL avance)
            cp 192
            jr c,.ok
            ld de,78
            add hl,de
            ret
.ok         push bc
            ex de,hl
            ld b,0
            call scr_addr
            ex de,hl
            ld bc,78
            ldir
            pop bc
            ret

;------------------------------------------------------------------------------
; explosions : les 4 images du jeu (12 x 12 pixels) agrandies 2 fois (24 x 24), a des endroits fixes autour du titre.
; Une explosion change d'image toutes les 3 images d'ecran : elle efface alors son rectangle (decor = titre ou noir) et se redessine.
;------------------------------------------------------------------------------
spawn:      ld a,(m_left)
            or a
            ret z
            ld a,(m_cool)
            or a
            jr z,.go
            dec a
            ld (m_cool),a
            ret
.go         ld ix,ex_tab
            ld de,3
            ld b,NSLOT
.f          ld a,(ix+0)
            or a
            jr z,.free
            add ix,de
            djnz .f
            ret
.free       ld a,(m_pos)
            and 15
            ld l,a
            ld h,0
            add hl,hl
            ld de,expo_pos
            add hl,de
            ld a,(hl)
            ld (ix+1),a
            inc hl
            ld a,(hl)
            ld (ix+2),a
            ld (ix+0),13
            ld hl,m_pos
            inc (hl)
            ld hl,m_left
            dec (hl)
            ld a,2
            ld (m_cool),a
            ld a,6                      ; bruit d'explosion
            jp sfx

expl_step:  ld ix,ex_tab
            ld a,NSLOT
.s          push af
            ld a,(ix+0)
            or a
            jr z,.next
            dec a
            ld (ix+0),a
            ld b,(ix+1)
            ld c,(ix+2)
            jr z,.last                  ; temps ecoule : on efface
            ld e,a
            ld d,0
            ld hl,fr_idx
            add hl,de
            ld e,(hl)                   ; image 0..3 (255 = pas de changement a cette image)
            inc e
            jr z,.next
            dec e
            push de
            push bc
            call restore_blk
            pop bc
            pop de
            ld a,e
            ld hl,explo_frames
            call frame_ptr
            call draw_expl
            jr .next
.last       call restore_blk
.next       ld de,3
            add ix,de
            pop af
            dec a
            jr nz,.s
            ret

; rectangle de 12 x 24 octets en B = x, C = y : on y remet le titre (ou du noir)
restore_blk:
            ld a,24
            ld (m_ly),a
.l          ld a,c
            sub TITLE_Y
            jr c,.zero
            cp TITLE_H
            jr nc,.zero
            add a,a
            ld e,a
            ld d,0
            ld hl,rowtab
            add hl,de
            ld e,(hl)
            inc hl
            ld d,(hl)
            ld a,b
            add a,e
            ld e,a
            jr nc,.n
            inc d
.n          call scr_addr               ; HL = ecran ; conserve BC, DE
            ex de,hl
            push bc
            ld bc,12
            ldir
            pop bc
            jr .next
.zero       call scr_addr
            ld d,h
            ld e,l
            inc de
            ld (hl),0
            push bc
            ld bc,11
            ldir
            pop bc
.next       inc c
            ld hl,m_ly
            dec (hl)
            jr nz,.l
            ret

; image de 12 x 12 pixels (HL ; paires masque/donnee, lignes impaires de droite a gauche) en B = x, C = y,
; affichee en 24 x 24 : chaque ligne source est agrandie dans xbuf (12 paires), puis posee sur 2 lignes
draw_expl:  ld (m_ip),hl
            ld a,b
            ld (m_bx),a
            ld a,c
            ld (m_by),a
            xor a
            ld (m_s),a
.s          ld hl,(m_ip)
            ld de,xbuf
            ld a,(m_s)
            and 1
            ld (m_odd),a
            ld a,6
            ld (m_pc),a
.p          ld c,(hl)                   ; masque : 2 octets (pixel gauche double, pixel droit double)
            inc hl
            ld b,TAB_L
            ld a,(bc)
            ld (m_t0),a
            inc b
            ld a,(bc)
            ld (m_t1),a
            ld c,(hl)                   ; donnee
            inc hl
            ld b,TAB_L
            ld a,(bc)
            ld (m_t2),a
            inc b
            ld a,(bc)
            ld c,a                      ; C = donnee droite
            ld a,(m_odd)
            or a
            jr nz,.o
            ld a,(m_t0)
            ld (de),a
            inc de
            ld a,(m_t2)
            ld (de),a
            inc de
            ld a,(m_t1)
            ld (de),a
            inc de
            ld a,c
            ld (de),a
            inc de
            jr .w
.o          ld a,(m_t1)
            ld (de),a
            inc de
            ld a,c
            ld (de),a
            inc de
            ld a,(m_t0)
            ld (de),a
            inc de
            ld a,(m_t2)
            ld (de),a
            inc de
.w          ld a,(m_pc)
            dec a
            ld (m_pc),a
            jr nz,.p
            ld (m_ip),hl
            ld a,(m_s)
            add a,a
            ld hl,m_by
            add a,(hl)
            ld c,a
            call .line
            inc c
            call .line
            ld hl,m_s
            inc (hl)
            ld a,(hl)
            cp 12
            jr nz,.s
            ret
.line       ld a,(m_bx)
            ld b,a
            call scr_addr               ; HL = ecran ; conserve BC
            ld de,xbuf
            ld a,(m_odd)
            or a
            jr nz,.lo
            repeat 12
              ld a,(de)
              inc de
              and (hl)
              ld b,a
              ld a,(de)
              inc de
              or b
              ld (hl),a
              inc hl
            rend
            ret
.lo         ld a,l
            add a,11
            ld l,a
            jr nc,.l2
            inc h
.l2         repeat 12
              ld a,(de)
              inc de
              and (hl)
              ld b,a
              ld a,(de)
              inc de
              or b
              ld (hl),a
              dec hl
            rend
            ret

; tables d'agrandissement : TAB_L[v] = pixel gauche de v double sur 2 pixels, TAB_L+256[v] = pixel droit
mk_tab:     ld hl,TAB_L*256
.t          ld a,l
            and #AA
            ld b,a
            rrca
            or b
            ld (hl),a
            inc h
            ld a,l
            and #55
            ld b,a
            rlca
            or b
            ld (hl),a
            dec h
            inc l
            jr nz,.t
            ret

;------------------------------------------------------------------------------
; bandeau defilant : les 8 lignes du bas de la carte glissent d'un octet (2 pixels) vers la gauche ;
; une colonne du glyphe courant (1 octet = 2 pixels) entre a droite
;------------------------------------------------------------------------------
scroll_step:
            ld a,184
            ld (m_ly),a
            ld hl,(m_gp)
            ld (m_gr),hl
.sl         ld a,(m_ly)
            ld c,a
            ld b,0
            call scr_addr
            ld d,h
            ld e,l
            inc hl
            ld bc,77
            ldir                        ; DE = dernier octet de la ligne
            ld a,(m_ly)                 ; glyphe de 5 lignes, pose sur les lignes 186 a 190 de la bande de 8
            sub 186
            ld c,0
            cp 5
            jr nc,.z
            ld hl,(m_gr)
            ld c,(hl)
            inc hl
            ld (m_gr),hl
.z          ld a,(m_sh)
            ld b,a
            ld a,c
            inc b
            dec b
            jr z,.ns
.sf         rrca
            djnz .sf
.ns         and 3
            ld c,a
            ld b,0
            ld hl,pentab
            add hl,bc
            ld a,(hl)
            ld (de),a
            ld hl,m_ly
            inc (hl)
            ld a,(hl)
            cp 192
            jr nz,.sl
            ld a,(m_sh)                 ; colonne suivante ; apres la 4e : caractere suivant
            sub 2                       ; 2 colonnes par caractere (3 pixels + 1 d'espace)
            cp 4
            jr nc,.same
            ld hl,(m_ptr)
            inc hl
            ld a,(hl)
            or a
            jr nz,.nz
            ld hl,txt_scroll
            ld a,(hl)
.nz         ld (m_ptr),hl
            call set_glyph
            ld a,6
.same       ld (m_sh),a
            ret

set_glyph:  cp 'a'                      ; A = caractere -> m_gp = son glyphe (police du bandeau de jeu, 5 octets) ; minuscules lues en majuscules
            jr c,.up
            sub 32
.up         sub 32
            ld l,a
            ld h,0
            ld d,h
            ld e,l
            add hl,hl
            add hl,hl
            add hl,de
            ld de,scroll_font
            add hl,de
            ld (m_gp),hl
            ret

;------------------------------------------------------------------------------
; musique : le flux (mus_data) est un flux "delta" compresse (voir tools/mkmusic.py) ; mu_get rend l'octet suivant du flux decompresse
; (un anneau de 2 Ko garde les derniers octets pour les copies), mu_update lit une image et ecrit dans le AY les registres qui changent
;------------------------------------------------------------------------------
mu_src      equ MUV             ; (2) flux compresse
mu_wr       equ MUV+2           ; (2) ecriture dans l'anneau
mu_rd       equ MUV+4           ; (2) lecture de la copie en cours
mu_lit      equ MUV+6           ; octets litteraux restants
mu_mat      equ MUV+7           ; octets de copie restants
mu_n        equ MUV+8           ; (2) images restantes avant la boucle
mu_r        equ MUV+10          ; registre en cours

mu_init:    ld hl,mus_data
            ld (mu_src),hl
            ld hl,MU_RING
            ld (mu_wr),hl
            ld hl,MUS_FRAMES
            ld (mu_n),hl
            xor a
            ld (mu_lit),a
            ld (mu_mat),a
            ret

mu_get:     ld a,(mu_lit)               ; A = octet suivant ; detruit HL, BC, D
            or a
            jr z,.nl
            dec a
            ld (mu_lit),a
            ld hl,(mu_src)
            ld a,(hl)
            inc hl
            ld (mu_src),hl
            jr .put
.nl         ld a,(mu_mat)
            or a
            jr nz,.mt
            ld hl,(mu_src)              ; nouveau jeton
            ld a,(hl)
            inc hl
            bit 7,a
            jr nz,.nm
            inc a                       ; 0nnnnnnn : n+1 litteraux
            ld (mu_lit),a
            ld (mu_src),hl
            jr mu_get
.nm         ld d,a                      ; 1LLLLooo oooooooo : copie de LLLL+2 octets, distance (ooo.oooooooo)+1
            ld c,(hl)
            inc hl
            ld (mu_src),hl
            and 7
            ld b,a
            inc bc
            ld hl,(mu_wr)
            or a
            sbc hl,bc
            ld a,h
            and 7
            or MU_RING>>8
            ld h,a
            ld (mu_rd),hl
            ld a,d
            rrca
            rrca
            rrca
            and 15
            add a,2
.mt         dec a
            ld (mu_mat),a
            ld hl,(mu_rd)
            ld a,(hl)
            inc hl
            ld d,a
            ld a,h
            and 7
            or MU_RING>>8
            ld h,a
            ld (mu_rd),hl
            ld a,d
.put        ld hl,(mu_wr)
            ld (hl),a
            inc hl
            ld d,a
            ld a,h
            and 7
            or MU_RING>>8
            ld h,a
            ld (mu_wr),hl
            ld a,d
            ret

mu_update:  ld hl,(mu_n)
            ld a,h
            or l
            call z,mu_init              ; fin du morceau : on reboucle (la 1re image reecrit tous les registres)
            ld hl,(mu_n)
            dec hl
            ld (mu_n),hl
            call mu_get
            ld e,a                      ; masque des registres modifies
            push de
            call mu_get
            pop de
            ld d,a
            xor a
            ld (mu_r),a
.lp         srl d
            rr e
            jr nc,.nx
            push de
            call mu_get
            pop de
            ld c,a
            ld a,(mu_r)
            cp 7
            jr nz,.w
            ld a,c
            and #3F                     ; melangeur : les bits 6 et 7 restent a 0 (le clavier se lit par le port A du AY)
            ld c,a
            ld a,7
.w          call ay_write
.nx         ld a,(mu_r)
            inc a
            ld (mu_r),a
            cp 13
            jr nz,.lp
            ret

mu_stop:    ld c,#3F                    ; silence (melangeur coupe, volumes a 0) : le jeu reprend le AY
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

;------------------------------------------------------------------------------
; poursuite au-dessus du titre : Papi (12 x 12) poursuit 2 ou 3 ennemis d'un type (soldat, officier, general), ou est poursuivi par eux,
; d'un bout a l'autre de l'ecran, dans un sens puis dans l'autre.  Les sprites sont poses sur du noir : on ecrit leurs octets de donnees
; tels quels, avec une colonne noire de chaque cote qui efface la trace d'un pas (1 octet toutes les 2 images).
;------------------------------------------------------------------------------
; scene : type d'ennemi (1 soldat, 2 officier, 3 general), Papi en tete (1) ou en queue (0), sens (0 droite, 1 gauche), nombre d'ennemis
scenes:     db 1,0,0,3, 1,1,1,2, 2,0,1,3, 2,1,0,2, 3,0,0,2, 3,1,1,3
NSCENE      equ 6

chase_step: ld a,(m_sc)
            add a,a
            add a,a
            ld e,a
            ld d,0
            ld hl,scenes
            add hl,de
            push hl
            pop ix                      ; IX = scene
            xor a
            ld (c_i),a
.act        ld a,(c_i)                  ; D = 11 x (rang de l'acteur) : les acteurs sont espaces de 11 octets
            ld e,a
            add a,a
            add a,a
            add a,e
            add a,a
            add a,e
            ld d,a
            ld a,(m_t)
            bit 0,(ix+2)
            jr nz,.left
            sub 6                       ; vers la droite : le premier entre a x = -6
            sub d
            jr .xok
.left       ld e,a
            ld a,78                     ; vers la gauche : il entre a x = 78
            sub e
            add a,d
.xok        ld (c_x),a
            ld a,(c_i)                  ; quel acteur ?  Papi : le rang 0 s'il est en tete, sinon le dernier
            ld c,a
            ld a,(ix+1)
            or a
            jr z,.back
            ld a,c
            or a
            jr z,.papi
            jr .enemy
.back       ld a,c
            cp (ix+3)
            jr z,.papi
.enemy      ld a,(ix+0)
            jr .st
.papi       xor a
.st         add a,a
            add a,(ix+2)                ; type x 2 + sens
            add a,a
            add a,a                     ; x 4 images
            ld e,a
            ld a,(m_an)
            rrca
            and 3
            add a,e                     ; numero de l'image 0..31 : x 72 octets
            ld l,a
            ld h,0
            ld d,h
            ld e,l
            add hl,hl
            add hl,hl
            add hl,hl
            add hl,de                   ; x 9
            add hl,hl
            add hl,hl
            add hl,hl                   ; x 72
            ld de,menu_spr
            add hl,de
            ld a,(c_x)
            ld b,a
            ld c,CHASE_Y
            call draw_act
            ld a,(c_i)
            inc a
            ld (c_i),a
            cp (ix+3)
            jr z,.act
            jr c,.act
            ld hl,m_an
            inc (hl)
            ld hl,m_t                   ; fin de scene : tous les acteurs sont sortis (85 + 11 x ennemis)
            inc (hl)
            ld a,(ix+3)
            ld e,a
            add a,a
            add a,a
            add a,e
            add a,a
            add a,e
            add a,85
            cp (hl)
            ret nz
            ld (hl),0
            ld hl,m_sc
            inc (hl)
            ld a,(hl)
            cp NSCENE
            ret nz
            ld (hl),0
            ret

; image de 6 x 12 octets (HL, donnees seules) en B = x (signe : -6 a 90), C = y ; les colonnes hors ecran sont ignorees
draw_act:   ld (a_src),hl
            ld a,b
            or a
            jp m,.neg
            ld d,0                      ; D = 1re colonne visible (0 = colonne noire de gauche)
            jr nz,.p
            inc d
.p          ld a,78
            sub b
            ret c                       ; x > 78 : rien
            cp 7
            jr c,.k
            ld a,7
.k          ld e,a                      ; E = derniere colonne visible
            jr .go
.neg        neg
            inc a
            ld d,a
            ld e,7
.go         ld a,e
            sub d
            ret c                       ; rien de visible
            inc a
            ld (a_n),a
            ld a,d
            ld (a_kmin),a
            add a,b
            dec a
            ld (a_col),a                ; colonne d'ecran de la 1re colonne visible
            ld a,c
            ld (a_y),a
            ld a,12
            ld (m_ly),a
.line       ld hl,(a_src)
            ld de,lbuf+1
            ld bc,6
            ldir
            ld (a_src),hl
            ld a,(a_col)
            ld b,a
            ld a,(a_y)
            ld c,a
            call scr_addr
            ex de,hl
            ld hl,lbuf
            ld a,(a_kmin)
            add a,l
            ld l,a
            ld a,(a_n)
            ld c,a
            ld b,0
            ldir
            ld hl,a_y
            inc (hl)
            ld hl,m_ly
            dec (hl)
            jr nz,.line
            ret


txt_start:  db 'START GAME !',0
txt_access: db 'ACCESS CODE',0
txt_zone:   db 'ZONE 1',0
txt_scroll: db '                    Papi Commando CPC !! A game by Studio Vetea - GFX, SFX, Design by Vetea - Music by Jon Something - Code by Vetea & Claude IA - Version 56 - @[ 2026 Studio Vetea                    ',0   ; @[ = le (c) en 2 caracteres

fr_idx:     db 255,255,255,3,255,255,2,255,255,1,255,255,0       ; temps restant 0..12 -> image (255 : on ne redessine pas)
; positions (x en octets, y en lignes) des explosions de 12 x 24 : tout autour et sur les lettres du titre (lignes 30 a 56) ;
; deux explosions simultanees ne se recouvrent jamais
expo_pos:   db 30,4, 6,52, 62,22, 14,8, 50,52, 0,26, 66,6, 36,50
            db 22,22, 54,6, 8,38, 40,26, 26,54, 66,48, 14,52, 38,8
rowtab:     repeat TITLE_H,r
              dw title_data+(r-1)*78
            rend
            include 'menu_music.asm'    ; genere par tools/mkmusic.py
