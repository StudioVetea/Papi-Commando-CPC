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

            include 'veh_mod.asm'
;------------------------------------------------------------------------------
; voix numerisee de l'intro (banque 7 aussi) : « Papi Commando CPC ! », echantillons 4 bits (2 par octet, poids fort d'abord) joues
; sur le canal A du PSG (registre 8 = volume, tons et bruit coupes). Interruptions coupees pendant la lecture (~2,4 s).
; Entree : m_voice (appelee par la rampe 'voice_play' du demarrage, miroir de la banque 1 non necessaire)
;------------------------------------------------------------------------------
VOICE_DATA  equ BOSS_LOAD+VOICE_OFF
VOICE_END   equ VOICE_DATA+VOICE_LEN
VOICE_DELAY equ 35                      ; reglage de la cadence (~6 kHz), mesure a l'emulateur
m_voice:    di
            ld bc,#F782                 ; PPI : port A en sortie
            out (c),c
            ld a,7                      ; registre 7 (mixer) = tout coupe
            ld e,#3F
            call .psg
            ld a,8                      ; registre 8 (volume A) : reste selectionne, on n'ecrit plus que la valeur
            ld e,0
            call .psg
            ld de,VOICE_DATA
            ld h,#80
            ld l,0
.byte       ld a,(de)
            rrca
            rrca
            rrca
            rrca
            and 15
            ld c,a
            ld b,#F4
            out (c),c                   ; donnee du volume sur le port A
            ld b,#F6
            out (c),h                   ; ecriture PSG (BDIR = 1)
            out (c),l                   ; inactif
            ld a,VOICE_DELAY
.d1         dec a
            jr nz,.d1
            ld a,(de)
            inc de
            and 15
            ld c,a
            ld b,#F4
            out (c),c
            ld b,#F6
            out (c),h
            out (c),l
            ld a,VOICE_DELAY
.d2         dec a
            jr nz,.d2
            ld a,d
            cp hi(VOICE_END)
            jr nz,.byte
            ld c,0                      ; silence
            ld b,#F4
            out (c),c
            ld b,#F6
            out (c),h
            out (c),l
            ret
.psg        ld b,#F4                    ; A = registre, E = valeur : selection puis ecriture
            out (c),a
            ld bc,#F6C0
            out (c),c
            ld bc,#F600
            out (c),c
            ld b,#F4
            out (c),e
            ld bc,#F680
            out (c),c
            ld bc,#F600
            out (c),c
            ret

; ==== OFFICIERS et GRENADIERS (voir gr_call dans boss.asm) ====

; mort du grenadier IX : 25 % de chance de laisser une caisse de grenades a l'endroit ou il tombe (une seule caisse en jeu a la fois)
gr_drop:    ld a,(crate_st)
            or a
            ret nz
            call rand
            ld a,h
            and 3
            ret nz
            ld a,(ix+E_X)
            ld (crate_x),a
            ld a,(ix+E_Y)
            ld (crate_y),a
            ld a,#FF
            ld (crate_ox),a             ; rien a effacer
            ld a,1
            ld (crate_st),a             ; au sol
            ret

; A = 1 officers_update, 2 reflexion du grenadier IX, 3 mort du grenadier IX
gr_mod:       dec a
            jp z,m_officers_update
            dec a
            jp z,grenadier_think
            jr gr_drop

;------------------------------------------------------------------------------
; OFFICIERS : un lancer de grenade toutes les 8 a 13 secondes chacun.
;   Les officiers sont les derniers de la liste (off_from) : 1, 1, 2, 2, 3, 3 pour 2..12 ennemis.
;   officers_update est appelee une image sur 4. Une minuterie par officier (off_tmr) compte en
;   pas de 4 images : 100 a 163 pas = 400 a 652 images = 8 a 13 s. Zero = a retirer au hasard.
;   Une seule grenade ennemie a la fois : si elle est occupee, nouvel essai 2 s plus tard.
;------------------------------------------------------------------------------
m_officers_update:
            ld a,(nb_wanted)
            add a,a
            add a,a
            add a,a
            add a,a
            ld c,a                      ; C = fin de la liste des fiches
            xor a
            ld ixl,a
            ld ixh,hi(enemies)
.next       ld a,ixl
            cp c
            ret nc
            rrca
            rrca
            rrca
            rrca
            and 15
            ld e,a
            ld d,0
            ld hl,slot_gren             ; cette place lance-t-elle des grenades ? (bit 0)
            add hl,de
            ld a,(hl)
            and #71                     ; bit 0 : lance des grenades ; bits 4-6 : classe (6 = grenadier)
            ld b,a
            and 1
            jp z,.step
            ld a,b
            and #70
            cp #60
            ld a,0
            jr nz,.nogr
            inc a
