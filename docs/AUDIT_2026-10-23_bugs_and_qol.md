# RS Aliens VR Weapons (Quest) — audit, 2026-10-23

Report only. Nothing in the pack was changed. Engine claims are read from
`E:\DOOMWork\QZD17-engine` (branch `qzd173-pinned`, contains 9afc750). Spec claims are cited to
`C:\Users\Command\Desktop\Quest_Weapons_Kit`. Reference pack is BD22 VR-Reloaded 1.92
(text lumps extracted to the session scratchpad) — used only to judge this pack's code, not to
produce a port plan (a separate lane owns that diff).

Excluded by instruction: hook/rot **numbers** in `zscript/rsq/handtable.zs`. Mechanism bugs in how
that table is consumed are in scope and several are reported below.

---

## 0. The engine transform chain, settled

Everything in sections 1–3 rests on this. Read from `src/r_data/models.cpp`
`RenderHUDModel` (lines 211–280) and the MODELDEF parser (lines 990–1015).

Matrix build order (so the **vertex** order is the reverse):

```
scale   (xscale, zscale, yscale)                                    // models.cpp:248
translate(xoffset/xscale, zoffset/zscale, yoffset/yscale)            // :251  MODELDEF Offset
translate(-vr_3dweaponOffsetX, +Y, +Z)                               // :254
translate(pivot)                                                     // :260
rotate(rotation.X, 0,1,0)   // about Y  -> YAW                       // :262
rotate(rotation.Y, 1,0,0)   // about X  -> PITCH                     // :263
rotate(rotation.Z, 0,0,1)   // about Z  -> ROLL                      // :264
translate(-pivot)                                                    // :266
translate(translation.X, translation.Y, translation.Z)               // :268  THE HOOK
rotate(90, 0,1,0)                                                    // :272  jDoom fix
```

Parser (`models.cpp:990-1015`): `Scale A B C` → `xscale=A, yscale=B, zscale=C`.
`Offset A B C` → `xoffset=A, yoffset=B, zoffset=C`. `ZOffset C` sets `zoffset` alone.

Four consequences that matter:

1. **Rotation slots are (yaw, pitch, roll)**, applied yaw→pitch→roll. `RSQ_Turn`'s header comment
   and `RSQ_Place.Layer`'s `gunTurnNow = (g.x/4, (g.y - WEAPONTOP)/-4, 0)` are **correct**.
   `RSP_Guns.HandRot(1) = (0.656, 57.6, 0.550)` is therefore yaw 0.656 / **pitch 57.6** / roll 0.550,
   and the in-file comment naming 57.6 a pitch is right.
2. **The hook is scaled component-wise by (xscale, zscale, yscale)** — note the pairing: hook.y
   is multiplied by `zscale`, hook.z by `yscale`. `RSP.HookOf` (`rsr_pump.zs:118-122`) divides by
   exactly that pairing and is **correct**. `RSQ_HandTable.GunHook` needs no division because the
   hand blocks are `Scale -1.0 1.0 1.0`, so 1 unit = 1 cm; the negative xscale is why
   `handtable.zs`'s "x left, y up, z back" is **correct** as documented.
3. **MODELDEF `Offset` and the hook are NOT interchangeable component-for-component.** Matrix Y
   takes Offset's **third** number and the hook's **y**; matrix Z takes Offset's **second** number
   and the hook's **z**. Baking a hook into `Offset` requires swapping y and z. §1.2 is a bug
   caused by not doing that.
4. **The hook is applied to the vertex before the rotation**, so the hook is rotated by the
   layer's returned rotation. `RSQ_Turn.Place` is built for this and compensates correctly (it
   pre-rotates the frame move by the inverse of `hookTurn`). But the raw `hook` is *not*
   pre-rotated, which is fine when `GunRot = 0` and is the cause of §1.4.

Also confirmed from the engine, correcting two statements in the handoff:

* **`hw_weapon.cpp:919` / `:833`: `if (weaponStabilised && psp->GetCaller() == player->OffhandWeapon) continue;`**
  — while the engine is two-hand steadying, **every layer whose caller is the off-hand weapon is
  not drawn at all.** The kit documents this as a hard limit
  (`docs/QuestReload_Diagnosis.md`, "While steadying is on, everything owned by the off-hand
  weapon is not drawn"). Three findings below come out of this.
* **A MODELDEF block naming an unknown class is FATAL**, not silent:
  `models.cpp:901 sc.ScriptError("MODELDEF: Unknown actor type '%s'")`. The comment at
  `zscript/rsq/hands.zs:8-9` ("A MODELDEF block pointing at an unknown class is not a parse
  error, which is why a clean script parse said nothing about it") is **wrong on this engine**,
  and the historical diagnosis built on it cannot have happened that way. This matters for §5.

And the key dispatch fact, which the handoff states loosely and which is the root of §1.1:
`hw_weapon.cpp:943-963` looks `ModifyBobLayer3D` up on **`weap.weapon->GetCaller()`'s class** and
passes that actor as `self`. `GetWeaponPosition3D` (`hw_weapon.cpp:332`) sets
`w.weapon = psp->GetCaller() == player->ReadyWeapon ? readyWeaponPsp : offhandWeaponPsp`. So for
every hand layer, the hook is looked up on **`player.OffhandWeapon`'s class**, and
`hw_weapon.cpp:949` nulls it out when that class has not overridden it.

---

# PART 1 — BUGS

Ranked. "file:line" is this repo unless marked otherwise.

---

## §1 Hands on the gun, recoil follow, trigger finger

### 1.1 — CRITICAL. Dual wield silently disables every hand hook and all recoil follow

`zscript/rsq/hands.zs:413` is the **only** `ModifyBobLayer3D` override in the entire pack
(verified by grep across `*.zs`, `*.txt`). It lives on `RSQ_Hands`.

`DECORATE.aedual:20,42,64,86,108,130,152,174,196,218` define the ten `AE_Off_*` copies as
**DECORATE** subclasses of the TC's weapons. DECORATE cannot override a ZScript virtual, and
nothing in `zscript/` defines them. So `AE_Off_*` has the base `Weapon.ModifyBobLayer3D`.

`AE_DualHandler.WorldTick` (`zscript/rsq/dual.zs:150`) parks that copy in
`p.PendingWeapon` → it becomes `p.OffhandWeapon`. From that moment,
`hw_weapon.cpp:946-949` resolves the hook to the *base* function, compares it to
`ModifyBobLayer3DOrigFunc`, and sets it to `nullptr`.

**Result, the moment dual wield engages:** layers 2100 (gun hand), 2101 (support hand), 2130
(pulse-rifle LED counter) and every reload layer get **no hook, no `RSQ_Turn` recoil follow and no
frame follow**. They fall back to the raw controller pose plus their MODELDEF `Offset`.

What the player sees: the main-hand hand model stops riding the gun. For pistols it also drifts
1.5 cm / 2.5 cm (the whole `GunHook`), and on every gun **the hand stops following the kick** — the
pistol's 1.7–3.5 cm fire travel and the shotgun's 23 cm / 61° pump now slide through a frozen
hand. On the pulse rifle the "88" LED quad stops following the receiver and slides off the window
during fire.

`hands.zs:47-52` claims this was already solved — *"dual wielding puts a real gun in that slot,
and the moment it does, a gun that does not implement this silently drops every hand hook on the
floor. Both owners call the same code instead."* `RSQ_Place.Layer` was correctly factored out for
that purpose, but the **second owner was never given the override**.

**Smallest fix:** stop defining the copies in DECORATE. Declare them in ZScript as
`class AE_Off_X : <Gun>_3D { override Vector3, Vector3 ModifyBobLayer3D(...) { Vector3 t,r;
[t,r] = RSQ_Place.Layer(Owner, translation, rotation, layer, ticfrac); return t, r; } }` — one
three-line override per copy, or one shared intermediate class if the ten base guns allow it (they
do not share a parent here, so ten overrides). `DECORATE.aedual`'s ammo/flag properties move into
the ZScript `Default` block unchanged.

**Do not apply the fix without also fixing 1.4**, or the off gun's own hand will double-apply its
hook.

**Settle it on the Windows exe** (`C:\Users\Command\Desktop\qzdoom-17-3-Windows-64bit\qzdoom.exe`,
do not run it here): launch with `+vr_mode 0 +vr_override_weap_pos 1 +vr_render_weap_in_scene 1`
(the kit: *"`+vr_mode 0`, not `-config`, is what keeps a desktop test out of the headset"*), then
`+ae_dual_pistol 1 +ae_start_dual 1`, and use `tools/probe/probe_zscript.txt` to print the layer
list and whether `ModifyBobLayer3D` fires. A one-line `Console.Printf` in
`RSQ_Hands.ModifyBobLayer3D` that never prints while dual is the whole proof.

---

### 1.2 — HIGH. `MODELDEF.aedual`'s baked hand offsets transpose "up" and "back"

`MODELDEF.aedual:1218-1241` and the nine blocks after it. Also the bake formula written down in
`docs/HANDOFF_2026-10-23.md` §2: *"Offset = (0+x, -24+y, -10+z)"*.

Per §0.3, matrix Y takes `Offset`'s **third** number and the hook's **y**; matrix Z takes
`Offset`'s **second** number and the hook's **z**. The correct bake is therefore
`Offset (0+x) (-24+z) (-10+y)`.

What is in the file:

| class | `Offset` | delta vs base `0 -24 -10` | `GunHook` (x, y, z) | correct `Offset` |
|---|---|---|---|---|
| `AE_Off_M4A3Pistol` and the 3 other pistols | `0 -22.500 -7.500` | B +1.5, C +2.5 | (0, 1.5, 2.5) | `0 -21.5 -8.5` |
| `AE_Off_PulseRifle`, `AE_Off_YutaniRifle` | `0 -23.500 -10.000` | B +0.5, C 0 | (0, 0.5, 0) | `0 -24.0 -9.5` |
| shotguns, flamers | `0 -24.000 -10.000` | 0 | (0, 0, 0) | correct |

So the off-hand pistol's hand is 2.5 cm along the height axis where it should be 1.5, and 1.5 along
the depth axis where it should be 2.5 — about 1.4 cm of diagonal error. The off-hand rifle's hand is
0.5 cm **back** where it should be 0.5 cm **up**.

Small in magnitude, but the point is that **the generator will reproduce it on every bake**, and the
owner is about to bake headset numbers through that formula. Fix the formula in the handoff and in
`tools/gen_aedual_modeldef.py` (not yet written — write it with y/z swapped) before the next bake.

---

### 1.3 — HIGH. The hand poses never blend; they pop

`zscript/rsq/hands.zs:309-331` (RSQ_GunSide) and `:435-462` (RSQ_Hands). **Every** hand state is
`SPRITE X -1; Stop;`.

The kit documents the mechanism that was available and not used
(`docs/QuestReload_Diagnosis.md`): *"The engine blends a layer's model between its current frame
and the next state's frame, smoothly at headset rate — models.cpp:367-405. **Two states per pose
give a smooth blend from any pose to any other.** Script can set a layer's tic count, which sets
how far through the blend it is."*

With `Tics = -1` and `NextState = Stop`, there is no blend target and no progress, so:

* **The trigger finger snaps.** `TrgB` → `SqzB` is the documented 15–20° further curl
  (`docs/FINGER_ON_TRIGGER.md`) and it arrives in one frame as an instantaneous jump.
* Every reload hand change snaps: open → `RsrHold` → `AmmoH` → open, and `RspShell` on the
  shotgun. Four hard cuts per shotgun shell.
* Every weapon switch snaps the hand from one grip pose to another.

The pack's own code already knows how the engine does this: `RSQ_Hands.FollowGun`
(`hands.zs:366-375`) blends the **gun's** model frame toward `gunState.NextState` and
`RSQ_GunMoves.Blends(i)` exists for exactly that. So the gun blends and the hand does not.

**Smallest fix:** give each pose a 2-state pair whose first state has a positive `Tics` and whose
`NextState` is the pose itself, e.g.
`GunCto: RQGS C 3 { } ; GunC: RQGS C -1; Stop;` and have `SetLayer` enter the `...to` state. That
is the kit's documented "two states per pose". Cheap; no new art.

---

### 1.4 — HIGH (latent). The `OFFGUN` branch would double-apply the hook

`zscript/rsq/hands.zs:131-137`:

```
if (layer == RSQ_Layers.OFFGUN)
{
    let psp = p.FindPSprite(layer);
    Vector2 h = psp ? (psp.x, psp.y) : (0.0, WEAPONTOP);
    return translation + hook, rotation + rot - (h.x / 4, (h.y - WEAPONTOP) / -4, 0);
}
```

`hook` here is `RSQ_HandTable.GunHook(oi)` + the slider delta (added at `:125-126`). But
`MODELDEF.aedual` already bakes `GunHook` into that layer's `Offset`. Today this branch is
unreachable (see 1.1), so it is latent — but the fix for 1.1 makes it live, and the off gun's hand
will then jump by a full `GunHook`.

**Fix:** in the `OFFGUN` branch use only the slider delta, never the table hook:
`Vector3 hook = RSQ_HandTune.Offset(p, oi);` (and keep `rot` from the table, since `GunRot` is
zero for all ten dual-able guns so nothing is baked for it).

Two lesser problems in the same five lines:
* It reads `psp.x / psp.y` raw where the main path uses the interpolated
  `RSQ_Hands.LayerOffset(psp, ticfrac)` (`:156-157`). One frame of stale tilt; inconsistent.
* It applies **no recoil follow at all** — see 1.5.

---

### 1.5 — HIGH. The off gun's own hand never follows that gun's recoil

Same branch, `hands.zs:131-137`. It returns the rest hook and nothing else: no
`frameTurn`/`frameMove` from `RSQ_GunMoves`, no gun-layer turn, no pivot. The comment at `:133`
says *"(no follow yet)"*.

So even once 1.1 and 1.4 are fixed: fire the off-hand pistol and **the gun cycles through its 1.7–3.5 cm
fire travel, and its own canned reload swings 28 cm / 42° (`tools/ae_kick.py` numbers quoted in
`hands.zs:19-21`), while the hand hangs motionless in the air.** The slide passes through the palm;
during a flick-reload the gun swings away from a hand that stays put.

`RSQ_Place.Layer`'s main path already does all of this. The off gun needs the same treatment with
two substitutions: the gun layer is `PSP_OFFHANDWEAPON` (not `PSP_WEAPON`), and the frame cache
must be the **off** gun's, not `RSQ_Hands.gunState` (which `FollowGun` fills from
`p.FindPSprite(PSP_WEAPON)` and `RSQ_HandTable.Index(p.ReadyWeapon)` only —
`hands.zs:349,554`). Smallest correct shape: add `offState/offTurn/offMove/nextOffTurn/nextOffMove`
to `RSQ_Hands` and a `FollowOffGun(p, oi)` that is `FollowGun` with `PSP_OFFHANDWEAPON` and the
off gun's index, then route the `OFFGUN` layer through the same `RSQ_Turn.Place` call.

---

### 1.6 — HIGH. The "forward / up / side" sliders do not move forward, up or side on the smartgun or the satchel

`zscript/rsq/hands.zs:125-128` adds `RSQ_HandTune.Offset(p, i)` to `hook` **before**
`RSQ_Turn.Place` composes `hookTurn` into the rotation. Per §0.4 the hook is rotated by the
layer's returned rotation, which includes `GunRot(i)`.

For the fourteen guns with `GunRot = (0,0,0)` that is harmless and the sliders do exactly what
their labels say. For the two guns with a non-zero `GunRot` it is not:

* `Smartgun_3D` / `YutaniSmartgun_3D` (indices 8, 16): `GunRot = (0, 90, -90)` — yaw 0, pitch 90,
  roll −90. "Gun hand forward" moves the hand along a GunRot-rotated axis, not forward.
* `Satcheler_3D` / `YutaniSatchel_3D` (7, 14): `GunRot = (138.21, 125.82, -48.72)` — the sliders are
  effectively scrambled, and `ae_satchel_yaw/pitch/roll` (added to `rot` at `:129-130`) change
  which way they point as you turn them.

This matters right now: the owner is tuning in the headset with these sliders and reporting
numbers to be baked. On the smartgun and the satchel, moving "forward" and getting sideways motion
is this, not a mis-measured mesh.

**Fix:** pre-rotate the slider delta into the hook's own frame before adding it, using the same
`RSQ_Turn.Rows` / `Back` pair already in the file:

```
Vector3 d = RSQ_HandTune.Offset(p, i);
Vector3 h0, h1, h2; [h0, h1, h2] = RSQ_Turn.Rows(RSQ_HandTable.GunRot(i));
hook += RSQ_Turn.Back(h0, h1, h2, d);   // Back() is the transpose: world delta -> hook frame
```

Same for `SupportOffset` against `SupportRot(i)` (non-zero on the smartguns only). Baked values
taken before this fix will need re-deriving for those two guns.

---

### 1.7 — MEDIUM. `ae_lefthanded` moves the hands but not the gun

`zscript/rsq/hands.zs:523-524`:

```
Actor gunOwner  = swap ? Actor(hands) : Actor(side);
Actor freeOwner = swap ? Actor(side)  : Actor(hands);
```

The comment at `:519-522` is right that this swaps which controller the **hands** draw on. But the
**gun** is `PSP_WEAPON`, whose caller is `p.ReadyWeapon`, and `models.cpp:224` sends a layer to the
off controller only when its caller is `player->OffhandWeapon`. The ready weapon can never be the
off-hand weapon. So with `ae_lefthanded 1`:

* the gun stays on the main controller and the hand holding it moves to the off controller;
* worse, layers 2100/2101 now have caller == `OffhandWeapon`, so **`hw_weapon.cpp:919` stops drawing
  the gun hand and support hand entirely whenever the engine is two-hand steadying** — which is
  precisely the two-handed pose.

Default-off, so not urgent. But it cannot be made to work this way. Left-handed play on QZD is the
engine's own control-scheme setting (which swaps which physical controller is "main", so the gun
follows the left hand and no fit changes); the honest fix is to delete `ae_lefthanded` and point the
menu row at the engine's setting, or at minimum change the menu text to say what it does.

