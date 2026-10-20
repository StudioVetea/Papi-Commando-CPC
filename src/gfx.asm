; --- genere par tools/convert.py : ne pas modifier a la main ---

palette_hw:            ; 16 encres + bordure (numeros materiels)
 db #54,#5C,#4C,#45,#56,#46,#5E,#40,#4E,#47,#5A,#4A,#43,#4B,#44,#55
 db #54

spr_grenade:           ; 3 images 2x6
 db #FF,#00,#FF,#00
 db #FF,#00,#FF,#00
 db #AA,#00,#55,#22
 db #AA,#00,#55,#00
 db #FF,#00,#FF,#00
 db #FF,#00,#FF,#00
 db #FF,#00,#FF,#00
 db #AA,#00,#55,#00
 db #00,#00,#00,#22
 db #00,#00,#00,#00
 db #AA,#00,#55,#00
 db #FF,#00,#FF,#00
 db #AA,#00,#55,#00
 db #00,#11,#00,#A2
 db #00,#00,#00,#22
 db #00,#00,#00,#00
 db #00,#00,#00,#00
 db #AA,#00,#55,#00

spr_eclat:             ; eclat d une balle en fin de portee : 3 images 2x6
 db #FF,#00,#FF,#00
 db #FF,#00,#FF,#00
 db #AA,#51,#FF,#00
 db #FF,#00,#55,#A2
 db #FF,#00,#FF,#00
 db #FF,#00,#FF,#00
 db #FF,#00,#FF,#00
 db #55,#A2,#AA,#51
 db #FF,#00,#FF,#00
 db #FF,#00,#FF,#00
 db #55,#A2,#AA,#51
 db #FF,#00,#FF,#00
 db #55,#A2,#AA,#51
 db #FF,#00,#FF,#00
 db #FF,#00,#FF,#00
 db #FF,#00,#FF,#00
 db #FF,#00,#FF,#00
 db #55,#A2,#AA,#51

spr_balle:             ; 1 image 1x6
 db #00,#CF
 db #00,#CF
 db #FF,#00
 db #FF,#00
 db #FF,#00
 db #00,#00

font:                  ; glyphes 3x5 compactes : 2 octets (poids faible d abord) = 15 bits, ligne du haut en tete, ordre "0123456789 ACEGIMNOPRSVUTFLD-HKZ!.Y+BQ"
 db #DE,#F6
 db #2E,#59
 db #CE,#E7
 db #9E,#E7
 db #92,#B7
 db #9E,#F3
 db #DE,#F3
 db #24,#E5
 db #DE,#F7
 db #9E,#F7
 db #00,#00
 db #DA,#F7
 db #4E,#F2
 db #4E,#F3
 db #DE,#F2
 db #2E,#E9
 db #DA,#BF
 db #DA,#F6
 db #DE,#F6
 db #C8,#F7
 db #5A,#F7
 db #9E,#F3
 db #D4,#B6
 db #DE,#B6
 db #24,#E9
 db #48,#F3
 db #4E,#92
 db #DC,#D6
 db #80,#03
 db #DA,#B7
 db #5A,#B7
 db #4E,#E5
 db #04,#49
 db #04,#00
 db #24,#B5
 db #A0,#0B
 db #5C,#D7
 db #D6,#56

hp_pens:               ; barre de vie du boss : (pixel gauche, pixel droit) pour vert, jaune, orange, rouge
 db #0A,#05
 db #8A,#45
 db #02,#01
 db #08,#04

SND_BOSS_LEN equ 14
boss_vol:              ; son Tir Boss : volume par image
 db #0E,#0F,#0E,#0F,#0E,#0E,#0F,#0F,#0F,#0F,#0E,#0D,#0C,#08

zc_per:                ; jingle ZONE CLEAR : periode / 2 par image de 20 ms (64 images)
 db #A4,#74,#74,#75,#76,#78,#7B,#7D,#80,#83,#88,#8E,#95,#9C,#A9,#91
 db #7C,#6B,#5B,#4E,#43,#3A,#31,#2A,#24,#1F,#AC,#93,#7E,#6C,#5D,#50
 db #44,#3B,#32,#2B,#25,#20,#AF,#96,#80,#6E,#5E,#51,#45,#3C,#33,#2C
 db #26,#20,#B2,#98,#83,#70,#60,#52,#47,#3D,#34,#2D,#26,#21,#1F,#1F
