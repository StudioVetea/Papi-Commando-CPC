#!/usr/bin/env python3
"""Prototype 3 = prototype 2 + bandeau HUD (score, vies, ennemis restants) : proto/game3.dsk (RUN"GAME3")
Les sources g2_* ne sont pas modifiees : les changements sont appliques ici, en memoire."""
import re, subprocess, sys, os
os.chdir(os.path.dirname(os.path.abspath(__file__)) + '/..')

def rep(s, old, new, count=1):
    assert old in s, 'ancre introuvable : ' + old[:60]
    return s.replace(old, new, count)

head = open('proto/g2_head.asm').read()
if 'sp_dmin' not in head:
    head = rep(head, "dbgn        equ VARS+131", "dbgn        equ VARS+131\nsp_dmin     equ VARS+132\nbk_c0       equ VARS+133\nbk_c1       equ VARS+134\nbk_r0       equ VARS+135\nbk_r1       equ VARS+136")
# --- tete : le bandeau remplace le dessin de la rangee du haut ---
head = rep(head, "        call spr_init           ; table des sprites (Papi, ennemis)\n", "        call spr_init           ; table des sprites (Papi, ennemis)\n        call hud_init           ; bandeau\n")
a = head.index("dyn_early:\n")
b = head.index("dyn_finish:\n")
head = head[:a] + """dyn_early:                     ; (prototype 3) la rangee du haut est entierement couverte par le bandeau
        xor a
        ld (dyn_late),a
        ld a,(r_nxt)
        ld (dyn_r),a
        ld a,(s_nxt)
        ld (dyn_s),a
        ret

""" + head[b:]
head = rep(head, ".o2     ld a,d\n        or #C0\n        ld d,a\n", ".o2     ld a,d\n        or #C0\n        ld d,a\n        ld a,(dr_pl)            ; decalage de plan (restauration d'une seule ligne)\n        add a,a\n        add a,a\n        add a,a\n        add a,d\n        ld d,a\n")

