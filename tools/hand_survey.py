"""Render where every gun's hands ACTUALLY sit, from the live handtable, using the pack's own
render chain -- so a wrong hand is something you look at rather than something you feel for
with sliders.

Why this can be trusted: hudrender.to_local implements the engine's RenderHUDModel chain
exactly -- axis swap, Ry(90), +hook, the three rotations, then scale and Offset mapped as
(xo, zo, yo). That is the same y/z mapping the engine uses (translate(xoffset/xscale,
zoffset/zscale, yoffset/yscale)) and the same hook-inside-rotations order. Verified against
src/r_data/models.cpp at 9afc750917 on 2026-10-23.

Run from this directory:
    python -I hand_survey.py            # every gun, side+front+top sheets
    python -I hand_survey.py PulseRifle_3D
Sheets land in ../docs/renders/fit/.
"""
import os
import re
import sys

# python -I is isolated mode, which does NOT put the script's own directory on sys.path, so
# gunview/hudrender next to this file would not import. Add it explicitly rather than dropping
# -I, since isolated mode is what keeps a stray module in the working directory out of the way.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import gunview

SEP = chr(92)  # backslash, written this way so no shell heredoc can eat it

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
OUT = os.path.join(ROOT, 'docs', 'renders', 'fit')

# Guns in RSQ_HandTable order (zscript/rsq/handtable.zs Index()).
GUNS = [
    None, 'Knife_3D', 'M240Flamethrower_3D', 'M4A3Pistol_3D', 'MercPistol_3D',
    'NewShotgun_3D', 'PulseRifle_3D', 'Satcheler_3D', 'Smartgun_3D', 'SynthPistol_3D',
    'YutaniFlamer_3D', 'YutaniKnife_3D', 'YutaniPistol_3D', 'YutaniRifle_3D',
    'YutaniSatchel_3D', 'YutaniShotgun_3D', 'YutaniSmartgun_3D',
]

# hand.md3 frame per pose letter, from MODELDEF.ae's FrameIndex RQGS lines
POSE_FRAME = {'A': 0, 'B': 1, 'C': 2, 'D': 3, 'E': 4, 'F': 5}


def norm(p):
    return p.replace(SEP, '/')


def read(path):
    with open(path, encoding='utf-8', errors='replace') as fh:
        return fh.read()


def handtable():
    """-> {index: dict(gunpose, supportpose, gunhook, gunrot, supporthook, supportrot)}"""
    t = read(os.path.join(ROOT, 'zscript', 'rsq', 'handtable.zs'))

    def strs(fn):
        # take the function BODY first (same shape as vecs below), then the array inside it
        body = re.search(r'static\s+String\s+%s\s*\(\s*int\s+i\s*\)\s*\{(.*?)\n\t\}' % fn, t, re.S).group(1)
        vals = re.search(r'static\s+const\s+String\s+v\[\s*\]\s*=\s*\{(.*?)\}', body, re.S).group(1)
        return [x.strip().strip('"') for x in vals.split(',')]

    def vecs(fn):
        body = re.search(r'static\s+Vector3\s+%s\s*\(\s*int\s+i\s*\)\s*\{(.*?)\n\t\}' % fn, t, re.S).group(1)
        ax = {a: [float(v) for v in vv.replace('\n', ' ').split(',') if v.strip()]
              for a, vv in re.findall(r'static\s+const\s+double\s+([xyz])\s*\[\s*\]\s*=\s*\{([^}]*)\}', body)}
        return [(ax['x'][i], ax['y'][i], ax['z'][i]) for i in range(len(ax['x']))]

    gp, sp = strs('GunPose'), strs('SupportPose')
    gh, gr, sh, sr = vecs('GunHook'), vecs('GunRot'), vecs('SupportHook'), vecs('SupportRot')
    out = {}
    for i in range(1, len(GUNS)):
        out[i] = dict(gunpose=gp[i] if i < len(gp) else '', supportpose=sp[i] if i < len(sp) else '',
                      gunhook=gh[i], gunrot=gr[i], supporthook=sh[i], supportrot=sr[i])
    return out


