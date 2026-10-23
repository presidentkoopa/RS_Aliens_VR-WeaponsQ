# Body-worn gear on QuestZDoom 17.3 — what the engine actually lets us build
### A design-and-feasibility study for RS Aliens VR Weapons (Quest), 2026-10-23

Everything below is read from `E:\DOOMWork\QZD17-engine` at commit **9afc750917**
(= QuestZDoom 17.3 = GZDoom 4.14.3). Line numbers are that commit's, not the working
tree's: the checkout's HEAD is `670d19eba6` ("pre-swarm snapshot"), which carries 871
added lines of engine work across 18 files on top of 9afc750 — `src/r_data/models.cpp`,
`src/playsim/p_pspr.*`, `player.zs` among them. **None of that exists on the engine this
pack ships against.** Citations were taken with `git grep -n <pat> 9afc750917`, so every
`file:line` in this document is a line of QuestZDoom 17.3 as the player will run it.

One boundary to state up front, because it limits what can be *proved* rather than
inferred. The Quest build's input and tracking layer is **not in this repository**:
`mobile/Android_src.mk` compiles `../../QzDoom/TBXR_Common.cpp`,
`QzDoom_OpenXR.cpp`, `OpenXrInput.cpp`, `VrInputCommon.cpp` and `VrInputDefault.cpp` —
paths two directories *above* the tree, i.e. in the QuestZDoom launcher project.
What is in the tree is (a) the engine's *consumption* of the globals that layer writes
(`src/QzDoom/qzdoom_common.cpp`, `hw_openxrdevice.cpp`), and (b) the PC OpenVR copy of
the same input logic, `src/rendering/gl/stereo3d/gl_openvr.cpp`, which is the same code
family and is the best in-tree documentation of what the Quest layer does. Where I rely
on the OpenVR copy I say so.

---

## 0. Priority note

The owner's standing priority is hands-on-gun quality — the hand planted on the grip,
hands riding recoil, finger on the trigger, smooth reloading. Body gear is an idea, not a
commitment. This study therefore front-loads two things that matter whatever happens to
the belt:

1. **§2.6 — the two-hand steady mechanism**, exactly as the engine computes it. This is
   the proximity-plus-button primitive the owner wants reused, and it is also the thing
   the reload system already has to dodge.
2. **§4 — how a body-gear reach interacts with the reload gestures already in
   `zscript/rsr/vreload.zs` and `rsr_pump.zs`.** The short version is that the current
   holster design competes with the reload for the off hand and for the off-hand trigger,
   which is a sufficient reason to reject it as it stands, and that a belt done as a
   *source constraint* on the existing reload instead of as a new input mode competes
   with nothing.

The designs in §6 are deliberately compressed.

---

## 1. Capability map — the exported VR surface at 9afc750

### 1.1 Every `vr_` cvar that exists

All declared in `src/common/rendering/hwrenderer/data/hw_vrmodes.cpp` unless noted;
all `CVAR_ARCHIVE | CVAR_GLOBALCONFIG`, so a mod can read them but must not write them.

| cvar | default | line | what it does / why it matters here |
|---|---|---|---|
| `vr_mode` | 0, forced to 15 | 56-61 | `CUSTOM_CVAR`; under `USE_OPENXR` it reassigns itself to 15 every callback. On the Quest it is always 15. |
| `vr_vunits_per_meter` | **34.0** | 94 | The one number every body-relative calculation needs. Map units per metre. |
| `vr_height_adjust` | 0.0 | 95 | Metres added to the HMD height. Must be included in any head-height computation. |
| `vr_ipd` | 0.064 | 78 | metres. |
| `vr_screendist` | 0.80 | 81 | metres. |
| `vr_control_scheme` | 0 | 96 | `<10` = right-handed, `>=10` = left-handed. Decides which physical controller is "main" (`hw_vrmodes.cpp:464-465`). |
| `vr_joy_mode` | 1 | 100 | Needs a restart. |
| `vr_move_use_offhand` | false | 104 | Stick movement follows the off controller's facing. |
| `vr_teleport` | false | 105 | When on, stick movement is disabled (`g_game.cpp:844-847`) and the off hand aims a teleport trace (`hw_openxrdevice.cpp:612-652`). A belt reach with the off hand while `vr_teleport` is on fights the teleport aim. |
| `vr_weaponRotate` | -30 | 106 | Degrees; applied in the out-of-tree input layer. |
| `vr_weaponScale` | 1.02 | 107 | Multiplies every HUD model (`models.cpp:277`). |
| `vr_3dweaponOffsetX/Y/Z` | 0 | 108-110 | Player's own nudge on every 3D HUD model (`models.cpp:251`), applied **after** the model's own `Scale`, so its units are model-scale-dependent. |
| `vr_2dweaponOffsetX/Y/Z`, `vr_2dweaponScale` | 0,0,0,1 | 111-114 | 2D sprite path only. |
| `vr_snapTurn` | 45 | 115 | Degrees per snap. Relevant: see §3.4 on frame disagreement during a snap. |
| `vr_switch_sticks` | false | 116 | Swaps stick roles. |
| `vr_use_alternate_mapping` | false | 117 | Selects `defbind3`. |
| `vr_secondary_button_mappings` | **true** | 118 | The dominant grip becomes a shift key (`gl_openvr.cpp:1630-1634`). Every other button therefore has two meanings. |
| `vr_two_handed_weapons` | **true** | 119 | Gates the steady test in §2.6. |
| `vr_momentum`, `vr_momentum_threshold` | false, 1.0 | 120-121 | Commented "Only used in player.zs". |
| `vr_crouch_use_button` | **true** | 122 | When *false*, the engine drives `player->crouchfactor` from the HMD height every frame (`hw_openxrdevice.cpp:574-579`). This changes `player.viewheight` continuously and is the main reason not to anchor anything to `viewheight`. |
| `use_action_spawn_yzoffset` | false | 123 | |
| `vr_enable_haptics` | true | 125 | |
| `vr_pickup_haptic_level` | 0.2 | 126 | The only haptic a mod can reach — see §1.6. |
| `vr_quake_haptic_level` | 0.8 | 127 | |
| `vr_missile_haptic_level` | 0.6 | 128 | |
| `vr_hud_scale/stereo/distance/rotate/fixed_pitch/fixed_roll` | .25/1.4/1/10/false/true | 131-136 | The flat HUD quad. |
| `vr_automap_*` (7) | | 139-145 | Same for the automap. |
| `vr_overlayscreen`, `_always`, `_size`, `_dist`, `_vpos`, `_bg` | 1,false,1,0,0,0 | 84-89 | The virtual screen used in menus. |
| `vr_desktop_view` | 2 | 83 | |
| `vr_swap_eyes` | false | 76 | |
| `vr_kill_momentum` | 0.0 | 91 | |
| `vr_move_speed`, `vr_run_multiplier`, `vr_walk_multiplier` | 19, 1, 1 | 153-164 | |
| `vr_override_weap_pos`, `vr_render_weap_in_scene` | false, false | 147-148 | `CVARD`, flagged "Only used for testing VR environment on PC". `vr_render_weap_in_scene` is read by `VRMode::RenderPlayerSpritesInScene()` (`hw_vrmodes.cpp:427-430`). |
| `vr_enable_quadbuffered` | false | `win32glvideo.cpp:78` | PC only. |
| `ext_haptic_level_<event>`, `ext_haptic_level_global_intensity` | — | `c_cvars.cpp:1440-1453` | A mod **can define these**: the engine looks up `ext_haptic_level_<name>` by string for each built-in haptic event. See §1.6. |

### 1.2 Where controller and HMD poses enter the playsim, in what frame and units

Four C++ globals carry the poses (`src/QzDoom/qzdoom_common.cpp:10-16`, declared
`src/QzDoom/VrCommon.h:37-41`): `weaponangles`, `weaponoffset`, `offhandangles`,
`offhandoffset`, plus `hmdPosition` and `hmdorientation`. All `vec3_t` = `float[3]`,
indexed `PITCH 0, YAW 1, ROLL 2` for angles (`VrCommon.h:9-11`).

**`weaponoffset` / `offhandoffset` are the hand minus the head, in metres, already
rotated into Doom's world axes.** The in-tree OpenVR copy computes it literally
(`gl_openvr.cpp:1733-1740`):

```
weaponoffset[0..2] = controllerPose - hmdPosition          // metres, tracking space
yawRotation        = getViewpointYaw() - hmdorientation[YAW]
v                  = DVector2(weaponoffset[0], weaponoffset[2]).Rotated(-yawRotation)
weaponoffset[0] = v.Y;  weaponoffset[2] = v.X
```

`hmdPosition` itself is set raw from the tracking layer, metres, `[1]` = up
(`qzdoom_common.cpp:93-104`).

The engine then publishes the hands to the playsim once per rendered frame, in
`OpenXRDeviceMode::SetUp()` (`hw_openxrdevice.cpp:585-610`):

```
AttackPitch = -weaponangles[PITCH]                                      (deg)
AttackAngle = -90 + getViewpointYaw() + (weaponangles[YAW] - playerYaw) (deg)
AttackRoll  =  weaponangles[ROLL]                                       (deg)
AttackPos.X = mo->X() - weaponoffset[0] * vr_vunits_per_meter
AttackPos.Y = mo->Y() - weaponoffset[2] * vr_vunits_per_meter
AttackPos.Z = r_viewpoint.CenterEyePos.Z
            + ((hmdPosition[1] + weaponoffset[1] + vr_height_adjust) * vr_vunits_per_meter) / pixelstretch
            - getDoomPlayerHeightWithoutCrouch(player)
```
and the identical block for `Offhand*` at `:600-609`. `CenterEyePos` is just the
interpolated camera position (`r_utility.cpp:1236`: `viewPoint.CenterEyePos = viewPoint.Pos`),
so `CenterEyePos.Z == viewz` and `CenterEyePos.XY == mo->XY`.
`getDoomPlayerHeightWithoutCrouch` returns the cached `player->DefaultViewHeight()`
while `vr_crouch_use_button` is true (`hw_openxrdevice.cpp:158-171`) — i.e. **41 units**
for a normal pawn.

