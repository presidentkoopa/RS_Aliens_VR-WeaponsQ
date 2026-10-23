#!/bin/bash
# runae.sh NAME "console script"  -> runs/NAME.log, runs/NAME.out ; shots go to runs/
HERE="$(cd "$(dirname "$0")" && pwd)"; P=/home/claude/rig/packs
cd "$HERE" && timeout ${TMO:-600} ./qzdoom -iwad $P/freedoom2.wad -file $P/A01.pk3 $P/${PACK:-AliensVR_Weapons_v1.9.pk3} ${EXTRA:-} -nosound -nomusic +map MAP01 +logfile "$HERE/runs/$1.log" +"$2" > "$HERE/runs/$1.out" 2>&1
echo "exit=$?"
