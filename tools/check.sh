#!/bin/bash
# check.sh -- pack the set and load it WITH the TC, hidden, then report honestly.
#
# WHY THIS FILE EXISTS. Checking the pack without _A01 loaded produces three errors that look
# like our bugs and are not:
#     Replaced type 'Knifespawner' not found for Knifespawner_3D
#     Parent type 'Loader' not found in Loader_3D
#     Replaced type 'Loader' not found for Loader_3D
# `Loader`, `AELoader` and `Knifespawner` belong to the TC. Verified 2026-10-23: our pack needs
# exactly the same 33 TC classes the _A03 addon needed and not one more, so a TC-less check can
# only ever produce phantoms. With the TC loaded, LoadActors passes clean.
#
# It does NOT run the game: -norun, no sound, no VR, its own log, and never the owner's ini.
# -norun cannot see a VM abort -- that still needs the headset.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ENG="/e/DOOMWork/QZD17-engine/build/Release"
AE="D:/SteamLibrary/steamapps/common/DooM VR/__Games/Aliens/Eradication"
TC="$AE/_A01_ALIENS_ERADICATION_TC_2_0.pk3"
MAP="$AE/_A02_ERADICATION_MAPSET_2_0.wad"
OUT="${TMPDIR:-/tmp}/ae_check.pk3"
LOG="${TMPDIR:-/tmp}/ae_check.log"

python -B "$HERE/tools/mkpk3.py" "$HERE" "$OUT" || exit 1
[ -f "$TC" ] || { echo "*** TC NOT FOUND: $TC"; exit 1; }

( cd "$ENG" && ./qzdoom.exe -iwad doom2.wad -file "$TC" -file "$MAP" -file "$OUT" \
    -norun -nosound -nomusic +logfile "$LOG" >/dev/null 2>&1 )

# The mapset's own MAPINFO has an unclosed episode block (its lines 20-25). Not ours; filtered
# so a real error of ours is never lost in it.
ERR=$(grep -iE "script error|script warning|unexpected|VM abort|fatal" "$LOG" \
      | grep -v "_A02_ERADICATION_MAPSET_2_0.wad:MAPINFO")
if ! grep -q "LoadActors" "$LOG"; then
	echo "*** DID NOT REACH LoadActors -- the load died early, read $LOG"
	exit 1
fi
if [ -n "$ERR" ]; then
	echo "*** DID NOT COMPILE ***"
	echo "$ERR"
	exit 1
fi
grep -q "D_CheckNetGame" "$LOG" \
	&& echo "clean: LoadActors passed and startup completed  ($LOG)" \
	|| echo "clean so far, but startup did not complete -- read $LOG"