Two consequences that every body-relative design rests on:

* **`AttackPos` / `OffhandPos` are absolute world positions in map units.** Horizontally
  they are the pawn origin plus the hand's offset from the head; vertically they are
  `viewz + handHeightAboveFloor − 41`.
* Therefore, substituting and converting to real centimetres (horizontal map units ÷
  `vu`, vertical × `pixelstretch` ÷ `vu`):

  ```
  (AttackPos.Z − viewz) × pixelstretch × 100 / vu  =  handHeightAboveFloor_cm − 144.7
  ```
  where 144.7 cm = 41 units × 1.2 / 34. **The vertical datum is a fixed 1.447 m above the
  floor, not the player's head.** This single fact is the diagnosis in §3.

* The eye is rendered at the same datum plus the real HMD height:
  `eyeOffset[2] += getHmdAdjustedHeightInMapUnit() − getDoomPlayerHeightWithoutCrouch()`
  (`hw_openxrdevice.cpp:219`), with
  `getHmdAdjustedHeightInMapUnit() = (hmdPosition[1] + vr_height_adjust) * vu / pixelstretch`
  (`:151-155`). So the *rendered* eye and the *reported* hands agree, and a mod that
  places something using the same arithmetic will agree with both.

The non-VR / fallback path sets all of it to the pawn's shoot position
(`hw_vrmodes.cpp:432-447`), and the same function sets `player->PlayInVR = IsVR()` and
`player->mo->OverrideAttackPosDir = !puristmode && (IsVR() || vr_override_weap_pos)` —
the pair the pack already uses as its "are we in VR" gate (`zscript/rsvr/vrhand.zs:18-21`).

**Update rate.** `VRMode::SetUp()` runs on the render path, once per *frame*, not per tic.
A `WorldTick` reading `OffhandPos` sees the most recent frame's value; a `ui` function
reading it during `ModifyBobLayer3D` sees that frame's. Neither is interpolated and
neither is net-replicated: these fields are local presentation state. Any gameplay
decision keyed on them is client-local by construction, which matters for the
crossplatform-co-op rule — a belt grab must be turned into a net event the way
`vreload.zs:990` already does, not acted on directly in a client's tick.

### 1.3 The complete ZScript-exported surface

This is the whole constraint. There is nothing else.

**On `Actor` — `wadsrc/static/zscript/actors/actor.zs:268-277`, registered at
`src/scripting/vmthunks_actors.cpp:2185-2195`, backed by `src/playsim/actor.h:1652-1668`:**

| ZScript declaration | units / frame |
|---|---|
| `native readonly vector3 AttackPos;` | main-hand controller, **absolute world position, map units**; Z measured from the 1.447 m datum as derived above |
| `native readonly double AttackPitch;` | degrees, `= -weaponangles[PITCH]` |
| `native readonly double AttackRoll;` | degrees, `= weaponangles[ROLL]` |
| `native readonly double AttackAngle;` | degrees, **with a baked −90**: `-90 + doomYaw + (handYaw − playerYaw)` |
| `native readonly vector3 OffhandPos;` | off-hand controller, same frame and units |
| `native readonly double OffhandPitch/Roll/Angle;` | as above |
| `native readonly bool OverrideAttackPosDir;` | true while in VR and not `puristmode` |
| `native readonly vector3 HmdPosition;` | **raw tracking-space metres**, `(x, y=up, z)`, *not* map units and *not* a world position (`hw_vrmodes.cpp:445`) |
| `native vector3 AttackDir(Actor actor, double angle, double pitch);` | `actor.zs:858` |
| `native vector3 OffhandDir(Actor actor, double angle, double pitch);` | `actor.zs:859` |

Every one of them is `readonly`. **ZScript cannot write a hand pose.**

`AttackDir`/`OffhandDir` are function pointers assigned per frame to `MapAttackDir` /
`MapOffhandDir` (`hw_vrmodes.cpp:439-440`), implemented by `MapWeaponDir`
(`hw_vrmodes.cpp:390-415`). They take a world yaw/pitch, subtract the actor's own yaw and
pitch (`:401-402`), rotate the result through the hand matrix, and return
`(dir.Angle(), dir.Pitch(), 0)` in degrees (`p_actionfunctions.cpp:5694-5712`). Two things
follow: the baked −90 in `AttackAngle` cancels inside this function, so **hand orientation
must be read through `AttackDir`/`OffhandDir`, never from `AttackAngle` directly**; and
the off hand's matrix includes the engine's mirror (next paragraph), so `OffhandDir`
returns axes in the *mirrored* frame the off-hand layers are actually drawn in. The pack
already does exactly this (`zscript/rsvr/vrhand.zs:38-61`) and it is correct.

Three calls to `OffhandDir` — `(0,0)`, `(90,0)`, `(0,90)` — give the off hand's full
orthonormal basis in world axes. That is how you convert a world vector into the hand's
own frame without any matrix export.

**On `PlayerInfo` — `player.zs`:** `native readonly bool PlayInVR;` (`:3136`, registered
`p_user.cpp:1946`), `native AActor* OffhandWeapon` (`:384` in `d_player.h`, registered
`p_user.cpp:1883`), `native uint WeaponState` (`:3073`), `native double viewz` (`:3053`),
`native double viewheight` (`:3054`), `native double crouchfactor` (`:3126`),
`native uint bonuscount` (`:3087` — writable, and see §1.6), `native @UserCmd cmd`
(`:3134`).

**`UserCmd`** (`player.zs`) is `buttons` plus `pitch/yaw/roll/forwardmove/sidemove/upmove`
as `int16`. The thumbsticks arrive as `forwardmove`/`sidemove`; there is no separate axis
export.

**Button bits** — `constants.zs:832-870`, mirrored from `src/d_event.h:42-77`:
`BT_ATTACK, BT_USE, BT_JUMP, BT_CROUCH, BT_TURN180, BT_ALTATTACK, BT_RELOAD, BT_ZOOM,
BT_SPEED, BT_STRAFE, BT_MOVERIGHT/LEFT, BT_BACK, BT_FORWARD, BT_RIGHT, BT_LEFT,
BT_LOOKUP/DOWN, BT_MOVEUP/DOWN, BT_USER1..4, BT_RUN, BT_OFFHANDATTACK (1<<26),
BT_OFFHANDALTATTACK (1<<27), BT_OFFHANDRELOAD (1<<28), BT_MAINHANDRELOAD (1<<20)`.
`BT_SHOWSCORES` has been redefined to 0 to make room. `BT_USER1..4` are built from
`buttonMap.ButtonDown(Button_User1..4)` at `g_game.cpp:779-782`; the comment at
`constants.zs:843` says everything from `BT_SPEED` on "are all ignored by the play
simulation and are for scripts".

**Weapon-state flags**: `WF_TWOHANDSTABILIZED = 1 << 24` (`constants.zs:1242`,
`d_player.h:164`). See §2.6 for how and when it is set.

**Psprite layers** — `PSP_OFFHANDWEAPON = 1000000` (`p_pspr.h:58`, `player.zs:2939`).
`class PSprite` (`player.zs:2932-2982`) exports, all writable from play: `Caller`,
`Sprite`, `Frame`, `x`, `y`, `oldx`, `oldy`, `baseScale`, `pivot`, `scale`, `rotation`,
`HAlign/VAlign`, `Coord0..3`, `alpha`, `firstTic`, `InterpolateTic`, `Tics`,
`Translation`, and the flag bools `bAddWeapon, bAddBob, bPowDouble, bCVarFast, bFlip,
bMirror, bPlayerTranslated, bPivotPercent, bInterpolate`, plus `SetState()`.
`CurState`, `Next`, `Owner`, `ID` are readonly.

**The placement hooks** — `wadsrc/static/zscript/actors/inventory/weapons.zs`:
```
virtual ui Vector2 ModifyBobLayer(Vector2 Bob, int layer, double ticfrac)            :44
virtual ui Vector3, Vector3 ModifyBobLayer3D(Vector3 T, Vector3 R, int layer, double ticfrac) :46
virtual ui Vector3 ModifyBobPivotLayer3D(...)                                        (see hw_weapon.cpp:896)
Vector3 BobPivot3D;                                                                  :42
```
plus `virtual Vector3, Vector3 BobWeapon3D(double ticfrac)` on `PlayerPawn`
(`player.zs:2784`), called from `P_BobWeapon3D` (`p_pspr.cpp:703-705`).

**`switchhand <0|1>`** (CCMD, `g_game.cpp:335-350`) calls the ZScript virtual
`PlayerPawn.SwitchWeaponHand(hand)`; **`slot N [hand]`** (`g_game.cpp:352-376`) calls
`PickWeapon(slot, checkammo, hand)`. Both are mod-overridable entry points for moving a
weapon between hands.

**`A_ChangeModel`** (`actor.zs:1232`, native `p_actionfunctions.cpp:5433-5578`) — see §1.5.

### 1.4 How weapon and hand models are placed and drawn

**Which controller a layer lands on** is decided in one line, `src/r_data/models.cpp:221`:
```
int hand = psp->GetCaller() == playermo->player->OffhandWeapon ? 1 : 0;
```
A layer goes to the off controller **only** if its caller actor is literally
`player.OffhandWeapon`. Everything else goes to the main controller. There is no third
option. This is why the pack owns main-hand layers with an inventory item
(`RSQ_GunSide`) and off-hand layers with a weapon parked in `OffhandWeapon`
(`RSQ_Hands`) — `zscript/rsq/hands.zs:31-37` documents it correctly.

