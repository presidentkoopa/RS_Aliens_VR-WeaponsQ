// Body holsters: reach to where a weapon hangs and take it.
//
// AE sets exactly seven weapon slots, so every one can have a place on the
// body that you reach for directly -- no radial menu, no scroll wheel, and no
// two close enough to grab by mistake. Most mods carry too many guns for this
// to work; this set does not.
//
// Each holster shows the gun's OWN pickup model (the set ships them for floor
// spawns), because reaching for an invisible hip is what makes holstering feel
// bad. The placement table and the ghost classes are generated --
// tool/hands/ae_holster_gen.py -- so the offsets live in one place.
//
// WHAT IT DOES NOT DO: there is no empty-handed state in Doom, so "holstering"
// is always a swap. Taking the pistol puts whatever you were holding back on
// your body. That is the honest model of the engine rather than a limitation
// worked around with a fake empty weapon.

class AE_Holster abstract
{
	const REACH = 18.0;			// cm: the off hand within this of a holster is on it
	const LEAVE = 26.0;			// and off it past this (hysteresis: one reach, one draw)
}

class AE_HolsterHandler : EventHandler
{
	Array<Actor> ghost;			// Count() per player, flattened
	bool onHolster[MAXPLAYERS];
	transient CVar cvOn, cvShow;

	override void WorldLoaded(WorldEvent e)
	{
		ghost.Clear();
		int n = AE_Holsters.Count();
		for (int i = 0; i < MAXPLAYERS * n; i++)
			ghost.Push(null);
	}

	override void WorldTick()
	{
		if (!cvOn)
			cvOn = CVar.GetCVar('ae_holsters');
		bool on = !cvOn || cvOn.GetBool();
		int n = AE_Holsters.Count();

		for (int p = 0; p < MAXPLAYERS; p++)
		{
			if (!playeringame[p])
				continue;
			let pl = players[p];
			let mo = pl.mo;
			if (!mo || mo.health <= 0)
			{
				Hide(p, n);
				continue;
			}
			if (!on || !RSVR_VRHand.InVR(mo))
			{
				Hide(p, n);
				onHolster[p] = false;
				continue;
			}
			// a reload owns the off hand; drawing must not steal it
			bool busy = RSR_Handler.FreeHand(mo) != "";

			Vector3 off = OffInBody(mo);
			int near = -1;
			double nd = AE_Holster.REACH;

			for (int i = 0; i < n; i++)
			{
				let w = AE_Holsters.Held(mo, i);
				bool show = w != null && w != pl.ReadyWeapon;
				Place(p, i, mo, show);
				if (!show || busy)
					continue;
				Vector3 h = (AE_Holsters.PosF(i), AE_Holsters.PosL(i), AE_Holsters.PosU(i));
				double d = (off - h).Length();
				if (d < nd)
				{
					nd = d;
					near = i;
				}
			}

			if (near >= 0 && !onHolster[p])
			{
				onHolster[p] = true;
				let w = AE_Holsters.Held(mo, near);
				if (w && w != pl.ReadyWeapon)
					pl.PendingWeapon = w;
			}
			else if (near < 0 && onHolster[p] && !NearAny(mo, off, n, AE_Holster.LEAVE))
			{
				onHolster[p] = false;
			}
		}
	}

	bool NearAny(PlayerPawn mo, Vector3 off, int n, double r)
	{
		for (int i = 0; i < n; i++)
		{
			Vector3 h = (AE_Holsters.PosF(i), AE_Holsters.PosL(i), AE_Holsters.PosU(i));
			if ((off - h).Length() <= r)
				return true;
		}
		return false;
	}

	// The off hand in the player's YAW frame, centimetres F / L / U from the
	// view. Yaw only: a holster that followed head pitch would swing away at
	// the exact moment you looked down to find it.
	static Vector3 OffInBody(PlayerPawn mo)
	{
		double ps = mo.Level.pixelstretch;
		if (ps <= 0)
			ps = 1.2;
		double vu = 34.0;
		let cv = CVar.GetCVar('vr_vunits_per_meter', mo.player);
		if (cv && cv.GetFloat() > 0)
			vu = cv.GetFloat();
		Vector3 w = RSVR_VRHand.OffPos(mo) - (mo.pos + (0, 0, mo.player.viewheight));
		w.z *= ps;
		w *= 100.0 / vu;
		double a = mo.Angle;
		Vector3 F = (cos(a), sin(a), 0);
		Vector3 L = (-sin(a), cos(a), 0);
		return (w dot F, w dot L, w.z);
	}

	// keep a holster's ghost where the body says, or hide it
	void Place(int p, int i, PlayerPawn mo, bool show)
	{
		int k = p * AE_Holsters.Count() + i;
		if (k >= ghost.Size())
			return;
		let g = ghost[k];
		if (!show)
		{
			if (g)
			{
				g.Destroy();
				ghost[k] = null;
			}
			return;
		}
		if (!g)
		{
			// a Name does not convert to Class<Actor> on its own
			Class<Actor> gc = AE_Holsters.Ghost(i);
			if (!gc)
				return;
			g = Actor.Spawn(gc, mo.pos);
			ghost[k] = g;
			if (!g)
				return;
		}
		double vu = 34.0;
		let cv = CVar.GetCVar('vr_vunits_per_meter', mo.player);
		if (cv && cv.GetFloat() > 0)
			vu = cv.GetFloat();
		double ps = mo.Level.pixelstretch;
		if (ps <= 0)
			ps = 1.2;
		double a = mo.Angle;
		Vector3 F = (cos(a), sin(a), 0);
		Vector3 L = (-sin(a), cos(a), 0);
		Vector3 c = (AE_Holsters.PosF(i), AE_Holsters.PosL(i), AE_Holsters.PosU(i));
		Vector3 w = F * c.x + L * c.y;
		w.z = c.z / ps;
		w *= vu / 100.0;
		g.SetOrigin(mo.pos + (0, 0, mo.player.viewheight) + w, true);
		g.Angle = a;
		g.Roll = AE_Holsters.Roll(i);
	}

	void Hide(int p, int n)
	{
		for (int i = 0; i < n; i++)
		{
			int k = p * n + i;
			if (k < ghost.Size() && ghost[k])
			{
				ghost[k].Destroy();
				ghost[k] = null;
			}
		}
	}
}
