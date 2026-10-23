"""Measure how each hand-table gun's model frames move the gun off its ready frame.

For every (sprite, frame) key of the gun's MODELDEF block, fit the rigid move of the
gun body from the ready mesh frame to that key's mesh frame (trimmed Kabsch over all
vertices, so a bolt / magazine / trigger moving on its own does not count), in the
controller frame of hudrender.to_local (cm: x right, y up, z back).

usage: kick_measure.py bd22|vplus  -> prints a summary, writes kick_<set>.json
"""
import sys, os, re, json, math, struct
import numpy as np

S = 'C:/Users/Command/Desktop/Quest_Weapons_Kit/kit'
W = S + '/team/hands_work'
sys.path.insert(0, S + '/tool/hands')
WS = 1.02            # vr_weaponScale default (hw_vrmodes.cpp)


def modeldef_blocks(text):
    text = re.sub(r'//[^\n]*', '', text)
    out = []
    for m in re.finditer(r'\bModel\s+(\S+)\s*\{(.*?)\}', text, re.S | re.I):
        cls, b = m.group(1), m.group(2)
        pm = re.search(r'\bPath\s+"([^"]+)"', b, re.I)
        mm = re.search(r'\bModel\s+0\s+"([^"]+)"', b, re.I)
        if not pm or not mm:
            continue
        blk = dict(cls=cls, path=pm.group(1).rstrip('/'), mesh=mm.group(1), scale=(1.0, 1.0, 1.0), off=[0.0, 0.0, 0.0], keys={},
                   nointerp=bool(re.search(r'\bNoInterpolation\b', b, re.I)))
        sm = re.search(r'\bScale\s+(\S+)\s+(\S+)\s+(\S+)', b, re.I)
        if sm:
            blk['scale'] = tuple(float(x) for x in sm.groups())
        om = re.search(r'\bOffset\s+(\S+)\s+(\S+)\s+(\S+)', b, re.I)
        if om:
            blk['off'] = [float(x) for x in om.groups()]
        zm = re.search(r'\bZOffset\s+(\S+)', b, re.I)
        if zm:
            blk['off'][2] = float(zm.group(1))
        for fm in re.finditer(r'FrameIndex\s+(\S+)\s+(\S+)\s+(\d+)\s+(\d+)', b, re.I):
            if int(fm.group(3)) == 0:
                for ch in fm.group(2).upper():
                    blk['keys'][(fm.group(1).upper(), ch)] = int(fm.group(4))
        out.append(blk)
    return out


def md3_frames(path):
    d = open(path, 'rb').read()
    nfr, ntag, nsurf, nskin, ofr, otag, osurf, oeof = struct.unpack_from('<8i', d, 76)
    per = []
    off = osurf
    for s in range(nsurf):
        flags, snfr, nsh, nv, nt, otri, osh, ost, oxyz, oend = struct.unpack_from('<10i', d, off + 68)
        xyz = np.frombuffer(d, dtype='<i2', count=snfr * nv * 4, offset=off + oxyz).reshape(snfr, nv, 4)[:, :, :3].astype(np.float64) / 64.0
        per.append(xyz)
        off += oend
    return lambda f: np.concatenate([x[f] for x in per], 0), nfr


def iqm_frames(path):
    import gunview
    return lambda f: np.concatenate([v for t, v in gunview.load_iqm(path, f)], 0), 10 ** 6


def to_ctrl(v, blk):
    """mesh coords -> controller frame (cm, x right, y up, z back), hudrender.to_local without the shared shift"""
    xs, ys, zs = blk['scale']
    xo, yo, zo = blk['off']
    r = np.stack([v[:, 0], v[:, 2], v[:, 1]], 1) * WS
    p = np.stack([r[:, 2], r[:, 1], -r[:, 0]], 1)
    return p * np.array([xs, zs, ys]) + np.array([xo, zo, yo])


def kabsch(a, b):
    ca, cb = a.mean(0), b.mean(0)
    H = (a - ca).T @ (b - cb)
    U, s, Vt = np.linalg.svd(H)
    d = np.sign(np.linalg.det(Vt.T @ U.T))
    R = Vt.T @ np.diag([1, 1, d]) @ U.T
    return R, cb - R @ ca


