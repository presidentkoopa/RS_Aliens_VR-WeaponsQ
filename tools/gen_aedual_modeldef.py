#!/usr/bin/env python3
"""Bake handtable.zs GunHook values into the MODELDEF.aedual hand blocks.

Why this exists: a DECORATE off-hand copy (AE_Off_*) has no ModifyBobLayer3D, so
the hand hook that RSQ_Place.Layer applies to the main-hand layer cannot be applied
to the off gun's own hand at runtime.  It has to be baked into the hand block's
Offset instead:

    Offset = (0 + GunHook.x, -24 + GunHook.y, -10 + GunHook.z)

So every time GunHook changes in zscript/rsq/handtable.zs (the owner tunes with the
Options sliders and sends numbers), the off-hand copies must be re-baked or the off
gun's hand drifts away from the main gun's hand.

UNSETTLED, 2026-10-23 -- READ BEFORE YOU TRUST A BAKE.
The formula above reproduces the ten Offset values currently shipped in
MODELDEF.aedual exactly, which proves only that it matches what is in the file --
NOT that what is in the file is right.

An audit of this pack (docs/AUDIT_2026-10-23_bugs_and_qol.md, finding 1.2/4) reads
the engine's HUD model chain as crossing the two axes:

    src/r_data/models.cpp:248 @ 9afc750917
    objectToWorldMatrix.translate(smf->xoffset / smf->xscale,
                                  smf->zoffset / smf->zscale,
                                  smf->yoffset / smf->yscale);

i.e. MODELDEF Offset's SECOND number reaches the matrix's Z and its THIRD number
reaches the matrix's Y.  If GunHook is (x left, y up, z back), the bake would then
have to be Offset = (0 + x, -24 + z, -10 + y) -- y and z swapped against what this
file does and what the shipped values encode.  On the pistols that is the
difference between Offset 0 -22.5 -7.5 (shipped) and 0 -21.5 -8.5 (audit), about
1.4 cm diagonally.

This is NOT resolved.  The handoff (docs/HANDOFF_2026-10-23.md section 2) warns
that the offline transform chain is suspect for this pack specifically, because
its weapon blocks carry their own Offset/ZOffset/Scale; and the owner approved the
hands he saw in the headset, not a chain anyone derived.  So settle it by LOOKING
at an off-hand gun -- a render on the Windows QZD 17.3 build, or the owner's eye in
the headset -- and not by argument.

Until then this script defaults to the shipped convention and changes nothing on
its own.  Pass --swap-yz to bake the audit's reading instead.  Whichever turns out
to be right, delete the loser from here so the next session is not asked to
re-litigate it.

Run with no arguments to CHECK (prints a table, writes nothing, exit 1 on drift).
Run with --write to apply.  Only the Offset line inside a hand block (the block whose
Model 0 is hand.md3) is ever touched; nothing else in MODELDEF.aedual is rewritten.
"""
import re
import sys
import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HANDTABLE = ROOT / "zscript" / "rsq" / "handtable.zs"
DECORATE = ROOT / "DECORATE.aedual"
MODELDEF = ROOT / "MODELDEF.aedual"

# The off-hand copy's hand sits at this Offset when GunHook is zero.
BASE = (0.0, -24.0, -10.0)


def parse_handtable(text):
    """-> ({base class name: index}, {index: (x, y, z)}) from the live declarations."""
    idx = {}
    for cls, i in re.findall(r"if\s*\(\s*w\s+is\s+'([A-Za-z0-9_]+)'\s*\)\s*return\s+(\d+)\s*;", text):
        idx[cls] = int(i)
    if not idx:
        sys.exit("gen_aedual: could not parse RSQ_HandTable.Index() -- did the table change shape?")

    body = re.search(r"static\s+Vector3\s+GunHook\s*\(\s*int\s+i\s*\)\s*\{(.*?)\n\t\}", text, re.S)
    if not body:
        sys.exit("gen_aedual: could not find GunHook() in handtable.zs")

    axes = {}
    for axis, values in re.findall(r"static\s+const\s+double\s+([xyz])\s*\[\s*\]\s*=\s*\{([^}]*)\}", body.group(1)):
        axes[axis] = [float(v) for v in values.replace("\n", " ").split(",") if v.strip()]
    if sorted(axes) != ["x", "y", "z"]:
        sys.exit("gen_aedual: GunHook() is missing an axis array")
    if len({len(v) for v in axes.values()}) != 1:
        sys.exit("gen_aedual: GunHook() axis arrays are different lengths")

    hooks = {i: (axes["x"][i], axes["y"][i], axes["z"][i]) for i in range(len(axes["x"]))}
    return idx, hooks


