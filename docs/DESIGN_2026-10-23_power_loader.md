# The P-5000 Power Loader as a machine you wear
### A buildable design for RS Aliens VR Weapons (Quest), 2026-10-23

Target: **QuestZDoom 17.3 = emawind84/gzdoom `9afc750917` = GZDoom 4.14.3**, stock app, no
engine change. Every `file:line` below was read with `git show 9afc750917:<path>` or
`git grep -n <pat> 9afc750917` in `E:\DOOMWork\QZD17-engine`, never from the checkout's HEAD
(`670d19eba6`), which carries engine work that does not exist on the shipped app.
Mesh numbers were read out of the MD3 headers and vertex blocks directly, in this session.
Nothing under `_old/` or `RS_HardPoints/` was opened.

Companion documents, read before this one and not re-derived:
`docs/STUDY_2026-10-23_body_gear_on_qzd173.md` (the capability map — **three corrections
below**), `docs/HANDOFF_2026-10-23.md`, `docs/PLAN_2026-10-23_owner_all_of_it.md`.

---

## 0. The three findings that change the shape of the job

**1. `A_SetSpeed(0.35)` has never done anything.** `PlayerPawn.MovePlayer()` reassigns
`Speed` at the top of every tic it runs — `wadsrc/static/zscript/actors/player/player.zs:1374-1383`:

```zscript
if (!vr_momentum && !player.keepmomentum && player.onground && friction == ORIG_FRICTION)
{ vel.XY *= 0.0001; Speed = Default.Speed * 8; }
else { Speed = Default.Speed; }
```

and then uses it at `:1414-1415` (`fm *= Speed / 256`). `vr_momentum` is false by default
(`hw_vrmodes.cpp:120`), so in VR on the ground the first branch always wins. The loader's
`A_SetSpeed(0.35)` in `actors/weapons/mechloader.txt:22` is overwritten on the next tic and
the loader has never been slower than anything else. **The TC's own `avw_speed_mult` is dead
the same way** — `zscript/superhuman_attributes.txt:48-53` writes `pawn.Speed`.

The working hook is `Inventory.GetSpeedFactor()` (`inventory.zs:1182`, virtual), which
`PlayerPawn.TweakSpeeds` multiplies in at `player.zs:1313-1322` *inside* `MovePlayer`, after
`Speed` has been reassigned. A ZScript token on the player is the whole fix.

**2. The two arms are one mesh surface.** `mechloader.md3` has exactly three surfaces and
`MechArms.001` (3590 verts) is *both* arms, spanning `y −121.81 … +121.81` — exactly
symmetric. There is no way to draw one arm without the other, and no `A_ChangeModel` flag
operates below model-index granularity (`CMDL_HIDEMODEL` sets `modelID = -2`,
`p_actionfunctions.cpp:5481`, skipped at `models.cpp:446-449`; `CMDL_USESURFACESKIN` only
reskins). **Two independent arms requires splitting that surface.** That is the one piece of
mesh work the whole design rests on, and it is carving, not authoring.

**3. `MechGuard.001` is the cage, and the owner's guess was right.** Per-surface bounding
boxes of `mechloader.md3` frame 0, in model units (= centimetres on the HUD path, see §3.2):

| surface | verts | x | y | z | what it is |
|---|---|---|---|---|---|
| `MechCover` | 18 | 9.95 … 58.11 | ±15.2 | 80.2 … 94.9 | a 48×30 cm flat panel above the head — the roof grate (skin `loader_grate.png`) |
| `MechArms.001` | 3590 | −65.1 … 228.0 | ±121.8 | −47.4 … 95.7 | **both** arms: 2.28 m reach, 2.44 m span |
| `MechGuard.001` | 1245 | −0.80 … 69.1 | ±30.7 | −2.19 … 102.4 | a 69×61×104 cm symmetric frame starting at the origin — **the cab cage** |

The origin of the held mesh is the operator. So one carving pass yields
`loader_arm_r.md3`, `loader_arm_l.md3` and `loader_cage.md3` (guard + cover) and unlocks
items 1, 4 and the cage at once.

### Corrections to `STUDY_2026-10-23_body_gear_on_qzd173.md`

* **§1.7 "No haptics API for ZScript … the only mod-side pulse is `player.bonuscount`, which
  fires both hands" is wrong.** `SpawnPlayerMissile` fires a **per-hand** 150 ms pulse at 0.8
  intensity from ZScript on the stock engine — `src/playsim/p_mobj.cpp:7546-7563`:
  ```cpp
  long rightHanded = vr_control_scheme < 10;
  rightHanded = (aimflags & ALF_ISOFFHAND) ? 1 - rightHanded : rightHanded;
  vrmode->Vibrate(150, rightHanded ? 1 : 0, 0.8);
  ```
  gated only on the missile having a `DamageFunc`, a non-zero `DamageType`, or a `SeeSound`.
  `RSVR_Buzz` (`zscript/rsvr/common.zs:24-42`) has `DamageType "RSVRHaptic"`, which is why
  `vreload.zs:334-337`'s `Buzz()` works. `P_LineAttack` with `LAF_ISOFFHAND` does the same
  when damage > 0 (`p_map.cpp:4767-4777`). **The pack already has one-hand haptics**; the
  loader should use them heavily. Both hands do buzz while `weaponStabilised` (`:7558-7562`).
* **A new trap for body-anchored world actors the study does not record.** `+MASTERNOSEE`
  with a `master` set makes the actor **invisible**: `hw_sprites.cpp:832-835` redirects
  `viewmaster` to `thing->master`, and `:849-865` then returns early for anything whose
  viewmaster is the camera and within 2 units of it. Never set that combination on the legs
  or the cage.
* **§1.5's caveat stands and is still open:** whether `A_ChangeModel` compiles when called as
  a method from an `EventHandler` is unverified. It is a one-line compile check and the
  design below does not depend on it (see §3.5).

---

## 1. Ordered build plan

Each step compiles, boots and is judgeable on its own. Step 1 needs no new art and no mesh
work and is the single biggest change in feel per line written.

Every step ends the way `PLAN_2026-10-23_owner_all_of_it.md` requires: build, compile-check,
**in-level** boot-check (a `-norun` parse cannot see a VM abort), install, report.

| # | step | files | new art | what the owner feels |
|---|---|---|---|---|
| **1** | **It is heavy.** `AE_LoaderWorn` token: `GetSpeedFactor()` from `ae_loader_speed` (0.35); a looping hydraulic hum re-asserted every tic, pitched by arm speed on the saber's curve; `A_Quake` per footstep scaled by `vel`; a servo clunk and a per-hand `Buzz()` when an arm stops hard; `flick.zs` and `melee.zs` gated off while worn. | new `zscript/rsvr/handmotion.zs`, `zscript/ae/loader.zs`; 1 line in `ZSCRIPT.ae`; `CVARINFO.ae`, `MENUDEF.ae`, `SNDINFO.rsr` | none | He walks like a machine and the machine answers his arms. Nothing is drawn differently yet. |
| **2** | **The beacon.** `loader_lamp.md3` on a new layer on the worn loader, yaw advanced per tic by writing `psp.x` (with `oldx` carried), its existing brightmap, and a red `A_AttachLight` on the pawn that washes the arms. | `modeldef.loader.txt`, `zscript/ae/loader.zs` | none | The orange light sweeps the walls. Pure flavour, two days of asset value for an afternoon. |
| **3** | **Two arms.** Split `MechArms.001` by `y` sign into `loader_arm_r.md3` / `loader_arm_l.md3`, keeping original coordinates. Main arm on layer 2300 (caller `AE_LoaderArms`, an inventory item), off arm on 2301 (caller `RSQ_Hands`). Both placed by `RSQ_Hands.ModifyBobLayer3D` through one new dispatch line in `RSQ_Place.Layer`. The old 3-surface held model stops drawing. | carve 2 meshes; `modeldef.loader.txt`, `zscript/ae/loader.zs`, `zscript/rsq/hands.zs` (+5 lines) | carve only | **This is the moment it stops being a melee weapon.** Each controller is an arm. |
| **4** | **Mass through lag.** A 10-deep ring of each hand's world pose, sampled in play; the arm drawn at the pose `ae_loader_lag` tics ago plus `ae_loader_overshoot` × the last step, translation in `ui`, yaw/pitch via `psp.x/y` in play. Lag scales with what is carried (step 6). | `zscript/rsvr/handmotion.zs`, `zscript/ae/loader.zs` | none | The booms swing behind his hands and overshoot. The owner's own instinct, cheapest to test once step 3 exists. |
| **5** | **The claw, and the swing.** Claw closure 0→1 over `ae_loader_claw_tics` while the trigger is held, drawn as a model frame; damage at the claw's own world point via `BlockThingsIterator.CreateFromPos`; swing detection by the saber's tip-speed-minus-body-step on the claw point. `A_CustomPunch(500, 72)` is deleted. | `zscript/ae/loader.zs`, `actors/weapons/mechloader.txt`, `modeldef.loader.txt` | claw frames (optional; frame 0 works) | A swing lands where the claw is, not down a line from his face. |
| **6** | **Grab, carry, throw, pin, crush.** `RSVR_Carry` as a general service; velocity-spring carry; the thrown-actor tracker; crush by `DamageMobj` past the gib threshold; the whole thing routed through `RSVR_HandNet` net events. | new `zscript/rsvr/carry.zs`, `zscript/rsvr/handnet.zs`, `zscript/ae/loader.zs` | none | *"Get away from her."* |
| **7** | **The body frame, then the legs.** `RSVR_Body` (the study's Design A) built first as its own thing; then `RSVR_Legs`, two world actors under the waist line, carved from `loader_lower`, pitched counter-phase at a cadence from `mo.vel`. | new `zscript/rsvr/body.zs`, `zscript/rsvr/legs.zs`; carve 1 mesh; `MODELDEF` | carve; walk frames later | He looks down and the machine is under him, striding. |
| **8** | **The cage.** `loader_cage.md3` as a world actor at head height on the body frame; `ModifyDamage` on the worn token taking `ae_loader_cage_absorb` percent; the existing `mechaloader_spark.md3` fired at the impact bearing. | new actor; `modeldef.loader.txt`, `zscript/ae/loader.zs` | carve (shared with step 3) | He is *inside* something, and it sparks when it saves him. **Needs his eyes before it ships.** |
| **9** | **Diegetic.** Crosshair and weapon HUD suppressed while worn; getting in as a moment. | `zscript/ae/loader.zs`, `sbarinfo.txt` | none | The frame goes away. |

Steps 1, 2, 4 and 6 need no mesh work at all. Steps 3, 7 and 8 share **one** carving session.

---

## 2. Verdict on each idea

### 1. Two arms, one per controller — **BUILDABLE**

The caller/override constraint is real but it is not in the way, because the loader must be
the **ready weapon** and `RSQ_Hands` must stay the **off-hand weapon**.

*Which controller.* `src/r_data/models.cpp:221`:
```cpp
int hand = psp->GetCaller() == playermo->player->OffhandWeapon ? 1 : 0;
```
So the main arm's layer takes a caller that is *not* `OffhandWeapon` (a plain inventory item,
`AE_LoaderArms`, exactly as `RSQ_GunSide` already does) and the off arm's layer takes
`RSQ_Hands` as its caller.

