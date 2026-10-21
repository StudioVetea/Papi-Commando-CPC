; --- genere par tools/convert.py ---
cover_pal:  ; 16 encres + bordure (numeros materiels)
 db #54,#5C,#4B,#43,#40,#4C,#4E,#47,#52,#56,#5F,#4A,#46,#57,#55,#5E
 db #54
logo_pal:   ; logo du studio (affiche avant la cover)
 db #54,#56,#52,#4B,#5F,#4C,#4A,#46,#55,#57,#4E,#40,#54,#54,#54,#54
 db #54
logo_text:  ; "PRESENTS" : 10 lignes de (adresse ecran, 32 octets)
 dw #C478
 db #CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00
 dw #CC78
 db #CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00
 dw #D478
 db #CC,#00,#CC,#00,#CC,#00,#CC,#00,#CC,#00,#00,#00,#CC,#00,#00,#00,#CC,#00,#00,#00,#CC,#00,#CC,#00,#00,#CC,#00,#00,#CC,#00,#00,#00
 dw #DC78
 db #CC,#00,#CC,#00,#CC,#00,#CC,#00,#CC,#00,#00,#00,#CC,#00,#00,#00,#CC,#00,#00,#00,#CC,#00,#CC,#00,#00,#CC,#00,#00,#CC,#00,#00,#00
 dw #E478
 db #CC,#CC,#CC,#00,#CC,#CC,#00,#00,#CC,#CC,#00,#00,#CC,#CC,#CC,#00,#CC,#CC,#00,#00,#CC,#00,#CC,#00,#00,#CC,#00,#00,#CC,#CC,#CC,#00
 dw #EC78
 db #CC,#CC,#CC,#00,#CC,#CC,#00,#00,#CC,#CC,#00,#00,#CC,#CC,#CC,#00,#CC,#CC,#00,#00,#CC,#00,#CC,#00,#00,#CC,#00,#00,#CC,#CC,#CC,#00
 dw #F478
 db #CC,#00,#00,#00,#CC,#00,#CC,#00,#CC,#00,#00,#00,#00,#00,#CC,#00,#CC,#00,#00,#00,#CC,#00,#CC,#00,#00,#CC,#00,#00,#00,#00,#CC,#00
 dw #FC78
 db #CC,#00,#00,#00,#CC,#00,#CC,#00,#CC,#00,#00,#00,#00,#00,#CC,#00,#CC,#00,#00,#00,#CC,#00,#CC,#00,#00,#CC,#00,#00,#00,#00,#CC,#00
 dw #C4C8
 db #CC,#00,#00,#00,#CC,#00,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#00,#CC,#00,#00,#CC,#00,#00,#CC,#CC,#CC,#00
 dw #CCC8
 db #CC,#00,#00,#00,#CC,#00,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#00,#CC,#00,#00,#CC,#00,#00,#CC,#CC,#CC,#00
