"""Cross-section the knife and satchel grips with the kit's melee sheets.

WHY. tools/fit_hands.py fits these two with the GUN fitter and they score 2/8 and 0/8 on
enclosure -- a knife handle should sit fully inside a fist. The kit's own melee work says what
to do about a grip in doubt, in saw_fix.py's own words: a contact score "alone is not trusted
(a round tube scores much the same at many rolls -- the axe's first fit scored 62% with the
haft outside the fist), so the sheets decide". fitlib.xsec_sheet is those sheets.

This cuts the weapon and the hand on three planes through the grip and draws both outlines, so
the question "is the handle inside the curl or beside it" is answered by looking.
"""
import os
import sys

KIT = 'C:/Users/Command/Desktop/Quest_Weapons_Kit/kit/kit'
sys.path.insert(0, KIT + '/team/melee_hands/work')
sys.path.insert(0, KIT + '/melee')
sys.path.insert(0, KIT + '/tool/hands')

import importlib.util

import numpy as np


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    sys.modules[name] = m
    spec.loader.exec_module(m)
    return m


# the registry that knows this pack (tool/hands/guns.py has add_pack; melee/guns.py does not)
guns = _load('guns', KIT + '/tool/hands/guns.py')
import align
import ermac
import fitlib

fitlib.guns = guns
align.guns = guns

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..')).replace('\\', '/')

READY = [('Knife_3D', 'ATKN', 'A'), ('Satcheler_3D', 'STCG', 'A')]

# the gun-fitter's answers, from docs/kitfit.json -- what the sheets are judging
SHIFT = {'Knife_3D': (0.24, 0.50, -2.35), 'Satcheler_3D': (8.50, 1.07, -0.85)}
POSE = {'Knife_3D': 19, 'Satcheler_3D': 19}        # Ermac's pistol gun hand, as handtable uses


def main():
    for name in sorted(os.listdir(ROOT)):
        if name.lower().startswith('modeldef') and os.path.isfile(os.path.join(ROOT, name)):
            guns.add_pack(os.path.join(ROOT, name), ROOT)
    guns.READY.extend(READY)

    out = os.path.join(ROOT, 'docs', 'renders', 'fit')
    os.makedirs(out, exist_ok=True)

    for cls, shift in SHIFT.items():
        it = guns.item(cls)
        if not it:
            print('%s: no MODELDEF block' % cls)
            continue
        g = dict(it, color=list(fitlib.GUN), fill=False)
        h = fitlib.hand(POSE[cls], hook=align.hook_from_shift(np.array(shift, float)))

        # where the hand actually is, so the cuts go through the grip and not through air
        pts = align.surface_points(h, per_tri=False)
        c = pts.mean(0)
        print('%-14s hand centre F %+6.2f L %+6.2f U %+6.2f' % (cls, c[0], c[1], c[2]))

        planes = []
        for d in (-3.0, 0.0, 3.0):
            o = c + np.array([d, 0, 0])
            planes.append((o, (1, 0, 0), (0, 0, 1), 'F %+.0f' % (c[0] + d)))
        p = os.path.join(out, 'xsec_%s.png' % cls)
        fitlib.xsec_sheet([g, h], planes, p, half=9, px=16,
                          title='%s  grey = weapon, skin = hand' % cls)
        print('   %s' % p)


if __name__ == '__main__':
    main()
