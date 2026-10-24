# tools/rtest — the headless behaviour harness

The Windows port of the kit's `kit/kit/team/integ/rtest`. It runs the pack in the real playsim
with fake VR hands and a scripted off hand, so the reload is **exercised** rather than merely
compiled. `tools/check.sh` proves the scripts compile and the pack loads; it cannot see a VM
abort and it cannot see a reload that never finishes. This can.

```bash
cd tools/rtest
python -B run.py pistol 400 "10:god; show_messages 0; rsq_reload 1; aet_empty 1; aet_gun M4A3Pistol_3D" "40:rsrtest_script 1" "2400:echo END"
```

A window appears: 320x240, windowed, silent, and it quits itself. `xvfb-run` is what kept this
invisible on Linux and Windows has no equivalent. Each run gets a scratch `-config`, so the
owner's ini is never read or written.

| file | what |
|---|---|
| `run.py` | builds the overlay, patches the mapset, drives the run |
| `fakehands.zs` | stands in for `zscript/rsvr/vrhand.zs`; same eight signatures |
| `rsr_testdriver.zs` | the kit's scripted off hand, verbatim, minus its break-open branch |
| `driver.zs` | `aet_gun` picks the gun, `aet_empty` empties its magazine |
| `fixmapset.py` | a COPY of the mapset with its MAPINFO episode block closed |

## WHICH INPUT GRABS — read this before believing a run

`rsr_grab_with` decides what takes a magazine, and the kit's driver was written for BD22,
whose default was the **grip**. This pack's default is the **trigger**:

| `rsr_grab_with` | what grabs | what the driver must drive |
|---|---|---|
| **0 (this pack's default)** | the off-hand trigger, as a usercmd button mask (`rsr_grab_buttons`, default `BT_OFFHANDATTACK`) | `RSR_TestDriver.trig`, which `fakehands.Buttons()` ORs into the usercmd |
| 1 | the off-hand grip key | the `rsr_grip` net event, which `RSR_TestDriver` sends |
| 2 | the Use key, intercepted for the reload's duration | the Use key |

`vreload.zs:1083` drops every `rsr_grip` event unless `GrabWith(p) == 1`, so a run that scripts
the grip while the cvar sits at 0 is driving an input nothing is listening to. That was the
first thing this harness appeared to "find", and it was the harness being wrong, not the pack.

## Coverage, in guns

This set has FOUR guns -- pistol, shotgun, pulse rifle, smartgun -- and the Merc / Synth /
Yutani entries are reskins of those same four meshes, not separate guns. Count classes and you
get twelve reloading entries; count guns and you get four. An earlier version of this file said
"all six reloading guns", which was six entries on ONE path and read as if six were the whole
roster. It was not.

| gun | path | proved |
|---|---|---|
| pistol | RSR magazine | YES -- all four variants, 8/8 phases |
| pulse rifle | RSR magazine | YES -- both variants, 8/8 phases |
| shotgun | RSP pump | YES -- 8 shells into the tube, reserve 50 -> 42 |
| smartgun | RSR magazine, no handle | not yet |

The smartgun and the flamers are `HasHandle == false`: a magazine but no slide or bolt to work,
so they are excluded from the magazine driver's path everywhere in the pack and are not covered
by `suite.py`.

## WHICH INPUT GRABS, again -- it caught me twice

The magazine driver (`rsr_testdriver.zs`) can use either, via `rsrtest_script` (1 = grip,
7 = trigger). **The pump driver (`pump_test.zs`) only ever uses the GRIP** -- it writes
`RSR_TestDriver.grip` and never touches `trig`; `rsp_test_trigger` is a hook it sets for the
runtime, not its own input mode. So a pump run needs `rsr_grab_with 1` or the grip it presses
is dropped and the tube never fills. With it, the shotgun loads eight shells.

## Where the runs got to, 2026-10-23

Both on `M4A3Pistol_3D`, emptied, `rsq_reload 1`, `rsrtest_script 1`.

- **`rsr_grab_with 0`** (default): `IDLE -> EMPTY -> DROP`, a magazine actor spawned on the
  floor at a measured position with sprite `RSPW`, `nomag 1`, the off hand driven out to the
  belt at 56 cm and the grip pressed. Then it stops: `held` stays 0 and the phase never
  reaches `CARRY`. Expected, given the table above — the grip is not what grabs here.
- **`rsr_grab_with 1`** (the grip, which the driver does script): the phase never leaves
  `IDLE` at all, for 315 tics. That is the open question. It is NOT the same stall as above,
  and it is not a load failure — the pack loads and the gun is in hand.

**So the next step is to script the TRIGGER on the default path** (`RSR_TestDriver.trig`,
`rsrtest_script 7` is the kit's "trigger everywhere" variant) and see whether a full
`DROP -> CARRY -> INSERT -> SEATED -> DONE` completes. Until one run does that end to end,
this harness has proved the path runs, not that the reload works.