**Whose `ModifyBobLayer3D` is called** is `src/rendering/hwrenderer/scene/hw_weapon.cpp:332`:
```
w.weapon = psp->GetCaller() == player->ReadyWeapon ? readyWeaponPsp : offhandWeaponPsp;
```
and then `:941-965`: the virtual is looked up on `weap.weapon->GetCaller()`'s class, is
skipped if it is still `Weapon`'s own implementation (`:947`), and is only called when the
layer has `PSPF_ADDBOB` (`:951`). So **the off-hand weapon places every layer that is not
the ready weapon's** — which is exactly how `RSQ_Hands` places layers it does not own,
and exactly why a real gun in `OffhandWeapon` that does not implement the hook silently
drops every hand hook (the pack's `RSQ_Place.Layer` indirection, `hands.zs:79-183`, is the
right answer to that).

**The transform chain for a 3D HUD model**, `RenderHUDModel`, `src/r_data/models.cpp:208-287`.
Matrix ops append, so the *last* listed applies first to a vertex:

| step | line | effect |
|---|---|---|
| hand transform | 223 | `GetWeaponTransform(&m, hand)` **replaces** the matrix (it calls `loadIdentity` inside, `hw_openxrdevice.cpp:437`). Local units are now **metres**, because of `mat->scale(vu, vu, -vu)` at `:442`. |
| `scale(0.01)` | 226 | local units are now **centimetres** |
| `translate(0, 5, 30)` | 227 | a fixed 5 cm up, 30 cm along the hand axis |
| `scale(smf->xscale, zscale, yscale/fovscale)` | 245 | model units |
| `translate(offset/scale)` | 248 | net effect = MODELDEF `Offset` in **centimetres** |
| `translate(-vr_3dweaponOffsetX, +Y, +Z)` | 251 | player nudge, in *scaled* units |
| pivot / rotation / un-pivot | 257-263 | `rotation.X` about local **y (yaw)**, `.Y` about local **x (pitch)**, `.Z` about local **z (roll)** |
| `translate(translation)` | 265 | the `ModifyBobLayer3D` translation, in units of (1 / model scale) cm |
| `rotate(90, y)` | 269 | the jDoom fixup |
| `angleoffset/pitchoffset/rolloffset` | 272-274 | MODELDEF |
| `scale(vr_weaponScale)` | 277 | |

Two details with teeth. First, `GetWeaponTransform` mirrors the left hand:
`if (!hand && autoReverse) out->scale(-1.0f, 1.0f, 1.0f)` (`hw_vrmodes.cpp:468-469`),
suppressed only by the weapon flag `WIF_NO_AUTO_REVERSE` (`:462`). So the off-hand frame
is **left-handed**: an x translation on an off-hand layer has the opposite sign to the
same translation on a main-hand layer, and a model drawn in it needs mirrored u
(handoff §5 records this). Second, the renderer adds each layer's *own* psprite x/y as a
rotation on top — `hw_weapon.cpp:108`:
```
RenderHUDModel(..., huds->rotation + FVector3(huds->mx / 4., (huds->my - WEAPONTOP) / -4., 0), ...)
```
So **psprite `x`/`y` are yaw/pitch in quarter-degrees for a 3D model.** That is the only
way to steer a HUD model from *play* scope rather than `ui`, it is what the smartgun
gimbal uses (`CVARINFO.ae:17`), and it is what `RSQ_Place.Layer` has to subtract back out
(`hands.zs:181`).

**What can be drawn attached to the body rather than to a hand or the view: nothing, on
the HUD path.** In VR, `GetWeaponTransform` always succeeds for a live player, so the
`else if (vrmode->IsVR())` body-anchored branch at `models.cpp:229-234` — which would
place a model at `playermo->Pos()` + 40 units — is **dead code in VR**. Every psprite
model is anchored to one of the two controllers. A body-fixed psprite layer is only
achievable by *counter-transforming* it every frame: see §2.4.

**World models** are the other path, `RenderModel` (`models.cpp:71-206`). Scale is
`actor->Scale.X * smf->xscale` horizontally and `actor->Scale.Y * smf->zscale` vertically
(`:82-84`) — the actor's own scale multiplies MODELDEF's, which is precisely the bug the
pack's holster code documents and fixed (`holstertable.zs:9-18`). Orientation comes from
the actor's `Angles.Yaw` always (`:93`), from `Pitch` only with `MDL_USEACTORPITCH`
(`:132-137`) and from `Roll` only with `MDL_USEACTORROLL` (`:138`).

**Near plane** is `0.5` map units — `static float GetZNear() { return 0.5f; }`
(`src/common/rendering/v_video.h:294`), used for the VR projection at
`hw_openxrdevice.cpp:232`. That is ~1.5 cm horizontally, ~1.8 cm vertically: a world-actor
model can come within a couple of centimetres of the eye before it clips. And the
"too close to the camera" sprite cull explicitly exempts models and stationary things —
`hw_sprites.cpp:889-894` requires `!thing->Vel.isZero() && !modelframe`. **A zero-velocity
model-bearing actor worn on the body is not culled.** That is the single most important
rendering fact for this study.

**HUD models vs world models and depth.** HUD models are drawn with the depth range
squashed into `[0, 0.3]` (`hw_models.cpp:86-92`) so they cannot poke into walls — and
consequently can never be occluded by anything. World models are depth-tested normally
(`hw_models.cpp:60`), so a world-actor belt *will* be correctly hidden behind geometry and
will clip into a wall the player backs into.

**MODELDEF's capabilities**, parser at `models.cpp:740-1125`: `Path`, `Model <i> "file"`,
`Animation`, `Scale x y z`, `Offset x y z`, `ZOffset`, `AngleOffset`, `PitchOffset`,
`RollOffset`, `Skin <i>`, `SurfaceSkin <i> <surface>`, `BaseFrame`,
`FrameIndex`/`Frame`, and the flags `IgnoreTranslation, PitchFromMomentum,
InheritActorPitch, InheritActorRoll, UseActorPitch, UseActorRoll, NoPerPixelLighting,
ScaleWeaponFOV, ModelsAreAttachments, Rotating (+ rotation-speed/-vector/-center),
InterpolateDoubledFrames, NoInterpolation, DontCullBackfaces, ForceCullBackfaces,
UseRotationCenter, CorrectPixelStretch`. There is **no model-index limit**:
`smf.modelsAmount = index + 1` and the arrays are allocated to fit
(`models.cpp:763-788`), minimum 4. Surfaces per model are capped at
`MD3_MAX_SURFACES 32` (`src/common/models/model.h:30`). A block binds to an **exact
class**; subclasses inherit nothing (handoff §5, and `FindModelFrame` keys on the class).
Model formats include **`.obj` loaded directly** (`src/common/models/model.cpp:192`,
loader `models_obj.cpp`), as well as md2/md3/iqm/kvx/ue1.

### 1.5 Runtime model control from ZScript — the cheap trick that makes gear possible

Three mechanisms, all mod-side, all verified:

1. **Per-frame model selection.** The smf for a psprite layer is looked up by the
   *caller's class plus the layer's sprite and frame*: `FindModelFrame(psp->Caller,
   psp->GetSprite(), psp->GetFrame(), false)` (`hw_weapon.cpp:922`, resolved at
   `models.cpp:1219-1223`). `psp.Sprite` and `psp.Frame` are writable from play
   (`player.zs:2949-2950`). So **one layer can draw any of N models** by writing its
   frame — which is exactly how the pulse rifle's ammo counter works (100 one-block
   blocks, handoff §1).

2. **Whole-MODELDEF redirection.** `FindModelFrame` uses
   `thing->modelData->modelDef` in preference to the class (`models.cpp:1223`), and
   `A_ChangeModel`'s first parameter sets it (`p_actionfunctions.cpp:5459-5484`). An
   inventory item can therefore be repointed at another class's MODELDEF blocks at
   runtime.

3. **Per-model-index hide and per-surface reskin at runtime.**
   `CMDL_HIDEMODEL` makes `queryModel = -2` (`p_actionfunctions.cpp:5481`), and
   `CalcModelOverrides` returns false for `modelID == -2` (`models.cpp:446-449`), so that
   model index is skipped entirely. `CMDL_USESURFACESKIN` writes
   `surfaceSkinIDs[skinindex]` (`:5504-5537`). So a belt declared as `Model 0..7` can hide
   box 5 when box 5 has been emptied, with no engine change and no actor churn.

   *Caveat to settle with a compile, not an argument:* `A_ChangeModel` is declared
   `action` (`actor.zs:1232`). Calling it as `item.A_ChangeModel(...)` from an
   `EventHandler` resolves `stateinfo == null`, so `mobj = invoker = self` at `:5469` —
   correct behaviour — but whether ZScript's compiler permits the call outside an action
   context at this version is **UNVERIFIED**. The check is a one-line compile. The
   guaranteed fallback is to drive it from a state on the item.

4. **Moving a layer between hands.** `psp.Caller` is writable (`player.zs:2946`), and the
   hand is chosen by comparing the caller to `OffhandWeapon` (`models.cpp:221`). So a
   held item can be passed from one controller to the other by reassigning one field.

### 1.6 Input, exhaustively — what a mod can detect, and per which hand

