"""Find the pulse rifle's ammo-counter window on the m41a mesh (by its texture UV box) and write
a tiny quad md3 lying on it. Usage: md3_counter.py in.md3 surfname u0 v0 u1 v1 out.md3"""
import struct, sys, numpy as np
src, sname, u0, v0, u1, v1, out = sys.argv[1], sys.argv[2], *map(float, sys.argv[3:7]), sys.argv[7]
d = open(src, 'rb').read()
flags, nF, nT, nS, nSk, ofF, ofT, ofS, ofEnd = struct.unpack_from('<9i', d, 72)
o = ofS
for s in range(nS):
    name = d[o+4:o+68].split(b'\0')[0].decode()
    sflags, snF, snSh, snV, snTri, ofTri, ofSh, ofST, ofXYZ, ofSEnd = struct.unpack_from('<10i', d, o+68)
    if name == sname:
        tris = np.frombuffer(d[o+ofTri:o+ofTri+snTri*12], dtype='<i4').reshape(-1, 3)
        st = np.frombuffer(d[o+ofST:o+ofST+snV*8], dtype='<f4').reshape(-1, 2)
        xyz = np.frombuffer(d[o+ofXYZ:o+ofXYZ+snV*8], dtype='<i2').reshape(-1, 4)[:, :3] / 64.0
        break
    o += ofSEnd
inbox = (st[:, 0] >= u0) & (st[:, 0] <= u1) & (st[:, 1] >= v0) & (st[:, 1] <= v1)
sel = [t for t in tris if inbox[t].all()]
vid = sorted(set(int(i) for t in sel for i in t))
P = xyz[vid]; UV = st[vid]
print('tris', len(sel), 'verts', len(vid)); print('xyz min', P.min(0), 'max', P.max(0)); print('uv min', UV.min(0), 'max', UV.max(0))
# plane
c = P.mean(0); u, sv, vt = np.linalg.svd(P - c); n = vt[2]
# the display's u and v directions from the mesh UVs (least squares)
A = np.c_[UV - UV.mean(0), np.ones(len(UV))]
coef = np.linalg.lstsq(A, P - c, rcond=None)[0]   # rows: dP/du, dP/dv
du, dv = coef[0], coef[1]
print('normal', n, 'dP/du', du, 'dP/dv', dv)
# quad corners at the uv box
corners = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
Q = np.array([c + du * (uu - UV.mean(0)[0]) + dv * (vv - UV.mean(0)[1]) for uu, vv in corners])
# nudge off the surface along the normal, toward the outside (pick the side facing away from the gun's centre line y=0)
side = n if np.dot(n, [0, c[1], 0]) > 0 else -n
Q = Q + side * 0.15
print('quad', Q)
# write md3: 1 frame, 1 surface, 4 verts, 2 tris, uv 0..1 (flip: md3 v grows down like the png)
def pad(b, n): return b + b'\0' * (n - len(b))
verts = Q; nrm = side
tri = np.array([[0, 1, 2], [0, 2, 3]], dtype='<i4')
# winding: make the triangle normal face 'side'
if np.dot(np.cross(verts[1]-verts[0], verts[2]-verts[0]), side) < 0: tri = tri[:, ::-1].copy()
uvq = np.array([[1, 0], [0, 0], [0, 1], [1, 1]], dtype="<f4")  # u mirrored: the gun block has Scale -1.1 (mirrored width), which turns the quad inside out
# normal encoding (lat/lng)
lng = int(np.degrees(np.arctan2(nrm[1], nrm[0])) * 255 / 360) & 255
lat = int(np.degrees(np.arccos(np.clip(nrm[2], -1, 1))) * 255 / 360) & 255
xyzb = b''.join(struct.pack('<hhhBB', *[int(round(v * 64)) for v in vv], lat, lng) for vv in verts)
shader = pad(b'counter.png', 64) + struct.pack('<i', 0)
sh = struct.pack('<4s', b'IDP3') + pad(b'counter', 64) + struct.pack('<10i', 0, 1, 1, 4, 2, 0, 0, 0, 0, 0)
ofTri = len(sh); ofSh = ofTri + 24; ofST = ofSh + 68; ofXYZ = ofST + 32; ofEnd = ofXYZ + 32
sh = struct.pack('<4s', b'IDP3') + pad(b'counter', 64) + struct.pack('<10i', 0, 1, 1, 4, 2, ofTri, ofSh, ofST, ofXYZ, ofEnd)
surf = sh + tri.tobytes() + shader + uvq.tobytes() + xyzb
mn, mx = verts.min(0), verts.max(0)
frame = struct.pack('<3f3f3ff', *mn, *mx, *((mn+mx)/2), float(np.linalg.norm(mx-mn)/2)) + pad(b'counter', 16)
hdr_len = 108
hdr = struct.pack('<4si', b'IDP3', 15) + pad(b'counter', 64) + struct.pack('<9i', 0, 1, 0, 1, 0, hdr_len, hdr_len + 56, hdr_len + 56, hdr_len + 56 + len(surf))
open(out, 'wb').write(hdr + frame + surf)
print('wrote', out)
