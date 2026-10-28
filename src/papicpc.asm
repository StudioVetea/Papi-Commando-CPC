;==============================================================================
;  PAPI COMMANDO CPC - moteur "beaucoup d'ennemis"
;  Amstrad CPC 464 (64K), MODE 0, tout en assembleur Z80 - RASM
;
;      rasm src/papicpc.asm -Isrc/ -o build/papicpc -eo      (voir build.sh / build.bat)
;      puis sous BASIC :  RUN"PAPICPC"
;
;  Idees directrices (detaillees dans LISEZMOI.md) :
;   1. aucun appel systeme pendant le jeu ; on se cale sur le VBL en lisant le
;      PPI ; l'interruption ne sert que d'horloge (6 tops par image)
;   2. un sprite = une seule ecriture par octet ecran (fond + sprite composes
;      a la volee depuis une copie du decor) : pas d'effacement prealable, pas
;      de scintillement, pas de double buffer
;   3. Papi et ses balles passent en premier, a 50 Hz quoi qu'il arrive. Les
;      ennemis se partagent le temps qui reste : on en traite autant que
;      possible, a tour de role, et on s'arrete avant la fin de l'image. Un
;      ennemi qui a attendu 2 ou 3 images avance de 2 ou 3 pas d'un coup.
;   4. l'IA "reflechit" 3 fois par seconde et par ennemi, a tour de role ;
;      entre deux reflexions un ennemi ne fait qu'avancer
;   5. le chemin vers Papi est calcule UNE fois pour tout le monde (champ de
;      distances par inondation), quelques cases par image
;   6. jamais de multiplication ni de division : tables et decalages
;==============================================================================

; ---- OVERSCAN VERTICAL : 32 rangees = 256 lignes (7 de bandeau + HUD + 24 de carte) ------------
;   #0000-#3FFF  programme, donnees, tables, pile
;   #4000-#7FFF  copie du decor ("miroir") : adresse miroir = adresse ecran - #8000 (bit 7 de H a zero)
;   #8000-#BFFF  page video A : bandeau (7 rangees a la fin de chaque bloc de 2 Ko) ; le reste de
;                chaque bloc (1488 octets) contient 10 images de sprites
;   #C000-#FFFF  page video B : HUD + carte, disposition habituelle
GRID        equ #3800           ; 26 x 16 cases : decor + occupation
                                ; GRID+#200 et GRID+#400 : champs de distances
SCR_LO      equ #3E00           ; adresse ecran de chaque ligne (poids faible) ; y = 200..255 : bandeau
SCR_HI      equ #3F00           ; (poids fort)
COLTAB      equ #3200           ; x octet -> colonne de tuile (x/6)
MOD6        equ #3300           ; x octet -> x mod 6
OCCY        equ #3400           ; y -> un mur "devant" peut-il cacher un sprite ici ?
QUEUE       equ #3500           ; file de l'inondation (2 x 312 octets)
bullets     equ #308C           ; table des balles (110 octets) : zone #3000-#31FF (ancien bloc de sprites de demarrage, libre une fois copie)
FIRE_LAST   equ #3060           ; derniere image de tir de chaque ennemi (12 octets) : trou apres le 1er champ de distances
GRENADE_HOLD equ 25             ; appui long sur tir = grenade : 25 images = 0,5 s (35 = 0,7 s en v12, 75 = 1,5 s en v11) ; a regler apres essais
            include 'layout.inc'        ; pistes de la cover et de la zone, zone de preparation (genere par tools/convert.py)
