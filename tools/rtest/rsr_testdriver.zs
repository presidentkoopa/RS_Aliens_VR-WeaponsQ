// TEST ONLY, taken verbatim from the kit at
// kit/kit/team/reload_merged/rtest/vrhand_rsr.zs (the RSR_TestDriver and RSR_TestView
// halves). It scripts the off hand through a real reload -- grip, position, trigger --
// and logs every phase. It touches only RSR.* , RSR_Guns.* and RSR_Handler.StateOf,
// all of which this pack carries from the same 1.92 port, so it needed no changes.
class RSR_TestDriver : EventHandler
{
	Vector3 off;
	Vector3 target;
	double offPitch;	// RSR-PUMP (test only): the off hand's pitch (OffDir)
	bool grip;
	bool trig;
	bool steady;
	bool sentGrip;
	int at;				// tics the hand has been at its target
	int lastPhase;
	int sub;			// a step inside a phase
	int holdUntil;
	String holdName;
	int fumbled;
	bool pitched;
	bool yawSet;
	bool hideGun;		// TEST VIEW: the floor shot turns every layer away (yaw 180) to see the dropped magazine

	const REST_F = 2.0;
	const REST_L = 10.0;
	const REST_U = -6.0;

	override void WorldLoaded(WorldEvent e)
	{
		off = (REST_F, REST_L, REST_U);
		target = off;
	}

	bool Hold(int now, String name, int tics)
	{
		if (holdName == name)
			return now < holdUntil;
		holdName = name;
		holdUntil = now + tics;
		Console.Printf("HOLD %s t%d..t%d", name, now, holdUntil);
		return true;
	}

	// move toward the target at most step cm a tic; true once there
	bool MoveTo(Vector3 t, double step)
	{
		target = t;
		Vector3 dv = t - off;
		double l = dv.Length();
		if (l <= step)
		{
			off = t;
			at++;
			return true;
		}
		off += dv * (step / l);
		at = 0;
		return false;
	}

	override void WorldTick()
	{
		let mo = players[0].mo;
		if (!mo)
			return;
		let cv = CVar.FindCVar('rsrtest_script');
		int script = cv ? cv.GetInt() : 0;
		let s = RSR_Handler.StateOf(mo);
		int now = Level.maptime;
		if (s && script > 0)
			Script(mo, s, now, script);
		if (grip != sentGrip)
		{
			EventHandler.SendNetworkEvent("rsr_grip", grip ? 1 : 0, 443);
			sentGrip = grip;
		}
		// TEST VIEW (rsr_test_yaw): on a desktop the HUD models are seen from behind; turn
		// every layer of the gun and the hands by the same yaw (a psprite's x is yaw * 4 in
		// hw_weapon.cpp) to see them from the side
		let yv = CVar.FindCVar('rsr_test_yaw');
		double yaw = hideGun ? 180 : yv ? yv.GetFloat() : 0;
		bool turned = yawSet;
		yawSet = yaw != 0;
		if (yaw != 0 || turned)
		{
			static const int ids[] = { PSP_WEAPON, 2100, 2101, 2102, 2103, 2104, 2105, 2106, 2107, 2108, 2109, 2110, 2111, 2200, 2201, 2202 };	// RSR-BREAK: + 2105-2111, 2202
			for (int k = 0; k < ids.Size(); k++)
			{
				let q = mo.player.FindPSprite(ids[k]);
				if (q)
				{
					q.x = yaw * 4;
					q.oldx = yaw * 4;
				}
			}
		}
		// the hands' layers are made with y 0 (an 8 degree pitch about their own block's
		// pivot: hw_weapon.cpp (my - WEAPONTOP) / -4); in this desktop view that pivot is
		// 40 cm away, so it is taken out here to show them as they sit in the headset
		static const int hl[] = { 2200 };
		for (int k = 0; k < hl.Size(); k++)
		{
			let q = mo.player.FindPSprite(hl[k]);
			if (q)
			{
				q.y = 32;
				q.oldy = 32;
			}
		}
		if (s && s.phase != lastPhase)
		{
			Log(mo, s, now, "phase");
			lastPhase = s.phase;
			sub = 0;
			at = 0;
		}
		else if (now % 35 == 0)
			Log(mo, s, now, "tick");
	}

	// how the hand takes hold at this step: the trigger, or the grip
	void Take(bool on, bool useGrip)
	{
		grip = on && useGrip;
		trig = on && !useGrip;
	}