*Who places them.* `hw_weapon.cpp:332` sets `w.weapon = psp->GetCaller() == player->ReadyWeapon
? readyWeaponPsp : offhandWeaponPsp`, and `:941-965` looks `ModifyBobLayer3D` up on
`weap.weapon->GetCaller()`'s class, nulling it when it is still `Weapon`'s own
(`:948-949`) and calling it only with `PSPF_ADDBOB` (`:953`). Neither of our two layers is the
ready weapon's, so both route through the off-hand psprite, whose caller is `RSQ_Hands` — a
ZScript class that already overrides the virtual (`hands.zs:439-446`). **Both arms are placed
by one function that already exists.**

The dual-wield failure the handoff records does not apply: that happened because a *DECORATE*
gun sat in `OffhandWeapon` and a ZScript class may not inherit a DECORATE actor. The loader
must therefore **never** be dual-wielded, and `ae_dual_*` must refuse it.

*What happens to the hands system.* `RSQ_HandHandler.WorldTick` keeps running and keeps
`RSQ_Hands` parked in `OffhandWeapon` (`hands.zs:526-527`) — that is required, not
incidental. While the loader is the ready weapon:
* `RSQ_HandTable.Index(Loader_3D)` returns 0, so `GUNHAND`, `SUPPORT` and `FREEHAND` all go
  to `"Hidden"` by the existing code paths with no edit. Verify with the table; if the loader
  is not in it, it already returns 0.
* `RSR_Guns.Index` and `RSP_Guns.Index` likewise return 0, so neither reload engages and
  neither claims a hand or a button. **The loader costs the reload system nothing.**
* `melee.zs` is already gated to the two knives (`melee.zs:116` `if (!KnifeHeld(p)) continue;`)
  so the free-fist punch cannot fire. No edit needed, but assert it in a comment.
* **`flick.zs` must be gated off.** `AE_FlickHandler.Reload` jumps the ready weapon to its
  `Reload` state (`flick.zs:97-102`) on any sharp downward jerk of the main hand — which is
  the single most common loader gesture. Whether `Loader` has a `Reload` state is in the TC and
  not in this repo, so this is a must-fix either way: add `|| AE_Loader.Worn(mo)` to its guard.

**The named compromise, and it is the one thing in this design that needs a decision:**
`hw_weapon.cpp:832` and `:917` both do
```cpp
if (weaponStabilised && psp->GetCaller() == player->OffhandWeapon) continue;
```
so **the off arm is not drawn at all while the engine is two-hand steadying.** The engine
latches that on an off-grip press with the controllers within 0.50 m (hard-coded; the in-tree
OpenVR copy is `gl_openvr.cpp:1717-1728`) and unlatches only on release. It also overrides the
weapon's aim along the hand-to-hand line (`:1742-1755`), which is nonsense for a loader.

ZScript **cannot** turn it off: `CVar.SetInt` throws `"Attempt to change CVAR '%s' outside of
menu code"` for any cvar without `CVAR_MOD` (`src/common/scripting/interface/vmnatives.cpp:947-955`),
and `vr_two_handed_weapons` is `CVAR_ARCHIVE | CVAR_GLOBALCONFIG` (`hw_vrmodes.cpp:119`).
Eating the grip key does not help either — `weaponStabilised` is set from the raw controller
state in the out-of-tree input layer before any key event exists.

Three options, recommendation first:
* **(a) Put a "Two-handed steadying" row for `vr_two_handed_weapons` in the Aliens VR menu**
  with a `StaticText` saying the loader needs it off, and have the loader print one console
  line the first time it is selected with the cvar on. The player turns it off once; the whole
  pack still behaves as he set it for every gun. Costs nothing, hides nothing, and is the only
  route the engine permits.
* (b) Accept it: design so the off grip has no loader function, and the off arm blinks out if
  he presses it anyway. Cheap, but a blink-out is the kind of bug that gets reported as "the
  left arm disappears sometimes" and costs a session to re-diagnose.
* (c) Mirror the off arm onto a main-controller layer while stabilised. Rejected: it would
  draw on the wrong controller, which is worse than not drawing.

### 2. Grab, carry, throw, pin, crush — **BUILDABLE**

Built on `vreload.zs`'s capture code where it generalises, and only there.

**What generalises from `vreload`** (all of it structural, none of it magazine-specific):
* The phase machine with a `phaseTic` stamp and `SetPhase` logging (`vreload.zs:201-207`).
* The hold rule: a grab is a *held* input, a release is the end of it, and a grab already held
  when a phase starts is not a new grab (`:350`, `:388-392`, and the hand-patched
  `case RSR.CHARGE: if (press || g)` at `:490-506` — the loader wants exactly that
  "held counts" behaviour, for the same reason).
* Capture with hysteresis: enter at `cap`, leave at `Leave(cap)` (`rsr_assist.zs`, used at
  `:435-446` and `:463-474`). The loader's grab/release radii are the same shape.
* The abort path: the weapon left, the player died, the tic stream lapsed
  (`RSR_Handler.WorldTick:904-915`, `Abort`, `End`). A held monster **must** be released by
  exactly this, on all four conditions.
* `prev`/`cur` + `ticfrac` interpolation for anything drawn (`:869-873`).
* The net boundary: `InputProcess` → `SendNetworkEvent` → `NetworkProcess` → playsim state
  (`:948-1007`).

**What does not generalise:** the well axis / mouth / seat geometry (`MagAtWell`,
`RSR_Guns.*`) — a monster has no axis to be pushed along; `Fall()` spawning a dropped-mesh
actor (the grabbed thing already *is* a world actor); `CanTakeMag`'s reserve-count and pouch
rules; the gun-frame `ToGun`/`FromGun` conversion, which should move to `RSVR_Body` and be
shared rather than copied.

So the new code is `RSVR_Carry`: a per-player, per-hand carry slot with `vreload`'s phase
shape and `vreload`'s abort discipline, and its own geometry.

**How a held actor is moved — a velocity spring, not `SetOrigin`.** Each tic:
```
held.Vel = clamp((clawWorld - held.pos) * ae_loader_grip_k, ae_loader_grip_vmax)
```
with `held.bNOGRAVITY = true` and `held.bTHRUACTORS = true` for the duration (both saved and
restored). Why:
* The engine's own `P_XYMovement` / `P_ZMovement` then do the line collision, the sliding and
  the blocking. **Pinning against a wall is not a feature we write — it is what happens when
  the claw keeps asking and the wall keeps refusing.**
* `SetOrigin(pos, true)` is a teleport: it ignores lines and would push the monster through the
  wall, so there would be nothing to pin it against. Writing `pos` directly is the same with
  the blockmap relink skipped as well.
* `bTHRUACTORS` stops the held thing shoving the player (who is solid) and the rest of the
  level's monsters, while leaving line collision intact.
* `bNOGRAVITY` is what keeps it from falling out of the claw, and restoring it is what makes a
  release a drop.
* The spring, not a hard snap, is also where half the weight comes from: `grip_k` low and
  `grip_vmax` capped means a Cacodemon trails the claw. One constant does two jobs.

**Its AI while held: still thinking. Recommended.** Nothing needs doing for that — its state
machine keeps running, and because our velocity write lands after its `A_Chase`, its own
`P_Move` is irrelevant. `CheckMeleeRange` is a distance test, so a held Alien held *close*
will claw at your face, and that is the scene from the film. The escape hatch is one cvar
`ae_loader_held_awake` (default **true**); setting it false sets `held.tics = 4` every tic,
which freezes the state machine entirely because no state's action runs again until its tics
expire. One line, both behaviours, the owner picks in the headset.

**What is grabbable — data, not a class list.** In order, cheapest test first:
```
a && a != mo && !a.player && !a.bNOINTERACTION && !a.bDORMANT
&& !a.bBOSS && !a.bNOTARGET && !a.bINVULNERABLE && !a.bNODAMAGE
&& (a.bSHOOTABLE || a.bCORPSE)
&& a.Mass > 0 && a.Mass <= ae_loader_grab_mass       // default 700
&& a.Height  <= ae_loader_grab_height                // default 80
```
`Mass` (`actor.zs:165`) is the natural datum: Doom's barrel is the default 100, a Cacodemon
400, a Baron and a Cyberdemon 1000 — and those two carry `+BOSS` anyway, so the mass cap and
the boss flag agree. **No class is named anywhere, `ExplosiveBarrel` included**: it is
`+SHOOTABLE` with default mass and passes on its own merits
(`wadsrc/static/zscript/actors/doom/doommisc.zs:3-19`). Never another player — netplay and
griefing. `ae_loader_grab_items` (default false) opens the door to decorations later without
touching the predicate.

**Finding the target.** `BlockThingsIterator.CreateFromPos(x, y, z, h, radius, false)`
(`doombase.zs:224-225`) at the claw's own world point, radius `ae_loader_claw_r` (default
40 units ≈ 1.2 m — the claw is big), nearest-passing-candidate wins. One iterator per arm per
tic while the claw is closing; nothing while it is open or already holding.

**How a thrown thing hurts what it hits — our own tracker, not `+MISSILE`.** `+MISSILE` is
tempting and wrong:
* `P_ExplodeMissile` jumps the actor to `Death` on the first line it touches, so a thrown
  Imp would die on a doorframe and a thrown barrel would detonate on one, regardless of the
  throw.
* It changes the whole `P_XYMovement` branch, makes the actor pass through its thrower, and
  makes other monsters stop treating it as a target.
* It permanently mutates an actor that survives, which is exactly the bug class the shield
  saw's own header warns about (`rs_shieldsaw.zs:36-40`: a flag cleared and never put back).

The tracker: `RSVR_Carry` keeps a capped list (`ae_loader_thrown_cap`, default 8) of
`{actor, thrower, speedWas, seen[]}` for `ae_loader_thrown_tics` (default 70) after release.
Per tic, per entry:
* `BlockThingsIterator.Create(a, a.radius + 8)`; for each `bSHOOTABLE` other than the thrower
  and not already in `seen`, `victim.DamageMobj(a, thrower, dmg, 'LoaderThrow')`, then
  `a.DamageMobj(a, thrower, dmg / 2, 'LoaderThrow')` so the thrown thing takes its share.
* Impact: `speedWas - a.Vel.Length() > ae_loader_impact_drop` (default 6 units/tic), or landed
  (`a.pos.z <= a.floorz + 1` with `speedWas` over the threshold). Then the self-damage, the
  surface-matched spall at the contact point (§5), and the entry is dropped.
* The list is capped and deterministic. It is pure playsim, driven from a net-replicated
  launch velocity, so every machine runs it identically.