.nogr       ld (og_gr),a                ; 1 : cet officier est un grenadier (cadence de 2 s, portee +20 %)
            ld hl,off_tmr
            add hl,de                   ; HL = minuterie de cet officier
            ld a,(ix+E_STATE)
            dec a
            jr z,.alive
            ld (hl),0                   ; mort ou absent : on repart de zero
            jr .step
.alive      ld a,(hl)
            or a
            jr nz,.armed
            push hl
            call rand                   ; A = hasard
            pop hl
            ld b,a
            ld a,(og_gr)
            or a
            ld a,b
            jr nz,.rgr
            and 63
            add a,100
            ld (hl),a
            jr .step
.rgr        and 15                      ; grenadier : premier lancer dans 40 a 100 images, ensuite toutes les 2 s (25 pas de 4 images)
            add a,10
            ld (hl),a
            jr .step
.armed      dec (hl)
            jr nz,.step
            ld a,(og_gr)
            or a
            jr z,.ofc
            push bc
            call gr_dist                ; grenadier : trop loin pour lancer : nouvel essai dans 24 images
            pop bc
            cp GR_THROW+1
            jr nc,.retry
.ofc        ld a,(eg_state)             ; echeance : grenade libre et Papi en jeu ?
            ld b,a
            ld a,(p_state)
            or b
            jr z,.throw
.retry      ld a,(og_gr)                ; non : nouvel essai (officier : 100 images, grenadier : 24)
            or a
            ld a,25
            jr z,.rr
            ld a,6
.rr         ld (hl),a
            jr .step
.throw      ld a,(og_gr)
            or a
            jr nz,.gthrow
            push bc
            call egrenade_throw
            pop bc
            jr .step
.gthrow     ld (hl),25                  ; grenadier : prochain lancer dans 2 s (25 pas de 4 images), portee des officiers + 20 %
            ld a,EG_RANGEX*6/5
            ld (eg_rx),a
            ld a,EG_RANGEY*6/5
            ld (eg_ry),a
            push bc
            call egrenade_throw_r
            pop bc
.step       ld a,ixl
            add a,ESIZE
            ld ixl,a
            jp .next

; lance la grenade de l'officier IX vers la position de Papi, a portee de grenade au plus (vol de 64 images)
egrenade_throw:                         ; portee des officiers
            ld a,EG_RANGEX
            ld (eg_rx),a
            ld a,EG_RANGEY
            ld (eg_ry),a
egrenade_throw_r:                       ; portee eg_rx / eg_ry (le grenadier : +20 %)
            ld a,(ix+E_X)
            add a,2
            ld b,a                      ; B = x de depart
            ld a,(ix+E_Y)
            add a,3
            ld c,a                      ; C = y de depart
            xor a
            ld (eg_xf),a
            ld (eg_yf),a
            ld a,b
            ld (eg_x),a
            ld a,c
            ld (eg_y),a
            ld a,(p_x)
            add a,2
            sub b
            ld hl,eg_rx
            ld e,(hl)
            call .clamp                 ; elle ne va pas plus loin que celle de Papi
            call .v4                    ; vitesse = ecart x 4 : 64 images x 4 / 256 = l'ecart
            ld (eg_vx),hl
            ld a,(p_y)
            add a,3
            sub c
            ld hl,eg_ry
            ld e,(hl)
            call .clamp
            call .v4
            ld (eg_vy),hl
            xor a
            ld (eg_t),a
            dec a
            ld (eg_ox),a                ; rien a effacer
            ld a,1
            ld (eg_state),a
            ld a,7                      ; son du lancer
            jp sfx
.v4         ld l,a
            add a,a
            sbc a,a
            ld h,a                      ; HL = A etendu au signe
            add hl,hl
            add hl,hl
            ret
.clamp      jr c,.cneg                  ; retenue du sub = ecart negatif (8 bits signes ne suffisent pas : 200 lignes)
            cp e
            ret c
            ld a,e
            ret
.cneg       neg
            cp e
            jr c,.cok
            ld a,e
.cok        neg
            ret

;------------------------------------------------------------------------------
; GRENADIER : ne cherche pas le contact. Distance m a Papi = max(3 x |dx octets|, |dy lignes|) (en gros des lignes) :
;   m > GR_FAR  -> il se rapproche (champ de distances, comme les autres) ; m < GR_NEAR -> il recule ; entre les deux il reste sur place, face a Papi.
;   Il lance une grenade toutes les 2 s tant que m <= GR_THROW (voir officers_update).
;------------------------------------------------------------------------------
GR_NEAR     equ 40
GR_FAR      equ 62
GR_THROW    equ 76              ; portee de lancer : celle des officiers (60 lignes) + 20 %, plus la dispersion
grenadier_think:
            call gr_dist                ; A = m
            cp GR_FAR
            jr c,.mid
            call enemy_think.nocov      ; trop loin : il suit de loin (champ de distances, comme les autres)
            jr gr_face