	void Script(PlayerPawn mo, RSR_State s, int now, int script)
	{
		int i = s.gun;
		Vector3 rest = (REST_F, REST_L, REST_U);
		Vector3 belt = (-10, 28, -48);			// 56 cm from the gun hand
		bool gripMag = script != 7;				// the magazine: grip at the belt (trigger in 7)
		bool gripHandle = script == 6;			// the handle: trigger (grip in 6)
		if (script == 3)
		{
			// proximity only: the hand goes where a magazine would go in, and onto the
			// handle, without ever squeezing the grip or the trigger. Nothing may happen.
			grip = false;
			trig = false;
			if (s.phase == RSR.EMPTY)
			{
				Vector3 home = RSR_Guns.Well(i) - RSR_Guns.TopInHand(i);
				Vector3 h0 = RSR_Guns.Grab(i) - RSR.PalmGrab();
				if (sub == 0 && MoveTo(home - RSR_Guns.Axis(i) * (RSR_Guns.Mouth(i) + 3), 2) && at > 10)
					sub = 1;
				else if (sub == 1 && MoveTo(home + RSR_Guns.Axis(i), 1) && at > 20)
					sub = 2;
				else if (sub == 2 && MoveTo(h0, 2) && at > 10)
					sub = 3;
				else if (sub == 3)
					MoveTo(h0 + RSR_Guns.Pull(i) * (RSR_Guns.Travel(i) + 1), 1);
			}
			return;
		}
		switch (s.phase)
		{
		case RSR.IDLE:
		case RSR.DONE:
			Take(false, true);
			steady = false;
			MoveTo(rest, 3);
			if (pitched)
			{
				mo.A_SetPitch(0);
				pitched = false;
			}
			break;

		case RSR.DROP:
			break;

		case RSR.EMPTY:
			// the magazine is out: hold for a look at the empty well, then a look at the floor
			if (sub == 0)
			{
				if (Hold(now, fumbled ? "EMPTY_AGAIN" : "MAG_OUT", 36))
					break;
				sub = fumbled ? 2 : 1;
			}
			if (sub == 1)
			{
				mo.A_SetPitch(60);
				pitched = true;
				hideGun = true;
				if (Hold(now, "FLOOR", 36))
					break;
				hideGun = false;
				mo.A_SetPitch(0);
				pitched = false;
				sub = script == 4 ? 10 : script == 5 ? 20 : 2;
			}
			if (sub == 10)
			{
				// 4: a grip pressed 30 cm from the gun hand is the engine's steadying: no grab
				if (!MoveTo((-5, 18, -22), 3) || at < 4)
					break;
				grip = true;
				if (Hold(now, "GRIP_NEAR_NOGRAB", 25))
					break;
				grip = false;
				sub = 2;
			}
			if (sub == 20)
			{
				// 5: steadied (faked) while the grip is pressed at the belt: no grab
				if (!MoveTo(belt, 3) || at < 4)
					break;
				steady = true;
				grip = true;
				if (Hold(now, "STEADIED_NOGRAB", 25))
					break;
				grip = false;
				steady = false;
				sub = 2;
				at = 0;
			}
			// to the belt, then take hold (at the belt: well over 50 cm from the gun hand)
			Take(false, gripMag);
			if (MoveTo(script == 6 ? (-6, 22, -24) : belt, 3) && at > 4)
				Take(true, gripMag);
			break;

		case RSR.CARRY:
		{
			// up beside the gun (the magazine in the hand, on view), then under the well
			Vector3 under = RSR_Guns.Well(i) - RSR_Guns.Axis(i) * (RSR_Guns.Mouth(i) + 3) - RSR_Guns.TopInHand(i);
			if (sub == 0)
			{
				if (!MoveTo(under - RSR_Guns.Axis(i) * 8 + (0, 4, 0), 3))	// beside the gun, out along the well's axis
					break;
				if (Hold(now, "MAG_IN_HAND", 36))
					break;
				sub = 1;
			}
			MoveTo(under, 2);
			break;
		}

		case RSR.INSERT:
		{
			Vector3 home = RSR_Guns.Well(i) - RSR_Guns.TopInHand(i);
			// half into the well (a shallow well, the ASG's 0.9 cm: 2 cm, at its mouth, still not home)
			Vector3 half = home - RSR_Guns.Axis(i) * max(RSR_Guns.Mouth(i) * 0.5, 2.0);
			if (sub == 0)
			{
				if (!MoveTo(half, 1.5))
					break;
				if (Hold(now, "MAG_HALF_IN", 36))
					break;
				sub = 1;
				if (script == 2 && !fumbled)
				{
					// let go before it is home: it must fall out
					fumbled = 1;
					Take(false, gripMag);
					break;
				}
			}
			MoveTo(home + RSR_Guns.Axis(i) * 1.0, 1.5);		// a hand pushes through: home is where it stops
			break;
		}

		case RSR.SEATED:
		case RSR.CHARGE:
		{
			Take(false, gripHandle);
			Vector3 at0 = RSR_Guns.Grab(i) - RSR.PalmGrab();
			if (sub == 0)
			{
				if (Hold(now, "SEATED", 36))
					break;
				sub = script == 4 ? 10 : 1;
			}
			if (sub == 10)
			{
				// 4: the grip on the handle (well within 50 cm): steadying, not a grab
				if (!MoveTo(at0, 3) || at < 4)
					break;
				grip = true;
				if (Hold(now, "GRIP_HANDLE_NOGRAB", 25))
					break;
				grip = false;
				sub = 1;
				at = 0;
				break;
			}
			if (MoveTo(at0, 3) && at > 4)
				Take(true, gripHandle);
			break;
		}

		case RSR.PULL:
		{
			Vector3 at0 = RSR_Guns.Grab(i) - RSR.PalmGrab();
			double tr = RSR_Guns.Travel(i);
			if (sub == 0)
			{
				if (!MoveTo(at0 + RSR_Guns.Pull(i) * (tr * 0.5), 1.0))
					break;
				if (Hold(now, "HANDLE_HALF", 36))
					break;
				sub = 1;
			}
			if (sub == 1)
			{
				if (!MoveTo(at0 + RSR_Guns.Pull(i) * (tr + 1.0), 1.0))
					break;
				if (Hold(now, "HANDLE_BACK", 36))
					break;
				sub = 2;
			}
			Take(false, gripHandle);
			break;
		}

		case RSR.RELEASED:
			Take(false, gripHandle);
			break;
		}
	}

