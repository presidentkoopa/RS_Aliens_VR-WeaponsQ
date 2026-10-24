// TEST ONLY: picks the gun under test and empties it, so a run can step through every gun
// without a headset or a keyboard.
//
// The kit's own driver.zs does this with a v9t_* cvar block written for BD22's class names and
// its ten-gun table. This is the same idea against this set's names, and small enough to read
// in one go. It is NOT in the shipped pk3: tools/ is in mkpk3.py's SKIP_DIRS.
class AET_Driver : EventHandler
{
	String was;
	int settle;

	static String S(Name n)
	{
		let c = CVar.FindCVar(n);
		return c ? c.GetString() : "";
	}

	static double F(Name n, double def)
	{
		let c = CVar.FindCVar(n);
		return c ? c.GetFloat() : def;
	}

	override void WorldTick()
	{
		if (!playeringame[0] || !players[0].mo)
			return;
		let mo = PlayerPawn(players[0].mo);
		if (!mo || !mo.player)
			return;

		String want = S('aet_gun');
		if (want == "" || want == was)
			return;

		Class<Weapon> wc = (Class<Weapon>)((Name)(want));
		if (!wc)
		{
			Console.Printf("AET want=%s UNKNOWN CLASS", want);
			was = want;
			return;
		}

		mo.GiveInventory(wc, 1);
		let w = Weapon(mo.FindInventory(wc));
		if (!w)
		{
			Console.Printf("AET want=%s GIVE FAILED -- TryPickup refused it", want);
			was = want;
			return;
		}
		mo.player.PendingWeapon = w;

		// empty the magazine the gun itself names, which is the same thing the slide-lock path
		// reads -- so "empty" here means exactly what the gun means by it
		if (F('aet_empty', 0) > 0 && w.AmmoType1)
		{
			let a = mo.FindInventory(w.AmmoType1);
			if (a)
				a.Amount = 0;
		}
		// and top up the reserve, or there is nothing to reload FROM
		if (w.AmmoType2)
		{
			let r = mo.FindInventory(w.AmmoType2);
			if (!r)
				mo.GiveInventory(w.AmmoType2, 1);
			r = mo.FindInventory(w.AmmoType2);
			if (r)
				r.Amount = r.MaxAmount;
		}

		Console.Printf("AET gun=%s mag=%s(%d) reserve=%s(%d)", want,
			w.AmmoType1 ? w.AmmoType1.GetClassName() : 'none',
			w.AmmoType1 && mo.FindInventory(w.AmmoType1) ? mo.FindInventory(w.AmmoType1).Amount : -1,
			w.AmmoType2 ? w.AmmoType2.GetClassName() : 'none',
			w.AmmoType2 && mo.FindInventory(w.AmmoType2) ? mo.FindInventory(w.AmmoType2).Amount : -1);
		was = want;
	}
}
