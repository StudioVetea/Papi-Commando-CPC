@echo off
rem Assemble Papi Commando CPC : produit build\PAPICPC.dsk (RUN"PAPICPC").  rasm.exe dans le PATH ou dans ce dossier ; Python 3 + Pillow.
if not exist build mkdir build
python tools\convert.py
if errorlevel 1 goto fin
if exist build\PAPICPC.dsk del build\PAPICPC.dsk
rem build.bat debug : version de TEST (codes secrets) ; sans argument : version de diffusion
set DEF=
if "%1"=="debug" set DEF=-DCHEATS=1
rasm %DEF% src\papicpc.asm -Isrc\ -o build\papicpc -s -eo
if errorlevel 1 goto fin
python tools\symvars.py
python tools\mkdisk.py build\PAPICPC.dsk
:fin
