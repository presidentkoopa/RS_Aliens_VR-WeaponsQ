#!/bin/bash
# mkpk3.sh <srcdir> <out.pk3>
out="$(realpath -m "$2")"; rm -f "$out"; (cd "$1" && zip -q -r -X "$out" .) && ls -la "$out"
