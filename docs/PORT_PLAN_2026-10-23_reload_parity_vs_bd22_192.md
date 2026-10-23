# Port plan: reload and hand parity against BD22 VR-Reloaded 1.92

Target: `E:\DOOMWork\RS_Aliens_Q` (RS Aliens VR Weapons, Quest).
Reference: `C:\Users\Command\Desktop\BD2Weapons192\BD22_VR-Reloaded_1.92.pk3`.
Spec: `C:\Users\Command\Desktop\Quest_Weapons_Kit` (its `docs/` and `measurements/` only — see
"Provenance" below).
Engine: stock QuestZDoom 17.3 = `9afc750` (GZDoom 4.14.3). **No engine change anywhere in this
plan.** Engine claims below are cited with `git show 9afc750:<path>` against
`E:\DOOMWork\QZD17-engine` (branch `qzd173-pinned`, HEAD `670d19eba6`), not the working tree,
because that tree is not stock (`docs/QZD17_TARGET.md`).

Written 2026-10-23. Report only: nothing in the pack was edited, nothing was built, nothing was
launched.

## Provenance of the inputs

BD22 1.92 was made with the Quest Weapons Kit's documented method, and the owner's verdict is
that its reloading is smooth. The kit's `docs/` and `measurements/` are therefore a **validated
method**, and this plan leans on them and cites them.

