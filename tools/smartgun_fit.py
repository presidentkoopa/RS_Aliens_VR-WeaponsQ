"""Fit the smartgun's two hands with the Quest Weapons Kit's own tools.

REWRITTEN 2026-10-23 against MEASURED targets. The previous version solved a hook to put a
hand's centre on a point I had typed in by eye. These targets come out of the mesh:

  HighQualityTools/md3label.py on m56.md3 gave the grip line and the muzzle;
  HighQualityTools/md3read.py + an island split of surface 0 gave the three handles.

The owner names them (and the film's own layout):
  REAR grip    surf 1, its own surface, x -58.5..-41.7 y~0 z -7.3..-3.7. The harness tilt grip
               from the film. NOT USED in VR -- left alone here.
  SIDE HANDLEBAR  island ctr [30.5, 13.6, 9.7], long axis y, y 8.6..18.5. The OFF hand, fist
               round the bar with the thumb out over the red button.
  RED BUTTON   islands [31.9, 18.9, 9.7] and [32.1, 19.6, 9.7], at the bar's outboard end --
               this is what the thumb has to reach, so it sets which way the fist turns.
  VERTICAL GRIP  md3label's grip line [8.89, 11.98, 2.72] -> [7.37, 12.00, -8.08]. The MAIN
               hand.

Model units -> controller cm with this pack's chain (Scale 0.9, ZOffset -7): x0.918, U-2.

The handlebar is fitted the way kit/tool/hands/minigun_fit.py does it, with that file's own
rot_hook() and frame(): Ermac's vertical-grip fist (hand2 frame 91) turned so THE BAR RUNS
THROUGH THE FIST. HAND_FITTING.md is explicit that a flat palm laid over a bar is wrong, and
the owner caught exactly that on the minigun in v9.

Run from this directory with plain `python -B` (never -I: it strips the script's own directory
and the kit's tools import their neighbours).
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
import minigun_fit                      # rot_hook() and frame(), the handlebar method
import support

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))

# the smartgun as its own MODELDEF draws it (modeldef.smartgun.txt)
GUN = dict(path=ROOT.replace('\\', '/') + '/models/weapons/smartgun/m56.md3', frame=0,
           scale=[-0.9, 0.9, 0.9], off=[0.0, -30.0, -7.0], color=[120, 120, 110])

S = 0.918                               # model units -> cm
U0 = -2.0

# --- the measured targets, in controller cm -------------------------------------------------
BAR_MID = np.array([30.5 * S, 13.6 * S, 9.7 * S + U0])          # F 28.0  L 12.5  U  6.9
BUTTON  = np.array([32.0 * S, 19.2 * S, 9.7 * S + U0])          # F 29.4  L 17.6  U  6.9
VGRIP_T = np.array([8.89 * S, 11.98 * S,  2.72 * S + U0])       # top of the vertical grip
VGRIP_B = np.array([7.37 * S, 12.00 * S, -8.08 * S + U0])       # bottom
VGRIP   = (VGRIP_T + VGRIP_B) / 2

DROP = 1.5                              # HAND_FITTING.md section 4: every gun hand, 1.5 cm down


def gun_hand():
    """Ermac's plasma gun hand (106) onto our vertical grip, translation only (align.py)."""
    gE, hE = align.ermac_points('plasma', 1)        # 1 = the gun hand
    patch = align.held_patch(gE, hE, 3.0)
    ours = align.surface_points(GUN)
    # a box around the vertical grip only, generous in U because the grip is 10.8 cm tall
    dst = align.box(ours, f=(VGRIP[0] - 7, VGRIP[0] + 7),
                          l=(VGRIP[1] - 6, VGRIP[1] + 6),
                          u=(VGRIP_B[2] - 3, VGRIP_T[2] + 3))
    if len(dst) < 20:
        print('gun hand: only %d points in the grip box -- not fitting' % len(dst))
        return None, None, 0.0
    t, err = align.icp_translate(patch, dst, (0, 0, 0))
    t = np.array(t, float)
    t[2] -= DROP
    return align.hook_from_shift(t), t, err