| channel | how | per-hand? | evidence |
|---|---|---|---|
| `player.cmd.buttons & BT_*` | play scope, net-synchronised, free | **Only** `BT_OFFHANDATTACK/ALTATTACK/RELOAD` and `BT_MAINHANDRELOAD` carry a hand. `BT_USE`, `BT_ATTACK`, `BT_USER1..4` do not. | `constants.zs:832-870`, `g_game.cpp:779-782` |
| custom `+command` via KEYCONF | `AddKeySection` / `AddMenuKey` / `defaultbind`, reaching `user1..user4` and the `oh_*` actions | no hand of its own; the hand must be inferred geometrically | bindable action names at `d_main.cpp:2722-2759`: `attack, altattack, reload, zoom, use, jump, crouch, speed, strafe, user1..user4, oh_attack, oh_altatk, oh_reload, mh_reload, showscores, am_*`; the pack already does this in `KEYCONF.ae:4-11` |
| `netevent` alias | `alias foo "netevent bar"` + a bind → `EventHandler.NetworkProcess` | no | `KEYCONF.ae:6` |
| **raw key codes** via `EventHandler.InputProcess` (`ui`) | `e.KeyScan` on `Type_KeyDown/KeyUp`, relayed to play with `SendNetworkEvent` | **yes, in practice** — the input layer emits a *different* key code for the same physical button on each controller: `HandleVRButton(..., KEY_PAD_X, role * (KEY_PAD_Y - KEY_PAD_X))` (`gl_openvr.cpp:1600-1606`) | the pack's `rsr_grip_keys` default `"443 436"` = `KEY_PAD_RTHUMB`, `KEY_PAD_DPAD_UP` (`CVARINFO.rsr:11`), consumed at `vreload.zs:979-1023` |
| the dominant **grip as a shift key** | `vr_secondary_button_mappings` (default true) makes every other button report a *second* key code while the main grip is held | n/a | `gl_openvr.cpp:1630-1634`, `hw_vrmodes.cpp:118`; handoff §5 records "grip+trigger = +altattack" |
| default Quest binds | `space +use`, `pad_a +use`, `tab togglemap`, `rtrigger +attack`, `ltrigger +altattack`, `lthumb crouch`; with dualwield, `shift +oh_attack`, `alt +oh_altatk`, `axis7± switchhand`, `axis8± weapnext/prev 1` | — | `wadsrc/static/engine/vr/commonbinds.txt`, `defbind1.txt`, `defbind3.txt` |

