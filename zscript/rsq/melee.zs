// 2026-10-22 VR MELEE BY MOTION (owner: "we can perform the stab motion"). With a knife in the
// main hand, a fast stab with the controller lands the knife's own blow (A_CustomPunch's damage
// and EnhancedKnifePuff, from actors/weapons/knife.txt) where the hand is going; a fast punch
// with the free off hand lands a fist. The weapon's own trigger swing is untouched. The blow is
// a short-lived, fast, invisible projectile spawned AT THE HAND, flying along the hand's
// direction (BD22 1.92 OffPunch does the same with MeleeStrikeNormal), so it hits what the
// hand is thrust at and not what the player faces.
//   ae_stab (OnOff), ae_stab_speed (m/s the hand must move: default 2.0), ae_stab_reach (cm).
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
			// the knife: a thrust along the blade (the hand moving the way it points)
			if (sh >= need && handCool[n] == 0)
			{
				Vector3 dir = RSVR_VRHand.HandDir(mo, 0, 0, ps);
				Vector3 mv = dh / max(dh.Length(), 0.001);
				if (mv dot dir > 0.3)
				{
					Strike(mo, h, dir, reach * vu / 100.0, 2 * random(1, 10), 'EnhancedKnifePuff', "ALIECLW1");
					handCool[n] = 12;
				}
			}
			// the free fist: any fast punch, if nothing has the off hand
			if (so >= need && offCool[n] == 0 && p.OffhandWeapon is 'RSQ_Hands' && RSQ_MeleeHandler.OffFree(mo))
			{
				Vector3 mv = dq / max(dq.Length(), 0.001);
				Strike(mo, o, mv, reach * vu / 100.0, random(2, 8), 'EnhancedKnifePuff', "ALIECLW1");
				offCool[n] = 12;
			}
		}
	}

	static bool OffFree(PlayerPawn mo)
	{
		let rs = RSR_Handler.StateOf(mo);
		return !rs || rs.phase == RSR.IDLE;
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
