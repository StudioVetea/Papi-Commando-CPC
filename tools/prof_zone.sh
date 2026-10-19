#!/bin/sh
# tools/prof.sh <touche 1..6> [frames] [seed] : profil avec un joueur automatique
cd "$(dirname "$0")/.."
sym() { grep -E "^$1 " build/papicpc.sym | sed 's/.*#\([0-9A-F]*\).*/\1/'; }
I0=$(sym MAIN_LOOP); I1=$(sym WAIT_END); LV=$(sym LIVES); H0=$(sym INT_HANDLER); H1=$(python3 -c "import sys;a=int(sys.argv[1],16);v=sorted(int(l.split()[1][1:],16) for l in open('build/papicpc.sym') if ' #' in l and '.' not in l.split()[0]);print('%X'%min(x for x in v if x>a))" $H0)
tools/cpcrun ${CPCMODEL:-6128} build/PAPICPC.dsk 'type:RUN"PAPICPC"~' run:1000 key:0x20 run:4 keyup:0x20 run:260 poke:$(sym ZONE_CUR):${ZONE:-0} key:0x20 run:4 keyup:0x20 idle:$I0:$I1 ign:$H0:$H1 cnt:$(sym EN_LOOP) cnt:$(sym ENEMY_ALIVE) cnt:$(sym DRAW_SPRITE) seed:${3:-12345} run:420 poke:$(sym NB_WANTED):$((2*$1)) run:5 poke:$LV:200 poke:$(sym KILLS_LEFT):99 bot:1 run:500 poke:$LV:200 poke:$(sym KILLS_LEFT):99 prof:${2:-1500} sym:build/papicpc.sym shot:/tmp/_p$1.ppm
