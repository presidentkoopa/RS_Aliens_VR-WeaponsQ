// TEST ONLY, taken verbatim from the kit at kit/kit/team/reload_merged/rtest/pump_test.zs.
// It scripts the pump path -- shells into the port, the forend worked -- and every RSP.*,
// RSP_Guns.* and RSP_Handler.StateOf it touches exists in this pack from the same 1.92
// port, so it needed no changes. It reads RSR_TestDriver.off, which is why both drivers
// have to live in the one lump the pack's ZSCRIPT includes.
// TEST ONLY (RSR-PUMP): scripts the off hand for the pump shotguns (rsptest_script) and logs.
// The off hand's position, pitch and grip go through the real reload's test kit (RSR_TestDriver.off,
// .offPitch, .grip: rtest/vrhand_rsr.zs; the grip is the same rsr_grip network event a real key
// sends). The off trigger and the engine's steadying go through the test-only cvars
// rsp_test_trigger / rsp_test_steady, which rsr/rsr_pump.zs reads (they exist only in test packs).
// Run with rsrtest_script 0 so the rifle script keeps its hands off.
//
// scripts: 1 fill (shells by hand to the set's end, then the pump by hand, steadied)
//          2 pump (steadied on the pump; every pump a full stroke at rsptest_speed cm/tic)
//          3 off  (the hand never on the pump)
//          4 short (steadied on the pump; two short strokes, then a full one)
//          5 switch (fill; with a shell in the hand after 2, switch to the rifle and back)
//          6 fumble (fill; the first shell let go half in)
//          7 near (a grip pressed 30 cm from the gun hand takes nothing; the trigger there does)
//          8 loadpump (3 shells into an empty gun, then the pump stroke ends the reload)
//          9 grabpump (not steadied: the off trigger held on the pump works it)
//          10 gripsupport (vr_two_handed_weapons 0: the grip held on the pump works it; the support hand rides it)
class RSP_TestDriver : EventHandler
{
	int sub, at, holdUntil, lastMode, lastHand, lastAmmo, lastRes, shots, casings, strokes, shortsDone, homeCount;
	bool lastHeld, lastBack, switched, nearDone, fumbled, trigger;
	int switchTic, fumbleTic;
	String switchBack;
	String holdName;
	int pumpSub;
	int drvMode, drvHand;

	const REST_F = 2.0;
	const REST_L = 10.0;
	const REST_U = -6.0;

	RSR_TestDriver D()
	{
		return RSR_TestDriver(EventHandler.Find('RSR_TestDriver'));
	}

	static void SetCV(Name n, bool v)
	{
		let cv = CVar.FindCVar(n);
		if (cv && cv.GetBool() != v)
			cv.SetBool(v);
	}

	static int CI(Name n, int d)
	{
		let cv = CVar.FindCVar(n);
		return cv ? cv.GetInt() : d;
	}

	static double CF(Name n, double d)
	{
		let cv = CVar.FindCVar(n);
		return cv ? cv.GetFloat() : d;
	}

	bool Hold(int now, String name, int tics)
	{
		if (CI('rsptest_holds', 1) == 0)
			return false;
		if (holdName == name)
			return now < holdUntil;
		holdName = name;
		holdUntil = now + tics;
		Console.Printf("HOLD %s t%d..t%d", name, now, holdUntil);
		return true;
	}

	bool MoveTo(Vector3 t, double step)
	{
		let d = D();
		if (!d)
			return false;
		d.target = t;
		Vector3 dv = t - d.off;
		double l = dv.Length();
		if (l <= step)
		{
			d.off = t;
			at++;
			return true;
		}
		d.off += dv * (step / l);
		at = 0;
		return false;
	}

	void Grip(bool g)
	{
		let d = D();
		if (d)
			d.grip = g;
	}

	// the off controller that puts a point of the off hand's frame at a gun-frame point (pitched hand)
	Vector3 OffFor(Vector3 inHand, Vector3 want)
	{
		let d = D();
		double op = d ? d.offPitch : 0;
		Vector3 r = (inHand.x * cos(op) - inHand.z * sin(op), inHand.y, inHand.x * sin(op) + inHand.z * cos(op));
		return want - r;
	}

	static double Elev(Vector3 v)
	{
		return atan2(v.z, (v.x, v.y).Length());
	}

