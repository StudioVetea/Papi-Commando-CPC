#!/usr/bin/env python3
"""Assemble le prototype 2 : g2_head + blocs recycles de scroll_tail + g2_game -> proto/game2.dsk"""
import re, subprocess, sys, os
os.chdir(os.path.dirname(os.path.abspath(__file__)) + '/..')
head = open('proto/g2_head.asm').read()
if 'sp_dmin' not in head:
    head = head.replace("dbgn        equ VARS+131", "dbgn        equ VARS+131\nsp_dmin     equ VARS+132\nbk_c0       equ VARS+133\nbk_c1       equ VARS+134\nbk_r0       equ VARS+135\nbk_r1       equ VARS+136")
    open('proto/g2_head.asm', 'w').write(head)
t = open('proto/scroll_tail.asm').read()
sep = ";------------------------------------------------------------------------------\n"
i_isr = t.index("; boucle d'images, pilotee")
i_isr = t.rindex(sep, 0, i_isr)
i_main = t.index("; boucle principale : attend")
i_main = t.rindex(sep, 0, i_main)
isr_block = t[i_isr:i_main]
i_rk = t.index("; clavier / manette"); i_rk = t.rindex(sep, 0, i_rk)
i_up = t.index("; deplacement de Papi + camera")
readkeys = t[i_rk:i_up]
update = t[i_up:i_isr]
update = update.replace("        ld e,2                  ; vitesse verticale : 2 lignes par image (4 avec TIR)\n        bit 4,c\n        jr z,.sp\n        ld e,4\n.sp     ld a,c", "        ld e,2                  ; vitesse verticale : 2 lignes par image\n.sp     ld a,c")
update = update.replace("update:\n        call readkeys\n", "update:\n        call readkeys\n        ld hl,(py)\n        ld (opy),hl\n        ld a,(px)\n        ld (opx),a\n")
update = update.replace(".p3     ld (py),hl\n", ".p3     ld (py),hl\n        call papi_collide\n        ld hl,(py)\n")
assert 'papi_collide' in update and 'ld e,4' not in update
a = t.index("        ld a,(r_nxt)\n        ld hl,drawn_r\n        cp (hl)")
b = t.index(".nr2    call dyn_early\n") + len(".nr2    call dyn_early\n")
rows = t[a:b]
wait = t[t.index("wait_flag:"):t.index("mainloop:")]
main = "idle_halt: halt\n        ret\n" + wait + """mainloop:
.wf     ld hl,frame_flag
        call wait_flag
        xor a
        ld (frame_flag),a
        ld a,(tickf)
        xor 1
        ld (tickf),a
        call update
        call papi_actions
        call papi_sync
        call game_tick
        call cam_split
        ld (r_nxt),a
        ld a,c
        ld (s_nxt),a
""" + rows + """        ld a,(r_nxt)
        call calc_start
        di
        ld a,(r_nxt)
        ld (pub_r),a
        ld a,(s_nxt)
        ld (pub_s),a
        ld a,1
        ld (ready),a
        ei
        call vis_scan
        call spr_job
        jp mainloop

"""
tail = "crtc_tab:" + t[t.index("crtc_tab:") + 9:t.index("        include 'data.inc'")] + "        include 'data.inc'\n        include 'data2.inc'\n        save 'GAME2.BIN',#0200,$-#0200,DSK,'proto/game2.dsk'\n"
game = open('proto/g2_game_a.asm').read() + open('proto/g2_game_b.asm').read()
open('proto/game2.asm', 'w').write(head + isr_block + readkeys + update + game + main + tail)
r = subprocess.run(['rasm', 'proto/game2.asm', '-o', 'proto/game2', '-eo', '-s'], capture_output=True, text=True)
out = r.stdout + r.stderr
errs = [l for l in out.split('\n') if 'rror' in l or 'not found' in l or 'too far' in l or 'nknown' in l]
print('\n'.join(errs[:25]) if errs else 'ok')
