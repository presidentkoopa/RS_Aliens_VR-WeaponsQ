// 2026-10-22 PULSE RIFLE: PUMP TO LOAD THE LAUNCHER (owner: "1 pump reduces ammo by 20 but
// loads 1 secondary fire"). The M41A's underbarrel launcher is loaded by working its pump by
// hand: the off hand takes the pump (off trigger within ae_glpump_grab cm of it), pulls it back
// ae_glpump_travel cm and brings it forward again. Each full stroke takes ae_glpump_cost rounds
// out of the magazine (PulseLoaded / YPulseLoaded) and puts one grenade in (GrenadeAmmo); the
// gun's own alt fire shoots it as before. No stroke while a magazine reload has the off hand.
//
// 2026-10-23 THE PUMP IS NOW A PART, NOT AN ANIMATION (parity step 4). This used to create no
// psprite layer at all: it read the hand, counted a stroke, and on completion jumped the weapon
// to a canned 10-tic animation. So the part never moved with the hand -- it moved on its own,
// afterwards. It is now driven exactly as the shotgun's pump is (zscript/rsr/rsr_pump.zs): the
// rifle draws without its pump, the pump draws on its own layer, and that layer is placed at
// however far the hand has actually carried it, interpolated by ticfrac like every other part.
//
// Pump point, travel and hook are MEASURED, not tuned:
//   * PumpPoint is surface [1] m41a_pump's centroid through the MEASUREMENTS.md chain
//     (F = x x Scale x vr_weaponScale, U = z x Scale x vr_weaponScale + (ZOffset + 5)). The same
//     chain on surface [4] m41a_magazine reproduces RSR_Guns.MagCentre(2) = (8.900, -0.001,
//     -17.597) to three decimals on this very gun, which is what makes it trustworthy here.
//     The hand-estimated (42.5, 0, -8.5) it replaces was 1.5 cm forward and 0.6 cm high.
//   * The stroke is the mesh's own: 14.201 md3 units along -x between frames 8 and 10,
//     x 1.1 x 1.02 = 15.93 cm (ae_glpump_travel's default).
//   * PumpHook is 1/Scale along the pull axis, as RSP_Guns.PumpHook is for the shotgun -- both
//     guns are Scale 1.1, so it is the same 0.909.
class RSQ_PumpGL : EventHandler
{
	const LAYER = 2130;			// RSR_GunParts, main controller: the launcher pump

	bool held[MAXPLAYERS];
	double startF[MAXPLAYERS];
	bool back[MAXPLAYERS];
	bool trigPrev[MAXPLAYERS];
	double pull[MAXPLAYERS], pullPrev[MAXPLAYERS];

	// surface [1] m41a_pump's centroid in the gun controller's frame (F, L, U cm)
	clearscope static Vector3 PumpPoint() { return (43.965, -0.021, -9.115); }

	// the part slides straight back along the gun's own axis. NOT Pull(): ZScript identifiers
	// are case-insensitive, so that would collide with the pull[] array above.
	clearscope static Vector3 PullDir() { return (-1.0, 0.0, 0.0); }

	// 1 / MODELDEF Scale, along the pull axis: hooks are x left, y up, z back
	clearscope static Vector3 PumpHook() { return (0.0, 0.0, 0.909); }

	clearscope static int Index(Weapon w)
	{
		if (w is 'PulseRifle_3D')	return 1;
		if (w is 'YutaniRifle_3D')	return 2;
		return 0;
	}

	clearscope static Name SprGun(int i)  { return i == 1 ? 'RSLG' : i == 2 ? 'RSRG' : 'None'; }
	clearscope static Name SprPart(int i) { return i == 1 ? 'RSLQ' : i == 2 ? 'RSRQ' : 'None'; }

	static RSQ_PumpGL Get() { return RSQ_PumpGL(EventHandler.Find('RSQ_PumpGL')); }