**For the owner's question — "the use key or a different button entirely" — both work, and
a separate button is better.** `BT_USE` is already in `player.cmd.buttons`, costs one bit
test, is net-synchronised, and collides with neither the grip (owned by the reload and the
engine's steady) nor the off trigger (owned by the reload). Its one real cost is that
`+use` also opens doors and presses switches; note that when `use_mode > 0` the engine
already starts the use trace from `AttackPos`/`OffhandPos` (`p_map.cpp:6168-6183`,
`:6289-6304`), so a "use" with the hand down at the belt traces from the belt and will
usually hit nothing — but "usually" is not "never". The cleaner answer is a dedicated
bind: `AddMenuKey "Belt" ae_beltkey` + `defaultbind Pad_B +user3`, read as
`player.cmd.buttons & BT_USER3`. Pad_B is free in QuestZDoom's default layout
(`KEYCONF.ae:9` records A=use, Y=jump, B free, X now taken by `ae_dualkey`). Make the
mask a cvar the way `rsr_grab_buttons` is (`CVARINFO.rsr:12`) so the owner can move it to
`BT_USE` without a rebuild.

### 1.7 What the engine does not give us

Each of these is an absence I checked for and did not find at 9afc750.

* **No per-finger or skeletal hand data.** `git grep -niE "finger|skeletal" 9afc750917 -- src/ wadsrc/`
  returns only an OpenAL comment, a Win32 comment and a map-compatibility string. The
  only hand state is the button bits.
* **No haptics API for ZScript.** Every pulse is fired from C++ on a fixed event list
  (`p_interaction.cpp:1450-1500`, `p_map.cpp:4769-4773`, `p_mobj.cpp:7556-7560`,
  `a_weapons.cpp:107`, `p_user.cpp:1297-1303`, `v_blend.cpp:136-142`,
  `sbar_mugshot.cpp:346-352`). `VR_HapticEvent` is declared at `hw_vrmodes.h:97` and is an
  empty stub in-tree (`qzdoom_common.cpp:65-67`); the real implementation is in the APK.
  There is no `DEFINE_ACTION_FUNCTION` for it and no CCMD.
  **Two mod-side handles exist, and both are worth taking:** a mod may define
  `ext_haptic_level_<event>` cvars to scale any built-in event (`c_cvars.cpp:1442-1453`),
  and writing `player.bonuscount = 1` from play (`player.zs:3087` is a plain `native uint`)
  makes `v_blend.cpp:131-142` fire a 50 ms pulse in **both** hands on the next frame.
  Side effect: the pickup palette flash, which `pickup_fade_scalar` can suppress. So
  "the magazine seated" can be felt, but not in one hand only.
* **No controller velocity or acceleration.** There is no `AttackVel`/`OffhandVel`
  (grep: absent). Hand speed must be differenced per tic, as `melee.zs:104-119` does:
  `delta.Length() * 35 / vu` with the z component un-squashed by `pixelstretch`.
* **No writable hand pose.** All the pose fields are `native readonly`
  (`actor.zs:268-277`). A mod cannot move, offset or re-anchor a controller.
* **No per-actor model angle override.** Our fork's `ForceModelAngles` does not exist here
  (grep: absent). A world model's orientation comes only from the actor's own
  Angle/Pitch/Roll, and Pitch and Roll only with the MODELDEF flags.
* **No grip-claim arbitration field.** Our PCVR family's engine-native
  `GripClaimMain`/`GripClaimOff` (described in `RS_WorldHands/zscript/arbiter/rs_griparbiter.zs:1-27`)
  does not exist here (grep: absent). Any arbitration between a belt reach, a reload grab
  and a world grab must be built in ZScript, in one place, by us.
* **`weaponStabilised` is not exported.** It is a C++ global (`qzdoom_common.cpp:19`,
  `hw_vrmodes.h:100`) and reaches ZScript only as a weapon-state bit, refreshed on psprite
  state changes — see §2.6.
* **No body-anchored HUD model.** `models.cpp:229-234` would do it, but is unreachable in VR.
* **No view-space psprite in VR at all**; and 2D and 3D layers are mutually exclusive per
  layer (`hw_weapon.cpp:841` skips any layer that has a model, `:925` skips any that does
  not).
* **No way to read the head's horizontal position in world units.** `HmdPosition` is raw
  tracking-space metres with an arbitrary origin; only its `.y` (height) is directly
  useful. Horizontally, the pawn origin *is* the body: the engine itself uses
  `mo->X()/Y()` as the hands' horizontal datum (`hw_openxrdevice.cpp:593-594`).
* **No head pitch/roll export of its own.** The HMD's orientation reaches the playsim
  through the ordinary player-angle path, and the code that does it is in the out-of-tree
  input layer — `VR_GetMove`'s yaw/pitch/roll outputs are discarded at the one in-tree
  call site (`g_game.cpp:838-841` passes `&dummy` for all three). So "`mo.Angle` ≈ head
  yaw" is **UNVERIFIED from source**; it is verified only by the pack's own rig
  (`qz_hmd "x y z pitch yaw roll"`, handoff §3) and by the fact that the existing holster
  and reload code works. The check that would settle it: on the rig, set
  `qz_hmd "0 1.7 0 0 90 0"` and print `mo.Angle`, `mo.Pitch` from a WorldTick.

---

## 2. The mechanism the owner wants reused: QZD's two-handed-weapon test

### 2.1 What it actually computes

In-tree, `src/rendering/gl/stereo3d/gl_openvr.cpp:1706-1728`, inside
`HandleInput_Default`, gated on `gamestate == GS_LEVEL && menuactive == MENU_Off && !paused`
(`:1704`):

```cpp
const HmdMatrix34_t& dominantControllerPose = pDominantTracking->pose.mDeviceToAbsoluteTracking;
const HmdMatrix34_t& offhandControllerPose  = pOffTracking->pose.mDeviceToAbsoluteTracking;

float distance = sqrtf(powf(offhandControllerPose.m[0][3] - dominantControllerPose.m[0][3], 2)
                     + powf(offhandControllerPose.m[1][3] - dominantControllerPose.m[1][3], 2)
                     + powf(offhandControllerPose.m[2][3] - dominantControllerPose.m[2][3], 2));

if (vr_two_handed_weapons &&
    (offGripNew != offGripOld))                       // EDGE, not level
{
    if (offGripNew) { if (distance < 0.50f) weaponStabilised = true; }
    else            { weaponStabilised = false; }
}
```

Precisely:

* **Frame:** raw tracking space, straight off the two pose matrices' translation columns.
  No yaw rotation, no pixelstretch, no Doom units.
* **Units:** metres.
* **Shape:** a **sphere**. Full 3-D Euclidean distance; no cylinder, no cone, no direction
  test at all. Hand orientation is irrelevant.
* **Radius:** **0.50 m, hard-coded.** Not a cvar. There is no `vr_two_hand_radius`.
* **Trigger:** **edge-triggered on the off-hand grip's press.** The distance test runs
  *only* on the frame the grip changes state. Once latched, moving the hands apart does
  **not** unlatch; only releasing the grip does (`:1725-1727`). That asymmetry is worth
  copying or deliberately not copying — see §2.5.
* **Gate:** `vr_two_handed_weapons`, default **true** (`hw_vrmodes.cpp:119`).
* **Where it runs:** the input layer, once per rendered frame, *before* the pose globals
  are published — note that `weaponoffset` is written at `:1733-1740` and then
  **overwritten by the steady** at `:1742-1755`, which recomputes `weaponangles` pitch and
  yaw to point the gun from the main hand toward the off hand. That is the two-hand aim.
  On the Quest the same logic lives in the out-of-tree `VrInputDefault.cpp`; the OpenXR
  file even refers to it by name (`hw_openxrdevice.cpp:653`).

### 2.2 What ZScript can see of it

The result is a C++ global, `weaponStabilised` (`qzdoom_common.cpp:19`,
`hw_vrmodes.h:100`). It has no `DEFINE_FIELD`. It reaches ZScript by exactly one route:

```cpp
// DPSprite::SetState — src/playsim/p_pspr.cpp:499-515
if (ID == PSP_WEAPON)         Owner->WeaponState &= ~(... | WF_TWOHANDSTABILIZED);   // :503-504
if (ID == PSP_OFFHANDWEAPON)  Owner->WeaponState &= ~(... | WF_TWOHANDSTABILIZED);   // :508-509
if (weaponStabilised)         Owner->WeaponState |=   WF_TWOHANDSTABILIZED;          // :512-515
```

So `player.WeaponState & WF_TWOHANDSTABILIZED` is **only refreshed when a psprite changes
state**. A weapon sitting in a one-tic `A_WeaponReady` loop refreshes it every tic; a
weapon parked on a long state does not, and the flag goes stale. The pack reads it through
`RSVR_VRHand.Steadied()` (`vrhand.zs:71-74`) and that staleness is a real latency source
for any guard built on it.

The engine also *acts* on the flag in three more places a mod should know about: the
off-hand weapon's psprite layers are **not drawn at all** while stabilised
(`hw_weapon.cpp:832` and `:917`, `continue` for any layer whose caller is
`player->OffhandWeapon`), the off-hand fire haptic is suppressed
(`p_map.cpp:4771`, `:5700`, `p_mobj.cpp:7557`), and `p_pspr.cpp:755` /
`weapons.zs:415` / `player.zs:393`, `:426` route hand-1 actions differently.
**That first one matters: steady the gun and every off-hand gear layer vanishes.**

### 2.3 Can a mod run the same test against an arbitrary anchor? Yes, exactly

The engine's test is C++-only, but its *content* is reproducible to the centimetre,
because the mod has both endpoints in world units and the conversion is already written.

The conversion, derived from the publication arithmetic in §1.2: a world displacement
`w` in map units is, in real metres,
`|(w.x, w.y, w.z * pixelstretch)| / vr_vunits_per_meter`. The pack already implements this
exactly once, as `RSVR_VRHand.SteadyGap` (`zscript/rsvr/vrhand.zs:79-91`):

```zscript
Vector3 w = mo.OffhandPos - mo.AttackPos;
w.z *= ps;
return w.Length() * 100.0 / vu;      // real centimetres
```

Replace `mo.AttackPos` with any body-relative anchor and you have the engine's test
against that anchor, in the same units, with the same geometry. What a reimplementation
needs, and nothing more:

* `mo.OffhandPos` (or `mo.AttackPos`) — the hand, world map units (`actor.zs:272`, `:268`).
* `mo.Level.pixelstretch` and the `vr_vunits_per_meter` cvar (default 34,
  `hw_vrmodes.cpp:94`) — read once per tic and cached, not per anchor.
* The anchor, built in the same world frame: `mo.pos` horizontally and the Z datum of
  §1.2 vertically, rotated by `mo.Angle`. §3.2 gives the corrected formula.
* `mo.HmdPosition.y` + `vr_height_adjust` if the anchor height is to scale with the
  player (it should).
* Nothing from `OffhandDir` — the engine's test has no direction term, and neither should
  a belt reach. Orientation is for *what happens after* the grab (e.g. inverting the hand
  over the dump pouch).

The one thing a reimplementation **cannot** replicate is the engine's own side effects:
it cannot set `weaponStabilised`, cannot suppress the off-hand layers, and cannot
redirect the gun's aim. It only gets the boolean.

### 2.4 The other mechanism, for completeness: a counter-transformed psprite layer

For the record, because it is the only way to draw gear without a world actor. A psprite
layer is anchored to a controller (§1.4), but `ModifyBobLayer3D` can be handed a
translation that cancels the anchor: build the world vector from the hand to the slot,
project it onto the hand's basis from three `OffhandDir` calls, divide by the model's
`Scale`, and return it in centimetres. **Translation cancels cleanly. Orientation does
not.** To make the model body-fixed rather than hand-fixed you must also return the
inverse of the controller's rotation decomposed into the renderer's exact
yaw(y)→pitch(x)→roll(z) order (`models.cpp:259-261`), in a frame that for the off hand is
mirrored and therefore left-handed (`hw_vrmodes.cpp:469`). That is a three-axis Euler
inversion with sign traps, computed in `ui` scope, once per layer per frame, on a mobile
CPU, for an answer that a world actor gives for free. **Recommendation: do not do this for
body gear.** It remains the right mechanism for things that genuinely live in the hand —
which is what `RSQ_Place.Layer` already uses it for, correctly.

### 2.5 Recommended radius, and what it costs to test many anchors

The engine's 0.50 m is generous because it has exactly **one** target and only has to
catch a deliberate two-hand grab. A belt has many targets a few centimetres apart, so the
radius must be well under half the smallest anchor spacing, with nearest-wins arbitration
and hysteresis. The pack's own precedents: rifle charging-handle grab 16 cm (handoff §1),
`ae_glpump_grab` 14 cm (`CVARINFO.ae:89`), `RSR.GRAB_HANDLE` 7 cm / `LEAVE_HANDLE` 12 cm
(`vreload.zs:58-59`), and the existing holsters' 18 cm reach / 26 cm leave
(`holster.zs:20-21`) — which is too loose for seven slots and is part of why they
misfire.

**Recommend R = 8 cm, leave at 14 cm**, nearest-anchor-wins, with a button. 8 cm is
comfortably inside a controller's tracking accuracy and a hand's proprioception for a
target you can see, and it keeps clusters 15 cm apart unambiguous. Where the mesh puts
boxes 3–7 cm apart (§5), **do not make them separate anchors** — make the cluster one
anchor with a counted payload.

Cost: per anchor per tic the test is a vector subtract, one multiply, a dot product and a
compare. Use squared distances and you avoid the `sqrt` entirely; hoist the `CVar` lookups
and `pixelstretch` out of the loop (the existing code re-reads `vr_vunits_per_meter`
through `CVar.GetCVar` inside both `OffInBody` and `Place`, `holster.zs:119` and `:159` —
that is the expensive part, not the arithmetic). **You could test a hundred anchors per
tic and not measure it.** The budget is entirely in *drawing*: every model index drawn is
a draw call plus, on the HUD path, a dynamic-light gather per layer
(`hw_weapon.cpp:988-999`, inside the per-psprite loop) and on the world path a
`GetDynSpriteLight` per sprite (`hw_weapon.cpp:880-883` for 2D; `hw_sprites.cpp` for world
actors). Design the drawing, not the testing.

---

## 3. Diagnosis of the existing holster code

Files: `zscript/rsq/holster.zs` (189 lines), `zscript/rsq/holstertable.zs` (146),
`MODELDEF.holster` (78), gated off by `ae_holsters` (`CVARINFO.ae:29`).

### 3.1 What it does

`AE_HolsterHandler` is an `EventHandler`. Every `WorldTick`, for every player, it:
spawns or destroys one `AE_HolsterGhost` world actor per slot (7 slots), places each at a
body-relative position with `SetOrigin(..., true)` and sets its `Angle` and `Roll`
(`holster.zs:132-175`); converts the off hand into the same body frame
(`OffInBody`, `:113-129`); finds the nearest slot within 18 cm; and, on entering that
radius, **switches the player's weapon outright** — `pl.PendingWeapon = w`
(`:85-91`) — with 26 cm hysteresis on the way out. Its only guard against the reload is
`bool busy = RSR_Handler.FreeHand(mo) != ""` (`:63`). Each ghost subclass carries its
weapon's actor scale so MODELDEF's pickup-block `Scale` comes out pickup-sized
(`holstertable.zs:31-71`, and the header comment `:9-18` records the "giant box" bug and
its fix).

### 3.2 The frame error, precisely

The code's own comment says the offsets are "centimetres in the player's YAW frame
(F forward, L left, U up **from the view**)" (`holstertable.zs:4-7`, `holster.zs:110-112`).
They are not. The datum is

```zscript
Vector3 w = RSVR_VRHand.OffPos(mo) - (mo.pos + (0, 0, mo.player.viewheight));   // :122
```

and the ghost is placed at the mirror image of that (`:172`). Substituting the engine's
publication formula from §1.2, with `viewz ≈ mo.pos.z + viewheight`:

```
U_cm  =  handHeightAboveFloor_cm  −  41 units × pixelstretch × 100 / vu
      =  handHeightAboveFloor_cm  −  144.7 cm
```

**U = 0 is a fixed 1.447 m above the floor, independent of the player.** It is not the
view, not the head, not anything about the person wearing the belt. The slots are
therefore at absolute heights above the floor:

| slot | `PosU` | implied height above the floor |
|---|---|---|
| pistol | −58 | 87 cm |
| knife | −55 | 90 cm |
| rifle | −10 | 135 cm |
| shotgun | −10 | 135 cm |
| flamer | −32 | 113 cm |
| smartgun | −32 | 113 cm |
| satchel | −40 | 105 cm |

The system is *internally consistent* — ghost and reach test share the datum, and both
move with `viewheight`, so they agree with each other — which is why it half-works. But
it is wrong against the player's body, in two ways that cannot be tuned out with better
numbers:

* **It does not scale with the player.** For eye height 1.50 m the "shoulder" slots at
  1.35 m sit 15 cm below the eyes, about right. For eye height 1.78 m they sit 43 cm
  below — mid-chest. For seated play at 1.20 m they are *above the eyes*. Meanwhile the
  hip slots at 87-90 cm are, for a typical 1.63 m eye height (waist ≈ 1.04 m by
  `waist ≈ 0.64 × eyeHeight`), **15 cm below the waist — mid-thigh.** Everything is too
  low for a standing adult and arbitrarily placed for anyone else.
* **The fix is available and cheap.** `mo.HmdPosition.y` plus the `vr_height_adjust` cvar
  is the player's measured eye height in metres (`hw_vrmodes.cpp:445`,
  `hw_openxrdevice.cpp:151-155`). Anchor the slots to the floor and scale by it:

  ```
  eye_m   = mo.HmdPosition.y + vr_height_adjust          // measured, metres
  waist_m = 0.64 * eye_m                                 // iliac crest ≈ 0.60 × stature;
                                                          // eye ≈ 0.936 × stature
  slotZ_mapunits = mo.pos.z + (slotHeightFraction * eye_m) * vu / pixelstretch
  ```
  and express the table as fractions of eye height (waist 0.64, chest 0.86, shoulder 0.96)
  rather than centimetres below a phantom datum. Then do the reach test in real
  centimetres against that anchor with the §2.3 conversion. One formula, every player,
  seated or standing.

