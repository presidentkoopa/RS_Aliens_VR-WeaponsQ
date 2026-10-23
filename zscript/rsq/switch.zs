// A physical fire-mode selector: reach up with the off hand and flick the
// switch on the receiver, instead of pressing the alt-fire button.
//
// It does NOT reimplement anything. Each Aliens gun already has an AltFire
// state that toggles its own mode item (PistolRapidAlt, ShotgunBurstAlt,
// SmartAlt), plays its own sound and lands in its own ready state. This
// enters that state, so the switch is a second INPUT to the gun's own
// alt-fire and never a second copy of its logic. Nothing desyncs, and a gun
// whose alt-fire changes later follows along for free.
//
// Only guns whose MESH HAS a selector get one. On this set that is the two
// smartguns: surface 2, a 3.5 x 2.1 x 1.5 cm switch on the upper left of the
// receiver that never moves in any animation -- measured, not chosen. The
// pistol, rifle, shotgun and flamethrower have no such surface (their named
// parts are triggers, hammers, slides, pumps, bolts and magazines), so
// inventing a place on them to reach for would be a control the player cannot
// see. Those keep the button.

class AE_Switch abstract
{
	// where the selector sits, in the gun hand's frame: cm F / L / U
	const SMART_F =  26.81;
	const SMART_L =   5.74;
	const SMART_U =   8.45;
	const REACH   =   7.0;		// the off hand within this of it is on the switch
	const LEAVE   =  10.0;		// and off it again past this (hysteresis, so one
								// flick is one toggle and not a stream of them)

	// the selector's position for this weapon, or (0,0,0) with ok = false
	clearscope static Vector3, bool Of(Weapon w)
	{
		if (!w)
			return (0, 0, 0), false;
		Name n = w.GetClassName();
		if (n == 'Smartgun_3D' || n == 'YutaniSmartgun_3D')
			return (SMART_F, SMART_L, SMART_U), true;
		return (0, 0, 0), false;
	}
}

class AE_SwitchHandler : EventHandler
{
	transient CVar cvOn;
	bool onSwitch[MAXPLAYERS];		// the hand was on it last tic (edge, not level)

	override void WorldTick()
	{
		if (!cvOn)
			cvOn = CVar.GetCVar('ae_handswitch');
		bool on = !cvOn || cvOn.GetBool();

		for (int i = 0; i < MAXPLAYERS; i++)
		{
			if (!playeringame[i])
			{
				onSwitch[i] = false;
				continue;
			}
			let p = players[i];
			let mo = p.mo;
			if (!on || !mo || mo.health <= 0 || !RSVR_VRHand.InVR(mo))
			{
				onSwitch[i] = false;
				continue;
			}
			// A reload owns the off hand; the switch must not steal it.
			// (This is the one place the selector depends on the reload being
			// present. They ship together.)
			if (RSR_Handler.FreeHand(mo) != "")
			{
				onSwitch[i] = false;
				continue;
			}
			let w = p.ReadyWeapon;
			Vector3 sw;
			bool has;
			[sw, has] = AE_Switch.Of(w);
			if (!has)
			{
				onSwitch[i] = false;
				continue;
			}
			Vector3 off = GunFrame(mo);
			double d = (off - sw).Length();
			if (!onSwitch[i] && d <= AE_Switch.REACH)
			{
				onSwitch[i] = true;
				Flick(p, w);
			}
			else if (onSwitch[i] && d > AE_Switch.LEAVE)
			{
				onSwitch[i] = false;
			}
		}
	}

	// The off hand relative to the gun hand, in the gun's own frame (cm F/L/U).
	// Built exactly as rsr/vreload.zs Frames() builds it -- three HandDir calls
	// at 0, 90 and 90 degrees. The engine mirrors the left controller and
	// AttackDir already carries that, so these are the axes the layers are
	// actually drawn in; deriving L and U with cross products instead gets the
	// handedness wrong and puts the switch on the other side of the gun.
	static Vector3 GunFrame(PlayerPawn mo)
	{
		double ps = mo.Level.pixelstretch;
		if (ps <= 0)
			ps = 1.2;
		double vu = 34.0;
		let cv = CVar.GetCVar('vr_vunits_per_meter', mo.player);
		if (cv && cv.GetFloat() > 0)
			vu = cv.GetFloat();
		Vector3 F = RSVR_VRHand.HandDir(mo, 0, 0, ps);
		Vector3 L = RSVR_VRHand.HandDir(mo, 90, 0, ps);
		Vector3 U = RSVR_VRHand.HandDir(mo, 0, 90, ps);
		Vector3 w = RSVR_VRHand.OffPos(mo) - RSVR_VRHand.HandPos(mo);
		w.z *= ps;
		w *= 100.0 / vu;
		return (w dot F, w dot L, w dot U);
	}

	// Enter the gun's OWN AltFire. This is what the alt-fire button does.
	static void Flick(PlayerInfo p, Weapon w)
	{
		State s = w.FindState('AltFire');
		if (!s)
			return;
		p.SetPsprite(PSP_WEAPON, s);
	}
}