.mid        cp GR_NEAR
            jr c,.back
            jp enemy_think.near         ; a bonne distance : il s'arrete, face a Papi (il ne tire pas : voir enemy_try_fire)
.back       call aim_dir                ; trop pres : il recule (direction opposee a Papi)
            ld c,a
            ld b,0
            ld hl,opp_tab
            add hl,bc
            ld a,(hl)
            call enemy_setdir
            ld (ix+E_TIMER),8           ; il repense plus souvent quand il recule
; en marchant en haut ou en bas il reste face a Papi : de face s'il est plus bas, de dos s'il est plus haut (la planche n'a que 4 directions)
gr_face:    ld a,(ix+E_DIR)
            sub 2
            cp 2
            ret nc
            ld a,(p_y)
            cp (ix+E_Y)
            ld a,2
            jr nc,.f
            inc a
.f          ld (ix+E_DIR),a
            ret
opp_tab:    db 1,0,3,2,7,6,5,4

; distance du grenadier IX a Papi : A = max(3 x |dx|, |dy|), plafonnee a 255
gr_dist:
            ld a,(p_x)
            sub (ix+E_X)
            jr nc,.x
            neg
.x          ld c,a
            add a,a
            add a,c                     ; 3 x |dx| (au plus 3 x 78 = 234)
            ld c,a
            ld a,(p_y)
            sub (ix+E_Y)
            jr nc,.y
            neg
.y          cp c
            ret nc
            ld a,c
            ret


;------------------------------------------------------------------------------
; SNIPER C++ (classe 7) : immobile dans son trou (trou tire au hasard a chaque sortie : sn_pick, liste ecrite par convert.py).
;   E_STATE : 0 cache (E_TICK:E_TIMER = delai de 3 a 10 s avant la prochaine sortie), 3 sorti mais intouchable, 1 sorti et touchable (balles et grenade).
;   E_DX = phase : 0 sortie (4 images de 8 images : touchable des la 3e), 1 vise Papi (5 s au plus, un tir toutes les 2 s, bas / bas droite / bas gauche),
;   2 rentre dans son trou (4 images : touchable pendant les 2 premieres). E_TICK = images ecoulees dans la phase. E_DIR = direction du tir (2, 4 ou 5).
;   Papi n'est pas en dessous de lui : il ne sort pas, ou il rentre. Sortie de sn_mod : A = 0 rien a faire, 1 effacer son image, 2 + n dessiner l'image n.
;------------------------------------------------------------------------------
sn_slot:    ld a,ixl                    ; DE = numero de sa place
            rrca
            rrca
            rrca
            rrca
            and 15
            ld e,a
            ld d,0
            ret

sn_rearm:   call rand                   ; prochaine sortie : 150 a 500 images (3 a 10 s), sur 16 bits dans E_TICK:E_TIMER
            and 1
            ld c,a
            call rand
            ld l,a
            ld h,0
            ld de,150
            add hl,de
            bit 0,c
            jr z,.s
            ld de,95
            add hl,de
.s          ld (ix+E_TIMER),l
            ld (ix+E_TICK),h
            xor a
            ret

; choisit un trou libre au hasard (liste dans spawn_tab, indices spawn_n a 14, x = #FF : vide) ; ecrit E_X, E_Y ; IX, IY conserves ; 16 essais
sn_pick:    ld b,16
.t          push bc
            call rand
            and 15
            ld hl,spawn_n
            cp (hl)
            jr c,.nx
            cp 15
            jr nc,.nx
            add a,a
            ld e,a
            ld d,0
            ld hl,spawn_tab
            add hl,de
            ld a,(hl)
            inc hl
            ld l,(hl)
            ld h,a                      ; H = x, L = y
            inc a
            jr z,.nx
            push iy
            ld iy,enemies
            ld de,ESIZE
            ld b,MAXENEMY
.o          ld a,(iy+E_STATE)
            or a
            jr z,.on
            ld a,(iy+E_X)
            cp h
            jr nz,.on
            ld a,(iy+E_Y)
            cp l
            jr z,.occ
.on         add iy,de
            djnz .o
            pop iy
            ld (ix+E_X),h
            ld (ix+E_Y),l
            pop bc
            ret
.occ        pop iy
.nx         pop bc
            djnz .t
            ret

sn_mod:     ld a,(ix+E_STATE)
            or a
            jp nz,.vis
            ld a,(ix+E_X)
            or a
            jr nz,.cd
            call sn_pick                ; premier passage : il prend un trou au hasard, puis attend
            jp sn_rearm
.cd         ld a,(en_dt)
            ld c,a
            ld a,(ix+E_TIMER)
            sub c
            ld (ix+E_TIMER),a
            jr c,.brw
            jr nz,.wait
            ld a,(ix+E_TICK)
            or a
            jr z,.go
.wait       xor a
            ret
.brw        ld a,(ix+E_TICK)
            or a
            jr z,.go
            dec (ix+E_TICK)
            xor a
            ret
.go         call sn_pick                ; trou au hasard parmi les trous libres
            ld a,(ix+E_Y)               ; Papi doit etre en dessous de lui, sinon il reste cache : nouvel essai dans 30 images
            add a,6
            ld hl,p_y
            cp (hl)
            jr c,.ok
            jr z,.ok
            ld (ix+E_TIMER),30
            ld (ix+E_TICK),0
            xor a
            ret
.ok         ld b,(ix+E_X)               ; il sort : il occupe ses cases, 3 PV
            ld c,(ix+E_Y)
            call enemy_claim
            ld (ix+E_STATE),3
            xor a
            ld (ix+E_DX),a
            ld (ix+E_TICK),a
            ld (ix+E_OX),#FF
            ld (ix+E_LAST),#FF
            ld (ix+E_DIR),2
            call sn_slot
            ld hl,slot_hp0
            add hl,de
            ld a,(hl)
            ld hl,slot_hp
            add hl,de
            ld (hl),a
            ld hl,slot_flash
            add hl,de
            ld (hl),0
            xor a
.show       cp (ix+E_LAST)              ; A = image voulue : redessin seulement si elle change
            jr nz,.d
            xor a
            ret
.d          add a,2
            ret

.vis        call sn_slot                ; clignotement blanc (touche sans mourir) : il se decompte, puis image normale
            ld hl,slot_flash
            add hl,de
            ld a,(hl)
            or a
            jr z,.nofl
            ld b,a
            ld a,(en_dt)
            ld c,a
            ld a,b
            sub c
            jr z,.flend
            jr nc,.flst
.flend      xor a
            ld (hl),a
            ld (ix+E_LAST),#FF
            jr .nofl
.flst       ld (hl),a
.nofl       ld a,(en_dt)
            add a,(ix+E_TICK)
            ld (ix+E_TICK),a
            ld a,(ix+E_DX)
            or a
            jr z,.emerge
            dec a
            jr z,.aim
            ld a,(ix+E_TICK)            ; --- il rentre
            cp 32
            jr nc,.hide
            cp 16
            jr c,.rt
            ld (ix+E_STATE),3
.rt         rrca
            rrca
            rrca
            and 3
            add a,4
            jr .show
.hide       call enemy_free
            ld (ix+E_STATE),0
            call sn_rearm
            ld a,(ix+E_OX)
            inc a
            ret z
            ld a,1
            ret
.emerge     ld a,(ix+E_TICK)            ; --- il sort
            cp 32
            jr nc,.toaim
            cp 16
            jr c,.em1
            ld (ix+E_STATE),1
.em1        rrca
            rrca
            rrca
            and 3
            jr .show
.toaim      ld (ix+E_DX),1
            xor a
            ld (ix+E_TICK),a
            ld (ix+E_STATE),1
            call fire_ptr               ; premier tir 1 s plus tard
            ld a,(frame)
            sub 50
            ld (hl),a
.aim        ld a,(ix+E_TICK)            ; --- il vise
            cp 244
            jr nc,.leave
            ld a,(ix+E_Y)
            add a,6
            ld hl,p_y
            cp (hl)
            jr c,.below
            jr nz,.leave
.below      ld a,(p_x)
            sub (ix+E_X)
            ld c,4
            jr nc,.dx
            neg
            ld c,5
.dx         cp 4
            jr nc,.dset
            ld c,2
.dset       ld (ix+E_DIR),c
            call fire_ptr
            ld a,(frame)
            sub (hl)
            cp 100
            jr c,.nofire
            ld a,(frame)
            ld (hl),a
            xor a
            ld (cov_now),a
            call enemy_shoot
.nofire     ld a,(ix+E_DIR)
            ld b,8
            cp 2
            jr z,.sh2
            ld b,12
            cp 4
            jr z,.sh2
            ld b,16
.sh2        ld a,b
            jp .show
.leave      ld (ix+E_DX),2
            xor a
            ld (ix+E_TICK),a
            ld a,4
            jp .show

            assert $<=VOICE_DATA                ; (la voix et les images des vehicules sont ajoutees apres le code par tools/mkdisk.py : build/boss_code.bin + voice.bin + trucks.bin)
TRUCK_DATA  equ BOSS_LOAD+TRUCK_OFF
