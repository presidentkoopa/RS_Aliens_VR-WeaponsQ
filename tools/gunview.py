"""Orthographic measuring views of HUD models in the weapon controller's frame,
the way QZD places them (models.cpp RenderHUDModel; hudrender.to_local).

Controller frame used for every number printed or drawn here, in centimetres:
  F forward along the controller, L to the player's left, U up.
(hudrender's local frame is x right, y up, z back: F = -z, L = -x, U = y.)

Views: 'side' looks at the gun's right side (F to the right, U up),
'bottom' looks up from below (F to the right, L up), 'front' looks back
down the barrel (L to the left... drawn with -L to the right, U up).
"""
import struct, math, sys
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, 'C:/Users/Command/Desktop/Quest_Weapons_Kit/kit/melee')
import hudrender


def load_md3(path, frame):
    out = []
    for tris, xyz in hudrender.load(path):
        out.append((tris, xyz[frame]))
    return out


def _quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def _trs(t, q, s):
    m = np.eye(4)
    m[:3, :3] = _quat_mat(q / np.linalg.norm(q)) @ np.diag(s)
    m[:3, 3] = t
    return m


def load_iqm(path, frame, skip_meshes=()):
    d = open(path, 'rb').read()
    assert d[:16] == b'INTERQUAKEMODEL\0'
    h = struct.unpack_from('<27I', d, 16)
    (ver, fsize, flags, ntext, otext, nmesh, omesh, nva, nvert, ova, ntri, otri, oadj, njoint, ojoint,
     npose, opose, nanim, oanim, nframe, nchan, oframe, obounds, ncom, ocom, next_, oext) = h
    arrays = {}
    for i in range(nva):
        typ, fl, fmt, size, off = struct.unpack_from('<5I', d, ova + i * 20)
        dt = {0: 'i1', 1: 'u1', 2: '<i2', 3: '<u2', 4: '<i4', 5: '<u4', 7: '<f4', 8: '<f8'}[fmt]
        arrays[typ] = np.frombuffer(d, dtype=dt, count=nvert * size, offset=off).reshape(nvert, size).astype(np.float64)
    pos = arrays[0]
    tris = np.frombuffer(d, dtype='<u4', count=ntri * 3, offset=otri).reshape(ntri, 3)
    joints = []
    for i in range(njoint):
        name, parent = struct.unpack_from('<Ii', d, ojoint + i * 48)
        vals = struct.unpack_from('<10f', d, ojoint + i * 48 + 8)
        joints.append((parent, np.array(vals[0:3]), np.array(vals[3:7]), np.array(vals[7:10])))
    base = []
    for parent, t, q, s in joints:
        m = _trs(t, q, s)
        base.append(base[parent] @ m if parent >= 0 else m)
    invbase = [np.linalg.inv(m) for m in base]
    poses = []
    for i in range(npose):
        parent, mask = struct.unpack_from('<iI', d, opose + i * 88)
        off = np.array(struct.unpack_from('<10f', d, opose + i * 88 + 8))
        sc = np.array(struct.unpack_from('<10f', d, opose + i * 88 + 48))
        poses.append((parent, mask, off, sc))
    frame = max(0, min(frame, nframe - 1))
    p = oframe + frame * nchan * 2
    glob = []
    for j, (parent, mask, off, sc) in enumerate(poses):
        ch = off.copy()
        for c in range(10):
            if mask & (1 << c):
                ch[c] += struct.unpack_from('<H', d, p)[0] * sc[c]
                p += 2
        m = _trs(ch[0:3], ch[3:7], ch[7:10])
        glob.append(glob[parent] @ m if parent >= 0 else m)
    skin = [glob[j] @ invbase[j] for j in range(len(glob))]
    idx = arrays[4].astype(int)
    w = arrays[5] / 255.0
    P = np.hstack([pos, np.ones((nvert, 1))])
    out_pos = np.zeros((nvert, 3))
    for k in range(4):
        M = np.stack([skin[i] for i in idx[:, k]])
        out_pos += w[:, k:k + 1] * np.einsum('nij,nj->ni', M, P)[:, :3]
    out = []
    for i in range(nmesh):
        name, mat, fv, nv, ft, nt = struct.unpack_from('<6I', d, omesh + i * 24)
        if i in skip_meshes:
            continue
        out.append((tris[ft:ft + nt].astype(np.int64), out_pos))
    return out


def item_mesh(it):
    if it['path'].lower().endswith('.iqm'):
        return load_iqm(it['path'], it['frame'], it.get('skip', (0,)))
    return load_md3(it['path'], it['frame'])


