# Plan, 2026-10-23 — "all of it"

Owner: "all of it, proceed however you see fit but be sure to draw up a sensible plan and stick
to it." This is that plan. Ordered by what unblocks the owner first, then by (impact x certainty)
/ effort. Every step ends the same way: build, compile-check, in-level boot-check, install to all
three pk3 locations, report. No step is reported done on a compile alone.

Test harness and paths: `docs/` has none of it — see the memory note
`aliens-pack-build-and-test-harness`, or in short: `tools/mkpk3.py` to pack, the engine copied to
scratch so it cannot touch the owner's ini, `-norun` for a parse and `+map MAP01` for a live boot.
A `vr_mode 0` run proves it compiles and does not abort; it proves NOTHING about where hands sit.

---

## 1. The Doom patch  (unblocks everything else)

Why first: the owner cannot see in Aliens Eradication ("too damn dark"). Until the guns run on
ordinary Doom maps he cannot usefully test any of the rest of this list. It is also the most
mechanical item here, so it is the cheapest large win.

A separate pk3, `AliensVR_DoomPatch.pk3`, loaded AFTER the weapons pack. The weapons pack is not
modified. Built from `E:\DOOMWork\AliensVR_DoomPatch\`.

The pack needs **76 classes that live in the TC**, established statically by cross-referencing
every parent / `replaces` / inventory / projectile / `StartItem` / `AmmoType` reference in the
pack's DECORATE against the TC's own actor list. Three sub-steps:

- **1a — make it LOAD.** The non-combat classes: 23 parent weapons, the magazine counters
  (`PistolLoaded`, `PulseLoaded`, `ShotgunLoaded`, `SmartLoaded`, the Yutani twins...), the
  reserve ammo (`PistolClip`, `PulseRifleClip`, `Smartgunbullets`, `GAS`, `AliensShell`,
  `GrenadeAmmo`, `SatchelAmmo`), the spawners, and the player tokens (`IsPlayer`, `YutaniClass`,
  `TargetIsAMarine`...). Magazine caps must match each gun's own reload loop — they are recorded
  in `DECORATE.aedual`'s off-hand Ammo stubs (pistol 12, Yutani pistol 18, Synth 30, shotgun 8,
  pulse rifle 95, flamer 150). Done when the pack parses on doom2.wad with no TC.
- **1b — make it SHOOT.** The 17 projectiles (`ShotgunTracer`, `SmartgunTracer`,
  `DummyProjectile1-4`, `FTFire`, `ColPistol`, `PulseGrenade`, `SatchelThrow`, `TankThrow`...).
  These are the guns' actual bullets, so a harmless stub means guns that do nothing. Written as
  OUR actors with OUR numbers — the TC's definitions are not copied. Values start from the
  owner's stated stat sources (vanilla for pistol/shotgun, and the pack's own rate of fire) and
  are his to tune. Done when a summoned monster dies to each gun.
- **1c — make them REACHABLE.** Replace Doom's weapons and ammo so the guns appear in ordinary
  maps: pistol→Pistol, shotgun→Shotgun, pulse rifle→Chaingun, smartgun→SSG slot, flamer→Plasma,
  and the reserve ammo onto Doom's Clip / Shell / Cell pickups. Slots via KEYCONF.
  Done when a pistol start on MAP01 gives a working M4A3 and the map's pickups arm the rest.

## 2. Power Loader — the hidden model

Owner already reported it: "much of the model is being hidden". Diagnose `modeldef.loader.txt`'s
`SurfaceSkin` / clear-skin blocks, the `avw_weapons` cvar gate, and MD3 surface-slot overflow
BEFORE cutting any mesh. Small, known, and his own report.

## 3. The assets the pack already ships and never uses

The highest Aliens-feel per unit of work in the whole repo, because the art is already here:

- **Smartgun display** — `smart_hud.md3`, `smart_mode1.png`, `smart_mode2.png` + brightmaps.
  Shipped, referenced by nothing. The gun's own screen.
- **Motion tracker + visor** — `graphics/radar/RDR1A0..K0.png`, `AVISOR0..10`, `NOVIS0..10`.
  Shipped, referenced by nothing. The motion tracker is *the* Aliens instrument, and the free
  hand is already a drawable off-controller layer that can hold it.
- **Smartgun lock tone** — `smartgun.zs` already tracks whether it had a target (`s.had`) and
  never reads it, so acquiring a lock happens in silence.

## 4. Body frame, then the belt

In this order, because the belt is worthless on a wrong datum.

- **4a — the body frame.** One class computing, once per tick: measured eye height from
  `HmdPosition.y + vr_height_adjust`, waist/chest as fractions of it, the yaw basis from
  `mo.Angle`, and ONE reach test. The current holster slots use a fixed datum 1.447 m above the
  floor, so they are mid-chest for a tall player and above the eyes seated. Five places in the
  pack re-read the same cvars and redo the same conversion, one of them inside `vreload.zs`, so
  this REMOVES work as well as fixing it.
- **4b — the belt as a magazine source.** Belt 02 (it has the four-grenade loop), worn at the
  waist, drawn only while the off hand is below the chest. Then change ONE predicate:
  `RSR.CanTakeMag` and the pump's shell take require the hand near the belt's cluster instead of
  "anywhere 20 cm from the gun". No new button, no new state machine, no new claim on that hand —
  the gesture the owner already does, with something visible to reach for. 4 anchors, not 11: the
  pouches are 3-7 cm apart, far below what a controller can select.
- **4c — the holsters.** Either gate them properly (a button, plus the `Busy()` and `Steadied()`
  guards they lack) or delete them. As they stand they fire on proximity alone and can switch the
  weapon out from under a reload that is about to start. Owner's call; they are off by default.

## 5. Per-gun polish (taste — his eyes and ears decide)

Pulse rifle: real 4-round burst cadence, a per-shot transient instead of one looping sample,
counter dark when the magazine is out, launcher count in the window, and the `m41a_pump`
handguard actually moving with the hand. Shotgun: the one-handed toss-and-catch forend cycle.
Flamethrower: the tank throw is already good and badly undersold. Satchel: a real throw/place
gesture.

---

## Not in this plan, on purpose

- No engine changes. The Quest runs the stock QuestZDoom app.
- No hand hook/rot numbers in `handtable.zs` — the owner tunes those himself.
- Nothing from `_old/` or `RS_HardPoints/`.
- `rsr_m203.zs` is not ported: it is a sliding breech that takes a loose round, the M41A's is a
  pump, and porting it would not move the pump.
