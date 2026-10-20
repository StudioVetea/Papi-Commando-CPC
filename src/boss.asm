;==============================================================================
;  BOSS : Caporal Garatonku (sprite 12 x 24 = deux places d'ennemi empilees)
;    place 0 (ixl = 0)  : le CORPS (12 lignes du bas) : il reflechit, marche, tire, comme un soldat (memes routines)
;    place 1 (ixl = 16) : la TETE (12 lignes du haut) : collee 12 lignes au-dessus du corps, elle recopie sa direction, son pas
;                         et son clignotement ; elle reserve ses cases dans la grille (les balles qui passent la reveillent)
;    kills_left = ses points de vie (le quota de la mission) ; hp_thr = seuils de couleur de la barre (vert > jaune > orange > rouge)
;    Rafale de 3 balles toutes les 2 s (son Tir Boss), grenade (celle des officiers) toutes les 2 s ;
;    une balle de Papi lui retire 1 point, sa grenade 3 ; a 0 : explosions pendant 1,3 s, puis ecran de fin de zone.
;==============================================================================
; parametres propres a chaque boss (en-tete de la zone) : rafale de bk_nb balles, bk_dl images entre deux rafales, bk_cov images a couvert
bk_cov      equ z80_img
bk_pts      equ z80_m                   ; (boss : points / 10 ; la mission Z80 n'a pas de boss)
BK_GREN     equ 100             ; images entre deux grenades (2 s)
BK_SPACE    equ 5               ; images entre deux balles d'une rafale (le son dure 14 images)
BK_GI       equ 24              ; apres une explosion qui l'a touche : pas de second degat (le corps ET la tete sont dans le souffle)
BK_ADV      equ 150             ; images d'avance sans couvert (3 s), puis il peut se replanquer
BK_GDMG     equ 3               ; degats de la grenade de Papi
BK_HH     equ 12              ; hauteur d'une moitie de sprite


; --- le code du boss (boss_mod.asm) vit dans la BANQUE 7 : il est assemble pour #4000 et lu au demarrage (OVLB).
;   Les rampes d'entree ci-dessous (en memoire permanente) font apparaitre la banque 7 en #4000 le temps de l'appel ;
;   le miroir (banque 1) revient ensuite. Le code de la banque 7 ne dessine jamais. ATTENTION : le miroir ne peut etre
;   remis que depuis la memoire permanente (une instruction OUT executee dans la fenetre changerait le code sous le
;   processeur) : le code de la banque 7 rend donc la main au moteur par bk_to_next / bk_to_absent2 / bk_to_draw.
CFG_BOSS    equ #C7
boss_tick:  ld bc,#7F00+CFG_BOSS
            out (c),c
            call m_boss_tick
            jr bk_back
bk_unhead:  ld bc,#7F00+CFG_BOSS
            out (c),c
            call m_bk_unhead
            jr bk_back
bk_grenade: ld bc,#7F00+CFG_BOSS
            out (c),c
            call m_bk_grenade
            jr bk_back
hud_kills:  ld bc,#7F00+CFG_BOSS
            out (c),c
            call m_hud_kills
bk_back:    ld bc,#7F00+GAME_CFG
            out (c),c
            ret
bk_killed:  push bc                     ; (conserve BC)
            ld bc,#7F00+CFG_BOSS
            out (c),c
            call m_bk_killed
            ld bc,#7F00+GAME_CFG
            out (c),c
            pop bc
            ret
bk_absent:  push bc
            ld bc,#7F00+CFG_BOSS
            out (c),c
            pop bc
            jp m_bk_absent
bk_head:    push bc
            ld bc,#7F00+CFG_BOSS
            out (c),c
            pop bc
            jp m_bk_head

; sorties du code de la banque 7 vers le moteur : le miroir revient (depuis la memoire permanente), BC reste intact
bk_to_next: push bc
            ld bc,#7F00+GAME_CFG
            out (c),c
            pop bc
            jp enemy_next
bk_to_absent2:
            push bc
            ld bc,#7F00+GAME_CFG
            out (c),c
            pop bc
            jp enemy_absent2
bk_to_draw: push bc
            ld bc,#7F00+GAME_CFG
            out (c),c
            pop bc
            jp enemy_draw

; --- mort du boss (appelee par 'victory') : explosions sur le corps et la tete, puis fin de la zone ---
bk_final:
            xor a
            ld (b_t),a
.lp         ld b,#F5
.w1         in a,(c)
            rra
            jr c,.w1
.w2         in a,(c)
            rra
            jr nc,.w2
            ld a,(b_t)
            and 31
            jr nz,.nx
            ld a,6
            call sfx
.nx         ld a,(b_t)
            rrca
            rrca
            and 3
            ld hl,explo_frames
            call frame_ptr
            push hl
            call .pos
            call draw_sprite
            pop hl
            ld a,(enemies+E_X)
            ld b,a
            ld a,(enemies+E_Y)
            ld c,a
            ld d,b
            ld e,c
            call draw_sprite
            call sound_update
            ld hl,b_t
            inc (hl)
            ld a,(hl)
            cp 64
            jr nz,.lp
            ld a,(bk_pts)               ; points du boss / 10 (25 : Caporal, 35 : Capitaine)
            ld b,a
.pt         push bc
            ld hl,score+4
            call add_score
            pop bc
            djnz .pt
            jp new_game                 ; zone_cur passe a NZONES : l'ecran CONGRATULATIONS (intro.asm)
.pos        ld a,(enemies+ESIZE+E_X)
            ld b,a
            ld a,(enemies+ESIZE+E_Y)
            ld c,a
            ld d,b
            ld e,c
            ret

boss_frames: ds 72                      ; table d'images de la tete (72) : copiee de la zone ; celle du corps est dans general_frames
