"""TEST ONLY: run the headless reload on every gun that has a slide or a bolt, and report.

    python -B suite.py            # all six
    python -B suite.py PulseRifle_3D MercPistol_3D

The six are RSR_Guns.HasHandle: 1 M4A3Pistol, 2 PulseRifle, 5 MercPistol, 6 SynthPistol,
7 YutaniPistol, 8 YutaniRifle. The smartguns and flamers have no handle to work and are left
out of this path everywhere else in the pack, so they are left out here too.

Each gun gets its own run with a FRESH config (run.py copies template.ini), because the engine
writes cvars back on quit and a shared config is how this harness last lied to us.

A gun passes when its phases reach DONE and its magazine comes back full off the reserve.
"""
import os
import re
import sys

import run

GUNS = ['M4A3Pistol_3D', 'PulseRifle_3D', 'MercPistol_3D', 'SynthPistol_3D',
        'YutaniPistol_3D', 'YutaniRifle_3D']

ORDER = ['DROP', 'EMPTY', 'CARRY', 'INSERT', 'CHARGE', 'PULL', 'RELEASED', 'DONE']


def one(gun):
    # 700 tics of script, and 220 s of real time to get through them.
    #
    # BOTH NUMBERS WERE WRONG ONCE, in opposite directions, and each produced a lie:
    #   3000 tics meant a passing gun still sat there to the end of the script -- four minutes
    #     of watching a rifle do nothing, per gun.
    #   80 s cut YutaniRifle_3D off at t105, before its FLOOR hold had even finished at t156,
    #     and the suite reported it STUCK at 2/8. It passes 8/8 given 220 s. The guns do not
    #     run at the same real-time speed, and a budget tuned on the fast ones libels the
    #     slow one.
    # A false STUCK is far worse than a slow suite, so the budget is generous and the script
    # short. If a gun ever does report STUCK, check its last logged tick against the hold it
    # died in before believing it.
    log = run.run('suite_' + gun, 220, [
        '10:god; show_messages 0; rsq_reload 1; aet_empty 1; aet_gun ' + gun,
        '40:rsrtest_script 7',
        '80:+reload',
        '84:-reload',
        '700:echo END',
    ])
    text = open(log, encoding='utf-8', errors='replace').read()
    phases = []
    for m in re.finditer(r'^t\d+ phase .*?\| phase ([A-Z_]+)', text, re.M):
        p = m.group(1)
        if not phases or phases[-1] != p:
            phases.append(p)
    ammo = re.findall(r'^   ammo (\S+) (\d+) (\S+) (\d+) held (\d+) nomag (\d+)', text, re.M)
    holds = re.findall(r'^HOLD (\S+) ', text, re.M)
    return phases, ammo[-1] if ammo else None, holds


def main():
    want = sys.argv[1:] or GUNS
    rows = []
    for g in want:
        phases, ammo, holds = one(g)
        got = [p for p in ORDER if p in phases]
        done = 'DONE' in phases
        loaded = int(ammo[1]) if ammo else -1
        rows.append((g, done, len(got), ORDER[len(got)] if len(got) < len(ORDER) else '-',
                     ammo, len(holds)))
        print('   %-18s %-4s %d/8 phases, %d holds' % (g, 'DONE' if done else 'STUCK',
                                                       len(got), len(holds)))

    print('\n%-18s %-6s %-8s %-18s %s' % ('gun', 'result', 'phases', 'stopped before', 'ammo after'))
    print('-' * 86)
    for g, done, n, nxt, ammo, nh in rows:
        a = '%s %s / %s %s  nomag %s' % (ammo[0], ammo[1], ammo[2], ammo[3], ammo[5]) if ammo else '?'
        print('%-18s %-6s %d/8      %-18s %s' % (g, 'pass' if done else 'STUCK', n,
                                                 '-' if done else nxt, a))


if __name__ == '__main__':
    main()
