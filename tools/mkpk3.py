import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
SKIP_DIRS = {'.git', 'docs', 'tools'}
SKIP_FILES = {'.gitignore'}
n = 0
if os.path.exists(out):
    os.remove(out)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(src):
        rel = os.path.relpath(root, src).replace(os.sep, '/')
        if rel == '.':
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            rel = ''
        for f in sorted(files):
            if rel == '' and f in SKIP_FILES:
                continue
            arc = (rel + '/' + f) if rel else f
            z.write(os.path.join(root, f), arc)
            n += 1
print(str(n) + ' files -> ' + out + '  (' + str(os.path.getsize(out)) + ' bytes)')