def to_fl(v_local):
    """hudrender local (x right, y up, z back; m) -> (F, L, U) cm"""
    return np.stack([-v_local[:, 2], -v_local[:, 0], v_local[:, 1]], 1) * 100.0


def triangles(items):
    out = []
    for it in items:
        col = np.array(it.get('color', (200, 200, 190)), float)
        for tris, raw in item_mesh(it):
            v = to_fl(hudrender.to_local(raw, it))
            out.append((v[tris[:, 0]], v[tris[:, 1]], v[tris[:, 2]], col))
    return out


VIEWS = {
    # (horizontal axis, vertical axis, depth axis toward the viewer), as (index, sign)
    'side': ((0, 1), (2, 1), (1, -1)),      # F right, U up, seen from the right (-L)
    'bottom': ((0, 1), (1, 1), (2, -1)),    # F right, L up, seen from below
    'front': ((1, -1), (2, 1), (0, 1)),     # -L right (player's right), U up, seen from the muzzle
    'top': ((0, 1), (1, -1), (2, 1)),       # F right, -L up (right side down), seen from above
}


def view(items, out, kind='side', rng=None, px=8, marks=(), title=''):
    """rng: (h0, h1, v0, v1) in cm; px pixels per cm; marks: [(F, L, U, label, colour)]"""
    tr = triangles(items)
    (hi, hs), (vi, vs), (di, ds) = VIEWS[kind]
    if rng is None:
        allv = np.concatenate([np.concatenate([a, b, c]) for a, b, c, _ in tr])
        hv = allv[:, hi] * hs
        vv = allv[:, vi] * vs
        rng = (math.floor(hv.min() / 5) * 5 - 5, math.ceil(hv.max() / 5) * 5 + 5,
               math.floor(vv.min() / 5) * 5 - 5, math.ceil(vv.max() / 5) * 5 + 5)
    h0, h1, v0, v1 = rng
    W, H = int((h1 - h0) * px), int((v1 - v0) * px) + 18
    img = Image.new('RGB', (W, H), (60, 62, 78))
    dr = ImageDraw.Draw(img)

    def P(h, v):
        return ((h - h0) * px, H - (v - v0) * px)

    # grid
    for g in range(int(h0), int(h1) + 1):
        if g % 5 == 0:
            x = P(g, 0)[0]
            dr.line([(x, 18), (x, H)], fill=(95, 98, 120) if g % 10 else (120, 124, 150))
            if g % 10 == 0:
                dr.text((x + 2, 20), str(g), fill=(170, 170, 190))
    for g in range(int(v0), int(v1) + 1):
        if g % 5 == 0:
            y = P(0, g)[1]
            dr.line([(0, y), (W, y)], fill=(95, 98, 120) if g % 10 else (120, 124, 150))
            if g % 10 == 0:
                dr.text((2, y - 12), str(g), fill=(170, 170, 190))
    L = np.array([0.4, 0.5, 0.75])
    L /= np.linalg.norm(L)
    polys = []
    for a, b, c, col in tr:
        n = np.cross(b - a, c - a)
        n /= (np.linalg.norm(n, axis=1)[:, None] + 1e-12)
        sh = np.abs(n @ L) * 0.7 + 0.3
        depth = (a[:, di] + b[:, di] + c[:, di]) / 3 * ds
        for i in range(len(a)):
            polys.append((depth[i], [P(p[hi] * hs, p[vi] * vs) for p in (a[i], b[i], c[i])], tuple(int(x) for x in col * sh[i])))
    polys.sort(key=lambda t: t[0])
    for _, pts, c in polys:
        dr.polygon(pts, fill=c)
    o = P(0, 0)
    dr.ellipse((o[0] - 4, o[1] - 4, o[0] + 4, o[1] + 4), outline=(255, 255, 0), width=2)
    for f, l, u, lab, col in marks:
        q = (f, l, u)
        x, y = P(q[hi] * hs, q[vi] * vs)
        dr.ellipse((x - 5, y - 5, x + 5, y + 5), outline=col, width=2)
        dr.text((x + 6, y - 6), lab, fill=col)
    dr.rectangle((0, 0, W, 17), fill=(30, 30, 40))
    dr.text((4, 3), '%s  [%s] cm: F right, %s up' % (title, kind, {'side': 'U', 'bottom': 'L', 'front': 'U', 'top': '-L'}[kind]), fill=(255, 255, 255))
    img.save(out)
    return rng