	override void WorldTick()
	{
		let mo = players[0].mo;
		if (!mo)
			return;
		let s = RSP_Handler.StateOf(mo);
		let d = D();
		int now = Level.maptime;
		int script = CI('rsptest_script', 0);
		if (s && d && script > 0)
			Script(mo, s, d, now, script);
		SetCV('rsp_test_trigger', trigger);
		// TEST VIEW (rsr_test_yaw): turn these layers with the gun's, as the rifle kit does its own
		double yaw = CF('rsr_test_yaw', 0);
		if (yaw != 0)
		{
			static const int ids[] = { 2120, 2121, 2122, 2123, 2210 };
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
		Watch(mo, s, now);
	}

	void Script(PlayerPawn mo, RSP_State s, RSR_TestDriver d, int now, int script)
	{
		if (s.mode != drvMode || s.hand != drvHand)
		{
			// a new step of the hand: start its moves over
			drvMode = s.mode;
			drvHand = s.hand;
			sub = 0;
			at = 0;
		}
		int i = RSP_Guns.Index(mo.player.ReadyWeapon);
		bool grabPump = script == 9 || script == 10;
		bool gripPump = script == 10;
		bool steadyScripts = script == 1 || script == 2 || script == 4 || script == 5 || script == 6 || script == 8;
		if (i <= 0)
		{
			SetCV('rsp_test_steady', false);
			d.offPitch = 0;
			Grip(false);
			trigger = false;
			MoveTo((REST_F, REST_L, REST_U), 3);
			if (script == 5 && switched && now - switchTic > 40 && switchBack != "")
			{
				class<Inventory> sc = switchBack;
				let sg = sc ? Weapon(mo.FindInventory(sc)) : null;
				if (sg && mo.player.PendingWeapon == WP_NOCHANGE)
				{
					Console.Printf("SWITCH back to %s t%d", sg.GetClassName(), now);
					mo.player.PendingWeapon = sg;
				}
			}
			return;
		}
		Vector3 grab = RSP_Guns.Grab(i);
		Vector3 pd = RSP_Guns.Pull(i);
		double travel = RSP_Guns.Travel(i);
		// where the off controller is on the pump: steadied (the engine aims the gun at it: on the
		// gun's axis), or with the palm on it (the trigger grab)
		Vector3 onPump = grabPump ? grab - RSR.PalmGrab() : (grab.x, 0, 0);

		if (s.mode == RSP.PUMPING)
		{
			d.offPitch = 0;
			bool steady = !grabPump;
			if (script == 1 || script == 5 || script == 6 || script == 8)
			{
				// after loading: the hand comes to the pump, then works it steadied
				if (pumpSub == 0)
				{
					Grip(false);
					trigger = false;
					if (s.waitHand && Hold(now, "LOADED_WAITS", 15))
						return;
					if (!MoveTo(onPump, 3))
					{
						SetCV('rsp_test_steady', false);
						return;
					}
					pumpSub = 1;
				}
			}
			SetCV('rsp_test_steady', steady);
			trigger = grabPump && !gripPump;
			Grip(gripPump);
			if (s.done)
			{
				MoveTo(onPump, 3);
				return;
			}
			double spd = CF('rsptest_speed', 1.0);
			if (script == 4 && holdName.Left(5) == "SHORT" && now < holdUntil)
				return;
			if (script == 4 && shortsDone < 2)
			{
				// a short stroke: 40 % back and forward again
				if (sub == 0)
				{
					if (MoveTo(onPump + pd * (travel * 0.4), spd))
						sub = 1;
				}
				else if (MoveTo(onPump, spd))
				{
					sub = 0;
					shortsDone++;
					Console.Printf("SHORT stroke %d done t%d", shortsDone, now);
					Hold(now, String.Format("SHORT_%d", shortsDone), 15);
				}
				return;
			}
			if (sub == 0)
			{
				if (!MoveTo(onPump + pd * (travel * 0.5), spd))
					return;
				if (Hold(now, "PUMP_HALF", 15))
					return;
				sub = 2;
				return;
			}
			if (sub == 2)
			{
				if (!MoveTo(onPump + pd * (travel + 1.0), spd))
					return;
				sub = 4;
				return;		// one place a tic: the engine samples the hand once a tic
			}
			if (sub == 4)
			{
				if (Hold(now, "PUMP_AT_BACK", 5))		// (the set's eject is under way: a look at it)
					return;
				sub = 5;
			}
			if (sub == 5)
			{
				if (Hold(now, "PUMP_BACK", 16))
					return;
				sub = 1;
				return;
			}
			if (sub == 1)
			{
				if (!MoveTo(onPump + pd * (travel * 0.5), spd))
					return;
				if (Hold(now, "PUMP_FWD_HALF", 12))
					return;
				sub = 3;
				return;
			}
			if (MoveTo(onPump - pd * 1.0, spd))
				sub = 0;
			return;
		}
		pumpSub = 0;

		if (s.mode == RSP.LOAD)
		{
			SetCV('rsp_test_steady', false);
			LoadScript(mo, s, d, i, now, script);
			return;
		}

		// idle
		sub = 0;
		Grip(false);
		d.offPitch = 0;
		if (script == 2 || script == 4 || script == 9 || script == 10 || (steadyScripts && s.shells > 0))
		{
			SetCV('rsp_test_steady', !grabPump);
			trigger = grabPump && !gripPump;
			if (grabPump)
			{
				// the trigger (or the grip, steadying off) is pressed on the pump: released first, then pressed there
				bool there = MoveTo(onPump, 3) && at > 2;
				trigger = there && !gripPump;
				Grip(there && gripPump);
			}
			else
				MoveTo(onPump, 3);
		}
		else
		{
			SetCV('rsp_test_steady', false);
			trigger = false;
			MoveTo((REST_F, REST_L, REST_U), 3);
		}
	}

	void LoadScript(PlayerPawn mo, RSP_State s, RSR_TestDriver d, int i, int now, int script)
	{
		Vector3 port = RSP_Guns.Port(i);
		Vector3 push = RSP_Guns.Push(i);
		Vector3 sih = RSP_Guns.ShellInHand(i);
		Vector3 aih = RSP_Guns.AxisInHand(i);
		double depth = RSP_Guns.Depth(i);
		// the hand comes from below the port (BD22) / from the ejection port's side (V+)
		Vector3 side = i == 1 ? (0, 0, -3) : (0, -3, 0);
		side -= push * (side dot push);
		bool useTrigger = script == 7;
		switch (s.hand)
		{
		case RSP.EMPTY:
		{
			d.offPitch = 0;
			if (script == 8 && s.shells >= 3)
			{
				// done loading: the hand goes to the pump, and pulls it back, and forward
				SetCV('rsp_test_steady', true);
				Grip(false);
				Vector3 g0 = RSP_Guns.Grab(i);
				Vector3 onPump = (g0.x, 0, 0);
				if (sub < 10)
				{
					if (MoveTo(onPump, 3))
						sub = 10;
					return;
				}
				if (sub == 10)
				{
					if (MoveTo(onPump + RSP_Guns.Pull(i) * (RSP_Guns.Travel(i) + 1), 1))
						sub = 11;
					return;
				}
				MoveTo(onPump - RSP_Guns.Pull(i), 1);
				return;
			}
			if (script == 6 && fumbled && now - fumbleTic < 60)
			{
				// the dropped shell, on the floor
				if (now - fumbleTic > 8)
				{
					mo.A_SetPitch(50);
					Hold(now, "SHELL_ON_FLOOR", 30);
				}
				return;
			}
			if (script == 6 && fumbled && now - fumbleTic == 60)
				mo.A_SetPitch(0);
			if (s.shells == 1 && sub == 0 && Hold(now, "SHELL_PUSHED_HOME", 15))
				return;
			if (script == 7 && !nearDone)
			{
				// 30 cm from the gun hand: the grip there is the engine's steadying grip, not a grab
				Vector3 near = (-5, 20, -20);
				if (sub == 0)
				{
					Grip(false);
					trigger = false;
					if (MoveTo(near, 3) && at > 3)
						sub = 1;
					return;
				}
				if (sub == 1)
				{
					Grip(true);
					if (at > 12)
					{
						Console.Printf("NEAR grip held 12 tics at %.0f cm: hand %s", near.Length(), RSP.HandName(s.hand));
						Grip(false);
						sub = 2;
						at = 0;
					}
					at++;
					return;
				}
				if (sub == 2)
				{
					at++;
					if (at > 4)
					{
						trigger = true;		// the off trigger grabs anywhere
						nearDone = true;
						if (at > 6)
						{
							nearDone = true;
							sub = 0;
						}
					}
					return;
				}
			}
			// release, go to the belt, take one
			trigger = false;
			if (sub == 0)
			{
				Grip(false);
				if (MoveTo((-10, 25, -45), 3) && at > 3)
					sub = 1;
				return;
			}
			if (useTrigger)
				trigger = true;
			else
				Grip(true);
			return;
		}

		case RSP.CARRY:
		{
			sub = sub < 20 ? 20 : sub;
			if (useTrigger)
				trigger = true;
			else
				Grip(true);
			d.offPitch = Elev(push) - Elev(aih);
			if (script == 5 && s.shells >= 2 && !switched)
			{
				// a shell in the hand: switch to the rifle (the gun's own switching)
				if (Hold(now, "SWITCH_CARRY", 10))
					return;
				String n1 = "Rifle", n2 = "VR_Rifle";
				class<Inventory> c1 = n1;
				class<Inventory> c2 = n2;
				let rf = c1 ? Weapon(mo.FindInventory(c1)) : null;
				if (!rf && c2)
					rf = Weapon(mo.FindInventory(c2));
				if (rf)
				{
					switchBack = mo.player.ReadyWeapon.GetClassName();
					Console.Printf("SWITCH to %s t%d, hand %s", rf.GetClassName(), now, RSP.HandName(s.hand));
					mo.player.PendingWeapon = rf;
					switched = true;
					switchTic = now;
				}
				return;
			}
			Vector3 entry = port - push * 6 + side;
			if (sub == 20)
			{
				// beside the gun first, to look at it
				if (!MoveTo(OffFor(sih, port - push * 8 + side * 4), 3))
					return;
				if (s.shells == 0 && Hold(now, "SHELL_IN_HAND", 25))
					return;
				sub = 21;
			}
			MoveTo(OffFor(sih, entry), 2);
			return;
		}

		case RSP.INSERT:
		{
			if (useTrigger)
				trigger = true;
			else
				Grip(true);
			if (sub < 30)
			{
				sub = 30;
				homeCount = s.shells;
			}
			if (sub == 30)
			{
				// halfway to the port
				if (!MoveTo(OffFor(sih, port - push * 2 + side), 1.0))
					return;
				if (s.shells == 0 && Hold(now, "SHELL_ENTERING", 20))
					return;
				if (script == 6 && !fumbled)
				{
					Console.Printf("FUMBLE: let go of the shell t%d", now);
					fumbled = true;
					Grip(false);
					fumbleTic = now;
					sub = 0;
					return;
				}
				sub = 31;
			}
			if (sub == 31)
			{
				if (!MoveTo(OffFor(sih, port + push * (depth * 0.5) + side), 1.0))
					return;
				if (s.shells == 0 && Hold(now, "SHELL_HALF_IN", 20))
					return;
				sub = 32;
			}
			MoveTo(OffFor(sih, port + push * (depth + 1.5) + side), 1.0);
			return;
		}
		}
	}

	// ---- log ----------------------------------------------------------------------------------

	static int Cnt(Actor mo, String n)
	{
		class<Inventory> c = n;
		return c ? mo.CountInv(c) : -1;
	}

	static String SprName(int spr)
	{
		static const Name n[] = { 'TNT1', 'SHTN', 'SHTA', 'SHT8', '2HTN', '2HTA', 'SHTG', 'RQUG', 'RQUP', 'RQUH', 'RQUQ', 'RQUN',
			'RQHN', 'RQGS', 'RQSP', 'RIFG', 'RIFL', 'KICK' };
		for (int k = 0; k < n.Size(); k++)
		{
			if (spr == Actor.GetSpriteIndex(n[k]))
				return n[k];
		}
		return String.Format("spr%d", spr);
	}

	static String Layer(PlayerInfo p, int id)
	{
		let q = p.FindPSprite(id);
		if (!q)
			return "-";
		return String.Format("%s/%c", SprName(q.Sprite), 65 + q.Frame);
	}

	static String StateName(PlayerInfo p)
	{
		let w = p.ReadyWeapon;
		let wp = p.FindPSprite(PSP_WEAPON);
		if (!wp || !w || !wp.CurState)
			return "-";
		static const String labels[] = { "Ready", "Ready3", "RSP_LoadWait", "RSP_P1Wait", "RSP_P2Wait", "RSP_P3Wait", "RSP_PWait", "ReadyToFireAgain", "Pump1", "Pump2" };
		for (int k = 0; k < labels.Size(); k++)
		{
			let st = w.FindStateByString(labels[k], true);
			if (st && wp.CurState == st)
				return labels[k];
		}
		let r = w.FindStateByString("Ready", true);
		return r ? String.Format("Ready%+d", wp.CurState.DistanceTo(r)) : "?";
	}

	void Watch(PlayerPawn mo, RSP_State s, int now)
	{
		let p = mo.player;
		let w = p.ReadyWeapon;
		// SET-SPECIFIC NAMES REPLACED, 2026-10-23. The kit's version chose between BD22's
		// ShotgunAmmo/AmmoShell and Vanilla+'s VR_ShotLoaded/VR_Shell by class name, so on
		// this pack it counted a token nothing here owns and logged -1 for everything. This
		// asks the pack's own tables by index instead -- ShotgunLoaded / YShotgunLoaded over
		// AliensShell -- which is how a third set was always going to have to do it.
		int pgi = RSP_Guns.Index(w);
		String magName = RSP_Guns.MagAmmo(pgi);
		String resName = RSP_Guns.Reserve(pgi);
		int ammo = Cnt(mo, magName);
		int res = Cnt(mo, resName);
		int cas = 0;
		if (CI('rsptest_casings', 1))
		{
			String cn = "RSQ_Shell12ga";	// this pack's spent shell, not BD22's
			class<Thinker> sc = cn;
			if (sc)
			{
				let it2 = ThinkerIterator.Create(sc);
				while (it2.Next())
					cas++;
			}
		}
		int drops = 0;
		let it3 = ThinkerIterator.Create('RSP_DroppedShell');
		while (it3.Next())
			drops++;
		String why = "";
		if (ammo < lastAmmo && s.mode != RSP.LOAD && ammo >= 0)
		{
			shots++;
			Console.Printf("SHOT %d t%d (%s %d -> %d)", shots, now, magName, lastAmmo, ammo);
			why = "shot";
		}
		if (s && (s.mode != lastMode || s.hand != lastHand || s.held != lastHeld || s.backDone != lastBack))
			why = why == "" ? "phase" : why;
		if (ammo != lastAmmo || res != lastRes || cas != casings)
			why = why == "" ? "ammo" : why;
		if (why == "" && now % 35 != 0 && CI('rsptest_every', 0) == 0)
		{
			lastAmmo = ammo;
			return;
		}
		lastAmmo = ammo;
		lastRes = res;
		casings = cas;
		if (s)
		{
			lastMode = s.mode;
			lastHand = s.hand;
			lastHeld = s.held;
			lastBack = s.backDone;
		}
		let d = D();
		Vector3 off = d ? d.off : (0, 0, 0);
		Console.Printf("t%d %s [%s] %s state %s gun %s | %s %s held %d back %d pull %.1f s %.1f shells %d | off %.1f %.1f %.1f pitch %.0f steady %d trig %d grip %d",
			now, why, holdName, w ? w.GetClassName() : 'none', StateName(p), Layer(p, PSP_WEAPON),
			s ? RSP.ModeName(s.mode) : "?", s ? RSP.HandName(s.hand) : "?", s ? s.held : 0, s ? s.backDone : 0, s ? s.pull : 0, s ? s.s : 0, s ? s.shells : 0,
			off.x, off.y, off.z, d ? d.offPitch : 0, RSP.TestCvar('rsp_test_steady'), RSP.TestCvar('rsp_test_trigger'), d ? d.grip : 0);
		Console.Printf("   ammo %s %d reserve %d | WasEmpty %d HasUnloaded %d | casings %d dropped shells %d",
			magName, ammo, res, 0, 0, cas, drops);
		Console.Printf("   layers 2120 %s 2121 %s 2122 %s 2123 %s 2210 %s | 2200 %s 2101 %s 2100 %s",
			Layer(p, 2120), Layer(p, 2121), Layer(p, 2122), Layer(p, 2123), Layer(p, 2210), Layer(p, 2200), Layer(p, 2101), Layer(p, 2100));
	}
}
