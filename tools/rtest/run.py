"""TEST ONLY: headless-as-possible behaviour runs of this pack on the local QuestZDoom build.

    python -B run.py <name> <timeout s> [spec ...]

spec: "T:console cmds" runs them at about maptime T.

This is the Windows port of the kit's kit/kit/team/integ/rtest/run.py. 000_READ_THIS_FIRST.md
lists those suites under "genuinely Linux-only", and that is true of the SHELL around them --
not of the idea. What was actually Linux-only:

    xvfb-run    a fake X server, so no window appeared. Windows has no equivalent, so a
                window DOES appear here. It is 320x240, windowed, silent and quits itself.
    timeout     replaced by subprocess's own timeout.
    stdbuf      not needed; the log goes to a file via +logfile.
    HOME=...    the Linux build reads $HOME/.config/qzdoom/qzdoom.ini. Here the run gets a
                scratch -config so the owner's ini is never touched or read.

WHAT THIS BUYS over the load check: tools/check.sh proves the scripts compile and the pack
loads. It cannot see a VM abort, and it cannot see a reload that never finishes. This runs the
playsim with fake VR hands and a scripted off hand, so the reload path is actually exercised.

THE OVERLAY. Built fresh each run and loaded last, so its lumps win:
    zscript/rsvr/vrhand.zs   REPLACED by fakehands.zs. The pack's ZSCRIPT #includes that path,
                             and the include resolves to the last lump of that name, so the
                             production hands are swapped out without touching the pack.
    zscript/rtest/*.zs       the scripted off hand (the kit's RSR_TestDriver, verbatim) and
                             the gun picker (driver.zs).
    CVARINFO / ZSCRIPT / MAPINFO  .rtest suffixes, which become the lumps CVARINFO, ZSCRIPT and
                             MAPINFO -- GZDoom reads every file's copy of those, which is the
                             same trick the pack itself uses for ZSCRIPT.ae.
"""
import os
import subprocess
import sys
import zipfile

import fixmapset

H = os.path.dirname(os.path.abspath(__file__))
PACK = os.path.abspath(os.path.join(H, '..', '..'))
ENG = 'E:/DOOMWork/QZD17-engine/build/Release'
AE = 'D:/SteamLibrary/steamapps/common/DooM VR/__Games/Aliens/Eradication'
TC = AE + '/_A01_ALIENS_ERADICATION_TC_2_0.pk3'
MAPSET = AE + '/_A02_ERADICATION_MAPSET_2_0.wad'
SCRATCH = os.environ.get('TMPDIR', os.environ.get('TEMP', H)) + '/aet'

CVARS = '''user int rsrtest_script = 0;
user bool rsr_test_offdraw = true;
user float rsr_test_yaw = 0;
user int rsbtest_script = 0;
user int rsbtest_chambers = 0;
user bool rsp_test_steady = false;
user bool rsp_test_trigger = false;
user int rsptest_script = 0;
user float rsptest_speed = 1.0;
user int rsptest_holds = 0;
user int rsptest_every = 0;
user int rsptest_casings = 1;
user string aet_gun = "";
user int aet_empty = 0;
'''


def overlay(path):
    # ALL THREE GO IN ONE LUMP, and that lump is the one the pack's own ZSCRIPT #includes.
    # The kit's run.py says why and I had to be shown it twice: "the one file the pack's ZSCRIPT
    # includes (a later ZSCRIPT lump cannot be seen from the pack's)". Split across a second
    # ZSCRIPT lump, the hands compile first and RSR_TestDriver is an unknown class inside them
    # -- 24 errors of 'Call to unknown function RSR_TestDriver' and its knock-ons.
    body = '\n'.join(open(os.path.join(H, f), encoding='utf-8').read()
                     for f in ('fakehands.zs', 'rsr_testdriver.zs', 'driver.zs'))
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('zscript/rsvr/vrhand.zs', body)
        z.writestr('CVARINFO.rtest', CVARS)
        z.writestr('MAPINFO.rtest',
                   'gameinfo { AddEventHandlers = "RSR_TestDriver", "AET_Driver" }\n')
    return path


def run(name, tmo, specs):
    os.makedirs(SCRATCH, exist_ok=True)
    pk3 = os.path.join(SCRATCH, 'aet_pack.pk3')
    # the mapset with its MAPINFO episode block closed -- a COPY, in scratch; see fixmapset.py
    mapset, _why = fixmapset.build(MAPSET, os.path.join(SCRATCH, 'mapset_fixed.wad'))
    ov = os.path.join(SCRATCH, 'aet_overlay.pk3')
    log = os.path.join(SCRATCH, name + '.log')

    sys.path.insert(0, os.path.join(PACK, 'tools'))
    subprocess.check_call([sys.executable, '-B', os.path.join(PACK, 'tools', 'mkpk3.py'),
                           PACK, pk3], stdout=subprocess.DEVNULL)
    overlay(ov)

    # PRESS USE ONCE THE MAP IS UP. The mapset's first map opens on a prompt that waits for a
    # button, so without this every run sits there and every phase reads IDLE for ever. 20 tics
    # in, held for 2, which is a press rather than a stuck key.
    items = sorted((int(a.split(':', 1)[0]), a.split(':', 1)[1]) for a in specs)
    items += [(20, '+use'), (22, '-use')]
    items.sort()
    cmds, now = [], 0
    for t, c in items:
        if t > now:
            cmds.append('wait %d' % (t - now))
            now = t
        cmds.append(c)
    cmds += ['wait 5', 'quit']

    argv = [os.path.join(ENG, 'qzdoom.exe'),
            '-iwad', 'doom2.wad',
            '-file', TC, '-file', mapset, '-file', pk3, '-file', ov,
            '-config', os.path.join(SCRATCH, 'scratch.ini'),
            '-nosound', '-nomusic',
            '+vid_fullscreen', '0', '+vid_defwidth', '320', '+vid_defheight', '240',
            '+vr_mode', '0',
            '+logfile', log,
            '+map', 'MAP01',
            '+' + '; '.join(cmds)]
    try:
        r = subprocess.call(argv, cwd=ENG, timeout=tmo,
                            stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    except subprocess.TimeoutExpired:
        r = 'TIMEOUT'
    print('%s exit %s -> %s' % (name, r, log))
    return log


if __name__ == '__main__':
    run(sys.argv[1], int(sys.argv[2]), sys.argv[3:])