**Damage scaling.** `RSVR_HandMotion` gives the claw's speed in units/tic; the release
velocity is `dir * speed * ae_loader_throw_gain` (default 1.4). Then
```
dmg = ae_loader_throw_dmg * (impactSpeed / ae_loader_throw_ref)^1.5 * (Mass / 100)^0.5
```
defaults `throw_dmg 40`, `throw_ref 20` units/tic. Super-linear in speed (so a real heave
reads as a real heave) and sub-linear in mass (so a thrown Cacodemon hurts twice as much as a
thrown barrel, not four times). The exponents are fixed in code; only the gain, the base and
the reference are sliders, because three knobs is already two more than he will want.
On the renderer-read rule: these are **play-scope** reads, and that is correct — see §6.

**Barrels.** Damaging one is enough. `ExplosiveBarrel` is `Health 20`, `+SHOOTABLE`, and its
`Death` state runs `A_Scream` and `A_Explode` itself (`doommisc.zs:3-31`). The tracker's
`DamageMobj` kills it and the barrel explodes on its own terms, with its own sound and its own
radius. No special case, no named class. **A barrel crushed in the claw explodes in your
face**, and it should — which is the best argument for crush being deliberate rather than
incidental (see the crush ladder below). The blast then comes back through the cage's
`ModifyDamage`, which is a pleasing bit of system talking to system.

**Corpses.** Confirmed grabbable. `p_interaction.cpp:435` sets `MF_CORPSE` on death
(`if(!(flags6 & MF6_DONTCORPSE)) flags |= MF_CORPSE;`); `A_NoBlocking` in the Death state
clears solidity and shootability but **nothing unlinks the corpse from the blockmap**, so
`BlockThingsIterator` still finds it and the grab predicate above accepts it on `bCORPSE`.
A thrown corpse damaging what it lands on is **free**, because the tracker does the damage —
the corpse never has to be shootable, never has to be a missile, and is never mutated. That
is the strongest single argument for the tracker design. A corpse that lands hard gets
`SetStateLabel("XDeath")` if it has that state, and a `'flesh'` spall burst either way.

**Crush.** `held.DamageMobj(self, mo, held.health + abs(held.GetGibHealth()) + 1, 'Crush',
DMG_FORCED)`. `GetGibHealth()` is the engine's own virtual (`actor.zs:634-640`, returning
`-abs(GibHealth)`), so driving health past it is what makes the engine pick `XDeath` and gib.
Not `A_Die`, which deals exactly `health` and leaves it at zero — a clean death, no gibs.
Never `Destroy()`, which removes the actor with no death state, no gibs, no kill count and no
item drop. `DMG_FORCED` is right for a deliberate crush but it bypasses `+NODAMAGE` and
invulnerability, which is why those are in the grab filter rather than checked here.

The ladder, so a crush is a decision: closure must reach ≥ 0.9 **and stay there for
`ae_loader_crush_tics`** (default 10, ~0.3 s). During that window a strain whine rises in
pitch (the saber's `A_SoundPitch` pattern) and a per-hand `Buzz()` pulses — so he hears and
feels it coming and can let go. Then: the engine's own gibs, a `'flesh'` spall burst at the
claw point, a `Radius_Quake`-scale thump, and the claw springs back 20%.

**Netplay.** §4.

### 3. Mass through lag — **BUILDABLE**

The arm's draw anchor is the controller and we cannot touch it: `GetWeaponTransform`
*replaces* the matrix (`models.cpp:223`, and it calls `loadIdentity` internally,
`hw_openxrdevice.cpp:437`). Lag is therefore expressed as an **offset from the live pose
toward the pose N tics ago** — which is exactly computable and costs nothing.

In **play** (`WorldTick`), per player per hand, keep a 10-deep ring of the hand's world pose
and of the hand's orthonormal basis (three `AttackDir`/`OffhandDir` calls — the method
`vreload.zs:217-222` already uses, and the only correct way to read hand orientation per the
study §1.3). The lagged target is
```
target = ring[now - lag] + (ring[now - lag] - ring[now - lag - 1]) * ae_loader_overshoot
```
In **`ui`** (`ModifyBobLayer3D`, per frame, interpolated by `ticfrac` between ring entries),
return `translation + ToHandFrame(target - live) / modelScale` in centimetres.

Rotation lag is the half with the sign traps the study warns about (§2.4: a three-axis Euler
inversion in a frame that is mirrored for the off hand, `hw_vrmodes.cpp:468-469`). **Named
compromise: take the cheap two axes and skip roll.** `hw_weapon.cpp:108` draws a HUD model at
`rotation + (mx/4, (my - WEAPONTOP)/-4, 0)`, so writing `psp.x = yawLag * 4` and
`psp.y = WEAPONTOP - pitchLag * 4` in **play** gives lagged yaw and pitch for two
assignments. That is precisely the mechanism `hands.zs:653-672` already uses for the dual
main-hand follow, including the thing that makes it work:

> **`oldx`/`oldy` must be carried by hand.** `ResetInterpolation()` is the only writer
> (`p_pspr.h:114`: `oldx = x; oldy = y; …`) and `hw_weapon.cpp` calls it on `firstTic` only,
> then interpolates `oldx + (x - oldx) * ticFrac` every frame. Leave them and the turn ramps
> from zero to target *inside every tic* — a shake, not a follow.

So the per-tic write is `psp.oldx = psp.x; psp.oldy = psp.y;` **then** the new values, exactly
once per tic, from `WorldTick`. The translation half has no such problem: it is returned from
`ui` and already interpolated.

**The right lag.** `ae_loader_lag` in **tics**, default **3** (86 ms at 35 Hz), range 0–8;
`ae_loader_overshoot` default **0.35**. Three tics is long enough to see and short enough that
the claw still goes where he points it. Then scale it by what the arm is carrying:
`lag = base * (1 + held.Mass / 400)`, capped at 8 — a Cacodemon doubles it, a barrel adds a
quarter. One formula, every grabbable thing, and no table.

Both of these are **renderer-read**: the translation reads them inside `ModifyBobLayer3D`,
which runs per frame in `ui` scope and is therefore live while the menu is open. That is the
hard rule satisfied where it matters most, on the one number he will spend the longest tuning.

### 4. The analogue claw — **BUILDABLE WITH A NAMED COMPROMISE**

There is no analogue trigger to read. `UserCmd` is `buttons` plus six `int16`s —
`pitch, yaw, roll, forwardmove, sidemove, upmove` (`player.zs:2-11`) — and that is the whole
input surface; `forwardmove`/`sidemove` are the movement stick and taking them would break
movement. The study's §1.6 table is complete and I found nothing to add to it.

**The compromise: closure is driven by hold time, not trigger travel.**
`closure += (triggerHeld ? +1 : -1) / ae_loader_claw_tics` clamped to 0–1, default 7 tics
(0.2 s) for a full close. The claw's drawn frame is `int(closure * (frames - 1))` — writing
`psp.Frame` from play, which is how the pulse rifle's 100-value ammo counter works
(`counter.zs:22`, `MODELDEF.ae`), so the mechanism is proven in this pack at a hundred times
this resolution.

What matters is that it is analogue **in the dimension you can see**: the jaws are at a
continuous position, the damage and the grab happen at the jaws' actual world point via
`BlockThingsIterator.CreateFromPos`, and a tap gives a different result from a squeeze. That
is everything the owner asked for except the trigger's own travel.

`A_CustomPunch(500, 72)` goes. It traces `AimLineAttack` from `self.Angle` with a random
spread (`stateprovider.zs:338-340`) — a hitscan from the player's facing, which is the single
most "it's a melee gun" thing in the file.

### 5. The rotating beacon — **BUILDABLE**

Assets confirmed: `loader_lamp.md3` is one surface, `loader_alarm`, 34 verts / 28 tris, one
frame, at `z 251.1 … 267.2` in the pickup model's frame — i.e. the top of the cab. Its
brightmap is declared on `loader_lamp.jpg` (`gldefs.txt:13-16`) and the MODELDEF binds that
same skin (`modeldef.loader.txt:81`), so **reusing the skin name keeps the brightmap for
free** — zero GLDEFS change for the glow.

**Why it does not spin by itself.** `MDL_ROTATING` and `rotationSpeed` are applied only in
`RenderModel`, the **world** path (`models.cpp:116-128` and `:175-180`). `RenderHUDModel`
(`:208-287`) has no rotation-speed handling at all. So a HUD-layer beacon must be spun by
script.

**How.** A dedicated layer (2304) whose caller is `AE_LoaderArms`, with `psp.x` advanced
`ae_loader_beacon_rpm * 6 * 4 / 35` quarter-degrees per tic, `psp.oldx` carried, wrapped at
1440 (= 360°×4). `hw_weapon.cpp:108` turns that into yaw. `oldx` carried means the renderer
interpolates it at frame rate, so the spin is smooth at 72/90 Hz off a 35 Hz write. Default
**90 rpm**.

**Can the dynamic light follow it? Partly, and better than "follow" suggests.** The existing
`PointLight LoaderLamp` is attached via `Object Loader_3D { Frame CSAWP { Light LoaderLamp } }`
(`gldefs.txt:25-28`), which keys on an **actor's sprite frame** — a psprite has none, and
`Loader_3D` in the player's inventory is not a world actor with a sprite. That is exactly why
wearing the loader gives you no light today.

The replacement is `A_AttachLight` (`actor.zs:1337`, native `a_dynlight.cpp:918`), called once
on the **player pawn** when the loader is selected and `A_RemoveLight` on deselect. Its offset
is stored as `{ofs_x, ofs_z, ofs_y}` (`a_dynlight.cpp:901` — the GLDEFS `(x, y=up, z)`
ordering, a sign trap worth writing down) and is applied rotated by the owner's angle
(`:392`: `Pos = target->Vec3Offset(m_off.X*c + m_off.Y*s, m_off.X*s - m_off.Y*c, m_off.Z + bob)`).
So the light sits above and behind the head, turns with the body, and — because HUD models
gather dynamic light from around the player (`hw_weapon.cpp:988`:
`hw_GetDynModelLight(playermo, lightdata)`) — **it washes red over the arms**, which is most
of what sells it. What it cannot do is sweep: the offset is fixed in the pawn's frame.

Nearest thing that *is* possible if a sweep is wanted: re-call `A_AttachLight` each tic with a
rotating offset. One VM call and a `MF8_RECREATELIGHTS` flag per tic per player
(`a_dynlight.cpp:913-914`) — cheap enough, but it marks the level's light list dirty every
tic, so put it behind `ae_loader_beacon_sweep` (default **off**) and let the headset decide.

**Quest cost.** One extra model index (34 verts, 28 tris — nothing), one extra HUD layer and
therefore one extra per-layer dynamic-light gather (`hw_weapon.cpp:985-1000`, inside the
per-psprite loop — this is the real cost of any new layer, not the geometry), and one extra
dynamic light in the level. One light is well inside budget; the study's warning about the
holsters was about *seven* always-on world draws, not one.

### 6. Legs, and slowing the player — **BUILDABLE WITH TWO NAMED COMPROMISES**

