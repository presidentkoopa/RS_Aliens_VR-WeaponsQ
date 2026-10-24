"""Fit this pack's hands with the kit's own fitters, via its documented add_pack() route.

HOW THE KIT WANTS THIS DONE (tool/hands/guns.py add_pack, HAND_FITTING section 7): register
the pack's MODELDEF and root, add a row per gun to handtable.TABLE saying which Ermac set each
hand borrows and how the support hand holds, then call fitall.run(cls). Nothing is reinvented
here -- align.fit, support.front_point and minigun_fit.rot_hook do the work.

WHY A PER-GUN BOX IS PASSED. fitall.run() looks for the gun hand's grip in a FIXED box,
f=(-22,6) l=(-5,5) u=(-24,-1) -- within 5 cm of the centreline, because every BD22 gun's grip
is there. This set's smartgun has its vertical grip at L +11, out to one side, so the kit's
default box cannot contain it and the fit lands nowhere near. That is the pack being unusual,
not the tool being wrong, so the box is given per gun and the default kept for the rest.

Run from this directory with plain `python -B`.
"""
import os
import sys

KIT = 'C:/Users/Command/Desktop/Quest_Weapons_Kit/kit/kit'
sys.path.insert(0, KIT + '/tool/hands')
sys.path.insert(0, KIT + '/melee')

import importlib.util

import numpy as np
import align
import ermac
import gunview
import handtable


def _load(name, path):
    """Load a specific file as a module.

    THERE ARE TWO guns.py IN THE KIT -- melee/guns.py and tool/hands/guns.py -- and only the
    second has add_pack(), the documented way to register another pack. Every kit module
    inserts melee/ at sys.path[0] as it loads, so a plain `import guns` resolves to the melee
    copy and add_pack is simply absent. This takes the file by name instead of by luck.
    """
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    sys.modules[name] = m
    spec.loader.exec_module(m)
    return m


guns = _load('guns', KIT + '/tool/hands/guns.py')

# align.py and support.py each captured the OTHER guns module when they loaded, so registering
# the pack on ours alone never reached align.fit() -- it looked our classes up in BD22's
# registry, got None, and died subscripting it. Point them at the one that knows this pack.
align.guns = guns
import support
support.guns = guns

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..')).replace('\\', '/')

# Each gun's ready (class, sprite, frame), as guns.READY lists BD22's. These are what the
# pack's own MODELDEF keys, so align.fit measures the gun AS DRAWN.
READY = [
    ('M4A3Pistol_3D', 'RSPM', 'B'),
    ('NewShotgun_3D', 'RSHG', 'A'),
    ('PulseRifle_3D', 'PULS', 'A'),
    ('Smartgun_3D',   'SMRT', 'A'),
    ('Knife_3D',             'ATKN', 'A'),
    ('Satcheler_3D',         'STCG', 'A'),
    ('M240Flamethrower_3D',  'FLMT', 'A'),
]

# gun -> (Ermac set for the gun hand, Ermac set for the support, how the support holds)
ROWS = {
    # the pistols: the off hand cups the gun hand, which is the kit's 'same'
    'M4A3Pistol_3D': ('pistol', 'pistol', ('same',)),
    # the pump: the off hand wraps the forend. 39 is where Shot_Gun's is; ours is measured below
    'NewShotgun_3D': ('shotgun', 'shotgun', ('wrap', 41)),
    'PulseRifle_3D': ('plasma', 'shotgun', ('wrap', 28)),
    # the smartgun's support is the side handlebar -- the kit's 'handle', which fitall.run()
    # deliberately does not do (it returns early); minigun_fit.py is that fit, and
    # tools/smartgun_fit.py drives it off the measured bar.
    'Smartgun_3D':   ('plasma', 'chaingun', ('handle',)),
    # The last three, 2026-10-24. A knife and a satchel are ONE-handed -- no support row, so
    # fitall.run() returns before its support branches, which is correct and not a failure.
    # The flamethrower is a two-handed gun and wraps like the rifle does.
    'Knife_3D':             ('pistol', 'pistol', ('none',)),
    'Satcheler_3D':         ('pistol', 'pistol', ('none',)),
    'M240Flamethrower_3D':  ('plasma', 'shotgun', ('wrap', 48)),
}

# gun hand grip box per gun, where the kit's default f=(-22,6) l=(-5,5) u=(-24,-1) is wrong
BOX = {
    # a knife is held by a handle at its own back end, not at a pistol grip's station
    'Knife_3D':     dict(f=(-14, 10), l=(-6, 6), u=(-12, 8)),
    'Satcheler_3D': dict(f=(-14, 12), l=(-8, 8), u=(-14, 8)),
    # vertical grip measured at F +6.8..+8.2, L +11.0, U -9.4..+0.5 (md3label + island split)
    'Smartgun_3D': dict(f=(1, 14), l=(5, 17), u=(-13, 4)),
}


