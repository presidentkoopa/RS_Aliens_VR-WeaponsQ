"""Fit Ermac's ONE-HANDED pistol pose onto this pack's pistols, with the kit's own tools.

The two-handed pose (Ermac hand.md3 frame 19) is already fitted and is what the pistols use.
This finds the hook for the ONE-handed pose (his frame 6) so the gun hand can change when the
support hand comes off, which is what BD22 does and what the kit documents:

    Quest_Weapons_Kit/kit/kit/tool/hands/HAND_FITTING.md section 1
      | Ermac set | gun hand (two hands) | support hand | gun hand (one hand) |
      | pistol    | 19                   | 4            | 6                   |

    section 5: "within 15 cm of the gun's support point the off hand takes hold ... pistols
    also switch to the two-hand gun-hand pose."

WHY A SECOND FIT IS NEEDED AT ALL, and why shipping the pose without one broke the hands:

    section 7: "Ermac's frames carry the pose and THE FIT CARRIES ONLY THE POSITION."

Each pose is posed against Ermac's OWN pistol. The hook is what moves it onto ours, and it is
found per pose by fitting the patch of Ermac's gun that THAT hand holds. Pose 6 holds his gun
in a different place from pose 19, so it needs its own run. Swapping the pose under pose 19's
hook leaves the hand holding air.

Method, exactly as align.py does it for the gun hand (HAND_FITTING.md section 4):
  - sample the surface of Ermac's berreta and of his hand frame 6;
  - keep the patch of the gun within 3 cm of that hand -- what it is holding;
  - ICP that patch onto our pistol's grip, translation only, in the box F -22..6, U -24..-1;
  - then 1.5 cm down, which the kit applies to every gun hand;
  - hook_from_shift() turns the shift into a ModifyBobLayer3D hook.

Run from this directory with plain `python` (the kit's note: never -I, it strips the script's
own directory from sys.path and the kit's tools import their neighbours).
"""
import os
import sys

KIT = 'C:/Users/Command/Desktop/Quest_Weapons_Kit/kit/kit'
sys.path.insert(0, KIT + '/tool/hands')
sys.path.insert(0, KIT + '/melee')

import numpy as np
import align
import ermac
import gunview
import hudrender

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))

# our pistols, as their own MODELDEF draws them at ready (modeldef.pistol.txt). The hand is
# fitted against the gun AS DRAWN, so these are the numbers that matter.
OURS = [
    ('M4A3Pistol_3D',   'models/weapons/pistol/m4a3.md3',  0),
    ('MercPistol_3D',   'models/weapons/pistol/m4a3.md3',  0),
    ('SynthPistol_3D',  'models/weapons/pistol/m4a3.md3',  0),
    ('YutaniPistol_3D', 'models/weapons/pistol/m4a3.md3',  0),
]
PLACE = dict(scale=[-0.82, 0.82, 0.82], off=[0.0, -29.0, -8.0])

GRIP_BOX = dict(f=(-22.0, 6.0), u=(-24.0, -1.0))   # HAND_FITTING.md section 4
DROP = 1.5                                          # "...then 1.5 cm down"


def ermac_one_handed():
    """(points of Ermac's pistol, points of his ONE-handed pose) -- SETS[...][4] is frame 6."""
    g, gf, h_two, h_sup, h_one = ermac.SETS['pistol']
    gun = dict(path=ermac.E + g, frame=gf, **ermac.PL)
    hand = dict(path=ermac.E + 'hand/hand.md3', frame=h_one, **ermac.PL)
    return align.surface_points(gun), align.surface_points(hand, per_tri=False), h_one, h_two


def main():
    gE, hE, h_one, h_two = ermac_one_handed()
    patch = align.held_patch(gE, hE, 3.0)
    print("Ermac's pistol: %d surface points; one-handed pose is hand.md3 frame %d "
          "(the fitted two-handed pose is frame %d)" % (len(gE), h_one, h_two))
    print('the patch his one hand holds: %d points' % len(patch))
    if len(patch) < 10:
        print('REFUSING: too small a patch to fit')
        return 1

    seen = {}
    for cls, mesh, frame in OURS:
        path = os.path.join(ROOT, mesh).replace('\\', '/')
        if not os.path.exists(path):
            print('%-18s mesh missing: %s' % (cls, path))
            continue
        it = dict(path=path, frame=frame, **PLACE)
        gO = align.surface_points(it)
        dst = align.box(gO, **GRIP_BOX)
        if len(dst) < 20:
            print('%-18s only %d points in the grip box -- not fitting' % (cls, len(dst)))
            continue
        key = (mesh, frame)
        if key in seen:
            t, err = seen[key]
            print('%-18s same mesh as a gun already fitted: carries its fit' % cls)
        else:
            t, err = align.icp_translate(patch, dst, (0, 0, 0))
            t = np.array(t, float)
            t[2] -= DROP
            seen[key] = (t, err)
        hook = align.hook_from_shift(t)
        print('%-18s shift F %+6.2f L %+6.2f U %+6.2f cm   median residual %.2f cm   hook %s'
              % (cls, t[0], t[1], t[2], err, hook))
    return 0


if __name__ == '__main__':
    sys.exit(main())