	override void WorldTick()
	{
		for (int n = 0; n < MAXPLAYERS; n++)
		{
			if (!playeringame[n])
				continue;
			let p = players[n];
			let mo = p.mo;
			if (!mo || p.playerstate != PST_LIVE || !RSVR_VRHand.InVR(mo))
			{
				held[n] = false;
				pull[n] = pullPrev[n] = 0;
				continue;
			}
			let w = p.ReadyWeapon;
			int gi = Index(w);
			Name loaded = gi == 1 ? 'PulseLoaded' : gi == 2 ? 'YPulseLoaded' : 'None';
			bool trig = (p.cmd.buttons & RSR.GrabMask(p)) != 0;
			bool press = trig && !trigPrev[n];
			trigPrev[n] = trig;
			let rs = RSR_Handler.StateOf(mo);
			bool busy = rs && rs.phase != RSR.IDLE;
			if (gi == 0 || !(p.OffhandWeapon is 'RSQ_Hands') || busy || p.PendingWeapon != WP_NOCHANGE)
			{
				held[n] = false;
				pull[n] = pullPrev[n] = 0;
				Show(p, mo, 0, false);
				continue;
			}
			Vector3 o = AE_SwitchHandler.GunFrame(mo);		// the off hand in the gun's frame: F, L, U cm
			double grab = RSR.Float('ae_glpump_grab', 14.0);
			double travel = RSR.Float('ae_glpump_travel', 15.9);
			pullPrev[n] = pull[n];
			if (!held[n])
			{
				if (trig && (o - PumpPoint()).Length() < grab)
				{
					held[n] = true;
					back[n] = false;
					startF[n] = o.x;
					pull[n] = pullPrev[n] = 0;
					RSQ_MeleeHandler.Buzz(mo);		// the hand feels it take the pump
				}
				else
					pull[n] = 0;
				Show(p, mo, gi, held[n]);
				continue;
			}
			// holding the pump
			if (!trig || (o - PumpPoint()).Length() > grab * 2.0)
			{
				held[n] = false;
				pull[n] = 0;
				Show(p, mo, gi, false);
				continue;
			}
			double d = startF[n] - o.x;			// cm back from where it was taken
			pull[n] = clamp(d, 0, travel);		// the part never leaves its own track
			if (!back[n] && d >= travel)
			{
				back[n] = true;
				mo.A_StartSound("PULSREL3", CHAN_AUTO, CHANF_OVERLAP);
				RSQ_MeleeHandler.Buzz(mo);		// ...and feels it reach the back of its travel
			}
			else if (back[n] && d <= travel * 0.3)
			{
				back[n] = false;
				Cycle(p, mo, w, loaded);
			}
			Show(p, mo, gi, true);
		}
	}

	// the rifle without its pump on the weapon layer, the pump alone on its own
	static void Show(PlayerInfo p, PlayerPawn mo, int gi, bool on)
	{
		let parts = RSR_GunParts(mo.FindInventory('RSR_GunParts'));
		if (on && !parts)
		{
			mo.GiveInventory('RSR_GunParts', 1);
			parts = RSR_GunParts(mo.FindInventory('RSR_GunParts'));
		}
		RSR.SetPart(p, LAYER, parts, on && gi > 0, SprPart(gi), 0);
		if (!on || gi == 0)
			return;
		// swap the gun's own frame for the one with the pump surface cleared, but only while it
		// is simply at ready -- never over a reload or a firing frame, which own the layer
		let psp = p.FindPSprite(PSP_WEAPON);
		if (psp && (p.WeaponState & WF_WEAPONREADY) && RSR.IsReadyFrame(psp, RSR_Guns.Index(p.ReadyWeapon)))
		{
			psp.Sprite = Actor.GetSpriteIndex(SprGun(gi));
			psp.Frame = 0;
		}
	}

	static void Cycle(PlayerInfo p, PlayerPawn mo, Weapon w, Name loaded)
	{
		int cost = max(1, int(RSR.Float('ae_glpump_cost', 20)));
		if (mo.CountInv(loaded) < cost)
		{
			mo.A_StartSound("DRYFIRE", CHAN_AUTO, CHANF_OVERLAP);		// not enough rounds to make a grenade
			return;
		}
		mo.TakeInventory(loaded, cost);
		mo.GiveInventory('GrenadeAmmo', 1);
		// 2026-10-23: the canned AE_GLPump animation is NOT played in VR any more -- the hand
		// has just done that movement itself, and playing it again moved the part a second
		// time under a hand that was already still. The state stays in rifle.txt for the
		// non-VR path, which has no hand to drive anything.
	}

	// where the pump is drawn: its own hook carried back by however far the hand has it
	clearscope static bool Places(int layer)
	{
		return layer == LAYER;
	}

	clearscope static Vector3, Vector3 Place(Actor owner, Vector3 t, Vector3 r, double ticfrac)
	{
		let h = RSQ_PumpGL(EventHandler.Find('RSQ_PumpGL'));
		let p = owner ? owner.player : null;
		if (!h || !p)
			return t, r;
		int n = 0;
		for (; n < MAXPLAYERS; n++)
			if (players[n] == p)
				break;
		if (n >= MAXPLAYERS)
			return t, r;
		double d = h.pullPrev[n] + (h.pull[n] - h.pullPrev[n]) * ticfrac;
		return t + PumpHook() * d, r;
	}
}
