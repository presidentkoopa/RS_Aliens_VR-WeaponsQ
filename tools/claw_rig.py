"""Give the power loader's claw a closing jaw, with the kit's own rig and writer.

THE PROBLEM. loader_arm_r.md3 and loader_arm_l.md3 carry 21 frames and every one of them is
the punch (travel peaks at frame 6, back by 14, 15..20 padding). There is no frame in which the
jaws are part-closed, so clawShut -- which already tracks 0 -> 1 on a grab and >= 0.98 on a
crush -- had nothing to draw.

THE PRECEDENT is trigger_finger/, which does this exact thing to a hand: it finds the index
finger as its own mesh component, hinges it with Rodrigues, and appends the result with
md3w.add_frames(). rig.py's own docstring: "The index finger is its own mesh piece (component
1, 79 verts). Three hinge joints ... flexion about the finger's lateral axis". A claw jaw is
the same kind of part, so this is that method pointed at a different component.

THE GEOMETRY, measured with HighQualityTools/md3read and a union-find island split: the arm is
one surface of 1777 verts in 114 components, and the front-most ones come in MIRRORED PAIRS --
17 verts at z +35.8 against 17 at z -35.3, 32 at +28.5 against 32 at -28.2, and so on, all at
x 181..228. That is a two-jaw claw split across z, each jaw several components.

A jaw closes by hinging about the Y axis at its own root: rotation about y moves a point in the
xz plane, and a jaw tip sits ~53 units FORWARD of its root, so z' = -53 sin(theta) -- about 32
degrees brings a tip from z 28 to the centreline. Each jaw turns the opposite way.

Writes the two meshes in place with CLOSE_STEPS extra frames appended, lossless: add_frames
only appends, so frames 0..20 are untouched and the punch still plays.
"""
import os
import sys

KIT = 'C:/Users/Command/Desktop/Quest_Weapons_Kit'
sys.path.insert(0, KIT + '/trigger_finger/trigger_finger')
sys.path.insert(0, KIT + '/HighQualityTools')

import numpy as np
import md3w
from md3read import read_md3

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..')).replace('\\', '/')
ARMS = ('loader_arm_r.md3', 'loader_arm_l.md3')

CLOSE_STEPS = 6          # extra frames: 1/6 shut .. fully shut
FULL_DEG = 26.7          # MEASURED, not derived: at 26.7 the tips meet (gap 0.7) and at 32
                         # they pass THROUGH each other (gap back to 12.4, jaws crossed). The
                         # 32 came from sin(theta) = 28/53 on the tip alone and was wrong,
                         # because the tip is not the part that meets first.
JAW_Z = 20.0             # |z| above which a component belongs to a jaw
JAW_X = 160.0            # and only at the front of the arm


def components(v, tri):
    par = list(range(len(v)))

    def find(a):
        while par[a] != a:
            par[a] = par[par[a]]
            a = par[a]
        return a

    for t in tri:
        for b in t[1:]:
            ra, rb = find(t[0]), find(b)
            if ra != rb:
                par[ra] = rb
    g = {}
    for i in range(len(v)):
        g.setdefault(find(i), []).append(i)
    return list(g.values())


def rodrigues(axis, deg):
    a = np.asarray(axis, float)
    a /= np.linalg.norm(a)
    th = np.radians(deg)
    K = np.array([[0, -a[2], a[1]], [a[2], 0, -a[0]], [-a[1], a[0], 0]])
    return np.eye(3) + np.sin(th) * K + (1 - np.cos(th)) * K @ K


def jaws(v, tri):
    """-> [(vertex indices, pivot)] for the +z jaw and the -z jaw"""
    out = []
    for sign in (+1, -1):
        idx = []
        for c in components(v, tri):
            p = v[c]
            ctr = (p.min(0) + p.max(0)) / 2
            if p[:, 0].max() > JAW_X and sign * ctr[2] > JAW_Z:
                idx.extend(c)
        if not idx:
            out.append((None, None))
            continue
        idx = np.array(sorted(set(idx)))
        p = v[idx]
        # the jaw's ROOT: its rearmost tenth, where it meets the arm
        back = p[p[:, 0] <= np.percentile(p[:, 0], 10)]
        out.append((idx, back.mean(0)))
    return out


def run(path):
    m = read_md3(path)
    assert len(m['surfs']) == 1, '%s: %d surfaces, md3w wants 1' % (path, len(m['surfs']))
    s = m['surfs'][0]
    V = np.asarray(s['xyz'], float)          # (nframes, nv, 3)
    N = np.asarray(s['normals'], float) if 'normals' in s else None
    tri = np.asarray(s['tris']).reshape(-1, 3)
    rest = V[0]
    restN = N[0] if N is not None else np.tile(np.array([0.0, 0.0, 1.0]), (len(rest), 1))

    js = jaws(rest, tri)
    for k, (idx, piv) in enumerate(js):
        print('   jaw %s: %s verts, root %s'
              % ('+z' if k == 0 else '-z',
                 len(idx) if idx is not None else 'NONE',
                 np.round(piv, 1) if piv is not None else '-'))
    if any(i is None for i, _ in js):
        print('   %s: a jaw was not found -- not writing' % os.path.basename(path))
        return None

    frames, names = [], []
    for step in range(1, CLOSE_STEPS + 1):
        deg = FULL_DEG * step / CLOSE_STEPS
        P = rest.copy()
        Nn = restN.copy()
        for k, (idx, piv) in enumerate(js):
            # SIGN, verified by the gap and not by reasoning: the first run turned the two
            # jaws the wrong way and the tip-to-tip gap OPENED from 75 to 136. A jaw tip sits
            # forward of its root, rotation about y gives z' = -dx sin(theta), so the +z jaw
            # needs a POSITIVE angle to come down to the centreline.
            R = rodrigues((0, 1, 0), deg * (+1 if k == 0 else -1))
            P[idx] = (R @ (rest[idx] - piv).T).T + piv
            Nn[idx] = (R @ restN[idx].T).T
        frames.append((P, Nn))
        names.append('claw%d' % step)
        tips = [P[idx][P[idx][:, 0].argmax()] for idx, _ in js]
        print('   +%4.1f deg  tip z  %+6.1f / %+6.1f  (gap %.1f)'
              % (deg, tips[0][2], tips[1][2], abs(tips[0][2] - tips[1][2])))

    src = open(path, 'rb').read()
    out = md3w.add_frames(src, frames, names)
    open(path, 'wb').write(out)
    m2 = read_md3(path)
    print('   %s: %d -> %d frames' % (os.path.basename(path), m['nframes'], m2['nframes']))
    return m['nframes']


def main():
    first = None
    for a in ARMS:
        p = '%s/models/weapons/mech/%s' % (ROOT, a)
        print(a)
        n = run(p)
        if n is not None:
            first = n if first is None else first
    if first is not None:
        print()
        print('new frames start at model frame %d; bind %d sprite frames from there'
              % (first, CLOSE_STEPS))


if __name__ == '__main__':
    main()