`Quest_Weapons_Kit\USERADDEDTOOLS\`, `01_USERADDEDTOOLS.txt` and `kit_top_tools.zip` were **not**
used to make BD22. Nothing in this plan depends on any of them, and none is cited as method.

The kit's `measurements/` hold BD22 and V+ numbers only (`reload_survey.json` covers BD22 Rifle,
BrutalPistol, BrutalSMG, MP40, AssaultShotgun, Sniper, Shot_Gun, Revolver, SSG, Rocket_Launcher,
RailGun, Plasma_Gun, GrenadeLauncher and five V+ guns — no Aliens gun). So the kit is cited for
**method, frames, units and default tolerances**, never for an Aliens value.
`measurements/rsr_weapons.json` is only a map of Linux scratch paths to BD22 `.dec` files and is
of no use here.

The pack's own `zscript/rsq/handtable.zs` header comments are known to contradict its live
arrays. Every claim below comes from a declaration or a mesh, read directly.

---

## 1. ORDERED PLAN

Ordered by (owner's stated priority x certainty) / effort. Each step is independently testable.
"Parse gate" means the `docs/QZD17_TARGET.md` procedure on
`C:\Users\Command\Desktop\qzdoom-17-3-Windows-64bit\qzdoom.exe` — `+vr_mode 0`, a scratch
`-config`, pass is the line `script parsing took`, and the warning count must equal the previous
pack's. **Per the owner's hard rule, a `-norun` parse is not a boot test: the staged pk3 gets an
in-level boot on the exe it will run on before it is installed.** I did not run anything.

### Step 1 — "Grab ammo with" is wired to the JUMP button

**Files:** `MENUDEF.ae` (lines 25-30), `CVARINFO.rsr`.

`MENUDEF.ae`'s `OptionValue "AE_GrabWith"` offers `4, "Use key"` and `67108868, "Either"` for
`rsr_grab_buttons`. In the pinned engine, `git show 9afc750:wadsrc/static/zscript/constants.zs`
line 835-836 gives `BT_USE = 1<<1` (= 2) and `BT_JUMP = 1<<2` (= 4). So "Use key" binds the
reload grab to **jump**, and "Either" is off-trigger OR jump.

**Change:** remove both rows (leaving "Off hand trigger" as the only value, which is 1.92's
shipped default), or restore them properly as Step 2.

**What the owner would feel:** picking anything but the first option no longer makes jumping grab
a magazine. On the default setting nothing changes.

**Verify:** parse gate; then in the menu, read the cvar back.

**Risk:** none. Two lines of a menu lump.

### Step 2 — Match 1.92's grab input rule exactly

**Files:** `zscript/rsr/vreload.zs`, `CVARINFO.rsr`, `MENUDEF.ae`.

The owner's judgement is that 1.92's reloading is smooth. As 1.92 ships, the reload grab is the
**off trigger and nothing else**: `RSR.GrabWith()` reads `rsr_grab_with` (default 0 = trigger),
`GrabMask()` returns the trigger mask only when that is 0, `NetworkProcess` ignores the
`rsr_grip` event unless `rsr_grab_with == 1`, and `InputProcess` sets
`eaten[k] = busy && RSR.GrabWith(me) == 1 && rsr_eat_grip`.

The pack dropped all three gates. `RSR.GrabWith` and `RSR.IsUseKey` do not exist in
`zscript/rsr/vreload.zs`; `NetworkProcess` accepts every `rsr_grip` event; `Grip()` returns
`trig || grip`; and `InputProcess` sets `eaten[k] = busy && rsr_eat_grip` with no choice gate. So
in the pack the off **grip** is always a second grab button (subject to `GripCanGrab`, which is
intact and correct), and during any reload or shell feed the grip key is swallowed outright.

`docs/RELOAD_ON_QUEST.md` states the rule the reference is built to: "Stock two-hand steadying
untouched", the trigger grabs anywhere, "the off **grip** grabs only where its press *cannot*
start the engine's steadying". 1.92 honours that by not using the grip at all unless the player
asks for it.

**Change:** port `rsr_grab_with` (a `user int`, default 0) and restore the three gates. Port
`IsUseKey` / `useEaten` / the `rsr_use` netevent with it if the "Use key" option is wanted back
(1.92 intercepts the Use *key* so it does not also open doors — simply putting `BT_USE` in the
usercmd mask gives a grab **and** a door). The pack's `RSP_Handler.Busy` / `Feedable` terms stay;
`RSB_Handler` and `RSK_M203Handler` stay out (Section 4).

**What the owner would feel:** one grab button, as in 1.92. No accidental grab or release from a
grip press, and the grip is never swallowed, so steadying behaves exactly as stock throughout a
reload.

**Verify:** parse gate, then in-headset: with the default, press the off grip 60 cm from the gun
mid-reload and confirm nothing is grabbed; press it near the gun and confirm the engine steadies.

**Risk:** low. The field (`netUse`) and the gates are a straight transcription from 1.92.
`rsr_eat_grip` already exists in `CVARINFO.rsr`.

### Step 3 — The pistols' support hand, by closeness with hysteresis

**Files:** `zscript/rsq/hands.zs` (one bool on `RSQ_Hands`, the `hold` decision in
`RSQ_HandHandler.WorldTick`).

The pack shows the support hand only while the engine is two-hand steadying:
`SetLayer(p, RSQ_Layers.SUPPORT, gunOwner, (steady && s != "") ? "Sup" .. s : "Hidden")`, with
`bool steady = (p.WeaponState & WF_TWOHANDSTABILIZED) != 0`.

1.92's `A_RSQ_Layers` has, in addition, a dated owner fix (2026-10-16) for exactly the guns the
Aliens set is full of:

> the engine's steadying aims the gun along the line from the gun hand to the off hand, which is
> right for a forend and wrong for a two-hand pistol grip, where the hands are together. So on a
> cup-support gun the support hand shows by CLOSENESS instead

1.92: if not steadied and `RSQ_HandTable.Support(i) == "A"`, then
`hold = gap < (s.holding ? 18.0 : 13.0)` — in at 13 cm, out at 18, latched in `RSQ_State.holding`
so it cannot flicker.

**The data is already in the pack.** `RSQ_HandTable.SupportPose` is
`{ "", "", "B","A","A","B","B","","C","A","B","","A","B","","B","C" }`: letter `A` sits on indices
3 (M4A3Pistol_3D), 4 (MercPistol_3D), 9 (SynthPistol_3D) and 12 (YutaniPistol_3D) — the four
pistols, exactly the cup-support marker 1.92 keys on. `SupA: RQSP A -1` exists in the pack's
`RSQ_GunSide` states. **No new mesh, no new MODELDEF block, no handtable number.**

1.92's `hold` also carries three vetoes the pack's `steady` lacks:
`s.kind == 0 && carry == 0 && rsr == ""`. `zscript/rsq/handler.zs` in 1.92 says in its own
comment that `kind` and `carry` "are always 0", so only the reload veto matters. It exists for a
dated reason (1.12): "grabbing a shell with grip near the gun also two-hands it, and that hid the
hand and the shell it was holding." The engine half of that is real and stock:
`git show 9afc750:src/rendering/hwrenderer/scene/hw_weapon.cpp` contains
`if (weaponStabilised && psp->GetCaller() == player->OffhandWeapon) continue;` — while steadying,
every layer owned by `RSQ_Hands` is skipped, which is the free hand (2200) **and** the magazine in
it (2201).

**Change:** add `bool holding;` to `RSQ_Hands` (do **not** port `zscript/rsq/handler.zs`: the pack
contains no reference to `RSQ.`, `RSQ_Handler` or `RSQ_State` at all, so a whole extra
EventHandler would be dead weight for one bool). Compute `hold` as 1.92 does: steadied, or the
closeness rule for `SupportPose(i) == "A"`, and in both cases only when `RSR_Handler.FreeHand(mo)`
and `RSP_Handler.FreeHand(mo)` are both `""`.

**What the owner would feel:** bring the off hand to a pistol's grip and the second hand appears
cupped under it, without pressing grip and without the engine re-aiming the gun along the
hand-to-hand line. It stops appearing mid-reload, so the magazine in the hand is never replaced
by a support hand.

**Verify:** headset only. The rig can render the pistol with `Sup A` forced, but the 13/18 cm
hysteresis is a feel test.

**Risk:** low, and contained: the change only ever *adds* a reason to show a layer that already
exists, and the reload veto only ever hides it.

### Step 4 — Drive the launcher pump with the hand

**Files:** `MODELDEF.rsr` (two new blocks), `zscript/rsr/rsr_guns.zs` or a small new table,
`zscript/rsq/pumpgl.zs`, `zscript/rsq/hands.zs` (`RSQ_Place.Layer` routing),
`actors/weapons/rifle.txt`.

Handoff open item 3 is "launcher pump part does not move with the hand". The cause is in the code,
not in the geometry: `zscript/rsq/pumpgl.zs` creates **no psprite layer at all**. It reads the off
hand's position, counts a stroke, and on completion jumps the weapon to its own canned animation
(`p.SetPsprite(PSP_WEAPON, w.FindState('AE_GLPump'))`). There is nothing for `RSQ_Place.Layer` to
place.

Everything needed is already present and measured:

- **The surface exists and is separable.** `models/weapons/rifle/m41a.md3` has 5 surfaces:
  `[0] m41a_trigger`, `[1] m41a_pump` (448 verts, 428 tris), `[2] m41a_body`, `[3] m41a_bolt`,
  `[4] m41a_magazine`. `MODELDEF.rsr`'s PulseRifle blocks already address them as
  `SurfaceSkin 0 0..4`, so surface 1 can be hidden or isolated with `rsr_clear.png` exactly the
  way `MODELDEF.rsrpump` isolates `m37a2_pump` for the shotgun. **No mesh edit.**
- **The mesh already animates it, and by how much.** Measuring `m41a_pump`'s centroid relative to
  `m41a_body` per frame: frames 9-12 move it purely along -x (0.000 on y and z) by
  -7.099, **-14.201**, -10.518, -3.682 md3 units, back to 0 at frame 13.
  `actors/weapons/rifle.txt` `AE_GLPump` is `PULS J 2` then `PULS KLMN 2`, and
  `modeldef.rifle.txt` maps `PULS J..N` to md3 frames **9, 10, 11, 12, 13**. That is the authored
  pump stroke, and the pack currently plays it as a canned 10-tic animation.
- **The mesh-to-controller mapping is known and reproducible.** `MEASUREMENTS.md` gives the chain
  (`rgeo.py`, `vr_weaponScale = 1.02`, F forward / L left / U up, cm). It reproduces the pack's
  own shipped values exactly, on two independent guns:
  `m37a2_pump` centroid x 36.589 x 1.1 x 1.02 = **41.053** against `RSP_Guns.Grab(1)` =
  `41.050`; `m41a_magazine` centroid (7.932, -0.001, -12.119) maps to
  (8.900, -0.001, -17.597) against `RSR_Guns.MagCentre(2)` = `(8.900, -0.001, -17.597)` using
  `U = md3_z x Scale x 1.02 + (ZOffset + 5)` (rifle `ZOffset -9`; the shotgun's `ZOffset -7`
  gives the shotgun's own -2.0 constant). So the launcher pump's point and travel can be
  **computed**, not tuned — the memory rule "measure it, do not ask the owner" applies.
- **The pump hook falls out of the scale.** `RSP_Guns.PumpHook(1)` is `(0, 0, 0.909)` = 1/1.1 =
  1/`Scale`, for a pump whose `Pull` is `(-1,0,0)`; 1.92's `RSM_Geo.FwdHook()` is `(0,0,-1.0)` on
  a gun whose MODELDEF `Scale` is `-1 1 1`, i.e. 1/1. The rifle's `Scale` is also `-1.1 1.1 1.1`,
  so its hook is the shotgun's.

Two bugs fall out of the same reading, both in the pack's own code:

- **`ae_glpump_travel` defaults to 6.0 cm** against a mesh stroke of
  14.201 x 1.1 x 1.02 = **~15.9 cm**. Drive the part off a 6 cm hand stroke and the part reaches
  the end of its travel after about a third of the hand's movement, or lags two thirds behind it,
  depending on which end is normalised. The travel has to match the mesh.
- **The rack sound plays twice.** `pumpgl.zs` plays `"PULSREL3"` when the stroke reaches back, and
  `AE_GLPump` opens with `PULS J 2 A_PlaySound("PULSREL3",CHAN_AUTO)`.

**Change:** treat it as a pump, the way the shotgun already is.
1. `MODELDEF.rsr`: add a PulseRifle_3D block with surface 1 clear (the rifle **without** its
   pump), keyed to a new `SprGun` letter; and an `RSR_GunParts` block showing **only** surface 1,
   keyed to a sprite of its own. Give the launcher pump its own sprite pair rather than extending
   `RSLP`: `RSR.SetPart` already reserves `SprPart` frames 0/1/2 for WELLMAG / HANDLE / BOLT, and
   Step 5 wants the next `SprGun` letter.
2. `pumpgl.zs`: keep the existing grab test (its grab-at-`grab`, release-at-`grab * 2.0`
   hysteresis is sound), add a continuous `pull`/`pullPrev` pair as `RSP_State` has, set
   `ae_glpump_travel`'s default to the measured stroke, show the two layers while held, and stop
   jumping to `AE_GLPump` in VR.
3. `hands.zs`: route the two new layers in `RSQ_Place.Layer` (a `Places`/`Place` pair beside the
   existing `RSP_Handler` and `RSR_Handler` branches), interpolating `pullPrev -> pull` by
   `ticfrac`, and add the support-hand ride (`RSP_Handler.SupportShift`'s equivalent) so the hand
   on the pump moves with it.
4. `rifle.txt`: leave `AE_GLPump` in place for the non-VR path only; drop the duplicate
   `A_PlaySound` or drop the sound in `pumpgl.zs`.

**What the owner would feel:** the underbarrel pump slides under his hand as he works it, at the
distance his hand actually moved, and the rack sounds once.

**Verify:** the pump point and travel are checkable on the rig with a side render
(`tools/rig/runae.sh`, `qz_rhand`/`qz_lhand`), which is also how the shotgun's pump was proved;
`printinv` before and after confirms `ae_glpump_cost` rounds became one `GrenadeAmmo`. Parse gate
for the MODELDEF (an unknown class or sprite in MODELDEF is fatal at startup, a missing frame is
silent — `docs/POSTMORTEM.md` §7).

**Risk:** medium, and all of it in MODELDEF. Mitigation: the shotgun's working blocks in
`MODELDEF.rsrpump` are the template, and the surface indices are confirmed above.

### Step 5 — Slide / bolt lock

**Files:** `zscript/rsr/vreload.zs`, `MODELDEF.rsr` (six new blocks), `MENUDEF.ae` (nothing
needed).

1.92's 1.13 + 1.23 behaviour, absent from the pack: a gun fired dry locks its slide back and
**stays** back through the magazine change until the hand racks it; taking a locked slide does not
close it; a short tug (`LOCK_TUG = 1.5` cm) racks it with the sound, and letting go then sends it
home. Missing from `zscript/rsr/vreload.zs`: the const `LOCK_TUG`, the fields `slideLock`,
`lockedGrab`, `lockGun`, the `lockedGrab` branches in `CHARGE`, `PULL` and `RELEASED`, the
slide-lock block at the top of `Draw()`, and the two `slideLock` branches in
`RSR_Handler.Place` (`case RSR.HANDLE` and `case RSR.BOLT`).

Everything the code reads already exists in the pack: `RSR_Guns.MagAmmo`, `NoMag`,
`ReadySprites`, `RSR.IsReadyFrame`, `RSR_Guns.BoltRatio`, `HandleHook`, `Travel`.

**Which guns, and the one thing that must be built.** `RSR_Guns.HasHandle` is true for indices
1 (M4A3Pistol), 2 (PulseRifle), 5 (MercPistol), 6 (SynthPistol), 7 (YutaniPistol),
8 (YutaniRifle), and `BoltRatio` is **0.000 for all ten guns** — so every one of them takes
1.92's simpler `BoltRatio(i) <= 0` path ("A slide (no separate bolt) is drawn all the way back
meanwhile"), and the separate-bolt-carrier branches are dead code here.

`MODELDEF.rsr` currently gives each `SprGun` sprite frame `A` (magazine surface clear = the gun
without its magazine) and frame `B` (handle surface clear = the gun without its slide). The `B`
frames exist for exactly `RSPM, RSLM, RSMM, RSYM, RSNM, RSRM` = indices 1, 2, 5, 6, 7, 8, which
matches `HasHandle` exactly. 1.92 also needs a **frame 2** (both clear: no slide *and* no
magazine) — BD22's `MODELDEF.rsr` has three letters `A B C` on precisely its four slide-lock guns
(`RQAM`, `RQBM`, `RQPM`, `RQRM`). The pack has no third letter on any sprite. So this step needs
**six new MODELDEF blocks**, each a copy of that gun's frame-`A` block with the handle surface
also set to `rsr_clear.png`.

**What the owner would feel:** shoot a pistol dry and the slide stays back. It stays back while
he changes the magazine, and goes home when he racks it — and taking hold of it no longer snaps
it shut before he has pulled.

**Verify:** rig render of each of the six guns on the new frame (`docs/renders/` has the existing
proof sheets); then headset for the tug. `printinv` plus the `rsr_debug` phase print confirms the
lock state transitions.

**Risk:** medium. 1.92's `Draw()` hard-codes its own gun indices
(`if ((i == 1 || i == 2 || i == 3 || i == 5) && psp)`); the Aliens index space is different and the
list is the six `HasHandle` guns. Do not copy the literal.

### Step 6 — Flick reload: gate it, and stop the player's own motion firing it

**Files:** `zscript/rsq/flick.zs`.

Two divergences from 1.92, both verified in the declarations:

- **No ready gate.** 1.92's `RSQ_Flick.Reload` is
  `if (!w || !(p.WeaponState & ready)) return;` — "The gun must be in its ready loop ... so a
  flick never cuts into firing or a reload already running." The pack's `AE_FlickHandler.Reload`
  checks only `RSR_Handler.FreeHand(p.mo) != ""`, which is `""` whenever the magazine reload is
  idle. So a flick can cut into firing, a pump cycle, or a weapon raise.
- **The test is not translation-invariant.** 1.92 reads the **barrel's elevation**
  (`asin(d.z)` of the hand's forward vector) with arm/rearm hysteresis (`REARM_DEG -15`,
  `DOWN_DEG -40`, `FLICK_DEG 45` within `FLICK_TICS 4`) — walking and turning cannot change it.
  The pack measures `now - last[i]` on `RSVR_VRHand.HandPos(mo)`, a raw world position, and never
  subtracts `mo.vel`, so the player's own movement counts as hand speed; and `d.z` is not divided
  by `pixelstretch`, so the vertical component is overstated by about 1.2x in the
  `down < speed * DOWN` test — biased toward firing.

**Change:** add the ready-state gate. Then either subtract `mo.vel` and divide `d.z` by
`pixelstretch`, or replace the velocity test with 1.92's elevation test (`RSQ_Flick` ports almost
unchanged; the pack's `AE_Flick` constants become 1.92's four).

**What the owner would feel:** no reload starting by itself when he steps off a ledge or rides a
lift, and no flick interrupting a shot.

**Risk:** low. Self-contained file, and the reference implementation is 90 lines.

### Step 7 — Re-derive the shell's orientation in the hand

> **DISPROVED BY MEASUREMENT 2026-10-23. Do not do this step.**
> The premise below -- "a copied orientation on a different mesh is the exact signature of the
> symptom" -- does not hold for this mesh. Pushed the shell surface's principal axis through
> `tools/hudrender.to_local` (the engine's own chain) and read the result:
>
> | | forward | up | elevation |
> |---|---|---|---|
> | shell at zero rotation | +1.0000 | -0.0044 | **-0.25 deg** |
> | shell at our `HandRot` (0.656, 57.6, 0.550) | +0.5395 | +0.8420 | **+57.35 deg** |
> | the `AxisInHand` we declare (0.537, -0.009, 0.844) | +0.5370 | +0.8440 | **+57.53 deg** |
>
> The drawn shell and the axis the insert test uses agree to 0.2 degrees. Our shell model
> points straight along hand-forward at zero rotation, which is the same convention BD22's
> has -- so BD22's pitch carries over correctly here and re-deriving it would change nothing.
> Whatever is 45 degrees off in the headset, it is not the disagreement claimed below. Look
> at the HAND's own orientation against the shell, or at a non-zero
> `ae_shell_yaw/pitch/roll` in the owner's ini, before touching this table.

**Files:** `zscript/rsr/rsr_pump_guns.zs`.

Handoff open item 1: the held shotgun shell is still ~45 degrees off in the headset, upright on the
rig at `HandRot` pitch 57.6.

That number is BD22's. `measurements/rsr_pump_geometry.json` gives
`BD22/Shot_Gun.hand_rot = [0.976, 57.529, 0.536]` and
`axis_in_hand = [0.5368, -0.0091, 0.8437]`. The pack's `RSP_Guns.HandRot(1)` is
`(0.656, 57.6, 0.550)` with the in-file note "pitch 25.117 -> 57.6", and `AxisInHand(1)` is
`(0.537, -0.009, 0.844)` commented "as BD22 1.92 (its HandRot pitch is 57.5 too)". A copied
orientation on a different mesh is the exact signature of the symptom.

`MEASUREMENTS.md` states the method: `hand_rot` and `axis_in_hand` are **derived** per gun from
that gun's own shell geometry and Ermac's hold (`ermac_mid`, `shell_ref`, `shell_len`), not
carried across. The Aliens shell is measurable and clean: surface `[3] shell` of
`models/weapons/shotgun/m37a2.md3`, 188 verts / 240 tris, centroid (11.207, 0.015, 4.589),
principal axis **(1.0000, 0.0017, -0.0044)** in md3 space — a pure along-the-barrel rod, against
BD22's `axis_in_hand` which is 0.54 forward / 0.84 up. The two shells do not point the same way in
the hand, so one rotation cannot serve both.

**Change:** derive `AxisInHand` and `HandRot` for indices 1 and 2 from this surface through the
`MEASUREMENTS.md` chain, rather than baking slider values. Keep `ae_shell_yaw/pitch/roll` as taste
sliders afterwards (memory rule: sliders are for taste, never for a value we failed to measure).

**What the owner would feel:** the shell sits in the fist the way a shell does, before he touches
a slider.

**Verify:** rig render of the hand holding the shell (that is how the 57.6 was checked), then
headset.

**Risk:** low. One table, two rows, and the current values are known wrong by the owner's own
report.

### Step 8 — Melee: a swept blade, a hit list, a measured reach, haptics

**Files:** `zscript/rsq/melee.zs`.

The pack's melee is 5,025 bytes against 1.92's 22,045. What 1.92's `RSVR_Hand` has and the pack's
`RSQ_MeleeHandler` does not (declaration names from `zscript/rsvr/melee.zs`):

| 1.92 | what it does | worth bringing to the Aliens knife |
|---|---|---|
| `HIST` ring + `Push` / `Sweep` / `Touches` | the blade is swept between last tic's position and this one's, and everything the segment passes through is hit | **Yes.** The pack spawns a 3-tic projectile from the hand instead, so a fast stab can pass a body between tics. This is the same class of bug `docs/RELOAD_ON_QUEST.md` records for the break-open guns: "Faster than ~1.5 m/s and the crossing fell between tics and was never seen." |
| `Clear` | per-swing hit list, so one swing cannot hit the same actor twice | **Yes.** Cheap. |
| `BladeIn` / `BladeOut` / `AxeHead` | the blade's extent taken from the mesh | **Yes** — replaces the `ae_stab_reach` slider with a measured length (memory rule again). The knife meshes are in `models/weapons/`. |
| `Buzz` | haptic on a hit | **Yes.** Handoff QoL item 4. Note that half of that item is already done: `geo.Buzz(mo)` fires at eight sites in `zscript/rsr/rsr_pump.zs` (shell seat and pump) and `Buzz(mo)` at five in `vreload.zs`. The two places with **no** haptic are `melee.zs` and `pumpgl.zs` (zero `Buzz` calls in either). |
| `whooshWait`, `scrapeWait`, `WallCheck`, `inWall` | a whoosh on a swing, a scrape on a wall, and no hit through geometry | **Partly.** The whoosh and the wall block are worth it; the scrape is BD22 flavour. |
| `swingTics` / `calmTics` / `settle` / `ReadyPose` / `BodyFrame` | swing state and a held-ready pose for the blade | **No.** Ties to BD22's axe frames. |
| `Throw` / `Launch` / `AimAssist` / `RSVR_AxeThrown` / `RSVR_AxeGrip` | axe throwing by velocity | **No.** Nothing in the Aliens set is a thrown blade, and the satchel already has its own throw. |
| `KindOf` / `AXE` / `SWORD` / `RSVR_MeleeHandler.NetworkProcess` with `rsvr_axe_grip` | key-level grip sync for the throw | **No**, with the throw gone. |

**What the owner would feel:** a hard stab connects instead of passing through, a swing cannot
double-hit, the hand buzzes on a hit, and the reach is the knife's own blade.

**Verify:** headset for feel; the rig can prove the swept segment by scripting
`qz_rhand` through a monster (`summon SynthAT` + `notarget`, never `freeze`) and reading
`printinv` / the monster's health.

**Risk:** low-medium, and confined to one file nothing else calls.

### Step 9 — The two-handed gun-hand pose (needs a hand frame)

**Files:** `zscript/rsq/handtable.zs` (a new accessor, not a number),
`zscript/rsq/hands.zs`, `MODELDEF.ae` hand blocks, `models/rsq/hand.md3`.

1.92's `RSQ_HandTable` has **two** gun-hand letters, `GunOne(i)` and `GunTwo(i)`, and
`A_RSQ_Layers` picks `String g = hold ? GunTwo(i) : GunOne(i)`. They differ on exactly two BD22
guns: index 4 (BrutalPistol) `A`/`B` and index 18 (Rifle) `A`/`B`; every other gun has
`GunOne == GunTwo`. So the mechanism exists to change the gun hand's own pose when the second hand
comes on — a thumb tucked out of the cup, on a pistol.

The pack has a single `GunPose(i)`. Its `RSQ_GunSide` states run `GunA..GunF` and `TrgA..SqzE`
only, so a second pistol pose needs **a new hand frame in `hand.md3` plus a new MODELDEF letter**,
i.e. art and a mesh write, not just code. `docs/FINGER_ON_TRIGGER.md` is the method
(`trigger_finger/` rig, and `patch.py` asserts the target `hand.md3` matches what the solution was
solved against, so a stale solution is refused rather than silently applied).

**Do this after Step 3, not before.** Step 3 makes the second hand appear on the pistols at all;
until the owner has seen that in the headset there is no way to judge whether the gun hand also
needs to change. Deferring also keeps it clear of the owner's live tuning of `handtable.zs`.

**Risk:** medium-high, because it writes a mesh. Lowest certainty of value in this plan.

### Step 10 — Shell casings (needs new actors first)

**Files:** a new `zscript/rsq/casings.zs`, `actors/` (new casing actors), `MODELDEF`.

1.92's `zscript/rsq/casings.zs` is small (2,856 bytes) and does **one** thing: it catches BD22's
own casing actors in `WorldThingSpawned` (`PistolCasing`, `EmptyBrass`, `ShotgunCasing`) and
re-places them at a measured ejection port in the controller's frame, flicked right and up. It
creates nothing.

**That premise does not hold here.** `zscript/rsr/rsr_pump.zs` line 491, written during the
2026-10-22 port, records the finding: "AE (2026-10-22): the TC has no casing actor". A grep for
`casing|brass|shelleject|spentshell` across `actors/`, `decorate.ae.txt` and `zscript/` returns
only that comment and the two lines around it. So porting `casings.zs` needs casing actors made
first, plus a measured ejection port per gun.

**Partly already done:** the shotgun **does** eject a spent case —
`RSP_State.CaseOut` spawns `RSP_DroppedShell` with the shell mesh and flings it
`-L * 3.0 + U * 3.5 - F * 0.5`. Its in-file note says it uses the **loading** port because no
ejection port was measured (`RSP.Ports(i)` returns 1, and the BD22 side port
`PortK(i,1) = (12.8, -1.9, 0.2)` is BD22's measurement, not an Aliens one).

So the honest claim is: the pack has no brass from the pistols, rifles or smartgun, and the
shotgun's spent case comes out of the wrong hole.

**Cost and budget.** `docs/QuestReload_Diagnosis.md` records the Quest limits that matter:
"Vertex-animated MD3 costs about 5.1x its file size in RAM, twice on Quest", and the owner's 2026-10-02
decision "Nothing that grows file size". A casing is a world actor, not a psprite layer, so it costs
nothing in the 128-bone or per-layer budget — but each new mesh costs RAM, and a corridor full of
brass costs actors. The affordable form is a **sprite** casing, or the magazine mesh the pack
already ships reused at a small scale, with a short lifetime — not a new mesh per gun.

**Recommendation: defer, and scope it separately.** It is the only item here that needs new assets
and new measurements, it touches none of the owner's four named priorities, and
`measurements/` has no Aliens ejection port to work from. When it is picked up: measure each gun's
port the way the kit measures everything (`MEASUREMENTS.md`, "Moving parts" and the F/L/U chain),
and give the shotgun its real ejection port while there.

### Not a port gap — checked and clear

Recorded so the next session does not re-open them:

- **`zscript/rsvr/vrhand.zs`** is **byte-identical** to 1.92's after line-ending normalisation.
- **`zscript/rsq/gunmoves.zs`** exports exactly 1.92's four accessors (`Pivot`, `Mirrored`,
  `Blends`, `Frame`) with the same shapes; only the per-gun tables differ, as they must.
- **`zscript/rsq/ballistics.zs`** is identical apart from line endings and 28 lines of per-set
  tuning.
- **`RSQ_Turn`** (the rotation order: yaw about y, pitch about x, roll about z) is byte-identical.
- **`zscript/rsr/rsr_assist.zs`** is a complete port: every const, `Scale`, `R`, `A`, `Frac`,
  `Back`, `Leave`, `SeatAt`, `Ring` and all twelve per-module accessors are present with 1.92's
  values. The handoff's "zone rings draw far too large" is **not** a port gap — `ZoneRing` and
  `Ring` match 1.92 exactly, so that symptom is the `rsr_assist` scale or
  `vr_vunits_per_meter` on the headset, and belongs to the audit lane.
- **`zscript/rsr/rsr_pump.zs`** is 1.92 **plus** additions, and it carries both 2026-10-13 pump
  fixes from `docs/HANDOFF_trigger_finger.md`: the waiting mode (`waitHand`, `BeginPump(..., wait)`,
  and the `!waitHand || (buttons & BT_ATTACK)` fallback) and the scaled magnetic lead-in
  (`LeadIn()` returning `max(RSP.ENTER_BEHIND, RSR_Assist.PumpCapture(...))`, used at all three
  sites).
- **Abort on death or weapon switch** is present and identical: `RSR_Handler.WorldTick`'s
  `gone = mo.health <= 0 || mo.player.ReadyWeapon != s.weap || now - s.lastTick > 2`, then
  `s.Abort(mo)`, which drops the magazine from `DROP`/`INSERT`/`CARRY` before `End()`.
- **`RSR_Guns.MagCentre`, `Grab`, `Travel`, `Well`, `Axis`, `Mouth`** reproduce the
  `MEASUREMENTS.md` chain on the meshes to three decimals (checked on the rifle's magazine and the
  shotgun's pump). The Aliens reload geometry was measured properly.
- **`BT_OFFHANDRELOAD`** is `1<<28` = 268435456 in the pinned engine, matching both
  `CVARINFO.rsr`'s `rsr_magrelease` default and 1.92's literal.
- **`RSQ_Place.Layer`'s recoil-follow** is a faithful port of 1.92's `ModifyBobLayer3D`, including
  `LayerOffset`'s `oldx/oldy -> x/y` interpolation, the gun layer's own turn
  (`g.x / 4`, `(g.y - WEAPONTOP) / -4`), `Mirrored`, `Pivot`, the `FollowGun` cache, and the
  next-state blend (`inter = (gunState.Tics - gp.Tics + ticfrac) / gunState.Tics`).
- **`RSQ_HandTable.SupportPoint`** exists in 1.92 and is read by **no** ZScript in 1.92 (one grep
  across the whole extracted pk3 returns only its declaration). Its absence from the pack is not a
  gap.

---

## 2. Per-file missing-piece list

### `zscript/rsr/vreload.zs` — 1.92 36,354 / pack 32,423

Every reload phase, capture test, tolerance, confirmation and failure path 1.92 has:

| 1.92 | pack |
|---|---|
| phases `IDLE DROP EMPTY CARRY INSERT SEATED CHARGE PULL RELEASED DONE` (consts) | **PRESENT**, identical values |
| `DROP`: `d = DROP_CM * f*f` ease over `DROP_TICS 4`, then `Fall()` | **PRESENT** |
| `EMPTY`: `press && CanTakeMag` -> `Buzz` -> `CARRY` | **PRESENT** |
| `CanTakeMag`: reserve count, `POUCH_MIN 20` cm from the well, optional `rsr_pouch` low-draw at `POUCH_LOW 40` cm below the eyes | **PRESENT** |
| `CARRY` capture: `side < cap && dd < Mouth + cap && dd > -0.5*cap && ang < tilt`, snap to axis, `Buzz` | **PRESENT**, identical |
| `CARRY` release: `!g` -> `Fall()` at the hand | **PRESENT** |
| `INSERT` near-miss: `side > leave \|\| dd > Mouth + leave` -> back to `CARRY` | **PRESENT** |
| `INSERT` seat: `RSR_Assist.SeatAt(Mouth, MagSeatFrac, SEAT)`, `SndIn`, `Buzz`, `RSR_Seated` | **PRESENT** |
| `CHARGE` grab within `RSR_Assist.MagGrab` | **PRESENT**, and **DIVERGED for the better**: the pack's `if (press \|\| g)` lets a grab *held* since the magazine went in take the handle, where 1.92 needs a fresh `press`. The in-file note dates it to the owner's report "the pulse rifle does not let me rack after loading". **The pack is right; do not revert this to 1.92.** |
| `PULL`: `grabS` origin, `SndBack` at `BackAt * travel`, racked at `MagPullFrac * travel`, let go at `Leave(MagGrab) * 1.2` sideways | **PRESENT** |
| `RELEASED`: spring home at `SPRING 4.0` cm/tic, `SndFwd` + `RSR_Done` if racked, else back to `CHARGE` | **PRESENT** |
| grab debounce: `press = (g && !gripPrev) \|\| netPresses != usedPresses && !Steadied` | **PRESENT** |
| held-vs-fresh: `Begin()` sets `gripPrev = Grip(mo)` so a grip already held is not a new grab | **PRESENT** |
| `GripCanGrab` (grip grabs only outside `STEADY_RANGE 50` or with `vr_two_handed_weapons 0`) | **PRESENT** |
| `gripFree` latched at the press, cleared on release | **PRESENT** |
| interpolation of the held item: `dPrev/d`, `pullPrev/pull` x `ticfrac` in `Place` | **PRESENT** |
| abort on death / weapon switch / stale tick | **PRESENT** |
| `const LOCK_TUG = 1.5` | **MISSING** |
| fields `slideLock`, `lockedGrab`, `lockGun` | **MISSING** |
| `lockedGrab` branches in `CHARGE`, `PULL`, `RELEASED` | **MISSING** |
| the slide-lock block at the head of `Draw()` (sets/clears `slideLock` from `MagAmmo` count + `IsReadyFrame`, picks `SprGun` frame 1 / 2, keeps the handle layer alive while locked) | **MISSING** |
| `slideLock` branches in `Place` (`case RSR.HANDLE`, `case RSR.BOLT`) | **MISSING** |
| `End()` clearing `lockedGrab` | **MISSING** (with the fields) |
| `RSR.GrabWith` (`rsr_grab_with`: trigger / grip / Use) | **MISSING** |
| `RSR.GrabMask` returning 0 unless the trigger is the chosen way | **DIVERGED**: always returns `rsr_grab_buttons` |
| field `netUse`, `Grip()`'s `\|\| netUse` | **MISSING** |
| `IsUseKey` + `useEaten` + the `rsr_use` netevent + the Use interception in `InputProcess` | **MISSING** |
| `NetworkProcess`'s `GrabWith(...) != 1` gate on `rsr_grip` | **MISSING** |
| `InputProcess`'s `GrabWith(me) == 1` term in `eaten[k]` | **MISSING** |
| `Wanted()`'s Purist gate (`IsPlayingAsPurist`) | **CORRECTLY DROPPED** — BD-specific |
| `RSB_Handler.Busy` / `RSK_M203Handler.Busy` terms in `busy` | **CORRECTLY DROPPED**, with the reason in-file: an unknown identifier is a hard error, and neither module ships here |
| class name `RSR_ReloadHandler` | renamed `RSR_Handler`; cvar `rsr_reload` renamed `rsq_reload` |

### `zscript/rsq/hands.zs` — 1.92 26,329 / pack 25,908

Restructured, not cut down: the layer selection moved from a weapon state action
(`RSQ_Hands.A_RSQ_Layers`) into `RSQ_HandHandler.WorldTick`, and the placement into
`RSQ_Place.Layer` called from `RSQ_Hands.ModifyBobLayer3D`. Both are sound, and
`git show 9afc750:src/rendering/hwrenderer/scene/hw_weapon.cpp` confirms the single-hook design is
the only one that works: `GetWeaponPosition3D` sets `w.weapon = psp->GetCaller() ==
player->ReadyWeapon ? readyWeaponPsp : offhandWeaponPsp`, and the virtual is then looked up on
`w.weapon->GetCaller()->GetClass()`, so `RSQ_Hands::ModifyBobLayer3D` is called for every layer
owned by `RSQ_GunSide` — gated on `(psp->Flags & PSPF_ADDBOB)`, which both packs set.

| 1.92 | pack |
|---|---|
| `RSQ_Layers` ids 2100 gun hand / 2101 support / 2200 free / 2201 hand magazine | **PRESENT** (plus `OFFGUN` and `COUNTER`) |
| `TrgA..SqzQ` trigger / squeeze states, `Sqz` while `BT_ATTACK` is held | **PRESENT** (`TrgA..SqzE`, matching the four `Trigger` letters in use) |
| `SetLayer` only on a state change, `bAddBob = true`, `y = oldy = WEAPONTOP` | **PRESENT** |
| `FollowGun` + `LayerOffset` + next-state blend + `Mirrored` + `Pivot` + `RSQ_Turn.Place` | **PRESENT** |
| `hold`'s closeness rule for `Support(i) == "A"` with 13 / 18 cm hysteresis and the `holding` latch | **MISSING** (Step 3) |
| `hold`'s reload veto (`rsr == ""`) | **MISSING** (Step 3) |
| `GunTwo` selection while two-handed | **MISSING** (Step 9) |
| `Upkeep`'s `p.playerstate != PST_LIVE` term | **MISSING** (the pack checks `mo.health <= 0` only) |
| `showOwn` / `OwnHand` / `fistMesh` / `FistFrame` / `FistMove` / `OffPunch` / `offMesh` / `freeFist` / `OffFist` / `nadeSprite` / `unsSprite` / `bdHandSprites` / `ongSprites` / `ungSprites` | **CORRECTLY ABSENT** — all keyed to BD22's own punch, taunt, grab and grenade sprites |
| the `i == 18` M203 and `PuristRifle` special cases | **CORRECTLY ABSENT** |
| `RSB_Handler` / `RSK_M203Handler` routing in `ModifyBobLayer3D` | **CORRECTLY ABSENT** |
| — | pack-only and needed: `RSQ_HandTune` (the owner's live sliders), handedness swap by layer owner, `OFFGUN`, `COUNTER`, the smartgun gimbal exemption (`i == 8 \|\| i == 16` zeroes `gunTurnNow`) |

### `zscript/rsq/handtable.zs` — 1.92 6,649 / pack 6,609

**The owner is tuning this file's hook and rot numbers in the headset right now. No number below
is a proposal.**

| 1.92 | pack |
|---|---|
| `GunOne(i)` / `GunTwo(i)` | **DIVERGED**: one `GunPose(i)` (Step 9) |
| `Support(i)` | renamed `SupportPose(i)`; same role, same letters, `A` on the four pistols |
| `GunHook` / `GunRot` / `SupportHook` / `SupportRot` | **PRESENT** |
| `Trigger(i)` | **PRESENT** |
| `SupportPoint(i)` | **ABSENT, and correctly so** — dead in 1.92 too |

### `zscript/rsr/rsr_assist.zs` — 1.92 9,533 / pack 9,375

No missing piece. Complete port; the 158 bytes are comments plus one per-gun row
(`MagGrab` 16.0 cm for indices 2 and 8, the pulse rifles' charging handle).

### `zscript/rsq/gunmoves.zs` — 1.92 19,329 / pack 17,473

No missing piece. Same four accessors, same shapes; the difference is 16 Aliens guns against
BD22's 25.

### `zscript/rsr/rsr_pump.zs` — pack 45,504 / 1.92 42,189 (pack larger)

The pack's additions are real work, not divergence: a second insertion port
(`Ports`/`PortK`/`PushK`/`DepthK`/`ShellAtPortK`), the `shotgun_shell.png` surface fix, the
`RSP_DroppedShell` spent case, and the shell-into-the-port-then-forward behaviour
(`Push (1,0,0)`, `Depth 6`). Both 2026-10-13 pump fixes are in. Only `HandRot`/`AxisInHand` carry
BD22's numbers (Step 7).

### Files absent from the pack

| 1.92 file | bytes | verdict |
|---|---|---|
| `zscript/rsr/rsr_m203.zs` + `rsr_m203_geo.zs` | 16,428 + 2,398 | **Do not port.** Section 3. |
| `zscript/rsr/rsr_break.zs`, `zscript/rsr/rsb_guns.zs` | 44,810 + — | **Do not port.** Section 4. |
| `zscript/rsq/casings.zs` | 2,856 | Premise does not hold — Step 10. |
| `zscript/rsvr/melee.zs` | 22,045 | Port the five mechanisms in Step 8, not the file. |
| `zscript/rsq/fists.zs` + `fistmoves.zs` | 4,968 + 2,742 | **Do not port.** Section 4. |
| `zscript/rsq/alts.zs` | 1,703 | **Do not port.** Section 4. |
| `zscript/rsq/handler.zs` | 2,110 | **Do not port** — Step 3 needs one bool, and the pack has zero references to `RSQ.`, `RSQ_Handler` or `RSQ_State`. |
| `zscript/rsq/dualhands.zs` | 3,026 | **Do not port.** Section 4. |
| `zscript/rsq/voxels.zs`, `voxtable.zs` | — | **Do not port.** Section 4. |
| `zscript/rsr/rsr_guns.bd.zs` | — | BD-only table; the pack's `rsr_guns.zs` is its equivalent. |
| `zscript/rsg/grenade.zs` | — | BD's pin-pull grenade; the Aliens satchel has its own throw. Not in scope. |

### Reimplemented rather than ported (noted, not faulted)

`zscript/rsq/flick.zs` (`RSQ_Flick` -> `AE_Flick` + `AE_FlickHandler`) and
`zscript/rsq/dual.zs` (`RSQ_Dual` -> `AE_DualHandler`). The flick's two divergences are Step 6;
dual wield is another lane's.

---

## 3. The underbarrel launcher: decision

**Keep `pumpgl.zs` and finish it (Step 4). Do not port `rsr_m203.zs`.**

The 18.8 KB size difference is not the point — the two mechanisms are not the same mechanism.

`rsr_m203.zs`'s own header states what it models: "stabilized (the off grip ...), the OFF TRIGGER
is the latch: hold it and push the off hand forward, the tube follows the hand and **opens at the
front** ... take a 40 mm round away from the gun, tilt its nose into the breech and push it home
... stabilize and pull back: the tube **locks shut**." Its phases are `EMPTY / CARRY / INSERT`
with `OPEN_FRAC 0.92`, `SHUT_FRAC 0.06`, `RELOCK 0.6`, and `RSM_Geo` carries `TUBE_REAR`,
`TUBE_FRONT`, `ROUND_LEN`, `ROUND_SEAT`. It is a sliding-breech launcher that takes a loose
grenade.

The M41A's launcher is a **pump**, and the owner's rule for it is already fixed:
`ae_glpump_cost` rounds out of the magazine become one grenade
(`pumpgl.zs` header: owner, "1 pump reduces ammo by 20 but loads 1 secondary fire"). There is no
loose 40 mm round in this arsenal to insert, and the rifle mesh has no tube surface to slide —
it has `m41a_pump`.

Cost of porting `rsr_m203.zs` anyway: a new `RSM_Geo` measured for a mechanism the mesh does not
have; a 40 mm round mesh and three MODELDEF blocks for it (round in hand, round at the breech,
round seated); an `RSM_NoTube` sprite-twin table pairing **every** rifle sprite with a no-tube
copy (1.92's has 16-plus pairs, and `modeldef.rifle.txt` shows the Aliens rifle uses `PULS`,
`PLSR`, `PLMF`, `PLSP`, `YULS` and their Yutani twins); the `RSM_SpentCase` actor; and a gameplay
rule that contradicts the owner's. It would not solve "the pump part does not move with the hand",
because it does not drive a pump.

Cost of finishing `pumpgl.zs`: two MODELDEF blocks, a layer pair routed in `RSQ_Place.Layer`
exactly as `RSP_Handler`'s already are, a continuous `pull` in place of a boolean `back`, and the
travel default corrected to the mesh's measured stroke. It solves the open item directly, because
the pump then *is* the hand's position.

**Verification that the surface exists, before relying on it (the brief asked):**
`models/weapons/rifle/m41a.md3` surface **`[1] m41a_pump`**, 448 verts, 428 tris, present in all
36 frames, bbox x[31.0, 46.3] y[-2.9, 2.9] z[-7.6, -0.8], centroid (39.185, -0.018, -4.558), long
axis (0.9874, 0.0123, 0.1578). `MODELDEF.rsr` already writes `SurfaceSkin 0 1` for it. It exists,
it is separable, and it is exactly the same shape of job as `m37a2_pump` (381 verts) in
`MODELDEF.rsrpump`.

One honest correction while there: `pumpgl.zs`'s `PumpPoint()` of `(42.5, 0.0, -8.5)` is **close
enough**. Through the chain verified in Step 4, the surface centroid is (43.97, -0.02, -9.11) —
about 1.5 cm forward and 0.6 cm down of what the file uses, well inside the 14 cm
`ae_glpump_grab` radius. **The grab point is not why the part does not move.** Use the derived
point when the layer goes in, but do not spend time on it as a suspect.

---

## 4. What NOT to port

### `rsr_break.zs` + `rsb_guns.zs` — nothing in the Aliens arsenal is a break action

Checked before asserting. Every weapon class in `actors/weapons/` is:
`Knife_3D`, `YutaniKnife_3D`, `M4A3Pistol_3D`, `MercPistol_3D`, `SynthPistol_3D`,
`YutaniPistol_3D`, `PulseRifle_3D`, `YutaniRifle_3D`, `NewShotgun_3D`, `YutaniShotgun_3D`,
`Smartgun_3D`, `YutaniSmartgun_3D`, `M240Flamethrower_3D`, `YutaniFlamer_3D`, `Satcheler_3D`,
`YutaniSatchel_3D`, plus `Loader_3D` / `AELoader_3D` / `LBerserk_3D` / `AEBerserk_3D` and the
alt-fire token inventories. No revolver, no double barrel, no hinged launcher. Both shotguns are
the pump `m37a2.md3` (surface `[1] m37a2_pump`), handled by `rsr_pump.zs`. The pack's
`vreload.zs` already drops the `RSB_Handler` terms with the reason recorded in-file.

`rsr_assist.zs`'s `BreakCapture` / `BreakTilt` / `BreakSeatFrac` are harmless dead accessors;
leaving them costs nothing and keeps the file diffable against 1.92.

### `rsb_guns.zs`, `rsr_guns.bd.zs` — BD22 gun tables. Nothing transfers.

### `voxels.zs` + `voxtable.zs` + `Voxeldef.txt` / `Voxeldef.cruel.txt` / `CVARINFO.rsqvox` / `MENUDEF.rsqvox` / `MODELDEF.rsqvox`

BD-specific, and they carry a shipping trap with them. `00_START_HERE.md` Step 8:
"For BD22, `BD_VoxelPack.pk3` must load **before** the weapons pack. Without it, 1.90+ fails at
startup on any platform." The Aliens pack must not acquire a second required pk3 — its load order
is already fixed in `docs/HANDOFF_2026-10-23.md` §0 and `MENUDEF.ae` already states "No voxel
options: this set ships no voxels."

### `alts.zs` — BD22's option-gated secondary fires

`RSA_Opt_SMG`, `RSA_Opt_Rev`, `RSA_Opt_Slug`, `RSA_Opt_Semi`, `RSA_BurstSMG`, `RSA_Magnum`,
`RSA_Slug` and the `rsa_*` server cvars drive BD22's own `RSA_` DECORATE states. The handoff
records that every Aliens alt fire already works through the TC's own states, untouched.

### `fists.zs` + `fistmoves.zs` — BD22's fists weapon

Needs BD22's `Melee_Attacks`, `MeleeStrikeNormal` / `MeleeStrike1Berserked` and the
`fistclosed.md3` punch frames. The Aliens set's melee weapon is a knife. The pack's `melee.zs`
already punches with the free off fist and already has the once-per-blow cooldown
(`offCool[n] = 12`) that is the valuable part.

### `dualhands.zs` — superseded by the pack's own solution

The pack puts the off-hand gun's hand on `RSQ_Layers.OFFGUN` with the gun as caller and the hook
baked into `MODELDEF.aedual`'s `Offset`, which is the same trick for the same engine reason
(`models.cpp:221`) and is already working per the handoff.

### `handler.zs` — one bool, not a file. See Step 3.

### 1.92's own bugs and traps, not to import

- **The "Use key" grab as a usercmd bit.** Do not take the shortcut the pack already took: a
  `BT_USE` bit in `rsr_grab_buttons` grabs the magazine **and** opens the door. 1.92 solves it by
  eating the key (`IsUseKey` / `useEaten` / `rsr_use`). Either port that properly or drop the
  option (Step 1).
- **`BreakCapture`/`BreakTilt`'s per-gun rows.** 1.92's indices 2 and 3 are BD22's grenade
  launcher and revolver. The pack already stripped them; keep them stripped.
- **`rsr_assist.zs`'s shared `Mag*` index space.** 1.92's own header warns: "BD22 index 1 is
  `Rifle` and V+ index 1 is `VR_Rifle`, so leave index 1 at the default or the two sets drag each
  other." The Aliens pack is a third set in that space, and index 1 is `M4A3Pistol`. The pack's
  only per-gun row is on 2 and 8. **Do not add a row on index 1.**
- **`Draw()`'s hard-coded slide-lock gun list** (`i == 1 || i == 2 || i == 3 || i == 5`). Those are
  BD22 indices. Step 5 uses the six `HasHandle` guns instead.
- **`ModifyBobPivotLayer3D`.** `docs/QuestReload_Diagnosis.md`: "broken in this build. Do not
  use it" (`hw_weapon.cpp:973-974` against `weapons.zs:48`). Neither pack uses it; keep it that
  way.
- **V+'s 1.5 cm shell depth problem**, recorded in `docs/HANDOFF_trigger_finger.md` as still open:
  a seating distance below hand tremor makes a part seat the instant it is caught. The Aliens
  shotgun's `RSP_Guns.Depth` is 6.00, so this one is already avoided — do not "simplify" it back
  down.
- **Writing `vr_two_handed_weapons`.** `docs/RELOAD_ON_QUEST.md`: read, never written. Neither
  pack writes it. Keep it that way; Step 3 only reads `WF_TWOHANDSTABILIZED` and the controller gap.

---

## 5. What cannot be verified without the headset

Marked per the brief. The Windows build at
`C:\Users\Command\Desktop\qzdoom-17-3-Windows-64bit\qzdoom.exe` can run the parse gate and a
desktop look (`+vr_mode 0`); the Linux rig in `tools/rig/` can render any pose on the real engine
and script the hands (`qz_hmd` / `qz_rhand` / `qz_lhand`, `qz_rtrigger` / `qz_rgrip`,
`qz_shot <file.ppm>`). Neither can judge feel. **A `-norun` parse cannot see a VM abort, so
every step below gets an in-level boot test on the staged pk3 before it is installed.**

| Step | Verifiable without a headset | Headset only |
|---|---|---|
| 1 grab-input menu bug | **Fully** — parse gate, then read the cvar back after picking each option | — |
| 2 grab-input parity | parse gate; `rsr_debug` prints the grip decision and the gap, which the rig can script | whether one grab button feels better than two, which is the owner's call |
| 3 pistol support hand | rig render with the support layer forced, to confirm `Sup A` draws on the pistols at all | the 13 / 18 cm in/out distances, and whether a cup support reads as both hands on the gun. **Do not touch those two numbers without his report.** |
| 4 launcher pump | parse gate (MODELDEF is fatal on a bad class or sprite, silent on a missing frame); rig side render at scripted hand positions proves the part tracks the hand and the travel matches the mesh; `printinv` proves the ammo conversion | whether the stroke length is comfortable |
| 5 slide / bolt lock | rig render of all six guns on the new frame; `rsr_debug` phase prints prove the lock transitions | the `LOCK_TUG` tug, and whether a locked slide reads correctly at arm's length |
| 6 flick reload | the ready gate is testable by scripting a flick during a fire animation on the rig; the `pixelstretch` and `mo.vel` corrections are arithmetic | whether it fires when he does not mean it — the whole point of the step |
| 7 shell orientation | rig render of the hand holding the shell is how the current 57.6 was checked, and will show the new value | the final ~45 degrees the owner reports; his eye settles it |
| 8 melee | rig can prove the swept hit lands and does not double-hit, by scripting a hand sweep through a summoned monster and reading its health | stab feel, reach, and whether the haptic reads as a hit |
| 9 two-hand gun pose | `trigger_finger/patch.py` asserts the `hand.md3` matches what the pose was solved against, so a stale apply is refused; the fit sheet is a render | **everything that matters.** Do not start this before the owner has seen Step 3. |
| 10 casings | parse gate; actor counts | whether brass in a dark corridor is the win it sounds like, and whether it costs frames on the Quest |

Nothing in this plan has been seen in a headset, and — as `docs/RELOAD_ON_QUEST.md` says of 1.92's
own tolerances — every tolerance named here is a default derived from geometry, not from play.
