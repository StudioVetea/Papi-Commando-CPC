        org #0200
        run boot
boot:   di
        ld sp,#0200
        ld bc,#7F8C : out (c),c
        ; palette: ink0 black, border varies
        ld hl,#C000 : ld de,#C001 : ld bc,#3FFF : ld (hl),#FF : ldir
        ld hl,crtc : ld d,0
.c      ld bc,#BC00 : out (c),d : ld b,#BD : ld a,(hl) : out (c),a : inc hl : inc d : ld a,d : cp 14 : jr nz,.c
        ld a,#C3 : ld (#38),a : ld hl,isr : ld (#39),hl
        im 1 : xor a : ld (icnt),a : ei
.l      jr .l
isr:    push af : push bc
        ld a,(icnt) : ld c,a : inc a : cp 6 : jr c,.o : xor a
.o      ld (icnt),a
        ld a,c : add a,a : add a,a : add a,#40 : ld c,a    ; ink numbers differ
        ld a,(icnt) : ld b,0
        ld a,c
        ld bc,#7F10 : out (c),c
        ld c,a : out (c),c
        pop bc : pop af : ei : ret
icnt:   db 0
crtc:   db 63,40,46,#8E,39,0,25,30,0,7,0,0,#30,0
 save 'CAL.BIN',#0200,$-#0200,DSK,'cal.dsk'
