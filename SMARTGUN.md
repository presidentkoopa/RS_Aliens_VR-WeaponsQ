# M56 Smartgun

Three behaviours, each using a mechanism already proven elsewhere in this pack
rather than a new one.

## The harness gimbal

The M56 hangs off an articulated arm. The gun swings to follow a target while
the operator's arms stay where they are — which is a VR mechanic by nature,
and the engine already does the hard part.

`hw_weapon.cpp` turns a psprite's x/y into a HUD model's yaw and pitch:
`yaw = x/4`, `pitch = (y - WEAPONTOP)/-4`. `zscript/rsq/hands.zs` documents
this because the hand layers have to subtract their own tilt back out. So
tilting the *weapon* layer swings the gun, and because the hand layers carry
their own (zero) tilt, the hands do not follow. Gun swivels, hands stay. No
layer ownership, no clear skins, no second copy of the model.

Limits: 22 degrees of yaw, 16 of pitch, eased 18% a tic toward the wanted
angle. The lock is the nearest live monster within 35 degrees of the gun's
forward, 2048 units, and in line of sight — deliberately the same question the
gun's own restored `A_JumpIfTargetInLOS` asks, rather than a second tracker
behaving differently alongside it.

It is **additive**. The gun's own states drive the same psprite — `Offset(0,52)`
during the reload, the recoil frames during fire — so the gimbal remembers
what it put there last tic, takes that back off, and adds the new value to
whatever the weapon has meanwhile set. Assigning x and y outright would have
silently cancelled every animation the set already has.

It stands down entirely during a reload, and lets go at once on a weapon
switch rather than easing, so it never tilts the gun you switched *to*.

## Rounds that track

A gun that points at a target and shoots straight ahead is worse than one that
does not point.

`SmartgunTracer` lives in the base Aliens Eradication pk3, which this addon
does not include. It is therefore neither subclassed nor replaced: guessing a
projectile's damage and speed in order to re-declare it would be inventing
gameplay. Instead each round is marked by class name as it spawns and steered
afterwards, which needs nothing from the base pk3 and works whatever that
class turns out to be. The projectile stays exactly as the set ships it.

The steer is weak and capped — `ae_smartturn`, 6 degrees a tic. A smart round
nudges; a homing missile removes the shooting. At the default a round pulls
about a body's width across a room.

## The lock-on, restored

The set shipped with `A_Jump(256, "LockedOn")` ahead of its own tracking
check. 256/256 is an unconditional jump, so `LockOnTarget` / `HoldFire` and
their `A_JumpIfTargetInLOS` were unreachable: the M56 always fired as though
locked and never looked for a target. Both smartguns had it. `ae_smartlock`
runs the check the labels were written for; 0 restores shipped behaviour.

## Switches

- `ae_smartlock` — the gun's own lock-on (default on)
- `ae_gimbal` — the harness swing (default on)
- `ae_gimbal_flip` — negate the yaw. The engine mirrors the left controller and
  the sign could not be confirmed without a headset. If the gun leans *away*
  from targets, set this.
- `ae_smartturn` — degrees a tic a round may turn (default 6, 0 = off)
- `ae_handswitch` — flick the selector on the receiver with the off hand
  instead of pressing alt-fire

## Untested

None of this has run in an engine. The geometry and the name-level consistency
are checked by `tf/check_pack.py` and `tf/check_reload.py`; the feel is not.
The yaw sign and the gimbal limits are the two things most likely to want
adjusting on first sight.
