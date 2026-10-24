"""TEST ONLY: write a copy of the Eradication mapset with its MAPINFO episode block closed.

THE DEFECT, in _A02_ERADICATION_MAPSET_2_0.wad:MAPINFO:

    16| episode e1m1
    17| {
    18|     name = "Aliens: LV-426"
    19|
    20|  map MAP01 lookup "HUSTR_1"        <- still inside the episode block
    21| {
    ...
    26| }                                  <- this closes the EPISODE, not the map

`episode e1m1` is never closed, so GZDoom reads `map`, `MAP01`, `lookup`, `HUSTR_1`, `{`,
`next`, `secretnext`, `sky1` and `cluster` as properties of the episode -- the nine "Unknown
property ... found in episode definition" errors. Two consequences beyond the noise: MAP01
loses its own next / secretnext / sky1 / cluster (it falls back to defaultmap), and the parser
is left out of step for that stretch of the file.

The fix is one brace after the episode's name. This writes a patched COPY into the scratch
directory and never touches the owner's wad. If the mapset is ever fixed upstream, this
becomes a no-op: it checks for the defect before changing anything.
"""
import os
import struct
import sys


def lumps(data):
    magic, n, ofs = struct.unpack_from('<4sii', data, 0)
    if magic not in (b'PWAD', b'IWAD'):
        raise SystemExit('not a wad: %r' % magic)
    out = []
    for i in range(n):
        fp, sz, nm = struct.unpack_from('<ii8s', data, ofs + i * 16)
        out.append([nm, data[fp:fp + sz]])
    return magic, out


def fix_mapinfo(text):
    lines = text.split('\n')
    for i, ln in enumerate(lines):
        if ln.strip().lower().startswith('episode ') and i + 2 < len(lines):
            # walk to the end of this block's properties; if we meet a `map` line before any
            # closing brace, the episode was never closed and the brace belongs before it
            depth = 0
            for j in range(i + 1, min(i + 12, len(lines))):
                s = lines[j].strip()
                if s == '{':
                    depth += 1
                    continue
                if s.startswith('}'):
                    break
                if depth and s.lower().startswith('map ') and '{' not in s:
                    lines.insert(j, '}')
                    return '\n'.join(lines), 'closed the "%s" block before line %d'\
                        % (lines[i].strip(), j + 1)
    return text, None


def build(src, dst):
    data = open(src, 'rb').read()
    magic, ls = lumps(data)
    note = None
    for L in ls:
        if L[0].rstrip(b'\0').upper() in (b'MAPINFO', b'ZMAPINFO'):
            t = L[1].decode('utf-8', 'replace')
            new, note = fix_mapinfo(t)
            if note:
                L[1] = new.encode('utf-8')
            break
    if not note:
        return src, 'already correct, using the original'

    body = b''
    dirent = []
    pos = 12
    for nm, d in ls:
        dirent.append(struct.pack('<ii8s', pos, len(d), nm))
        body += d
        pos += len(d)
    with open(dst, 'wb') as f:
        f.write(struct.pack('<4sii', magic, len(ls), 12 + len(body)))
        f.write(body)
        f.write(b''.join(dirent))
    return dst, note


if __name__ == '__main__':
    out, why = build(sys.argv[1], sys.argv[2])
    print('%s  (%s)' % (out, why))
