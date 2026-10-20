;==============================================================================
;  BOSS (banque 7) : le code de boss.asm qui ne dessine pas.  Assemble pour #4000 (BOSS_LOAD), lu une fois au demarrage dans la banque 7.
;  Il s'execute avec la banque 7 en #4000 : le miroir du decor n'est pas visible tant qu'on y est (voir les rampes d'entree dans boss.asm).
;  Pour rendre la main au moteur (enemy_next, enemy_draw, enemy_absent2) : jp bk_to_next / bk_to_draw / bk_to_absent2 (memoire permanente : elles remettent le miroir).
;==============================================================================
; appelee a chaque image (boucle principale) : rafales et grenades
m_boss_tick:
            ld a,(enemies+E_STATE)      ; le corps est-il en jeu ?
            dec a
            ret nz
            ld hl,b_gi
            ld a,(hl)
            or a
            jr z,.n1
            dec (hl)
.n1         ld a,(p_state)              ; Papi touche ou en train d'entrer : le boss attend (compteurs geles)
            or a
            ret nz
            ld a,(b_cno)                ; cycle couvert / avance
            or a
            jr z,.c1
            dec a
            ld (b_cno),a
            jr .cdone
.c1         ld a,(b_cov)
            or a
            jr z,.c2
            ld hl,(b_cin)
            inc hl
            ld (b_cin),hl
            ld de,(bk_cov)
            or a
            sbc hl,de
            jr c,.cdone
            ld a,BK_ADV
            ld (b_cno),a
.c2         ld hl,0
            ld (b_cin),hl
.cdone      ld a,(b_n)
            or a
            jr nz,.inb
            ld a,(b_cd)
            or a
            jr z,.go
            dec a
            ld (b_cd),a
            jr .gren
.go         ld a,(bk_nb)
            ld (b_n),a
            xor a
            ld (b_t),a
            ld a,11                     ; Tir Boss : un seul son pour toute la rafale
            call sfx
.inb        ld a,(b_t)
            or a
            jr z,.shoot
            dec a
            ld (b_t),a
            jr .gren
.shoot      ld a,BK_SPACE
            ld (b_t),a
            ld hl,b_n
            dec (hl)
            jr nz,.sh
            ld a,(bk_dl)
            ld (b_cd),a
.sh         call bk_shoot
.gren       ld hl,b_gcd
            ld a,(hl)
            or a
            jr z,.gtry
            dec (hl)
            ret
.gtry       ld a,(bk_pts)               ; points >= 500 : ce boss ne lance pas de grenade (Falzar)
            cp 50
            ret nc
            ld a,(eg_state)             ; une seule grenade ennemie a la fois
            or a
            ret nz
            ld ix,enemies
            call egrenade_throw         ; (avec son son)
            ld a,BK_GREN
            ld (b_gcd),a
            ret

; une balle du corps vers Papi (comme enemy_shoot, sans le bruit de coup de feu du soldat)
bk_shoot:
            ld a,(enemies+E_X)
            ld d,a
            ld a,(enemies+E_Y)
            ld e,a
            ld a,4                      ; classe de portee : boss
            ld (shot_cls),a
            push ix
            ld ix,bullets+4*BSIZE
            ld bc,BSIZE
            ld a,NBUL-4
.find       ex af,af'
            ld a,(ix+B_ON)
            or a
            jr z,.ok
            add ix,bc
            ex af,af'
            dec a
            jr nz,.find
            pop ix
            ret
.ok         push de
            call aim_dir_de
            pop hl                      ; H = x, L = y
            call bullet_start
            jr nz,.nf
            sra (ix+B_DX)
            sra (ix+B_DY)
            ld a,(b_cov)                ; a couvert : la balle traverse son obstacle
            or a
            jr z,.nf
            ld (ix+B_PASS),3
.nf         pop ix
            ret