---

### 1.8 — MEDIUM. Two-hand steadying hides things the pack still thinks are visible

`hw_weapon.cpp:919`, cited above. Three reachable cases:

* **A magazine or shell in the hand vanishes while steadied.** Layers 2201 (`RSR.HANDMAG`) and
  2210 (`RSP.HANDSHELL`) are set with caller `p.OffhandWeapon` (`vreload.zs:635-636`,
  `rsr_pump.zs:963-964`). The off **trigger** grabs anywhere (`rsr_grab_buttons`), so: take a
  shell with the off trigger, then press the off grip near the gun — the engine steadies and the
  shell in your hand disappears while `FreeFeed`/`LoadTick` keep tracking it. Pushing an invisible
  shell home still works, which is worse than it failing.
* **Dual wield + off grip near the gun hides the second gun.** Its own
  `PSP_OFFHANDWEAPON` psprite and its hand layer 2202 both have caller == `OffhandWeapon`. The
  engine has no idea the off hand is holding a gun, so it steadies as usual and the gun you are
  firing is not drawn.
* `ae_lefthanded` — see 1.7.

**Fix for the first two:** these are presentation-only, so the mod can compensate. For the shell /
magazine, mirror the already-correct pump handling: while `RSVR_VRHand.Steadied(mo)` is true and
the hand holds a part, draw that part on an **`RSR_GunParts`-owned** layer (main controller, so it
is drawn) placed from `offLocal` instead of on the off-hand layer. For dual, refuse to treat a grip
press as steadying while `p.OffhandWeapon` is an `AE_Off_*` — the mod cannot write
`vr_two_handed_weapons` (and must not, per the kit's rules), but it can at least draw a
`RSR_GunParts`-owned copy of the off gun's hand so the player is not left with an invisible pistol.
Needs an owner decision; report it as a known limit if neither is wanted.

---

### 1.9 — LOW. The trigger finger is digital only, and on purpose

`zscript/rsq/hands.zs:527-528` selects `Sqz`/`Trg` from `p.cmd.buttons & BT_ATTACK`.

The kit settles whether more is possible: *"No analog trigger or grip value, no controller
velocity, no finger tracking — searched, not found"* (`docs/QuestReload_Diagnosis.md`, hard
limits). So an analogue finger **needs an engine change** and is listed in Part 3.

Two things that are in scope mod-side:

* Verified correct: the frames exist and the arithmetic lines up. `models/rsq/hand.md3` has
  **16 frames** (MD3 header, `num_frames` at offset 0x4C) and `MODELDEF.ae:16-31` uses frames
  0–15: six grips (`RQGS A–F`) plus five `RQGT`/`RQGU` pairs. `models/rsq/hand2.md3` has 3 frames
  and `MODELDEF.ae:41-43` uses 0–2. `RSQ_HandTable.Trigger()` returns only A–D, and
  `RSQ_GunSide` defines `TrgA..TrgE`/`SqzA..SqzE`, so every requested letter is bound.
  **The handoff's "N values need N blocks" warning does not apply here** — it applies when each
  value needs a different `Skin` (which is why the counter correctly uses 100 blocks,
  `MODELDEF.ae:65-...`, all 100 `RSC*` values distinct, verified). Different model *frames* in one
  block is the normal form. Nothing to change.
* It cannot get stuck: `SetLayer` recomputes the label from `p.cmd.buttons` every tic. But it does
  snap (§1.3), and on a single shot the button is usually released before the gun's fire frames
  finish, so the finger returns to rest mid-shot. Holding `Sqz` for the length of the fire
  sequence (e.g. until `WF_WEAPONREADY` returns) would read better; see Part 2.

---

### 1.10 — LOW. The hands freeze in front of the camera on death

`zscript/rsq/hands.zs:479-480` — `if (!mo || mo.health <= 0) continue;` skips the player **before**
any layer is touched, so 2100/2101/2130/2200 keep their last state and keep being placed through
the death-cam. `FollowGun` also stops updating, so they hold a stale recoil frame.

**Fix:** on `mo.health <= 0`, hide the layers (`SetLayer(p, id, null, "")` destroys them) before
the `continue`. `AE_HolsterHandler` already does the equivalent (`holster.zs:51-55`).

---

### 1.11 — LOW. The smartgun's hands also sit out its reload swing

`zscript/rsq/hands.zs:161-162` forces `gunTurnNow = (0,0,0)` for indices 8/16 so the harness gimbal
does not drag the hands. Correct for the gimbal — but the smartgun's own states drive the same
psprite (`SMARTGUN.md`: *"`Offset(0,52)` during the reload, the recoil frames during fire"*), so the
hands also ignore the reload swing and the fire kick's layer component. They do still get the mesh
frame follow. Acceptable trade; worth knowing. A cleaner version would subtract only the gimbal's
own contribution — `AE_SmartState.putX/putY` is already the exact number
(`smartgun.zs:325-326`) and could be exposed for `RSQ_Place.Layer` to remove.