def gun_blocks():
    """-> {class: dict(mesh, scale, off)} for each gun's BODY block (not its hand block)."""
    blocks = {}
    for name in sorted(os.listdir(ROOT)):
        if not name.lower().startswith('modeldef') or os.path.isdir(os.path.join(ROOT, name)):
            continue
        cur, d = None, {}
        for line in read(os.path.join(ROOT, name)).split('\n'):
            m = re.match(r'^\s*Model\s+(\w+)\s*$', line)
            if m:
                if cur and d.get('model'):
                    blocks.setdefault(cur, []).append(dict(d))
                cur, d = m.group(1), {}
                continue
            if cur is None:
                continue
            m = re.match(r'^\s*Path\s+"?([^"\n]+)"?', line, re.I)
            if m:
                d['path'] = m.group(1).strip()
            m = re.match(r'^\s*Model\s+0\s+"([^"]+)"', line, re.I)
            if m:
                d['model'] = m.group(1)
            m = re.match(r'^\s*Scale\s+(\S+)\s+(\S+)\s+(\S+)', line, re.I)
            if m:
                d['scale'] = [float(x) for x in m.groups()]
            m = re.match(r'^\s*Offset\s+(\S+)\s+(\S+)\s+(\S+)', line, re.I)
            if m:
                d['off'] = [float(x) for x in m.groups()]
        if cur and d.get('model'):
            blocks.setdefault(cur, []).append(dict(d))

    res = {}
    for cls, bs in blocks.items():
        for b in bs:
            mdl = b.get('model', '').lower()
            if 'hand' in mdl or not mdl.endswith(('.md3', '.obj', '.iqm')):
                continue
            p = norm(os.path.join(ROOT, b.get('path', ''), b['model']))
            if os.path.exists(p):
                res[cls] = dict(mesh=p, scale=b.get('scale', [1, 1, 1]), off=b.get('off', [0, 0, 0]))
                break
    return res


def main():
    os.makedirs(OUT, exist_ok=True)
    ht, gb = handtable(), gun_blocks()
    want = sys.argv[1:] or [g for g in GUNS if g]
    hand = norm(os.path.join(ROOT, 'models', 'rsq', 'hand.md3'))
    hand2 = norm(os.path.join(ROOT, 'models', 'rsq', 'hand2.md3'))

    print('%-22s %-7s %-24s %-24s %s' % ('gun', 'pose', 'GunHook', 'GunRot', 'sheets'))
    for i in range(1, len(GUNS)):
        cls = GUNS[i]
        if cls not in want:
            continue
        row, body = ht[i], gb.get(cls)
        if not body:
            print('%-22s -- no gun body mesh found in any MODELDEF' % cls)
            continue
        items = [dict(path=body['mesh'], frame=0, scale=body['scale'], off=body['off'],
                      color=[120, 120, 110])]
        gpose = row['gunpose']
        if gpose in POSE_FRAME:
            items.append(dict(path=hand, frame=POSE_FRAME[gpose], scale=[-1, 1, 1],
                              off=[0, -24, -10], hook=list(row['gunhook']),
                              rot=list(row['gunrot']), color=[235, 140, 40]))
        spose = row['supportpose']
        if spose in POSE_FRAME:
            items.append(dict(path=hand2 if spose == 'C' else hand, frame=POSE_FRAME[spose],
                              scale=[-1, 1, 1], off=[0, -24, -10], hook=list(row['supporthook']),
                              rot=list(row['supportrot']), color=[60, 200, 80]))
        made = []
        for kind in ('side', 'front', 'top'):
            out = os.path.join(OUT, '%s_%s.png' % (cls, kind))
            try:
                gunview.view(items, out, kind=kind, title='%s  %s' % (cls, kind))
                made.append(kind)
            except Exception as exc:
                made.append('%s FAILED(%s)' % (kind, exc))
        print('%-22s %-7s %-24s %-24s %s'
              % (cls, gpose or '-', '(%.2f %.2f %.2f)' % row['gunhook'],
                 '(%.2f %.2f %.2f)' % row['gunrot'], ','.join(made)))
    print('\nsheets in', OUT)
    print('orange = gun hand, green = support hand, grey = the gun')


if __name__ == '__main__':
    main()