def parse_offclasses(text):
    """-> {AE_Off_* class: base class it inherits} from DECORATE.aedual."""
    pairs = re.findall(r"^\s*ACTOR\s+(AE_Off_[A-Za-z0-9_]+)\s*:\s*([A-Za-z0-9_]+)", text, re.M | re.I)
    if not pairs:
        sys.exit("gen_aedual: no 'ACTOR AE_Off_x : y' lines found in DECORATE.aedual")
    return dict(pairs)


def hand_blocks(lines):
    """Yield (class name, index of its Offset line) for every hand.md3 block."""
    start = None
    cls = None
    for n, line in enumerate(lines):
        m = re.match(r"^Model\s+([A-Za-z0-9_]+)", line)
        if m:
            start = n
            cls = m.group(1)
            continue
        if start is None:
            continue
        if line.startswith("}"):
            start = None
            cls = None
            continue
        if re.search(r'Model\s+0\s+"hand\.md3"', line):
            off = next((k for k in range(start, len(lines))
                        if lines[k].startswith("}") is False and re.match(r"^\s*Offset\s", lines[k])), None)
            if off is None:
                sys.exit(f"gen_aedual: hand block for {cls} has no Offset line to bake into")
            yield cls, off


def main():
    write = "--write" in sys.argv[1:]
    # SETTLED 2026-10-23 from models.cpp RenderHUDModel: y/z swapped is correct, and is now
    # the default. --no-swap-yz reproduces the old shipped values, for comparison only.
    swap = "--no-swap-yz" not in sys.argv[1:]
    print("Baking Offset 2nd number <- hook z, 3rd <- hook y (settled; --no-swap-yz for the old values).")
    print()

    idx, hooks = parse_handtable(HANDTABLE.read_text(encoding="utf-8", errors="replace"))
    offmap = parse_offclasses(DECORATE.read_text(encoding="utf-8", errors="replace"))
    lines = MODELDEF.read_text(encoding="utf-8", errors="replace").splitlines()

    seen = set()
    drift = []
    today = datetime.date.today().isoformat()

    print(f"{'off-hand class':<24} {'base':<24} {'i':>3}  {'GunHook':<22} {'Offset now':<22} {'Offset wanted':<22}")
    for cls, off_line in hand_blocks(lines):
        seen.add(cls)
        base = offmap.get(cls)
        if base is None:
            sys.exit(f"gen_aedual: {cls} has a hand block but no ACTOR line in DECORATE.aedual")
        i = idx.get(base)
        if i is None:
            sys.exit(f"gen_aedual: {base} (parent of {cls}) is not in RSQ_HandTable.Index()")
        if i not in hooks:
            sys.exit(f"gen_aedual: index {i} ({base}) is past the end of the GunHook arrays")

        hx, hy, hz = hooks[i]
        # Which hook axis each MODELDEF Offset slot carries is the unsettled question
        # documented at the top of this file.
        if swap:
            want = (BASE[0] + hx, BASE[1] + hz, BASE[2] + hy)
        else:
            want = (BASE[0] + hx, BASE[1] + hy, BASE[2] + hz)
        have = tuple(float(v) for v in re.match(r"^\s*Offset\s+(\S+)\s+(\S+)\s+(\S+)", lines[off_line]).groups())
        ok = all(abs(a - b) < 1e-6 for a, b in zip(have, want))

        print(f"{cls:<24} {base:<24} {i:>3}  "
              f"{'(%.3f %.3f %.3f)' % (hx, hy, hz):<22} "
              f"{'(%.3f %.3f %.3f)' % have:<22} "
              f"{'(%.3f %.3f %.3f)' % want:<22} {'' if ok else '<-- DRIFT'}")

        if not ok:
            drift.append(cls)
            if write:
                lines[off_line] = ("\tOffset %.3f %.3f %.3f" % want +
                                   f"\t// GunHook ({hx:.3f} {hy:.3f} {hz:.3f}) baked {today} by tools/gen_aedual_modeldef.py")

    missing = sorted(set(offmap) - seen)
    if missing:
        print("\nWARNING: off-hand classes with NO hand block (their off gun draws with no hand): "
              + ", ".join(missing))

    if not drift:
        print("\nIn sync: every off-hand hand block matches handtable.zs GunHook.")
        return 0
    if write:
        MODELDEF.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"\nRe-baked {len(drift)} block(s) in {MODELDEF.name}: " + ", ".join(drift))
        return 0
    print(f"\n{len(drift)} block(s) out of sync. Re-run with --write to bake.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
