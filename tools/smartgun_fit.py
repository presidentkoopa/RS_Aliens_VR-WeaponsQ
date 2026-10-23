"""How the smartgun hands were fitted (2026-10-23). Run from a dir with hudrender.py/gunview.py.
Solves the hook that puts a hand frame's centre on a target point (F, L, U cm, controller frame)
for a given turn, then renders orange (gun hand) / green (support) sheets. Edit TARGETS/ROTS."""
import sys, numpy as np, gunview, hudrender
A = sys.argv[1] if len(sys.argv) > 1 else '..'
def center(path, frame, hook, rot):
    h = {'path': path, 'frame': frame, 'scale': [-1, 1, 1], 'off': [0, -24, -10], 'hook': list(hook), 'rot': list(rot)}
    tr = gunview.triangles([h]); allv = np.concatenate([np.concatenate([a, b, c]) for a, b, c, _ in tr])
    return (allv.min(0) + allv.max(0)) / 2
def solve(path, frame, rot, target):
    c0 = center(path, frame, (0, 0, 0), rot); J = np.zeros((3, 3))
    for k in range(3):
        e = [0, 0, 0]; e[k] = 10.0; J[:, k] = (center(path, frame, e, rot) - c0) / 10.0
    return np.linalg.solve(J, np.array(target) - c0)
gun = {'path': A + '/models/weapons/smartgun/m56.md3', 'frame': 0, 'scale': [-0.9, 0.9, 0.9], 'off': [0, -30, -7], 'color': [120, 120, 110]}
# rear handlebar (bar along F at U -2, brake lever below) / left handle past the drum
gh_rot, gh_t = (0, 90, -90), (-52, 1, -2)      # hand.md3 frame 5 = Ermac 106 fist; wrist up, fingers down
sh_rot, sh_t = (10.21, 16.06, 95.16), (23, 13, -4)   # hand2.md3 frame 2 = Ermac 91 handlebar fist, BD22 minigun turn
gh = solve(A + '/models/rsq/hand.md3', 5, gh_rot, gh_t); sh = solve(A + '/models/rsq/hand2.md3', 2, sh_rot, sh_t)
print('GunHook', gh.round(2), 'GunRot', gh_rot, 'SupportHook', sh.round(2), 'SupportRot', sh_rot)
items = [gun, {'path': A + '/models/rsq/hand.md3', 'frame': 5, 'scale': [-1, 1, 1], 'off': [0, -24, -10], 'hook': [float(x) for x in gh], 'rot': list(gh_rot), 'color': [235, 140, 40]},
         {'path': A + '/models/rsq/hand2.md3', 'frame': 2, 'scale': [-1, 1, 1], 'off': [0, -24, -10], 'hook': [float(x) for x in sh], 'rot': list(sh_rot), 'color': [60, 200, 80]}]
for vn, v in {'rearleft': dict(eye=(-0.75, 0.35, 0.55), look=(-0.05, -0.05, -0.05)), 'rear': dict(eye=(0.0, 0.3, 1.2), look=(0.0, -0.05, 0.3)), 'left': dict(eye=(-1.1, 0.15, -0.1), look=(0.0, -0.05, -0.1))}.items():
    hudrender.render(items, f'smartgun_{vn}.png', **v)
