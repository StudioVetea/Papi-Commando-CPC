;==============================================================================
;  GAME OVER : overlay lu en GO_LOAD quand le message GAME OVER est affiche (la scene reste figee dessous), puis appele.
;  Il joue le jingle (assets/MusiqueGameOver_AY.vgm), puis rend la main : le jeu repart sur le menu principal.
;  Meme format que le jingle de depart de niveau : par image, un masque de 2 octets puis les valeurs des registres modifies.
;==============================================================================
GV          equ #7A00
go_src      equ GV              ; (2)
go_cnt        equ GV+2            ; (2) images restantes
go_r        equ GV+4

            jp go_run                  ; GO_LOAD : point d'entree
go_run:     ld a,(acc_zone)             ; fin de la demo (acc_zone bit 7, voir menu.asm) : pas de jingle, retour direct au menu
            rlca
            ret c
            ld hl,go_data
            ld (go_src),hl
            ld hl,GO_FRAMES
            ld (go_cnt),hl
.fr         call .vs
            call go_update
            ld hl,(go_cnt)
            ld a,h
            or l
            jr nz,.fr
            ld d,10                     ; un peu de silence apres la derniere image
.tl         call .vs
            dec d
            jr nz,.tl
            ld c,#3F                    ; silence
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
            call ay_write
            ld a,(score+1)              ; Hall of Fame : score minimum en jeu (HOF_MIN points) atteint ?  (chiffres milliers, centaines, dizaines)
            or a
            jr nz,.hin
            ld hl,score+2
            ld a,(hl)
            cp HM_K
            ret c
            jr nz,.hin
            inc hl
            ld a,(hl)
            cp HM_H
            ret c
            jr nz,.hin
            inc hl
            ld a,(hl)
            cp HM_T
            ret c
.hin        ld a,1                      ; oui : saisie du nom (l'overlay HOF rend la main au menu principal)
            ld (HOF_MODE),a
            ld hl,menu_enter
            push hl
            jp ovl_hof

.vs         ld b,#F5
.va         in a,(c)
            rra
            jr c,.va
.vb         in a,(c)
            rra
            jr nc,.vb
            ret

go_update:  ld hl,(go_cnt)
            dec hl
            ld (go_cnt),hl
            ld hl,(go_src)
            ld e,(hl)
            inc hl
            ld d,(hl)
            inc hl
            xor a
            ld (go_r),a
.lp         srl d
            rr e
            jr nc,.nx
            ld c,(hl)
            inc hl
            ld a,(go_r)
            cp 7
            jr nz,.w
            ld a,c
            and #3F                     ; melangeur : bits 6 et 7 a 0
            ld c,a
            ld a,7
.w          push hl
            push de
            call ay_write
            pop de
            pop hl
.nx         ld a,(go_r)
            inc a
            ld (go_r),a
            cp 13
            jr nz,.lp
            ld (go_src),hl
            ret

            include 'jingle_gameover.asm'
