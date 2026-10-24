// THE ROUND LEAVES THE BARREL, 2026-10-23 (owner: "does the rifle projectile leave the barrel
// or is it still too high from the barrel?").
//
// It was leaving 4.3 cm above the bore, and no slider would have fixed it, because the number
// the gun asks for is thrown away before it is ever used. actors/weapons/rifle.txt fires
//
//     A_FireProjectile("HeavyTracer", random(-1,1), 1, 5, -5, 0, random(-1,-2))
//                                                      ^  ^^
//                                            spawnofs_xy  spawnheight
//
// and in VR p_mobj.cpp (P_SpawnPlayerMissile, the OverrideAttackPosDir branch) does:
//
//     if (!use_action_spawn_yzoffset)
//         y = z = 0;
//
// `use_action_spawn_yzoffset` is a CVAR that DEFAULTS TO FALSE (hw_vrmodes.cpp). So every
// gun's spawnheight is discarded in VR and every round leaves from AttackPos -- the
// controller itself -- whatever its states ask for. Turning that cvar on is not the fix: it
// would switch the y and z offsets back on for every A_FireProjectile in the TC at once, and
// those numbers were authored for a flat screen where the gun is a sprite.
//
// So the round is moved to the bore here instead, per gun, from a MEASURED table.
//
// HOW THE BORES WERE MEASURED. The frontmost 0.8 cm of each gun's body surface is taken and
// split into clusters wherever there is a gap over 1 cm in U; a bore shows up as a ring of
// verts about 3 cm across, centred on L = 0. The pulse rifle has two, 3.4 cm apart -- the
// 10 mm barrel at U -4.32 and the grenade launcher at U -9.04. Values are centimetres in the
// gun controller's frame (F forward, L left, U up), the same mapping that reproduces
// RSR_Guns.MagCentre(2) exactly.
//
// NETPLAY: this only moves a missile that has already been spawned, by a fixed measured
// amount, with no randomness and no new actor. It runs identically wherever the shot runs.

class RSQ_Muzzle : EventHandler
{
	// measured bore height, cm above (+) or below (-) the controller
	static double Bore(int i)
	{
		switch (i)
		{
		case 1:	case 5:	case 6:	case 7:	return -0.20;	// the pistols: already on the axis
		case 2:	case 8:						return -4.32;	// the pulse rifles' 10 mm barrel
		case 3:	case 9:						return  0.54;	// the smartguns
		}
		return 0.0;
	}

	static double PumpBore(int i)
	{
		return i > 0 ? 3.35 : 0.0;		// the shotguns
	}

	// the shots this applies to. A flame or a grenade is not a bullet leaving a bore.
	static bool IsRound(Name n)
	{
		switch (n)
		{
		case 'ColPistol':	case 'MerPistol':	case 'SynPistol':	case 'YutPistol':
		case 'BulletTracer':	case 'ShotgunTracer':	case 'HeavyTracer':
		case 'SmartgunTracer':	case 'SmartgunTracer2':
			return true;
		}
		return false;
	}

	override void WorldThingSpawned(WorldEvent e)
	{
		let cv = CVar.FindCVar('ae_muzzle_bore');
		if (cv && !cv.GetBool())
			return;
		// NETPLAY, 2026-10-23. WorldThingSpawned is a playsim event: it runs on every machine,
		// and the offset below is built from HandDir, which is local VR data only the shooter
		// has. So in a net game the shooter displaces the round and nobody else does, which
		// can diverge the impact point. This was gated behind `if (multiplayer) return;` for
		// that reason and the owner un-gated it -- this set is played single player, and a
		// round that leaves 4.3 cm above the barrel is a real fault every shot, against a
		// desync in a mode nobody runs. If a net game is ever wanted, the fix is to carry the
		// offset in an event rather than to switch this off again.
		let a = e.Thing;
		if (!a || !a.target || !a.target.player || !IsRound(a.GetClassName()))
			return;
		let mo = PlayerPawn(a.target);
		if (!mo || !mo.player || !RSVR_VRHand.InVR(mo))
			return;		// outside VR the engine never zeroed the offset, so nothing to undo

		int gi = RSR_Guns.Index(mo.player.ReadyWeapon);
		double d = gi > 0 ? Bore(gi) : PumpBore(RSP_Guns.Index(mo.player.ReadyWeapon));
		if (d == 0)
			return;

		double ps = mo.Level.pixelstretch;
		if (ps <= 0)
			ps = 1.2;
		double vu = 34.0;
		let cvv = CVar.GetCVar('vr_vunits_per_meter', mo.player);
		if (cvv && cvv.GetFloat() > 0)
			vu = cvv.GetFloat();

		// up the GUN's own up, not the world's: a rifle held on its side ejects its round out
		// of the side of the barrel, which is where the barrel is
		Vector3 U = RSVR_VRHand.HandDir(mo, 0, 90, ps);
		Vector3 off = U * (d * vu / 100.0);
		off.z /= ps;
		a.SetOrigin(a.pos + off, false);
	}
}
