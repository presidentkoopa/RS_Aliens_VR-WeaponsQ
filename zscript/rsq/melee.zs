// 2026-10-22 VR MELEE BY MOTION (owner: "we can perform the stab motion"). With a knife in the
// main hand, a fast stab with the controller lands the knife's own blow (A_CustomPunch's damage
// and EnhancedKnifePuff, from actors/weapons/knife.txt) where the hand is going; a fast punch
// with the free off hand lands a fist. The weapon's own trigger swing is untouched.
//   ae_stab (OnOff), ae_stab_speed (m/s the hand must move: default 2.0), ae_stab_reach (cm).
//
// 2026-10-23 SWEPT BLADE (parity step 8, from BD22 1.92's zscript/rsvr/melee.zs). This used to
// spawn a short-lived invisible projectile at the hand and let it fly. Two faults came with that:
//
//   * A FAST STAB COULD MISS A BODY ENTIRELY. The hand moves between tics, and the projectile
//     only ever started from where the hand was at the tic boundary, so a thrust quicker than
//     the tic rate stepped straight over a monster. docs/RELOAD_ON_QUEST.md records the same
//     class of bug on the break-open guns: "Faster than ~1.5 m/s and the crossing fell between
//     tics and was never seen."
//   * ONE SWING COULD ONLY EVER HIT ONE THING -- the projectile destroyed itself on contact.
//
// The blade is now SWEPT: the segment from last tic's blade to this tic's is tested against
// everything in the box it passes through, so what the blade crossed is what gets hit. A hit
// list per swing means a single swing can open up two bodies but neither one twice, and the
// hand buzzes when it connects.
//
// The reach is the knife's OWN LENGTH, measured, not a round number: models/weapons/knife/
// knife.md3 is one surface 518 verts, 53.508 md3 units end to end along its principal axis
// (0.3001, 0.0000, 0.9539), x Scale 0.65 x 1.02 = 35.48 cm. It was 70.0 -- twice the knife --
// so the blow landed on things the blade was nowhere near. ae_stab_reach stays as a taste
// slider on top (memory rule: sliders are for taste, never for a value we failed to measure).
class RSQ_Strike : Actor
{
	int dmg;
	Name puff;
	Default
	{
		Projectile;
		Radius 6;
		Height 8;
		Speed 0;
		Damage 0;
		+NOGRAVITY +HITTRACER +BLOODSPLATTER +THRUSPECIES +NOEXTREMEDEATH
		RenderStyle "None";
		DamageType "Melee";
	}
	// the blow lands here, not through the missile's own Damage (0): the victim takes dmg as a
	// melee hit from the player, the knife's puff plays its body hit, and the strike is spent
	override int SpecialMissileHit(Actor victim)
	{
		if (!victim || victim == target)
			return 1;
		if (!victim.bSHOOTABLE)
			return -1;
		victim.DamageMobj(self, target, dmg, 'Melee', DMG_THRUSTLESS);
		class<Actor> pc = puff;
		if (pc)
		{
			let a = Spawn(pc, pos, ALLOW_REPLACE);
			if (a)
			{
				a.target = target;
				a.SetStateLabel("XDeath");
			}
		}
		Destroy();
		return 0;
	}
	States
	{
	Spawn:
		TNT1 A 1;
		TNT1 A 1;
		TNT1 A 1;
		Stop;
	Death:
		TNT1 A 0
		{
			class<Actor> pc = puff;
			if (pc)
			{
				let a = Spawn(pc, pos, ALLOW_REPLACE);
				if (a)
				{
					a.target = target;
					if (tracer && tracer.bSHOOTABLE)
						a.SetStateLabel("XDeath");	// the body hit, as a puff with PUFFONACTORS plays it
				}
			}
		}
		Stop;
	}
}

class RSQ_MeleeHandler : EventHandler
{
	Vector3 handPrev[MAXPLAYERS], offPrev[MAXPLAYERS];
	int handCool[MAXPLAYERS], offCool[MAXPLAYERS];
	// last tic's blade segment per hand, so this tic can sweep from it
	Vector3 tipPrev[MAXPLAYERS][2], rootPrev[MAXPLAYERS][2];
	bool hasPrev[MAXPLAYERS][2];
	Array<Actor> struck;		// the current swing's hit list: one swing never hits a body twice

	static bool KnifeHeld(PlayerInfo p)
	{
		let w = p.ReadyWeapon;
		return w && (w is 'Knife_3D' || w is 'YutaniKnife_3D');
	}

