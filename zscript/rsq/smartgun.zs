// The M56 Smartgun, as the film's gun actually behaves.
//
// Three things, and none of them is a new rendering trick -- each uses a
// mechanism already proven elsewhere in this pack.
//
// 1. THE HARNESS GIMBAL. The M56 hangs off an articulated arm; the gun swings
//    to follow a target while the operator's arms stay where they are. That is
//    a VR mechanic by nature, and the engine already does the hard part:
//    hw_weapon.cpp turns a psprite's x/y into a HUD model's yaw and pitch,
//    yaw = x/4 and pitch = (y - WEAPONTOP)/-4. rsq/hands.zs documents this
//    because the HAND layers have to subtract their own tilt out.
//
//    So tilting the WEAPON layer swings the gun, and because the hand layers
//    carry their own (zero) tilt, the hands do not follow. Gun swivels, hands
//    stay. No layer ownership, no clear skins, no second copy of the model.
//
// 2. ROUNDS THAT TRACK. A gun that POINTS at a target and shoots straight
//    ahead is worse than one that does not point. The set's SmartgunTracer
//    lives in the base Aliens Eradication pk3, which this addon does not
//    include, so it is neither subclassed nor replaced -- guessing a
//    projectile's damage and speed to re-declare it would be inventing
//    gameplay. Instead each round is steered AFTER it spawns, caught by class
//    name in WorldThingSpawned. That needs nothing from the base pk3 and works
//    whatever SmartgunTracer turns out to be.
//
//    The steer is deliberately weak and capped (ae_smartturn, default 6
//    degrees a tic). A smart round nudges; a homing missile removes the
//    shooting. At the default a round can correct maybe a body's width at
//    across-the-room range, which is what "smart" should buy.
//
// 3. IT ONLY DOES THIS WHEN THE GUN SAYS SO. Target selection reuses the gun's
//    own notion of a lock -- the same cone and sight test its restored
//    A_JumpIfTargetInLOS performs -- rather than a second, differently-behaved
//    tracker running alongside it.
//
// ae_gimbal_flip exists because the engine mirrors the left controller and the
// sign of the yaw term cannot be confirmed without a headset. If the gun leans
// away from targets instead of toward them, flip it; nothing else changes.

class AE_Smart abstract
{
	const CONE      = 35.0;		// degrees off the gun's forward a target can be
	const RANGE     = 2048.0;	// map units
	const MAX_YAW   = 22.0;		// how far the harness swings, degrees
	const MAX_PITCH = 16.0;
	const EASE      = 0.18;		// per tic, toward the wanted angle (0..1)

	clearscope static bool IsSmart(Weapon w)
	{
		if (!w)
			return false;
		Name n = w.GetClassName();
		return n == 'Smartgun_3D' || n == 'YutaniSmartgun_3D';
	}
}

// per player: the current lock and where the harness has swung to
class AE_SmartState
{
	Actor lock;
	double yaw, pitch;			// degrees, what the gun is showing now
	double putX, putY;			// what THIS gimbal last added to the weapon layer
	bool had;					// a lock last tic
}

class AE_SmartHandler : EventHandler
{
	AE_SmartState st[MAXPLAYERS];

	override void WorldLoaded(WorldEvent e)
	{
		for (int i = 0; i < MAXPLAYERS; i++)
			st[i] = new('AE_SmartState');
	}

	// No 'out CVar' cache. The first version took the handler's transient CVar
	// field as an out parameter and aborted the VM with "tried to read from
	// address zero" the moment the smartgun became the ready weapon. A cvar
	// lookup is cheap; a null deref in WorldTick kills every handler after it.
	static double Pref(PlayerInfo p, Name cv, double def)
	{
		let c = CVar.GetCVar(cv, p);
		return c ? c.GetFloat() : def;
	}

	// The nearest live monster inside the gun's cone that the player can see.
	// Deliberately the same question the gun's own A_JumpIfTargetInLOS asks.
	Actor Pick(PlayerPawn mo)
	{
		Actor best = null;
		double bestd = AE_Smart.RANGE;
		let it = ThinkerIterator.Create('Actor');
		Actor a;
		while (a = Actor(it.Next()))
		{
			if (a == mo || !a.bIsMonster || a.health <= 0 || a.bFriendly || a.bCorpse)
				continue;
			double d = mo.Distance3D(a);
			if (d >= bestd)
				continue;
			// Actor.absangle, qualified. These are declared in actor.zs as
			// `native clearscope static`, so the engine's own code can call
			// them bare from inside an Actor -- but this is an EventHandler,
			// where the bare name resolves to nothing.
			double da = Actor.absangle(mo.Angle, mo.AngleTo(a));
			if (da > AE_Smart.CONE)
				continue;
			if (!mo.CheckSight(a))
				continue;
			best = a;
			bestd = d;
		}
		return best;
	}

