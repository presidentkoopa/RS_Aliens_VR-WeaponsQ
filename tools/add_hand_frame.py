"""Append a hand pose from BD22 1.92's hand.md3 into this pack's hand.md3.

Why this is a copy and not new art: both files are the SAME mesh -- one surface `fist1`,
1021 verts, 1693 tris, from Ermac / Force Unleashed / Rusted Legacy (MIT, see
models/rsq/LICENSE_RustedLegacy_MIT.txt, which ships in both packs). BD22 keeps 44 poses of
it; this pack was cut down to 16 and lost some. Nothing is authored here: one frame's vertex
block is moved across verbatim.

What it is for: BD22's RSQ_HandTable has TWO gun-hand letters, GunOne(i) and GunTwo(i), and
picks between them by whether the support hand is on the gun -- a thumb tucked out of the cup
on a pistol. This pack has a single GunPose, and it is already set to the letter whose frame
is Ermac 19, which is BD22's TWO-handed pose. So the pistols are permanently two-handed and
the ONE-handed pose is the one missing: BD22's RQGS A, its frame index 2, Ermac frame 6.

MD3 layout, for whoever reads this next:
    header 108 bytes, then nframes x 56-byte frame headers at ofs_frames,
    then tags (none here), then the surfaces at ofs_surf.
    A surface is its own 108-byte header, then shaders / triangles / st, then the
    vertex block at ofs_xyz: nframes x nverts x 8 bytes (3 x int16 xyz + 1 x uint16
    packed normal). Everything but the frame headers and that vertex block is per-mesh,
    not per-frame, so appending a pose touches exactly two regions and four offsets.

    python -I tools/add_hand_frame.py
"""
import io
import os
import struct
import sys
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
OURS = os.path.join(ROOT, 'models', 'rsq', 'hand.md3')
BD22 = r"C:\Users\Command\Desktop\BD2Weapons192\BD22_VR-Reloaded_1.92.pk3"
# BD22's one-handed pistol pose and ITS trigger frames. All three are needed: the pack only
# falls back to the bare grip letter when a gun has no trigger pose solved, and every pistol
# has one -- so without 10 and 11 the new grip would never be seen.
#   2  RQGS A  the one-handed grip      (Ermac hand.md3 frame 6)
#  10  RQGT A  index finger on the trigger
#  11  RQGU A  trigger squeezed
DONOR_FRAMES = [2, 10, 11]

FRAME_REC = 56
VERT_REC = 8


def read_md3(b):
    nframes, ntags, nsurf = struct.unpack('<3i', b[76:88])
    ofs_frames, ofs_tags, ofs_surf, ofs_eof = struct.unpack('<4i', b[92:108])
    o = ofs_surf
    name = b[o + 4:o + 68].split(b'\0')[0].decode('latin-1')
    snframes, nshader, nverts, ntris = struct.unpack('<4i', b[o + 72:o + 88])
    ofs_tri, ofs_sh, ofs_st, ofs_xyz, ofs_end = struct.unpack('<5i', b[o + 88:o + 108])
    return dict(nframes=nframes, nsurf=nsurf, ofs_frames=ofs_frames, ofs_surf=ofs_surf,
                ofs_eof=ofs_eof, sname=name, snframes=snframes, nverts=nverts, ntris=ntris,
                ofs_xyz=ofs_xyz, ofs_end=ofs_end)


def main():
    ours = open(OURS, 'rb').read()
    theirs = zipfile.ZipFile(BD22).read('models/rsq/hand.md3')
    a, b = read_md3(ours), read_md3(theirs)

    for k in ('nsurf', 'sname', 'nverts', 'ntris', 'ofs_xyz'):
        if a[k] != b[k]:
            print('REFUSING: %s differs (%r vs %r) -- these are not the same mesh' % (k, a[k], b[k]))
            return 1
    if a['nsurf'] != 1:
        print('REFUSING: this tool assumes the one surface hand.md3 has')
        return 1
    print('same mesh: surface %r, %d verts, %d tris. ours %d frames, BD22 %d frames'
          % (a['sname'], a['nverts'], a['ntris'], a['nframes'], b['nframes']))
    for f in DONOR_FRAMES:
        if f >= b['nframes']:
            print('REFUSING: donor has no frame %d' % f)
            return 1

    vblock = a['nverts'] * VERT_REC

    fh, verts = b'', b''
    for f in DONOR_FRAMES:
        h = theirs[b['ofs_frames'] + f * FRAME_REC:b['ofs_frames'] + (f + 1) * FRAME_REC]
        vs = b['ofs_surf'] + b['ofs_xyz'] + f * vblock
        v = theirs[vs:vs + vblock]
        if len(h) != FRAME_REC or len(v) != vblock:
            print('REFUSING: short read from the donor at frame %d' % f)
            return 1
        fh += h
        verts += v
    nnew = len(DONOR_FRAMES)

    # rebuild: header | frames + 1 | surface header | ... | xyz + 1 block | tail
    sstart = a['ofs_surf']
    frames = ours[a['ofs_frames']:sstart] + fh
    surf = bytearray(ours[sstart:a['ofs_eof']])
    xyz_at = a['ofs_xyz']
    xyz_end = xyz_at + a['nframes'] * vblock
    surf[xyz_end:xyz_end] = verts                       # append the pose's vertices

    struct.pack_into('<i', surf, 72, a['snframes'] + nnew)  # surface nframes
    struct.pack_into('<i', surf, 104, a['ofs_end'] + nnew * vblock)

    out = bytearray(ours[:a['ofs_frames']] + frames + bytes(surf))
    struct.pack_into('<i', out, 76, a['nframes'] + nnew)  # header nframes
    struct.pack_into('<i', out, 100, sstart + nnew * FRAME_REC)  # ofs_surf
    struct.pack_into('<i', out, 104, len(out))            # ofs_eof

    open(OURS, 'wb').write(bytes(out))

    # PROVE the pose survived the write byte for byte. tools/md3.py's decoder once swapped
    # the packed normal's two bytes and the bug lived for weeks, so a write is not trusted
    # until the bytes are compared against the donor.
    back = open(OURS, 'rb').read()
    c = read_md3(back)
    got = back[c['ofs_surf'] + c['ofs_xyz'] + a['nframes'] * vblock:][:nnew * vblock]
    print('wrote frames %s (were BD22 %s). frames %d -> %d, %d bytes'
          % (list(range(a['nframes'], a['nframes'] + nnew)), DONOR_FRAMES,
             a['nframes'], c['nframes'], len(back)))
    print('vertex block byte-identical to the donor: %s' % (got == verts))
    return 0 if got == verts else 1


if __name__ == '__main__':
    sys.exit(main())