def off_hand():
    """Ermac's vertical-grip fist (hand2 frame 91) round the handlebar, bar through the fist.

    His 91 holds a VERTICAL bar, so his held axis is U. Ours runs out laterally, so the turn
    maps his U onto our L. The thumb then points along +L, which is where the red button is --
    that is the whole reason the bar is fitted with a turn rather than a translation.
    """
    gE, hE = align.ermac_points('plasma', 2)        # 2 = the support hand, frame 91
    patch = align.held_patch(gE, hE, 3.0)
    c = patch.mean(0)

    # THE RECIPE, VERBATIM. HAND_FITTING / the fitting notes give the handlebar turn as
    #     rot_hook(c, t, frame(bar_axis, (1, 0, 0.3)) @ frame((0, 0, -1), (1, 0, 0)).T)
    # The source frame is (0, 0, -1): his 91 fist holds its bar pointing DOWN, not up. I first
    # wrote (0, 0, 1) from the name "vertical-grip fist" and the result was a fist standing on
    # end -- 17 cm tall, the bar beside it rather than through it, which is precisely the flat
    # -palm-on-a-bar failure the notes warn about and the owner caught on the minigun.
    bar_axis = np.array([0.0, 1.0, 0.0])            # our bar: straight out along L, level
    Rw = minigun_fit.frame(bar_axis, (1, 0, 0.3)) @ minigun_fit.frame((0, 0, -1), (1, 0, 0)).T
    hook, ypr = minigun_fit.rot_hook(c, BAR_MID, Rw)
    return hook, ypr, c


def main():
    print('MEASURED TARGETS (controller cm, F forward / L left / U up)')
    print('   side handlebar mid  F %+6.2f  L %+6.2f  U %+6.2f' % tuple(BAR_MID))
    print('   red button          F %+6.2f  L %+6.2f  U %+6.2f' % tuple(BUTTON))
    print('   vertical grip mid   F %+6.2f  L %+6.2f  U %+6.2f' % tuple(VGRIP))
    print('   thumb reach, bar mid -> button: %.2f cm' % np.linalg.norm(BUTTON - BAR_MID))
    print()

    gh, gt, gerr = gun_hand()
    oh, oypr, c = off_hand()
    print('MAIN hand  (hand.md3 frame 5 = Ermac 106) on the vertical grip')
    print('   GunHook  %s   median residual %.2f cm' % (gh, gerr))
    print('OFF hand   (hand2.md3 frame 2 = Ermac 91) round the handlebar')
    print('   SupportHook %s' % oh)
    print('   SupportRot  %s' % oypr)
    print()

    items = [GUN,
             dict(path=ROOT.replace('\\', '/') + '/models/rsq/hand.md3', frame=5,
                  scale=[-1, 1, 1], off=[0, -24, -10], hook=list(gh),
                  color=[235, 140, 40]),
             dict(path=ROOT.replace('\\', '/') + '/models/rsq/hand2.md3', frame=2,
                  scale=[-1, 1, 1], off=[0, -24, -10], hook=list(oh), rot=list(oypr),
                  color=[60, 200, 80])]
    out = os.path.join(ROOT, 'docs', 'renders', 'fit')
    os.makedirs(out, exist_ok=True)
    made = []
    for kind in ('side', 'front', 'top'):
        p = os.path.join(out, 'smartgun_handles_%s.png' % kind)
        try:
            gunview.view(items, p, kind=kind, title='smartgun handles  %s' % kind)
            made.append(p)
        except Exception as exc:
            print('%s sheet FAILED: %s' % (kind, exc))
    print('sheets:')
    for p in made:
        print('  ', p)
    print('orange = main hand, green = off hand, grey = the gun')


if __name__ == '__main__':
    main()