---

## §2 Reload: correctness

### 2.1 — CRITICAL. The Yutani shotgun's VR reload loads an ammo pool it cannot fire

`actors/weapons/shotgun.txt:809` and `:820`.

Within `YutaloniShotgun_3D` (lines 424–842) every **live** path uses `ShotgunLoaded`:
fire takes it at `:500, :548, :557, :565`, the slug at `:834`, the stock reload loop gives it at
`:685,:687`, and both VR top-off paths give it at `:757` (`RSP_P1Feed`) and `:783` (`RSP_Feed`).
Only the commented-out blocks use `YShotgunLoaded`.

But the reload-button VR path uses `YShotgunLoaded`:

```
809:  YTSG A 0 A_JumpIfInventory("YShotgunLoaded", 8, "RSP_LoadEnd")   // full
820:  YTSG A 0 A_GiveInventory("YShotgunLoaded", 1)
```

**Reproduction:** take the Yutani shotgun, press reload, hand-feed shells. Each shell home consumes
one `AliensShell` from reserve (`:821`) and adds one `YShotgunLoaded`. Fire still drains
`ShotgunLoaded`. The gun gains nothing you can shoot, the loop ends "full" at 8, and the player has
burned 8 shells for nothing. `NewShotgun_3D` (lines 1–423) is consistent throughout and is fine.

`:652`'s reload gate (`A_JumpIfInventory("YShotgunLoaded", 8, 2)`) is the same mistake, benign
(it just never blocks).

**Smallest fix:** `:652`, `:809`, `:820` → `ShotgunLoaded`. That also makes
`RSP_Guns.Loaded(2) = "ShotgunLoaded"` (`rsr_pump_guns.zs:304`) correct, which it currently is not,
and makes `RSP_Guns.MagAmmo(2) = "YShotgunLoaded"` (`:327`) dead and wrong — delete it or align it.
The weapon's `AmmoType1` lives in `_A01` and is UNVERIFIED here; if it turns out to be
`YShotgunLoaded`, the fix is the other way round and must change the five fire lines instead.
`printinv` before and after a hand reload on the Windows exe settles it in one run.

---

### 2.2 — HIGH. Aborting a magazine reload with an empty reserve loses the rounds permanently

`actors/weapons/rifle.txt:238-246` (and the same shape at `pistol.txt:155-190`,
`smartgun.txt:243-255`, `flamethrower.txt:166-186`, `rifle.txt:521-545`).

`RSR_Out` drains the whole loaded count into `RSR_Held_<gun>` one at a time and then sets
`RSR_NoMag_<gun>`, all in the same tic. Those rounds come back only at `RSR_Fill` → `RSR_Return`,
which is reached only by completing a reload.

`RSR_Handler.WorldTick:906-914` aborts on death, a weapon switch, or two missed ticks:

```
bool gone = mo.health <= 0 || mo.player.ReadyWeapon != s.weap || now - s.lastTick > 2;
... s.Abort(mo);
```

`RSR_State.Abort` (`vreload.zs:551-558`) drops a world magazine and calls `End`. It never returns
`RSR_Held_*` and never clears `RSR_NoMag_*`.

**Reproduction:** pulse rifle with 60 loaded and **0 `PulseRifleClip`** in reserve. Press reload.
The 60 become `RSR_Held_PulseRifle_3D`, the counter reads 00, the gun is empty. Switch weapons (or
die). Come back: `Reload` (`rifle.txt:96-100`) gates on
`A_JumpIfInventory("PulseRifleClip", 1, "ReloadWork")` — 0 reserve, so it falls through to
`Goto Ready`. The reload can never be re-entered, so the 60 rounds can never come back. The rifle is
a paperweight holding 60 invisible rounds.

**Smallest fix:** add a held-rounds escape to each gun's `Reload` gate, one line:
`A_JumpIfInventory("RSR_Held_PulseRifle_3D", 1, "ReloadWork")` immediately after the reserve test.
Better, and still small: make `RSR_State.Abort` give the weapon a new `RSR_Abort` token and add a
two-state `RSR_Abort:` label per gun that runs the existing `RSR_Return` loop and takes
`RSR_NoMag_*`. The second form also fixes the cosmetic "counter reads 00 while holding 60".

---

### 2.3 — HIGH. The launcher pump charges you 20 rounds even when grenades are full

`zscript/rsq/pumpgl.zs:342-358`:

```
int cost = max(1, int(RSR.Float('ae_glpump_cost', 20)));
if (mo.CountInv(loaded) < cost) { dryfire; return; }
mo.TakeInventory(loaded, cost);
mo.GiveInventory('GrenadeAmmo', 1);
```

`GrenadeAmmo` is an `Ammo` from `_A01` with a `MaxAmount`, and `actors/players.txt:116` starts the
player with 10 of it. `GiveInventory` silently clamps at the cap; the `TakeInventory` does not.

**Reproduction:** pulse rifle, grenades at the cap, work the underbarrel pump once → 20 rounds gone
from the magazine, no grenade gained, no feedback.

**Smallest fix:** before taking anything,
`let g = Ammo(mo.FindInventory('GrenadeAmmo')); if (g && g.Amount >= g.MaxAmount) { dryfire; return; }`.

Two smaller things in the same function:
* The stroke plays `PULSREL3` at the back (`:332`) and the `AE_GLPump` state plays `PULSREL3`
  again on the way forward (`rifle.txt:142`) — the same sample twice in ~10 tics.
* `held[n]` is not cleared on the early `continue` at `:293-294` (dead / not in VR), so leaving and
  re-entering VR mid-stroke resumes a stroke from a stale `startF`.

---

### 2.4 — HIGH. The flick reload fires from any weapon state, including mid-fire and mid-switch

`zscript/rsq/flick.zs:93-103`:

```
static void Reload(PlayerInfo p)
{
    let w = p.ReadyWeapon;
    if (!w || !p.mo) return;
    if (RSR_Handler.FreeHand(p.mo) != "") return;
    State s = w.FindState('Reload');
    if (s) p.SetPsprite(PSP_WEAPON, s);
}
```

No `p.WeaponState & WF_WEAPONREADY` check — compare `RSQ_PumpGL.Cycle` (`pumpgl.zs:353`), which
does check. The `FreeHand` guard only covers a *magazine* reload in flight; it returns `""` during
fire, during `Select`/`Deselect`, during `AE_GLPump`, and during `RSP_*` pump waits
(`RSP_Handler.FreeHand` is consulted separately in `hands.zs:535` but not here).

**Reproduction:** flick down during the shotgun's fire sequence → the psprite jumps straight to
`Reload`, cancelling the shot's tail and skipping `RSP_P1` (the hand-pump entry) entirely, so the
gun is "ready" without having been pumped. Flick during `Deselect` → the gun jumps to `Reload`
while `PendingWeapon` is set, and the switch is deferred until `RSR_Wait`'s `A_WeaponReady` happens
to run `P_CheckWeaponSwitch`.

**Smallest fix:** `if (!(p.WeaponState & WF_WEAPONREADY)) return;` and extend the busy test to
`RSP_Handler.FreeHand(p.mo) != "" || RSP_Handler.Busy(p.mo.PlayerNumber())`.

---

### 2.5 — MEDIUM. The fire selector and the holsters complete on proximity alone

The kit's non-negotiable rules (`docs/RELOAD_ON_QUEST.md`): *"**Nothing completes because a hand is
near something.** You must be *holding* the part."*

* `zscript/rsq/switch.zs:85-89` — `if (!onSwitch[i] && d <= AE_Switch.REACH) { onSwitch[i] = true;
  Flick(p, w); }`. No button, no grab. Brushing the off hand within 7 cm of a point 26.8 cm forward /
  5.7 left / 8.5 up of the gun controller toggles the smartgun's fire mode. Default **on**
  (`CVARINFO.ae:11`).
* `zscript/rsq/holster.zs:85-91` — `if (near >= 0 && !onHolster[p]) { ... pl.PendingWeapon = w; }`.
  No grab. Reaching across your own chest swaps your weapon. Default off (`CVARINFO.ae:29`), which
  is presumably why it has not bitten.

**Smallest fix:** gate both on a held grab, which is already computed:
`(RSVR_VRHand.Buttons(mo) & RSR.GrabMask(mo.player)) != 0`, or `RSR_State.Grip(mo)` for the full
trigger-or-free-grip rule.

`switch.zs:122-128` also enters `AltFire` with no `WF_WEAPONREADY` check, same class as 2.4; on the
smartgun `AltFire` only toggles `SmartAlt`, so the damage is limited to interrupting an animation.

---

### 2.6 — MEDIUM. The shell drawn in the hand and the shell the capture test measures are two different things

This is the mechanism behind the owner's "the held shell is still 45° off in the headset" (handoff
§4.1). It is not an angle to re-tune; it is two uncoordinated constants.

**Drawing** — `zscript/rsr/rsr_pump.zs:1166-1170`:
```
Vector3 hr = RSP_Guns.HandRot(i) + (ae_shell_yaw, ae_shell_pitch, ae_shell_roll);
return t + RSP_Guns.HandHook(i) + Unturn(hr, DeskShift(...)), r + hr;
```
`HandRot(1) = (0.656, 57.6, 0.550)` = yaw / pitch / roll (§0.1). `Unturn(...)` returns `(0,0,0)`
in game because `DeskShift` is zero without `rsr_test_offdraw`, so the whole drawing is:
`translation + HandHook`, `rotation + HandRot`. A **constant Euler rotation relative to the off
controller.**

**Testing** — `rsr_pump.zs:545-554`:
```
Vector3 a = geo.OffDirInGun(RSP_Guns.AxisInHand(gun));
... acos(clamp(a dot push, -1, 1))
```
`AxisInHand(1) = (0.537, -0.009, 0.844)` — a direction in the off-hand frame (x fwd, y left, z up),
rotated properly into the gun frame and compared against the port's push direction. That
construction is **correct**.

