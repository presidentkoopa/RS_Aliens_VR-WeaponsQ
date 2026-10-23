// Flick down to reload.
//
// A sharp downward snap of the gun's barrel starts that gun's reload, the way you snap a
// magazine out. BD22 1.92 has this for its dual wield; here it works on a single gun too,
// because the thing it replaces -- taking a hand off the gun to find a button -- is the same
// problem whether you hold one weapon or two.
//
// REWRITTEN 2026-10-23 against BD22 1.92's zscript/rsq/flick.zs, which the owner's own verdict
// says reloads smoothly. What was here before was a VELOCITY test on RSVR_VRHand.HandPos, and
// it had two faults that no amount of threshold tuning fixes:
//
//   * HandPos is a RAW WORLD POSITION. The test never subtracted mo.vel, so the player's own
//     movement counted as hand speed: stepping off a ledge or riding a lift moves the hand
//     downward at speed through no fault of the arm, and the gun reloaded by itself.
//   * d.z was not divided by pixelstretch, so the vertical component was overstated by about
//     1.2x in the "mostly downward" test -- biased toward firing.
//
// 1.92 reads the BARREL'S ELEVATION instead, and that is the whole point: an angle is
// translation-invariant, so walking, falling, turning and riding a lift cannot change it. No
// velocity, no calm window, no lockout needed -- the re-arm band does that job honestly.
//
//   fast    the barrel drops FLICK_DEG within FLICK_TICS;
//   down    it ends at least DOWN_DEG below level;
//   once    it re-arms only after coming back above REARM_DEG.
//
// The gun must also be in its ready loop, so a flick never cuts into firing, a pump cycle or a
// reload already running. That gate was missing here too: the old Reload() asked only whether
// the magazine reload was idle, which is true in the middle of a shot.

class AE_Flick abstract
{
	const FLICK_DEG = 45.0;		// degrees of drop...
	const FLICK_TICS = 4;		// ...within this many tics (about 400 degrees a second)
	const DOWN_DEG = -40.0;		// and it has to end this far below level
	const REARM_DEG = -15.0;	// come back above this before it can fire again
	const HIST = 8;
}

class AE_FlickHandler : EventHandler
{
	double el[MAXPLAYERS][2][AE_Flick.HIST];
	int head[MAXPLAYERS][2];
	int count[MAXPLAYERS][2];
	bool armed[MAXPLAYERS][2];
	transient CVar cvOn;

	// something held that can actually be reloaded. The hands themselves are not a gun, the
	// Power Loader is not a gun, and anything with no Reload state has nothing to start.
	static bool IsGun(Weapon w)
	{
		if (!w || w is 'RSQ_Hands')
			return false;
		// A downward jerk of the arm is the commonest gesture there is in a loader -- you do it
		// every time you swing or drop something -- and the loader has no magazine in any case
		// (RSR_Guns.Index(Loader_3D) is 0, so no VR reload ever runs for it).
		if (AE_LoaderHandler.IsLoader(w))
			return false;
		return w.FindState('Reload') != null;
	}

	override void WorldTick()
	{
		if (!cvOn)
			cvOn = CVar.GetCVar('ae_flick_reload');
		bool want = !cvOn || cvOn.GetBool();

		for (int n = 0; n < MAXPLAYERS; n++)
		{
			if (!playeringame[n] || !players[n].mo)
				continue;
			let mo = players[n].mo;
			let p = mo.player;
			bool on = want && RSVR_VRHand.InVR(mo) && p.playerstate == PST_LIVE && mo.health > 0;
			double ps = mo.Level.pixelstretch;
			if (ps <= 0)
				ps = 1.2;
			for (int h = 0; h < 2; h++)
			{
				Weapon w = h == 0 ? p.ReadyWeapon : p.OffhandWeapon;
				if (!on || !IsGun(w))
				{
					count[n][h] = 0;
					armed[n][h] = false;
					continue;
				}
				Vector3 d = h == 0 ? RSVR_VRHand.HandDir(mo, 0, 0, ps) : RSVR_VRHand.OffDir(mo, 0, 0, ps);
				double e = asin(clamp(d.z, -1, 1));
				head[n][h] = (head[n][h] + 1) % AE_Flick.HIST;
				el[n][h][head[n][h]] = e;
				if (count[n][h] < AE_Flick.HIST)
					count[n][h]++;
				if (e > AE_Flick.REARM_DEG)
					armed[n][h] = true;
				if (!armed[n][h] || count[n][h] <= AE_Flick.FLICK_TICS || e > AE_Flick.DOWN_DEG)
					continue;
				double before = el[n][h][(head[n][h] - AE_Flick.FLICK_TICS + AE_Flick.HIST) % AE_Flick.HIST];
				if (before - e < AE_Flick.FLICK_DEG)
					continue;
				armed[n][h] = false;
				Reload(p, h);
			}
		}
	}

	// Enter the weapon's own Reload. This is what the reload key does, so the flick reaches the
	// real VR reload (or the set's canned one when that is switched off) without knowing
	// anything about either.
	static void Reload(PlayerInfo p, int h)
	{
		Weapon w = h == 0 ? p.ReadyWeapon : p.OffhandWeapon;
		if (!w || !p.mo)
			return;
		// 1.92's gate, which this file did not have: the gun must be in its ready loop for THAT
		// hand. Without it a flick cuts into a shot, a pump stroke or a weapon raise.
		int ready = h == 0 ? WF_WEAPONREADY : WF_OFFHANDREADY;
		if (!(p.WeaponState & ready))
			return;
		if (RSR_Handler.FreeHand(p.mo) != "")		// a magazine reload already has the hand
			return;
		State s = w.FindState('Reload');
		if (s)
			p.SetPsprite(h == 0 ? PSP_WEAPON : PSP_OFFHANDWEAPON, s, false, w);
	}
}