def enclosure(cls, it, hand_items, f, grip, lmax=9.0):
    """Is the gun INSIDE the hand's curl at the plane F = f?

    The kit's check for a doubtful grip is the cross-section: "the part must sit inside the
    hand's curl" (HAND_FITTING, and the melee fits' xsec sheets). support.section() already
    gives the gun's outline at a plane; this slices the hand at the same plane and asks, from
    the gun's centre, how many of eight bearings have hand within 6 cm. 8/8 is a closed fist
    round the part; a flat palm laid on top scores about half, which is the failure the owner
    caught on the minigun.
    """
    # `gc` MUST be the grip, not the gun. First version sliced at F = the fit's SHIFT (a
    # translation, not a place) and centred on the whole cross-section, so it was asking
    # whether the hand surrounded the middle of the receiver. The caller now passes the grip
    # point the fit was matched against -- the centroid of align.box over the grip region.
    g = support.section(cls, f)
    if not len(g):
        return None, None
    gc = np.array(grip[1:], float)
    H = []
    for h in hand_items:
        for a, b, c3, _ in gunview.triangles([h]):
            a, b, c3 = np.atleast_2d(a), np.atleast_2d(b), np.atleast_2d(c3)
            for p, q in ((a, b), (b, c3), (c3, a)):
                s = (p[:, 0] - f) * (q[:, 0] - f)
                m = s < 0
                if m.any():
                    w = (f - p[m, 0]) / (q[m, 0] - p[m, 0])
                    H.append((p[m] + (q[m] - p[m]) * w[:, None])[:, 1:])
    if not H:
        return 0, gc
    H = np.concatenate(H)
    hit = 0
    for k in range(8):
        th = k * np.pi / 4
        d = np.array([np.cos(th), np.sin(th)])
        rel = H - gc
        along = rel @ d
        off = np.abs(rel @ np.array([-d[1], d[0]]))
        if ((along > 0) & (along < 6.0) & (off < 2.5)).any():
            hit += 1
    return hit, gc


def main():
    for name in sorted(os.listdir(ROOT)):
        if name.lower().startswith('modeldef') and os.path.isfile(os.path.join(ROOT, name)):
            guns.add_pack(os.path.join(ROOT, name), ROOT)
    guns.READY.extend(READY)
    handtable.TABLE.update(ROWS)
    import fitall

    out = os.path.join(ROOT, 'docs', 'renders', 'fit')
    os.makedirs(out, exist_ok=True)
    print('%-16s %-24s %-7s %-24s %-7s %s'
          % ('gun', 'gun hand F L U', 'resid', 'support F L U', 'resid', 'enclosure'))
    print('-' * 104)
    res = {}
    for cls, (gs, ss, where) in ROWS.items():
        it = guns.item(cls)
        if not it:
            print('%-16s no MODELDEF block' % cls)
            continue
        box = BOX.get(cls, dict(f=(-22, 6), l=(-5, 5), u=(-24, -1)))
        t, err, _ = align.fit(cls, gs, 1, box)
        t = np.array(t, float) + np.array([0, 0, -1.5])

        sup, serr = None, None
        if where[0] != 'handle':
            try:
                r, _t, t2 = fitall.run(cls)
                if t2 is not None:
                    sup, serr = np.array(t2, float), r.get('sup_err', 0.0)
            except Exception as exc:
                print('      support fit failed: %s' % exc)

        items = [dict(it, color=[120, 120, 110]),
                 dict(path=ROOT + '/models/rsq/hand.md3', frame=5, scale=[-1, 1, 1],
                      off=[0, -24, -10], hook=align.hook_from_shift(t), color=[235, 140, 40])]
        if sup is not None:
            items.append(dict(path=ROOT + '/models/rsq/hand2.md3', frame=2, scale=[-1, 1, 1],
                              off=[0, -24, -10], hook=align.hook_from_shift(sup),
                              color=[60, 200, 80]))
        # the plane through the gun hand's grip
        # the grip the fit was matched against, in the gun's own frame
        gpts = align.box(align.surface_points(it), **box)
        grip = gpts.mean(0) if len(gpts) else np.array([0.0, 0.0, 0.0])
        gf = float(grip[0])
        enc, gc = enclosure(cls, it, items[1:2], gf, grip)
        print('%-16s %-24s %-7.2f %-24s %-7s %s'
              % (cls, np.round(t, 2), err,
                 np.round(sup, 2) if sup is not None else 'handle (minigun_fit)',
                 ('%.2f' % serr) if serr is not None else '-',
                 ('%d/8 at grip F%+.1f L%+.1f U%+.1f' % (enc, grip[0], grip[1], grip[2])) if enc is not None else 'no section'))
        res[cls] = dict(gun=t.round(2).tolist(), gun_err=round(err, 2),
                        sup=sup.round(2).tolist() if sup is not None else None,
                        enc=enc)
        for kind in ('side', 'front'):
            try:
                gunview.view(items, os.path.join(out, 'kitfit_%s_%s.png' % (cls, kind)),
                             kind=kind, title='%s %s  kit fit' % (cls, kind))
            except Exception as exc:
                print('      %s sheet failed: %s' % (kind, exc))
    import json
    json.dump(res, open(os.path.join(ROOT, 'docs', 'kitfit.json'), 'w'), indent=1)
    print()
    print('enclosure 8/8 = the grip is inside the hand all round; a flat palm scores ~4.')


if __name__ == '__main__':
    main()