	// sprite names for the log: the reload's own (RSR_Guns) and the hands'
	static String SprName(int spr)
	{
		static const Name n[] = { 'TNT1', 'RQHN', 'RQGS', 'RQSP' };
		for (int k = 0; k < n.Size(); k++)
		{
			if (spr == Actor.GetSpriteIndex(n[k]))
				return n[k];
		}
		for (int g = 1; g <= RSR_Guns.Count(); g++)
		{
			Array<String> w;
			String all = String.Format("%s %s %s %s", RSR_Guns.SprGun(g), RSR_Guns.SprPart(g), RSR_Guns.SprWorld(g), RSR_Guns.ReadySprites(g));
			all.Split(w, " ", TOK_SKIPEMPTY);
			for (int k = 0; k < w.Size(); k++)
			{
				if (w[k].Length() == 4 && spr == Actor.GetSpriteIndex(w[k]))
					return w[k];
			}
		}
		return String.Format("spr%d", spr);
	}

	static String Layer(PlayerInfo p, int id)
	{
		let q = p.FindPSprite(id);
		if (!q)
			return "-";
		return String.Format("%s/%c%s", SprName(q.Sprite), 65 + q.Frame, q.Caller ? "@" .. q.Caller.GetClassName() : "");
	}

	void Log(PlayerPawn mo, RSR_State s, int now, String why)
	{
		let p = mo.player;
		let w = p.ReadyWeapon;
		let wp = p.FindPSprite(PSP_WEAPON);
		String st = "-";
		if (wp && w)
		{
			if (wp.CurState == w.FindState("RSR_Wait"))
				st = "RSR_Wait";
			else if (wp.CurState == w.FindState("Ready"))
				st = "Ready";
			else
				st = String.Format("%+d", wp.CurState.DistanceTo(w.FindState("Ready")));
		}
		int mags = 0;
		let it = ThinkerIterator.Create('RSR_DroppedMag');
		Actor dm;
		while (dm = Actor(it.Next()))
		{
			if (mags == 0 && why == "phase" || mags == 0 && now % 70 == 0)
			{
				Vector3 rel = dm.pos - mo.pos;
				Console.Printf("   dropped mag at %.1f %.1f %.1f from the player (floor %.1f) angle %.0f pitch %.0f roll %.0f sprite %s",
					rel.x, rel.y, rel.z, dm.floorz - mo.pos.z, dm.angle, dm.pitch, dm.roll, SprName(dm.sprite));
			}
			let sv = CVar.FindCVar('rsrtest_magscale');
			if (sv && sv.GetFloat() > 0)
				dm.scale = (sv.GetFloat(), sv.GetFloat());
			mags++;
		}
		Console.Printf("t%d %s [%s] %s state %s gun %s | phase %s d %.1f pull %.1f | off %.1f %.1f %.1f gap %.0f grip %d trig %d steady %d",
			now, why, holdName, w ? w.GetClassName() : 'none', st, wp ? SprName(wp.Sprite) .. String.Format("/%c", 65 + wp.Frame) : "-",
			s ? RSR.PhaseName(s.phase) : "?", s ? s.d : 0, s ? s.pull : 0, off.x, off.y, off.z, RSVR_VRHand.SteadyGap(mo), grip, trig, steady);
		int g = RSR_Guns.Index(w);
		if (g > 0)
		{
			String held = "RSR_Held_" .. w.GetClassName();
			Console.Printf("   ammo %s %d %s %d held %d nomag %d charge %s %d | dropped mags %d",
				RSR_Guns.MagAmmo(g), CountByName(mo, RSR_Guns.MagAmmo(g)), RSR_Guns.Reserve(g), CountByName(mo, RSR_Guns.Reserve(g)),
				CountByName(mo, held), CountByName(mo, RSR_Guns.NoMag(g)), RSR_Guns.ChargeToken(g), CountByName(mo, RSR_Guns.ChargeToken(g)), mags);
		}
		else
			Console.Printf("   (not a real-reload gun) | dropped mags %d", mags);
		Vector3 hs = RSR_TestView.HandShift(2200);
		Console.Printf("   layers 2102 %s 2103 %s 2104 %s | 2200 %s 2201 %s | 2100 %s 2101 %s",
			Layer(p, 2102), Layer(p, 2103), Layer(p, 2104), Layer(p, 2200), Layer(p, 2201), Layer(p, 2100), Layer(p, 2101));
	}