Evaluating the owner's own proposal — legs only, no torso, no arms, no IK, cut at the belt,
below the head, cadence from real movement speed, slowdown as a slider.

**The draw mechanism: world actor. The study is right and I confirm both halves.**
* `RenderHUDModel`'s body-anchored branch (`models.cpp:229-234`) is unreachable in VR:
  `GetWeaponTransform` returns true whenever `GetHandTransform` does, and it only fails
  without a live hand (`hw_vrmodes.cpp:455-473`). Every psprite model is anchored to a
  controller. Confirmed.
* A world actor with a model is **never** near-camera-culled. `hw_sprites.cpp:889-894`:
  ```cpp
  if (thing != camera && fabs(...) < 2 && ... && !thing->Vel.isZero() && !modelframe) return;
  ```
  The cull requires non-zero velocity **and** no model frame; a model-bearing actor fails the
  second condition whatever its velocity. The study says "zero velocity *and* a model"; the
  source says either is enough. Confirmed and slightly stronger than stated.
* The near plane is `0.5` map units (`src/common/rendering/v_video.h:294`), used for the VR
  projection at `hw_openxrdevice.cpp:232` — about 1.5 cm horizontally.
* **The scale trap is real and I confirm it:** `models.cpp:82-84` multiplies the actor's
  `Scale` by MODELDEF's. The holster ghosts' 1.2 m crate
  (`holstertable.zs:9-18`) is the precedent. `RSVR_Legs` must declare `Scale 1.0` explicitly
  in its Default block and the MODELDEF block must carry the only scale.
* **New: never give it `master` + `+MASTERNOSEE`.** `hw_sprites.cpp:832-835` would redirect
  `viewmaster` to the player and `:849-865` would then discard it entirely.

**Compromise 1 — the anchor, and the honest cost.** `HmdPosition` is raw tracking metres with
an arbitrary origin and only `.y` is usable (`hw_vrmodes.cpp:445`; the study's §1.7 is right).
The engine itself uses `mo->X()/Y()` as the hands' horizontal datum
(`hw_openxrdevice.cpp:593-594`), and `AttackPos − mo.pos` gives the *hand's* offset from the
*head*, not the head's from the pawn — so **the head's horizontal offset from the pawn is
genuinely unavailable and there is no mitigation.** "Directly below the HMD" can only be "at
the pawn, at a height derived from the measured head height".

What that costs: a physical sidestep in the playspace moves his head and not his legs, so the
legs sit up to the roomscale offset away — typically under 30 cm. For legs seen in the lower
periphery of a machine whose cab you are sitting in, I judge that acceptable, and the one
thing that genuinely helps is free: the **cage** (§item 9 below) is anchored the same way, so
the legs and the cage move together and the whole machine slides relative to his head as one
object rather than coming apart. A machine you are loosely seated in reads better than legs
that drift under a fixed cage.

**Compromise 2 — the cut, and where walk frames come from.** `loader_lower` is 2151 verts
spanning `z 0.55 … 231.36`; `loader_upper` starts at `z 108.42`. So the lower body overlaps
the upper by 123 units and **must be cut** — there is no "use `loader_lower` as-is" option
that does not put the hips and seat through the camera. `CMDL_HIDEMODEL` cannot help: it
hides a whole model index, not a surface, and a `SurfaceSkin … "empty.png"` blank (the trick
`modeldef.loader.txt:51` already uses — `empty.png` is a 3×2 RGBA image) hides the *other*
surfaces but cannot shorten this one.

So: **carve `loader_lower` at the waist, and split it left/right at the same time** so each
leg can pitch independently. The owner's tools at `C:\Users\Command\Desktop\up your ass\`
(`md3read.py`, `md3label.py`, `obj2md3.py`) can do it; **I did not run them**, and the cut
height should be chosen from a vertical vertex histogram of `loader_lower` rather than
guessed. Cut `ae_legs_overlap` (4 cm) *below* `RSVR_Body.WaistZ()` — see §4 on the belt join.

And plainly: **`loader_pickup.md3` has one frame. There are no walk frames anywhere in this
pack**, and `mechloader.md3`'s 21 frames animate the cover, arms and guard, not legs. Real
walk frames are new art. The cheap version that needs none:

Two actors, one per leg, each carrying its half of the carved mesh, pitched counter-phase
about the hip by `±ae_legs_swing` degrees (default 12) with `UseActorPitch` declared in the
MODELDEF — which the study correctly notes is the thing the holster blocks forgot
(`models.cpp:132-137`, `:897-907`). A machine with piston legs reads perfectly well as a
rigid fore/aft stride; this is not a human gait and should not pretend to be.

**Cadence from real speed, never a rate.** `phase += vel.XY.Length() / ae_legs_stride * 360`
per tic, where `ae_legs_stride` is a measured length (leg length × 0.8), so the legs stop when
he stops and double when he runs, with no animation clock anywhere. Yaw is `mo.Angle`.
Strafing: use the full `vel.XY` magnitude so a strafe strides too, plus an optional lean
`atan2(cmd.sidemove, cmd.forwardmove) * ae_legs_lean` (default 0.3) on the legs' yaw so they
angle into it. The lean is taste; the cadence is measurement.

**Live or latched height.** Track the hip **live** — `vr_crouch_use_button 0` drives
`crouchfactor` from the HMD height every frame (`hw_openxrdevice.cpp:574-579`), so a physical
crouch should drop the hips. But latch the leg *length* when the loader is selected, or the
legs rubber-band. Then clamp: `hipZ = max(waistZ, mo.pos.z + legLength)` — so crouching drops
the hips until the legs are straight and then stops, which is what a mech does and what keeps
the feet off the floor's other side.

**The speed slider.** `AE_LoaderWorn.GetSpeedFactor()` returning `ae_loader_speed`, default
**0.35** (preserving the number the DECORATE *intended*), range **0.20 – 1.00**, step 0.05.
Reduced further while carrying: `× (1 - 0.3 * held.Mass / ae_loader_grab_mass)`.

On the hard rule: this is read in **play**, inside `TweakSpeeds` → `MovePlayer`, which is
where it takes effect. The rule exists because a menu freezes the playsim and a script-read
slider then appears dead while you look at it — but **movement cannot be judged with the menu
open at all**, so there is no reading of this slider that the rule would improve. The rule
bites on things you *see*, and for the loader those are: the arm lag (read in
`ModifyBobLayer3D`, `ui`, per frame — correct), the beacon spin (`psp.x`, play, but visibly
spinning so a stale value is obvious), and the cage opacity (read in `ui`).

**The one slider the rule genuinely cannot be satisfied for**, and it must be said rather than
hidden: anything that positions a **world actor** — leg height, leg scale, cage standoff —
is written from `WorldTick`, which does not run while the menu is open. Mitigations in order
of preference: (a) derive it from measurement so no slider exists — which is what
`RSVR_Body` does for the leg height, and is the owner's own "measure it, do not ask" rule;
(b) for anything left over, a `StaticText` in the menu saying it applies on close. Do not
pretend otherwise.

**Generality: yes, and it is not the loader's.** `RSVR_Legs` is "legs under the player",
a general capability with a swappable mesh per wearer — the loader's legs now, a marine's
legs later, and it is the only part of the VR body problem you can actually see. Named for
what it does. The loader is its first caller and sets `RSVR_Legs.SetMesh()` and nothing else.

### 7. Weight cues — **BUILDABLE**, and the sounds already exist

* **`Radius_Quake` per footstep, scaled by speed.** In-pack idiom: `Radius_Quake (1, 2, 0, 1, 0)`
  appears 20 times in `actors/weapons/shotgun.txt` and `smartgun.txt`. From ZScript use
  `A_Quake(intensity, duration, damrad, tremrad, sfx)` (`actor.zs:1283`) with **`damrad 0`** so
  it can never hurt anyone, `tremrad ~ 256`, and `intensity = clamp(1 + speed/12 + heldMass/400, 1, 3)`.
  Footsteps derive from `mo.vel`, which **is** playsim, so they need no net event and are
  deterministic on every machine — and everyone in `tremrad` feels the loader coming, which is
  correct and free.
* **Hydraulic whine pitched by arm speed — follow the saber's curve, do not invent one.**
  `UltraBadassQuestSaber.pk3`'s hum is re-asserted every tic on a dedicated channel and its
  pitch tracks blade speed (`saber_zscript.txt:920`):
  `owner.A_SoundPitch(ch, 1.0 + clamp((speed - 6.0) / 60.0, 0.0, 0.3))`.
  Copy that shape with the loader's own references (a boom moves faster than a wrist, so
  divide by `ae_loader_hum_ref`, default 90 rather than 60). Copy the two hard-won lessons in
  that file verbatim: **the per-tic re-assert is the line that wins**, because a volume set
  only where the loop starts silently reverts; and **zero volume must stop the channel**,
  because `SoundEngine::StartSound` refuses `volume <= 0` and a loop started at zero leaves no
  channel for the re-assert to act on.
* **A servo clunk when an arm stops hard.** `speedWas > ae_loader_clunk` and this tic's speed
  under a third of it → one `ae_loader_clunk` sound plus a **per-hand** `Buzz()` in that arm
  (§0 correction 1). Rate-limited the way the saber rate-limits its whoosh
  (`swingQuiet = max(ubqs_swing_gap, 1)`, `saber_zscript.txt:958-960`).
* **The swing whoosh**, same source: volume `clamp(speed / 24, 0.5, 1.0)`, pitch
  `clamp(0.85 + speed / 60, 0.85, 1.35)` (`:961`), with the references scaled up for a heavier
  arm so the loader reaches full volume later and never gets as high-pitched.

**What exists and what does not.** The loader's own TC sounds are `SYNTPN2` and `LODRALTF`
(`actors/weapons/mechloader.txt:33`, `:56`). `sndinfo.txt:73-78` already defines
`melee/hitwall` as a random set of `DSMETALB`, `MET04`, `DSPUNCH2`, `FOOTWALL` under the
comment `//Loader attack` — that is the claw-on-wall sound, already here and already aliased.
`SNDINFO.rsr` carries the metal/magazine-drop sets.

**Genuinely missing: a hydraulic hum loop, a servo clunk, and a strain whine.** Three sounds.
`FOOTWALL` and `DSMETALB` will stand in for the clunk at build time; the hum is the one that
cannot be faked from a one-shot. Recommend `rsr/magdrop_big`'s heavier samples as a temporary
strain and flag the hum as the pack's one audio gap.

### 8. Diegetic — **BUILDABLE**

* **No crosshair.** `crosshair` is a non-mod cvar and ZScript cannot write it
  (`vmnatives.cpp:947-955`). Two mod-side routes that do work: give the weapon
  `Weapon.Crosshair 0` — but `Loader_3D` is DECORATE, so add the property there, one line;
  or override `StatusBar.DrawCrosshair`, which needs the pack's own statusbar. The DECORATE
  property is cheaper and exact.