	override void WorldTick()
	{
		let cvOn = CVar.FindCVar('ae_stab');
		if (cvOn && !cvOn.GetBool())
			return;
		let cvSpd = CVar.FindCVar('ae_stab_speed');
		double need = cvSpd ? cvSpd.GetFloat() : 2.0;
		let cvReach = CVar.FindCVar('ae_stab_reach');
		double reach = cvReach ? cvReach.GetFloat() : 70.0;
		for (int n = 0; n < MAXPLAYERS; n++)
		{
			if (!playeringame[n])
				continue;
			let p = players[n];
			let mo = p.mo;
			if (!mo || p.playerstate != PST_LIVE || !RSVR_VRHand.InVR(mo))
				continue;
			double vu = 34.0;
			let cv = CVar.GetCVar('vr_vunits_per_meter', p);
			if (cv && cv.GetFloat() > 0)
				vu = cv.GetFloat();
			double ps = mo.Level.pixelstretch;
			if (ps <= 0)
				ps = 1.2;
			Vector3 h = RSVR_VRHand.HandPos(mo);
			Vector3 o = RSVR_VRHand.OffPos(mo);
			// hand speed in m/s: map units per tic (the z axis squashed by pixelstretch) * 35 / vu
			Vector3 dh = h - handPrev[n]; dh.z *= ps;
			Vector3 dq = o - offPrev[n]; dq.z *= ps;
			handPrev[n] = h;
			offPrev[n] = o;
			if (handCool[n] > 0) handCool[n]--;
			if (offCool[n] > 0) offCool[n]--;
			if (!KnifeHeld(p))
				continue;
			double sh = dh.Length() * 35.0 / vu;
			double so = dq.Length() * 35.0 / vu;
			double len = reach * vu / 100.0;		// cm -> map units

			// the knife: a thrust along the blade (the hand moving the way it points). The
			// blade is swept from where it was last tic to where it is now, so what it passed
			// through is what it hits.
			Vector3 kdir = RSVR_VRHand.HandDir(mo, 0, 0, ps);
			Vector3 tip = h + kdir * len;
			bool swinging = sh >= need;
			if (swinging && handCool[n] == 0)
			{
				Vector3 mv = dh / max(dh.Length(), 0.001);
				if (mv dot kdir > 0.3)
				{
					if (!hasPrev[n][0])
					{
						rootPrev[n][0] = h;
						tipPrev[n][0] = tip;
					}
					Sweep(mo, rootPrev[n][0], tipPrev[n][0], h, tip,
						2 * random(1, 10), 'EnhancedKnifePuff', "ALIECLW1");
				}
			}
			// the swing is over: let the next one hit these bodies again
			if (!swinging && struck.Size() > 0)
				struck.Clear();
			rootPrev[n][0] = h;
			tipPrev[n][0] = tip;
			hasPrev[n][0] = true;

			// the free fist: any fast punch, if nothing has the off hand. A fist has no blade,
			// so its "segment" is the hand itself swept along its own travel.
			if (so >= need && offCool[n] == 0 && p.OffhandWeapon is 'RSQ_Hands' && RSQ_MeleeHandler.OffFree(mo))
			{
				Vector3 mv = dq / max(dq.Length(), 0.001);
				Vector3 ofrom = hasPrev[n][1] ? rootPrev[n][1] : o;
				Sweep(mo, ofrom, ofrom + mv * (len * 0.35), o, o + mv * (len * 0.35),
					random(2, 8), 'EnhancedKnifePuff', "ALIECLW1");
				offCool[n] = 12;
			}
			rootPrev[n][1] = o;
			hasPrev[n][1] = true;
		}
	}

	static bool OffFree(PlayerPawn mo)
	{
		let rs = RSR_Handler.StateOf(mo);
		return !rs || rs.phase == RSR.IDLE;
	}

	// is q inside t's cylinder, with a little slack?  (1.92 Touches)
	static bool Touches(Actor t, Vector3 q, double pad)
	{
		if (q.z < t.pos.z - pad || q.z > t.pos.z + t.height + pad)
			return false;
		double ddx = q.x - t.pos.x;
		double ddy = q.y - t.pos.y;
		double rr = t.radius + pad;
		return ddx * ddx + ddy * ddy <= rr * rr;
	}