Horizontally the existing code is right: `mo.pos` is the correct datum, because it is the
datum the engine itself uses for the hands (`hw_openxrdevice.cpp:593-594`), and
`mo.Angle` is the right yaw basis (`:590` builds `AttackAngle` from `getViewpointYaw()`,
which is sampled from the camera's yaw at `:556`).

### 3.3 Why the satchel ended up "14 cm in front of the face"

Two causes, stacked, and only one of them is a frame error.

* `PosF` for slot 6 was `+14` — 14 cm *forward of the pawn origin*, at an implied height
  of 105 cm. On a correct body that is on the belly, not the face.
* But `MODELDEF.holster`'s satchel block carries `Scale 6.00 6.00 6.00`
  (`MODELDEF.holster:75`), copied from the TC's pickup block, which the TC writes against
  a weapon actor scaled **0.1**. World models multiply the actor's scale by MODELDEF's
  (`models.cpp:82-84`), so a ghost at the default actor scale 1.0 drew the satchel **ten
  times too large** — a ~1.2 m crate centred 14 cm in front of the chest, with the camera
  inside it. That is the "filled the view". `holstertable.zs:9-18` diagnoses this
  correctly and fixes it by giving each ghost its weapon's actor scale
  (`AE_Holster_Satchel: Scale 0.1`, `holstertable.zs:69`).

So the owner's report was the scale bug, already fixed; the 14 cm was then patched to
−20 cm (lower back, `holstertable.zs:79`), which is where a satchel belongs anyway.
Both the scale fix and the lower-back move are right. The datum error of §3.2 is
untouched and is the remaining frame bug.

### 3.4 Three more concrete defects

* **`Roll(i)` is dead code.** `holster.zs:174` sets `g.Roll`, and the table gives the rifle
  and shotgun slots ∓25° (`holstertable.zs:97`). But a world model takes the actor's roll
  **only** with `MDL_USEACTORROLL` (`models.cpp:138`), set only by the MODELDEF keywords
  `useactorroll` / `inheritactorroll` (`models.cpp:897-907`) — and no block in
  `MODELDEF.holster` declares either. Pitch likewise: there is no way to angle a slung
  rifle at all. **Fix: add `UseActorPitch` and `UseActorRoll` to every holster block**, and
  the roll already in the table starts working.
* **No button — proximity alone fires the weapon switch.** `holster.zs:85-91` swaps the
  weapon the instant the off hand enters 18 cm of a slot. With seven slots at 18 cm reach
  and 26 cm leave, and the slots 15-40 cm apart, ordinary arm movement crosses them. This
  is a sufficient explanation for the owner turning it off, independent of any frame
  error, and it is the thing §4 says must change.
* **Per-tick churn and always-on drawing.** `Place()` is called for all seven slots every
  `WorldTick` whether or not they are visible, and show/hide is implemented as
  `Spawn`/`Destroy` (`holster.zs:141-157`). Up to **seven world model draws every frame,
  all the time**, each with its own dynamic-light gather, on a Quest. The fix is a pooled
  actor per slot that is hidden rather than destroyed, and a single cheap gate — draw
  nothing unless the off hand is below the chest line — which makes the common case zero
  draws.

### 3.5 Is the approach the right foundation?

**Yes — world actors are the correct mechanism, and should be kept.** The reasons are in
§1.4: a world actor is natively body-fixed, takes full Angle/Pitch/Roll, is depth-sorted
against the level, survives to within ~1.5 cm of the eye (near plane 0.5 units,
`v_video.h:294`), and is explicitly exempt from the near-camera sprite cull because it has
a model and zero velocity (`hw_sprites.cpp:889-894`). The HUD path cannot do body-fixed at
all (`models.cpp:229-234` is dead in VR) and the counter-transform alternative (§2.4) is
strictly worse.

What should be replaced is the **datum** (§3.2), the **input rule** (no button → a button),
the **slot count** (seven weapon slots at 18 cm → four or five clusters at 8 cm), and the
**draw budget** (always-on → gated and pooled). That is a rewrite of `holster.zs`'s body
of logic, keeping its architecture and its asset pipeline intact.

---

## 4. How a body-gear reach collides with the reload system — and how not to

This is the part that matters most, because the reload gestures are the owner's priority
and a belt must not cost them anything.

### 4.1 What the reload already owns

| resource | owned by | citation |
|---|---|---|
| the off hand's **position**, during EMPTY/CARRY/INSERT and the whole pump cycle | `RSR_State` / `RSP_State` | `vreload.zs:33-42`, `rsr_pump.zs:51-57` |
| **BT_OFFHANDATTACK** (the off trigger) — "grabs anywhere" | `rsr_grab_buttons`, default `67108864` = 1<<26 | `CVARINFO.rsr:12`, `vreload.zs:269-272` |
| the **off grip**, as raw key codes 443 / 436, relayed by netevent, and **eaten** while a reload is running | `rsr_grip_keys`, `rsr_eat_grip` | `CVARINFO.rsr:11`, `vreload.zs:979-1007` |
| a 20 cm exclusion around the magazine well, and optionally a 40 cm-below-the-eyes pouch rule | `RSR.POUCH_MIN`, `POUCH_LOW`, `rsr_pouch` | `vreload.zs:47-48`, `:289-307`, `CVARINFO.rsr:14` |
| the main hand's **downward flick** | `AE_Flick` | `flick.zs:19-24` |
| **fast off-hand motion** = a punch | `melee.zs` | `CVARINFO.ae:72-74` |

And the reload already has to dodge the engine's two-hand steady by hand: the off grip is
treated as a grab **only** when its press could not have started a steady —
`RSR.GripCanGrab` returns true only if `vr_two_handed_weapons` is off or
`SteadyGap() >= 50 cm` (`vreload.zs:101-107`), matched to the engine's hard-coded 0.50 m
(§2.1). That guard is correct and it is also the proof that the grip is already
triple-booked: engine steady, reload grab, and eaten-while-busy.

### 4.2 Where the current holster design competes — plainly

**It competes, and badly.**

* **Same hand, same place, same moment.** The reload's `EMPTY` phase is defined as "no
  magazine; the hand goes for one" (`vreload.zs:35`), and `rsr_pouch 1` says a magazine is
  taken "40 cm below the eyes" (`CVARINFO.rsr:14`). The holsters put the pistol slot at
  `PosL −20, PosU −58` (`holstertable.zs:85`, `:91`) — the same hip, the same reach, the
  same 10-20 cm of air.
* **The guard is too late.** `holster.zs:63` only suppresses the holster while a reload is
  *already running* (`RSR_Handler.FreeHand(mo) != ""`). It does nothing in the window
  where the player's hand is travelling toward the hip *to start* a reload: the holster
  fires first, `PendingWeapon` changes the weapon, and the reload the player intended now
  belongs to a different gun. That is the worst possible failure, because it destroys a
  gesture the owner cares about in order to serve one he called "just an idea".
* **Proximity with no button makes it unavoidable.** There is no press to disambiguate
  "my hand is passing my hip" from "I want what is on my hip" (§3.4).

**Therefore: reject the current holster scheme.** Not because the frame is wrong — that is
fixable — but because a buttonless proximity weapon-swap sharing the off hand with the
reload cannot be made safe by tuning.

### 4.3 The rules a belt must obey

1. **Never use the off trigger.** `BT_OFFHANDATTACK` is the reload's grab
   (`CVARINFO.rsr:12`) and the pump's. A belt on the off trigger means every hip-level
   reach during a reload is ambiguous.
2. **Never use the off grip.** It is the engine's steady, the reload's secondary grab, and
   is eaten while busy (§4.1).
3. **Use `BT_USER3` (recommended) or `BT_USE`** — §1.6. Neither is touched by the reload,
   by `rsr_pump`, by `flick.zs`, or by the engine's steady.
4. **Refuse while any reload owns the hand**, with the existing predicates, both of them:
   `RSR_Handler.FreeHand(mo) != ""` **and** `RSP_Handler.Busy(consoleplayer)`
   (the pattern at `vreload.zs:1000`). The current code checks only the first.
5. **Refuse while steadied.** `RSVR_VRHand.Steadied(mo)` — not just to avoid the gesture
   clash, but because the engine does not draw off-hand layers at all while stabilised
   (`hw_weapon.cpp:917`), so anything the belt puts in the off hand would be invisible.
6. **Never spend the off hand's motion.** No velocity test anywhere near the belt:
   `melee.zs` already claims fast off-hand motion as a punch
   (`CVARINFO.ae:72-74`) and `flick.zs` claims the main hand's downward jerk
   (`flick.zs:19-24`). A belt is position + button, full stop.
7. **Do not make a belt grab a weapon switch.** `PendingWeapon` is the heaviest thing a
   gesture can do, and `holster.zs:13-16` is honest that there is no empty-handed state to
   switch *to*. A belt that hands over a *magazine, shells, or a grenade* changes no
   weapon and cannot interrupt anything.

### 4.4 Where a belt actively *helps* the reload

This is the design to build, and it is the opposite of a competitor.

`CanTakeMag` currently accepts a magazine from anywhere more than 20 cm from the well,
with an optional "40 cm below the eyes" rule (`vreload.zs:289-307`). Replace the optional
rule's crude height test with "within R of the belt's magazine cluster", computed by §2.3
against the corrected anchor of §3.2, and the belt becomes a **position constraint on a
gesture that already exists plus a visible model to reach for**. It adds no input channel,
no new state machine, no new claim on the hand, and it makes the existing reload better in
the way the owner actually asked for — you reach to a place you can see, instead of
anywhere low. The magazine still appears in the hand on the existing `RSR.HANDMAG` layer
(`vreload.zs:28`, `:636`), drawn by the existing code. Nothing in the reload changes except
one predicate.

Shells are the same story: `rsr_pump` already has `POUCH_MIN`/`POUCH_LOW`
(`rsr_pump.zs:64-65`) and already draws a shell in the hand on `RSP.HANDSHELL`
(`:46`, `:964`). A bandolier is a model plus a tightened predicate.

---

## 5. The supplied Colonial Marine belt meshes

Two OBJ sets, each one `.obj` + `.mtl` + four PNG maps (`_D` diffuse, `_N` normal,
`_S` spec, `_M`), in
`…\scratchpad\belt01\A-CM_X360_MULTIPLAYER_Colonial_Marine_Belt_01\` and
`…\scratchpad\belt02\A-CM_X360_MULTIPLAYER_Colonial_Marine_Belt_02\`.
I re-ran a connected-component analysis to get real anchor coordinates.

**Belt 01** — 534 verts, 564 faces, 27 islands, bbox `x −0.224…0.248, y −0.101…0.083,
z −0.091…0.186` (metres, y up).
**Belt 02** — 609 verts, 588 faces, 40 islands, bbox `x −0.217…0.248, y −0.103…0.079,
z −0.084…0.183`.

Every island spans nearly the full 18 cm `y` range, so `y` is the belt's height and the
items are distinguished in the `xz` plane. Ring extent 47 cm × 27 cm; the model origin is
**not** the waist centre — the ring centres on about `(x +0.015, z +0.05)`. **There is
nothing behind `z ≈ −0.09`: this is a front-and-sides belt with no rear pouches**, so a
satchel-on-the-back cannot come from this mesh.

Clusters, as centres relative to the ring centre, in centimetres, `+z` forward
(which side is the wearer's right is **UNVERIFIED** without a render — it is a one-line
sign flip in the anchor table either way):

| cluster | belt 01 | belt 02 | size | reading |
|---|---|---|---|---|
| big hip item | `(+17.1, −2.6)`, 12.5×16.8×22.2 cm | `(+17.5, −3.3)`, 11.7×14.5×18.6 cm | largest island by far | a drop-pouch / holster-sized block on one hip |
| front row, 3 boxes | `(+5.3,+9.5) (−1.8,+10.6) (−8.9,+9.4)`, ~7.4×17.5×6.7 cm each | `(+7.3,+9.0) (−0.2,+10.7) (−7.7,+10.1)`, ~8×17×6 cm | **7-7.5 cm apart, touching** | three magazine pouches |
| side row | 4 flat boxes `x −14…−21.6`, `z +5.2…−10.7`, ~6.5×13×6.5 cm | 2 flat pouches `(−20.7,−4.3) (−20.1,−10.2)` | 5.7 cm apart | utility pouches |
| **grenade loop** | — | 4 cylinders `(−12.8,+6.8) (−15.6,+5.1) (−17.5,+2.7) (−19.3,0.0)`, 3×10×3 cm each with disc caps top and bottom | **3.3 cm apart** | four grenades or flares in a loop — exactly the Aliens detail worth having |
| straps / flaps | ~14 thin islands | ~20 | 1-2 cm thick | not reach targets |

**Four usable anchors, not eleven.** 3.3 cm and 7 cm spacings are far below what a
controller and a hand can select reliably at R = 8 cm (§2.5). So: *right hip* (big item),
*front centre* (the three mag pouches as one target), *grenade loop* (the four cylinders
as one target, with a count of 4), *left rear* (utility). Each cluster gets one payload and
a counted stack — which is exactly what the owner asked for, "each box offer something
different", at cluster granularity. Belt 02 is the better mesh for this pack on the
strength of the grenade loop alone.

**What MODELDEF can and cannot do with it:**

* **No conversion is needed.** `.obj` is loaded directly at this commit
  (`src/common/models/model.cpp:192`, loader `src/common/models/models_obj.cpp`).
  `E:\DOOMWork\tools\md3_write.py` exists if an MD3 is wanted later (not run here); the
  OBJ loader's surfaces are split per `usemtl` (`models_obj.cpp:126-156`,
  `hasSurfaces = surfaces.Size() > 1` at `:225`).
* **Per-box skinning is impossible as shipped.** Both `.mtl` files declare exactly one
  material ("Material Count: 1"), so each belt loads as **one surface**. `SurfaceSkin` and
  `CMDL_USESURFACESKIN` have nothing to index. There is no island-level control in
  MODELDEF — the 27 and 40 islands are invisible to the engine.
* **Per-box show/hide therefore needs separate model files**, declared as
  `Model 0 "belt_base.obj"`, `Model 1 "belt_grenades.obj"`, … in one block (no index
  limit, `models.cpp:763-776`), and hidden at runtime with
  `A_ChangeModel(modelindex: k, flags: CMDL_HIDEMODEL)` → `modelID = -2` → skipped
  (`p_actionfunctions.cpp:5481`, `models.cpp:446-449`).
* **Budget it.** Each model index is one `RenderModelFrame` call
  (`models.cpp:631-637`). Split into 8 and the worn belt costs 8 draw calls every frame it
  is visible. Split into **two or three** — base belt (always), grenade cylinders (hidden
  as they are used), and at most one more — and it costs two or three. The owner said no
  animation and no opening lids, which is what makes this cheap: a static ring plus a
  disappearing stack.
* **Scale and axes.** The OBJ is metres with `y` up; Doom models are `z` up, so either
  rotate the source or use `PitchOffset`/`RollOffset`. On the world path the scale needed
  is `vu` horizontally and `vu / pixelstretch` vertically — i.e. `Scale 34 34 28.33` at
  defaults, remembering that the **actor's** scale multiplies it (`models.cpp:82-84`) and
  that this is exactly the trap the holster ghosts already fell into
  (`holstertable.zs:9-18`). Declare `UseActorPitch` and `UseActorRoll` so the belt can be
  tilted to sit on the hips.
* 534-609 verts and ~570 faces is nothing for a Quest: a pulse-rifle mesh is heavier. The
  cost is draw calls and the four 112 KB textures, not geometry.

---

## 6. Designs

Kept short where speculative, per the priority correction. All four are mod-side on stock
QuestZDoom 17.3.

### Design A — "The body frame" (cheap, certain, and a prerequisite for everything else)

**Not gear.** One `RSQ_Body` class that computes, once per `WorldTick`, and publishes for
everyone else: the measured eye height (`mo.HmdPosition.y + vr_height_adjust`), the
derived waist/chest/shoulder heights as fractions of it, the yaw basis from `mo.Angle`, the
cached `vu` and `pixelstretch`, and one function `ReachCm(Vector3 anchorWorld, int hand)`
implementing §2.3 exactly. Plus one `AnchorWorld(slot)` that builds a world position from a
`(forward, side, heightFraction)` triple.

What the player does: nothing. What it costs: a dozen multiplies per tic and it *removes*
cost, because `holster.zs:119` and `:159`, `vreload.zs:302`, `melee.zs:104`, `flick.zs` and
`vrhand.zs:84` each re-read the same cvars and redo the same conversion today. How it
fails: it cannot — it is arithmetic over readonly fields. Interaction with the reload:
strictly positive; `vreload.zs`'s own `below = (viewz - op.z) * ps * 100 / vu` (`:302`)
becomes one call against a correct datum. **This is what I would build first**, and I would
build it even if no belt is ever shipped, because it is also the correct home for the
`SteadyGap` conversion the reload already depends on.

### Design B — "The belt is where magazines live" (the one that pays for itself)

Draw belt 02 as a world actor worn at the waist, anchored by Design A, with
`UseActorPitch`/`UseActorRoll`, pooled (one actor, never destroyed, hidden by moving it
away or by `CMDL_HIDEMODEL` on index 0), and drawn only while the off hand is below the
chest line — one scalar compare, so zero draw calls in the common case. Then change
**one predicate**: `RSR.CanTakeMag` (`vreload.zs:289-307`) requires the off hand within
R = 8 cm of the front-centre magazine cluster, and `RSP`'s shell take
(`rsr_pump.zs:64-65`) requires it within 8 cm of the same cluster or its own bandolier
anchor. The grab stays the off trigger **because it is the reload's own grab, on the
reload's own gesture** — no new input channel at all. The three front pouches show a count
by hiding the grenade/mag sub-model as the reserve falls, via `A_ChangeModel` +
`CMDL_HIDEMODEL`.

What the player does: the pulse-rifle reload he already does, except there is now a visible
set of pouches at his waist to reach to, and reaching anywhere else does not work (when
the pouch rule is on). Cost: 1-3 draw calls while the hand is low, ~0 otherwise; one extra
distance test inside a predicate that already runs. Failure modes: a player with
`vr_height_adjust` badly set has a belt at the wrong height (mitigate with one
`ae_belt_height` slider, renderer-read — see the hard rule in memory); a crouching player
with `vr_crouch_use_button 0` has `viewheight` moving under him, which Design A avoids by
anchoring to `mo.pos.z` and `HmdPosition.y` rather than `viewheight`. Reload interaction:
**this is the reload**, narrowed, not a competitor. Aliens-specific: the M41A's box
magazines in the three front pouches; shotgun shells get their own cluster.

### Design C — "The grenade loop" (small, self-contained, high flavour)

Belt 02's four cylinders at the left front hip (§5) as one anchor with a payload count of
four. Reach within 8 cm **plus `BT_USER3`** (a fresh button, §1.6) and one grenade leaves
the loop: the cylinder sub-model's count drops by one via `CMDL_HIDEMODEL`, and the
grenade appears in the off hand on a new psprite layer owned by `RSQ_Hands` — the
mechanism `RSR.SetPart` already provides (`vreload.zs:117-142`), placed by
`RSQ_Place.Layer`'s existing dispatch (`hands.zs:92-104`). Throwing it reuses the hand-speed
differencing `melee.zs:104-119` already does, at a threshold well above the punch
threshold. Cost: one extra model index on the belt, one psprite layer while carrying.
Failure modes: the throw-vs-punch threshold needs separating from `ae_stab_speed`
(`CVARINFO.ae:73`) or a hard throw will register as a punch — that is a real collision and
the reason this is design C and not design B; and a grenade in the off hand is invisible
while the gun is steadied (`hw_weapon.cpp:917`), so the loop must refuse while
`Steadied()`. Reload interaction: none, if and only if it uses `BT_USER3` and not the
trigger.

### Design D — "Worn, not holstered" (ambitious; I would not build it yet)

Replace the seven weapon holsters with **four cluster anchors** (§5) on the corrected
frame, each with a payload that is *not a weapon switch*: magazines, shells, grenades, and
one chest sheath for the knife. The knife is the only item that wants to become a held
weapon, and the pack already has a path for a second weapon in the off hand
(`ae_dual_*`, `CVARINFO.ae:48-51`, `MODELDEF.aedual`, the `ae_dualkey` bind at
`KEYCONF.ae:5-11`) — so "knife on the chest" is "pull it and it becomes the off-hand
weapon", not a `PendingWeapon` swap of the main gun. Long guns on the back are out: belt 02
has no rear geometry (§5), and a slung rifle needs pitch on a model whose MODELDEF blocks
currently declare no `UseActorPitch` at all (§3.4). Cost: the full four-anchor draw and
state machine, plus a real arbitration layer that we have to write ourselves because QZD
has no `GripClaim` equivalent (§1.7). Failure modes: everything in §4.3 at once.
Reload interaction: manageable only with the §4.3 rules enforced in one place.
**Verdict: design the arbitration before the gear, or do not do it.**

### What our PCVR family does, and whether QZD can

Our PCVR holsters live in packages this study may not open — one on ice, one quarantined —
so I describe only the architecture visible from the files I may read.

* **A service interface so packages need not name each other.**
  `RS_VR_Reload/zscript/wm/mountservice.zs:1-50` exposes `wm.look` (what to draw on a
  mount), `wm.model` (`"path|file"`), `wm.mountable` (the card's declared mount:
  back-left, back-right, off-hand forearm), `wm.bindnow`, `wm.topup` — reached by
  `ServiceIterator.Find("RS_WeaponMountService")`.
  **QZD 17.3 can do this**: `Service`, `ServiceIterator` and the no-compile-time-link
  property are stock GZDoom 4.14 features, and `rs_griparbiter.zs:29-46` documents exactly
  why that matters. Worth adopting here *only* if a second Quest pack will consume it;
  today there is one pack, and a plain class is cheaper.
* **A separate prop actor carries the model, because a VR gun's Ready state is TNT1**
  (`mountservice.zs:13-19`). **QZD can do this** — it is what `AE_HolsterGhost` already is.
* **A shared per-hand grip claim arbitrated in the engine**
  (`rs_griparbiter.zs:1-27`: `GripClaimMain`/`GripClaimOff`, three mods writing them).
  **QZD 17.3 cannot do this**: those fields do not exist here (grep: absent, §1.7). On the
  Quest, arbitration has to be a ZScript-side single owner — and the lesson from that file
  stands: identify a claim by its *owner*, never by its value.
* **Anything that needs a writable hand pose or a per-actor model-angle override.**
  **QZD cannot**: every pose field is `readonly` (`actor.zs:268-277`) and
  `ForceModelAngles` does not exist (§1.7).

---

## 7. Recommendation — ranked

1. **Build Design A, the body frame.** One class, no gear, no visuals, no input. It fixes
   the datum error of §3.2 for everyone at once, deletes five duplicated cvar-and-convert
   blocks, and is the only place the §2.3 reach test should ever be written. Do this even
   if the belt is never shipped.
2. **Fix `MODELDEF.holster` and gate the existing holsters properly, or delete them.**
   Add `UseActorPitch`/`UseActorRoll` (two lines per block) so the roll in the table stops
   being dead; pool the ghosts instead of `Spawn`/`Destroy`; gate drawing on the hand being
   low. Then **require a button** — `BT_USER3`, default-bound to Pad_B — and add the
   `RSP_Handler.Busy` and `Steadied()` guards. If the owner does not want holstered
   weapons at all (and §4.2 is a good reason not to), **delete `holster.zs`,
   `holstertable.zs`, `MODELDEF.holster` and `ae_holsters`** and keep only Design A. A
   dead subsystem that costs seven draw calls when someone flips a cvar is worse than no
   subsystem.
3. **Build Design B, the belt as the magazine source.** Belt 02, one world actor, two or
   three model indices, drawn only when the hand is low, and **one changed predicate** in
   `vreload.zs`/`rsr_pump.zs`. This is the only body-gear idea that makes the reloading the
   owner cares about *better* rather than riskier, and it introduces no new input channel.
4. **Build Design C, the grenade loop**, after the throw/punch thresholds are separated
   from `ae_stab_speed`. Small, self-contained, and the most Aliens-looking thing on the
   belt.
5. **Do not build Design D yet**, and do not build any of it in its current form: no
   holstered long guns on the back (the mesh has no back and the models cannot pitch),
   no shoulder sling, no backpack reach, no satchel-on-the-back from this mesh.
6. **Do not build at all:** (a) the counter-transformed psprite-layer body gear of §2.4 —
   a three-axis Euler inversion in a mirrored frame in `ui` scope, every frame, for
   something a world actor does for free; (b) any gear on the **off grip** or the **off
   trigger** (§4.3); (c) any gear keyed on **hand velocity** near the belt, which would
   collide with `melee.zs` and `flick.zs`; (d) per-island belt boxes as eleven separate
   anchors — the mesh's 3.3-7 cm spacings cannot be selected reliably at any usable radius
   (§5); (e) one-hand haptic feedback, which the engine cannot do (§1.7).

**Open checks, as checks rather than claims.** Three things in this study are
UNVERIFIED and each has a cheap settlement on the pack's own rig
(`tools/rig/`, handoff §3): that `mo.Angle`/`mo.Pitch` track the HMD (set
`qz_hmd "0 1.7 0 0 90 0"` and print them from a WorldTick — the whole yaw basis rests on
it); that `A_ChangeModel` compiles when called as a method from an `EventHandler`
(§1.5 — one compile); and which side of belt 02 is the wearer's right (one render, and a
sign flip in the anchor table either way).

---

## 8. Appendix — ideas that would need an engine change, and therefore cannot ship

The pack must run on the stock QuestZDoom app, so none of this is proposable for
RS_Aliens_Q. Recorded only so nobody re-derives it. For reference, the equivalents already
exist in our own fork (`E:\UZDXREMA`), which is why the PCVR family can do things this
pack cannot.

* **Expose the two-hand test's radius and result.** `weaponStabilised` is a C++ global
  (`src/QzDoom/qzdoom_common.cpp:19`, `src/common/rendering/hwrenderer/data/hw_vrmodes.h:100`)
  and reaches ZScript only through a flag refreshed at psprite state changes
  (`src/playsim/p_pspr.cpp:512-515`). The change: a `DEFINE_FIELD` on `AActor` for the
  flag updated in `VRMode::SetUp()` (`hw_vrmodes.cpp:432-447`), and a
  `vr_two_hand_radius` cvar replacing the hard-coded `0.50f`
  (`src/rendering/gl/stereo3d/gl_openvr.cpp:1722` and its out-of-tree Quest twin in
  `VrInputDefault.cpp`). Files: `hw_vrmodes.cpp/.h`, `vmthunks_actors.cpp`, `actor.h`.
* **Controller velocity.** Every gesture in this pack differences positions per tic
  (`melee.zs:104-119`, `flick.zs`), which costs a tic of latency and a tic of noise. The
  change: publish `AttackVel`/`OffhandVel` alongside the poses in
  `hw_openxrdevice.cpp:585-610`, declare them in `src/playsim/actor.h:1652-1668`, register
  in `src/scripting/vmthunks_actors.cpp:2185-2195`, declare in
  `wadsrc/static/zscript/actors/actor.zs:268-277`. (Ours has this; see the
  controller-velocity follow-ups.)
* **A ZScript haptics call.** `VR_HapticEvent` is declared at `hw_vrmodes.h:97` and
  stubbed at `qzdoom_common.cpp:65`; `VRMode::Vibrate` already exists and is called from
  `v_blend.cpp:138` and `sbar_mugshot.cpp:348`. The change: one
  `DEFINE_ACTION_FUNCTION` wrapping `Vibrate(duration, channel, intensity)` with a
  `channel` argument so one hand can be addressed. File:
  `hw_vrmodes.cpp` plus a thunk. Without it, the only mod-side pulse is
  `player.bonuscount = 1`, which fires both hands and flashes the screen (§1.7).
* **A body-anchored HUD model.** `src/r_data/models.cpp:229-234` already contains a
  pawn-anchored branch; it is unreachable because `GetWeaponTransform` always succeeds in
  VR (`hw_vrmodes.cpp:455-470`). The change: a psprite flag, or a layer-ID range, that
  selects the body anchor instead of the hand. One `if` in `RenderHUDModel`. That one
  change would make body gear a psprite layer instead of a world actor, with correct
  near-plane behaviour and no thinker — but it is an engine change, so for this pack the
  answer is the world actor.
* **Per-actor model angle override** (`ForceModelAngles` in our fork) so a world-actor
  belt or slung rifle can be oriented without the MODELDEF flags and without the actor's
  own angles. File: `src/r_data/models.cpp:130-138`, `src/playsim/actor.h`.