* **No weapon HUD.** The pack ships `sbarinfo.txt`; suppress the weapon block when the worn
  token is present. One conditional.
* **Getting in as a moment, not a weapon select.** The current `Select` does `A_Raise`,
  `A_SetGravity(3)`, `A_SetSpeed(0.35)` and the ACS `LOADUP` (which sets `APROP_ViewHeight`
  to 61 — `SOURCE.acs:1544-1547`, i.e. it already raises the camera 20 units, so the player
  is already *standing up* into the cab and nobody has noticed). The moment is: hold the view
  rise over ~25 tics instead of instantly, run the arms in from stowed over the same window
  via the claw-closure layer frames, bring the hum up from zero, spin the beacon up from rest,
  and buzz both hands once on the latch. No new asset, no new state machine — a ramp on four
  numbers that already exist.

### 9. The cage over the head — **BUILDABLE WITH A NAMED COMPROMISE**, and it needs his eyes

**Geometry.** `MechGuard.001` is the cage (§0 finding 3): 69 cm forward of the operator,
61 cm wide, 104 cm tall, symmetric. `MechCover` is the roof grate above it. Both are already
in `mechloader.md3`, already skinned, already shipped.

**How it is drawn: a world actor on the body frame, at head height.** Same reasoning as the
legs — the psprite path cannot be body-fixed in VR, a world model near the eye is not culled,
it is depth-sorted so it is correctly occluded, and it takes full `Angle`/`Pitch`/`Roll`. It
**must not** follow the gaze: it is bolted to the machine. Anchored at `mo.pos.xy` with
`Angle = mo.Angle` and `z` from `RSVR_Body`'s shoulder line, it does exactly that — it stays
put as he looks around, and it swings when he turns his body.

**Where the geometry comes from: carve it.** Two options weighed:
* *Reuse `mechloader.md3` whole with `MechArms.001` blanked by a `SurfaceSkin … "empty.png"`.*
  No mesh work; the trick is already in this file. But it transforms 3590 unwanted vertices
  every frame and submits an empty surface draw, on a Quest, on an always-visible object.
* *Carve `loader_cage.md3` = `MechGuard.001` + `MechCover`, 1263 verts.* **Recommended** — and
  it is the same carving session as the arms (§0 finding 2), so it costs nothing extra.

**The damage reduction: `Inventory.ModifyDamage`, passive.** `ModifyDamage` is the right hook
and `AbsorbDamage` is the wrong one. Evidence from the pipeline in `p_interaction.cpp`:
```
:1218-1223  source->GetModifiedDamage(..., passive=false, ...)   // the attacker's modifiers
:1229-1232  target->GetModifiedDamage(..., passive=true, ...)    // ← the cage goes here
:1233-1236  target->ApplyDamageFactor(...)
:1363-1370  player->mo->AbsorbDamage(...)                        // armour, players only
```
`GetModifiedDamage` walks the whole inventory chain calling each item's `ModifyDamage`
(`p_mobj.cpp:8083-8097`). So the cage takes its percentage **before** damage factors and
**before** armour.

**That ordering is the answer to "what happens with armour", and it is the good one.** The
cage is outside the armour, which is physically what it is: the machine stops a fraction, then
the player's own factors and armour work on what is left. Because the cage's effect is a
*percentage* and armour's is a mix of percentage and absolute, nothing stacks pathologically
in either direction and the result can never go negative.
```zscript
override void ModifyDamage(int damage, Name damageType, out int newdamage,
                           bool passive, Actor inflictor, Actor source, int flags)
{
    if (!passive || damage <= 0) return;
    double a = clamp(CvF('ae_loader_cage_absorb'), 0.0, 0.9);   // default 0.40
    newdamage = max(1, int(damage * (1.0 - a)));                // never a free hit
    Spark(damage - newdamage, inflictor, source);
}
```
Cap it at 0.9 in code so no slider can make the player invulnerable. `newdamage` floors at 1
so the cage never silently eats a hit entirely — a hit that does nothing reads as a bug.

**The sparks — and `ModifyDamage` knows where the hit came from.** It is handed both
`inflictor` and `source`, so the bearing is `(inflictor ? inflictor : source).pos − mo.pos`.
Spawn the spark on the cage shell at that bearing: a world actor at
`mo.pos + bearing.Unit() * cageRadius`, carrying `mechaloader_spark.md3` — already shipped,
**20 surfaces over 11 frames** of electric arc. A hit from behind sparks behind you, for free.

Two things to know before reusing that model. First, its block declares
`SurfaceSkin 0 0 "empty.png"` (`modeldef.loader.txt:51`) with the real skin commented out on
the line above — surface 0 is `spark_ball1` (136 verts, 240 tris), the largest, deliberately
blanked because a glowing ball is wrong for an arc. Keep it blanked. Second, **20 surfaces is
20 draw calls per spark instance** (`models.cpp:631-637` loops model indices; an MD3's
surfaces are submitted per surface), so a spark must be short-lived and capped. Spec: 6 tics
(the 11 frames at 2 tics each is too long for a hit flash), one at a time per player, and skip
it entirely if one is already alive. Alternative that costs almost nothing and should be the
default: the pack's own particle spall (§5) with the `'metal'` material — 8 additive sparks
and 3 dust particles, no actor, no draw call. **Recommend particles as the default and the
arc model behind `ae_loader_cage_arc` (default off) until he has looked at it.**

**Does it block the view? This is the risk and it needs the headset.** The honest numbers:
the cage is 61 cm wide and its front face is 69 cm ahead of the operator. At 69 cm, a 61 cm
width subtends about 48° — so the uprights sit at roughly ±24°, comfortably outside the
central field but inside the horizontal sweep of a glance. The roof grate at 80–95 cm above
the origin is above a seated or standing head and should read as a ceiling, not a lid. What
keeps it readable:
* **Nothing within 15 cm of the eye.** The near plane is only 1.5 cm, so geometry *can* get
  that close; the constraint is comfort, not clipping. A standoff cvar
  (`ae_loader_cage_fwd`, default 0, range −20…+20 cm) lets him push the whole cage away.
* **An opacity cvar, read in `ui`.** A world actor's `Alpha` is play-written, so this one is
  the world-actor slider problem again. Use `RenderStyle "Translucent"`… **no**: a non-Normal
  RenderStyle model is drawn without depth even at Alpha 1 (a standing finding in this
  family). Keep `RenderStyle Normal` and give the thinned-down look by *geometry*: if he finds
  it oppressive, the answer is to carve the uprights out and keep only the roof and the two
  front posts, not to make it transparent.
* **An on/off cvar** `ae_loader_cage` (default on), because this is the one element where
  "I hate it" is a plausible headset verdict and it must be one toggle away from gone.
* Flag it clearly: **the cage is the only part of this design I would not ship without the
  owner wearing it first.** Everything else fails visibly; this one fails by making him
  nauseous twenty minutes in.

**How it reads when it breaks — cheap, and it gives the machine a condition.** Accumulate
absorbed damage in the token. Three bands off one integer:
* under `ae_loader_cage_hp` × 0.5: as above.
* over 0.5: a spark every `random`-free fixed interval (use `Level.maptime % 35`, not RNG —
  see §4), the hum gains a rough low harmonic via `A_SoundPitch` wobble, the beacon's light
  flickers by re-calling `A_AttachLight` with a lower radius on alternate seconds.
* over 1.0: **absorption drops to zero and the sparks become continuous.** The cage is still
  drawn — a broken cage you are still inside is better than a cage that vanishes — but it no
  longer protects. One integer, three bands, no new asset, and the player learns the
  machine's health by looking and listening rather than by reading a bar.

---

## 3. Architecture

### 3.1 Classes

New **general** capabilities in `zscript/rsvr/`, none named for the loader, each usable by a
second caller without modification:

| class | file | what it does |
|---|---|---|
| `RSVR_Body` | `rsvr/body.zs` | the body frame. Per tic per player: `eyeM = HmdPosition.y + vr_height_adjust`; cached `vu` and `pixelstretch`; `WaistZ()` / `ChestZ()` / `ShoulderZ()` as fractions of `eyeM` above `mo.pos.z`; `Yaw()`, `Fwd()`, `Left()`; `AnchorWorld(fwdCm, sideCm, heightFrac)`; `ReachCm(anchorWorld, hand)`; `ToCm(worldDelta)` / `FromCm(cm)`. |
| `RSVR_HandMotion` | `rsvr/handmotion.zs` | the saber's swing method, generalised. Per player per hand: a 10-deep ring of `handPos − bodyAt`, the body step subtracted, snap-turn amnesia, the 3-tic max window; `SpeedAt(hand, lenCm)` for a point `lenCm` out along the hand axis; `PoseAgo(hand, tics)` for the lag. |
| `RSVR_HandNet` | `rsvr/handnet.zs` | the shield saw's publish-pose pattern, portable. Local poll → quantised net events → playsim fields on every machine; accessors fall through to the live local pose in single-player. |
| `RSVR_Carry` | `rsvr/carry.zs` | grab / carry / throw / pin / crush, and the thrown-actor tracker. Per player per hand. Filter and curves from cvars; knows nothing about loaders. |
| `RSVR_Legs` | `rsvr/legs.zs` | two pooled world actors under the player, mesh set by the caller, cadence from `mo.vel`, anchored to `RSVR_Body.WaistZ()`. |

Loader-specific, in `zscript/ae/loader.zs`:

| class | base | role |
|---|---|---|
| `AE_LoaderArms` | `Inventory` | owns the **main-controller** layers. The loader's `RSQ_GunSide`. Nothing else. |
| `AE_LoaderWorn` | `Inventory` | the worn token. `GetSpeedFactor()` (the slowdown), `ModifyDamage()` (the cage), the cage-condition integer, and `DoEffect()` for the hum. Given on `Select`, taken on `Deselect`. |
| `AE_LoaderHandler` | `EventHandler` | the per-tic brain: claw closure, the lag ring, layer states, the beacon's `psp.x`, the footsteps, the net-event send and receive. |
| `AE_LoaderCageActor` | `Actor` | the cage world model. |
| `AE_LoaderPlace` | abstract | `Places(owner, layer)` / `Place(...)` — the two statics `RSQ_Place.Layer` dispatches to. |

The loader stays `Loader_3D` / `AELoader_3D` in DECORATE. It must **not** become ZScript: it
is the ready weapon, so nothing needs a virtual on it, and converting it would break the TC's
`replaces` chain and its `LBerserk_3D` pickup path for no gain.

### 3.2 Layers

Verified in use across the pack: **2100, 2101, 2102, 2103, 2104, 2120, 2121, 2122, 2123,
2130, 2200, 2201, 2202, 2203, 2210** (`hands.zs:204-212`, `vreload.zs:24-30`,
`rsr_pump.zs:42-48`). The 2300 band is clean. `PSP_TARGETCENTER = INT_MAX - 2` (`p_pspr.h:58`)
bounds the draw loop, so 2300-level ids are fine.