	// nothing solid between the hand and the point the blade reached (1.92 Clear): without this
	// a swing cuts through a wall into whatever is standing on the other side of it
	static bool Clear(Actor mo, Vector3 from, Vector3 to)
	{
		Vector3 d = to - from;
		double len = d.Length();
		if (len <= 0.001)
			return true;
		FLineTraceData t;
		mo.LineTrace(VectorAngle(d.x, d.y), len, -asin(clamp(d.z / len, -1, 1)),
			TRF_ABSPOSITION | TRF_THRUACTORS, from.z, from.x, from.y, t);
		return t.HitType == TRACE_HitNone;
	}

	// SWEEP the quad between last tic's blade (a0..b0) and this tic's (a1..b1), hitting
	// everything the blade actually passed through. Ported from 1.92's Sweep, with its step
	// counts: the blade is walked in <=16 steps of travel and 8 segments along its length,
	// which is what stops a fast thrust from stepping over a body between tics.
	void Sweep(PlayerPawn mo, Vector3 a0, Vector3 b0, Vector3 a1, Vector3 b1, int dmg, Name puff, Sound snd)
	{
		double pad = 5;
		Vector3 c = (a0 + b0 + a1 + b1) / 4;
		double r = max(max((a0 - c).Length(), (b0 - c).Length()),
		               max((a1 - c).Length(), (b1 - c).Length())) + pad;
		double travel = max((b1 - b0).Length(), (a1 - a0).Length());
		int steps = clamp(int(travel / 4) + 1, 1, 16);
		int segs = 8;
		bool any = false;
		let it = BlockThingsIterator.CreateFromPos(c.x, c.y, c.z - r, 2 * r, r, false);
		while (it.Next())
		{
			Actor t = it.thing;
			if (!t || t == mo || t.player || !t.bSHOOTABLE || t.bDORMANT || t.health <= 0)
				continue;
			if (struck.Find(t) != struck.Size())
				continue;
			bool hit = false;
			Vector3 at = (0, 0, 0);
			for (int i = 1; i <= steps && !hit; i++)
			{
				double f = double(i) / steps;
				for (int j = segs; j >= 0 && !hit; j--)
				{
					double sv = double(j) / segs;
					Vector3 p0 = a0 + (b0 - a0) * sv;
					Vector3 p1 = a1 + (b1 - a1) * sv;
					Vector3 q = p0 + (p1 - p0) * f;
					if (Touches(t, q, pad))
					{
						hit = true;
						at = q;
					}
				}
			}
			if (!hit || !Clear(mo, a1, at))
				continue;
			struck.Push(t);
			t.DamageMobj(mo, mo, dmg, 'Melee', DMG_THRUSTLESS);
			class<Actor> pc = puff;
			if (pc)
			{
				let a = Actor.Spawn(pc, at, ALLOW_REPLACE);
				if (a)
				{
					a.target = mo;
					a.SetStateLabel("XDeath");		// the body hit, as the puff plays it
				}
			}
			any = true;
		}
		mo.A_StartSound(snd, CHAN_AUTO, CHANF_OVERLAP);
		if (any)
			Buzz(mo);		// the hand feels it connect -- handoff QoL item 4
	}

	// a short haptic pulse in the main hand (RSVR_Buzz carries a DamageType so the engine's
	// per-hand haptics fire; see zscript/rsvr/common.zs)
	static void Buzz(PlayerPawn mo)
	{
		mo.SpawnPlayerMissile('RSVR_Buzz', mo.angle, noautoaim: true);
	}

	static void Strike(PlayerPawn mo, Vector3 from, Vector3 dir, double reach, int dmg, Name puff, Sound snd)
	{
		let s = RSQ_Strike(Actor.Spawn('RSQ_Strike', from, ALLOW_REPLACE));
		if (!s)
			return;
		s.target = mo;
		s.dmg = dmg;
		s.puff = puff;
		s.vel = dir * (reach / 3.0);	// three tics of flight = the reach
		s.angle = VectorAngle(dir.x, dir.y);
		s.pitch = -asin(clamp(dir.z, -1, 1));
		mo.A_StartSound(snd, CHAN_AUTO, CHANF_OVERLAP);
		if (RSR.Debug(mo.player))
			Console.Printf("ae melee t%d: strike from (%.0f %.0f %.0f) dir (%.2f %.2f %.2f) reach %.0f dmg %d", mo.Level.maptime, from.x, from.y, from.z, dir.x, dir.y, dir.z, reach, dmg);
	}
}
