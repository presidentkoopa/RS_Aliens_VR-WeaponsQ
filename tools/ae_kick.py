"""AE: how much each gun's HUD model frames move the gun body off its ready frame (kick_measure.py maths)."""
import sys, os, re, glob, json
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kick_measure as km
AE = sys.argv[1] if len(sys.argv) > 1 else '/home/claude/rig/ae_fix'
blocks = []
for f in sorted(glob.glob(AE + '/modeldef.*.txt')):
    blocks += km.modeldef_blocks(open(f, encoding='latin-1').read())
# ready key per gun = first frame of its Ready state sprite (AE DECORATE): hand table order
guns = {'M4A3Pistol_3D': ('MM91', 'A'), 'MercPistol_3D': ('MM91', 'A'), 'SynthPistol_3D': ('MM91', 'A'), 'YutaniPistol_3D': ('YM91', 'A'),
        'PulseRifle_3D': ('PULS', 'A'), 'YutaniRifle_3D': ('PULS', 'A'), 'NewShotgun_3D': ('ATSG', 'A'), 'YutaniShotgun_3D': ('YTSG', 'A'),
        'Smartgun_3D': ('SMRT', 'A'), 'YutaniSmartgun_3D': ('SMRT', 'A'), 'M240Flamethrower_3D': ('FLMT', 'A'), 'YutaniFlamer_3D': ('YLAM', 'A')}
out = {}
for cls, rk in guns.items():
    mine = [b for b in blocks if b['cls'].lower() == cls.lower()]
    first = next((b for b in mine if rk in b['keys']), None)
    if not first:
        print(cls, 'no block with', rk); continue
    keys = {}
    for b in mine:
        if b['mesh'].lower() == first['mesh'].lower():
            for k, f in b['keys'].items(): keys.setdefault(k, f)
    path = km.find_file(AE, first['path'].replace('\\', '/') + '/' + first['mesh'])
    get, nfr = km.md3_frames(path)
    rf = keys[rk]
    a = km.to_ctrl(get(rf), first)
    rows = []
    for key, f in sorted(keys.items(), key=lambda kv: kv[1]):
        if f == rf or f >= nfr: continue
        b = km.to_ctrl(get(f), first)
        R, t, err = km.rigid(a, b)
        d = np.linalg.norm(a @ R.T + t - a, axis=1)
        rows.append((key, f, float(np.percentile(d, 95)), km.angle_of(R), err))
    big = [r for r in rows if r[2] >= 0.3 or r[3] >= 0.4]
    print('%-22s mesh %-12s ready %s%s=f%d  %d keyed frames, %d move the body' % (cls, first['mesh'], rk[0], rk[1], rf, len(rows), len(big)))
    for key, f, mv, ang, err in big[:12]:
        print('    %s %s -> f%-2d  move95 %5.2f cm  turn %5.2f deg  fit %.2f' % (key[0], key[1], f, mv, ang, err))