| id | const | caller | controller | contents |
|---|---|---|---|---|
| 2300 | `ARM_MAIN` | `AE_LoaderArms` | main | `loader_arm_r.md3` |
| 2301 | `ARM_OFF` | `RSQ_Hands` | off | `loader_arm_l.md3` |
| 2302 | `CLAW_MAIN` | `AE_LoaderArms` | main | claw, frame = closure (only if the claw is carved out of the arm; otherwise the arm layer's own frame carries it and 2302/2303 go unused) |
| 2303 | `CLAW_OFF` | `RSQ_Hands` | off | ditto |
| 2304 | `BEACON` | `AE_LoaderArms` | main | `loader_lamp.md3`, yaw from `psp.x` |
| 2305-2309 | — | — | — | reserved. **The held thing is a world actor, not a layer** — it must be depth-sorted against the level or a pinned monster would draw through the wall it is pinned to (`hw_models.cpp:86-92` squashes HUD depth into `[0, 0.3]`, so HUD models can never be occluded). |

All layers get `bAddBob = true` (required: `hw_weapon.cpp:953` gates `ModifyBobLayer3D` on
`PSPF_ADDBOB`) and `psp.y = WEAPONTOP` at creation, because a layer left at `y = 0` is tilted
8° (`(0 - 32) / -4`). Reuse `RSQ_HandHandler.SetLayer` (`hands.zs:693-718`) verbatim — it
already does all of this, including only touching a layer when its state actually changes.
`bAddWeapon` stays **false** for all of them: the loader has no Offset animation to inherit
and `:432-436` would add the gun layer's x/y on top of our lag.

### 3.3 The single integration point

`RSQ_Place.Layer` (`hands.zs:81-104`) already dispatches to `RSP_Handler` and `RSR_Handler`
by layer range. One more clause, in the same shape, before the hand-layer tests:

```zscript
if (AE_LoaderPlace.Places(owner, layer))
{
    Vector3 pt, pr;
    [pt, pr] = AE_LoaderPlace.Place(owner, translation, rotation, layer, ticfrac);
    return pt, pr;
}
```

That is the **whole** edit to the hands system — five lines in one function. `hands.zs`'s own
behaviour while the loader is worn needs no change, because `RSQ_HandTable.Index(Loader_3D)`
is 0 and the existing code hides every hand layer on a zero index.

### 3.4 MODELDEF

`modeldef.loader.txt`, keeping every existing block (the pickup blocks are still needed for
`LBerserk_3D` / `AEBerserk_3D`; the dead `CSAW P` blocks on `Loader_3D` / `AELoader_3D` can go
or stay):

* `Model AE_LoaderArms` — one block per layer state. Main arm: `Model 0 "loader_arm_r.md3"`,
  skins as the fixed `loader_upper.png`, `Scale -1.0 1.0 1.0`, `Offset -10.0 40.0 -10.0`
  (the existing held-model values, which already work).
  Off arm: `Model 0 "loader_arm_l.md3"` — **the off-hand frame is mirrored by the engine**
  (`hw_vrmodes.cpp:468-469`: `if (!hand && autoReverse) out->scale(-1,1,1)`), so the off
  block almost certainly wants `Scale 1.0 1.0 1.0` and an `Offset` with the x sign flipped.
  That sign is not derivable from source; settle it with one render on the rig.
  Beacon: `Model 0 "loader_lamp.md3"`, `Skin 0 "loader_lamp.jpg"` (keeps the brightmap).
* `Model RSVR_Legs` — the carved legs, world path. `UseActorPitch`, `UseActorRoll`,
  `Scale 34 34 28.33` at defaults (`vu` horizontally, `vu / pixelstretch` vertically), and the
  actor's own `Scale 1.0` declared explicitly so the multiply at `models.cpp:82-84` is a
  no-op.
* `Model AE_LoaderCageActor` — `loader_cage.md3`, same world-path scale rules,
  `UseActorPitch`/`UseActorRoll`.

Reminder from the handoff that still applies: a MODELDEF block binds to the **exact** class;
subclasses inherit nothing. And a sprite name a state references needs no lump — the counter
proves it (`RSQ_CounterSprites` exists only so the sprite names resolve, `counter.zs:27-38`);
do the same with an `AE_LoaderSprites` actor.

### 3.5 GLDEFS

Almost nothing. The beacon's brightmap is already declared on `loader_lamp.jpg`
(`gldefs.txt:13-16`) and reusing that skin name keeps it. The worn beacon's **light** comes
from `A_AttachLight` on the pawn, not from a GLDEFS `Object` block, because an `Object`/`Frame`
light keys on an actor's sprite frame and a psprite has none — which is the diagnosis of why
`PointLight LoaderLamp` at `gldefs.txt:18-23` lights only the dropped pickup today.

Keep `PointLight LoaderLamp` exactly as it is (the pickup still uses it) and pass its numbers
to `A_AttachLight` by hand: `type = DynamicLight.PointLight`, `color = (255, 51, 51)`,
`radius1 = radius2 = 60`, `ofs` in the **GLDEFS `(x, y=up, z)`** order, because
`a_dynlight.cpp:901` stores `{ofs_x, ofs_z, ofs_y}`. Or simpler and less error-prone:
`A_AttachLightDef('loaderbeacon', 'LoaderLamp')` (`actor.zs:1336`), which copies the GLDEFS
definition wholesale and keeps one source of truth for the colour — at the cost of taking that
definition's `Offset 5 75 5` as-is.

### 3.6 Input map, both arms, no new binds

`RSR_Guns.Index(Loader_3D) == 0` and `RSP_Guns.Index == 0`, so **no reload system is running
and no reload button is claimed** while the loader is worn. That is what makes room for two
arms with multiple modes each.

| arm | input | bit / source | action |
|---|---|---|---|
| main | motion of the **claw point** | `RSVR_HandMotion` | **SWING** above `ae_loader_swing` |
| main | trigger held | `BT_ATTACK` | claw CLOSES; closing near a target = **GRAB**; ≥0.9 for `crush_tics` on a held target = **CRUSH** |
| main | trigger released, arm moving | `BT_ATTACK` edge | **THROW** at the claw's measured speed |
| main | trigger released, arm still | `BT_ATTACK` edge | **DROP** |
| main | grip **+** trigger | `BT_ALTATTACK` (`vr_secondary_button_mappings`) | **SLAM** — the existing `AltFire`/`AltHold` arc and `A_Explode`, kept |
| off | motion of the off claw point | `RSVR_HandMotion` | **SWING** |
| off | off trigger held | `BT_OFFHANDATTACK` (1<<26) | the same close/grab/crush ladder |
| off | off trigger released | `BT_OFFHANDATTACK` edge | **THROW** / **DROP** |
| off | off grip + off trigger | `BT_OFFHANDALTATTACK` (1<<27) | **SLAM** |
| — | off grip alone | raw keys 443/436 | **unused by the loader.** The engine's steady owns it; see §2 item 1's compromise. |
| — | `BT_RELOAD` / `BT_OFFHANDRELOAD` / `BT_USER1..4` / Pad_B | — | **left free.** Nothing the loader does needs them. |

Collision audit:
* **The reload:** nothing runs. `rsr_grab_buttons` defaults to `BT_OFFHANDATTACK`, which the
  loader also uses — but `RSR_State.phase` is `IDLE` throughout and `MagRelease` returns early
  on `!Wanted(mo)` (`vreload.zs:930`), which requires `RSR_Guns.Index(w) > 0`. No overlap.
* **The pump:** same, via `RSP_Guns.Index`.
* **`melee.zs`:** gated to the two knives at `melee.zs:116`. No overlap, but assert it.
* **`flick.zs`:** **does** collide and must be gated (§2 item 1).
* **`dual.zs`:** must refuse the loader (`ae_dual_*` has no loader entry; add an explicit
  refusal so a future entry cannot break the arms).
* **The engine's steady:** the only real collision, and it is the off grip, which the loader
  deliberately does not use.
* **`switchhand`** (`g_game.cpp:335-350`) calls `PlayerPawn.SwitchWeaponHand` — if the player
  presses it while worn the arms would swap owners and therefore controllers. `ae_lefthanded`
  already exists and does exactly that intentionally (`hands.zs:549-550`); make the loader read
  the same cvar so handedness works and nothing else can move it.

`RSQ_Hands` keeps `Fire: TNT1 A 1; Goto Ready;` so the engine's own handling of
`BT_OFFHANDATTACK` on the off-hand weapon does nothing while we read the bit ourselves.

### 3.7 The body frame: build it first, as its own thing

**Recommendation: its own step, built before the legs and consumed by them — and by the
loader's cage, and by the belt if it ever ships.** Not "step one of the loader".

Two reasons. First, it is the study's own number-one recommendation made independently of the
loader, and it fixes the 1.447 m datum error for the holsters too
(`STUDY §3.2`, which I confirm against `hw_openxrdevice.cpp:585-610`). Second, it *removes*
code: `vrhand.zs:79-91` (`SteadyGap`), `vreload.zs:302` (`below = (viewz - op.z) * ps * 100 / vu`),
`melee.zs:100-113`, `flick.zs:56-70` and `holster.zs:119`/`:159` each re-read the same cvars
and redo the same conversion. One class, and five duplications go.

**Its interface is the answer to "why the legs should not invent an anchor."**
`RSVR_Body.WaistZ()` is both the legs' cutoff height **and** the belt's anchor, by
construction. `RSVR_Body.Yaw()` is the shared basis, so belt, legs and cage turn together.
`RSVR_Body.eyeM` is the shared scale, so a tall player and a seated player get legs of the
right length with no per-feature slider.

**Does anchoring legs to the waist create a new problem?** One, and it is answered above:
crouching. Track the hip live, latch the length, clamp with
`hipZ = max(waistZ, mo.pos.z + legLength)`.

**Would a belt clip or z-fight at the join?** Only if two coincident horizontal surfaces meet
at the same `z`. Prevented by construction rather than by a tuned number: the legs' carved top
is cut `ae_legs_overlap` (4 cm) **below** `WaistZ()`, and the belt sits **on** `WaistZ()` with
its own 18 cm vertical extent (`STUDY §5`: every belt island spans the full 18 cm `y` range)
straddling it. The belt's lower skirt then overlaps the legs' top by about 5 cm and hides the
cut. Both numbers are offsets *from the same line*, so there is nothing to keep in sync.

---

## 4. Netplay

The rule is the owner's: netplay must never desync, and VR + desktop co-op on the same exe and
the same mod list is a stated target for this family.

**The hazard, precisely.** `AttackPos`, `OffhandPos`, `AttackDir`, `OffhandDir` and
`HmdPosition` are written in `VRMode::SetUp()` on the render path, once per frame, **only for
the local camera's player** (`hw_vrmodes.cpp:432-447`, which also sets `PlayInVR` and
`OverrideAttackPosDir`). On every other machine they are stand-ins. Anything that changes the
playsim from them diverges. `RS_ShieldSaw`'s header states this exactly
(`rs_shieldsaw.zs:71-76`) and it is right.

