# pad short rows of GZDoom language.* CSV files to the header width (see build.sh DATA FIX)
import sys, csv, io
for p in [q for q in sys.argv[1:] if not q.endswith(".def")]:
    raw = open(p, 'rb').read()
    try: txt = raw.decode('utf-8')
    except UnicodeDecodeError: txt = raw.decode('latin-1')
    rows = list(csv.reader(io.StringIO(txt)))
    if not rows: continue
    w = len(rows[0]); fixed = 0
    for r in rows:
        if 0 < len(r) < w:
            r.extend([''] * (w - len(r))); fixed += 1
    out = io.StringIO(); csv.writer(out, lineterminator='\n').writerows(rows)
    open(p, 'w', encoding='utf-8', newline='').write(out.getvalue())
    print(p, 'padded rows:', fixed)
