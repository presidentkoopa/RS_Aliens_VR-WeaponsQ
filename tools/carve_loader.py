"""Carve the Power Loader's held mesh into the pieces the two-armed design needs.

`models/weapons/mech/mechloader.md3` has exactly three surfaces and 21 frames:
    MechCover     18 verts   the roof grate
    MechArms.001  3590 verts BOTH arms as ONE surface, reach 228, span +/-122
    MechGuard.001 1245 verts the cab cage, 70 x 61 x 104 cm about the origin

Two arms therefore needs the arm surface split. It splits cleanly: 1813 verts at y > 0, 1777 at
y < 0 and NOTHING on the centreline, so there is no shoulder yoke crossing over -- that was the
one risk in the design that could have reordered the whole plan.

Writes, keeping every frame and the original coordinates so nothing has to be re-placed:
    loader_arm_r.md3    the y < 0 half
    loader_arm_l.md3    the y > 0 half
    loader_cage.md3     MechGuard.001 alone, for the cage over the head (step 8)

Lossless: triangles, texture coordinates and the packed vertex/normal shorts are copied
byte-for-byte and only re-indexed. Frame headers are left alone -- their bounds are now larger
than the carved mesh needs, which only ever means less culling, never a wrong draw.

Run from this directory:  python -I carve_loader.py
"""
import os
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, 'C:/Users/Command/Desktop/up your ass')

from md3label import read_raw, pad        # the owner's own lossless reader

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
MECH = os.path.join(ROOT, 'models', 'weapons', 'mech')


def surf_xyz(s):
    raw = np.frombuffer(s['xyz'], dtype='<i2').reshape(s['nframes'], s['nverts'], 4)
    return raw[:, :, :3].astype(np.float64) / 64.0


def surf_tris(s):
    return np.frombuffer(s['tris'], dtype='<i4').reshape(s['ntris'], 3)


def subset(s, keep_tris):
    """A new surface dict holding only keep_tris, with vertices re-indexed."""
    tris = surf_tris(s)[keep_tris]
    used = sorted(set(int(v) for t in tris for v in t))
    remap = {old: new for new, old in enumerate(used)}
    new_tris = np.array([[remap[int(v)] for v in t] for t in tris], dtype='<i4')

    st = np.frombuffer(s['st'], dtype='<f4').reshape(s['nverts'], 2)[used]
    xyz = np.frombuffer(s['xyz'], dtype='<i2').reshape(s['nframes'], s['nverts'], 4)[:, used, :]

    out = dict(s)
    out['tris'] = new_tris.tobytes()
    out['st'] = st.astype('<f4').tobytes()
    out['xyz'] = xyz.astype('<i2').tobytes()
    out['nverts'] = len(used)
    out['ntris'] = len(tris)
    return out


def write_md3(src, surfs, path, name):
    """Write an MD3 with the given surfaces, carrying src's frames and dropping its tags."""
    nframes = src['nframes']
    frames = b''.join(bytes(f) for f in src['frames'])

    surf_blobs = []
    for s in surfs:
        hdr_len = 108
        ofs_tris = hdr_len
        ofs_sh = ofs_tris + len(s['tris'])
        ofs_st = ofs_sh + len(s['shaders'])
        ofs_xyz = ofs_st + len(s['st'])
        ofs_end = ofs_xyz + len(s['xyz'])
        blob = struct.pack('<4s64s10i', b'IDP3', pad(s['name'], 64), s['flags'],
                           s['nframes'], s['nsh'], s['nverts'], s['ntris'],
                           ofs_tris, ofs_sh, ofs_st, ofs_xyz, ofs_end)
        blob += s['tris'] + s['shaders'] + s['st'] + s['xyz']
        assert len(blob) == ofs_end, (len(blob), ofs_end)
        surf_blobs.append(blob)

    hdr_size = 108
    ofs_frames = hdr_size
    ofs_tags = ofs_frames + len(frames)
    ofs_surf = ofs_tags                       # no tags
    body = b''.join(surf_blobs)
    ofs_eof = ofs_surf + len(body)

    hdr = struct.pack('<4si64s9i', b'IDP3', 15, pad(name, 64), src['flags'],
                      nframes, 0, len(surfs), 0, ofs_frames, ofs_tags, ofs_surf, ofs_eof)
    with open(path, 'wb') as fh:
        fh.write(hdr + frames + body)
    return ofs_eof


def main():
    src = read_raw(os.path.join(MECH, 'mechloader.md3'))
    by = {s['name']: s for s in src['surfs']}
    print('mechloader.md3  frames=%d  surfaces=%s' % (src['nframes'], list(by)))

    arms = by['MechArms.001']
    xyz0 = surf_xyz(arms)[0]
    tris = surf_tris(arms)

    # classify each TRIANGLE, and prove none straddles the centreline
    ys = xyz0[:, 1]
    side = np.sign(ys)
    straddle = 0
    right, left = [], []
    for i, t in enumerate(tris):
        s3 = side[t]
        if s3.min() < 0 and s3.max() > 0:
            straddle += 1
            (right if s3.sum() < 0 else left).append(i)
        elif s3.max() > 0:
            left.append(i)
        else:
            right.append(i)
    print('  arm triangles: %d right (y<0), %d left (y>0), %d straddling the centreline'
          % (len(right), len(left), straddle))

    for tag, keep in (('r', right), ('l', left)):
        s = subset(arms, keep)
        s['name'] = 'loader_arm_' + tag
        out = os.path.join(MECH, 'loader_arm_%s.md3' % tag)
        n = write_md3(src, [s], out, 'loader_arm_' + tag)
        print('  wrote %-22s verts=%-5d tris=%-5d %d bytes'
              % (os.path.basename(out), s['nverts'], s['ntris'], n))

    # FIXED 2026-10-23: the cage used to be MechGuard.001 ALONE, so the cab had a frame and
    # no roof -- you looked up and saw the sky. MechCover is the 48 x 30 cm grate panel above
    # the head and it belongs in the same file. Surface 0 is the frame, surface 1 the grate;
    # modeldef.loader.txt skins them in that order.
    cage = dict(by['MechGuard.001'])
    cage['name'] = 'loader_cage'
    cover = dict(by['MechCover'])
    cover['name'] = 'loader_cover'
    out = os.path.join(MECH, 'loader_cage.md3')
    n = write_md3(src, [cage, cover], out, 'loader_cage')
    print('  wrote %-22s frame=%d verts, roof=%d verts, %d bytes'
          % (os.path.basename(out), cage['nverts'], cover['nverts'], n))


if __name__ == '__main__':
    main()