	static int CountByName(Actor mo, String n)
	{
		if (n == "")
			return -1;
		class<Inventory> c = n;
		return c ? mo.CountInv(c) : -1;
	}
}

// TEST VIEW (desktop only). vr_3dweaponOffset and a yaw (psprite x) act inside each
// layer's own MODELDEF block (its Scale and Offset), so Ermac's hand blocks (Scale -1 1 1,
// Offset 0 -24 -10) would drift from a gun with another placement. This moves the hand
// layers so the whole assembly sits and turns as the gun's block does:
//   t0 = S_h^-1 (S_g - S_h) v        (v = the vr_3dweaponOffset translation)
//   c  = (R^T - I) S_h^-1 (P_g - P_h),  P = o + S v (a block's turning point), R = the yaw
// (c holds when both blocks have the same handedness, as on BD22; on V+ use yaw 0).
class RSR_TestView abstract
{
	clearscope static Vector3 HandShift(int layer)
	{
		if (layer != 2100 && layer != 2101 && layer != 2200)
			return (0, 0, 0);
		let h = RSR_Handler.Get();
		int gun = 0;
		if (h && h.st[consoleplayer])
			gun = h.st[consoleplayer].gun;
		let pl = players[consoleplayer].mo;
		int now = pl ? RSR_Guns.Index(pl.player.ReadyWeapon) : 0;
		if (now > 0)
			gun = now;
		// RSR-BREAK removed for this set: it has no break-open gun, and naming RSB_Handler /
		// RSB_Guns here is a compile error, not a silent miss. The pump branch stays -- this
		// pack does have pump shotguns.
		// RSR-PUMP: the pump shotguns' placement
		int pg = pl ? RSP_Guns.Index(pl.player.ReadyWeapon) : 0;
		if (gun <= 0 && pg <= 0)
			return (0, 0, 0);
		Vector3 gsc, gof;
		if (gun > 0) { gsc = RSR_Guns.Scale(gun); gof = RSR_Guns.Offset(gun); }
		else { gsc = RSP_Guns.Scale(pg); gof = RSP_Guns.Offset(pg); }
		Vector3 Sg = (gsc.x, gsc.z, gsc.y);			// local axes
		Vector3 Sh = (-1, 1, 1);
		Vector3 Og = (gof.x, gof.z, gof.y);
		Vector3 Oh = (0, -10, -24);
		Vector3 v = (-F('vr_3dweaponOffsetX'), F('vr_3dweaponOffsetY'), F('vr_3dweaponOffsetZ'));
		Vector3 t0 = ((Sg.x - Sh.x) * v.x / Sh.x, (Sg.y - Sh.y) * v.y / Sh.y, (Sg.z - Sh.z) * v.z / Sh.z);
		Vector3 dp = Og - Oh + ((Sg.x - Sh.x) * v.x, (Sg.y - Sh.y) * v.y, (Sg.z - Sh.z) * v.z);
		dp = (dp.x / Sh.x, dp.y / Sh.y, dp.z / Sh.z);
		double y = F('rsr_test_yaw');
		// the hands work's hands.zs (RSQ_Turn) already turns the gun-side hands with the
		// gun layer's turn about the gun's point; then only the free hand needs it here
		String tn = "RSQ_Turn";
		class<Object> teamHands = tn;
		if (teamHands && layer != 2200)
			y = 0;
		Vector3 r = (cos(-y) * dp.x + sin(-y) * dp.z, dp.y, -sin(-y) * dp.x + cos(-y) * dp.z);
		return t0 + (r - dp);
	}

	clearscope static double F(Name n)
	{
		let cv = CVar.FindCVar(n);
		return cv ? cv.GetFloat() : 0;
	}
}
