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
try:
    import support as _sup
    _sup.guns = guns
except Exception:
    pass

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..')).replace('\\', '/')

# Each gun's ready (class, sprite, frame), as guns.READY lists BD22's. These are what the
# pack's own MODELDEF keys, so align.fit measures the gun AS DRAWN.
READY = [
    ('M4A3Pistol_3D', 'RSPM', 'B'),
    ('NewShotgun_3D', 'RSHG', 'A'),
    ('PulseRifle_3D', 'PULS', 'A'),
    ('Smartgun_3D',   'SMRT', 'A'),
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
}

# gun hand grip box per gun, where the kit's default f=(-22,6) l=(-5,5) u=(-24,-1) is wrong
BOX = {
    # vertical grip measured at F +6.8..+8.2, L +11.0, U -9.4..+0.5 (md3label + island split)
    'Smartgun_3D': dict(f=(1, 14), l=(5, 17), u=(-13, 4)),
}


def main():
    md = os.path.join(ROOT, 'modeldef.pistol.txt')
    # every modeldef.*.txt in the pack, so one registration covers all four guns
    for name in sorted(os.listdir(ROOT)):
        if name.lower().startswith('modeldef') and os.path.isfile(os.path.join(ROOT, name)):
            guns.add_pack(os.path.join(ROOT, name), ROOT)
    guns.READY.extend(READY)
    handtable.TABLE.update(ROWS)

    print('%-18s %-22s %-8s %s' % ('gun', 'gun-hand shift F L U', 'residual', 'note'))
    print('-' * 78)
    for cls, (gs, ss, where) in ROWS.items():
        it = guns.item(cls)
        if not it:
            print('%-18s MODELDEF block not found -- add_pack could not measure it' % cls)
            continue
        box = BOX.get(cls, dict(f=(-22, 6), l=(-5, 5), u=(-24, -1)))
        try:
            t, err, _ = align.fit(cls, gs, 1, box)
        except Exception as exc:
            print('%-18s fit failed: %s' % (cls, exc))
            continue
        t = np.array(t, float) + np.array([0, 0, -1.5])
        note = 'box %s' % ('per-gun' if cls in BOX else 'kit default')
        if err > 2.0:
            note += '  *** residual over 2 cm, do not trust ***'
        print('%-18s %-22s %-8.2f %s'
              % (cls, np.round(t, 2), err, note))
        # OPEN THE SHEET. 000_READ_THIS_FIRST section 6: never trust a tool's silence -- both
        # owner-caught bugs in the shipped pack were visible in sheets nobody opened.
        items = [dict(it, color=[120, 120, 110]),
                 dict(path=ROOT + '/models/rsq/hand.md3', frame=5, scale=[-1, 1, 1],
                      off=[0, -24, -10], hook=align.hook_from_shift(t), color=[235, 140, 40])]
        out = os.path.join(ROOT, 'docs', 'renders', 'fit', 'kitfit_%s_%%s.png' % cls)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        for kind in ('side', 'front'):
            try:
                gunview.view(items, out % kind, kind=kind, title='%s %s  kit fit' % (cls, kind))
            except Exception as exc:
                print('      %s sheet failed: %s' % (kind, exc))
    print()
    print('Support hands: "same" and "wrap" are fitall.run()\'s own branches; "handle" is')
    print('minigun_fit.rot_hook, which tools/smartgun_fit.py drives off the measured bar.')


if __name__ == '__main__':
    main()