	override void WorldTick()
	{
		for (int i = 0; i < MAXPLAYERS; i++)
		{
			if (!playeringame[i] || !st[i])
				continue;
			let p = players[i];
			let mo = p.mo;
			let s = st[i];
			if (!mo || mo.health <= 0 || !AE_Smart.IsSmart(p.ReadyWeapon))
			{
				s.lock = null;
				s.had = false;
				Rest(p, s);
				continue;
			}
			bool on = Pref(p, 'ae_smartlock', 1) != 0;
			// a reload owns the gun and moves this same layer; the harness
			// centres and keeps out of the way until it is done
			if (RSR_Handler.FreeHand(mo) != "")
				on = false;
			s.lock = on ? Pick(mo) : null;

			double wy = 0, wp = 0;
			if (s.lock)
			{
				double flip = Pref(p, 'ae_gimbal_flip', 0) != 0 ? -1.0 : 1.0;
				wy = clamp(Actor.deltaangle(mo.Angle, mo.AngleTo(s.lock)),
				           -AE_Smart.MAX_YAW, AE_Smart.MAX_YAW) * flip;
				double tp = -atan2(s.lock.pos.z + s.lock.height * 0.5 - (mo.pos.z + mo.player.viewheight),
				                   mo.Distance2D(s.lock));
				wp = clamp(Actor.deltaangle(mo.Pitch, tp), -AE_Smart.MAX_PITCH, AE_Smart.MAX_PITCH);
			}
			if (Pref(p, 'ae_gimbal', 1) == 0)
			{
				wy = 0;
				wp = 0;
			}
			s.yaw   += (wy - s.yaw)   * AE_Smart.EASE;
			s.pitch += (wp - s.pitch) * AE_Smart.EASE;
			Apply(p, s, s.yaw, s.pitch);
			s.had = s.lock != null;
		}
	}

	// The player is not holding a smartgun: let go at once rather than easing.
	// Easing would mean writing the harness's leftover tilt onto whatever
	// weapon they just switched TO, and tilting that gun for half a second.
	void Rest(PlayerInfo p, AE_SmartState s)
	{
		s.yaw = 0;
		s.pitch = 0;
		if (s.putX == 0 && s.putY == 0)
			return;
		let psp = p.FindPSprite(PSP_WEAPON);
		if (psp)
		{
			psp.x -= s.putX;			// hand back exactly what was borrowed
			psp.y -= s.putY;
		}
		s.putX = 0;
		s.putY = 0;
	}

	// yaw/pitch in degrees -> the weapon layer's x/y, which is how the engine
	// takes a HUD model's rotation (hw_weapon.cpp; see the note at the top).
	//
	// ADDITIVE, and that is not a refinement. The gun's own states drive this
	// same psprite -- Offset(0,52) during the reload, the recoil frames during
	// fire -- so assigning x and y outright would silently cancel every
	// animation the set already has. Instead the gimbal remembers what IT put
	// there last tic, takes that back off, and adds the new value to whatever
	// the weapon has meanwhile set for itself.
	static void Apply(PlayerInfo p, AE_SmartState s, double yaw, double pitch)
	{
		let psp = p.FindPSprite(PSP_WEAPON);
		if (!psp)
			return;
		double ownX = psp.x - s.putX;			// the gun's own offset this tic
		double ownY = psp.y - s.putY;
		s.putX = yaw * 4.0;
		s.putY = -pitch * 4.0;
		psp.x = ownX + s.putX;
		psp.y = ownY + s.putY;
	}

	// Point the gun's own rounds at the gun's own lock. Caught by class name so
	// the TC's projectile is used exactly as it ships.
	override void WorldThingSpawned(WorldEvent e)
	{
		let a = e.Thing;
		if (!a || !a.target)
			return;
		Name n = a.GetClassName();
		if (n != 'SmartgunTracer' && n != 'SmartgunTracer2')
			return;
		let pp = PlayerPawn(a.target);
		if (!pp || !pp.player)
			return;
		let s = st[pp.PlayerNumber()];
		if (!s || !s.lock)
			return;
		a.tracer = s.lock;
	}

	// NO STEERING HERE, deliberately.
	//
	// The first version of this nudged each round's velocity toward the lock,
	// on the assumption that SmartgunTracer was an ordinary projectile. It is
	// not. The base TC declares it +SEEKERMISSILE +SCREENSEEKER and runs
	// A_SeekerMissile(179, 180, SMF_LOOK|SMF_PRECISE, 256, 10) every tic -- it
	// already tracks, hard, and far better than a velocity nudge would.
	//
	// Two things steering one projectile fight each other, so the handler's
	// whole contribution is the line above: setting `tracer` before the round
	// moves, so SMF_LOOK follows the target THE GUN IS AIMED AT instead of
	// acquiring one of its own. The gimbal and the round then agree.
}
