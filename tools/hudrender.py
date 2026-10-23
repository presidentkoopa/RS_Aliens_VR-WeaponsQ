"""Shaded render of HUD models placed in the controller's local frame, the way
QZD draws them (models.cpp RenderHUDModel). local: x right, y up, z back; metres.

items: list of dicts {path, frame, scale[3], off[3] (x, y, z=ZOffset), hook[3],
       rot[3] (hook rotation: yaw about y, pitch about x, roll about z, degrees),
       color[3]}
"""
import sys, math, json, struct
import numpy as np
from PIL import Image, ImageDraw

def load(path):
    d = open(path, 'rb').read()
    nfr, ntag, nsurf, nskin, ofr, otag, osurf, oeof = struct.unpack_from('<8i', d, 76)
    surfs = []; off = osurf
    for s in range(nsurf):
        flags, snfr, nsh, nv, nt, otri, osh, ost, oxyz, oend = struct.unpack_from('<10i', d, off + 68)
        tris = np.frombuffer(d, dtype='<i4', count=nt * 3, offset=off + otri).reshape(nt, 3)
        xyz = np.frombuffer(d, dtype='<i2', count=snfr * nv * 4, offset=off + oxyz).reshape(snfr, nv, 4)[:, :, :3].astype(np.float64) / 64.0
        surfs.append((tris, xyz))
        off += oend
    return surfs

def rot_y(a):
    c, s = math.cos(math.radians(a)), math.sin(math.radians(a)); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
def rot_x(a):
    c, s = math.cos(math.radians(a)), math.sin(math.radians(a)); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
def rot_z(a):
    c, s = math.cos(math.radians(a)), math.sin(math.radians(a)); return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])

def to_local(v, it, ws=1.02):
    xs, ys, zs = it.get('scale', (1, 1, 1))
    xo, yo, zo = it.get('off', (0, 0, 0))
    hook = np.array(it.get('hook', (0, 0, 0)), float)
    ry, rx, rz = it.get('rot', (0, 0, 0))
    r = np.stack([v[:, 0], v[:, 2], v[:, 1]], 1) * ws
    p = np.stack([r[:, 2], r[:, 1], -r[:, 0]], 1)          # jDoom Ry(90)
    p = p + hook
    R = rot_y(ry) @ rot_x(rx) @ rot_z(rz)                   # hook rotation (pivot 0)
    p = p @ R.T
    p = p * np.array([xs, zs, ys]) + np.array([xo, zo, yo])
    return 0.01 * (p + np.array([0, 5, 30]))

def render(items, out, eye=(0.10, 0.22, 0.32), look=(0.0, -0.02, -0.15), W=640, H=480, fov=70, title=''):
    eye = np.array(eye, float); look = np.array(look, float)
    fwd = look - eye; fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, [0, 1, 0]); right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    f = (W / 2) / math.tan(math.radians(fov / 2))
    polys = []
    L = np.array([-0.4, 0.8, 0.5]); L /= np.linalg.norm(L)
    for it in items:
        col = np.array(it.get('color', (200, 200, 190)), float)
        if it['path'].lower().endswith('.iqm'):
            import gunview
            meshes = gunview.load_iqm(it['path'], it['frame'], it.get('skip', (0,)))
        else:
            meshes = [(tris, xyz[it['frame']]) for tris, xyz in load(it['path'])]
        for tris, raw in meshes:
            v = to_local(raw, it)
            a, b, c = v[tris[:, 0]], v[tris[:, 1]], v[tris[:, 2]]
            n = np.cross(b - a, c - a); n /= (np.linalg.norm(n, axis=1)[:, None] + 1e-12)
            sh = np.abs(n @ L) * 0.75 + 0.25
            for P in (a, b, c):
                pass
            def proj(P):
                q = P - eye
                z = q @ fwd
                x = q @ right; y = q @ up
                z = np.maximum(z, 1e-3)
                return np.stack([W / 2 + x / z * f, H / 2 - y / z * f], 1), z
            pa, za = proj(a); pb, zb = proj(b); pc, zc = proj(c)
            depth = (za + zb + zc) / 3
            for i in range(len(tris)):
                polys.append((depth[i], (tuple(pa[i]), tuple(pb[i]), tuple(pc[i])), tuple(int(x) for x in col * sh[i])))
    polys.sort(key=lambda t: -t[0])
    img = Image.new('RGB', (W, H), (70, 72, 90)); dr = ImageDraw.Draw(img)
    for d, pts, c in polys:
        dr.polygon(pts, fill=c)
    # controller origin marker
    q = -eye; z = q @ fwd
    if z > 0:
        x = W / 2 + (q @ right) / z * f; y = H / 2 - (q @ up) / z * f
        dr.ellipse((x - 4, y - 4, x + 4, y + 4), outline=(255, 255, 0))
        # forward axis
        q2 = np.array([0, 0, -0.1]) - eye; z2 = q2 @ fwd
        x2 = W / 2 + (q2 @ right) / z2 * f; y2 = H / 2 - (q2 @ up) / z2 * f
        dr.line((x, y, x2, y2), fill=(255, 255, 0), width=2)
    dr.text((5, 5), title, fill=(255, 255, 0))
    img.save(out)
    return out

if __name__ == '__main__':
    items = json.loads(open(sys.argv[2]).read()) if sys.argv[2].endswith('.json') else json.loads(sys.argv[2])
    kw = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
    print(render(items, sys.argv[1], **kw))