def rigid(a, b, keep=0.6, rounds=5):
    idx = np.arange(len(a))
    for _ in range(rounds):
        R, t = kabsch(a[idx], b[idx])
        res = np.linalg.norm(a @ R.T + t - b, axis=1)
        idx = np.argsort(res)[:max(10, int(len(a) * keep))]
    R, t = kabsch(a[idx], b[idx])
    res = np.linalg.norm(a[idx] @ R.T + t - b[idx], axis=1)
    return R, t, float(res.mean())


def angle_of(R):
    return math.degrees(math.acos(max(-1.0, min(1.0, (np.trace(R) - 1) / 2))))


def handtable_order(text):
    return re.findall(r"if \(w is '([^']+)'\)\s*return (\d+);", text)


def sets(which):
    import zipfile
    if which == 'bd22':
        md = open(W + '/v8/MODELDEF.bd.txt', encoding='latin-1').read()
        root = W + '/v8'
        import guns
        ready = {c: (s, f) for c, s, f in guns.READY}
        ht = open(S + '/tool/vrmelee/zscript/rsq/handtable.zs').read()
        return modeldef_blocks(md), root, ready, handtable_order(ht)
    U = '/mnt/user-data/uploads/1.0b_Weapons_VanillaVRPlus_v1.2'
    md = ''
    for p in (U + '/Modeldef.Doom.Weapons.def', U + '/FILTER/DOOM/modeldef.weapons.txt', U + '/FILTER/DOOM/Modeldef.Rifle',
              U + '/FILTER/DOOM/Modeldef.Revolver', U + '/FILTER/DOOM/Modeldef.shotty'):
        md += open(p, encoding='latin-1').read() + '\n'
    sys.path.insert(0, S + '/vplus')
    import vplus
    ready = {c: tuple(v[4].split()) for c, v in vplus.ITEMS.items()}
    ht = zipfile.ZipFile(S + '/team/vplus/RS_VanillaVRPlus_VR_v9_sharedhands.pk3').read('zscript/rsq/handtable.zs').decode()
    return modeldef_blocks(md), U, ready, handtable_order(ht)


def find_file(root, rel):
    p = os.path.join(root, rel)
    if os.path.exists(p):
        return p
    # case-insensitive walk (V+ paths differ in case from the files)
    cur = root
    for part in rel.replace('\\', '/').split('/'):
        if not part:
            continue
        hit = [x for x in os.listdir(cur) if x.lower() == part.lower()] if os.path.isdir(cur) else []
        if not hit:
            return None
        cur = os.path.join(cur, hit[0])
    return cur


def main(which):
    blocks, root, ready, order = sets(which)
    out = {}
    for cls, idx in order:
        if cls not in ready:
            print(cls, 'no ready key'); continue
        rk = ready[cls]
        blk = next((b for b in blocks if b['cls'].lower() == cls.lower() and rk in b['keys']), None)
        if not blk:
            print(cls, 'no block with', rk); continue
        path = find_file(root, blk['path'] + '/' + blk['mesh'])
        if not path:
            print(cls, 'mesh missing', blk['path'], blk['mesh']); continue
        get, nfr = (iqm_frames if path.lower().endswith('.iqm') else md3_frames)(path)
        rf = blk['keys'][rk]
        a = to_ctrl(get(rf), blk)
        per_frame = {}
        for key, f in blk['keys'].items():
            if f in per_frame or f >= nfr:
                continue
            b = to_ctrl(get(f), blk)
            R, t, err = rigid(a, b)
            per_frame[f] = dict(R=R.tolist(), t=t.tolist(), ang=angle_of(R), err=err,
                                move=float(np.linalg.norm(a.mean(0) @ R.T + t - a.mean(0))))
        out[cls] = dict(index=int(idx), ready=list(rk), ready_frame=rf, scale=list(blk['scale']), off=blk['off'],
                        keys={'%s %s' % k: f for k, f in blk['keys'].items() if f in per_frame}, frames={str(k): v for k, v in per_frame.items()})
        big = sorted(per_frame.items(), key=lambda kv: -max(kv[1]['move'], kv[1]['ang'] / 2))[:4]
        print('%-24s ready %s %s -> %d   scale %s off %s   %d keys / %d frames' % (cls, rk[0], rk[1], rf, blk['scale'], blk['off'], len(blk['keys']), len(per_frame)))
        for f, v in big:
            print('      frame %3d  move %6.2f cm  turn %6.2f deg  fit err %.2f' % (f, v['move'], v['ang'], v['err']))
    json.dump(out, open(W + '/kick_%s.json' % which, 'w'), indent=1)


if __name__ == '__main__':
    main(sys.argv[1])