**The boundary.**

*Local only, never touches the playsim:* the lag ring; the layer placement
(`ModifyBobLayer3D`, `ui`); the beacon's `psp.x`; the legs' and cage's placement; the swing
whoosh and hum for the local player; the claw's drawn frame.

*Must cross as a net event, the way `vreload.zs:948-1007` does it:*
1. **The claw point**, every other tic while either claw is closing or holding — two events
   (position and angles) in thousandths, as `rs_shieldsaw_state.zs:665-680` does, because a
   `ConsoleEvent` carries three ints and a pose is five. Halving the rate halves the traffic
   and is well inside the window for a 40-unit claw radius.
2. **GRAB** — and the cheap, robust form: send the *claw point*, and let every machine run the
   same `BlockThingsIterator` against that published point with the same predicate. Nothing
   needs an actor id, nothing needs a lookup table, and the answer is identical everywhere
   because the iterator walks the blockmap in a fixed order.
3. **RELEASE**, carrying the launch velocity in thousandths of a map unit per tic — the shield
   saw's `rs-ss-throw` pattern verbatim, including riding extra values in the event *name* when
   three ints are not enough (`rs_shieldsaw_state.zs:621`).
4. **CRUSH** — the decision, because it calls `DamageMobj`.
5. **SWING** — the decision, the claw point and the speed, because it damages.

*Deterministic on every machine from playsim state, needing no event:* the footsteps and their
`A_Quake` (derived from `mo.vel`); the thrown-actor tracker once launched; the cage's
`ModifyDamage` (damage is playsim); the carry spring (the published claw point is playsim once
the event has landed).

**And the sharp edge.** The pack's effect code draws playsim RNG —
`random[rsqb]` / `frandom[rsqb]` throughout `RSQ_Ballistics.Spall`
(`zscript/rsq/ballistics.zs:140-213`), which is exactly why `rsq_ballistics` is a **server**
cvar and not a user one, and the file says so (`:19-20`). So **every loader effect must be
spawned on the net-event path, not on the local detection path.** A spark fired where only one
machine decided to fire it advances that machine's RNG stream and nothing else's, and the next
monster to roll a pain chance disagrees. Where an effect genuinely has no gameplay trigger —
the cage's condition sparks — use `Level.maptime % N` and no RNG at all.

**The one honest asymmetry.** `RSVR_VRHand.InVR(mo)` gates the entire loader; a desktop co-op
player holding it gets the TC's existing one-handed behaviour, unchanged. Same exe, same mod
list, different presentation, and the playsim agrees because every gameplay decision arrives as
a net event either way.

**A pre-existing co-op hazard worth recording, not ours to fix.** `vrmode->Vibrate(...)` in
`p_mobj.cpp:7555` and `p_map.cpp:4771` takes no player argument, so it buzzes the **local**
device whenever *any* player's missile spawns or hitscan lands. Every gun in this pack already
has this. The loader will make it more noticeable. The right answer — gating the buzz on
`mo.player == players[consoleplayer]` — cannot be done mod-side without spawning `RSVR_Buzz`
on some machines and not others, which is a real desync. Keep the existing pattern (spawn
everywhere) and raise the gate as an engine item for the family's own fork.

---

## 5. Effects: everything the loader needs is already in this pack

The pack ships a **surface-aware impact system**: `SURFACES.ae` (79 lines of texture-family
rules: metal, wood, glass, tech, brick, marble, tile, dirt, liquid, slime, lava, pipe, screen,
light) plus `zscript/rsq/ballistics.zs`, whose `Impact(tracer, from, dir, dist)` traces to the
surface, resolves the material, and `Spall(at, normal, material)` throws per-material dust,
sparks and 3D chips through `Level.SpawnParticle` with hard caps
(`MAX_DEBRIS 64`, `MAX_TRACERS 24`).

**So the answer to (a)/(b)/(c) is (c) for both packages — and nothing is lost.**

| loader effect | source | cost |
|---|---|---|
| cage absorbs a hit | `Spall(..., 'metal')` — 8 additive sparks + 3 dust, no actor. `mechaloader_spark.md3` behind `ae_loader_cage_arc`, default off (20 surfaces = 20 draw calls) | particles only |
| claw strikes a surface | `RSQ_Ballistics.Impact()` at the claw point — correct material, correct normal, already written | one `LineTrace` + particles |
| crush kill | the engine's own `XDeath` gibs + `Spall(..., 'flesh')` | free |
| thrown barrel detonates | the barrel's own `A_Explode` and `DeathSound "world/barrelx"` | free |
| thrown body lands | `Impact()` at the contact point + the set's own gore via `SetStateLabel("XDeath")` | free |
| footstep | `Spall(footPos, (0,0,1), material)` with `dust` scaled by speed, plus `A_Quake` | particles only |
| hydraulics venting | a slow `Spall` with the `'liquid'` colour and upward velocity, or 2 particles a tic | particles only |
| arm stops hard | `Spall(clawPos, -dir, 'metal')` with `sparks` only | particles only |

What this needs: a **static entry point** on `RSQ_Ballistics` so the loader can call
`Impact`/`Spall` whether or not `rsq_ballistics` is on — the loader's effects must default
**on** (the owner's standing rule) while that cvar defaults off and is a *server* cvar about
the guns' look. Factor `Spall` into `RSQ_Impact.At(Actor from, Vector3 at, Vector3 dir, double dist)`
and `RSQ_Impact.Spall(...)`, both respecting the existing debris cap. That is a refactor of
~20 lines in one file and it makes a general capability out of something currently private to
one cvar.

A nice detail already in place: `RSQ_Ballistics.IsMelee` matches on the keyword list
`{ "kick", "fist", "punch", "melee", "strike", "knife", "claw", "loader", "step", "stomp", "crush" }`
(`ballistics.zs:69`) and `MeleeHeld` already names `Loader_3D`, `AELoader_3D`, `LBerserk_3D`,
`AEBerserk_3D` (`:84-85`). **Name the loader's strike actor with one of those words** —
`AE_LoaderClaw` contains "claw" — and it is automatically excluded from projectile trails with
no edit.

### Why not RS_CombatFX or RS_Ballistics

**RS_CombatFX: do not carry it in, and there is a name collision to record.** The relevant
categories are small (`sparks` 84 KB, `puffs` 380 KB, `smoke` 1.2 MB, `explosions` 676 KB,
`blast` 329 KB, `hitflash` 227 KB — about 2.9 MB of art for everything on the list above,
on a 24.6 MB pack). Affordable. But it buys nothing the pack cannot already do with particles
and the surface table, and:

> **`RSC0`, `RSC1`, `RSC2` and `RSC3` collide.** RS_CombatFX's `casings` category uses
> `RSC0`–`RSC4`; this pack uses `RSC0`–`RSC3` as the pulse rifle's ammo-counter sprite keys
> (`MODELDEF.ae:72+`, 100 blocks; `hands.zs:230-328`; `counter.zs:27-38`). I intersected all
> 142 CombatFX ids against every sprite key in the pack: **those four and nothing else.**
> Copying the `casings` category in, or loading RS_CombatFX alongside this pack, makes those
> sprites real — and then a CombatFX casing at `RSC0 A` draws the Aliens counter *model*, and
> the counter's blocks fight real sprite lumps. Either rename the counter keys (100 MODELDEF
> blocks and 100 state labels, generated by `tools/md3_counter.py`, so mechanical) or do not
> bring the casings in. **Recommend: do not bring them in**, and record the collision here so
> the next session does not hit it blind.

**RS_Ballistics: cannot be a dependency, and its Service answers the question properly.**
It does expose exactly the interface the brief asks about — `class RSB_Service : Service`
(`zscript/rsb/service.zs:35`), documented for callers as
`ServiceIterator.Find("RSB_Service").Next()` and explicitly "for packages that want to work
with or without it" (`:1-10`). `Service` / `ServiceIterator` are stock GZDoom 4.14, so Quest
17.3 can call it, and `rsb/recoil.zs:79-85` shows the right discipline: `ServiceIterator.Find`
matches on **substring**, so compare `GetClassName()` exactly or a near-miss answers first.

But RS_Ballistics is written against our own fork: its README itself annotates features as
"(engine smoke volume)", "(engine collision and debris pool)", "(engine surface damage)",
"(engine effect lights)", "(engine emissive volumes)". It is not a candidate for the Quest.

**So: use the Service *pattern*, not the package.** If the loader ever wants another pack's
effects, ask by Service name with an exact class-name check and fall back to
`RSQ_Impact.Spall`. Today there is one pack on the Quest, so a plain class is cheaper — the
study's own conclusion about `RS_WeaponMountService`, and it holds here.

### The two reference mods, and where they actually apply

**`UltraBadassQuestSaber.pk3` — use its method, it runs on this engine.** I checked every
engine identifier it touches (`AttackPos`, `OffhandPos`, `AttackRoll`, `PlayInVR`,
`psp.alpha`, `A_SoundPitch`, `A_SoundVolume`) and all are stock at 9afc750. Four things to
copy, with their line numbers:
* `saber_zscript.txt:924` — the speed is the **tip's**, less the **body's step**:
  `double speed = lastOk ? ((tip - lastTip) - bodyStep).Length() : 0.0;` with
  `BodyAt(o) = (o.pos.x, o.pos.y, o.player ? o.player.viewz : o.pos.z + 41.0)` (`:786`) and a
  48-unit teleport guard (`:860`). This is the fix for "it makes the swing sound every time I
  take a step".
* `:789-796` — `HandVel()` takes the **fastest of the last three single-tic steps**, so a
  quick flick counts as much as a long swing.
* `:862-872` — a snap turn or a jump **wipes the motion history** (`snapQuiet = 2`, the ring
  flattened), because otherwise a turn registers as an attack. The in-file comment is honest
  that the `ubqs_snap_turn_deg 8` threshold is a workaround and that telling a snap from a
  fast smooth turn is the real fix — inherit the workaround and the caveat.
* `:954-963` — the threshold cvar and the audio curves.

**The one change the loader needs, and it goes the opposite way to intuition.** The saber
measures a ~1 m blade tip. The loader's claw is **2.28 m** from the hand (`MechArms.001`,
§0), so the same wrist rotation moves the claw more than twice as far. Using the claw point as
the "tip" — which is the saber's own formula, `tip = hand + dir * len`, with `len` = the arm
length — gets the physics right for free, but the **threshold must go up, not down**.
`ae_loader_swing` default **14.0** units/tic at the claw, against the saber's 8.0 at a shorter
lever, reduced from a pure 2.3× scaling because a mech swing is meant to be slower than a
lightsaber flourish. The in-file comment on `ubqs_swing_cut` calls it "this mod's most-felt
number" and notes it depends on arm length, standing vs seated and room size. **The same is
true here and this one is the owner's to set in the headset.** There are two of them, one per
arm, and they should be one cvar until he says otherwise.