; (pour rendre la main au moteur on saute en memoire permanente : bk_to_next / bk_to_absent2 / bk_to_draw remettent le miroir ; on ne
;  peut pas le faire d'ici, le code qui suit serait lu dans la banque 1)
; --- la place 0 / 1 n'est pas en jeu (hook de enemy_absent, IX = fiche, ixl < 32) ---
m_bk_absent:
            ld a,ixl
            or a
            jr nz,.head
            ld a,12                     ; le corps apparait a 12 lignes ou plus du haut (sa tete tient au-dessus)
            ld (ymin),a
            jp bk_to_absent2
.head       ld a,(enemies+E_STATE)      ; la tete arrive en meme temps que le corps
            dec a
            jp nz,bk_to_next
            ld (ix+E_STATE),1
            ld (ix+E_OX),#FF
            ld (ix+E_LAST),#FF
            ld a,60                     ; premiere rafale 1,2 s apres l'arrivee, premiere grenade 1,5 s
            ld (b_cd),a
            ld a,75
            ld (b_gcd),a
            ; (suite : bk_head)

; --- la tete (hook de enemy_alive, IX = fiche de la tete) ---
m_bk_head:
            ld a,(enemies+E_STATE)
            dec a
            jp nz,bk_to_next
            ld a,(enemies+E_X)
            ld b,a
            ld a,(enemies+E_Y)
            sub BK_HH
            ld c,a
            ld a,(enemies+E_DIR)
            ld (ix+E_DIR),a
            ld a,(enemies+E_TICK)
            ld (ix+E_TICK),a
            ld a,(slot_flash)           ; clignote en blanc avec le corps
            ld hl,slot_flash+1
            cp (hl)
            jr z,.nf
            ld (hl),a
            ld (ix+E_LAST),#FF
.nf         push bc                     ; chaque tour : on libere ses cases, on les reserve a la nouvelle place, puis celles du corps (rangees communes)
            ld a,(ix+E_CELL+1)
            or a
            call nz,enemy_free
            pop bc
            ld (ix+E_X),b
            ld (ix+E_Y),c
            call enemy_claim
            push ix
            ld ix,enemies
            ld b,(ix+E_X)
            ld c,(ix+E_Y)
            call enemy_claim
            pop ix
.draw       ld d,0
            jp bk_to_draw

; le corps libere les cases de la tete avant de bouger (sinon elles lui barrent la route quand il monte) ; la tete les reserve a nouveau a son tour
m_bk_unhead:
            push ix
            ld ix,enemies+ESIZE
            ld a,(ix+E_CELL+1)
            or a
            call nz,enemy_free
            pop ix
            ret

; --- touches ---
m_bk_killed:                            ; balle de Papi sur le corps ou la tete (la rampe d'entree conserve BC)
            ld a,1
            jr bk_dmg
m_bk_grenade:                           ; souffle de la grenade de Papi : une seule fois par explosion
            ld a,(b_gi)
            or a
            ret nz
            ld a,BK_GI
            ld (b_gi),a
            ld a,BK_GDMG
            ; (suite : bk_dmg)
bk_dmg:                                 ; A = degats
            ld c,a
            ld hl,kills_left
            ld a,(hl)
            sub c
            jr nc,.s
            xor a
.s          ld (hl),a
            ld hl,hud_dirty
            set 2,(hl)
            or a
            jr z,.dead
            ld a,FLASH_N
            ld (slot_flash),a
            ld (slot_flash+1),a
            ld a,#FF
            ld (enemies+E_LAST),a
            ld (enemies+ESIZE+E_LAST),a
            ld a,3
            jp sfx
.dead       ret                         ; kills_left = 0 : la boucle principale appelle 'victory' (bk_final)

; --- compteur de points de vie du HUD, en couleur ---
m_hud_kills:
            ld a,(kills_left)
            ld hl,hp_thr
            ld de,hp_pens
            cp (hl)
            jr nc,.c
            inc hl
            inc de
            inc de
            cp (hl)
            jr nc,.c
            inc hl
            inc de
            inc de
            cp (hl)
            jr nc,.c
            inc de
            inc de
.c          ld a,(de)
            ld (expand_glyph.a-1),a     ; pixel gauche (deux octets)
            ld (expand_glyph.c-1),a
            inc de
            ld a,(de)
            ld (expand_glyph.b-1),a     ; pixel droit
            ld a,(kills_left)
            ld bc,#45C1
            call put_2digits
            ld a,#A2                    ; blanc pour les autres nombres
            ld (expand_glyph.a-1),a
            ld (expand_glyph.c-1),a
            ld a,#51
            ld (expand_glyph.b-1),a
            ret
