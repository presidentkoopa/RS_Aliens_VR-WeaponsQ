// 2026-10-22 PULSE RIFLE: PUMP TO LOAD THE LAUNCHER (owner: "1 pump reduces ammo by 20 but
// loads 1 secondary fire"). The M41A's underbarrel launcher is loaded by working its pump by
// hand: the off hand takes the pump (off trigger within ae_glpump_grab cm of it), pulls it back
// ae_glpump_travel cm and brings it forward again. Each full stroke takes ae_glpump_cost rounds
// out of the magazine (PulseLoaded / YPulseLoaded) and puts one grenade in (GrenadeAmmo); the
// gun's own alt fire shoots it as before. The rifle plays its own pump frames (AE_GLPump state
// in actors/weapons/rifle.txt) when it is simply at ready. No stroke while a magazine reload
// has the off hand. Pump point: the m41a_pump surface's centre in the gun controller's frame
// (mesh x 31..46 -> F 42.5, U -8.5 with the rifle's 1.1 scale and the bolt's measured offset).
class RSQ_PumpGL : EventHandler
{
	bool held[MAXPLAYERS];
	double startF[MAXPLAYERS];
	bool back[MAXPLAYERS];
	bool trigPrev[MAXPLAYERS];

	static Vector3 PumpPoint() { return (42.5, 0.0, -8.5); }

	override void WorldTick()
	{
		for (int n = 0; n < MAXPLAYERS; n++)
		{
			if (!playeringame[n])
				continue;
			let p = players[n];
			let mo = p.mo;
			if (!mo || p.playerstate != PST_LIVE || !RSVR_VRHand.InVR(mo))
				continue;
			let w = p.ReadyWeapon;
			Name loaded = 'None';
			if (w is 'PulseRifle_3D') loaded = 'PulseLoaded';
			else if (w is 'YutaniRifle_3D') loaded = 'YPulseLoaded';
			bool trig = (p.cmd.buttons & RSR.GrabMask(p)) != 0;
			bool press = trig && !trigPrev[n];
			trigPrev[n] = trig;
			let rs = RSR_Handler.StateOf(mo);
			bool busy = rs && rs.phase != RSR.IDLE;
			if (loaded == 'None' || !(p.OffhandWeapon is 'RSQ_Hands') || busy || p.PendingWeapon != WP_NOCHANGE)
			{
				held[n] = false;
				continue;
			}
			Vector3 o = AE_SwitchHandler.GunFrame(mo);		// the off hand in the gun's frame: F, L, U cm
			double grab = RSR.Float('ae_glpump_grab', 14.0);
			double travel = RSR.Float('ae_glpump_travel', 6.0);
			if (!held[n])
			{
				if (trig && (o - PumpPoint()).Length() < grab)
				{
					held[n] = true;
					back[n] = false;
					startF[n] = o.x;
				}
				continue;
			}
			// holding the pump
			if (!trig || (o - PumpPoint()).Length() > grab * 2.0)
			{
				held[n] = false;
				continue;
			}
			double pull = startF[n] - o.x;		// cm back from where it was taken
			if (!back[n] && pull >= travel)
			{
				back[n] = true;
				mo.A_StartSound("PULSREL3", CHAN_AUTO, CHANF_OVERLAP);
			}
			else if (back[n] && pull <= travel * 0.3)
			{
				back[n] = false;
				Cycle(p, mo, w, loaded);
			}
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
		// the rifle's own pump frames, if it is simply at ready
		if (p.WeaponState & WF_WEAPONREADY)
		{
			State s = w.FindState('AE_GLPump');
			if (s)
				p.SetPsprite(PSP_WEAPON, s);
		}
	}
}
