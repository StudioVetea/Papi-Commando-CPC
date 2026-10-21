import sys,subprocess,re
sys.path.insert(0,'/home/claude/work/ovgame/tools'); sys.path.insert(0,'/tmp/t4')
from t4 import *
seed=sys.argv[1] if len(sys.argv)>1 else '3'
n=int(sys.argv[2]) if len(sys.argv)>2 else 20
c=['6128',root+'/build/PAPICPC.dsk','seed:'+seed,'type:RUN"PAPICPC"~','run:1000','key:0x20','run:4','keyup:0x20','run:260']
for i in range(n):
    c+=['poke:%X:200'%sym['LIVES'],'run:300','peek:%X:1'%sym['ZONE_CUR'],'poke:%X:0'%sym['KILLS_LEFT'],'run:900','peek:%X:1'%sym['ZONE_CUR'],'shot:/tmp/t4/c%d.ppm'%i]
r=subprocess.run([root+'/tools/cpcrun']+c,capture_output=True,text=True)
print(r.stdout[-3000:], r.stderr[-300:])