; ---- CPC 6128 (128 Ko) : la fenetre #4000-#7FFF montre une banque de 16 Ko a la fois (port #7Fxx : #C0 + numero de configuration) ----
;   banque 1 (configuration #C0, celle du demarrage) : le miroir du decor, pendant le jeu (GAME_CFG) ;
;   banques 4, 5, 6 : les overlays (ecrans), lus UNE fois au demarrage puis simplement affiches en #4000 quand on en a besoin (ovl_go) :
;   plus de lecture disquette entre les missions ; banque 7 : libre (modules de mission, etc.)
GAME_CFG    equ #C0             ; banque 1 en #4000 : le miroir
CFG_MENU    equ #C4             ; banque 4 : menu principal (entree MENU_LOAD)
CFG_INTRO   equ #C5             ; banque 5 : ecrans de mission (entree INTRO_LOAD, bandeau INTRO_LOAD+3)
CFG_HOF     equ #C6             ; banque 6 : Hall of Fame (entree HOF_LOAD)...
CFG_GO      equ #C6             ; ...et game over (entree GO_LOAD, un peu plus loin dans la meme banque)
spawn_tab   equ #306C          ; 16 x (x,y) : copie des points d'apparition de la zone (apres FIRE_LAST ; #3DA0+ est efface par init_screen)
slot_type   equ #3000          ; caracteristiques de chaque place d'ennemi, copiees de l'en-tete du fichier de zone (12 octets chacune)
slot_spd    equ #300C          ; decalage dans les tables de vitesse (0 normal, 32 rapide)
slot_fire   equ #3018          ; images entre deux tirs
slot_pts    equ #3024          ; points / 10
slot_hp0    equ #3030          ; points de vie au depart
slot_gren   equ #303C          ; 1 = lance des grenades
slot_hp     equ #3048          ; points de vie restants
general_frames equ #3190        ; 3e table d'images (72 octets)
lz_tok      equ #31E0          ; variables du decompresseur
lz_off      equ #31E1
slot_flash  equ #3054          ; clignotement blanc restant (images) de chaque place : 12 octets
white_buf   equ #3770          ; image blanche de l'ennemi qui clignote (144 octets, zone libre #3000-#31FF)
FLASH_N     equ 10             ; duree du clignotement blanc apres un tir qui ne tue pas (images)
GREN_MAX    equ 25             ; grenades au plus
GREN_START  equ 5              ; grenades au debut d'une zone (a regler)
CRATE_GREN  equ 5              ; grenades d'une caisse
ZC_LEN      equ 64             ; images du jingle ZONE CLEAR
CRATE_DELAY equ 100            ; images entre le moment ou il reste moins de 2 grenades et le parachutage
soldat_frames equ #3100         ; tables d'images des unites de la zone, 72 octets chacune : fin libre de la file d'inondation
officer_frames equ #3148
fdc_res     equ #3DA0           ; variables du lecteur de disquette : trou libre de la grille, apres le 2e champ de distances
ld_trk      equ #3DA7
ld_idx      equ #3DA8
ld_cnt      equ #3DA9           ; 2 octets
ld_dst      equ #3DAB           ; 2 octets
ld_try      equ #3DAD
rd_trk      equ #3DAE
rd_r        equ #3DAF
rd_eot      equ #3DB0
sk_trk      equ #3DB1
MOTOR       equ #FA7E
STACK       equ #0200
BANNER      equ #8760           ; ligne 0 du bandeau : #8000 + 2 x (1024 - 40 x 2)
SPRSLOT     equ 13              ; images de sprites par trou de la page A (1888 octets = 2048 - 2 rangees) : 104 emplacements

MAXENEMY    equ 12                ; equilibrage : 12 ennemis au plus a l'ecran
NEAR        equ 5               ; (boss : a moins de 5 cases de Papi il s'arrete et tire ; les autres classes : near_tab)
TICK_STOP   equ 5               ; on ne commence plus un ennemi apres 16,8 ms d'image
ESIZE       equ 16
NBUL        equ 10              ; 0-3 : Papi, 4-9 : ennemis
BSIZE       equ 11
XMAX        equ 72              ; 78 - 6
YMAX        equ 180             ; 192 - 12
PAPI_Y0     equ 180             ; Papi apparait tout en bas de la carte...
PAPI_Y1     equ 172             ; ...et avance de 8 lignes (1 ligne toutes les 3 images)
EG_FLIGHT   equ 64              ; grenade des officiers : images de vol (32 avant : deux fois plus lente)
EG_RANGEX   equ 20              ; portee maximale, celle de la grenade de Papi : 20 octets...
EG_RANGEY   equ 60              ; ...et 60 lignes (30 images x 2 lignes)
G_FLIGHT    equ 30              ; images de vol de la grenade (24 avant : +25 % de portee)
FF_CELLS    equ 6               ; cases du champ de distances developpees par image

; --- fiche ennemi (IX), 16 octets, tableau aligne sur 256 ---
E_STATE     equ 0               ; 0 absent, 1 vivant, 2 en train de mourir
E_X         equ 1
E_Y         equ 2
E_OX        equ 3               ; position affichee (#FF = rien a l'ecran)
E_OY        equ 4
E_DIR       equ 5
E_DX        equ 6               ; -1, 0, 1
E_DY        equ 7               ; -1, 0, 1
E_TIMER     equ 8               ; avant la prochaine reflexion / reapparition
E_LAST      equ 9               ; derniere image affichee
E_CELL      equ 10              ; (2) case occupee dans GRID
E_TICK      equ 12              ; avance en marchant : donne l'image d'animation
E_LASTF     equ 13              ; numero de l'image de son dernier passage
E_FX        equ 14              ; restes de vitesse (virgule fixe)
E_FY        equ 15

; --- fiche balle (IX) ---
B_ON        equ 0               ; 0 libre, 1 en vol, 2 a effacer, 3 eclat de fin de portee
B_X         equ 1
B_Y         equ 2
B_OX        equ 3
B_OY        equ 4
B_DX        equ 5
B_DY        equ 6
B_PASS      equ 9               ; pas restants pendant lesquels la balle traverse les murs rouges (tireur colle a son obstacle)
B_AGE       equ 8               ; nombre de pas faits (balles ennemies : une balle toute jeune n'est jamais cachee) ; eclat (etat 3) : image 0..6
B_RNG       equ 10              ; portee : nombre de pas au bout desquels la balle eclate (voir rng_tab)
og_gr       equ #30FB           ; officers_update : 1 = la place examinee est un grenadier (octets libres apres la table des balles)
eg_rx       equ #30FC           ; portee en x de la grenade ennemie qui part (octets)
eg_ry       equ #30FD           ; portee en y (lignes)
shot_cls    equ #30FA           ; classe de portee du tireur de la balle qui part (0 Papi, 1 soldat, 2 officier, 3 general, 4 boss, 5 vehicule)
PBUL_SPEED  equ 179             ; balles de Papi : 179/256 = 70 % des images (100 % avant), pas inchange
PSPEED_X    equ 90              ; Papi : cumul horizontal 90/256 = 0,35 octet par image (17,5 octets/s ; 25 avant)
PSPEED_Y    equ 179             ; Papi : cumul vertical 179/256 = 0,7 ligne par image (35 lignes/s ; 50 avant)
B_ACC       equ 7               ; balles ennemies : cumul de vitesse (voir EBUL_SPEED)
SBUL_SPEED  equ 97              ; balles du sniper : 54 % de PBUL_SPEED (67,5 % puis -20 %), avec le pas entier
EBUL_SPEED  equ 131             ; balles ennemies : elles avancent 131 images sur 256 (154 avant : -15 %) d'un pas moitie
                                ; moins long (shot_tab / 2) : 15 x pas/s au lieu de 25 x pas/s = 60 % de la v03b

            ifdef SNA
              buildsna
              bankset 0
            endif
            org #0200                   ; (la pile est juste en dessous : #0200 vers le bas)
prog_start:
enemies:    ds MAXENEMY*ESIZE           ; en tete de fichier : aligne sur une page, sans trou perdu
            run boot

new_game:
            di
            ld sp,STACK
            ld a,(won)                  ; victoire : zone suivante (la derniere est suivie de la premiere)
            or a
            jr z,.same
            xor a
            ld (won),a
            ld hl,score                 ; le score est conserve d'une zone a la suivante
            ld de,score_keep
            ld bc,5
            ldir
            ld a,1
            ld (carry),a
            ld a,(lives)                ; les vies passent aussi d'une mission a la suivante
            ld (lives_keep),a
            ld hl,zone_cur              ; mission suivante (apres la derniere : ecran de fin, puis le menu : voir intro.asm)
            inc (hl)
.same       ld a,CFG_INTRO              ; ecran noir : zone, numero et type de mission (overlay, en banque) ; la zone se charge ensuite
            ld hl,INTRO_LOAD
            call ovl_go
            call load_zone
new_game2:  ld a,CFG_INTRO              ; bandeau (efface par les ecrans noirs) : redessine par l'overlay
            ld hl,INTRO_LOAD+3
            call ovl_go
            call init_screen
            call build_occy
            call init_game
            ei

;------------------------------------------------------------------------------
; boucle principale : une iteration par image (50 Hz)
;------------------------------------------------------------------------------
main_loop:
.w0         ld a,(since)                ; le VBL deja servi ne compte pas : il faut au
            cp 5                        ; moins 5 tops (13 ms) depuis le debut de l'image
            jr c,.w0
wait_vbl:   ld b,#F5
.w          in a,(c)
            rra
            jr nc,.w
wait_end:
            xor a
            ld (since),a
            ld a,(meter)
            or a
            jr z,.nom
            ld bc,#7F10                 ; jauge : bordure rouge pendant le calcul
            out (c),c
            ld c,#4C
            out (c),c
.nom
            ld hl,frame
            inc (hl)
            call keyscan
            call wtr_tick               ; eau animee (zone 3) et vitesse de Papi dans l'eau : voir water.asm
            ld a,1                      ; zone 4 : le vehicule (avant Papi, qui se redessine par-dessus) et les bidons
            call veh_if
            call player_update          ; d'abord ce qui doit rester a 50 Hz
            call time_tick              ; Time Attack : une seconde de moins toutes les 50 images
            ld a,(kills_left)
            or a
            call z,victory              ; le quota d'ennemis est atteint (ou le temps est ecoule)
            ld a,(p_state)
            cp 2
            jr z,.frozen                ; partie finie : la scene reste figee sous le message
            call bullets_update
            call grenade_update
            call egrenade_update
            ld a,(bk_on)                 ; mission du boss : rafales et grenades
            or a
            call nz,boss_tick
            call crate_update
            call life_blink
            ld a,(frame)
            and 3
            call z,officers_update      ; les officiers : une image sur 4 suffit
            call flow_update
            call hud_update
            call sound_update
            ld a,(crate_st)             ; la caisse en descente se redessine a chaque image (0,8 ms) : les ennemis s'arretent un top plus tot
            cp 2
            ld a,TICK_STOP
            jr nz,.tl
            dec a
.tl         ld (tick_lim),a
            call enemies_update         ; puis les ennemis, tant qu'il reste du temps
            call crate_draw             ; la caisse parachutee, en dernier : premier plan
            ld a,5                      ; le vehicule repasse devant tout
            call veh_if
            jr .end
.frozen     ld a,(fz_n)                 ; quelques images encore : les ennemis recouverts par Papi (son effacement a sa mort)
            or a                        ; se redessinent, car la scene figee ne les repare plus
            jr z,.fz2
            dec a
            ld (fz_n),a
            call enemies_update
.fz2        call hud_update
            call sound_update
.end

            ld bc,#7F10                 ; calcul fini : bordure noire jusqu'au VBL
            out (c),c
            ld c,#54
            out (c),c
            jp main_loop

;------------------------------------------------------------------------------
; interruption (300 Hz) : sert seulement d'horloge.
;   tick = nombre de sixiemes d'image ecoules depuis le VBL (0 a 5).
;   C'est elle qui permet de savoir s'il reste du temps pour un ennemi de plus.
;------------------------------------------------------------------------------
int_handler:
            push af
            push bc
            ld b,#F5
            in a,(c)
            rra
            jr nc,.nv
            xor a                       ; celle qui tombe pendant le VBL remet a zero
            jr .st
.nv         ld a,(tick)
            inc a
.st         ld (tick),a
            ld a,(since)                ; tops depuis le debut de l'image en cours
            inc a
            ld (since),a
            pop bc
            pop af
            ei
            ret

;------------------------------------------------------------------------------
; tables construites au lancement
;------------------------------------------------------------------------------
; OCCY[y] : un sprite pose en y recouvre-t-il une ligne de tuiles qui contient
; un mur "devant" (bit 7 de la grille) ?  Sert a ne payer le cas lent que la.
build_occy:
            ld hl,GRID+16
            ld de,rowocc
            ld b,24
.ro         push bc
            ld b,16
            xor a
.rc         or (hl)
            inc hl
            djnz .rc
            and #80
            ld (de),a
            inc de
            pop bc
            djnz .ro
            ld hl,OCCY
.oy         ld a,l
            call .row
            ld c,a
            ld a,l
            add a,8
            call .row
            or c
            ld c,a
            ld a,l
            add a,11
            call .row
            or c
            ld (hl),a
            inc l
            ld a,l
            cp 192
            jr nz,.oy
            ret
.row        rrca
            rrca
            rrca
            and 31
            ld e,a
            ld d,0
            push hl
            ld hl,rowocc
            add hl,de
            ld a,(hl)
            pop hl
            ret

;------------------------------------------------------------------------------
; decor : ecran + miroir + grille de collision
;------------------------------------------------------------------------------
init_screen:
            ld hl,#C000
            ld de,#C001
            ld bc,#3FFF
            ld (hl),l
            ldir
            ld ix,tilemap
            ld c,0
.row        ld b,0
.col        push bc
            ld a,(ix+0)
            inc ix
            ld l,a
            ld h,0
            add hl,hl
            add hl,hl
            add hl,hl
            add hl,hl
            ld d,h
            ld e,l
            add hl,hl
            add hl,de                   ; x48
            ld de,tiles
            add hl,de
            ex de,hl                    ; DE = tuile
            ld a,8
.ln         ex af,af'
            push bc
            call scr_addr
            ex de,hl
            ld bc,6
            ldir
            ex de,hl
            pop bc
            inc c
            ex af,af'
            dec a
            jr nz,.ln
            pop bc
            ld a,b
            add a,6
            ld b,a
            cp 78
            jr nz,.col
            ld a,c
            add a,8
            ld c,a
            cp 192
            jr nz,.row
            ld hl,GRID                  ; grille de collision : bords pleins (#03), puis le type de chaque case
            ld de,GRID+1                ; (calcule d'apres la carte : 416 octets de moins en memoire)
            ld bc,415
            ld (hl),3
            ldir
            ld hl,tilemap
            ld de,GRID+16               ; ligne 1 de la grille (la ligne 0 est un bord)
            ld c,24
.gr         ld b,13
.gc         ld a,(hl)
            inc hl
            push hl
            ld l,a
            ld h,0
            push de
            ld de,tkind
            add hl,de
            pop de
            ld a,(hl)
            ld (de),a
            inc de
            pop hl
            djnz .gc
            inc de
            inc de
            inc de                      ; colonnes 13 a 15 : bord
            dec c
            jr nz,.gr
            ld hl,GRID+#200             ; champs de distances : "inconnu"
            ld de,GRID+#201
            ld bc,#3FF
            ld (hl),255
            ldir
            ld hl,#C000                 ; miroir = copie de l'ecran. EN DERNIER : il ecrase la zone de preparation
            ld de,#4000                 ; (tuiles, carte), qui occupe la meme region de memoire
            ld bc,#4000
            ldir
            ret

;------------------------------------------------------------------------------
; LECTEUR DE DISQUETTE (uPD765), sans AMSDOS : le jeu ecrase l'espace de travail du systeme.
;   Prototype teste a part (prototype_lecteur_disquette). Commandes d'un seul secteur : elles passent partout.
;   Les donnees sont en secteurs bruts, pistes COVER_TRK (cover) et ZONE1_TRK (zone) ; voir layout.inc.
;------------------------------------------------------------------------------
fdc_on:     ld a,(motor_on)
            or a
            jr nz,.rc                   ; deja en marche (demarre a la fin de la partie, ou apres la cover)
            ld bc,MOTOR
            ld a,1
            out (c),a
            ld (motor_on),a
            ld b,4                      ; le disque prend son regime : 4 x 0,25 s
.sp         push bc
            call fdc_delay
            pop bc
            djnz .sp
.rc         ld a,#07                    ; recalibrage
            call fdc_wr
            xor a
            call fdc_wr
            jr fdc_sense
fdc_off:    ld bc,MOTOR
            xor a
            out (c),a
            ld (motor_on),a
            ret
fdc_delay:  ld bc,#8000
.d          dec bc
            ld a,b
            or c
            jr nz,.d
            ret
fdc_wr:     push af                     ; envoie A au controleur (RQM = 1, DIO = 0)
            ld bc,#FB7E
.w          in a,(c)
            jp p,.w
            and #40
            jr nz,.w
            pop af
            inc c
            out (c),a
            ret
fdc_rd:     ld bc,#FB7E                 ; lit un octet du controleur (RQM = 1, DIO = 1)
.r          in a,(c)
            jp p,.r
            and #40
            jr z,.r
            inc c
            in a,(c)
            ret
fdc_seek:   ld (sk_trk),a               ; A = piste
            ld a,#0F
            call fdc_wr
            xor a
            call fdc_wr
            ld a,(sk_trk)
            call fdc_wr
fdc_sense:  ld de,0
.s          ld a,#08
            call fdc_wr
            call fdc_rd                 ; ST0
            cp #80
            jr nz,.got
            dec de                      ; pas d'interruption en attente : on recommence (avec une limite)
            ld a,d
            or e
            jr nz,.s
            ret
.got        push af
            call fdc_rd                 ; piste courante
            pop af
            and #20                     ; fin de deplacement ?
            jr z,fdc_sense
            ret
; lit un secteur : A = piste, D = E = identifiant du secteur, HL = destination -> HL = fin ; resultat en fdc_res
fdc_read:   ld (rd_trk),a
            ld a,d
            ld (rd_r),a
            ld a,e
            ld (rd_eot),a
            push hl
            ld a,#46                    ; lecture, double densite
            call fdc_wr
            xor a                       ; tete 0, unite 0
            call fdc_wr
            ld a,(rd_trk)
            call fdc_wr
            xor a
            call fdc_wr                 ; H = 0
            ld a,(rd_r)
            call fdc_wr
            ld a,2
            call fdc_wr                 ; N = 2 : 512 octets
            ld a,(rd_eot)
            call fdc_wr
            ld a,#2A
            call fdc_wr                 ; GPL
            ld a,#FF
            call fdc_wr                 ; DTL
            pop hl
            ld bc,#FB7E
.x          in a,(c)                    ; un octet toutes les 32 microsecondes : boucle serree
            jp p,.x
            and #20
            jr z,.res
            inc c
            in a,(c)
            ld (hl),a
            inc hl
            dec c
            jr .x
.res        ld iy,fdc_res
            ld b,7
.rl         push bc
            call fdc_rd
            pop bc
            ld (iy+0),a
            inc iy
            djnz .rl
            ret
; A = piste, B = indice du secteur dans la piste (0..8), DE = nombre de secteurs, HL = destination
load_data:  ld (ld_trk),a
            ld a,b
            ld (ld_idx),a
            ld (ld_cnt),de
            ld (ld_dst),hl
            ld a,(ld_trk)
            call fdc_seek
.next       xor a
            ld (ld_try),a
.again      ld a,(ld_idx)
            add a,#C1
            ld d,a
            ld e,a
            ld a,(ld_trk)
            ld hl,(ld_dst)
            call fdc_read
            ld a,(fdc_res+1)            ; ST1 : erreur de lecture ? (le bit 7, fin de cylindre, est normal)
            and #37
            jr z,.ok
            ld a,(ld_try)
            inc a
            ld (ld_try),a
            cp 4
            jr c,.again                 ; on relit le meme secteur, 4 essais au plus
.ok         ld (ld_dst),hl
            ld a,(ld_idx)
            inc a
            cp 9
            jr nz,.same
            xor a
            ld (ld_idx),a
            ld a,(ld_trk)
            inc a
            ld (ld_trk),a
            call fdc_seek
            jr .cnt
.same       ld (ld_idx),a
.cnt        ld hl,(ld_cnt)
            dec hl
            ld (ld_cnt),hl
            ld a,h
            or l
            jr nz,.next
            ret

; decompresseur (format de tools/convert.py, proche de LZ4) : HL = source, DE = destination
unpack:
.tok        ld a,(hl)
            inc hl
            ld (lz_tok),a
            rrca
            rrca
            rrca
            rrca
            and 15
            call lz_len                 ; BC = nombre de litteraux
            ld a,b
            or c
            jr z,.nl
            ldir
.nl         ld c,(hl)                   ; decalage de la copie (0 = fin)
            inc hl
            ld b,(hl)
            inc hl
            ld a,b
            or c
            ret z
            ld (lz_off),bc
            ld a,(lz_tok)
            and 15
            call lz_len
            ld a,c
            add a,4
            ld c,a
            jr nc,.m4
            inc b
.m4         push hl                     ; source
            ld hl,(lz_off)
            push de
            ex de,hl                    ; HL = destination, DE = decalage
            or a
            sbc hl,de                   ; HL = octets deja ecrits a recopier
            pop de
            ldir
            pop hl
            jr .tok
lz_len:     ld c,a                      ; A = quartet ; si 15, des octets de suite s'ajoutent (tant qu'ils valent 255)
            ld b,0
            cp 15
            ret nz
.e          ld a,(hl)
            inc hl
            push af
            add a,c
            ld c,a
            jr nc,.n
            inc b
.n          pop af
            inc a
            jr z,.e
            ret

; charge la zone zone_cur : lecture (compressee, sur place), decompression dans ZSTAGE, puis on la range :
; parametres, caracteristiques des places d'ennemis, points d'apparition, tables d'images et sprites des unites
; (dans les trous de la page video A, a partir de l'emplacement 34)
load_zone_data:
            ld a,(zone_cur)
            ld e,a
            add a,a
            add a,a
            add a,e                     ; x5
            ld e,a
            ld d,0
            ld hl,zone_dir
            add hl,de
            ld a,(hl)                   ; piste
            inc hl
            ld b,(hl)                   ; secteur
            inc hl
            ld e,(hl)                   ; nombre de secteurs
            ld d,0
            inc hl
            ld c,(hl)
            inc hl
            ld h,(hl)
            ld l,c                      ; HL = adresse de lecture
            push hl
            call load_data
            pop hl
            ld de,ZSTAGE
            call unpack
            ld a,(ZSTAGE)
            ld (nb_wanted),a
            ld a,(ZSTAGE+1)
            ld (zone_kills),a
            ld a,(ZSTAGE+5)             ; 1 : mission Time Attack (zone_kills = secondes a survivre)
            ld (mtime),a
            ld a,(ZSTAGE+4)             ; nombre de points d'apparition
            ld (spawn_n),a
            ld hl,ZSTAGE+16
            ld de,slot_type
            ld bc,72
            ldir
            ld hl,ZSTAGE+Z_SPAWN
            ld de,spawn_tab
            ld bc,32
            ldir
            ld hl,ZSTAGE+Z_FRAMES       ; tables d'images : soldat, officier, general (ou corps du boss : un boss n'a pas de generals), puis la tete du boss
            ld de,soldat_frames         ; (les trois premieres se suivent en memoire)
            ld bc,216
            ldir
            ld de,boss_frames
            ld bc,72
            ldir
            ld a,(ZSTAGE+2)             ; nombre d'images de sprites des unites
            ld b,a
            ld hl,ZSTAGE+Z_SPR
            ld de,ZSPR_DST              ; emplacement 35 = trou 2, rang 9
            ld c,ZSPR_C                 ; images restant dans ce trou
.f          push bc
            ld bc,144
            ldir
            pop bc
            dec c
            jr nz,.nh
            ld c,SPRSLOT
            ld a,e
            add a,#B0                   ; trou suivant : 2048 - 13 x 144 = 176
            ld e,a
            jr nc,.nh
            inc d
.nh         djnz .f
            ld a,(ZSTAGE+6)             ; images supplementaires (emplacements de la partie permanente, voir XSLOT_BASE)
            or a
            jr z,.nx
            ld b,a
            ld de,XSLOT_BASE
.ex         push bc
            ld bc,144
            ldir
            pop bc
            djnz .ex
.nx         ld hl,ZSTAGE+Z_ICON         ; icone de la mission (tuile 8x8 du HUD) : "tuer" ou "tuer le boss"
            ld de,TILE_BASE+32
            ld bc,32
            ldir
            ld hl,CRATE_IMG             ; la caisse de grenades reprend son image (le Z80 de la mission precedente l'avait remplacee)
            ld (crate_frame),hl
            ld a,(ZSTAGE+95)            ; zone a vehicules : mode de la mission
            ld (veh_on),a
            ld hl,ZSTAGE+8              ; seuils de couleur de la barre de vie du boss (0 : pas de boss), mission Z80 et son image, parametres du boss
            ld de,hp_thr
            ld bc,8
            ldir
            jp wtr_load                 ; eau : parametres de la zone (water.asm)
load_zone:  call fdc_on
            call load_zone_data
            jp fdc_off

;------------------------------------------------------------------------------
; etat initial
;------------------------------------------------------------------------------
init_game:
            ld hl,vars
            ld de,vars+1
            ld bc,vars_end-vars-1
            ld (hl),0
            ldir
            ld hl,enemies               ; les fiches ennemis ne sont plus dans 'vars'
            ld de,enemies+1
            ld bc,MAXENEMY*ESIZE-1
            ld (hl),0
            ldir
            ld a,(zone_kills)           ; ennemis a abattre (parametre de la zone, lu par load_zone_data)
            ld (kills_left),a
            ld a,50
            ld (time_f),a
            ld a,(mtime)                ; tuile du HUD : 2 (tuer) ou 3 (Time Attack)
            add a,2
            ld (hud_tile),a
            ld a,GREN_START
            ld (grenades),a
            ld a,3                      ; partie neuve : 3 vies
            ld (lives),a
            ld a,(carry)                ; zone suivante : on reprend le score et les vies
            or a
            jr z,.nc
            xor a
            ld (carry),a
            ld a,(lives_keep)
            ld (lives),a
            ld hl,score_keep
            ld de,score
            ld bc,5
            ldir
            ld hl,score                 ; les tranches de 250 points deja franchies ne redonnent pas de vie
            ld de,life_k
            ld bc,3
            ldir
            call life_flag
            ld (life_h),a
.nc            ld a,36
            ld (p_x),a
            ld a,PAPI_Y0
            ld (p_y),a
            ld a,#FF
            ld (p_ox),a
            ld a,3
            ld (p_dir),a                ; vers le haut
            ld (p_state),a              ; 3 = Papi entre dans la carte (voir player_enter)
            ld (p_timer),a
            ld hl,#ACE1
            ld (seed),hl
            ld a,2
            ld (ff_front),a
            ld a,5
            ld (since),a
            ; les ennemis attendent leur tour d'entree, decales les uns des autres
            ld ix,enemies
            ld b,MAXENEMY
            ld a,12
.en         ld (ix+E_TIMER),a
            ld (ix+E_OX),#FF
            add a,10                    ; arrivee initiale : toutes les 10 images (9 avant, +15 %)
            ld de,ESIZE
            add ix,de
            djnz .en
            ld hl,bullets               ; table des balles (hors de 'vars') a remettre a zero
            ld de,bullets+1
            ld bc,NBUL*BSIZE-1
            ld (hl),0
            ldir
            ld ix,bullets
            ld b,NBUL
.bu         ld (ix+B_OX),#FF
            ld de,BSIZE
            add ix,de
            djnz .bu
            ld a,31
            ld (hud_dirty),a
            ld hl,txt_hud
            ld bc,#00C1                 ; x=0, y=193
            jp print_text

;------------------------------------------------------------------------------
; clavier + joystick -> (joy) : bit0 haut, 1 bas, 2 gauche, 3 droite, 4 tir ; le bit 5 (grenade)
; est positionne par player_update apres un appui long sur tir
;------------------------------------------------------------------------------
keyscan:
            ld hl,keymap
            ld bc,#F782
            out (c),c
            ld bc,#F40E
            ld e,b
            out (c),c
            ld bc,#F6C0
            ld d,b
            out (c),c
            ld c,0
            out (c),c
            ld bc,#F792
            out (c),c
            ld a,#40
            ld c,#4A
.loop       ld b,d
            out (c),a
            ld b,e
            ini
            inc a
            cp c
            jr c,.loop
            ld bc,#F782
            out (c),c

            ld a,(keymap+9)             ; joystick 0 : directions et tir (plus de grenade directe)
            cpl
            and #1F
            ld c,a
.k0         ld a,(keymap+0)             ; curseur haut/droite/bas
            cpl
            ld b,a
            rra                         ; bit0 = haut
            jr nc,.k1
            set 0,c
.k1         bit 2,b
            jr z,.k2
            set 1,c
.k2         bit 1,b
            jr z,.k3
            set 3,c
.k3         ld a,(keymap+1)
            cpl
            ld b,a
            bit 0,b                     ; curseur gauche
            jr z,.k4
            set 2,c
.k4         bit 1,b                     ; COPY
            jr z,.k5
            set 4,c
.k5         ld a,(keymap+5)
            rla                         ; ESPACE (bit 7, 0 = appuye)
            jr c,.k6
            set 4,c
.k6         ld a,c
            ld (joy),a

            ifdef CHEATS                ; version de TEST seulement : touche M = jauge de charge
            ; touche M (jauge de charge), sur front montant
            ld a,(keymap+4)
            cpl
            and #40
            ld b,a
            ld hl,oldkeys
            ld a,(hl)
            ld (hl),b
            cpl
            and b
            ret z
            ld hl,meter
            ld a,(hl)
            cpl                         ; (0 <-> #FF : seul 'nul ou non' compte)
            ld (hl),a
            ret
            else
            ret
            endif

;------------------------------------------------------------------------------
; case de la grille sous le point (B = x octets, C = y lignes) -> HL
;   conserve BC, DE
;------------------------------------------------------------------------------
cell_ptr:
            ld h,hi(COLTAB)
            ld l,b
            ld l,(hl)                   ; colonne
            ld a,c
            and #F8
            add a,8
            add a,a                     ; (ligne+1) x 16, retenue = page
            ld h,hi(GRID)
            jr nc,.p0
            inc h
.p0         or l
            ld l,a
            ret

;------------------------------------------------------------------------------
; Papi peut-il se tenir en (B = x, C = y) ?
;   on teste la "ligne des pieds" : 2 points espaces de 3 octets, 10 lignes
;   sous le haut du sprite.     sortie : Z = libre.     conserve BC, DE
;------------------------------------------------------------------------------
can_stand_p:
            ld a,b
            cp XMAX+1
            jr nc,.no
            ld a,c
            cp YMAX+1
            jr nc,.no
            ld h,hi(COLTAB)
            ld l,b
            inc l
            ld a,(hl)
            ex af,af'                   ; A' = colonne du point gauche
            inc l
            inc l
            inc l
            ld l,(hl)                   ; L = colonne du point droit
            ld a,c
            add a,10
            and #F8
            add a,8
            add a,a
            ld h,hi(GRID)
            jr nc,.p0
            inc h
.p0         or l
            ld l,a
            bit 0,(hl)
            ret nz
            ld a,l
            and #F0
            ld l,a
            ex af,af'
            or l
            ld l,a
            bit 0,(hl)
            ret
.no         or 1
            ret

;------------------------------------------------------------------------------
; OCCUPATION DE LA GRILLE PAR LES ENNEMIS
;   Un ennemi reserve (bit 6) toutes les cases de 6x8 que son sprite touche :
;   1 ou 2 colonnes, 2 ou 3 lignes. Avant d'avancer il verifie que les cases
;   de sa nouvelle position sont libres : deux ennemis ne se superposent donc
;   jamais (et on n'a jamais a comparer les ennemis entre eux).
;   Par rapport a la ligne de cases des pieds (y+10), le sprite couvre toujours
;   celle du dessus, plus une 3e : au-dessous si y mod 8 = 5, au-dessus si 6 ou 7.
;------------------------------------------------------------------------------
            macro UP16
            ld a,l
            sub 16
            ld l,a
            jr nc,@u
            dec h
@u
            mend

            ; {op} = set ou res ; HL = case pieds-gauche, C = y, Z si une seule colonne
            macro MARKROW op,two
            {op} 6,(hl)
            if {two}
              inc l
              {op} 6,(hl)
              dec l
            endif
            mend

            macro MARKALL op,two
            MARKROW {op},{two}
            UP16
            MARKROW {op},{two}
            ld a,c
            and 7
            cp 5
            ret c
            jr z,@below
            UP16
            MARKROW {op},{two}
            ret
@below      ld a,l
            add a,32
            ld l,a
            jr nc,@b
            inc h
@b          MARKROW {op},{two}
            ret
            mend

            macro TESTROW bits,two
            ld a,(hl)
            and {bits}
            ret nz
            if {two}
              inc l
              ld a,(hl)
              and {bits}
              ret nz
              dec l
            endif
            mend

            macro TESTALL two
            TESTROW #49,{two}           ; ligne des pieds : murs + eau + ennemis
            UP16
            TESTROW #40,{two}           ; au-dessus : ennemis seulement
            ld a,c
            and 7
            cp 5
            jr c,@free
            jr z,@below
            UP16
            TESTROW #40,{two}
            xor a                       ; libre -> Z. (Le "dec l" qui termine TESTROW modifie les
            ret                         ; indicateurs : sans ce "xor a", un sprite sur 2 colonnes
@below      ld a,l                      ; etait toujours refuse aux lignes y mod 8 = 5, 6, 7 -- les
            add a,32                    ; ennemis marchaient "en escalier", bloques jusqu'a ce que
            ld l,a                      ; leur x retombe sur une colonne de tuile.)
            jr nc,@b
            inc h
@b          TESTROW #40,{two}
            xor a
            ret
@free       xor a
            ret
            mend

; un ennemi peut-il se tenir en (B = x, C = y) ?   Z = oui.   conserve BC, D
can_stand_e:
            ld a,b
            cp XMAX+1
            jr nc,.no
            ld a,c
            cp YMAX+1
            jr nc,.no
            ld a,(ymin)                 ; le corps du boss reste a 12 lignes ou plus du haut (sa tete tient au-dessus)
            cp c
            jr z,.in
            jr c,.in
.no         or 1
            ret
.in         call feet_cell
            jr nz,.two
            TESTALL 0
.two        TESTALL 1

; -> HL = case pieds-gauche, Z si le sprite tient dans une colonne.  conserve BC, D
feet_cell:
            ld h,hi(MOD6)
            ld l,b
            ld a,(hl)
            ex af,af'                   ; A' = x mod 6
            dec h                       ; COLTAB est juste avant MOD6
            ld e,(hl)
            ld a,c
            add a,10
            and #F8
            add a,8
            add a,a
            ld h,hi(GRID)
            jr nc,.p
            inc h
.p          or e
            ld l,a
            ex af,af'
            or a
            ret

; libere les cases de l'ennemi IX (a appeler avant de modifier E_X / E_Y)
enemy_free:
            ld l,(ix+E_CELL)
            ld h,(ix+E_CELL+1)
            ld c,(ix+E_Y)
            ld d,hi(MOD6)
            ld e,(ix+E_X)
            ld a,(de)
            or a
            jr nz,.two
            MARKALL res,0
.two        MARKALL res,1

; reserve les cases de l'ennemi IX en (B = x, C = y).   conserve BC
enemy_claim:
            call feet_cell
            ld (ix+E_CELL),l
            ld (ix+E_CELL+1),h
            jr nz,.two
            MARKALL set,0
.two        MARKALL set,1

;------------------------------------------------------------------------------
; PAPI
;------------------------------------------------------------------------------
player_update:
            ld a,(p_state)
            or a
            jr z,.alive
            cp 3
            jp nz,player_dying
            jp player_enter
.alive
            ld a,(joy)
            ld c,a
            ld de,0                     ; D = sx, E = sy
            ld b,4                      ; index (sy+1)*3 + (sx+1)
            bit 0,c
            jr z,.j1
            dec e
            ld b,1
.j1         bit 1,c
            jr z,.j2
            inc e
            ld a,b
            add a,3
            ld b,a
.j2         bit 2,c
            jr z,.j3
            dec d
            dec b
.j3         bit 3,c
            jr z,.j4
            inc d
            inc b
.j4         ld a,d
            or e
            jp z,.still
            ld a,b
            ld hl,dir_tab
            add a,l
            ld l,a
            jr nc,.j5
            inc h
.j5         ld a,(hl)
            cp 8
            jr nc,.j6
            ld (p_dir),a
.j6         ld hl,p_atick               ; animation : 10 images/s
            inc (hl)
            ld a,(hl)
            cp 5
            jr c,.j7
            ld (hl),0
            ld a,(p_anim)
            inc a
            and 3
            ld (p_anim),a
.j7         ld bc,(p_y)                 ; C = y, B = x  (p_y puis p_x en memoire)
            ; horizontal : cumul de vitesse (0,35 octet par image)
            ld a,d
            or a
            jr z,.movy
            ld a,(p_fx)
psx         equ $+1                     ; (eau : wtr_tick modifie l'operande ci-dessous, vitesse -25 %)
            add a,PSPEED_X
            ld (p_fx),a
            jr nc,.movy
            ld a,d
            add a,b
            ld b,a
            call can_stand_p
            jr z,.xok
            ld a,(p_x)
            ld b,a
.xok        ld a,b
            ld (p_x),a
.movy       ld a,e                      ; vertical : cumul de vitesse (0,7 ligne par image)
            or a
            jr z,.still
            ld a,(p_fy)
psy         equ $+1
            add a,PSPEED_Y
            ld (p_fy),a
            jr nc,.still
            ld a,e
            add a,c
            ld c,a
            call can_stand_p
            jr z,.yok
            ; bloque : si un seul des deux pieds bute, on glisse d'un octet du
            ; cote libre (on passe les coins et les portes sans viser au pixel)
            ld a,c
            add a,10
            ld c,a
            inc b
            call cell_ptr
            ld d,0
            bit 0,(hl)
            jr z,.s1
            inc d                       ; pied gauche bloque
.s1         ld a,b
            add a,3
            ld b,a
            call cell_ptr
            bit 0,(hl)
            jr z,.s2
            set 1,d                     ; pied droit bloque
.s2         ld bc,(p_y)
            ld a,d
            dec a
            jr z,.sr
            dec a
            jr nz,.still
            dec b                       ; vers la gauche
            jr .st
.sr         inc b                       ; vers la droite
.st         call can_stand_p
            jr nz,.still
            ld a,b
            ld (p_x),a
            jr .still
.yok        ld a,c
            ld (p_y),a
.still
            ld a,(joy)                  ; une seule touche : une balle par appui, ou la grenade si l'appui dure
            bit 4,a
            jr nz,.hld
            ld hl,p_hold                ; touche relachee : on repart de zero (p_hold puis p_lock)
            ld (hl),0
            inc hl
            ld (hl),0
            jr .nofire
.hld        ld hl,p_lock
            ld a,(hl)
            or a
            jr nz,.nofire               ; appui long deja utilise : rien avant le relachement
            dec hl
            inc (hl)                    ; images d'appui
            ld a,(hl)
            dec a                       ; (A = images d'appui - 1)
            jr nz,.hl2
            call player_fire            ; une balle, des le debut de l'appui
            jr .nofire
.hl2        cp GRENADE_HOLD-1
            jr c,.nofire
            inc hl
            ld (hl),1                   ; verrou : plus rien avant le relachement
            ld a,(joy)
            xor #30                     ; bit 4 (tir) -> 0, bit 5 (grenade) -> 1 : grenade_update la lance
            ld (joy),a
.nofire
            ld hl,p_inv                 ; invincibilite apres une vie perdue
            ld a,(hl)
            or a
            jr z,player_draw
            dec (hl)
            and 4                       ; clignote
            jr z,player_draw
            jp player_hide

; Papi apparait en bas de la carte et avance de 8 lignes tout seul. Pendant ce
; temps pas de tir, pas de grenade, et les ennemis n'entrent pas encore.
player_enter:
            ld hl,p_atick               ; animation de marche
            inc (hl)
            ld a,(hl)
            cp 5
            jr c,.e1
            ld (hl),0
            ld a,(p_anim)
            inc a
            and 3
            ld (p_anim),a
.e1         ld hl,p_timer
            dec (hl)
            jr nz,player_draw
            ld (hl),3
            ld hl,p_y
            dec (hl)
            ld a,(hl)
            cp PAPI_Y1
            jr nz,player_draw
            xor a
            ld (p_state),a              ; Papi est entre : le jeu commence, les ennemis viennent
            jr player_draw

player_draw:
            ld a,(p_dir)
            add a,a
            add a,a
            ld hl,p_anim
            add a,(hl)
player_draw_frame:
            ld hl,papi_frames
            call frame_ptr
            call wtr_frame              ; dans l'eau : image sans les jambes
            ld bc,(p_y)
            ld de,(p_oy)
            ld (p_oy),bc
            jp draw_sprite

player_hide:
            ld a,(p_ox)
            cp #FF
            ret z
            ld b,a
            ld a,(p_oy)
            ld c,a
            ld a,#FF
            ld (p_ox),a
            call wake_12                ; son effacement abime les ennemis qu'il recouvre (colles a lui) : ils se redessinent
            ld de,#060C
            jp restore_xy

player_dying:
            dec a
            jr nz,.over
            ld hl,p_timer               ; animation de mort : 4 images
            dec (hl)
            ld a,(hl)
            jr z,.dead
            rrca
            rrca
            rrca
            and 3
            xor 3
            add a,32
            jp player_draw_frame
.dead       call player_hide
            ld hl,lives
            dec (hl)
            ld hl,hud_dirty
            set 1,(hl)
            jr z,.gameover
            xor a
            ld (p_state),a              ; Papi reapparait la ou il est mort (p_x, p_y, p_dir inchanges)
            ld a,100                    ; invincibilite apres une mort : 100 images = 2 s
            ld (p_inv),a
            ret
.gameover   call check_hi               ; meilleur score (le HUD le redessine)
            call freeze_redraw
            ld hl,txt_over
            ld bc,17*256+84
            ld d,20                     ; GAME OVER : le jingle demarre apres 0,4 s
            ld a,#0C                    ; rouge vif
            jp end_game
.over       ld hl,p_timer               ; partie finie : tir pour recommencer
            ld a,(hl)
            or a
            jr z,.wait
            dec (hl)
            ret
.wait       ld a,(won)                  ; zone terminee : zone suivante toute seule ; partie perdue : jingle (overlay), puis menu principal
            or a
            jp nz,new_game
            di
            ld a,CFG_GO
            ld hl,GO_LOAD
            call ovl_go
            jp menu_enter

; Papi est touche (par une balle ou un ennemi).  conserve BC, DE, HL
player_hit:
            ld a,(p_state)
            or a
            ret nz
            ld a,(p_inv)
            or a
            ret nz
            ld a,1
            ld (p_state),a
            ld a,32
            ld (p_timer),a
            ld a,2
            jp sfx

player_fire:
            ld ix,bullets
            ld b,4
.find       ld a,(ix+B_ON)
            or a
            jr z,.free
            ld de,BSIZE
            add ix,de
            djnz .find
            ret
.free       xor a                       ; classe de portee 0 : Papi
            ld (shot_cls),a
            ld a,(p_dir)
            ld hl,(p_y)                 ; L = y, H = x
            push af
            push hl
            call bullet_start
            jr nz,.nf
            pop hl
            pop af
            call bullet_cover           ; colle a un obstacle rouge : tir en couverture
            ld a,1
            jp sfx
.nf         pop hl
            pop af
            ret

;------------------------------------------------------------------------------
; lance une balle : IX = case libre, A = direction, H = x, L = y du tireur
;   sortie Z = balle partie
;------------------------------------------------------------------------------
bullet_start:
            add a,a
            add a,a
            ld e,a
            ld d,0
            ex de,hl                    ; D = x, E = y
            ld bc,shot_tab
            add hl,bc
            ld a,(hl)                   ; decalage de depart x
            add a,d
            cp 78
            jr nc,.out
            ld (ix+B_X),a
            inc hl
            ld a,(hl)
            add a,e
            cp 187
            jr nc,.out
            ld (ix+B_Y),a
            inc hl
            ld a,(hl)
            ld (ix+B_DX),a
            inc hl
            ld a,(hl)
            ld (ix+B_DY),a
            ld (ix+B_OX),#FF
            xor a
            ld (ix+B_ACC),a
            ld (ix+B_AGE),a
            ld (ix+B_PASS),a
            ld a,(shot_cls)             ; portee : pas de la classe du tireur, horizontal ou autre (rng_tab : 2 octets par classe)
            add a,a
            ld e,a
            ld d,0
            ld hl,rng_tab
            add hl,de
            ld a,(ix+B_DY)
            or a
            jr z,.rh
            inc hl
.rh         ld a,(hl)
            ld (ix+B_RNG),a
            ld (ix+B_ON),1
            xor a                       ; sortie Z = balle partie (le test de DY laissait NZ pour les tirs verticaux : ni son, ni demi-pas)
            ret
.out        or 1
            ret

; portee des balles, en pas (une balle de Papi fait 4 px de large / 6 de haut par pas, celles des ennemis la moitie) :
; Papi 76 px, soldat 68, officier 76, general 85, boss 94 (cahier du 20/10 moins 15 %), vehicule infinie.  Par classe : pas horizontaux, pas verticaux ou diagonaux
rng_tab:    db 21,14, 34,23, 38,25, 42,28, 47,31, 255,255, 254,254, 254,254       ; (classes 6 et 7 : le sniper, portee quasi illimitee ; 254 : sa balle va a la vitesse de Papi)

; tir en couverture de Papi : A = direction, H = x, L = y du tireur, IX = balle qui vient de partir.
; Si la case JUSTE a cote de son corps, dans la direction du tir, est un mur rouge (il est colle a l'obstacle),
; sa balle traverse ce mur (quelques pas) ; sinon le mur l'arrete comme d'habitude.
bullet_cover:
            add a,a
            ld e,a
            ld d,0
            push hl
            ld hl,adj_tab
            add hl,de
            ld a,(hl)
            inc hl
            ld c,(hl)
            pop hl
            add a,h
            ld b,a                      ; B = x de la case voisine
            ld a,c
            add a,l
            ld c,a                      ; C = y de la case voisine
            call cell_ptr
            ld a,(hl)
            bit 1,a
            ret z                       ; pas colle a un mur rouge
            bit 2,a
            ret nz                      ; une caserne : jamais traversee
            ld a,(ix+B_DY)              ; pas a traverser : une case de 8 lignes ou 6 octets
            bit 7,a
            jr z,.p
            neg
.p          cp 4
            ld a,3
            jr c,.s
            ld a,2                      ; balle verticale rapide (6 lignes par pas)
.s          ld (ix+B_PASS),a
            ret

; par direction : depart x, depart y, vitesse x (octets), vitesse y (lignes)
shot_tab:   db 6,3, 2,0                 ; 0 droite
            db -1,3, -2,0               ; 1 gauche
            db 3,12, 0,6                ; 2 bas
            db 3,-6, 0,-6               ; 3 haut
            db 6,9, 2,4                 ; 4 bas-droite
            db -1,9, -2,4               ; 5 bas-gauche
            db 6,-3, 2,-4               ; 6 haut-droite
            db -1,-3, -2,-4             ; 7 haut-gauche
; par direction : decalage (x, y) de la case voisine, juste a cote du corps du tireur (sprite 6 x 12)
adj_tab:    db 6,7, -1,7, 3,12, 3,-1, 6,12, -1,12, 6,-1, -1,-1

; (sy+1)*3 + (sx+1) -> direction (ordre des lignes de la planche de sprites)
dir_tab:    db 7,3,6, 1,8,0, 5,2,4
; direction -> dx, dy
dir_vec:    db 1,0, -1,0, 0,1, 0,-1, 1,1, -1,1, 1,-1, -1,-1

;------------------------------------------------------------------------------
; BALLES
;------------------------------------------------------------------------------
bullets_update:
            ld ix,bullets
            xor a
.loop       ld (bul_n),a
            ld a,(ix+B_ON)
            or a
            jp z,.next
            dec a
            jp nz,.k2                   ; 2 = touchee, a effacer ; 3 = eclat
            ld a,(bul_n)
            cp 4
            jr c,.pb
            ld a,(ix+B_RNG)             ; portee 254 : balle de sniper, a la vitesse de Papi
            cp 254
            ld a,EBUL_SPEED             ; balles ennemies : 60 % des images, d'un pas moitie moins long
            jr nz,.sp
            ld a,SBUL_SPEED             ; sniper : pas entier comme Papi, mais 25 % moins vite
            jr .sp
.pb         ld a,PBUL_SPEED             ; balles de Papi : 70 % des images
.sp         add a,(ix+B_ACC)
            ld (ix+B_ACC),a
            jp nc,.next
            inc (ix+B_AGE)              ; age de la balle, en pas
            ld a,(ix+B_X)
            add a,(ix+B_DX)
            cp 78
            jp nc,.kill
            ld b,a
            ld a,(ix+B_Y)
            add a,(ix+B_DY)
            cp 187
            jp nc,.kill
            ld c,a
            ld (ix+B_X),b
            ld (ix+B_Y),c
            ld a,(ix+B_DY)
            or a
            jr nz,.cp0
            push bc                     ; tir horizontal : la balle roule dans la ligne de
            ld a,c                      ; cases des PIEDS du tireur (y + 7 : le depart est a
            add a,7                     ; y + 3 et les pieds a y + 10). Un tireur qui longe un
            ld c,a                      ; mur rouge n'a plus sa balle arretee par la tuile
            call cell_ptr               ; qui est juste a cote de son corps.
            pop bc
            jr .cp1
.cp0        call cell_ptr
.cp1        ld a,(hl)
            or a
            jp p,.ck
            push hl                     ; case d'avant-plan : si l'obstacle juste dessous arrete les balles, le tile d'avant-plan en fait
            ld de,16                    ; partie (le dessus du mur) : la balle ne le traverse pas non plus
            add hl,de
            ld a,(hl)
            pop hl
            and 2
            jr nz,.ck
            ld a,(hl)
.ck         bit 1,a                     ; decor qui arrete les balles...
            jr z,.nowall
            bit 2,a                     ; une caserne arrete TOUTES les balles (meme celle d'un tireur a couvert)
            jp nz,.impact
            ld a,(ix+B_PASS)            ; ...sauf pour un tireur colle a son obstacle : sa balle le traverse
            or a
            jp z,.impact
            jr .np                      ; (dans le mur, la fenetre reste ouverte : un obstacle epais est traverse en entier)
.nowall     ld a,(ix+B_PASS)
            or a
            jr z,.np
            dec (ix+B_PASS)             ; hors du mur, elle se referme au bout de quelques pas
.np         xor a
            ld (bul_hide),a             ; (l'avant-plan jaune ne cache pas les balles)
            ld a,(bul_n)
            cp 4
            jr c,.mine
            ld a,(ix+B_AGE)             ; une balle toute jeune sort de son tireur : jamais cachee
            cp 8                        ; (ses propres cases reservees la cachaient, d'ou un depart
            jr c,.e2                    ; quelques pixels trop loin)
            ld a,(hl)                   ; une balle ennemie passe aussi DERRIERE les
            and #40                     ; autres ennemis (cases reservees) : elle ne
            jr nz,.eh                   ; les abime pas en les traversant
            push bc
            ld a,c
            add a,5
            ld c,a
            call cell_ptr
            pop bc
            ld a,(hl)
            and #40
            jr z,.e2
.eh         ld (bul_hide),a
.e2         call bullet_vs_player
            jr .hit
.mine       call bullet_vs_enemies
.hit        call wake_enemies           ; ceux qui sont venus se placer sous l'ancienne position se redessinent
            call bullet_erase
            ld a,(ix+B_ON)
            dec a
            jp nz,.next
            ld a,(ix+B_AGE)             ; au bout de sa portee : la balle eclate (cachee derriere un ennemi : elle disparait)
            cp (ix+B_RNG)
            jr c,.inr
            ld a,(bul_hide)
            or a
            jp nz,.kill
            ld (ix+B_ON),3
            ld (ix+B_AGE),0
            jr .next
.inr        ld a,(bul_hide)
            or a
            jr nz,.next
.draw       ld b,(ix+B_X)
            ld c,(ix+B_Y)
            ld (ix+B_OX),b
            ld (ix+B_OY),c
            call scr_addr
            call draw_bullet
            jr .next
.k2         dec a
            jr z,.kill
            ld a,(ix+B_AGE)             ; eclat : 3 images de 2 pas d'affichage (B_AGE = 0..6)
            inc (ix+B_AGE)
            srl a
            jr c,.next
            call wake_enemies           ; (l'image precedente s'efface, les ennemis dessous se redessinent)
            call eclat_erase
            ld a,(ix+B_AGE)
            srl a                       ; (rra ramenait la retenue dans le bit 7 : image 3 jamais atteinte, eclat figé, image au hasard)
            cp 3
            jr z,.kill
            ld e,a
            add a,a
            add a,e
            add a,a
            add a,a
            add a,a                     ; x 24
            ld e,a
            ld d,0
            ld hl,spr_eclat
            add hl,de
            ex de,hl
            ld b,(ix+B_X)
            ld c,(ix+B_Y)
            ld (ix+B_OX),b
            ld (ix+B_OY),c
            call scr_addr
            call draw_gdat
            jr .next
            ; (HL = case de la grille)
.impact     bit 2,(hl)                  ; un bidon explosif (ou une caserne : le module regarde veh_on) : un coup de plus (module des vehicules)
            ld a,4
            call nz,veh_call
            call wake_enemies           ; impact sur un obstacle : la balle s'efface et son eclat s'affiche (meme animation qu'en fin de portee)
            call bullet_erase
            ld (ix+B_ON),3
            ld (ix+B_AGE),0
            jr .next
.kill       call wake_enemies           ; l'effacement peut abimer un sprite (le tireur, ou un ennemi arrive depuis)
            call bullet_erase
            ld (ix+B_ON),0
.next       ld de,BSIZE
            add ix,de
            ld a,(bul_n)
            inc a
            cp NBUL
            jp nz,.loop
            ret

; force le redessin des ennemis qui recouvrent l'ancienne position de la balle IX : l'effacement de la
; balle restituerait le decor sous un octet de leur sprite (la balle ennemie part de l'origine du sprite)
wake_enemies:                           ; IX = balle : son ancienne position (tous les tireurs, balles de Papi comprises)
            ld b,(ix+B_OX)
            ld c,(ix+B_OY)
            ld a,b
            inc a
            ret z                       ; pas dessinee : rien a effacer
            call cell_ptr               ; test bon marche : aucune des deux cases (haut et bas de la balle) n'est
            ld a,(hl)                   ; reservee par un ennemi -> aucun sprite n'est touche
            and #40
            jr nz,wake_rect
            ld a,c
            add a,5
            ld c,a
            call cell_ptr
            ld a,c
            sub 5
            ld c,a
            ld a,(hl)
            and #40
            ret z
; B = x, C = y : coin d'un rectangle de 2 octets x 6 lignes (balle, grenade) qu'on va effacer. Les ennemis qui
; le recouvrent se redessinent a leur prochain tour. conserve BC, IX ; clobbers A, DE, H, IY
wake_rect:
            ld iy,enemies
            ld h,MAXENEMY
            ld de,ESIZE
.w          ld a,b
            sub (iy+E_X)
            inc a
            cp 7
            jr nc,.n
            ld a,c
            sub (iy+E_Y)
            add a,5
            cp 17
            jr nc,.n
            ld (iy+E_LAST),#FF
.n          add iy,de
            dec h
            jr nz,.w
            ret

eclat_erase:                            ; efface les 2 octets de l'eclat IX
            ld a,(ix+B_OX)
            inc a
            ret z
            dec a
            ld b,a
            ld c,(ix+B_OY)
            ld (ix+B_OX),#FF
            ld de,#0206                 ; 2 octets x 6 lignes
            jp restore_xy

bullet_erase:
            ld a,(ix+B_OX)
            cp #FF
            ret z
            ld b,a
            ld c,(ix+B_OY)
            ld (ix+B_OX),#FF
            call scr_addr
            ld b,6
            jp restore_col

; balle ennemie en (B,C) contre Papi
bullet_vs_player:
            ld a,(p_x)
            ld d,a
            ld a,b
            sub d
            cp 6
            ret nc
            ld a,(p_y)
            ld d,a
            ld a,c
            add a,4
            sub d
            cp 14
            ret nc
            ld a,(p_inv)
            or a
            ret nz
            ld a,(p_state)
            or a
            ret nz
            ld (ix+B_ON),2
            jp player_hit

; balle de Papi en (B,C) contre les ennemis : la moitie des ennemis a chaque
; image (une balle met au moins 2 images a traverser un sprite)
bullet_vs_enemies:
            ld hl,enemies
            ld a,(frame)
            rra
            jr nc,.even
            ld l,ESIZE
.even       ld de,ESIZE*2-2
            ld a,MAXENEMY/2
.l          ex af,af'
            ld a,(hl)
            dec a
            jr nz,.n0                   ; pas en vie
            inc l
            ld a,b
            sub (hl)
            inc a
            cp 8
            jr nc,.n1
            inc l
            ld a,c
            add a,5
            sub (hl)
            cp 17
            jr c,.touch
            add hl,de
            jr .n
.n0         inc l
.n1         inc l
            add hl,de
.n          ex af,af'
            dec a
            jr nz,.l
            ld a,2                      ; aucun ennemi touche ; zone 4 : la balle touche-t-elle le vehicule ?
            jp veh_if
.touch      dec l
            dec l
            ld (ix+B_ON),2
            push ix
            push hl
            pop ix
            call enemy_killed
            pop ix
            ret

;------------------------------------------------------------------------------
; ENNEMIS : a tour de role, tant qu'il reste du temps dans l'image.
;   On reprend la ou on s'etait arrete a l'image precedente. Chaque ennemi sait
;   combien d'images ont passe depuis son dernier tour (dt = 1 a 4) et avance
;   d'autant : sa vitesse a l'ecran ne depend pas de la charge.
;------------------------------------------------------------------------------
enemies_update:
            ld a,(p_state)
            cp 3
            ret z                       ; Papi entre dans la carte : les ennemis attendent
            ld a,(nb_wanted)
            ld (en_cnt),a
            ld a,(en_cur)
            add a,a
            add a,a
            add a,a
            add a,a                     ; x16 (retenue si >= 16)
            ld ixl,a
            ld a,hi(enemies)
            adc a,0
            ld ixh,a
en_loop:    ld a,(tick)
            ld hl,tick_lim
            cp (hl)
            ret nc                      ; plus le temps : la suite a l'image prochaine
            ld a,(frame)
            ld b,a
            sub (ix+E_LASTF)
            ld (ix+E_LASTF),b
            cp 5
            jr c,.d1
            ld a,4                      ; (au-dela de 4 images de retard, il ralentit)
.d1         ld (en_dt),a
            ld hl,slot_spd              ; sa vitesse (0 ou 32 : decalage dans les tables)
            ld a,(en_cur)
            add a,l
            ld l,a
            ld a,(hl)
            ld (en_spd),a
            ld a,(en_dt)
            add a,a
            add a,a
            ld hl,en_spd
            add a,(hl)
            ld e,a
            ld d,0
            ld iy,dt_tab-4
            add iy,de                   ; IY -> pas a faire pour ce dt
            call gr_cls
            cp #70
            jp z,sn_run                 ; sniper
            ld a,(ix+E_STATE)
            dec a
            jp z,enemy_alive
            dec a
            jp z,enemy_dying
            jp enemy_absent
enemy_next:
            ld de,ESIZE
            add ix,de
            ld hl,en_cur
            inc (hl)
            ld a,(nb_wanted)
            cp (hl)
            jr nz,.nw
            ld (hl),0                   ; retour au premier
            ld ix,enemies
.nw         ld hl,en_cnt
            dec (hl)
            jr nz,en_loop
            ret

; pour dt = 1..4 images : octets entiers + reste, lignes entieres + reste
;   (8,8 octets/s en horizontal, 17,6 lignes/s en vertical : 70 % de la v03)
dt_tab:     db 41,0, 0,81               ; 8,0 octets/s = 16,0 pixels/s en horizontal ; 15,8 lignes (= pixels)/s en vertical
            db 82,0, 0,162
            db 123,0, 0,243
            db 164,0, 1,68
; deplacement en diagonale : 1 octet pour 4 lignes, avances ensemble (3,6 octets/s + 14,3 lignes/s).
; Vitesse sur la trajectoire : 15,9 pixels/s (1 octet = 2 pixels, 1 ligne = 1 pixel), comme en horizontal
; (16,0) et en vertical (15,8) : les 8 directions ont la meme vitesse, 10 % sous celle de la v08 en
; horizontal et en vertical (17,6 pixels/s). La diagonale de la v08 allait a 22 pixels/s.
dt_diag:    db 0,0, 0,73
            db 0,0, 0,146
            db 0,0, 0,219
            db 0,0, 1,36
; tables RAPIDES (+15 %, pour le general) : a 32 octets de leurs jumelles (dt_tab + 32, dt_diag + 32)
dt_tab_fast: db 47,0, 0,93
            db 94,0, 0,186
            db 141,0, 1,23
            db 188,0, 1,116
dt_diag_fast: db 0,0, 0,84
            db 0,0, 0,168
            db 0,0, 0,252
            db 0,0, 1,80
; tables TRES RAPIDES (+15 % de plus : le boss General Falzar), a 64 octets de leurs jumelles
            db 54,0, 0,107
            db 108,0, 0,214
            db 162,0, 1,65
            db 216,0, 1,172
            db 0,0, 0,97
            db 0,0, 0,193
            db 0,0, 1,34
            db 0,0, 1,130

; recherche d'un poste de couverture proche (IX = ennemi) : une case verte uniquement avec un mur rouge juste dessous,
; dans un rayon de 2 colonnes et 3 rangees autour de ses pieds. Sortie : A = direction (0 droite, 1 gauche, 2 bas) ou #FF.
cover_seek:
            ld a,(ix+E_X)
            add a,3
            ld b,a
            ld a,(ix+E_Y)
            add a,10
            ld c,a
            call cell_ptr               ; HL = case de ses pieds
            dec hl
            dec hl                      ; base = 2 colonnes a gauche (les decalages restent positifs)
            ld de,seek_tab
            ld b,15
.n          ld a,(de)
            inc de
            push hl
            add a,l
            ld l,a
            jr nc,.nc
            inc h
.nc         ld a,(hl)
            and #8B                     ; verte uniquement (ni eau : un poste ne se trouve pas dans la riviere) ?
            jr nz,.no
            ld a,16
            add a,l
            ld l,a
            jr nc,.nc2
            inc h
.nc2        ld a,(hl)                   ; mur rouge juste dessous (pas une caserne : bit 2) ?
            and #16                     ; v73 : un bidon (#17) est un abri aussi (comme le mur rouge)
            cp 2
            jr z,.okc
            cp #16
            jr nz,.no
.okc
            pop hl
            ld a,(de)
            ret
.no         pop hl
            inc de
            djnz .n
            ld a,#FF
            ret
; (decalage dans la grille, direction) : rangee 0 puis 1 puis 2, colonnes 0, -1, +1, -2, +2
seek_tab:   db 2,2, 1,1, 3,0, 0,1, 4,0
            db 18,2, 17,1, 19,0, 16,1, 20,0
            db 34,2, 33,1, 35,0, 32,1, 36,0

; donnees (pas de code ici : le code qui precede ne doit jamais "tomber" dedans)
; distance (en cases du champ de distances) a laquelle un ennemi s'arrete et tire, par classe (0, soldat, officier, general, boss, -, grenadier, sniper) :
;   soldat : va au contact (il ne s'arrete que sur la case de Papi) ; officier : a portee de grenade (60 lignes, environ 7 cases) ; general : a portee de tir (environ 10 cases)
near_tab:   db 5,1,8,11,5,5,5,5           ; (s'arrete s'il est a moins de cette distance)
            assert hi(near_tab)==hi(near_tab+7)
type_ptr:   dw soldat_frames,officer_frames,general_frames,general_frames,boss_frames,boss_frames,officer_frames       ; types 4 (corps du boss) et 5 (tete) : la table des generals sert au corps
            include 'zones.inc'         ; repertoire des zones (genere)
DT_FX       equ 0
DT_XI       equ 1
DT_YI       equ 2
DT_FY       equ 3

;--- pas encore en jeu : attendre puis entrer par un bord ---------------------
enemy_absent:
            ld a,(bk_on)
            or a
            jr z,enemy_absent2
            ld a,ixl
            cp 32
            jr nc,.nb
            ld a,(veh_on)               ; zone 4 (vehicule a barre de vie, modes 2 et 3) : les 2 premieres places sont factices
            and 3
            jp nz,enemy_next
            jp bk_absent                ; corps ou tete du boss
.nb
            xor a
            ld (ymin),a
enemy_absent2:
            ld a,(ix+E_TIMER)           ; delai sur 16 bits : E_TICK (octet fort) puis E_TIMER
            ld hl,en_dt
            sub (hl)
            ld (ix+E_TIMER),a
            jr nc,.nb
            ld a,(ix+E_TICK)            ; retenue : on emprunte a l'octet fort
            or a
            jr z,.try
            dec (ix+E_TICK)
            jp enemy_next
.nb         jp nz,enemy_next
            ld a,(ix+E_TICK)
            or a
            jp nz,enemy_next
.try        ld (ix+E_TIMER),14          ; si l'entree echoue : nouvel essai bientot (12 avant, +15 %)
            ld a,(spawn_ix)             ; point d'apparition suivant : ils servent tour a tour
            inc a
            ld hl,spawn_n
            cp (hl)
            jr c,.sp
            xor a
.sp         ld (spawn_ix),a
            add a,a
            ld l,a
            ld h,0
            ld de,spawn_tab
            add hl,de
            ld b,(hl)
            inc hl
            ld c,(hl)
            ; v72 : plus de zone d'exclusion autour de Papi (l'ennemi sort toujours)
.far        call can_stand_e
            jp nz,enemy_next
            call enemy_place
            jp enemy_draw

; IX = fiche d'une place libre, B = x, C = y : l'ennemi entre en jeu (aussi appelee par le module des vehicules)
enemy_place:
            ld (ix+E_X),b
            ld (ix+E_Y),c
            ld (ix+E_OX),#FF
            ld (ix+E_STATE),1
            ld (ix+E_DIR),2
            ld (ix+E_DX),0
            ld (ix+E_DY),0
            call fire_ptr               ; cadence de tir : le compte commence a l'arrivee
            ld a,(frame)
            ld (hl),a
            ld hl,slot_hp0              ; points de vie de depart (DE = indice de la place, laisse par fire_ptr)
            add hl,de
            ld a,(hl)
            ld hl,slot_hp
            add hl,de
            ld (hl),a
            ld hl,slot_flash            ; pas de clignotement a l'arrivee
            add hl,de
            ld (hl),0
            ld a,(en_cur)               ; reflexions decalees d'un ennemi a l'autre
            and 15
            inc a
            ld (ix+E_TIMER),a
            call enemy_claim
            ld hl,hud_dirty
            set 2,(hl)
            ret

;--- animation de mort --------------------------------------------------------
enemy_dying:
            ld a,(ix+E_TIMER)           ; compte en images
            ld hl,en_dt
            sub (hl)
            jr c,.gone
            ld (ix+E_TIMER),a
            rrca
            rrca
            rrca
            and 3
            xor 3
            add a,32
            jp enemy_draw_frame
.gone       call enemy_free
            ld b,(ix+E_OX)
            ld c,(ix+E_OY)
            ld (ix+E_OX),#FF
            ld de,#060C
            call restore_xy
            ld (ix+E_STATE),0
            call rand
            and 127
            add a,147                   ; renfort : 147 a 274 images (2,9 a 5,5 s) apres la mort
            ld (ix+E_TIMER),a           ; (+15 % sur la v08 : 120 a 247). 16 bits : E_TICK = octet fort
            sbc a,a
            and 1
            ld (ix+E_TICK),a
            ld hl,hud_dirty
            set 2,(hl)
            jp enemy_next

;--- en vie -------------------------------------------------------------------
enemy_alive:
            ld a,(bk_on)
            or a
            jr z,enemy_alive2
            ld a,ixl
            cp 16
            jp z,bk_head                ; la tete du boss
            or a
            jr nz,.gd
            call bk_unhead              ; le corps : libere les cases de sa tete, y >= 12
            ld a,12
            jr .ym
.gd         xor a
.ym         ld (ymin),a
enemy_alive2:
            ld hl,slot_flash            ; clignotement blanc : il se decompte, puis on le redessine normalement
            ld a,(en_cur)
            add a,l
            ld l,a
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
.nofl       call enemy_free             ; je libere mes cases le temps de bouger
            ld a,(ix+E_TIMER)
            ld hl,en_dt
            sub (hl)
            ld (ix+E_TIMER),a
            jr z,.th
            jr nc,.noth
.th         call enemy_think            ; c'est mon tour de reflechir
.noth       ld b,(ix+E_X)
            ld c,(ix+E_Y)
            ld d,0                      ; D : bit0 = j'ai bouge, bit1 = j'ai essaye
            ld a,(ix+E_DX)
            or a
            jp z,.hv
            ld a,(ix+E_DY)
            or a
            jp z,.hv
            ; --- diagonale : les deux axes avancent ENSEMBLE ----------------------------------
            ;   Un octet MODE 0 fait 2 pixels, et un pixel est environ 2 fois plus large que
            ;   haut : une vraie diagonale a l'ecran, c'est 1 octet pour 4 lignes (et non 1 pour
            ;   2, qui donnait une pente de 27 degres, en escalier). Les lignes sont cumulees
            ;   (dt_diag) ; chaque ligne ajoute 1/4 d'octet a E_FX, et l'octet est avance dans
            ;   le meme pas que la ligne qui le fait deborder. Si la diagonale est bloquee on
            ;   essaye la ligne seule, puis l'octet seul (glissement le long d'un mur).
            ld a,(en_dt)
            add a,a
            add a,a
            ld hl,en_spd
            add a,(hl)
            ld e,a
            ld d,0
            ld iy,dt_diag-4
            add iy,de
            ld a,(iy+DT_FY)
            add a,(ix+E_FY)
            ld (ix+E_FY),a
            ld a,(iy+DT_YI)
            adc a,0                     ; A = nombre de lignes de ce pas : 0, 1 ou 2
            ld d,0
            jp z,.moved                 ; pas de pas ce coup-ci
            ld e,a
            rrca
            rrca                        ; 1 ligne -> #40, 2 lignes -> #80 (un quart d'octet par ligne)
            add a,(ix+E_FX)
            ld (ix+E_FX),a
            sbc a,a                     ; retenue -> #FF : un octet a avancer dans ce pas
            and (ix+E_DX)               ; H = pas horizontal (0, +1 ou -1)
            ld h,a
            ld a,(ix+E_DY)
            dec e
            jr z,.dl
            add a,a                     ; 2 lignes
.dl         ld l,a                      ; L = pas vertical (+-1 ou +-2)
            ld (dg_v),hl
            ld a,b                      ; essai 1 : diagonale complete
            add a,h
            ld b,a
            ld a,c
            add a,l
            ld c,a
            call can_stand_e
            jr z,.dmove
            ld hl,(dg_v)                ; essai 2 : la ligne seule
            ld b,(ix+E_X)
            ld a,(ix+E_Y)
            add a,l
            ld c,a
            call can_stand_e
            jr z,.dmove
            ld hl,(dg_v)                ; essai 3 : l'octet seul
            ld a,h
            or a
            jr z,.dstuck
            add a,(ix+E_X)
            ld b,a
            ld c,(ix+E_Y)
            call can_stand_e
            jr z,.dmove
.dstuck     ld b,(ix+E_X)               ; bloque : meme traitement que plus bas (.moved, D = 2)
            ld c,(ix+E_Y)
            ld d,2
            jp .moved
.dmove      ld (ix+E_X),b
            ld (ix+E_Y),c
            ld a,(en_dt)                ; animation de marche : 2 x dt par pas (25 pas/s)
            add a,a
            add a,(ix+E_TICK)
            ld (ix+E_TICK),a
            jp .claim
            ; --- horizontal ---
.hv
            ld a,(ix+E_DX)
            or a
            jr z,.nudge
            ld e,a
            ld a,(iy+DT_FX)
            add a,(ix+E_FX)
            ld (ix+E_FX),a
            ld a,(iy+DT_XI)
            adc a,0
            jr z,.ymove                 ; pas encore un octet entier
            set 1,d
            ld a,b
            add a,e
            ld b,a
            jr .tryx
.nudge      ld a,(ix+E_DY)              ; en montee/descente : s'aligner sur la colonne
            or a                        ; (pour passer dans les couloirs d'une case)
            jr z,.ymove
            ld l,b
            ld h,hi(MOD6)
            ld a,(hl)
            or a
            jr z,.ymove
            cp 3
            jr c,.nd1
            inc b
            jr .tryx
.nd1        dec b
.tryx       call can_stand_e
            jr z,.xok
            ld b,(ix+E_X)
            jr .ymove
.xok        ld (ix+E_X),b
            set 0,d
            ; --- vertical ---
.ymove      ld a,(ix+E_DY)
            or a
            jr z,.moved
            ld e,a
            ld a,(iy+DT_FY)
            add a,(ix+E_FY)
            ld (ix+E_FY),a
            ld a,(iy+DT_YI)
            adc a,0                     ; 0, 1 ou 2 lignes
            jr z,.moved
            set 1,d
            dec a
            ld a,c
            jr z,.y1
            add a,e
.y1         add a,e
            ld c,a
            call can_stand_e
            jr z,.yok
            ld c,(ix+E_Y)
            jr .moved
.yok        ld (ix+E_Y),c
            set 0,d
.moved      ld a,d
            cp 2
            jr nz,.walk
            ; essaye mais bloque : le plus souvent j'attends que ca se libere,
            ; une fois sur 8 je pars au hasard quelques instants (ca suffit a
            ; contourner ce que le champ de distances ne voit pas : les autres)
            push bc
            call rand
            and 63
            cp 8
            jr nc,.wait
            call enemy_setdir
            ld (ix+E_TIMER),12
.wait       pop bc
            jr .claim
.walk       rra
            jr nc,.claim
            ld a,(en_dt)                ; animation de marche : 3 x dt par pas (image tous les 8
            ld d,a                      ; = 8/3 pas). Les pas etant 30 % plus rares, le rythme
            add a,a                     ; d'animation reste celui de la v03 (+6 %).
            add a,d                     ; (D est libre ici ; B et C = position, pour enemy_claim)
            add a,(ix+E_TICK)
            ld (ix+E_TICK),a
.claim      call enemy_claim            ; je reprends mes cases
            ; --- contact avec Papi ---
            ld d,0                      ; D = 1 : mon sprite chevauche celui de Papi
            ld a,(p_x)
            sub b
            add a,5
            cp 11
            jr nc,enemy_draw
            ld a,(p_y)
            sub c
            add a,11
            cp 23
            jr nc,enemy_draw
            inc d                       ; (je me redessinerai : Papi m'a peut-etre entame)
            ld a,(p_x)
            sub b
            add a,3
            cp 7
            jr nc,enemy_draw
            ld a,(p_y)
            sub c
            add a,7
            cp 15
            call c,player_hit

enemy_draw:
            ld a,(ix+E_TICK)
            rrca
            rrca
            rrca                        ; image d'animation : E_TICK / 8 (voir enemy_alive)
            and 3
            ld e,a
            ld a,(ix+E_DIR)
            add a,a
            add a,a
            add a,e
            ; rien n'a change (meme place, meme image) : inutile de redessiner,
            ; sauf une fois de temps en temps pour reparer un eventuel chevauchement
            cp (ix+E_LAST)
            jr nz,enemy_draw_frame
            ld e,a
            ld a,(ix+E_X)
            cp (ix+E_OX)
            jr nz,.go
            ld a,(ix+E_Y)
            cp (ix+E_OY)
            jr nz,.go
            dec d
            jr z,.go
            ld a,(frame)
            add a,(ix+E_CELL)
            and #0C
            jp nz,enemy_next
.go         ld a,e
enemy_draw_frame:
            ld (ix+E_LAST),a
            ld a,(tick)                 ; plus le temps de dessiner : ce sera pour son
            ld hl,tick_lim
            cp (hl)                     ; prochain tour (on force alors le redessin)
            jr c,.draw
            ld (ix+E_LAST),#FF
            jp enemy_next
.draw       ld a,ixl                    ; sa table d'images : selon son type (soldat, officier, general)
            rrca
            rrca
            rrca
            rrca
            and 15
            ld e,a
            ld d,0
            ld hl,slot_type
            add hl,de
            ld e,(hl)
            ld hl,type_ptr
            add hl,de
            add hl,de
            ld a,(hl)
            inc hl
            ld h,(hl)
            ld l,a
            ld a,(ix+E_LAST)
            call frame_ptr
            ld a,ixl                    ; il clignote (touche sans mourir) : image blanche
            rrca
            rrca
            rrca
            rrca
            and 15
            ld e,a
            ld d,0
            push hl
            ld hl,slot_flash
            add hl,de
            ld a,(hl)
            pop hl
            or a
            call nz,make_white
            ld b,(ix+E_X)
            ld c,(ix+E_Y)
            ld d,(ix+E_OX)
            ld e,(ix+E_OY)
            ld (ix+E_OX),b
            ld (ix+E_OY),c
            call draw_sprite
            jp enemy_next

; CAISSE DE GRENADES, PARACHUTEE : quand Papi n'a plus que 0 ou 1 grenade et qu'aucune caisse n'est en jeu, une caisse
; tombe du ciel (bruit de grenade) sur une case degagee (verte, sans obstacle) tiree au hasard, apres CRATE_DELAY images.
;   crate_st : 0 aucune, 1 au sol, 2 en train de descendre (37 lignes/s)
; Au sol, elle est ramassee quand Papi la touche, redessinee toutes les 16 images (un ennemi qui passe dessus l'efface)
; et detruite par toute explosion proche (grenade de Papi ou d'un officier : crate_blast).
crate_update:
            ld a,(crate_st)
            or a
            jr nz,.have
            ld a,(grenades)
            cp 2
            ret nc
            ld a,(p_state)
            or a
            ret nz
            ld hl,crate_cd
            ld a,(hl)
            or a
            jr nz,.cnt
            ld (hl),CRATE_DELAY         ; la caisse est commandee : elle arrive dans 2 s
            ret
.cnt        dec (hl)
            ret nz
            ld (hl),1                   ; (si le tirage echoue : nouvel essai a l'image suivante)
            call rand
            ld a,h
            and 15
            cp 13
            ret nc                      ; colonne 0..12
            ld b,a
            ld a,l
            and 31
            sub 2
            cp 20
            ret nc                      ; rangee 2..21 (la caisse occupe deux rangees)
            add a,2
            ld c,a
            ld l,a
            ld h,0
            inc l
            add hl,hl
            add hl,hl
            add hl,hl
            add hl,hl                   ; (rangee + 1) x 16
            ld e,b
            ld d,0
            add hl,de
            ld de,GRID
            add hl,de                   ; case de la grille
            ld a,(hl)
            ld de,16
            add hl,de
            or (hl)                     ; cette case et celle du dessous : ni bleu, ni rouge, ni jaune, ni ennemi
            and #CB
            ret nz
            ld a,b                      ; x = 6 x colonne
            add a,a
            ld e,a
            add a,a
            add a,e
            ld (crate_x),a
            ld a,c                      ; y d'arrivee = 8 x rangee
            add a,a
            add a,a
            add a,a
            ld (crate_ty),a
            xor a
            ld (crate_y),a              ; elle part du haut de la carte
            ld (crate_cd),a
            dec a
            ld (crate_ox),a
            ld a,2
            ld (crate_st),a
            ld a,7                      ; bruit de grenade
            jp sfx
.have       dec a
            jr z,.ground
            ld a,(frame)                ; --- elle descend : 1 ligne sur 3 images de 4 (37 lignes/s)
            and 3
            ret z
            ld a,(crate_y)
            ld hl,crate_ty
            cp (hl)
            jr nz,.fall
            ld a,1                      ; arrivee
            ld (crate_st),a
            ret
.fall       inc a
            ld (crate_y),a
            ld bc,(crate_oy)            ; les ennemis sous l'ancienne et la nouvelle place se redessinent
            call wake_12
            ld bc,(crate_y)
            jp wake_12
.ground     ld a,(p_state)
            or a
            jr nz,.draw                 ; Papi pas en jeu : pas de ramassage
            ld a,(crate_x)
            ld hl,p_x
            sub (hl)
            add a,5
            cp 11
            jr nc,.draw
            ld a,(crate_y)
            ld hl,p_y
            sub (hl)
            add a,10
            cp 21
            jr nc,.draw
            ld a,(crate_ox)             ; ramassee : on efface sa derniere image
            inc a
            jr z,.nodraw
            ld bc,(crate_oy)
            ld de,#060C
            call restore_xy
.nodraw     xor a
            ld (crate_st),a
            ld a,(z80_f)                ; c'etait le Z80 : fin de la mission
            or a
            jr z,.gr
            xor a
            ld (kills_left),a           ; la boucle principale appelle 'victory'
            ld a,9
            jp sfx
.gr         ld a,(grenades)
            add a,CRATE_GREN
            cp GREN_MAX+1
            jr c,.ok
            ld a,GREN_MAX
.ok         ld (grenades),a
            ld hl,hud_dirty
            set 4,(hl)
            ld a,9                      ; son de la grenade recuperee
            jp sfx
.draw       ret

; AFFICHAGE DE LA CAISSE : appelee en DERNIER dans l'image (apres les ennemis), pour que la caisse parachutee passe au premier
; plan : par-dessus Papi, les ennemis, les balles et meme les murs "devant" (jaunes), qu'elle ne respecte pas.
; En descente elle est redessinee a chaque image ; au sol, toutes les 16 images.
crate_draw:
            ld a,(crate_st)
            or a
            ret z
            dec a
            jr z,.ground
            jr .go
.ground     ld a,(crate_ox)
            inc a
            jr z,.go
            ld a,(frame)
            and 15
            ret nz
.go         ld bc,(crate_y)             ; C = y, B = x
            ld a,(crate_ox)
            ld d,a
            inc a
            jr z,.draw                  ; jamais dessinee : rien a effacer
            ld a,(crate_oy)
            ld e,a
            ld a,b
            cp d
            jr nz,.full
            ld a,c
            sub e
            jr z,.draw                  ; meme place : on se contente de la redessiner
            cp 1
            jr nz,.full
            push bc                     ; elle a descendu d'une ligne : seule la ligne quittee est remise
            ld b,d
            ld c,e
            ld de,#0601
            call restore_xy
            pop bc
            jr .draw
.full       push bc
            ld b,d
            ld c,e
            ld de,#060C
            call restore_xy
            pop bc
.draw       ld (crate_oy),bc
            call scr_addr
            call front_ok
            jr nc,.slow
            ld de,(crate_frame)
            jp comp_c
.slow       ld hl,(crate_frame)         ; bord de l'espace d'adressage : routine generale (qui respecte les murs)
            ld d,#FF
            jp draw_sprite

; carry = la composition rapide (comp_c) convient en HL (les 3 rangees de caracteres restent dans la page) ; ne teste pas les murs
front_ok:
            ld a,l
            cp 250
            ret nc
            add a,80
            cp 250
            ret nc
            ld d,a
            ld a,c
            and 7
            cp 5
            ret c
            ld a,d
            add a,80
            cp 250
            ret

; une explosion centree en (B = x, C = y) detruit la caisse posee a moins de 9 octets / 18 lignes.  conserve IX
crate_blast:
            ld a,(crate_st)
            dec a
            ret nz
            ld a,(z80_f)                ; le Z80 resiste aux explosions
            or a
            ret nz
            ld a,(crate_x)
            sub b
            add a,9
            cp 19
            ret nc
            ld a,(crate_y)
            sub c
            add a,18
            cp 37
            ret nc
            ld a,(crate_ox)             ; on efface son image (l'explosion se dessine par-dessus aux images suivantes)
            inc a
            jr z,.gone
            push bc
            ld bc,(crate_oy)
            ld de,#060C
            call restore_xy
            pop bc
.gone       xor a
            ld (crate_st),a
            ld (crate_cd),a             ; s'il reste moins de 2 grenades, une autre sera parachutee
            ret

; remet a "a redessiner" les ennemis qui recouvrent un bloc de 6 x 12 en (B = x, C = y).  conserve BC, IX ; clobbers A, DE, H, IY
wake_12:
            ld iy,enemies
            ld h,MAXENEMY
            ld de,ESIZE
.w          ld a,b
            sub (iy+E_X)
            add a,5
            cp 11
            jr nc,.n
            ld a,c
            sub (iy+E_Y)
            add a,11
            cp 23
            jr nc,.n
            ld (iy+E_LAST),#FF
.n          add iy,de
            dec h
            jr nz,.w
            ret

; HL = image -> HL = la meme image en blanc (masque conserve, pixels remplaces par du blanc), dans white_buf
make_white:
            ld de,white_buf
            ld b,72
.m          ld a,(hl)
            inc hl
            ld (de),a
            inc de
            cpl                         ; bits des pixels opaques
            and WHITE
            ld (de),a
            inc de
            inc hl
            djnz .m
            ld hl,white_buf
            ret

; IX = ennemi touche par une balle.   conserve BC
enemy_killed:                           ; touche par une balle : un point de vie de moins
            ld a,(bk_on)
            or a
            jr z,enemy_killed2
            ld a,ixl
            cp 32
            jp c,bk_killed              ; le boss
enemy_killed2:
            ld a,ixl
            rrca
            rrca
            rrca
            rrca
            and 15
            ld e,a
            ld d,0
            ld hl,slot_hp
            add hl,de
            dec (hl)
            jr z,enemy_kill_now
            ld hl,slot_flash            ; encore vivant : il clignote en blanc, et le bruit de l'impact
            add hl,de
            ld (hl),FLASH_N
            ld (ix+E_LAST),#FF
            ld a,3
            jp sfx
; mort immediate (aussi pour la grenade de Papi)
enemy_kill_now:
            ld a,(bk_on)
            or a
            jr z,.nb
            ld a,ixl
            cp 32
            jp c,bk_grenade             ; le boss : 3 points de degats
.nb         ld a,ixl                    ; cette place compte-t-elle pour le quota ? (bit 2 de sa fiche)
            rrca
            rrca
            rrca
            rrca
            and 15
            ld e,a
            ld d,0
            ld hl,slot_gren
            add hl,de
            bit 2,(hl)
            jr z,.nk
            ld a,(z80_f)                ; le Z80 est tombe : les kills ne comptent plus
            or a
            jr nz,.nk
            ld a,(kills_left)
            or a
            jr z,.nk
            dec a
            ld (kills_left),a
            call z,z80_drop             ; mission Z80 : quota atteint -> il tombe de cet ennemi (sinon : victoire par la boucle principale)
            ld hl,hud_dirty
            set 2,(hl)
.nk         call gr_test                ; grenadier : 25 % de chance de laisser une caisse de grenades (banque 7)
            jr nz,.nodrop
            ld a,3
            call gr_call
.nodrop     ld hl,slot_pts              ; points : 10 x la valeur de son type (DE = place)
            add hl,de
            ld b,(hl)
.pt         push bc
            ld hl,score+4
            call add_score
            pop bc
            djnz .pt
            ld a,3
            call sfx
            ld (ix+E_STATE),2           ; (il garde ses cases jusqu'a disparaitre)
            ld (ix+E_TIMER),31
            ret

; vie gagnee (life_bl = 150 images) : toutes les 8 images le nombre de vies du HUD se redessine, clignotant
life_blink: ld a,(life_bl)
            or a
            ret z
            dec a
            ld (life_bl),a
            and 7
            ret nz
            ld hl,hud_dirty
            set 1,(hl)
            ret

; mission 'Find the Z80' : le quota est atteint, le Z80 tombe de l'ennemi IX (la caisse sert d'objet : meme ramassage, victoire a la place des grenades).
; Le compteur du HUD repasse a 1 (= le Z80 a trouver).  Hors de cette mission : ne fait rien.  conserve DE, IX
z80_drop:   ld a,(z80_m)
            or a
            ret z
            ld a,1
            ld (kills_left),a
            ld (z80_f),a
            ld (crate_st),a
            ld a,(ix+E_X)
            ld (crate_x),a
            ld a,(ix+E_Y)
            ld (crate_y),a
            ld a,#FF
            ld (crate_ox),a
            ld hl,(z80_img)
            ld (crate_frame),hl
            ld a,64                     ; double arpege montant (celui de la vie bonus, deux fois) : le Z80 est la
            ld (snd_u),a
            ret

; A = direction 0..7 -> E_DIR, E_DX, E_DY
enemy_setdir:
            ld (ix+E_DIR),a
            add a,a
            ld l,a
            ld h,0
            ld de,dir_vec
            add hl,de
            ld a,(hl)
            ld (ix+E_DX),a
            inc hl
            ld a,(hl)
            ld (ix+E_DY),a
            ret

;------------------------------------------------------------------------------
; REFLEXION d'un ennemi (toutes les 16 images environ, a tour de role)
;   on lit le champ de distances autour de sa case et on descend la pente
;------------------------------------------------------------------------------
enemy_think:
            ld (ix+E_TIMER),16
            xor a
            ld (cov_now),a
            call gr_test                ; grenadier : son propre comportement (banque 7)
            jp z,gr_think
            ld hl,slot_gren             ; place a couvert (25 % des unites) ?  (bit 1 de la fiche)
            ld a,(en_cur)
            add a,l
            ld l,a
            ld a,(hl)
            and 2
            jr z,.nocov
            ld a,(bk_on)                ; boss : apres 10 s a couvert il avance vers Papi (b_cno : images restantes)
            or a
            jr z,.cv0
            ld a,ixl
            or a
            jr nz,.cv0
            ld a,(b_cno)
            or a
            jr nz,.nocov
.cv0        ld a,(ix+E_Y)               ; Papi doit etre au moins 16 lignes plus bas que lui
            add a,16
            ld hl,p_y
            cp (hl)
            jr z,.cv1
            jr nc,.nocov
.cv1        ld a,(ix+E_Y)               ; au bas de sa case (la case des pieds est celle de la ligne y + 10) :
            add a,10                    ; a 2 lignes au plus de la rangee suivante
            and 7
            cp 6
            jr c,.seek
            ld a,(ix+E_X)               ; colle a un obstacle rouge (la rangee juste sous la case de ses pieds)...
            add a,3
            ld b,a
            ld a,(ix+E_Y)
            add a,18
            ld c,a
            call cell_ptr
            ld a,(hl)
            and #16                     ; (une caserne - bit 2 - n'est pas un abri ; un bidon, #17, en est un : v73)
            cp 2
            jr z,.cv2
            cp #16
            jr nz,.seek
.cv2
            ld a,(ix+E_Y)               ; ...et debout sur une case verte uniquement (ni jaune, ni bleue)
            add a,10
            ld c,a
            call cell_ptr
            ld a,(hl)
            and #83
            jr nz,.seek
            ld a,3
            ld (cov_now),a
            jp .near                    ; en couverture : il s'arrete, se tourne vers Papi et tire
.seek       ld a,(frame)                ; pas encore a couvert : il cherche un poste proche (sauf 1 reflexion sur 4,
            and #30                     ; pour ne jamais rester bloque devant un poste inatteignable)
            jr z,.nocov
            call cover_seek
            cp #FF
            jr z,.nocov
            call enemy_setdir           ; il se dirige vers le poste (droite, gauche ou bas) et tire en marchant
            jp enemy_try_fire
.nocov      call gr_cls                 ; E = distance d'arret de cette classe (near_tab : il s'arrete s'il est plus pres que cela)
            rrca
            rrca
            rrca
            rrca
            add a,lo(near_tab)
            ld l,a
            ld h,hi(near_tab)
            ld e,(hl)
            ld a,(ix+E_X)
            add a,3
            ld b,a
            ld a,(ix+E_Y)
            add a,10
            ld c,a
            call cell_ptr
            ld a,(ff_front)
            or h
            ld h,a                      ; HL -> distance de ma case
            ld a,(hl)
            cp 255
            jr z,.direct                ; champ pas encore pret : tout droit vers Papi
            cp e
            jr c,.near                  ; assez pres : je m'arrete et je tire
            ld c,a                      ; C = ma distance
            ld d,4                      ; D = index dans dir_tab, 4 = immobile
            inc l                       ; a l'est, c'est plus pres ?
            ld a,(hl)
            dec l
            cp c
            jr nc,.e1
            inc d
            jr .e3
.e1         dec l                       ; a l'ouest ?
            ld a,(hl)
            inc l
            cp c
            jr nc,.e3
            dec d
.e3         ld a,l
            add a,16                    ; au sud ?
            ld l,a
            jr nc,.s0
            inc h
.s0         ld a,(hl)
            cp c
            jr nc,.s1
            ld a,d
            add a,3
            ld d,a
            jr .s2
.s1         ld a,l
            sub 32                      ; au nord ?
            ld l,a
            jr nc,.s3
            dec h
.s3         ld a,(hl)
            cp c
            jr nc,.s2
            ld a,d
            sub 3
            ld d,a
.s2         ld a,d
            cp 4
            jr z,.direct                ; pas de pente (ne devrait pas arriver)
            ld hl,dir_tab
            add a,l
            ld l,a
            jr nc,.s4
            inc h
.s4         ld a,(hl)
            call enemy_setdir
            jr enemy_try_fire           ; en marchant : tir selon la cadence du type

.near       call aim_dir
            ld (ix+E_DIR),a
            ld (ix+E_DX),0
            ld (ix+E_DY),0
            jr enemy_try_fire

.direct     call aim_dir
            jp enemy_setdir

; ennemi IX -> HL = sa case de FIRE_LAST (clobbers A, DE)
fire_ptr:
            ld a,ixl
            rrca
            rrca
            rrca
            rrca
            and 15
            ld e,a
            ld d,0
            ld hl,FIRE_LAST
            add hl,de
            ret

; cadence de tir : un soldat toutes les 5 s, un officier toutes les 3 s.  FIRE_LAST contient la valeur de
; 'frame' au dernier tir (ou a l'arrivee).  Reflexion toutes les 16 images : seuils choisis pour que la
; difference modulo 256 ne deborde jamais (240 + 16 < 256), d'ou 240 et 144 pour 5 s et 3 s.
enemy_try_fire:
            ld a,(bk_on)
            or a
            jr z,.n
            ld a,ixl
            or a
            jr nz,.n
            ld a,(cov_now)              ; le corps du boss ne tire pas ici (voir boss_tick) : il retient seulement s'il est a couvert
            ld (b_cov),a
            ret
.n          call gr_test                ; le grenadier ne tire pas a la balle : il ne lance que des grenades
            ret z
            call fire_ptr               ; HL = FIRE_LAST de cette place, DE = son indice
            push hl
            ld hl,slot_fire
            add hl,de
            ld b,(hl)
            pop hl
            ld a,(frame)
            sub (hl)
            cp b
            ret c
            ld a,(frame)
            ld (hl),a
            jr enemy_shoot

enemy_shoot:
            ld a,(p_state)
            or a
            ret nz
            call fire_ptr               ; classe de portee du tireur : bits 4-6 de sa fiche 'gren'
            ld hl,slot_gren
            add hl,de
            ld a,(hl)
            rrca
            rrca
            rrca
            rrca
            and 7
            ld (shot_cls),a
            ld d,(ix+E_X)
            ld e,(ix+E_Y)
            ld h,(ix+E_DIR)             ; la balle part dans la direction de l'ennemi : celle de sa marche, ou vers Papi quand il s'est arrete
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
.ok         ld a,h
            ld h,d                      ; H = x, L = y
            ld l,e
            call bullet_start
            jr nz,.nf                   ; pas de balle partie
            ld a,(shot_cls)
            cp 7
            jr z,.nsra                  ; sniper : la balle garde le pas entier (comme Papi)
            sra (ix+B_DX)               ; pas de la balle ennemie divise par deux
            sra (ix+B_DY)               ; (avec EBUL_SPEED : 60 % de l'ancienne vitesse, soit -40 %)
.nsra            ld a,(cov_now)              ; tir en couverture : la balle traverse l'obstacle derriere lequel il se tient
            or a
            jr z,.nc
            ld (ix+B_PASS),a            ; (cov_now = nombre de pas : 3 en couverture, 10 pour un sniper de tuile bleu clair : il traverse les obstacles qui l'entourent)
.nc         ld a,1                      ; son du tir (TirSon), comme pour Papi
            call sfx
.nf         pop ix
            ret

;------------------------------------------------------------------------------
; direction (0..7) de l'ennemi IX vers Papi, sans division :
;   |dy| < |dx|  -> horizontal ;  |dy| > 6|dx| -> vertical ; sinon diagonale
;------------------------------------------------------------------------------
aim_dir:
            ld d,(ix+E_X)
            ld e,(ix+E_Y)
aim_dir_de:
            ld b,4                      ; index dir_tab
            ld a,(p_x)
            sub d
            jr z,.x0
            jr nc,.xr
            neg
            dec b
            jr .x0
.xr         inc b
.x0         ld h,a                      ; H = |dx|
            ld a,(p_y)
            sub e
            ld c,0
            jr z,.y0
            jr nc,.yd
            neg
            ld c,-3
            jr .y0
.yd         ld c,3
.y0         ld l,a                      ; L = |dy|
            cp h
            jr c,.horiz                 ; |dy| < |dx|
            ld a,h
            cp 32
            jr nc,.diag
            add a,a
            ld d,a
            add a,a
            add a,d                     ; 6|dx|
            cp l
            jr nc,.diag
            ld a,4                      ; vertical
            add a,c
            jr .get
.horiz      ld a,b
            jr .get
.diag       ld a,b
            add a,c
.get        cp 4
            jr nz,.g1
            ld a,7                      ; pile sur Papi : peu importe
.g1         ld hl,dir_tab
            add a,l
            ld l,a
            jr nc,.g2
            inc h
.g2         ld a,(hl)
            ret

;------------------------------------------------------------------------------
; GRENADE : une seule a la fois. Elle passe par-dessus tout, retombe au bout de
; 24 images et son explosion elimine les ennemis autour.
;------------------------------------------------------------------------------
grenade_update:
            ld a,(g_state)
            or a
            jr z,.idle
            dec a
            jp z,.fly
            ; --- explosion : 4 images de 4 passages ---
            ld hl,g_t
            dec (hl)
            jr z,.endx
            ld a,(hl)
            rrca
            rrca
            and 3
            xor 3
            ld hl,explo_frames
            call frame_ptr
            ld bc,(g_ey)                ; C = y, B = x
            ld de,(g_eoy)
            ld (g_eoy),bc
            jp draw_sprite
.endx       ld bc,(g_ey)
            ld de,#060C
            call restore_xy
            xor a
            ld (g_state),a
            ld bc,(g_ey)                ; ceux qui se trouvaient dessous se redessinent
            jp wake_12

.idle       ld a,(p_state)              ; lancer ?
            or a
            ret nz
            ld a,(joy)
            bit 5,a
            ret z
            ld a,(grenades)             ; plus de grenade : rien
            or a
            ret z
            dec a
            ld (grenades),a
            ld hl,hud_dirty
            set 4,(hl)
            ld a,(p_dir)
            add a,a
            ld e,a
            ld d,0
            ld hl,dir_vec
            add hl,de
            ld a,(hl)
            ld (g_dx),a
            inc hl
            ld a,(hl)
            add a,a
            ld (g_dy),a
            ld bc,(p_y)
            ld a,b
            add a,2
            ld (g_x),a
            ld a,c
            add a,3
            ld (g_y),a
            xor a
            ld (g_t),a
            ld (g_t3),a
            dec a
            ld (g_ox),a
            ld a,1
            ld (g_state),a
            ld a,7                      ; son du lancer (GrenadeSon)
            jp sfx

.fly        call .erase
            ld hl,g_t3                  ; 2 octets toutes les 3 images en horizontal
            inc (hl)
            ld a,(hl)
            cp 3
            jr nz,.fx
            ld (hl),0
            jr .fy
.fx         ld a,(g_dx)
            ld hl,g_x
            add a,(hl)
            cp 77
            jr nc,.boom                 ; sortie de l'ecran : elle eclate au bord
            ld (hl),a
.fy         ld a,(g_dy)                 ; 2 lignes par image en vertical
            ld hl,g_y
            add a,(hl)
            cp 187
            jr nc,.boom
            ld (hl),a
            ld hl,g_t
            inc (hl)
            ld a,(hl)
            cp G_FLIGHT
            jr z,.boom
            ld e,a                      ; hauteur de la cloche
            ld d,0
            ld hl,arc_tab
            add hl,de
            ld a,(g_y)
            sub (hl)
            ret c
            ld c,a
            ld a,(g_x)
            ld b,a
            call cell_ptr               ; coin haut-gauche puis coin bas-droit
            ld a,(hl)
            and #40                     ; derriere un ennemi : on ne la voit pas (l'avant-plan jaune ne la cache pas)
            ret nz
            push bc
            inc b
            ld a,c
            add a,5
            ld c,a
            call cell_ptr
            pop bc
            ld a,(hl)
            and #40
            ret nz
            ld (g_oy),bc
            call scr_addr
            ld a,(g_t)
            jp draw_gren

.erase      ld a,(g_ox)
            cp #FF
            ret z
            ld b,a
            ld a,(g_oy)
            ld c,a
            call wake_rect              ; ceux qui sont venus se placer dessous se redessinent
            ld a,#FF
            ld (g_ox),a
            ld de,#0206
            jp restore_xy

.boom       ld a,(g_x)                  ; explosion centree sur la grenade, dans l'ecran
            sub 2
            jr nc,.b1
            xor a
.b1         cp XMAX+1
            jr c,.b2
            ld a,XMAX
.b2         ld (g_ex),a
            ld a,(g_y)
            sub 3
            jr nc,.b3
            xor a
.b3         cp YMAX+1
            jr c,.b4
            ld a,YMAX
.b4         ld (g_ey),a
            ld a,2
            ld (g_state),a
            ld a,16
            ld (g_t),a
            ld a,#FF
            ld (g_eox),a
            ld bc,(g_ey)                ; une caisse posee a cote est detruite
            call crate_blast
            ld ix,enemies               ; tout ennemi a moins de 9 octets / 18 lignes
            ld b,MAXENEMY
.k          ld a,(ix+E_STATE)
            dec a
            jr nz,.kn
            ld a,(g_ex)
            sub (ix+E_X)
            add a,9
            cp 19
            jr nc,.kn
            ld a,(g_ey)
            sub (ix+E_Y)
            add a,18
            cp 37
            jr nc,.kn
            push bc
            call enemy_kill_now         ; la grenade tue d'un coup, general compris
            pop bc
.kn         ld de,ESIZE
            add ix,de
            djnz .k
            ld a,3                      ; zone 4 : le vehicule et les bidons dans le souffle
            call veh_if
            ld a,6
            jp sfx

; grenade en vol (celle de Papi ou d'un officier) : A = temps de vol, HL = adresse ecran ; elle tourne : 3 images
draw_gren:
            rrca
            and 3
            cp 3
            jr nz,.rot
            xor a
.rot        ld e,a
            add a,a
            add a,e
            add a,a
            add a,a
            add a,a                     ; x24
            ld e,a
            ld d,0
            ex de,hl
            ld bc,spr_grenade
            add hl,bc
            ex de,hl
draw_gdat:  ld b,6                      ; DE = image 2 x 6 (masque, valeur), HL = adresse ecran
.gl         push hl
            ld c,2
.gb         ld a,(de)
            inc de
            push bc
            ld c,a
            res 7,h
            ld a,(hl)
            set 7,h
            and c
            ld c,a
            ld a,(de)
            inc de
            or c
            pop bc
            ld (hl),a
            inc hl
            dec c
            jr nz,.gb
            pop hl
            ld a,h
            add a,8
            ld h,a
            jr nc,.gk
            push de
            ld de,#C050
            add hl,de
            pop de
.gk         djnz .gl
            ret

arc_tab:    db 0,1,2,4,5,6,7,8,9,10,10,11,11,12,12
            db 12,12,12,11,11,10,10,9,8,7,6,5,4,2,1,0,0

;------------------------------------------------------------------------------
; OFFICIERS et GRENADIERS : un lancer de grenade toutes les 8 a 13 s chacun (officier) ou toutes les 2 s (grenadier).
;   Le code (officers_update, egrenade_throw, reflexion et caisse du grenadier) est dans la banque 7 (boss_mod.asm : m_gr), appele par la rampe gr_call.
;------------------------------------------------------------------------------
officers_update:
            ld a,1
            jp gr_call
gr_think:   ld a,2                      ; reflexion du grenadier IX
            jp gr_call
; Z si la place de l'ennemi IX est un grenadier (classe 6 : bits 4-6 de sa fiche 'gren') ; A, HL detruits
gr_test:    call gr_cls
            cp #60
            ret
; A = classe de la place de l'ennemi IX (bits 4-6 de sa fiche 'gren', laisses en place : #10 soldat ... #60 grenadier, #70 sniper) ; HL detruit
gr_cls:     ld a,ixl
            rrca
            rrca
            rrca
            rrca
            and 15
            add a,lo(slot_gren)
            ld l,a
            ld h,hi(slot_gren)
            ld a,(hl)
            and #70
            ret

; SNIPER (classe 7) : immobile dans son trou ; tout son comportement est dans la banque 7 (boss_mod.asm : sn_mod). Sortie de sn_mod : A = 0 rien, 1 effacer, 2 + n : dessiner l'image n
sn_run:     ld a,(ix+E_STATE)
            cp 2
            jp z,enemy_dying            ; (mort : l'animation habituelle)
            call sn_call
            or a
            jp z,enemy_next
            dec a
            jr z,.er
            dec a
            jp enemy_draw_frame
.er         ld a,(ix+E_OX)              ; rien de dessine : rien a effacer
            inc a
            jp z,enemy_next
            ld b,(ix+E_OX)
            ld c,(ix+E_OY)
            ld (ix+E_OX),#FF
            ld de,#060C
            call restore_xy
            jp enemy_next

; grenade des officiers : vol, atterrissage, explosion qui touche Papi
egrenade_update:
            ld a,(eg_state)
            or a
            ret z
            dec a
            jp nz,.expl
            ld a,(eg_acc)               ; en vol : 218 images sur 256 seulement avancent (vitesse -15 %)
            add a,218
            ld (eg_acc),a
            ret nc
            ld a,(eg_ox)                ; --- en vol : on efface l'ancienne position
            cp #FF
            jr z,.noerase
            ld b,a
            ld a,(eg_oy)
            ld c,a
            call wake_rect
            ld a,#FF
            ld (eg_ox),a
            ld de,#0206
            call restore_xy
.noerase    ld hl,eg_t
            inc (hl)
            ld a,(hl)
            cp EG_FLIGHT
            jr z,.land
            srl a
            ld e,a                      ; E = image du vol / 2 : indice dans arc_tab (32 entrees)
            ld hl,(eg_xf)
            ld bc,(eg_vx)
            add hl,bc
            ld (eg_xf),hl
            ld hl,(eg_yf)
            ld bc,(eg_vy)
            add hl,bc
            ld (eg_yf),hl
            ld d,0
            ld hl,arc_tab
            add hl,de
            ld a,(eg_y)
            sub (hl)                    ; y - hauteur de la cloche
            ret c
            cp 187
            ret nc
            ld c,a
            ld a,(eg_x)
            cp 77
            ret nc
            ld b,a
            call cell_ptr               ; derriere un ennemi (cases reservees) : on ne la voit pas,
            ld a,(hl)                   ; comme celle de Papi (le moteur dessine sur le decor, pas sur les sprites)
            and #40
            ret nz
            ld (eg_oy),bc               ; eg_oy puis eg_ox : C = y, B = x
            call scr_addr
            ld a,(eg_t)
            jp draw_gren

.land       ld a,(eg_x)                 ; explosion centree sur l'atterrissage, dans l'ecran
            sub 2
            jr nc,.l1
            xor a
.l1         cp XMAX+1
            jr c,.l2
            ld a,XMAX
.l2         ld (eg_ex),a
            ld a,(eg_y)
            sub 3
            jr nc,.l3
            xor a
.l3         cp YMAX+1
            jr c,.l4
            ld a,YMAX
.l4         ld (eg_ey),a
            ld a,2
            ld (eg_state),a
            ld a,16
            ld (eg_t),a
            ld a,#FF
            ld (eg_eox),a
            ld bc,(eg_ey)               ; une caisse posee a cote est detruite
            call crate_blast
            ld a,6                      ; les bidons explosifs dans le souffle de la grenade ennemie (module des vehicules)
            call veh_if
            ld a,(eg_ex)                ; Papi dans l'explosion ? Un bloc de carte autour (6 octets, 8 lignes) :
            ld hl,p_x                   ; 9 octets et 18 lignes avant
            sub (hl)
            add a,6
            cp 13
            jr nc,.safe
            ld a,(eg_ey)
            ld hl,p_y
            sub (hl)
            add a,8
            cp 17
            call c,player_hit
.safe       ld a,6
            jp sfx

.expl       ld hl,eg_t                  ; --- explosion : 4 images de 4 passages
            dec (hl)
            jr z,.endx
            ld a,(hl)
            rrca
            rrca
            and 3
            xor 3
            ld hl,explo_frames
            call frame_ptr
            ld bc,(eg_ey)               ; C = y, B = x
            ld de,(eg_eoy)
            ld (eg_eoy),bc
            jp draw_sprite
.endx       ld bc,(eg_ey)
            ld de,#060C
            call restore_xy
            xor a
            ld (eg_state),a
            ld bc,(eg_ey)               ; ceux qui se trouvaient dessous se redessinent
            jp wake_12

;------------------------------------------------------------------------------
; CHAMP DE DISTANCES vers Papi (inondation en largeur), etale sur plusieurs
; images. Deux tampons : les ennemis lisent le dernier champ complet pendant
; que le suivant se construit.
;   GRID est en #7000, les distances en GRID+#200 et GRID+#400 : pour passer
;   d'une case a sa distance il suffit d'un "or" sur H.
;------------------------------------------------------------------------------
            ; une voisine : HL = case. Libre et pas encore atteinte -> distance C, en file
            macro FF_TRY bk
            ld a,(hl)
            and 9                       ; mur, barbeles ou eau (bit 3) : les ennemis ne passent pas
            jr nz,@no
            ld a,h
{bk}        or 0                        ; (valeur ecrite par .start)
            ld h,a
            ld a,(hl)
            inc a
            jr nz,@no                   ; deja atteinte
            ld (hl),c
            ld a,h
            and #F9
            ld (iy+0),l
            ld (iy+1),a
            inc iy
            inc iy
@no
            mend

flow_update:
            ld a,(ff_state)
            or a
            jr z,.start
            dec a
            jr z,.clear
            jp .expand
.start      ld a,(ff_front)             ; tampon de travail = l'autre
            xor 6
            ld (.bk1+1),a
            ld (.bk2+1),a
            ld (.bk3+1),a
            ld (.bk4+1),a
            ld (.bk5+1),a
            ld (.bk6+1),a
            or hi(GRID)
            ld h,a
            ld l,0
            ld (ff_ptr),hl
            ld a,1
            ld (ff_state),a
            ld a,4
            ld (ff_cnt),a
            ret
.clear      ld hl,(ff_ptr)              ; remise a "inconnu" : 104 cases par image
            ld d,h
            ld e,l
            inc de
            ld (hl),255
            ld bc,103
            ldir
            inc hl
            ld (ff_ptr),hl
            ld hl,ff_cnt
            dec (hl)
            ret nz
            ld bc,(p_y)                 ; graine : la case de Papi, distance 0
            ld a,b
            add a,3
            ld b,a
            ld a,c
            add a,10
            ld c,a
            call cell_ptr
            ld (QUEUE),hl
            ld a,h
.bk1        or 0
            ld h,a
            ld (hl),0
            ld hl,QUEUE
            ld (ff_head),hl
            inc hl
            inc hl
            ld (ff_tail),hl
            ld a,2
            ld (ff_state),a
            ret

.expand     ld iy,(ff_tail)
            ld b,FF_CELLS
.cell       ld hl,(ff_head)
            ld a,iyl
            cp l
            jr nz,.more
            ld a,iyh
            cp h
            jp z,.done
.more       ld e,(hl)
            inc hl
            ld d,(hl)
            inc hl
            ld (ff_head),hl             ; DE = case a developper
            ld a,d
.bk2        or 0
            ld h,a
            ld l,e
            ld c,(hl)
            inc c                       ; C = distance des voisines
            ld h,d
            ld l,e
            inc l
            FF_TRY .bk3
            ld h,d
            ld l,e
            dec l
            FF_TRY .bk4
            ld hl,16
            add hl,de
            FF_TRY .bk5
            ld hl,-16
            add hl,de
            FF_TRY .bk6
            dec b
            jp nz,.cell
            ld (ff_tail),iy
            ret
.done       ld a,(ff_front)             ; champ complet : on bascule
            xor 6
            ld (ff_front),a
            xor a
            ld (ff_state),a
            ret

;------------------------------------------------------------------------------
; AFFICHAGE
;------------------------------------------------------------------------------
; adresse ecran de (B = x, C = y) -> HL       conserve BC, DE
scr_addr:
            ld l,c
            ld h,hi(SCR_LO)
            ld a,(hl)
            inc h
            ld h,(hl)
            add a,b
            ld l,a
            ret nc
            inc h
            ret

; A = numero d'image, HL = table -> HL = donnees
frame_ptr:
            add a,a
            add a,l
            ld l,a
            jr nc,.f1
            inc h
.f1         ld a,(hl)
            inc hl
            ld h,(hl)
            ld l,a
            ret

; remet le decor sur un rectangle : B = x, C = y, D = largeur, E = hauteur
restore_xy:
            call scr_addr
; HL = adresse ecran, D = largeur, E = hauteur
restore_rect:
            ld a,d
            dec a
            jr nz,.wide
            ld b,e
            jr restore_col
.wide       ld a,d
            ld (.w+1),a
            ld a,e
.line       ex af,af'
            push hl
            ld d,h
            ld e,l
            res 7,h                     ; HL = miroir, DE = ecran
.w          ld bc,6
            ldir
            pop hl
            ld a,h
            add a,8
            ld h,a
            jr nc,.ok
            ld bc,#C050
            add hl,bc
.ok         ex af,af'
            dec a
            jr nz,.line
            ret

; colonne d'un octet : HL = adresse ecran, B = hauteur
restore_col:
            res 7,h
            ld a,(hl)
            set 7,h
            ld (hl),a
            ld a,h
            add a,8
            ld h,a
            jr nc,.ok
            ld de,#C050
            add hl,de
.ok         djnz restore_col
            ret

; balle 1 octet x 6 lignes : HL = adresse ecran
draw_bullet:
            ld de,spr_balle
            ld b,6
.l          ld a,(de)
            inc de
            ld c,a
            res 7,h
            ld a,(hl)
            set 7,h
            and c
            ld c,a
            ld a,(de)
            inc de
            or c
            ld (hl),a
            ld a,h
            add a,8
            ld h,a
            jr nc,.ok
            push de
            ld de,#C050
            add hl,de
            pop de
.ok         djnz .l
            ret

;------------------------------------------------------------------------------
; affiche un sprite 6x12 qui etait en (D,E) et passe en (B,C)   (D = #FF : nouveau)
;   HL = donnees de l'image.      conserve IX
;   On ne remet le decor que sur les bandes que le sprite vient de quitter ;
;   tout le reste est ecrit une seule fois, deja compose : aucun scintillement.
;------------------------------------------------------------------------------
draw_sprite:
            ld (ds_frame),hl
            ld (ds_old),de
            ld a,d
            inc a
            jr z,.plain
            ld a,c
            sub e
            call nz,.rows               ; bandes du haut ou du bas
            ld a,b
            sub d
            jr z,.plain
            jr c,.neg
            dec a
            jr z,.right                 ; +1 octet : le cas courant
            inc a
            cp 6
            jr nc,.full
            push bc                     ; bande de gauche, A colonnes
            ld b,d
            ld c,e
            ld d,a
            ld e,12
            call restore_xy
            pop bc
            jr .plain
.neg        inc a
            jr z,.left                  ; -1 octet
            dec a
            neg
            cp 6
            jr nc,.full
            push bc                     ; bande de droite
            ld h,a
            ld a,d
            add a,6
            sub h
            ld b,a
            ld c,e
            ld d,h
            ld e,12
            call restore_xy
            pop bc
            jr .plain
.full       push bc
            ld b,d
            ld c,e
            ld de,#060C
            call restore_xy
            pop bc

.plain      call scr_addr
            call fast_ok
            jr nz,.slow
            ld de,(ds_frame)
            jp comp_c

.right      dec b                       ; la colonne quittee (x-1) est recopiee par la
            call scr_addr               ; meme routine que le sprite : variante "L"
            inc b
            call fast_ok
            jr nz,.slowcol
            ld de,(ds_frame)
            jp comp_l

.left       call scr_addr               ; colonne quittee = x+6 : variante "R"
            call fast_ok
            jr nz,.slowcol
            ld de,(ds_frame)
            jp comp_r

.slowcol    ld de,(ds_old)              ; cas lent : la colonne quittee a part
            ld a,b
            cp d
            jr nc,.sc1
            ld a,d
            add a,5
            ld d,a
.sc1        push bc
            ld b,d
            ld c,e
            ld de,#010C
            call restore_xy
            pop bc
            call scr_addr
.slow       push hl
            call occl_setup
            pop hl
            call comp_safe
            ld a,(oc_nclip)             ; bouts caches par un bord de mur
            or a
            ret z
            ld hl,oc_clip
.clip       push af
            ld b,(hl)
            inc hl
            ld c,(hl)
            inc hl
            ld d,(hl)
            inc hl
            ld e,(hl)
            inc hl
            push hl
            call restore_xy
            pop hl
            pop af
            dec a
            jr nz,.clip
            ret

.rows       push bc
            push de
            jr c,.up
            cp 12
            jr nc,.rfull
            ld b,d                      ; descendu de A lignes : bande du haut
            ld c,e
            ld d,6
            ld e,a
            jr .rgo
.up         neg
            cp 12
            jr nc,.rfull
            ld b,d                      ; monte de A lignes : bande du bas
            ld e,a
            ld a,c
            add a,12
            ld c,a
            ld d,6
.rgo        call restore_xy
            pop de
            pop bc
            ret
.rfull      ld b,d
            ld c,e
            ld de,#060C
            call restore_xy
            pop de
            pop bc
            ld d,b                      ; plus rien a effacer cote colonnes
            ret

; la routine rapide convient-elle ?  HL = adresse la plus a gauche, C = y
;   Z = oui.  Non si une ligne du sprite chevauche une frontiere de 256 octets
;   (la routine rapide n'incremente que L) ou si un mur peut cacher le sprite.
fast_ok:
            ld a,l
            cp 250
            jr nc,.no
            add a,80                    ; ligne de caracteres suivante
            cp 250
            jr nc,.no
            ld d,a
            ld a,c
            and 7
            cp 5
            jr c,.walls                 ; le sprite ne touche que 2 lignes de caracteres
            ld a,d
            add a,80
            cp 250
            jr nc,.no
.walls      ld d,hi(OCCY)
            ld e,c
            ld a,(de)
            or a
            ret
.no         or a
            ret

;------------------------------------------------------------------------------
; composition fond + sprite, 6 octets x 12 lignes
;   SP sert de pointeur de donnees : POP BC = masque + donnee en 3 microsecondes
;   (interruptions coupees le temps du sprite, environ 1 ms).
;   L'ecran est balaye en aller-retour : pour changer de ligne il suffit
;   d'ajouter 8 a H, sans revenir au debut de la ligne.
;------------------------------------------------------------------------------
            macro COMP_BYTE
            pop bc                      ; C = masque, B = donnee
            ld a,(de)                   ; decor
            and c
            or b
            ld (hl),a
            mend

            macro NEXT_LINE
            ld a,h
            add a,8
            ld h,a
            jr nc,@nw
            ld bc,#C050                 ; passage a la ligne de caracteres suivante
            add hl,bc
            ld e,l
            ld a,h
@nw         sub #80
            ld d,a
            mend

            ; side : 0 = sprite seul, 1 = + colonne de decor a gauche, 2 = a droite
            ; Boucle de 2 lignes (aller, puis retour) repetee 6 fois : le compteur vit dans B' (aucun autre code n'utilise EXX).
            ; (Les 12 lignes etaient depliees a la main : 2 Ko de code de moins pour environ 6 % de temps en plus.)
            macro COMP_FAST side
            di                          ; (une interruption ecrirait dans les donnees)
            ld (sp_save),sp
            ex de,hl
            ld sp,hl
            ex de,hl
            ld d,h
            ld e,l
            res 7,d                     ; DE = miroir
            exx
            ld b,6
            exx
@lp
            if {side}==1
              ld a,(de)
              ld (hl),a
              inc l
              inc e
            endif
            repeat 6,bt                 ; ligne "aller" : de gauche a droite
              COMP_BYTE
              if bt<6
                inc l
                inc e
              endif
            rend
            if {side}==2
              inc l
              inc e
              ld a,(de)
              ld (hl),a
            endif
            NEXT_LINE
            if {side}==2
              ld a,(de)
              ld (hl),a
              dec l
              dec e
            endif
            repeat 6,bt                 ; ligne "retour" : de droite a gauche
              COMP_BYTE
              if bt<6
                dec l
                dec e
              endif
            rend
            if {side}==1
              dec l
              dec e
              ld a,(de)
              ld (hl),a
            endif
            exx
            dec b
            exx
            jr z,@end
            NEXT_LINE
            jp @lp
@end        ld sp,(sp_save)
            ei
            ret
            mend

; HL = adresse ecran du premier octet a gauche, DE = image
comp_c:
            COMP_FAST 0
comp_l:
            COMP_FAST 1
comp_r:
            COMP_FAST 2

; version prudente : increments sur 16 bits, et chaque ligne prend ses donnees
; a l'adresse rangee dans line_ptrs (image, ligne vide ou ligne retouchee).
; Les quatre "LD SP,(line_ptrs...)" sont modifies sur place : 8 octets plus loin a chaque tour de boucle (4 lignes par tour).
comp_safe:
            di
            ld (sp_save),sp
            ld d,h
            ld e,l
            res 7,d
            exx
            ld b,3
            exx
            ld a,lo(line_ptrs)
            ld (.p1+2),a
            add a,2
            ld (.p2+2),a
            add a,2
            ld (.p3+2),a
            add a,2
            ld (.p4+2),a
.lp
.p1         ld sp,(line_ptrs+0)
            repeat 6,bt
              COMP_BYTE
              if bt<6
                inc hl
                inc de
              endif
            rend
            NEXT_LINE
.p2         ld sp,(line_ptrs+2)
            repeat 6,bt
              COMP_BYTE
              if bt<6
                dec hl
                dec de
              endif
            rend
            NEXT_LINE
.p3         ld sp,(line_ptrs+4)
            repeat 6,bt
              COMP_BYTE
              if bt<6
                inc hl
                inc de
              endif
            rend
            NEXT_LINE
.p4         ld sp,(line_ptrs+6)
            repeat 6,bt
              COMP_BYTE
              if bt<6
                dec hl
                dec de
              endif
            rend
            exx
            dec b
            exx
            jr z,.end
            ld a,(.p1+2)
            add a,8
            ld (.p1+2),a
            add a,2
            ld (.p2+2),a
            add a,2
            ld (.p3+2),a
            add a,2
            ld (.p4+2),a
            NEXT_LINE
            jp .lp
.end        ld sp,(sp_save)
            ei
            ret

;------------------------------------------------------------------------------
; prepare line_ptrs pour un sprite en (B = x, C = y) : pour chaque ligne,
;   - rien ne la cache        -> les donnees de l'image
;   - un mur la cache         -> une ligne entierement transparente
;   - cachee a moitie         -> l'image, et le bout cache sera recouvert de
;                                decor juste apres (rare : bord d'un mur)
; Les murs sont des tuiles de 8 lignes : la reponse ne change que toutes les
; 8 lignes, on travaille donc par tranches.          conserve BC, IX
;------------------------------------------------------------------------------
occl_setup:
            xor a
            ld (oc_nclip),a
            ld h,hi(OCCY)
            ld l,c
            ld a,(hl)
            or a
            jr nz,.walls
            ld hl,(ds_frame)            ; aucun mur par ici : les 12 lignes de l'image
            ld de,line_ptrs
            push bc
            ld b,12
            call .fill
            pop bc
            ret
.fill       ld a,l                      ; B lignes visibles : HL, HL+12, ...
            ld (de),a
            inc e
            ld a,h
            ld (de),a
            inc e
            ld a,l
            add a,12
            ld l,a
            jr nc,.f1
            inc h
.f1         djnz .fill
            ret

.walls      push bc
            ld a,b
            ld (oc_x),a
            ld h,hi(COLTAB)
            ld l,b
            ld a,(hl)
            ld (oc_cl),a                ; colonne de tuile a gauche
            ld a,b
            add a,5
            ld l,a
            ld a,(hl)
            ld (oc_cr),a                ; a droite
            ld h,hi(MOD6)
            ld l,b
            ld a,6
            sub (hl)
            ld (oc_k),a                 ; octets du sprite dans la colonne de gauche
            xor a
            ld (oc_line),a
            ld hl,(ds_frame)
            ld de,line_ptrs
.seg        ld a,c                      ; B = lignes jusqu'a la prochaine tuile
            and 7
            ld b,a
            ld a,8
            sub b
            ld b,a
            ld a,(oc_line)
            add a,b
            cp 12
            jr c,.s1
            ld a,(oc_line)              ; derniere tranche
            ld b,a
            ld a,12
            sub b
            ld b,a
.s1         push hl
            ld a,c
            and #F8
            add a,8
            add a,a
            ld h,hi(GRID)
            jr nc,.c0
            inc h
.c0         ld (oc_tmp),a
            ld l,a
            ld a,(oc_cl)
            or l
            ld l,a
            xor a
            bit 7,(hl)
            jr z,.c1
            inc a
.c1         ex af,af'
            ld a,(oc_tmp)
            ld l,a
            ld a,(oc_cr)
            or l
            ld l,a
            ex af,af'
            bit 7,(hl)
            jr z,.c2
            or 2
.c2         pop hl                      ; A = 0 visible, 3 cachee, 1 ou 2 a moitie
            ld (oc_mode),a
            push bc                     ; (B = taille de la tranche)
            or a
            jr z,.vis
            cp 3
            jr z,.hid
.half       push hl                     ; a moitie cachee : on note le rectangle a recouvrir
            push de
            ld hl,oc_nclip
            ld a,(hl)
            inc (hl)
            add a,a
            add a,a
            ld e,a
            ld d,0
            ld hl,oc_clip
            add hl,de
            ld a,(oc_k)
            ld e,a
            ld a,(oc_mode)
            dec a
            ld a,(oc_x)
            jr z,.hl1
            add a,e                     ; moitie droite : x+k, largeur 6-k
            ld (hl),a
            inc hl
            ld (hl),c
            inc hl
            ld a,6
            sub e
            jr .hl2
.hl1        ld (hl),a                   ; moitie gauche : x, largeur k
            inc hl
            ld (hl),c
            inc hl
            ld a,e
.hl2        ld (hl),a
            inc hl
            ld (hl),b
            pop de
            pop hl
            jr .vis
.hid        ld a,lo(transp_line)
            ld (de),a
            inc e
            ld a,hi(transp_line)
            ld (de),a
            inc e
            ld a,l
            add a,12
            ld l,a
            jr nc,.h1
            inc h
.h1         djnz .hid
            jr .adv
.vis        call .fill
.adv        pop bc
            push bc
            ld a,(oc_line)
            add a,b
            ld (oc_line),a
.next       pop bc
            ld a,c
            add a,b
            ld c,a
            ld a,(oc_line)
            cp 12
            jp c,.seg
            pop bc
            ret

;------------------------------------------------------------------------------
; TEXTE (score, vies...) : police 4x6 pixels, 2 octets de large
;------------------------------------------------------------------------------
; HL = texte termine par 0, B = x, C = y
print_text:
.next       ld a,(hl)
            or a
            ret z
            inc hl
            cp 5                        ; codes 1 a 4 = tuiles 8x8 : 1 grenade, 2 mission "tuer", 3 mission "Time Attack", 4 coeur (vies)
            jr nc,.chr
            dec a
            rrca
            rrca
            rrca                        ; x 32 octets
            push hl
            ld hl,TILE_BASE
            ld e,a
            ld d,0
            add hl,de
            ex de,hl
            pop hl
.tile       push hl
            push bc
            dec c                       ; la tuile de 8 lignes commence une ligne plus haut que le texte (y = 192)
            call put_tile
            pop bc
            pop hl
            inc b
            inc b
            inc b
            inc b
            jr .next
.chr        push hl
            push bc
            ld hl,font_chars
            ld e,0
.find       cp (hl)
            jr z,.found
            inc hl
            inc e
            ld d,a
            ld a,e
            cp font_count
            ld a,d
            jr nz,.find
            ld e,10                     ; inconnu : espace
.found      ld a,e
            call put_glyph
            pop bc
            pop hl
            inc b
            inc b
            jr .next

; tuile 8x8 (4 octets x 8 lignes) : DE = donnees, B = x, C = y.  conserve rien
put_tile:
            ld a,8
.l          ex af,af'
            push bc
            call scr_addr
            ex de,hl
            ldi
            ldi
            ldi
            ldi
            ex de,hl
            pop bc
            inc c
            ex af,af'
            dec a
            jr nz,.l
            ret

; A = numero de glyphe -> HL = glyph_buf : 5 lignes de 2 octets (pixels du stylo 13).  conserve BC
;   la police est stockee en 15 bits par caractere (3 colonnes x 5 lignes) : on la depaquette ici
expand_glyph:
            ld l,a
            ld h,0
            add hl,hl
            ld de,font
            add hl,de
            ld e,(hl)
            inc hl
            ld d,(hl)                   ; DE = 5 lignes de 3 bits, la ligne du haut en tete
            push bc
            ld hl,glyph_buf
            ld b,5
.row        ld c,0
            repeat 3
              sla e
              rl d
              rl c                      ; C = 3 bits de la ligne : bit 2 gauche, 1 milieu, 0 droite
            rend
            xor a
            bit 2,c
            jr z,.a
            ld a,#A2                    ; pixel de gauche (stylo 13)
.a          bit 1,c
            jr z,.b
            or #51                      ; pixel de droite
.b          ld (hl),a
            inc hl
            xor a
            bit 0,c
            jr z,.c
            ld a,#A2
.c          ld (hl),a
            inc hl
            djnz .row
            pop bc
            ld hl,glyph_buf
            ret

; A = numero de glyphe, B = x, C = y
put_glyph:
            call expand_glyph
            ex de,hl
            ld a,5
.l          ex af,af'
            push bc
            call scr_addr
            ld a,(de)
            ld (hl),a
            inc de
            inc hl
            ld a,(de)
            ld (hl),a
            inc de
            pop bc
            inc c
            ex af,af'
            dec a
            jr nz,.l
            ret

font_chars: db '0123456789 ACEGIMNOPRSVUTFLD-HKZ!.Y+BQW'
font_count  equ 39
txt_hud:    db 'SCORE       HI        ',4,'  ',1,'    '
hud_tile:   db 2,0   ; glyphes de 2 octets : SCORE x=0 chiffres x=12 (5) / HI x=24 chiffres x=30 (5) / coeur (tuile, 4 octets) x=44 vies x=48 / grenade (tuile) x=52 grenades x=57 / tuile mission x=64 ennemis restant x=69
txt_over:   db 'GAME OVER !',0
txt_win:    db 'MISSION DONE !',0

; +1 sur le chiffre HL du score (retenue vers la gauche).   conserve BC, DE
add_score:
            inc (hl)
            ld a,(hl)
            cp 10
            jr c,.done
            ld (hl),0
            dec hl
            ld a,l
            cp lo(score-1)
            jr nz,add_score
.done       ld a,(score)                ; le score est limite a 5 chiffres affiches (99990 au plus) : on plafonne
            or a
            jr z,.ok4
            ld hl,score
            ld (hl),0
            inc hl
            ld (hl),9
            inc hl
            ld (hl),9
            inc hl
            ld (hl),9
            inc hl
            ld (hl),9
.ok4        ld hl,hud_dirty
            set 0,(hl)
            call check_life
                                        ; le score depasse-t-il le hi-score ?  (conserve BC, DE)
check_hi:
            push bc
            push de
            ld hl,score
            ld de,hiscore
            ld b,5
.c          ld a,(de)
            cp (hl)                     ; hi - score, chiffre par chiffre depuis la gauche
            jr c,.copy                  ; score plus grand
            jr nz,.end                  ; hi-score plus grand
            inc hl
            inc de
            djnz .c
            jr .end
.copy       ld hl,score
            ld de,hiscore
            ld bc,5
            ldir
            ld hl,hud_dirty
            set 3,(hl)
.end        pop de
            pop bc
            ret

; une vie de plus tous les 250 points : quand les 3 chiffres de gauche du score (milliers et centaines) ou la
; moitie (chiffre suivant >= 5) ont change.   conserve BC, DE
check_life:
            push bc
            push de
            call life_flag
            ld c,a
            ld hl,score
            ld de,life_k
            ld b,3
.c          ld a,(de)
            cp (hl)
            jr nz,.bonus
            inc hl
            inc de
            djnz .c
            ld a,(life_h)
            cp c
            jr z,.end
.bonus      ld a,c
            ld (life_h),a
            ld hl,score
            ld de,life_k
            ld bc,3
            ldir
            ld a,(lives)
            cp 9
            jr nc,.end
            inc a
            ld (lives),a
            ld a,150
            ld (life_bl),a
            ld hl,hud_dirty
            set 1,(hl)
            ld a,8
            call sfx
.end        pop de
            pop bc
            ret

; A = quart de millier du score (0..3) : 0-249, 250-499, 500-749, 750-999  (une vie tous les 250 points)
;   = (2 x centaines + (dizaines >= 5)) / 5
life_flag:  ld a,(score+4)
            cp 5
            sbc a,a
            inc a                       ; 1 si dizaines >= 5
            ld b,a
            ld a,(score+3)
            add a,a
            add a,b
            ld b,0
.d          sub 5
            jr c,.e
            inc b
            jr .d
.e          ld a,b
            ret

; Time Attack : le compteur du HUD (kills_left) perd 1 toutes les 50 images, tant que Papi joue
time_tick:  ld a,(mtime)
            or a
            ret z
            ld a,(p_state)
            or a
            ret nz
            ld hl,time_f
            dec (hl)
            ret nz
            ld (hl),50
            ld hl,kills_left
            dec (hl)
            ld hl,hud_dirty
            set 2,(hl)
            ret

; un seul element du bandeau redessine par image, et seulement s'il a change
;   hud_dirty : bit0 score, bit1 vies, bit2 ennemis, bit3 hi-score
hud_update:
            ld hl,hud_dirty
            ld a,(hl)
            or a
            ret z
            bit 3,a
            jr z,.nohi
            res 3,(hl)
            ld hl,hiscore
            ld bc,#1EC1                 ; x = 30
            jr hud_number
.nohi       bit 0,a
            jr z,.h1
            res 0,(hl)
            ld hl,score
            ld bc,#0CC1                 ; x = 12
            jr hud_number
.h1         bit 1,a
            jr z,.h2
            res 1,(hl)
            ld a,(life_bl)              ; vie gagnee : le nombre clignote (cache pendant 8 images sur 16)
            and 8
            ld a,(lives)
            jr z,.lv
            ld a,10                     ; (espace)
.lv         ld bc,#30C1                 ; x = 48
            jp put_glyph
.h2         bit 2,a
            jr z,.h3
            res 2,(hl)
            ld a,(bk_on)
            or a
            jp nz,hud_kills             ; boss : points de vie en couleur
            ld a,(z80_m)
            or a
            jr nz,hud_z80               ; mission Z80 : le HUD montre 0 (Z80 pas encore la) puis 1 (il est au sol)
            ld a,(kills_left)           ; ennemis restant a abattre pour finir la partie
            ld bc,#45C1                 ; x = 69
            jp put_2digits
.h3         res 4,(hl)
            ld a,(grenades)             ; grenades restantes
            ld bc,#39C1                 ; x = 57 (un octet apres la tuile)
            jp put_2digits

hud_z80:    ld a,10                     ; (espace) : un seul chiffre, a droite
            ld bc,#45C1
            call put_glyph
            ld a,(z80_f)
            ld bc,#47C1
            jp put_glyph

; HL = 5 chiffres, BC = position : 5 chiffres + un zero fixe (le score va de 10 en 10)
hud_number:
            inc hl                      ; 5 chiffres affiches (4 + le zero fixe) : on saute le premier du score
            ld d,4
.sc         ld a,(hl)
            inc hl
            push hl
            push de
            push bc
            call put_glyph
            pop bc
            pop de
            pop hl
            inc b
            inc b
            dec d
            jr nz,.sc
            xor a
            jp put_glyph

; fin de partie : HL = texte, B = x, C = y, A = octet "allume" des gros caracteres.
;   La scene est figee (voir la boucle principale) : le message, dessine directement a l'ecran, reste
;   au premier plan, par-dessus la carte et les sprites, et rien ne l'efface.
; la scene figee ne redessine plus rien, sauf quelques images ou tous les ennemis se redessinent (Papi, en mourant, les a abimes).  conserve BC
freeze_redraw:
            ld a,4
            ld (fz_n),a
            ld iy,enemies               ; tous les ennemis seront redessines pendant ces images
            ld de,ESIZE
            push bc
            ld b,MAXENEMY
.wk         ld (iy+E_LAST),#FF
            add iy,de
            djnz .wk
            pop bc
            ret

end_game:
            ld (big_on),a
            push bc                     ; (BC = position du message : a conserver)
            ld bc,MOTOR                 ; le moteur du lecteur demarre maintenant : il aura pris son regime
            ld a,1                      ; quand le joueur appuiera sur tir pour recommencer
            out (c),a
            ld (motor_on),a
            pop bc
            ld a,2
            ld (p_state),a
            ld a,d
            ld (p_timer),a
            jp print_big

victory:                                ; quota atteint (appelee quand kills_left = 0)
            ld a,(p_state)
            cp 2
            ret z
            ld a,1
            ld (won),a
            call check_hi               ; meilleur score
            ld a,(bk_on)
            or a
            jp nz,bk_final              ; boss tue : explosions, puis l'ecran CONGRATULATIONS sans passer par ZONE CLEAR
victory_zc: call blackout               ; ecran entierement noir (bandeau et HUD compris) : "ZONE CLEAR !" et son jingle
            xor a
            ld (hud_dirty),a            ; (le HUD ne se redessine plus)
            ld a,10
            call sfx
            ld hl,txt_win
            ld bc,13*256+84
            ld d,150                    ; ZONE CLEAR : la zone suivante arrive d'elle-meme au bout de 3 s
            ld a,#CF                    ; jaune vif
            jr end_game

; efface tout l'ecran visible (216 lignes de 80 octets : bandeau, HUD, carte)
blackout:
            ld c,0
.l          push bc
            ld b,0
            call scr_addr
            ld a,c
            cp 200
            jr nc,.b                    ; bandeau : la ligne commence en x = 0
            dec hl                      ; HUD et carte : 1 octet de marge a gauche
.b          ld d,h
            ld e,l
            inc de
            ld (hl),0
            ld bc,79
            ldir
            pop bc
            inc c
            ld a,c
            cp 216
            jr nz,.l
            ret

; menu principal : l'overlay (MENU_N secteurs, piste MENU_TRK) est lu en MENU_LOAD, puis la partie commence
menu_enter:
            di
            ld sp,STACK
            xor a
            ld (zone_cur),a             ; une nouvelle partie recommence a la mission 1
            ld (won),a
            ld a,CFG_MENU
            ld hl,MENU_LOAD
            call ovl_go
            jp new_game

; affiche en #4000 la banque de l'overlay (A = configuration #C0 + banque, HL = point d'entree) et l'execute ; son 'ret' revient chez
; l'appelant, apres remise du miroir (banque 4). (Le port #7Fxx se decode sur A15 = 0 et A14 = 1 : l'octet bas ne compte pas.)
ovl_go:     ld b,#7F
            out (c),a
            call .go
            ld bc,#7F00+GAME_CFG
            out (c),c
            ret
.go         jp (hl)
; le Hall of Fame depuis un autre overlay (qui a empile son adresse de retour) : voir menu.asm, intro.asm, gameover.asm
ovl_hof:    ld a,CFG_HOF
            ld hl,HOF_LOAD
            jp ovl_go

big_on:     db 0                        ; octet "allume" des gros caracteres (2 pixels du meme stylo)
big_buf:    ds 4                        ; (4 octets)
glyph_buf   equ big_buf+4               ; caractere depaquete (expand_glyph) : 10 octets
            ds 10

; HL = texte, B = x (octet), C = y, (big_on) = octet allume.  Caracteres doubles : 4 octets x 10 lignes
print_big:
.next       ld a,(hl)
            or a
            ret z
            inc hl
            push hl
            push bc
            ld hl,font_chars
            ld e,0
.find       cp (hl)
            jr z,.found
            inc hl
            inc e
            ld d,a
            ld a,e
            cp font_count
            ld a,d
            jr nz,.find
            ld e,10
.found      ld a,e
            call big_glyph
            pop bc
            pop hl
            ld a,b
            add a,4
            ld b,a
            jr .next

big_glyph:                              ; A = numero de glyphe, B = x, C = y
            call expand_glyph
            push hl
            pop ix
            ld a,5
.ln         ex af,af'
            ld e,(ix+0)
            ld d,(ix+1)
            inc ix
            inc ix
            ld hl,big_buf
            ld a,(big_on)
            ld (hl),0
            bit 7,e
            jr z,.a
            ld (hl),a
.a          inc hl
            ld (hl),0
            bit 6,e
            jr z,.b
            ld (hl),a
.b          inc hl
            ld (hl),0
            bit 7,d
            jr z,.c
            ld (hl),a
.c          inc hl
            ld (hl),0
            call .put
            inc c
            call .put
            inc c
            ex af,af'
            dec a
            jr nz,.ln
            ret
.put        call scr_addr
            ld de,big_buf
            repeat 3
              ld a,(de)
              ld (hl),a
              inc hl
              inc de
            rend
            ld a,(de)
            ld (hl),a
            ret

; A (0..99) en deux chiffres
put_2digits:
            ld d,0
.t          cp 10
            jr c,.u
            sub 10
            inc d
            jr .t
.u          push af
            push bc
            ld a,d
            call put_glyph
            pop bc
            inc b
            inc b
            pop af
            jp put_glyph

;------------------------------------------------------------------------------
; hasard : xorshift 16 bits.   conserve BC, DE
;------------------------------------------------------------------------------
rand:
            ld hl,(seed)
            ld a,h
            rra
            ld a,l
            rra
            xor h
            ld h,a
            ld a,l
            rra
            ld a,h
            rra
            xor l
            ld l,a
            xor h
            ld h,a
            ld (seed),hl
            ret

;------------------------------------------------------------------------------
; SON : 3 bruitages sur le AY, mis a jour une fois par image
;------------------------------------------------------------------------------
; A = registre, C = valeur
ay_write:
            ld b,#F4
            out (c),a
            ld b,#F6
            ld a,#C0
            out (c),a
            xor a
            out (c),a
            ld b,#F4
            out (c),c
            ld b,#F6
            ld a,#80
            out (c),a
            xor a
            out (c),a
            ret

; A = 1 tir de Papi, 2 Papi touche, 3 ennemi touche, 6 explosion, 7 lancer de grenade.
;   conserve BC, DE, HL
;   Les deux sons "WAV" de l'archive sont refaits sur le AY d'apres leur analyse :
;   TirSon     : 0,1 s de bruit blanc (spectre plat) + un clic a 4 kHz au debut,
;                volume 1 / 0,86 / 0,53 / 0,24 / 0,04 par pas de 20 ms
;                -> canal A : bruit (periode 4) + ton 4 kHz (periode 16) 2 images, 5 images
;   GrenadeSon : 0,36 s d'un ton riche qui descend de 804 a 721 Hz, volume 1 -> 0,7,
;                coupe net -> canal B : ton periode 78 -> 86, 18 images, volume 15 -> 13
sfx:
            cp 1
            jr nz,.n1
            ld a,5
            ld (snd_a),a
            ret
.n1         cp 7
            jr nz,.n8
            ld a,18
            ld (snd_b),a
            ret
.n8         cp 8
            jr nz,.n9
            ld a,24                     ; vie en plus : petit arpege montant
            ld (snd_u),a
            ret
.n9         cp 9
            jr nz,.n10
            ld a,10                     ; grenades recuperees : 3 rafales de bruit
            ld (snd_p),a
            ret
.n10        cp 10
            jr nz,.n11
            ld a,ZC_LEN                 ; jingle ZONE CLEAR
            ld (snd_z),a
            ret
.n11        cp 11
            jr nz,.noise
            ld a,SND_BOSS_LEN           ; Tir Boss
            ld (snd_bs),a
            ret
.noise      rlca
            rlca
            add a,4                     ; 2 -> 12 images, 3 -> 16
            ld (snd_c),a
            ret

sound_update:
            ld a,#3F                    ; melangeur : tout coupe, chaque son rallume son canal
            ld (snd_new),a
            ; --- canal A : jingle ZONE CLEAR (64 images) : une note par image, volume en 4 paliers ---
            ld a,(snd_z)
            or a
            jr z,.noz
            dec a
            ld (snd_z),a
            ld e,a
            ld a,ZC_LEN-1
            sub e
            ld e,a                      ; t = 0..63
            ld d,0
            ld hl,zc_per
            add hl,de
            ld l,(hl)
            ld h,0
            add hl,hl                   ; periode AY
            push hl
            ld c,l
            xor a
            call ay_write
            pop hl
            ld c,h
            ld a,1
            call ay_write
            ld a,e
            ld c,15
            cp 26
            jr c,.zv
            dec c
            cp 38
            jr c,.zv
            dec c
            cp 50
            jr c,.zv
            ld c,11
            cp 62
            jr c,.zv
            ld c,0
.zv         ld a,8
            call ay_write
            ld hl,snd_new
            res 0,(hl)                  ; ton sur A
.noz
            ; --- canal A : coup de feu (5 images) ---
            ld a,(snd_a)
            or a
            jr z,.bsn
            dec a
            ld (snd_a),a                ; 4..0 : image du coup de feu (4 = la premiere)
            ld e,a
            ld d,0
            ld hl,shot_vol
            add hl,de
            ld c,(hl)
            ld a,8
            call ay_write               ; volume A
            ld hl,snd_new
            res 3,(hl)                  ; bruit sur A
            ld a,(snd_a)
            cp 3
            jr c,.noton
            ld hl,snd_new
            res 0,(hl)                  ; + clic 4 kHz pendant les 2 premieres images
            ld c,16
            xor a
            call ay_write
            ld c,0
            ld a,1
            call ay_write
.noton      ld a,(snd_c)                ; periode du bruit (partagee) : celle du tir, sauf si
            or a                        ; un bruitage du canal C est en cours
            jr nz,.bsn
            ld c,4
            ld a,6
            call ay_write
            ; --- canal A : Tir Boss (TirBoss.wav) : bruit blanc d'une rafale, SND_BOSS_LEN images ---
.bsn        ld a,(snd_bs)
            or a
            jr z,.chb
            dec a
            ld (snd_bs),a
            ld e,a
            ld a,SND_BOSS_LEN-1
            sub e
            ld e,a
            ld d,0
            ld hl,boss_vol
            add hl,de
            ld c,(hl)
            ld a,8
            call ay_write               ; volume A
            ld c,6
            ld a,6
            call ay_write               ; periode du bruit
            ld hl,snd_new
            res 3,(hl)                  ; bruit sur A
            ; --- canal B : lancer de grenade (18 images) ---
.chb        ld a,(snd_b)
            or a
            jr z,.chp
            dec a
            ld (snd_b),a                ; 17..0
            ld e,a
            ld a,17
            sub e                       ; t = 0..17
            ld e,a
            srl a
            add a,78
            ld c,a
            ld a,2
            call ay_write               ; periode 78 -> 86
            ld c,0
            ld a,3
            call ay_write
            ld a,e
            srl a
            srl a
            srl a                       ; t / 8 : 0..2
            ld e,a
            ld a,15
            sub e
            ld c,a
            ld a,9
            call ay_write               ; volume B : 15 -> 13 (le WAV perd 30 % d'amplitude)
            ld hl,snd_new
            res 1,(hl)                  ; ton sur B
            ; --- canal B : grenades recuperees (GrenadeRecuperee.wav), 10 images : 3 rafales de bruit qui s'eteignent ---
.chp        ld a,(snd_p)
            or a
            jr z,.chu
            dec a
            ld (snd_p),a                ; 9..0
            ld e,a
            ld a,9
            sub e
            ld e,a                      ; t = 0..9
            ld d,0
            ld hl,pick_vol
            add hl,de
            ld c,(hl)
            ld a,9
            call ay_write               ; volume B
            ld c,6
            ld a,6
            call ay_write               ; periode du bruit
            ld hl,snd_new
            res 4,(hl)                  ; bruit sur B
            ; --- canal C : arpege de la vie en plus ---
.chu        ld a,(snd_u)
            or a
            jr z,.chc
            dec a
            ld (snd_u),a
            rrca
            rrca
            rrca
            and 3
            ld e,a
            ld d,0
            ld hl,jingle
            add hl,de
            ld c,(hl)
            ld a,4
            call ay_write               ; periode du canal C
            ld c,0
            ld a,5
            call ay_write
            ld c,13
            ld a,10
            call ay_write               ; volume
            ld hl,snd_new
            res 2,(hl)                  ; ton sur C
            ; --- canal C : bruitages (touche, explosion) ---
.chc        ld a,(snd_c)
            or a
            jr z,.mix
            dec a
            ld (snd_c),a
            cp 16
            jr c,.v15
            ld a,15
.v15        ld c,a
            ld a,10
            call ay_write
            ld a,(snd_c)
            cpl
            and 15
            add a,8
            ld c,a
            ld a,6
            call ay_write
            ld a,(snd_c)
            or a
            jr z,.mix
            ld hl,snd_new
            res 5,(hl)                  ; bruit sur C
.mix        ld a,(snd_new)
            ld c,a
            ld a,(snd_mix)
            cp c
            ret z
            ld a,c
            ld (snd_mix),a
            ld a,7
            jp ay_write

pick_vol:   db 15,13,10,6,15,13,10,6,15,13   ; volume par image : une rafale toutes les 4 images (80 ms), comme le WAV
jingle:     db 30,45,70                 ; periodes, de la derniere note a la premiere
shot_vol:   db 5,9,12,14,15             ; volume du coup de feu, indexe par l'image restante 0..4

;------------------------------------------------------------------------------
; donnees
;------------------------------------------------------------------------------
            include 'frames.asm'
transp_line:
            repeat 6
              db #FF,0
            rend

            include 'gfx.asm'

; PARAMETRES DE ZONE : dans le fichier de zone (en-tete de 16 octets : unites simultanees, ennemis a abattre,
; premier officier x16, nombre de types, puis (type, pourcentage) par type) ; voir tools/convert.py, build_zone

; variables permanentes (persistent d'une partie a l'autre : hors de 'vars'), rangees en memoire basse juste apres 'vars' pour liberer 30 octets du programme (initialisees par boot)
PVARS       equ VARBASE+216             ; = vars_end
hp_thr      equ PVARS                   ; (3) boss : seuils de la barre de vie (vert / jaune / orange) ; 0 : pas de boss
bk_on       equ hp_thr
z80_m       equ PVARS+3                 ; mission 'Find the Z80' (apres le quota de kills, le Z80 tombe du dernier ennemi abattu) : 1 ; charge avec la zone
z80_img     equ PVARS+4                 ; (2) image 12 x 12 du Z80 (emplacement de sprite de la zone) ; mission du boss : images passees a couvert avant de repartir (bk_cov)
bk_nb       equ PVARS+6                 ; boss : balles par rafale
bk_dl       equ PVARS+7                 ; boss : images entre la fin d'une rafale et la suivante
nb_wanted   equ PVARS+8                 ; fixe par load_zone_data d'apres la zone
spawn_full  equ PVARS+9                 ; points d'apparition apres 15 s
spawn_n     equ PVARS+10                ; points d'apparition de la zone (parametre de la zone)
mtime       equ PVARS+11                ; 1 = Time Attack : le compteur du HUD descend d'une unite par seconde
zone_kills  equ PVARS+12                ; ennemis a abattre pour finir la partie (idem)
zone_cur    equ PVARS+13                ; zone en cours (0 .. NZONES-1)
score_keep  equ PVARS+14                ; (5) score garde d'une zone a la suivante
lives_keep  equ PVARS+19                ; vies gardees d'une mission a la suivante
carry       equ PVARS+20                ; 1 = reprendre score_keep dans la nouvelle partie
won         equ PVARS+21                ; 1 = la partie finie etait une victoire : la zone suivante se charge
motor_on    equ PVARS+22                ; 1 = le moteur du lecteur tourne deja
hiscore     equ PVARS+23                ; (5) meilleur score (hors de 'vars', donc jamais remis a zero)
meter       equ PVARS+28                ; touche M : jauge de charge dans la bordure
snd_mix     equ PVARS+29
acc_zone    equ PVARS+30                ; zone choisie par le code d'acces du menu (0 = zone 1, 1 = zone 2...) : la partie y commence
veh_on      equ PVARS+31                ; zone 4 : mode vehicule de la mission (0 aucun, 1 camion + quota ou chrono, 2 camion + barre de vie, 3 WarTruck + barre de vie : fin de zone), lu dans l'en-tete
PVARS_LEN   equ 32
WTR_ZP      equ PVARS+PVARS_LEN         ; eau animee : voir water.asm
; Hall of Fame : 7 entrees de 15 octets (nom sur 10 caracteres, 5 chiffres) rangees dans les 16 octets libres qui terminent chaque trou de la page A
; (13 images de 144 octets = 1872 octets sur 1888) : entree n en HOF_E0 + n x #800.  Aucun octet du programme permanent n'est utilise.
HOF_MIN     equ 500                     ; SCORE MINIMUM pour entrer dans le Hall of Fame, en points (0 a 9999 ; le score va de 10 en 10) : a regler
HM_K        equ (HOF_MIN-(HOF_MIN mod 1000))/1000   ; ses chiffres : milliers, centaines, dizaines
HM_H        equ ((HOF_MIN mod 1000)-(HOF_MIN mod 100))/100
HM_T        equ ((HOF_MIN mod 100)-(HOF_MIN mod 10))/10
HOF_E0      equ #8750
HOF_MAG1    equ #875F                   ; octets magiques : table creee (par le menu, hof_init)
HOF_MAG2    equ #8F5F
HOF_MODE    equ #975F                   ; 0 = classement qui defile, 1 = saisie du nom (lu par l'overlay HOF)

; VARIABLES de la partie (remises a zero a chaque nouvelle partie) : en memoire basse, #0040-#01B0, libre (la pile, sous #0200,
; ne descend pas sous #01E0). Ce ne sont plus des octets du fichier : adresses calculees par equ.
VARBASE     equ #0040
vars        equ VARBASE
frame       equ VARBASE+0
joy         equ VARBASE+1
oldkeys     equ VARBASE+2
keymap      equ VARBASE+3
seed        equ VARBASE+13
p_y         equ VARBASE+15   ; p_y puis p_x : ld bc,(p_y) donne C = y, B = x
p_x         equ VARBASE+16
p_oy        equ VARBASE+17   ; idem pour l'ancienne position
p_ox        equ VARBASE+18
p_dir       equ VARBASE+19
p_anim      equ VARBASE+20
p_atick     equ VARBASE+21
p_state     equ VARBASE+22   ; 0 en vie, 1 touche, 2 partie finie
p_timer     equ VARBASE+23
p_hold      equ VARBASE+24   ; images d'appui sur tir, puis p_lock (consecutifs)
p_lock      equ VARBASE+25   ; 1 = appui long utilise : pas de tir avant le relachement
p_inv       equ VARBASE+26
lives       equ VARBASE+27
score       equ VARBASE+28
hud_dirty   equ VARBASE+33
fz_n        equ VARBASE+34   ; images de mise a jour des ennemis apres la fin de partie
cov_now     equ VARBASE+35   ; 1 = l'ennemi qui reflechit est en couverture (sa balle traversera son obstacle)
grenades    equ VARBASE+36   ; grenades restantes (GREN_MAX au plus)
crate_st    equ VARBASE+37   ; caisse de grenades : 0 aucune, 1 au sol, 2 en train de tomber
crate_ty    equ VARBASE+38   ; y d'arrivee de la caisse
crate_cd    equ VARBASE+39   ; delai avant la prochaine caisse (0 = pas commandee)
crate_y     equ VARBASE+40   ; (y puis x : charges par 'ld bc,(crate_y)')
crate_x     equ VARBASE+41
crate_oy    equ VARBASE+42   ; position affichee (oy puis ox ; ox = #FF : pas encore dessinee)
crate_ox    equ VARBASE+43
bul_n       equ VARBASE+44
bul_hide    equ VARBASE+45
dg_v        equ VARBASE+46   ; pas vertical puis horizontal de la diagonale (ld hl,(dg_v))
dg_h        equ VARBASE+47
eg_state    equ VARBASE+48   ; grenade des officiers : 0 libre, 1 en vol, 2 explosion
eg_t        equ VARBASE+49
eg_xf       equ VARBASE+50   ; x puis y : partie fractionnaire puis entiere (ld hl,(eg_xf))
eg_x        equ VARBASE+51
eg_yf       equ VARBASE+52
eg_y        equ VARBASE+53
eg_vx       equ VARBASE+54   ; vitesse (x256) par image
eg_vy       equ VARBASE+56
eg_oy       equ VARBASE+58   ; derniere position affichee (y puis x)
eg_ox       equ VARBASE+59
eg_ey       equ VARBASE+60   ; explosion (y puis x)
eg_ex       equ VARBASE+61
eg_eoy      equ VARBASE+62
eg_eox      equ VARBASE+63
p_fx        equ VARBASE+64   ; Papi : cumuls de vitesse
p_fy        equ VARBASE+65
kills_left  equ VARBASE+66   ; ennemis restant a abattre (parametre de la zone)
life_k      equ VARBASE+67   ; milliers deja recompenses (3 chiffres de gauche du score)
snd_u       equ VARBASE+70   ; son de vie en plus
off_tmr     equ VARBASE+71   ; officiers : minuterie avant le prochain lancer (pas de 4 images)
g_state     equ VARBASE+83   ; 0 pas de grenade, 1 en vol, 2 explosion
g_t         equ VARBASE+84
g_t3        equ VARBASE+85
g_dx        equ VARBASE+86
g_dy        equ VARBASE+87
g_y         equ VARBASE+88   ; (y puis x, comme pour Papi)
g_x         equ VARBASE+89
g_oy        equ VARBASE+90
g_ox        equ VARBASE+91
g_ey        equ VARBASE+92
g_ex        equ VARBASE+93
g_eoy       equ VARBASE+94
g_eox       equ VARBASE+95
en_cur      equ VARBASE+96   ; prochain ennemi a traiter
en_cnt      equ VARBASE+97
en_dt       equ VARBASE+98
en_spd      equ VARBASE+99   ; decalage de vitesse de l'ennemi en cours (0 ou 32)
tick        equ VARBASE+100
tick_lim    equ VARBASE+101   ; on ne commence plus un ennemi a partir de ce top (TICK_STOP, ou un de moins si la caisse descend)
since       equ VARBASE+102
spawn_ix    equ VARBASE+103   ; prochain point d'apparition (on les parcourt tour a tour)
snd_a       equ VARBASE+104
snd_b       equ VARBASE+105
snd_c       equ VARBASE+106
snd_z       equ VARBASE+107   ; jingle ZONE CLEAR : images restantes
snd_p       equ VARBASE+108   ; grenades recuperees : images restantes
snd_new     equ VARBASE+109
ff_state    equ VARBASE+110
ff_front    equ VARBASE+111
ff_cnt      equ VARBASE+112
ff_ptr      equ VARBASE+113
ff_head     equ VARBASE+115
ff_tail     equ VARBASE+117
sp_save     equ VARBASE+119
ds_frame    equ VARBASE+121
ds_old      equ VARBASE+123
oc_cl       equ VARBASE+125
oc_cr       equ VARBASE+126
oc_k        equ VARBASE+127
oc_mode     equ VARBASE+128
oc_line     equ VARBASE+129
oc_tmp      equ VARBASE+130
rowocc      equ VARBASE+131
line_ptrs   equ VARBASE+160   ; dans une meme page de 256 octets (INC E)
oc_clip     equ VARBASE+184
oc_nclip    equ VARBASE+196
oc_x        equ VARBASE+197
eg_acc      equ VARBASE+198  ; grenade des officiers : cumul de vitesse (218/256 = -15 %)
time_f      equ VARBASE+199  ; Time Attack : images avant la prochaine seconde
life_h      equ VARBASE+200  ; vie bonus : 1 si le 4e chiffre du score etait >= 5
b_cd        equ VARBASE+201  ; boss : images avant la prochaine rafale
b_n         equ VARBASE+202  ; balles restant a tirer dans la rafale
b_t         equ VARBASE+203  ; images avant la prochaine balle (aussi : compteur de l'animation de mort)
b_gcd       equ VARBASE+204  ; images avant la prochaine grenade
b_gi        equ VARBASE+205  ; protection apres un souffle de grenade (corps et tete ne comptent qu'une fois)
b_cov       equ VARBASE+206  ; 1 = le boss est a couvert (ses balles traversent l'obstacle)
ymin        equ VARBASE+207  ; plus petit y accepte par can_stand_e (12 pour le corps du boss, 0 sinon)
snd_bs      equ VARBASE+208  ; son Tir Boss : images restantes
b_cin       equ VARBASE+209  ; (2) boss : images passees a couvert
b_cno       equ VARBASE+211  ; boss : images restant a avancer sans chercher de couvert
z80_f       equ VARBASE+212  ; 1 = le Z80 est au sol (la caisse sert d'objet)
spawn_t     equ VARBASE+213  ; temps depuis le debut de la mission (en 4 images)
life_bl     equ VARBASE+214  ; images de clignotement restantes du nombre de vies
v_init      equ VARBASE+215  ; vehicules : 1 = le module des vehicules (banque 7) a prepare la mission
vars_end    equ VARBASE+216
            assert vars_end<=#01B0


;------------------------------------------------------------------------------
; DEMARRAGE : execute une seule fois, puis ecrase par les tables et le miroir (il est en #4000+)
;------------------------------------------------------------------------------
; sprites de Papi, explosions et caisse : recopies au demarrage dans les trous de la page video A. Ce bloc (et les
; tables par zone, #3000-#31FF) est ensuite ecrase ; le code de demarrage, lui, est APRES, hors de portee des tables.
            include 'boss.asm'
perm_end:
            assert $<=XSLOT_BASE                ; la partie permanente doit finir avant les emplacements d'images supplementaires
            ds XSLOT_BASE-$
            ds NXS*144                          ; images d'unites en plus (zone du boss) : chargees par load_zone_data
            assert $<=#3000                     ; ...et avant les tables de la zone (#3000)
            include 'gfx_spr.asm'
boot:
            di
            ld sp,STACK
            xor a
            ld (acc_zone),a
            ld a,3                      ; variables permanentes a valeur initiale
            ld (lives_keep),a
            ld a,8
            ld (nb_wanted),a
            ld a,1
            ld (spawn_n),a
            ld bc,#7F8C                 ; MODE 0, ROM haute et basse coupees
            out (c),c
            ld hl,black_pal             ; ecran noir jusqu'a l'affichage du logo
            call set_palette
            ld hl,spr_papi              ; sprites de Papi et explosions (fin du fichier) -> 3 premiers trous de la page A
            ld de,#8000
            ld b,3
.spc        push bc
            push de
            ld bc,SPRSLOT*144
            ldir
            pop de
            ld a,d
            add a,8
            ld d,a
            pop bc
            djnz .spc
            ld hl,water_src             ; eau animee (APRES la copie des sprites : WTR_LO et WTR_HI tombent dans le bloc spr_papi, qui commence en #3000) : routines recopiees en memoire basse et dans le trou de la grille (water.asm)
            ld de,WTR_ZP
            ld bc,water_zp_len
            ldir
            ld hl,water_src+water_zp_len
            ld de,WTR_Z0
            ld bc,water_z0_len
            ldir
            ld hl,water_src+water_zp_len+water_z0_len
            ld de,WTR_HI
            ld bc,water_hi_len
            ldir
            ld hl,water_src+water_zp_len+water_z0_len+water_hi_len
            ld de,WTR_LO
            ld bc,water_lo_len
            ldir
            call silence
            call build_tables           ; (ecrase la fin de ce fichier, ou etaient les sprites : ils sont deja copies)
            ifdef TEST64
              jp no128                  ; (essai : se comporter comme un CPC 64 Ko)
            endif
            ld hl,ovlb_src              ; 128 Ko ? (le test change de banque : il s'execute en memoire basse, copie ici)
            ld de,OVLB
            ld bc,ovlb_end-ovlb_src
            ldir
            call OVLB
            jp nz,no128
            call fdc_on                 ; le moteur reste en marche : la zone se chargera des l'appui sur tir
            ld a,LOGO_TRK               ; --- le logo du studio, puis "PRESENTS" avec le jingle de fin de mission
            ld b,0
            ld de,LOGO_N
            ld hl,COVER_LOAD
            call load_data
            ld hl,COVER_LOAD
            ld de,#C000
            call unpack
            ld hl,logo_pal
            call set_palette
            xor a                       ; sons a zero (variables non initialisees au demarrage)
            ld (snd_a),a
            ld (snd_b),a
            ld (snd_c),a
            ld (snd_z),a
            ld (snd_p),a
            ld (snd_u),a
            ld (snd_bs),a
            dec a
            ld (snd_mix),a              ; (valeur impossible : le melangeur est ecrit a la premiere image)
            ld bc,50                    ; le logo seul pendant 1 seconde
.l0         push bc
            ld b,#F5
.l01        in a,(c)
            rra
            jr c,.l01
.l02        in a,(c)
            rra
            jr nc,.l02
            pop bc
            dec bc
            ld a,b
            or c
            jr nz,.l0
            ld hl,logo_text             ; le mot, ligne par ligne
            ld b,10
.pl         push bc
            ld e,(hl)
            inc hl
            ld d,(hl)
            inc hl
            ld bc,32
            ldir
            pop bc
            djnz .pl
            ld a,10                     ; jingle ZONE CLEAR
            call sfx
            ld bc,200                   ; puis 4 secondes avant la cover (le jingle dure 64 images)
.lw         push bc
            ld b,#F5
.l1         in a,(c)
            rra
            jr c,.l1
.l2         in a,(c)
            rra
            jr nc,.l2
            call sound_update
            pop bc
            dec bc
            ld a,b
            or c
            jr nz,.lw
            ld a,COVER_TRK
            ld b,COVER_SEC
            ld de,COVER_N
            ld hl,COVER_LOAD
            call load_data              ; la cover (compressee) est lue (le logo reste a l'ecran)...
            ld hl,black_pal
            call set_palette
            ld hl,COVER_LOAD
            ld de,#C000
            call unpack                 ; ... puis decompressee dans l'ecran
            ld hl,cover_pal
            call set_palette
            call OVLB+(ovlb_load-ovlb_src)  ; les ecrans (menu, missions, game over, Hall of Fame) : lus UNE fois, dans les banques 4, 5 et 6
            di                          ; (la voix numerisee coupait les interruptions ici : elles restent coupees jusqu'a l'installation de notre routine)
            ld bc,50*5                  ; la cover reste a l ecran 5 secondes au total (250 images), puis le menu principal
.wait       push bc
            ld b,#F5
.w1         in a,(c)
            rra
            jr c,.w1
.w2         in a,(c)
            rra
            jr nc,.w2
            pop bc
            dec bc
            ld a,b
            or c
            jr nz,.wait
            ld hl,black_pal             ; ecran noir pendant le changement de mode video
            call set_palette
            ld hl,crtc_tab              ; overscan : R6 = rangees, R12/R13 = ecran de 32 Ko #8000-#FFFF
            ld d,0
.crt        ld bc,#BC00
            out (c),d
            ld b,#BD
            ld a,(hl)
            out (c),a
            inc hl
            inc d
            ld a,d
            cp 14
            jr nz,.crt
            ld a,#C3                    ; notre routine d'interruption en #0038
            ld (#38),a
            ld hl,int_handler
            ld (#39),hl
            im 1
            jp menu_enter               ; menu principal (overlay lu sur la disquette), puis la 1re zone

; --- bloc recopie en OVLB (memoire basse, libre au demarrage) : il change de banque, donc ne peut pas s'executer dans la fenetre #4000 ---
;   OVLB       : test des 128 Ko (retour : Z = oui)
;   OVLB+ovlb_load-ovlb_src : lit les 4 overlays dans leurs banques ; le miroir (banque 1) revient ensuite
OVLB        equ #3000
ovlb_src:   ld hl,#7FF0                 ; la meme adresse, vue dans la banque 1 puis dans la banque 4 : deux cases differentes
            ld bc,#7FC0
            out (c),c
            ld (hl),#A5
            ld c,#C4
            out (c),c
            ld (hl),#5A                 ; (sur un 64 Ko, c'est la meme case : elle vaut maintenant #5A)
            ld c,#C0
            out (c),c
            ld a,(hl)
            cp #A5
            ret
ovlb_load:  ld hl,OVLB+(ovlb_tab-ovlb_src)
.lo         ld a,(hl)
            inc hl
            ld b,#7F
            out (c),a                   ; la banque de l'overlay apparait en #4000
            ld a,(hl)                   ; piste
            inc hl
            ld e,(hl)
            inc hl
            ld d,(hl)                   ; secteurs
            inc hl
            ld c,(hl)
            inc hl
            ld b,(hl)                   ; adresse de chargement
            inc hl
            push hl                     ; suite de la table
            ld h,b
            ld l,c
            ld b,0                      ; a partir du secteur 0 de la piste
            call load_data
            pop hl
            ld a,l
            cp (OVLB+(ovlb_tab_end-ovlb_src))&255
            jr nz,.lo
            ld hl,BOSS_LOAD+BOSS_PAD    ; la banque 7 est encore en #4000 : son image (compressee, lue en dernier) est decompressee sur place
            ld de,BOSS_LOAD
            call unpack
            ld bc,#7F00+GAME_CFG        ; le miroir revient
            out (c),c
            jp fdc_off                  ; le moteur s'arrete : plus de lecture avant la premiere zone
ovlb_tab:   db CFG_MENU,MENU_TRK
            dw MENU_N,MENU_LOAD
            db CFG_INTRO,INTRO_TRK
            dw INTRO_N,INTRO_LOAD
            db CFG_GO,GO_TRK
            dw GO_N,GO_LOAD
            db CFG_HOF,HOF_TRK
            dw HOF_N,HOF_LOAD
            db CFG_BOSS,BOSS_TRK
            dw BOSS_N,BOSS_LOAD+BOSS_PAD
ovlb_tab_end:
ovlb_end:
            assert ovlb_end-ovlb_src<=#E0

; pas de 128 Ko : message, et on s'arrete
no128:      ld bc,#7F8C                 ; MODE 0, ROM haute et basse coupees (deja fait)
            out (c),c
            ld hl,#C000                 ; ecran vide
            ld de,#C001
            ld bc,#3FFF
            ld (hl),0
            ldir
            ld bc,#7F00                 ; encre 0 : noir, encre 1 : blanc
            out (c),c
            ld c,#54
            out (c),c
            ld bc,#7F01
            out (c),c
            ld c,#4B
            out (c),c
            ld a,#C0                    ; stylo 1 : les deux pixels de l'octet
            ld (big_on),a
            ld hl,txt_no128a
            ld bc,14*256+60
            call print_big
            ld hl,txt_no128b
            ld bc,14*256+84
            call print_big
            jr $
txt_no128a: db '128K REQUIRED',0
txt_no128b: db 'CPC 6128 ONLY',0

black_pal:  ds 17,#54
set_palette:                            ; HL = 17 octets (16 encres + bordure)
            xor a
.p          ld b,#7F
            out (c),a
            ld e,(hl)
            out (c),e
            inc hl
            inc a
            cp 17
            jr nz,.p
            ret
            include 'cover.inc'

silence:
            ld a,7
            ld c,#3F
            call ay_write
            ld a,8
            ld c,0
            call ay_write
            ld a,10
            ld c,0
            jp ay_write

build_tables:
            ld de,SCR_LO
            ld hl,#C051                 ; y = 0 -> ligne ecran 8 (1 octet de marge a gauche) :
            ld b,192                    ; le decor est decale de 8 lignes vers le bas
            call .lines
            ld hl,#C001                 ; y = 192..199 -> lignes ecran 0..7 : le bandeau
            ld b,8                      ; (HUD) est en HAUT de l'ecran, texte a y = 193
            call .lines
            ld hl,BANNER                ; y = 200..215 : les 16 lignes du bandeau (2 rangees)
            ld c,2
.brow       ld b,8
            push hl
.bln        ld a,l
            ld (de),a
            inc d
            ld a,h
            ld (de),a
            dec d
            inc e
            ld a,h
            add a,8
            ld h,a
            djnz .bln
            pop hl
            ld a,l
            add a,80
            ld l,a
            jr nc,.bnc
            inc h
.bnc        dec c
            jr nz,.brow
            jr .cols
.lines
.lt         ld a,l
            ld (de),a
            inc d
            ld a,h
            ld (de),a
            dec d
            inc e
            ld a,h
            add a,8
            ld h,a
            jr nc,.lk
            push bc
            ld bc,#C050
            add hl,bc
            pop bc
.lk         djnz .lt
            ret
.cols
            ld hl,COLTAB                ; x/6 (15 = hors carte, toujours plein)
            ld c,0
.ct         ld b,6
.c2         ld (hl),c
            inc l
            jr z,.ctd
            djnz .c2
            ld a,c
            cp 15
            jr z,.ct
            inc c
            jr .ct
.ctd
            ld hl,MOD6                  ; x mod 6
            xor a
.m6         ld (hl),a
            inc a
            cp 6
            jr nz,.m7
            xor a
.m7         inc l
            jr nz,.m6
            ret

;       R0  R1  R2  R3   R4 R5 R6 R7 R8 R9 R10 R11 R12 R13
crtc_tab:   db 63, 40, 46, #8E, 38, 0, 27, 32, 0, 7, 0,  0,  #2F, #B0

            include 'water.asm'
prog_end:
            ifndef SNA
              save 'PAPICPC.BIN',prog_start,prog_end-prog_start,DSK,'build/PAPICPC.dsk'
            endif

;------------------------------------------------------------------------------
; overlay du menu principal : assemble en MENU_LOAD, ecrit tel quel dans build/menu.bin (tools/mkdisk.py le pose sur la piste MENU_TRK)
;------------------------------------------------------------------------------
            org MENU_LOAD
menu_start:
            include 'menu.asm'
menu_end:
            assert menu_end-menu_start<=MENU_N*512
            assert menu_end<=TAB_L*256
            save 'build/menu.bin',menu_start,menu_end-menu_start

;------------------------------------------------------------------------------
; overlay des ecrans de mission : en #4000-#47FF (sous la zone de preparation de la zone, il y reste jusqu'a la construction du miroir) : build/intro.bin
;------------------------------------------------------------------------------
            org INTRO_LOAD,#A000                ; assemble pour #4000, range en #A000 (ce bloc recouvrirait le programme)
intro_start:
            include 'intro.asm'
intro_stop:
            assert intro_stop-intro_start<=INTRO_N*512
            assert intro_stop-intro_start+#A000<=#D400
            save 'build/intro.bin',#A000,intro_stop-intro_start

;------------------------------------------------------------------------------
; overlay du game over : jingle, lu en GO_LOAD (#4000, sur la copie du decor : la scene est figee, le menu reconstruira tout) : build/gover.bin
;------------------------------------------------------------------------------
            org GO_LOAD,#D400                   ; assemble pour #4000, range en #D400 (zone d assemblage libre : l overlay des missions peut aller jusqu'en #D400)
go_start:
            include 'gameover.asm'
go_stop:
            assert go_stop-go_start<=GO_N*512
            save 'build/gover.bin',#D400,go_stop-go_start

;------------------------------------------------------------------------------
; overlay du Hall of Fame : saisie du nom (apres une partie dont le score entre dans le classement) et classement qui defile (menu) : build/hof.bin
;------------------------------------------------------------------------------
            org HOF_LOAD,#E000                  ; assemble pour #4000, range en #E000 (zone d assemblage libre)
hof_start:
            include 'hof.asm'
hof_stop:
            assert hof_stop-hof_start<=HOF_N*512
            assert hof_stop<=CANVAS
            save 'build/hof.bin',#E000,hof_stop-hof_start

;------------------------------------------------------------------------------
; code du boss (banque 7) : assemble pour #4000, range en #F800 : build/boss.bin
;------------------------------------------------------------------------------
            org BOSS_LOAD,#8000
boss_start:
            include 'boss_mod.asm'
boss_stop:
            assert boss_stop-boss_start<=VOICE_OFF
            save 'build/boss_code.bin',#8000,boss_stop-boss_start