The two numbers agree today only because they were hand-matched:
`atan2(0.844, 0.537) = 57.5°`, and `HandRot.y` was hand-edited from the generated 25.117 to **57.6**
(`rsr_pump_guns.zs:153-155`, *"the shell stood at 10 o'clock in the fist; pitch 25.117 → 57.6 turns
it upright (12/6), render-checked"*). Nothing in the code keeps them in step.

Two consequences:

1. **The 57.6 was tuned to make the shell look upright *in the world* on the rig**, where
   `qz_lhand` set a scripted hand with roll 0 and pitch 30 ("hand pitch 30 = level", handoff §3).
   In the headset the wrist is at a different roll and pitch. `ammo_hand.md3` frame 1 — the fist
   that is supposed to be holding it (`MODELDEF.rsrpump:164-172`, `RQUN A` → frame 1) — turns with
   the controller, because the free hand layer 2200 gets **no rotation at all**
   (`vreload.zs:876-877`, `case RSR.FREEHAND: return t + DeskShift(...), r;`). So the fist rotates
   with the wrist and the shell rotates with the wrist by the *same* constant offset, which means
   the shell/fist relationship is in fact stable — and what is *not* stable is "upright". The 45°
   the owner sees is the difference between the rig's scripted wrist attitude and his own. Tuning
   `ae_shell_pitch` until it looks right in the headset is therefore the correct action **and it
   will break the capture test**, see 2.
2. **The sliders move the drawing and not the test.** `ae_shell_yaw/pitch/roll` feed `hr` only.
   After the owner bakes a new pitch, `AxisInHand` still says 57.5° and the gate
   `ang < PumpTilt` (60° × `rsr_assist`) is measuring a shell at a different angle than the one on
   screen. With the default 60° tilt there is enough slack to hide it; at `rsr_assist 0.5` (30°) it
   will not be hidden.

**Fix (mechanism, no numbers):** derive one from the other instead of storing both. Keep
`AxisInHand` as the single source of truth and compute the drawing rotation from it, or — simpler
and the smaller change — make the sliders feed **both**: rotate `AxisInHand` by the slider delta
before the `acos`, using the `Rows`/`Back` pair already present. Then whatever the owner bakes is
automatically what the test measures. State in the handoff that `HandRot` and `AxisInHand` must be
baked together.

---

### 2.7 — MEDIUM. The magazine in the hand has no orientation control at all, and its angle gate is a proxy

Companion to 2.6, for the four magazine guns.

* **Drawing**: `vreload.zs:874-875`, `case RSR.HANDMAG: return t + RSR_Guns.HandHook(i) + DeskShift(...), r;`
  — **no rotation term**. The magazine's attitude in the hand is purely whatever its MODELDEF block
  gives (`MODELDEF.rsr:70-83` etc.), and there is no `MagHandRot` and no
  `ae_mag_yaw/pitch/roll` slider. If the pistol magazine sits wrong in the fist, there is nothing
  to turn.
* **Testing**: `RSR_State.MagAtWell` (`vreload.zs:277-287`):
  ```
  double c = clamp(OffDirInGun(axis) dot axis, -1, 1);
  return -along, side, acos(c);
  ```
  `axis` is `RSR_Guns.Axis(i)` — the **well's** axis. Feeding the well axis into `OffDirInGun` and
  comparing it against itself asks *"is the off hand oriented like the gun hand, measured about the
  well axis"*. That is a hand-attitude proxy, not the magazine's own axis. `rsr_pump` does it
  properly with `AxisInHand`; `vreload` has no equivalent table entry.

Not a crash, and with `MagTilt` at 60° it is forgiving enough to work. But it means a magazine
cannot be fitted to the hand and the gate is measuring the wrong thing. **Fix:** add
`MagAxisInHand(i)` and `MagHandRot(i)` to `rsr_guns.zs` on the `rsr_pump_guns.zs` pattern, apply
the rotation in the `HANDMAG` case, and use the real axis in `MagAtWell`. Add
`ae_mag_yaw/pitch/roll` next to the shell sliders (`MENUDEF.ae:51-53`).

---

### 2.8 — MEDIUM. The charging handle pull, the pump's forward stroke, and every dropped part are silent

All verified as empty strings in the generated tables:

* `zscript/rsr/rsr_guns.zs:506-522` — `SndBack(i)` returns `""` for all ten guns.
* `:524-540` — `SndFwd(i)` returns `""` for all ten.
* `:542-558` — `SndLand(i)` returns `""` for all ten.
* `zscript/rsr/rsr_pump_guns.zs:271-279` — `SndFwd(i)` `""` for both shotguns.
* `:291-299` — `SndLand(i)` `""` for both.

So: racking the pulse rifle's charging handle back and letting it fly forward makes **no sound**;
the shotgun's pump has its back half (`STGNPUMP`, `:255`) and nothing on the forward stroke; a
magazine or shell dropped on the floor lands in silence (`RSR_DroppedMag.BounceSound` /
`RSP_DroppedShell.BounceSound` are set from `SndLand`, `vreload.zs:330`, `rsr_pump.zs:608`).

This is the single biggest "doesn't feel high quality" item in the reload and it is pure data. The
samples exist and the TC's own states already use them: `PULSREL1`, `PULSREL2`, `PULSREL3`,
`PTCLIPIN`, `PTCLIPOU`, `SMARTOUT`, `FLAMPICK`, `SHELLIN`, `STGNPUMP`, `DRYFIRE` all appear 3–22
times each in `actors/` (counted). `PULSREL2` and `PULSREL3` are currently **unused by the reload
tables entirely**.

**Fix:** fill the tables. `SndBack` / `SndFwd` for the rifles from `PULSREL2`/`PULSREL3`, `SndFwd`
for the shotguns from `STGNPUMP` (the same sample on both halves is still better than silence), and
`SndLand` from whatever metallic sample `_A01` offers — note `RSR_DroppedMag` has
`DeathSound ""` set explicitly (`vreload.zs:778`) and `BounceSound` is the hook.

---

### 2.9 — MEDIUM. Dual wield's "each hand keeps its own magazine" is not implemented

`DECORATE.aedual` gives each copy `Weapon.AmmoType1 "AE_*MagOff"` (`:29, 51, 73, 95, 117, 139, 161,
183, 205, 227`), with `Inventory.Amount 0` and `Ammo.BackpackAmount 0` on every `AE_*MagOff` class.

**Nothing in the pack ever gives an `AE_*MagOff` item.** `AE_DualTable.Mag(i)` and
`AE_DualTable.MagMax(i)` (`zscript/rsq/dualtable.zs:204-214`) exist for exactly that and are
**never called** (grep: declaration only). So the off gun's `AmmoType1` is permanently 0 while all
the TC's guns consume ammo through explicit `A_TakeInventory("PistolLoaded", 1)` and friends, not
through `AmmoType1`.

Outcome depends on the base classes' `AmmoUse1`, which lives in `_A01` and is **UNVERIFIED** here:
* `AmmoUse1 > 0` → `A_JumpIfNoAmmo("Dryfire")` always jumps and **the off-hand gun can never
  fire**; `A_WeaponReady`'s `CheckAmmo` may also try to switch it away.
* `AmmoUse1 == 0` → it fires and drains the **shared** `PistolLoaded`, i.e. the main gun's
  magazine. Fire the off pistol and the main pistol's count drops.

Either way the documented behaviour (`README.txt:21-23`, `dual.zs:43-47`,
`MENUDEF.ae:105`) is wrong. **Settle it** on the Windows exe: `+ae_dual_pistol 1 +ae_start_dual 1`,
`printinv`, fire the off trigger, `printinv` again.

**Smallest fix if `AmmoUse1 == 0`:** leave `AmmoType1` alone and give the copy its own loaded
counter the way the main guns do — patch the copy's `Fire` to take `AE_*MagOff`, which means the
copies need their own `Fire` states and stop being pure renames. If `AmmoUse1 > 0`, add
`Weapon.AmmoUse1 0` to each copy as a stopgap so they at least fire off the shared pool, and
document that the per-hand magazine is not done.

Also in `DECORATE.aedual`: the copies carry `+WEAPON.CHEATNOTWEAPON` and `SelectionOrder 99999`
but **not** `+WEAPON.NOAUTOSWITCHTO` or `+WEAPON.NO_AUTO_SWITCH`, unlike `RSQ_Hands`
(`hands.zs:396-398`). `dual.zs:90-92` relies on restoring `PendingWeapon` after
`GiveInventory`, which covers the pickup path but not an ammo-pickup-driven `PickNewWeapon`. Add
the two flags.

---

### 2.10 — MEDIUM. The dual copy is handed out on the second **tic**, not the second **pickup**

`zscript/rsq/dual.zs:123-130`:

```
Class<Inventory> gc = AE_DualTable.Gun(i);
bool own = gc && mo.FindInventory(gc);
if (own && had[n][i] && Enabled(p, i))
    GiveCopy(mo, i);
had[n][i] = own;
```

`had[n][i]` means only "owned it last tic". `AE_DualHandler` is a **map-scope** handler
(`mapinfo.txt:10`), so `had` starts false on every level. Tic 1: `own = true`, `had = false`. Tic 2:
`own = true`, `had = true` → `GiveCopy`. So with `ae_dual_pistol 1`, **you get the second pistol
two tics into every map just for carrying one**, and `ae_start_dual` is redundant.

`AE_DualTable.PickupGun(Name)` (`dualtable.zs:229-236`) exists to detect a real second pickup and
is **never called**.

**Smallest fix:** weapons have `MaxAmount 1`, so a second pickup is not visible in `Amount`.
Detect it where it happens: override `TryPickup`/`Use` on the `*spawner` actors, or add a
`CheckReplacement`/`ItemPickup` handler that calls `AE_DualTable.PickupGun(e.Thing.GetClassName())`
and sets a per-player latch. Until then, state in `MENUDEF.ae:106-108` that the toggle *is* the
switch.

---

### 2.11 — LOW. The free-feed shell is deleted rather than dropped

`zscript/rsr/rsr_pump.zs:887-898` (`End`) clears `hand` only when `mode == RSP.LOAD`; the comment
says *"the free feed keeps its own shell"*. `Abort` (`:878-885`) likewise only drops when
`mode == RSP.LOAD`.

The leak is covered — `RSP_Handler.WorldTick:1236-1241` clears `s.hand` when the gun is gone — but
it clears it **silently**: the shell in your hand vanishes rather than falling. **Fix:** call
`DropShell` there before clearing, as `Abort` does. Confirmed **not** a leaked actor; the layer and
the state both go.

### 2.12 — LOW. `rsr_assist_debug` rings draw as a blob, which is the "far too large" report

`zscript/rsr/rsr_assist.zs:221-231` spawns 16 particles of **size 3.0** on a ring of radius
`cap` cm converted to map units: 8 cm × 34/100 = **2.72 units**. Circumference ≈ 17 units over 16
points = 1.07 units of spacing, with 3.0-unit particles. They overlap into a solid disc about 2×
the zone's true radius.

**Fix:** `A_SpawnParticle(col, SPF_FULLBRIGHT, 2, 0.6, ...)` and/or 24–32 points. The ring is
already correctly placed (`ZoneRing`, `vreload.zs:245-251`, converts through `FromGun` properly).

### 2.13 — LOW. `RSQ_Strike` destroys itself inside the collision callback

`zscript/rsq/melee.zs:130-149`. `PIT_CheckThing` (`src/playsim/p_map.cpp:1655-1660`) does
`switch (SpecialMissileHit(thing)) { case 0: return false; case 1: return true; }`, where `false`
means *blocked* — so the `return 0` at `:148` tells the engine to explode a missile the script
already `Destroy()`d on the line before.

The returns are otherwise right: `victim == target` → `1` → passes through the shooter ✓.

**Fix:** delete the `Destroy()` and the inline puff spawn, and `return 0` — the existing `Death:`
state (`:157-172`) already spawns the puff and `P_ExplodeMissile` will reach it.

### 2.14 — LOW. The free-fist melee only works while a knife is held

`zscript/rsq/melee.zs:220-221`:

```
if (!KnifeHeld(p))
    continue;
```

This sits **before** the free-fist block at `:236-241`, which has its own cooldown
(`offCool`), its own `OffFree(mo)` test and its own `p.OffhandWeapon is 'RSQ_Hands'` test — all of
which say it was meant to be independent of the main weapon. The handoff §1 describes them as two
separate things ("Knife thrust … lands the knife's blow; fast punch with the free off fist lands a
fist"), and `CVARINFO.ae:72` says *"a fast thrust with the knife, **or** a fast punch with the free
fist"*.

**Fix:** move the `if (!KnifeHeld(p)) continue;` guard inside the knife block (lines 225–234) only.
Confirm with the owner that a fist with any gun in the main hand is wanted.

### 2.15 — LOW. First tic after a map load / teleport can throw a spurious melee strike

`zscript/rsq/melee.zs:214-217` differences `HandPos` against `handPrev[n]`, which starts `(0,0,0)`.
On the first tic of a map the delta is the player's whole world position, so `sh` is enormous. The
knife block then needs only `mv dot dir > 0.3` to fire a free hit. The same happens after any
teleport. `AE_FlickHandler` guards this correctly with `have[MAXPLAYERS]` (`flick.zs:62-67`);
`melee.zs` has no equivalent.

**Fix:** add a `bool have[MAXPLAYERS]` latch exactly as `flick.zs` does, and clear it on
`playeringame` false / `!InVR`.

---

## §3 Netplay

### 3.1 — CRITICAL (architectural). Every VR gesture in the pack mutates the playsim from local-only data

The kit states the rule the pack was built to (`docs/RELOAD_ON_QUEST.md`, "Traps"):

> **Netplay:** gestures are detected locally and decided over the net. Anything that changes the
> simulation keys on the owning player and travels by netevent; `consoleplayer` appears only to ask
> "are these my hands".

Verified in the engine: `AttackPos`, `OffhandPos`, `AttackDir`, `OffhandDir`, `PlayInVR` and
`OverrideAttackPosDir` are written **only** for `r_viewpoint.camera->player`
(`src/common/rendering/hwrenderer/data/hw_vrmodes.cpp:434-445` and
`hw_openxrdevice.cpp:586-610`). They are not in the usercmd, not serialised, and not replicated —
grep of `src/d_net.cpp`, `d_netinfo.cpp`, `d_protocol.cpp` for them returns nothing.

Every one of these runs in `WorldTick` for all players, reads those fields, and writes the playsim:

| file:line | local-only read | playsim write |
|---|---|---|
| `zscript/rsr/vreload.zs:381-548` (`RSR_State.Tick`) | `Frames()` → `HandDir`/`OffDir`/`OffPos` | `GiveInventory('RSR_Seated')`, `GiveInventory('RSR_Done')`, `Fall()` spawns `RSR_DroppedMag`, `Buzz()` spawns `RSVR_Buzz` |
| `zscript/rsr/rsr_pump.zs:241-354, 699-875` | same | `GiveInventory('RSP_ShellIn', credit)`, `RSP_Back`/`RSP_Fwd`/`RSP_Auto`/`RSP_Ready`, `Spawn('RSP_DroppedShell')`, `frandom(...)` in `CaseOut:499` |
| `zscript/rsq/flick.zs:61-103` | `HandPos` | `SetPsprite(PSP_WEAPON, Reload)` → the gun's whole ammo path |
| `zscript/rsq/melee.zs:211-241` | `HandPos`/`OffPos`/`HandDir` | `Spawn('RSQ_Strike')`, `DamageMobj`, **`random(1,10)` / `random(2,8)`** |
| `zscript/rsq/pumpgl.zs:309-358` | `AE_SwitchHandler.GunFrame` | `TakeInventory(loaded, 20)`, `GiveInventory('GrenadeAmmo')` |
| `zscript/rsq/switch.zs:83-89` | `GunFrame` | `SetPsprite(PSP_WEAPON, AltFire)` → toggles `SmartAlt` |
| `zscript/rsq/holster.zs:65-91` | `OffInBody` | `pl.PendingWeapon = w`, and spawns/destroys up to 7 ghost actors per player |
| `zscript/rsq/smartgun.zs:264-266, 333-348` | via `RSR_Handler.FreeHand` (local-only phase) | `a.tracer = s.lock` on `SmartgunTracer`, which steers a `+SEEKERMISSILE` |

Mechanism of the desync: on machine A player 0 is local (`InVR` true) and player 1 is not; on
machine B the reverse. The guards (`!RSVR_VRHand.InVR(mo)` → `continue`) therefore make the loop
take **different branches on each machine**, so each machine applies a different set of
`GiveInventory` / `Spawn` / `DamageMobj` calls. `melee.zs`'s `random(1,10)` is the worst of it: a
playsim RNG draw on a path only one machine takes desynchronises every subsequent RNG consumer in
the level.

The smartgun chain is worth calling out because it looks safe and is not: `Pick(mo)`
(`smartgun.zs:217-243`) uses only replicated data, but `:264-265` sets `on = false` from
`RSR_Handler.FreeHand(mo)`, which depends on the local-only reload phase. So `s.lock` differs
between machines and `a.tracer` differs, and the projectile seeks a different target on each.

Exactly one path in the pack is done the kit's way, and it shows the shape of the fix:
`RSR_Handler.InputProcess` (`vreload.zs:979-1007`) reads the raw key for `consoleplayer` and sends
`EventHandler.SendNetworkEvent("rsr_grip", ...)`, consumed in `NetworkProcess` (`:948-975`). The
grip is correct. Nothing else is.

**Fix (large, and an owner decision):** the pack is single-player-only as it stands, and that should
be written down. To make it netplay-safe, every gesture handler must split the way the grip does:
detect locally (`if (n != consoleplayer) continue;`), send a netevent carrying the decision and any
geometry the playsim needs, and perform all `GiveInventory`/`Spawn`/`Damage`/`SetPsprite` work in
`NetworkProcess` keyed on `e.Player`. Replace `random()` in `melee.zs` with a damage value computed
in `NetworkProcess` or a fixed value. Given the family rule that netplay desync is a hard rule, and
the crossplatform-co-op goal, this is the pack's largest outstanding debt.

### 3.2 — LOW. Cached `CVar` handles make player 0's settings apply to everyone

`zscript/rsq/hands.zs:469` (`transient CVar cvHands, cvSwap;`) and the same pattern at
`flick.zs:31`, `switch.zs:43`, `holster.zs:28`, `dual.zs:63`. Each is looked up once with
`CVar.GetCVar(name, p)` **inside** a loop over all players, so the first player's handle is reused
for the rest. `ae_hands` is `user` (per-player); `ae_flick_reload`, `ae_handswitch`, `ae_holsters`
and `ae_dual_*` are `server`, so only `ae_hands` actually diverges.

Presentation-only, so not a desync. **Fix:** drop the cache and call `CVar.GetCVar(name, p)` per
player, or cache per player index.

---

## §4 Data-side

### 4.1 — HIGH. `MENUDEF.ae`'s "Grab ammo with → Use key" is actually the **jump** button

`MENUDEF.ae:25-30`:

```
OptionValue "AE_GrabWith"
{
    67108864, "Off hand trigger"
    4,        "Use key"
    67108868, "Either"
}
```

From the engine (`src/d_event.h:43-44`, mirrored in
`wadsrc/static/zscript/constants.zs:835-836`): `BT_USE = 1<<1 = 2`, `BT_JUMP = 1<<2 = 4`.
`BT_OFFHANDATTACK = 1<<26 = 67108864` ✓.

So selecting "Use key" sets `rsr_grab_buttons = 4` → `RSR.GrabMask` returns `BT_JUMP`, and
**jumping grabs a magazine**. "Either" (67108868 = `BT_OFFHANDATTACK | BT_JUMP`) does it while also
keeping the trigger.

**Fix:** `2, "Use key"` and `67108866, "Either"`.

BD22 1.92 sidesteps this entirely by exposing an enum (`rsr_grab_with` 0/1/2, `CVARINFO.rsq`) and
translating it in script rather than putting raw button masks in a menu — worth copying if the
values keep drifting.

### 4.2 — MEDIUM. Docs promise a cvar that does not exist, and cvar names diverge from 1.92

* `SMARTGUN.md:65` and `:48` document `ae_smartturn` as a live switch
  (*"degrees a tic a round may turn (default 6, 0 = off)"*), and `README.txt:23-25`/
  `zscript/rsq/smartgun.zs:26,155-157` describe the steer. **`ae_smartturn` is not declared
  anywhere** — `CVARINFO.ae:21-26` says it was removed, and a grep finds it only in comments. The
  removal was correct (the base TC's `SmartgunTracer` is `+SEEKERMISSILE` and self-steers); the
  docs were not updated. Fix `SMARTGUN.md` §"Switches" and §"Rounds that track".
* The master reload switch is `rsq_reload` here (`CVARINFO.rsr:10`, **`server int`**) but
  `rsr_reload` in 1.92 (`CVARINFO.rsq`, **`user int`**). `CVARINFO.rsr:7` claims *"BD22 declares it
  on the RSQ (hands) side"* — it does, but under a different name. Two consequences: a player who
  knows 1.92's menu will not find it, and because it is `server` a client in a netgame cannot turn
  the VR reload off. 1.92's `user` scope is the better choice.
* Similarly `ae_hands` here vs `rsq_hands` in 1.92.

### 4.3 — MEDIUM. Menu gaps against 1.92, all of which matter with a headset on

The kit's rule (`docs/RELOAD_ON_QUEST.md`): *"Both debug toggles have menu rows **on purpose**: a
console command cannot be reached with a headset on."* 1.92's `MENUDEF.rsq:77-79` has a
"RELOAD: TUNING AND DEBUG" submenu with both. `MENUDEF.ae` has `rsr_assist_debug` (`:59`) but:

| cvar | declared | menu row | 1.92 has a row |
|---|---|---|---|
| `rsr_debug` | `CVARINFO.rsr:16` | **no** | yes |
| `rsr_shell_credit` | `CVARINFO.rsr:23` | **no** | yes ("Shotgun Shells Per Insert") |
| `rsr_pouch` | `CVARINFO.rsr:14` | **no** | no |
| `rsr_magrelease` | `CVARINFO.rsr:13` | **no** | no |
| `rsr_eat_grip` | `CVARINFO.rsr:15` | **no** | no |
| `ae_glpump_travel` | `CVARINFO.ae:90` | **no** | n/a |
| `ae_stab_speed` / `ae_stab_reach` | `CVARINFO.ae:73-74` | yes | n/a |

`rsr_debug` is the one that hurts: the whole documented procedure for finding a headset's grip key
codes (handoff §3, `CVARINFO.rsr:16`, `vreload.zs:986-987`) is "turn on `rsr_debug` and read the
printed codes" — and it cannot be turned on from inside the headset.

Also: `OptionMenuItemRSRReload` (`vreload.zs:1028-1030`) is declared for a MENUDEF item named
`RSRReload` that `MENUDEF.ae` does not use. Dead; harmless.

### 4.4 — LOW. Dead generated tables

Declared and never called (grep-verified):

* `zscript/rsq/dualtable.zs:204` `Mag(i)`, `:210` `MagMax(i)`, `:222` `Nice(i)`, `:229`
  `PickupGun(n)` — see 2.9 and 2.10.
* `zscript/rsr/rsr_guns.zs:84` `MagLen(i)`, `:177` `HasHandle(i)`, `:380` `Offset(i)`, `:578`
  `MagAmmo(i)`.
* `zscript/rsr/rsr_pump_guns.zs:171` `Offset(i)`, `:322` `MagAmmo(i)` (and wrong, see 2.1).
* `zscript/rsr/rsr_guns.zs:652` `HandleFrame(i, t)` returns 0 unconditionally, so the
  `else` branch at `vreload.zs:597-604` always falls through to `ShowReady`. Fine, but it means the
  gun's own bolt-back frames are never used for the guns where `HandleLayers(i)` is false (3, 4, 9,
  10) — those four have `ChargeRule 0` so they never pull a handle anyway. Consistent.
* `BoltRatio(i)` is 0 for all ten magazine guns and both shotguns, so layers `RSR.BOLT` (2104) and
  `RSP.BOLT` (2121) are never shown (`vreload.zs:634`, `rsr_pump.zs:960`).

Nothing to fix; worth deleting so the next session does not assume they work.

### 4.5 — Checked and correct (so nobody re-checks)

* All 11 EventHandlers in `zscript/` are registered: `mapinfo.txt:10` `AddEventHandlers` lists
  `RSQ_HandHandler, RSR_Handler, RSP_Handler, AE_SwitchHandler, AE_SmartHandler,
  AE_HolsterHandler, AE_FlickHandler, AE_DualHandler, RSQ_Ballistics, RSQ_MeleeHandler,
  RSQ_PumpGL` — and the declarations are exactly those 11 plus A03's five on `:4`.
* `InputProcess` **does** reach a map-scope handler: `g_game.cpp:1103`
  `primaryLevel->localEventManager->Responder(ev)` → `events.cpp:954-963` calls
  `handler->InputProcess`. The grip-key path works.
* The pulse-rifle counter: 100 `Model RSQ_GunSide` blocks, 100 distinct `RSC0..RSC3` sprite/frame
  pairs, all `Skin`-per-block (which is why one block per value is genuinely required here), and
  `RSQ_CounterSprites` (`counter.zs:26-37`) declares exactly `RSC0 A..]`, `RSC1 A..]`, `RSC2 A..]`,
  `RSC3 A..M` = 29+29+29+13 = 100 names. `counter.md3` has 1 frame and all blocks use frame 0 ✓.
* `rsr_pump.zs:371`'s `(BT_RELOAD | (1 << 20))` is correct: `1<<20` is `BT_MAINHANDRELOAD`
  (`constants.zs:869`). Use the named constant.
* `"GAS"` vs the TC's `Gas`: harmless. `FName` lookup is `stricmp` (`src/common/utility/name.cpp:116`),
  so `RSR_Guns.Reserve(4)` resolves.
* Every sound name in the reload tables is used 3–22 times by the TC's own states in `actors/`, so
  they all exist in `_A01`.
* `RSQ_GunMoves.Pivot/Blends/Mirrored` arrays are correctly sized (51 / 17 / 17) and the Yutani
  twin of every gun carries the same row. `Frame()`'s 240 rows cover indices 2–16 and omit 1, 7, 11,
  14 — exactly the four guns with `Blends = 0`. Consistent.
* `RSR_GunParts`, `RSR_PartStates` and `RSQ_GunSide` all inherit `Spawn: TNT1 A -1; Stop;` from
  `Actor` (`wadsrc/static/zscript/actors/actor.zs:1526-1530`), so the missing `Spawn:` labels are
  fine.
* `RSR_Call` / `RSP_Call` return `false` from `TryPickup`, so the signal items are destroyed and do
  not accumulate.
* `RSR_DroppedMag` / `RSP_DroppedShell` do reach their `Death:` state: `BounceType "Doom"` is
  `BOUNCE_Doom` which includes `BOUNCE_AutoOff` (`src/playsim/actor.h:566`), and
  `FloorBounceMissile` clears the bounce flags once the vertical speed drops
  (`p_mobj.cpp:1893-1900`), after which the next floor contact explodes the missile into `Death` →
  350 tics → `A_FadeOut` removes it. **No actor leak.**
* `ModifyBobPivotLayer3D` is broken in this build (kit: `hw_weapon.cpp:973-974` vs `weapons.zs:48`)
  and the pack correctly does not use it — it implements its own pivot via `RSQ_GunMoves.Pivot` and
  `RSQ_Turn.Place`.
* `psp.bAddBob = true` is set on every layer the pack creates (`hands.zs:579`, `vreload.zs:136`),
  which `hw_weapon.cpp:953` requires for `ModifyBobLayer3D` to be called at all.

---

## §5 LOADING ALONGSIDE ANOTHER WEAPON MOD

The owner's snag is explained. This pack and BD22 VR-Reloaded 1.92 **cannot both be loaded** — not
"will misbehave", but will not start.

### 5.1 — FATAL. Duplicate ZScript class definitions

Both packs are the same codebase with the same class names in the same `rsq`/`rsr`/`rsvr`
namespaces. Verified from 1.92's own lumps (its MODELDEF blocks name its classes, so the classes
exist):

| class | this pack | BD22 1.92 |
|---|---|---|
| `RSQ_Hands` | `hands.zs:335`, `MODELDEF.ae:47` | `MODELDEF.rsq`, `MODELDEF.rsr`, `MODELDEF.rsrpump`, `MODELDEF.rsb` |
| `RSQ_GunSide` | `hands.zs:194`, `MODELDEF.ae:9` | `MODELDEF.rsq` |
| `RSQ_Debris` | `ballistics.zs`, `MODELDEF.debris` | `MODELDEF.rsq` |
| `RSR_GunParts` | `vreload.zs:723` | `MODELDEF.rsr`, `MODELDEF.rsrpump` |
| `RSR_DroppedMag` | `vreload.zs:758` | `MODELDEF.rsr` |
| `RSP_DroppedShell` | `rsr_pump.zs:1040` | `MODELDEF.rsrpump` |

And, from the shared source lineage, every other name in `zscript/rsvr/` + `zscript/rsq/` +
`zscript/rsr/`: `RSVR_Token`, `RSVR_Buzz`, `RSVR_VRHand`, `RSQ_HandTable`, `RSQ_HandTune`,
`RSQ_Place`, `RSQ_Layers`, `RSQ_Turn`, `RSQ_GunMoves`, `RSQ_HandHandler`, `RSR`, `RSR_State`,
`RSR_Call`, `RSR_Start`, `RSR_MagOut`, `RSR_Tick`, `RSR_Filled`, `RSR_Go`, `RSR_Seated`,
`RSR_Done`, `RSR_Charge`, `RSR_PartStates`, `RSR_Handler`, `RSR_Guns`, `RSR_GunSprites`,
`RSR_Assist`, `RSP`, `RSP_State`, `RSP_Call`, `RSP_LoadStart`, `RSP_PumpStart`, `RSP_LTick`,
`RSP_PTick`, `RSP_Go`, `RSP_ShellIn`, `RSP_Insert`, `RSP_Back`, `RSP_CaseOut`, `RSP_Fwd`,
`RSP_Auto`, `RSP_Ready`, `RSP_Guns`, `RSP_Sprites`, `RSP_Handler`, `OptionMenuItemRSRReload`.

A ZScript class defined twice is a hard load error. **UNVERIFIED only in the exact wording of the
message**; the collision itself is certain.

**What to do:** one of the two has to be renamed wholesale. This pack is the one to rename (1.92 is
the owner's shipped reference): `RSQ_* → AEQ_*`, `RSR_* → AER_*`, `RSP_* → AEP_*`,
`RSVR_* → AEVR_*`, and the same in `MODELDEF.ae`, `MODELDEF.rsr`, `MODELDEF.rsrpump`,
`MODELDEF.debris`, `MODELDEF.holster`, `MODELDEF.aedual`, `mapinfo.txt:10` and every generator in
`tools/`. **Caution:** `vreload.zs:602,790` and `rsr_pump.zs` identify a reload-capable player with
`OffhandWeapon is 'RSQ_Hands'`, and `hands.zs:10-12` calls that name "the kit's interface" — the
rename must be total or the reload silently stops seeing the hands.

The kit's own instruction is the same shape and worth quoting at the owner:
*"**The three modules number their guns separately** — an index means nothing without its module …
In the `Mag*` tables, BD22 index 1 is `Rifle` and V+ index 1 is `VR_Rifle`, so leave index 1 at the
default or the two sets drag each other"* (`docs/RELOAD_ON_QUEST.md`). Two packs sharing
`RSR_Assist` would have exactly that problem even after a class rename, if `rsr_assist.zs` were
shared.

### 5.2 — Shared cvars: one slider moves both packs

Declared with identical names, types and defaults in both `CVARINFO.rsr` files (this pack) and
1.92's `CVARINFO.rsr`:

`rsr_grip_keys`, `rsr_grab_buttons`, `rsr_magrelease`, `rsr_pouch`, `rsr_eat_grip`, `rsr_debug`,
`rsr_assist`, `rsr_assist_debug`, `rsr_shell_credit` — plus `rsq_ballistics` (1.92's
`CVARINFO.rsq`).

Same type and default, so GZDoom will not error, but the two packs then share one value. "Reload
assist" in one menu retunes the other pack's capture zones. These must be renamed with the classes.

Diverging names for the same control (§4.2): `rsq_reload` vs `rsr_reload`, `ae_hands` vs
`rsq_hands`, `rsr_grab_buttons`-as-mask vs `rsr_grab_with`-as-enum. After a rename these are
separate switches, which is correct — but note that 1.92's `rsr_grab_with` and this pack's
`rsr_grab_buttons` are **both** read by code that would exist twice, so pre-rename the enum/mask
mismatch is live.

### 5.3 — `keyconf.txt` takes over the weapon slots and the player classes

`keyconf.txt:1-16`:

```
clearplayerclasses
addplayerclass ColonistPlayer
... (4 classes)
weaponsection "ColonialMarineArsenal"
setslot 1 Loader_3D AELoader_3D Knife_3D YutaniKnife_3D
... setslot 7 ...
```

* **`clearplayerclasses`** removes every player class registered before it, including any another
  mod added.
* **`setslot 1` … `setslot 7`** *replace* those slots outright. 1.92's `KEYCONF.rsq` does
  `weaponsection "Brutal_Doom"` + `addslotdefault 1 RSQ_Hands` — its off-hand fist in slot 1, which
  is **how 1.92 puts the fist back in the off hand**. With two weapon sections present, whichever
  section is active loses the other's slot assignments. On the AE section the player cannot get
  1.92's off-hand fist back; on the BD section the AE guns are not slotted.

`KEYCONF.ae:11`:

```
defaultbind Pad_X ae_dualkey
```

`Pad_X` is free in QuestZDoom's default layout (`KEYCONF.ae:8-9` says so), which makes it exactly
the button any other VR weapon mod will also grab. Last KEYCONF parsed wins, silently.

`keyconf.txt:18-20` also does `AddMenuKey "Adrenaline" speed` / `alias speed "pukename SPEED"` /
`defaultbind U speed` — the alias name `speed` shadows nothing in GZDoom but is generic, and the
ACS script name `SPEED` is a global name in the puke namespace.

**What to do:** split `keyconf.txt`'s slot/class block out of the pack and ship it as an optional
lump, or at minimum change `defaultbind Pad_X` to no default bind and tell the player to bind it
(the menu key already exists). Keep `clearplayerclasses` only if the pack is meant to be the only
weapon mod — which the README (`README.txt:4-12`) says it is.

### 5.4 — `mapinfo.txt:4` uses `EventHandlers =`, which replaces the list

```
EventHandlers = "weather_event", "AEnvItemReplace", "PlayerPropModifier", "SuperHumanMovesHandler", "EnhancedVision"
```

The pack's own comment on `:6-9` explains that `EventHandlers =` replaces rather than adds — and
then uses it anyway on line 4. So another mod whose MAPINFO `GameInfo` also says
`EventHandlers =` will kill these five, or be killed by them, depending on which MAPINFO is read
second. Only the `AddEventHandlers` line (`:10`) is safe.

**Fix:** change line 4 to `AddEventHandlers` as well. One-word change, no behaviour change when
loaded alone.

### 5.5 — Shared sprite names

Both packs use the same four-character hand sprites: `RQGS`, `RQGT`, `RQGU`, `RQSP`, `RQHN`,
`RQUN` (1.92's set, extracted from its MODELDEF lumps, is `RQ2T RQAM RQAP RQAW RQBM RQBP RQBW RQDM
RQDP RQDW RQGF RQGN RQGS RQGT RQGU RQHN RQHR RQLM RQLP RQLW RQMM RQMP RQMW RQNP RQPM RQPP RQPW RQRM
RQRP RQRW RQSP RQUG RQUN RQUP RQUW RQZM RQZP RQZW`).

MODELDEF keys on (class, sprite, frame), so once the classes are renamed the sprites can safely
coincide. Before the rename they are a second layer of the same collision: the two packs' different
`hand.md3` cuts bound to the same `RSQ_GunSide`/`RQGS A` key, last block wins. **Note the frame
counts differ** — this pack's `hand.md3` has 16 frames, 1.92's has at least 44
(`docs/FINGER_ON_TRIGGER.md`: BD22 trigger frames occupy "frame range 10..43"), so the wrong winner
means out-of-range frame indices.

### 5.6 — Handlers that assume they own the player

Even after a rename, two behaviours would fight another VR weapon mod from the same family:

* `RSQ_HandHandler.WorldTick` (`hands.zs:500-501`) sets `p.PendingWeapon = hands` whenever
  `!p.OffhandWeapon`. 1.92's equivalent does the same for its own `RSQ_Hands`. Two handlers, one
  off-hand slot: each sees the other's weapon there, and whichever runs later wins — per tic.
* `RSQ_Layers` 2100 / 2101 / 2200 are documented in both packs as "rsq/hands.zs owns" them, and
  `SetLayer` destroys a layer whose caller is not its own (`hands.zs:563-568`). Two handlers on the
  same ids destroy each other's hand every tic.

Both would need a single owner, or distinct layer ids. 1.92 already reserves ranges (2102–2104,
2105–2111, 2120–2123, 2201, 2202, 2210); this pack reuses them identically.

### 5.7 — `replaces` chains

Every gun in `actors/weapons/*.txt` is `ACTOR X_3D : X replaces X`. Another mod replacing the same
TC actors is a last-one-wins race. `zscript/replacements.txt` and the `*spawner` actors
(`shotgun.txt:843`, `smartgun.txt:574`, …) are the same pattern. Unavoidable given what the pack
is; worth stating in `README.txt` next to "Do NOT load `_A03` as well".

---

# PART 2 — QoL, and the best Aliens set we can build

Mod-side on unmodified QuestZDoom 17.3 unless marked. Ranked by player impact ÷ effort.
Quest cost is stated honestly: the GPU budget goes on pixels and dynamic lights, not on psprite
layers, which are a handful of triangles each.

## Tier 1 — fix the four things the owner named

### Q1. Make the four hand bugs the next commit (1.1, 1.2, 1.3, 1.6)

What the player feels: the hand stays where it was fitted, in both hands, through recoil; the
trigger finger squeezes instead of teleporting; the sliders move the hand the way their labels say.
Files: `zscript/rsq/hands.zs`, `DECORATE.aedual` → a new `zscript/rsq/dual_off.zs`,
`MODELDEF.aedual`, `tools/gen_aedual_modeldef.py` (write it with the y/z swap).
Cost: zero — same number of layers, same models. Risk: low for 1.2/1.3/1.6; medium for 1.1 because
moving the ten copies from DECORATE to ZScript touches their flags and ammo properties.
**Mod-side.**

### Q2. Fill the reload sound tables (2.8)

What the player feels: the reload stops being mime. The charging handle *clacks* back and *slams*
forward, the pump has both halves, a dropped magazine hits the deck behind you.
Files: `zscript/rsr/rsr_guns.zs` `SndBack`/`SndFwd`/`SndLand`, `zscript/rsr/rsr_pump_guns.zs`
`SndFwd`/`SndLand`. All ten/two rows currently `""`.
Cost: zero. Risk: zero. Highest feel-per-line in the whole audit. **Mod-side.**

### Q3. Haptics on every confirm (handoff §4 open item)

`RSR_State.Buzz` (`vreload.zs:334-337`) already exists and already fires at: taking a magazine,
catching it at the well, seating it, taking the handle, racking it. `RSP_State` calls it at taking a
shell, catching it, seating it, taking the pump, reaching the back of the stroke. **What has no
buzz:** a melee hit landing (`RSQ_Strike.SpecialMissileHit`), a shell or magazine *dropped*, the
launcher pump's grenade, the fire selector flick, and every "refused" case (tube full, no reserve,
not enough rounds for a grenade).
The kit documents the second haptic channel too: *"Haptics, left or right, chosen duration: a
quake's X strength buzzes left, Y right — `r_utility.cpp:116,1084-1092`"*. So a refusal can be a
short double-tap on the *off* hand and a seat a longer single on the gun hand, which is readable
without looking.
Cost: zero. Risk: low. **Mod-side.**

### Q4. Per-gun capture radii by lever arm, not one number (the kit's own rule)

`docs/RELOAD_ON_QUEST.md`: *"**a radius is a wrist angle** … when a part 'doesn't catch', measure
the lever arm before touching the insertion point."*

`RSR_Assist.MagCapture` (`rsr_assist.zs:104-107`) returns the same 8 cm for all ten guns. The lever
arms are already in the pack — `|RSR_Guns.TopInHand(i)|`:

| gun | `TopInHand` | lever arm | wrist angle at 8 cm |
|---|---|---|---|
| pistols (1, 5, 6, 7) | (2.814, 3.905, 8.157) | 9.47 cm | 40° |
| rifles (2, 8) | (-0.840, 3.914, 9.036) | 9.88 cm | 39° |
| smartguns (3, 9) | (8.609, 1.777, -5.067) | 10.14 cm | 38° |
| **flamers (4, 10)** | (-0.598, 3.859, 13.705) | **14.25 cm** | **29°** |

The flamer's 29.3 cm tank is held furthest from the wrist and gets the tightest angle, which is the
one the owner will call impossible. Method, not a magic number: pick a target wrist angle (the
pistol's 40° is the one that already feels right) and set each gun's row to
`lever_arm * tan(target)`.
Files: one `switch (i)` row in `rsr_assist.zs:104`. Cost: zero. Risk: low. **Mod-side.**

### Q5. Hold the squeeze frame for the shot, not for the button

§1.9. `hands.zs:527` reads `BT_ATTACK` only, so on a single shot the finger springs back while the
gun is still cycling. Latch it: show `Sqz` while `BT_ATTACK` **or** while
`!(p.WeaponState & WF_WEAPONREADY)` and the last fire was within N tics. One line. Pairs with Q1's
blend so the finger curls and uncurls instead of flickering. **Mod-side.**

## Tier 2 — the pulse rifle, properly

### Q6. The counter is the gun's face — use all of it

The 100-value LED already works and is the best diegetic thing in the pack. Four additions, all
cheap, all in `counter.zs` + a handful of `MODELDEF.ae` blocks:

* **Dim/blank when the magazine is out.** The handoff already lists this (§4). `RSQ_Counter.Tick`
  knows the phase via `RSR_Handler.FreeHand(mo)`; point it at a `cXX_dim.png` skin set, or simply
  at a blank frame while `RSR_NoMag_PulseRifle` is held. Right now the counter keeps showing the
  old count while the gun has no magazine in it — and after 2.2 it shows `00` while holding 60
  stranded rounds, which is actively misleading.
* **Count down per shot, not per tic.** It already does (`CountInv`), but it jumps by 2 because the
  rifle fires two `HeavyTracer` per Fire (`rifle.txt:71-72`). That is correct and film-accurate —
  the M41A counter in *Aliens* steps in multiples. Leave it; mention it so nobody "fixes" it.
* **Flash on empty.** Two extra states alternating a lit/blank `c00` at ~6 tics while
  `PulseLoaded == 0`, which is 2 states and 2 blocks.
* **Launcher count.** The underbarrel grenade count has no diegetic readout at all; the counter
  window is two digits and the launcher never exceeds a handful. A second quad on the receiver, or
  a brief mode where the window shows the grenade count for ~1 s after a pump stroke
  (`pumpgl.zs:356` already knows the moment).

Cost: the counter is one 2-triangle quad with a 100-texture atlas already in RAM; the extra skins
are small PNGs. Risk: low. **Mod-side.**

### Q7. Make the handguard pump move (handoff §4.3)

The mesh surface `m41a_pump` exists. `MODELDEF.rsrpump` is the worked example of how to split a
surface onto its own layer with `rsr_clear.png` on the rest, and `RSQ_PumpGL` already tracks the
stroke (`held`, `startF`, `pull` equivalent in `o.x - startF`). The missing piece is a `RSR_GunParts`
layer carrying the pump surface, offset by the stroke — i.e. `RSP_Guns.PumpHook`'s pattern applied
to the rifle.
What the player feels: the single most physical gesture on the icon weapon stops being invisible.
Cost: one extra psprite layer during the stroke, with a clear skin on the rest of the mesh — the
kit confirms Quest discards fully transparent surfaces
(`docs/QuestReload_Diagnosis.md`: *"a fully transparent skin, and Quest discards it"*). Effectively
free. Risk: medium (surface indices must be measured off `m41a.md3`). **Mod-side.**

### Q8. Burst cadence and the pulse-rifle sound layer

The M41A's signature is a ~4-round burst at a very high rate with a distinctive tail. Currently
`Fire` is `A_ReFire` on a 3-tic loop with `PULSELOOP` held on channel 1 and stopped on release
(`rifle.txt:66-78`). Two mod-side moves:

* **A real burst**: count rounds in `A_ReFire`'s loop and force a short enforced pause after 4,
  gated behind an option so the owner can A/B it. Pure state work in `rifle.txt`.
* **Layer the sound**: `PULSELOOP` is one looping sample on one channel. Add a per-shot transient
  on `CHAN_AUTO` with `CHANF_OVERLAP` (the pack already uses that idiom in `melee.zs:262`) and a
  single tail sample on release in place of the bare `A_StopSound(1)`. The TC's library is fair
  game for the transient.

Cost: audio channels only. Risk: low, but it changes the set's sound, so it wants an option and the
owner's ear.

### Q9. Muzzle flash as the only light in a dark corridor

This is the Aliens image. `rifle.txt:197-208` already has a `MuzzleFlash` path gated on
`avw_weapons_mf`, and `gldefs.txt` exists in the pack. The cheap, high-impact version is a
**one-tic, short-radius dynamic light** on the flash frames only — `gldefs` `FlickerLight`/
`PulseLight` attached to the flash actor, radius kept small.
**Honest cost: this is the one expensive idea in Part 2.** The memory note for this family says
dynamic lights are the measured VR cost. One light for one tic per shot is affordable; one per
tracer is not. Keep it off the tracers, keep the radius under ~96 units, and make it an option.
Risk: medium (perf). **Mod-side.**

## Tier 3 — the smartgun as a smartgun

### Q10. The gimbal needs to be *seen* working

The harness swing already exists (`smartgun.zs`, 22° yaw / 16° pitch, 18% ease) and is the single
best idea in the pack. What is missing is the player knowing it is happening:

* **The visor.** `graphics/AVISOR0..10.png` and `graphics/NOVIS0..10.png` are already in the pack
  (11 frames each) and `graphics/radar/RDR1A0..K0.png` likewise, and `sbarinfo.txt` exists. There is
  also `models/weapons/smartgun/smart_hud.md3` and `smart_mode1/2.png` + `_bm` brightmaps —
  **a HUD mesh and a mode readout that nothing in `zscript/` references.** That is the smartgun's
  diegetic display, shipped and unused. Putting the lock state on it (`AE_SmartState.lock`
  non-null) is the difference between "a chaingun that wanders" and "a gun that sees".
* **A lock tone.** `A_JumpIfTargetInLOS` currently fails silently: `SMRT G 1` then
  `Goto RealReady` (`smartgun.txt:56-57`), so holding the trigger with no target does nothing at
  all with no feedback. A short acquire/lose tone on `s.lock` transitions (the handler already
  tracks `s.had` for exactly this and never uses it, `smartgun.zs:286`) costs nothing.
* **The drum.** `m56.md3` has 6 surfaces (`MODELDEF.rsr:242-256` skins 0–5). If one of them is the
  drum, spinning it with `roll` on a `RSR_GunParts` layer while firing is the chaingun→smartgun
  tell. **UNVERIFIED** which surface; settle with `tools/md3.py` / `tools_md3_render.py`.

Cost: the visor is 2D (free); the HUD mesh is one more small model layer; the drum is one layer.
Risk: low. **Mod-side.**

### Q11. Target seeking that reads as seeking

`WorldThingSpawned` already hands `SmartgunTracer` the gun's lock (`smartgun.zs:347`) and the base
TC's `+SEEKERMISSILE` does the steering. Good decision, do not change it. What would read better is
**where the rounds come from**: `A_FireProjectile("SmartgunTracer", random(-1,1), 1, 7, -12, ...)`
spawns at a fixed offset, not at the gun's gimballed muzzle. In VR the gun is visibly pointing
somewhere the rounds do not come out of. There is no mod-side way to spawn a projectile at a
psprite's drawn muzzle (the kit: *"No engine path draws a world actor at a controller"*), but the
gimbal's own `putX/putY` could be converted to an angle/pitch offset and passed to
`A_FireProjectile`'s angle and pitch arguments, which closes most of the gap. Risk: medium (netplay
— see 3.1). **Mod-side.**

## Tier 4 — handling that uses VR

### Q12. One-handed penalty, two-handed reward

The engine's two-hand steadying is already there and the support hand already shows only while it
is active (`hands.zs:517`, `:530`) — that is the reward half, and it is well done. The penalty half
does not exist: a one-handed pulse rifle is as accurate as a braced one. `WF_TWOHANDSTABILIZED` is
readable from script (`RSVR_VRHand.Steadied`), so a per-gun spread multiplier applied to the
`random(-1,1)` arguments in each `A_FireProjectile` is mod-side and small. Gate it behind an option;
it is a gameplay change.
Caution: do it in the weapon states (replicated) and not from an EventHandler reading `Steadied`,
or it joins §3.1.

### Q13. The satchel charge wants its own gesture

`actors/weapons/grenade.txt` + `modeldef.grenade.txt`. Handoff §1: *"Satchel: trigger throws,
grip+trigger places."* That is two button combinations for the most physical object in the set. A
satchel is a thing you **stick to a wall** or **lob**: `RSQ_MeleeHandler` already has the
hand-velocity machinery (differenced `AttackPos`, a direction, a cooldown) and
`flick.zs` the "fast then stopped" test. Throw on a real throw, place on a slow press against a
surface. Cost: zero (no new models). Risk: medium — it is a new gesture and it is a §3.1 netplay
path, so build it the grip's way (detect local, decide by netevent) from the start.

### Q14. A light source in the hand

Aliens is a dark-corridor set and the pack has no flashlight. There is nothing mod-side that puts a
light on a controller cheaply — a dynamic light must hang off a world actor, and the kit says a
world actor moved each tic trails by a tic. The affordable version: attach the light to the
**player**, not the hand, with a forward bias along `AttackDir`, and put the *lamp* on a psprite
layer so it looks hand-held. `models/weapons/mech/loader_lamp.md3` + `loader_lamp_bm.png` exist
already. **Expensive on Quest** if it is a large-radius light — keep it tight and spotlight-shaped
via `gldefs`. Risk: medium (perf). **Mod-side, with a caveat.**

### Q15. Melee: finish what is there

Beyond the two bugs (2.13, 2.14): the knife has a cooldown of 12 tics and a flat
`2 * random(1,10)` (which must go for §3.1 anyway). A stab that reads well wants **direction
mattering** — it already does, via `mv dot dir > 0.3` — plus a hit sound that differs on flesh vs
metal (`sounds/melee/` ships `KNSTON`, `MET04`, `DSMETALB`, `FOOTWALL` and four `PLSPNCH*`, all
currently reachable only through the TC's own puffs). And a buzz on contact (Q3).

## Tier 5 — diegetic over HUD

### Q16. What the set already ships and does not use

Worth an owner decision before anything new is built. All present in the repo, all unreferenced by
`zscript/`:

* `models/weapons/smartgun/smart_hud.md3`, `smart_mode1.png`/`_bm`, `smart_mode2.png`/`_bm` — the
  smartgun's own display and fire-mode readout.
* `graphics/AVISOR0..10.png`, `NOVIS0..10.png`, `graphics/radar/RDR1A0..K0.png`, `PDR1K0.png` —
  a visor and a motion tracker, 11 frames each.
* `models/weapons/mech/loader_lamp.md3` + brightmap, `mechaloader_spark.md3`,
  `loader_spark*.png` — the Power Loader's lamp and sparks.
* `models/rsq/debris/` — 12 debris meshes and 3 textures, wired to `rsq_ballistics`
  (default **off**, `CVARINFO.ae:60`).
* `shaders/SimSun.fp`, `gldefs/ModelShading.txt`.

The motion tracker in particular is *the* Aliens diegetic instrument and it is sitting in
`graphics/radar/` unused. A tracker is a 2D overlay (free) or, better, a model on a psprite layer
in the off hand when the off hand is empty — which the pack can do today, because the free hand is
already an off-hand-weapon-owned layer and `RSQ_Hands` already has states for it.

### Q17. Power Loader

Handoff §5 plus the owner's note *"much of the model is being hidden"*. Before cutting the mesh,
check three things in order: `modeldef.loader.txt`'s `SurfaceSkin` / clear-skin blocks (the same
`rsr_clear.png` trick used deliberately elsewhere in the pack can hide a surface by accident),
the `avw_weapons` cvar gate (`cvarinfo.txt:19`, read by `A_JumpIf(GetCVAR("avw_weapons")==0, ...)`
in several guns), and whether `mechloader.md3`'s surfaces are being skinned past
`DPSprite::RS_SURF_SLOTS`. That is a diagnosis job, not a modelling job; don't cut the mesh yet.

## Honest performance summary

Cheap to free (psprite layers, states, sounds, tables, 2D overlays): Q1–Q8, Q10, Q11, Q12, Q13,
Q15, Q16. Each extra model layer is a few hundred triangles and one draw call, and fully
transparent surfaces are discarded by the Quest renderer.

Costs real frames: **Q9 (muzzle-flash dynamic light)** and **Q14 (hand light)**. Dynamic lights are
the measured VR cost on this engine. Both must be options, both must keep radii small, and neither
should ever be per-tracer.

One existing cost worth knowing: `AE_SmartHandler.Pick` (`smartgun.zs:217-243`) runs a
`ThinkerIterator` over every Actor in the level **every tic per player** while a smartgun is held.
`CheckSight` is only called for candidates that already beat the best distance, so it is cheaper
than it looks, but the iteration is not free in a busy room. Throttling it to every 3rd tic would be
invisible at 18% ease and cuts it by two-thirds.

---

# PART 3 — Engine changes, clearly marked

Not mod-side on unmodified QuestZDoom 17.3. Listed, not recommended.

1. **Analogue trigger and grip values.** The kit: *"No analog trigger or grip value, no controller
   velocity, no finger tracking — searched, not found."* With a float per hand exposed on
   `PlayerInfo`, the trigger finger becomes a blend between `RQGT` and `RQGU` instead of two
   frames, and the grip becomes a real grab pressure. This is the single change that would most
   improve "finger on triggers".
2. **Replicate `AttackPos` / `OffhandPos` / the hand angles in the usercmd.** Would turn §3.1 from
   an architectural rewrite into a non-issue, and is the prerequisite for the family's
   crossplatform-co-op goal with any VR gesture mod.
3. **Fix `ModifyBobPivotLayer3D`** (`hw_weapon.cpp:973-974` vs `weapons.zs:48`). The pack works
   around it with its own pivot maths in `RSQ_Turn.Place`; a working engine hook would delete that
   whole class.
4. **Do not hide off-hand-weapon layers while steadying**, or make it opt-out per layer
   (`hw_weapon.cpp:919`). Fixes §1.8 at the root and makes `ae_lefthanded` and dual-wield-while-
   steadied possible at all.
5. **A per-layer controller override** ("draw this layer on hand N") would make `ae_lefthanded`
   and hand-swapping trivial instead of the owner-shuffling hack of §1.7.
6. **Bone/pose control from script** — the kit's first hard limit. Would replace the whole
   pre-baked-frame approach with a real grip solve, which is the direction
   `docs/CONCERN_vr_worldweapons_2026-10-12.md` already argues for.

---

# UNVERIFIED, and what would settle each

Verification runs would use `C:\Users\Command\Desktop\qzdoom-17-3-Windows-64bit\qzdoom.exe` with
`+vr_mode 0 +vr_override_weap_pos 1 +vr_render_weap_in_scene 1` (the kit: `+vr_mode 0`, **not**
`-config`, is what keeps a desktop test out of the headset) and a scratch config. **Not run here.**

1. **§2.1 / §2.9 — the Yutani shotgun's and the dual copies' `AmmoType1` and `AmmoUse1`.**
   Declared in `_A01_ALIENS_ERADICATION_TC_2_0.pk3`, not in this repo. Settle with
   `summon YutaniShotgunspawner`, `printinv` before and after a hand reload; and
   `+ae_dual_pistol 1 +ae_start_dual 1`, `printinv`, fire the off trigger, `printinv`.
2. **§2.3 — `GrenadeAmmo`'s `MaxAmount`.** Also `_A01`. `printinv` with 10 grenades, then one pump
   stroke.
3. **§1.1 — that `ModifyBobLayer3D` really stops being called while dual.** Verified from the
   engine source but not observed. A `Console.Printf` in `RSQ_Hands.ModifyBobLayer3D` plus
   `tools/probe/probe_zscript.txt`'s layer dump, with and without the dual copy in `OffhandWeapon`.
4. **§5.1 — the exact failure mode of loading both packs.** The class collision is certain; whether
   GZDoom reports "already defined" or something less obvious is not. One load of both pk3s with
   the console open settles it, and is the fastest way to confirm the owner's snag.
5. **Q10's drum surface** — which of `m56.md3`'s 6 surfaces is the ammo drum. `tools/md3.py` /
   `tools_md3_render.py` on the mesh (the family rule: verify model questions with the render
   tools, and check islands before calling a part missing).
6. **Q17 — which `modeldef.loader.txt` block or cvar gate is hiding the Power Loader.** Load with
   `+avw_weapons 1`, `summon` the loader pickup, and compare against each `SurfaceSkin` block
   commented out in turn.
7. **The `AE_GrabWith` "Either" value after the §4.1 fix.** `BT_OFFHANDATTACK | BT_USE` =
   67108866 is arithmetic, but whether QZD's off-hand trigger and Use can be held together on a
   Quest controller is a headset question.
8. **§1.3's blend timing.** That two states per pose blends smoothly is the kit's documented claim
   (`models.cpp:367-405`); the right `Tics` value for a finger curl is a feel question for the
   headset.