t = open('proto/scroll_tail.asm').read()
sep = ";------------------------------------------------------------------------------\n"
i_isr = t.index("; boucle d'images, pilotee"); i_isr = t.rindex(sep, 0, i_isr)
i_main = t.index("; boucle principale : attend"); i_main = t.rindex(sep, 0, i_main)
isr_block = t[i_isr:i_main]
# resynchronisation du compteur d'interruptions sur le VSYNC : l'interruption servie pendant le VSYNC est celle de la ligne 234 (numero 5)
isr_block = rep(isr_block, "isr:    push af\n        push bc\n        push de\n        push hl\n        ld a,(icnt)\n        inc a\n", "isr:    push af\n        push bc\n        push de\n        push hl\n        ld b,#F5\n        in a,(c)\n        rra\n        ld a,(icnt)\n        jr nc,.nv\n        ld a,4\n.nv     inc a\n")
i_rk = t.index("; clavier / manette"); i_rk = t.rindex(sep, 0, i_rk)
i_up = t.index("; deplacement de Papi + camera")
readkeys = t[i_rk:i_up]
update = t[i_up:i_isr]
update = rep(update, "        ld e,2                  ; vitesse verticale : 2 lignes par image (4 avec TIR)\n        bit 4,c\n        jr z,.sp\n        ld e,4\n.sp     ld a,c", "        ld e,2                  ; vitesse verticale : 2 lignes par image\n.sp     ld a,c")
update = rep(update, "update:\n        call readkeys\n", "update:\n        call readkeys\n        ld hl,(py)\n        ld (opy),hl\n        ld a,(px)\n        ld (opx),a\n")
update = rep(update, ".p3     ld (py),hl\n", ".p3     ld (py),hl\n        call papi_collide\n        ld hl,(py)\n")
a = t.index("        ld a,(r_nxt)\n        ld hl,drawn_r\n        cp (hl)")
b = t.index(".nr2    call dyn_early\n") + len(".nr2    call dyn_early\n")
rows = t[a:b]
rows = rep(rows, '.back   ld (hl),a               ; on recule : la rangee r+1 (l\'ancienne rangee du haut) devient persistante\n        inc a\n        call full_row\n', '.back   ld (hl),a               ; on recule : la rangee r+1 (l\'ancienne rangee du haut) devient persistante\n        inc a\n')
wait = t[t.index("wait_flag:"):t.index("mainloop:")]
main = "idle_halt: halt\n        ret\n" + wait + """mainloop:
.wf     ld hl,frame_flag
        call wait_flag
        xor a
        ld (frame_flag),a
        ld a,(tickf)
        xor 1
        ld (tickf),a
        ld a,(p_state)
        or a
        jr nz,.frozen
        call update
        call papi_actions
        call papi_sync
        jr .live
.frozen call game_over_tick
.live   call cam_split
        ld (r_nxt),a
        ld a,c
        ld (s_nxt),a
""" + rows + """        call hud_overlay
        ld a,(r_nxt)
        call calc_start
        di
        ld a,(r_nxt)
        ld (pub_r),a
        ld a,(s_nxt)
        ld (pub_s),a
        ld a,1
        ld (ready),a
        ei
        ld a,(p_state)
        or a
        call z,game_tick
        call vis_scan
        call spr_job
        jp mainloop

"""
tail = "crtc_tab:" + t[t.index("crtc_tab:") + 9:t.index("        include 'data.inc'")] + "        include 'data.inc'\n        include 'data2.inc'\n        org #4C00\n        include 'data3.inc'\n        org #5800\ndiv6tab:\n" + "".join("        db " + ",".join(str(i // 6) for i in range(r, r + 16)) + "\n" for r in range(0, 256, 16)) + "                save 'GAME3.BIN',#0200,$-#0200,DSK,'proto/game3.dsk'\n"
ga = open('proto/g2_game_a.asm').read()
ga = rep(ga, "div6:   ld e,0\n.d      cp 6\n        jr c,.e\n        sub 6\n        inc e\n        jr .d\n.e      ld a,e\n        ret\n", "div6:   ld l,a\n        ld h,div6tab/256\n        ld a,(hl)\n        ret\n")
gb = open('proto/g2_game_b.asm').read()
# --- sprites : visibles seulement sous le bandeau (rangees r+2 .. r+23) ; l'effacement saute les lignes du bandeau ---
ga = rep(ga, "        ld a,(r_cur)\n        inc a\n        cp c\n        jr z,.t2", "        ld a,(r_cur)\n        add a,2\n        cp c\n        jr z,.t2")
ga = rep(ga, ".nd     call bg_ptr\n        ld a,(ix+S_W)\n        cp 6\n        jr nz,.one", ".nd     call hud_skip\n        call bg_ptr\n        ld a,(ix+S_W)\n        cp 6\n        jr nz,.one")
ga = rep(ga, "        pop hl                  ; HL = fond\n        ld a,12\n        ld (nline),a\n", """        pop hl                  ; HL = fond
        ld a,(esk)
        or a
        ld a,12
        jr z,.nos
        ld a,(esk)
        cp 12
        ret nc
        ld b,a
        ld c,a
.sk     ld de,6
        add hl,de
        inc iy
        inc iy
        djnz .sk
        ld a,12
        sub c
.nos    ld (nline),a
""")
ga = rep(ga, "        pop hl\n        ld b,6\n.ol     ld e,(iy+0)", """        pop hl
        ld a,(esk)
        or a
        ld b,6
        jr z,.ol
        cp 6
        ret nc
        ld c,a
        ld b,a
.osk    inc hl
        inc iy
        inc iy
        djnz .osk
        ld a,6
        sub c
        ld b,a
.ol     ld e,(iy+0)""")
# --- jeu : vies et score ---
gb = rep(gb, "papi_hurt:\n        ld hl,(hits)\n        inc hl\n        ld (hits),hl\n        ld a,60\n        ld (invuln),a\n        ret\n", "papi_hurt:\n        ld hl,(hits)\n        inc hl\n        ld (hits),hl\n        ld a,60\n        ld (invuln),a\n        jp hud_life\n")
gb = rep(gb, "        ld hl,(kills)\n        inc hl\n        ld (kills),hl\n        pop ix\n        jp kill_spr", "        ld hl,(kills)\n        inc hl\n        ld (kills),hl\n        call hud_kill\n        pop ix\n        jp kill_spr")
hud = open('proto/g3_hud.asm').read()
hud = rep(hud, "        ld hl,hud_tpl\n        ld de,hudbuf\n        ld bc,624\n        ldir\n", '')
src = head + isr_block + readkeys + update + ga + gb + hud + main + tail
open('proto/game3.asm', 'w').write(src)
r = subprocess.run(['rasm', 'proto/game3.asm', '-o', 'proto/game3', '-eo', '-s'], capture_output=True, text=True)
out = r.stdout + r.stderr
errs = [l for l in out.split('\n') if 'rror' in l or 'not found' in l or 'too far' in l or 'nknown' in l]
print('\n'.join(errs[:25]) if errs else 'ok')
