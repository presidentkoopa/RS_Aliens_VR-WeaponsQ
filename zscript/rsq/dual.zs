// Dual wield for the Aliens guns: two of the same gun, one in each hand.
//
// Modelled on rs_brutal22weaponsq's RSQ_Dual, because that design already
// ships and works, rather than on anything invented here:
//
//   * each dual-able gun has an off-hand COPY (DECORATE.aedual, generated):
//     the gun itself, with its OWN magazine, living in the off hand only;
//   * the reserve is SHARED with the main-hand gun;
//   * firing is per hand -- the copy carries +WEAPON.OFFHANDWEAPON, so the
//     engine puts it on the off controller and BT_OFFHANDATTACK fires it;
//   * you get the copy by picking up a SECOND one of the gun, or from the
//     start if the start option says so;
//   * the Dual key toggles the off hand between the copy and the free hand,
//     so a real VR reload of the main gun is always one press away.
//
// That last point is why the hands-on magazine reload does not need to work
// while dual, and does not: vreload.zs tests `OffhandWeapon is 'RSQ_Hands'`,
// which fails with a gun there. With both hands full there is no hand to pull
// a magazine with. Flick down reloads the gun in that hand instead.

class AE_DualHandler : EventHandler
{
	const MAXGUNS = 16;
	bool had[MAXPLAYERS][MAXGUNS];		// owned it last tic, so a pickup now is a second
	bool started[MAXPLAYERS];
	transient CVar cvStart;

	static int GunIndex(Weapon w)
	{
		if (!w)
			return -1;
		Name n = w.GetClassName();
		for (int i = 0; i < AE_DualTable.COUNT; i++)
			if (n == AE_DualTable.Gun(i))
				return i;
		return -1;
	}

	static bool Enabled(PlayerInfo p, int i)
	{
		if (i < 0)
			return false;
		let c = CVar.GetCVar(AE_DualTable.CVarName(i), p);
		return c && c.GetBool();
	}

	static bool HasCopy(PlayerPawn mo, int i)
	{
		Class<Inventory> cc = AE_DualTable.Copy(i);
		return cc && mo.FindInventory(cc);
	}

	// Give the off-hand copy without letting it steal the main hand: it is
	// +WEAPON.CHEATNOTWEAPON and SelectionOrder 99999, but a GiveInventory can
	// still set PendingWeapon, so that is put back.
	static void GiveCopy(PlayerPawn mo, int i)
	{
		Class<Inventory> cc = AE_DualTable.Copy(i);
		if (!cc || mo.FindInventory(cc))
			return;
		let p = mo.player;
		let pend = p.PendingWeapon;
		mo.GiveInventory(cc, 1);
		if (p.PendingWeapon != pend)
			p.PendingWeapon = pend;
	}

	override void WorldTick()
	{
		for (int n = 0; n < MAXPLAYERS; n++)
		{
			if (!playeringame[n])
				continue;
			let p = players[n];
			let mo = p.mo;
			if (!mo || mo.health <= 0)
				continue;

			if (!started[n])
			{
				started[n] = true;
				StartDual(mo, n);
			}

			// picking up a SECOND of a gun you already had hands you the copy
			for (int i = 0; i < AE_DualTable.COUNT && i < MAXGUNS; i++)
			{
				Class<Inventory> gc = AE_DualTable.Gun(i);
				bool own = gc && mo.FindInventory(gc);
				if (own && had[n][i] && Enabled(p, i))
					GiveCopy(mo, i);
				had[n][i] = own;
			}

			// the off hand follows the gun in the main hand
			int gi = GunIndex(p.ReadyWeapon);
			bool want = gi >= 0 && Enabled(p, gi) && HasCopy(mo, gi) && Wants(p);
			let cur = p.OffhandWeapon;

			if (!want)
			{
				if (cur && !(cur is 'RSQ_Hands') && p.PendingWeapon == WP_NOCHANGE)
					p.PendingWeapon = Weapon(mo.FindInventory('RSQ_Hands'));	// PATCHED BY HAND 2026-10-22: via PendingWeapon (see hands.zs Default)
				continue;
			}
			Class<Weapon> cc = AE_DualTable.Copy(gi);
			if (!cc)
				continue;
			if (cur && cur.GetClass() == cc)
				continue;
			let off = Weapon(mo.FindInventory(cc));
			if (off && p.PendingWeapon == WP_NOCHANGE)
				p.PendingWeapon = off;	// PATCHED BY HAND 2026-10-22: via PendingWeapon so its psprite exists
		}
	}

	// The Dual key's latch (netevent "ae_dual").
	//
	// FIXED 2026-10-23: this used to default ON, so simply owning a gun whose ae_dual_* switch
	// was set put you in dual wield permanently -- and the loop above hands out the copy on the
	// SECOND TIC of owning one gun (had[] starts false, so tic 1 sets it and tic 2 grants),
	// despite its comment saying "picking up a SECOND of a gun". Two consequences the owner hit:
	// he was dual wielding without ever asking for it, and while dual the main hand is drawn on
	// a layer placed by a STATIC MODELDEF Offset (hw_weapon.cpp nulls ModifyBobLayer3D for every
	// layer that is not the off-hand weapon's own), so the hand-position sliders could not reach
	// it and appeared to do nothing at all.
	//
	// So the latch now starts OFF and the Dual key turns it on, which is what having a Dual key
	// is for. One gun in hand is the normal case again, and the sliders work there.
	bool want[MAXPLAYERS];
	static bool Wants(PlayerInfo p)
	{
		let h = AE_DualHandler(EventHandler.Find('AE_DualHandler'));
		return h && h.want[p.mo ? p.mo.PlayerNumber() : 0];
	}

	override void NetworkProcess(ConsoleEvent e)
	{
		if (e.Name != "ae_dual" || e.Player < 0 || e.Player >= MAXPLAYERS)
			return;
		want[e.Player] = !want[e.Player];
	}

	// "Start with dual pistols": the copy from the first tic, no second pickup
	void StartDual(PlayerPawn mo, int n)
	{
		if (!cvStart)
			cvStart = CVar.GetCVar('ae_start_dual', mo.player);
		if (!cvStart || cvStart.GetInt() == 0)
			return;
		for (int i = 0; i < AE_DualTable.COUNT; i++)
		{
			Name g = AE_DualTable.Gun(i);
			if (g != 'M4A3Pistol_3D')
				continue;
			Class<Inventory> gc = g;
			if (gc && mo.FindInventory(gc))
				GiveCopy(mo, i);
		}
	}
}
