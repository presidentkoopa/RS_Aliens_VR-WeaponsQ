// Flick down to reload.
//
// A sharp downward jerk of the gun hand starts the reload, the way you snap a
// magazine out. BD22 has this for its dual wield; here it works on every gun,
// because the thing it replaces -- taking a hand off the gun to find a button
// -- is the same problem whether you hold one weapon or two.
//
// It is a VELOCITY test, not a position test, and that distinction is the
// whole design. Any "the hand went below here" rule fires while you are
// walking with your arms down, reloading the gun every few seconds for no
// reason. A flick is a fast movement that then STOPS, so this wants three
// things at once: downward speed over the threshold, mostly-downward
// direction, and the hand having been still shortly before. Walking fails the
// third, a reach for a holster fails the second, and sweeping the gun across
// a room fails both.

class AE_Flick abstract
{
	const SPEED  = 110.0;		// cm/s downward: the threshold for a flick
	const DOWN   =  0.78;		// how much of that speed must be straight down
	const CALM   =  35.0;		// cm/s: "the hand was still" before it
	const QUIET  =  6;			// tics of calm wanted before a flick counts
	const LOCKED = 25;			// tics after one before another can fire
}

class AE_FlickHandler : EventHandler
{
	Vector3 last[MAXPLAYERS];
	bool have[MAXPLAYERS];
	int calm[MAXPLAYERS], lock[MAXPLAYERS];
	transient CVar cvOn;

	override void WorldTick()
	{
		if (!cvOn)
			cvOn = CVar.GetCVar('ae_flick_reload');
		bool on = !cvOn || cvOn.GetBool();

		for (int i = 0; i < MAXPLAYERS; i++)
		{
			if (!playeringame[i])
			{
				have[i] = false;
				continue;
			}
			let p = players[i];
			let mo = p.mo;
			if (!on || !mo || mo.health <= 0 || !RSVR_VRHand.InVR(mo))
			{
				have[i] = false;
				calm[i] = 0;
				continue;
			}
			if (lock[i] > 0)
				lock[i]--;

			double vu = 34.0;
			let cv = CVar.GetCVar('vr_vunits_per_meter', p);
			if (cv && cv.GetFloat() > 0)
				vu = cv.GetFloat();
			Vector3 now = RSVR_VRHand.HandPos(mo);
			if (!have[i])
			{
				last[i] = now;
				have[i] = true;
				continue;
			}
			Vector3 d = now - last[i];
			last[i] = now;
			d *= 100.0 / vu;				// map units -> cm
			double speed = d.Length() * TICRATE;
			if (speed < AE_Flick.CALM)
				calm[i]++;
			else if (speed < AE_Flick.SPEED)
				calm[i] = 0;

			if (speed < AE_Flick.SPEED || calm[i] < AE_Flick.QUIET || lock[i] > 0)
				continue;
			// mostly downward?
			double down = -d.z * TICRATE;
			if (down < speed * AE_Flick.DOWN)
				continue;

			calm[i] = 0;
			lock[i] = AE_Flick.LOCKED;
			Reload(p);
		}
	}

	// Enter the weapon's own Reload. This is what the reload key does, so the
	// flick reaches the real VR reload (or the set's canned one when that is
	// switched off) without knowing anything about either.
	static void Reload(PlayerInfo p)
	{
		let w = p.ReadyWeapon;
		if (!w || !p.mo)
			return;
		if (RSR_Handler.FreeHand(p.mo) != "")		// already reloading
			return;
		State s = w.FindState('Reload');
		if (s)
			p.SetPsprite(PSP_WEAPON, s);
	}
}