**`E:\DOOMWork\RS_ShieldSaw\` — design reference only. It cannot run on QuestZDoom 17.3.**
This contradicts the briefing and the shipped code wins, so here is the evidence:
`rs_shieldsaw.zs:124` and `:619` and `rs_shieldsaw_world.zs:283` call
`owner.player.GetVRHand(...)`, and `rs_shieldsaw_state.zs` reads `pmo.GripHeldOff`
(`:656`, `:684`). **`git grep -c "GetVRHand" 9afc750917` and `git grep -c "GripHeldOff" 9afc750917`
both return nothing** — and neither exists even in the QZD checkout's local HEAD. Its own
`ENGINE_PROPOSAL_FollowHandPlayer.md` names `FollowMainHand` / `FollowOffHand`,
`FollowHandFrozenMat`, `src/playsim/p_vrhand.cpp` and `models.cpp:1916-1960`, none of which
exist at 9afc750 either. RS_ShieldSaw is a PCVR-fork mod; ZScript would abort on an unknown
identifier.

What **does** transfer, and it is the most valuable thing in it:
* the **published-pose pattern** — a single writer, local poll → `SendNetworkEvent` with
  thousandths → `NetworkProcess` → playsim fields → **every gameplay read goes through the
  published pose, never the live local field**, with a single-player fall-through at zero
  latency (`rs_shieldsaw.zs:71-100`, `rs_shieldsaw_state.zs:665-680`, `:854-875`). That is
  `RSVR_HandNet`.
* the **half-rate publish** with its justification (`:661-664`).
* the **pair-of-events** trick and the ride-extra-values-in-the-name trick (`:605-621`).
* the discipline in its header: a flag cleared and never restored is the bug that outlives the
  session (`rs_shieldsaw.zs:36-40`) — which is why every flag the carry system touches on a
  held actor is saved and restored, and why `RSVR_Carry` must release on all four of
  `vreload`'s abort conditions.

---

## 6. What it costs on a Quest

**Draw calls, worn, steady state.** Today: 1 psprite layer, 3 MD3 surfaces. After all nine
steps:

| | layers | MD3 surfaces submitted | notes |
|---|---|---|---|
| arms | 2 | 2 | after the carve. Before the carve, the whole 3-surface mesh twice = 6, and four arms. |
| claws | 0 or 2 | 0 or 2 | zero if the claw is a frame of the arm mesh |
| beacon | 1 | 1 | 34 verts |
| **HUD total** | **3–5** | **3–5** | vs. 1 layer / 3 surfaces today |
| legs | — | 2 world | 2 actors, always visible while worn |
| cage | — | 1–2 world | 1 actor |
| held thing | — | its own | already in the scene; carrying it adds nothing |
| sparks | — | 0 | particles, unless `ae_loader_cage_arc` is on, and then **20 surfaces** per instance |

**The real per-layer cost is not geometry.** Each psprite goes through
`hw_weapon.cpp:985-1000` inside the per-psprite loop: `hw_GetDynModelLight(playermo, lightdata)`,
`UploadLights`, and a `FindLightProbe` — a dynamic-light gather **per layer per frame**. Going
from 1 to 5 layers is 5 gathers. That is the number to watch, and it is the same number the
pack already pays when a reload is running (2100, 2101, 2102, 2103, 2104, 2200, 2201, 2130 =
eight layers at once today). **The loader's five is cheaper than a pulse-rifle reload.**

**Per-tic work in `play`**, per player:
* two ring pushes (a `Vector3` and three `AttackDir` calls per hand) — the `AttackDir` calls
  are the expensive part at six VM calls a tic, which `melee.zs` and `vreload.zs` already pay;
* two claw-closure integrations (two adds);
* at most two `BlockThingsIterator`s, **and only while a claw is closing** — zero in the common
  case;
* one carry spring per held thing (a subtract, a scale, a clamp);
* the thrown-actor list, capped at 8, one iterator each;
* one footstep test;
* `RSVR_Body`: a dozen multiplies, and it **removes** five duplicated `CVar.GetCVar`-by-string
  lookups a tic. The study is right that the cvar lookups, not the arithmetic, are the cost
  (`holster.zs:119`, `:159`).

Hoist every cvar into a `transient CVar` cached once, as `flick.zs:38-39` and
`hands.zs:529-534` already do.

**Dynamic lights:** one, the beacon. `ae_loader_beacon_sweep` adds an `A_AttachLight` call and
a `MF8_RECREATELIGHTS | LEVEL3_LIGHTCREATED` dirty flag per tic (`a_dynlight.cpp:913-914`) —
default it **off**.

**Particles:** `Level.SpawnParticle` is not an actor and not a draw call per particle. The
existing caps (`MAX_DEBRIS 64`) must cover the loader's spall too, which is why the refactor
in §5 keeps the counter rather than bypassing it.

**Geometry totals after the carve:** arms 3590 verts split two ways (≈1795 each, both drawn, so
no saving but no loss), cage 1263, legs ≈1200 after the cut, beacon 34. All of it well under
one pulse-rifle mesh.

---

## 7. What could go wrong

**Failure modes, in descending likelihood.**

1. **`MechArms.001` may not split cleanly at `y = 0`.** The bbox is exactly symmetric
   (±121.81), which strongly suggests two mirror halves, but a shoulder yoke crossing the
   centreline is possible and would leave each arm missing its mount. **Check the connected
   components before cutting**; the owner's `md3read.py` / `md3label.py` do island analysis
   and I have not run them. If there is a yoke, it goes in a third model index drawn on the
   main arm's layer only, and the cab's geometry hides the asymmetry. This is the one risk
   that could reorder the plan.
2. **The claw's exact world point is not derivable from source.** The HUD chain is
   `GetWeaponTransform` → `scale(0.01)` → `translate(0, 5, 30)` → `scale(smf)` →
   `translate(Offset/scale)` (`models.cpp:223-251`), so with `Scale -1 1 1` one model unit is
   one centimetre and the claw is roughly 2.3 m ahead of the controller, ±1.0 m lateral, +0.3 m
   up. **Roughly.** Settle it with one render on the rig (`tools/rig/`, `tools/gunview.py`,
   `tools/hudrender.py`) before step 5, because the grab radius, the swing threshold and the
   impact point all hang off it. The reassuring part: `A_CustomPunch(500, 72)` — 72 map units
   ≈ 2.1 m — tells us the original author measured the same arm.
3. **The off-hand `Offset` sign.** The engine mirrors the off hand
   (`hw_vrmodes.cpp:468-469`) and the handoff already records that a mirrored block needs
   mirrored u. The off arm's `Scale` x sign and `Offset` x sign are one render each, not a
   derivation. Budget a sheet.
4. **The off arm vanishing on an off-grip press** (`hw_weapon.cpp:917`). Addressed in §2 item
   1; if the owner takes option (b) this will be reported as an intermittent bug and should be
   in a comment at the top of `loader.zs` so the next session recognises it in one read.
5. **`flick.zs` reloading the loader on a downward swing.** Certain to happen if not gated.
   Whether `Loader` even has a `Reload` state is in the TC and unknown here, which makes it
   *more* dangerous, not less: an unknown state label means an unknown jump.
6. **A held monster still attacking.** Recommended on purpose, but it may be brutal. One cvar,
   both behaviours.
7. **A crushed barrel killing the player.** Correct behaviour, mitigated by the deliberate
   crush ladder and the audible strain. Watch that the cage's absorption makes it survivable
   at 40%.
8. **`oldx`/`oldy` not carried** on the beacon or the lag yaw → a 35 Hz shake instead of a
   smooth follow. The pack has already made and fixed this mistake once
   (`hands.zs:658-670`); the comment there is the warning.
9. **Playsim RNG on a local-only path.** The subtlest hazard and the one that will not show up
   in single-player testing at all. Every effect on the net-event path, nothing on the
   detection path, `Level.maptime % N` for anything with no trigger.
10. **The actor's scale multiplying MODELDEF's** on the legs and the cage
    (`models.cpp:82-84`) — the holster ghosts' 1.2 m crate. Declare `Scale 1.0` explicitly.
11. **`+MASTERNOSEE` + `master`** making the legs or cage invisible (`hw_sprites.cpp:832-865`).
12. **`A_ChangeModel` from an `EventHandler`** — still unverified (study §1.5). This design does
    not depend on it; if a later step wants it, it is one compile.

**Netplay hazards:** §4. In one line: the claw point, the grab, the release, the crush and the
swing must all cross the net-event boundary, and every effect must be spawned on the far side
of it.

**What needs the owner's eyes in a headset — nothing else can settle these.**
* **The cage.** Whether a 61 cm frame 69 cm ahead of his face is immersive or oppressive. The
  one element I would not ship unseen.
* **`ae_loader_lag` and `ae_loader_overshoot`.** The whole point of item 3 is a feel, and the
  numbers are a guess until he swings an arm. Renderer-read, so he can tune them live.
* **`ae_loader_swing`.** The saber's own file calls its equivalent "this mod's most-felt
  number" and records that it depends on arm length, standing vs seated and room size.
* **`ae_loader_speed`.** 0.35 is what the DECORATE intended, not what anyone has felt, because
  it has never taken effect.
* **Whether the arms look right at all**, which is the step-3 gate and the only one that can
  fail the design rather than a number.
* **Whether a held Alien attacking you at arm's length is thrilling or unfair.**
* **The off-hand sign conventions**, which the rig can narrow but only the headset confirms.

---

## 8. Appendix — what would be easy with our own engine, and therefore is not proposed

Recorded only so nobody re-derives it. The equivalents exist in `E:\UZDXREMA`.

* **Expose `weaponStabilised` and its radius**, or let a weapon opt out of two-hand steadying
  with a flag. That one change deletes the only real compromise in this design
  (`gl_openvr.cpp:1717-1728` and its out-of-tree Quest twin; `hw_weapon.cpp:832`, `:917`).
* **A body-anchored HUD model.** `models.cpp:229-234` already contains the branch; it is
  unreachable because `GetWeaponTransform` always succeeds in VR. One `if` would make the legs
  and the cage psprite layers with correct near-plane behaviour and no thinkers.
* **An analogue trigger value.** Would make item 4 literal instead of time-driven.
* **`AttackVel` / `OffhandVel`.** Would remove a tic of latency and a tic of noise from every
  swing and throw, and delete the ring buffer.
* **A per-player hand transform for the renderer** (`FollowHandPlayer`, proposed in
  `RS_ShieldSaw/ENGINE_PROPOSAL_FollowHandPlayer.md`). Without it a co-op partner's loader arms
  cannot be drawn in his hands at all; the workaround is world actors at 35 Hz.
* **A one-hand haptics call with a duration and an intensity.** We have the per-hand pulse via
  `SpawnPlayerMissile` (§0 correction 1) but not its strength or its length, and
  `VR_HapticEvent` is a stub in-tree (`qzdoom_common.cpp:65-67`).
* **Per-surface hide at runtime.** `CMDL_HIDEMODEL` works on a model index; a surface-level
  equivalent would have made the carve unnecessary for the cage and the legs, though not for
  the two arms.
