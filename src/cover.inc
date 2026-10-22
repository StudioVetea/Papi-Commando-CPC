; --- genere par tools/convert.py ---
cover_pal:  ; 16 encres + bordure (numeros materiels)
 db #54,#5C,#4B,#43,#40,#4C,#4E,#47,#56,#52,#5E,#54,#54,#54,#54,#54
 db #54
logo_pal:   ; logo du studio (affiche avant la cover)
 db #54,#56,#52,#4B,#5F,#4C,#4A,#46,#55,#57,#4E,#40,#54,#54,#54,#54
 db #54
logo_text:  ; "PRESENTS" : 10 lignes de (adresse ecran, 32 octets)
 dw #FD68
 db #CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00
 dw #C5B8
 db #CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00
 dw #CDB8
 db #CC,#00,#CC,#00,#CC,#00,#CC,#00,#CC,#00,#00,#00,#CC,#00,#00,#00,#CC,#00,#00,#00,#CC,#00,#CC,#00,#00,#CC,#00,#00,#CC,#00,#00,#00
 dw #D5B8
 db #CC,#00,#CC,#00,#CC,#00,#CC,#00,#CC,#00,#00,#00,#CC,#00,#00,#00,#CC,#00,#00,#00,#CC,#00,#CC,#00,#00,#CC,#00,#00,#CC,#00,#00,#00
 dw #DDB8
 db #CC,#CC,#CC,#00,#CC,#CC,#00,#00,#CC,#CC,#00,#00,#CC,#CC,#CC,#00,#CC,#CC,#00,#00,#CC,#00,#CC,#00,#00,#CC,#00,#00,#CC,#CC,#CC,#00
 dw #E5B8
 db #CC,#CC,#CC,#00,#CC,#CC,#00,#00,#CC,#CC,#00,#00,#CC,#CC,#CC,#00,#CC,#CC,#00,#00,#CC,#00,#CC,#00,#00,#CC,#00,#00,#CC,#CC,#CC,#00
 dw #EDB8
 db #CC,#00,#00,#00,#CC,#00,#CC,#00,#CC,#00,#00,#00,#00,#00,#CC,#00,#CC,#00,#00,#00,#CC,#00,#CC,#00,#00,#CC,#00,#00,#00,#00,#CC,#00
 dw #F5B8
 db #CC,#00,#00,#00,#CC,#00,#CC,#00,#CC,#00,#00,#00,#00,#00,#CC,#00,#CC,#00,#00,#00,#CC,#00,#CC,#00,#00,#CC,#00,#00,#00,#00,#CC,#00
 dw #FDB8
 db #CC,#00,#00,#00,#CC,#00,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#00,#CC,#00,#00,#CC,#00,#00,#CC,#CC,#CC,#00
 dw #C608
 db #CC,#00,#00,#00,#CC,#00,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#CC,#CC,#00,#CC,#00,#CC,#00,#00,#CC,#00,#00,#CC,#CC,#CC,#00
