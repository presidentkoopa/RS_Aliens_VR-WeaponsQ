// 2026-10-22 PULSE RIFLE AMMO COUNTER (owner). The M41A's receiver has a two-digit LED window
// painted "88" on m41a.png. This draws the loaded count on it: layer RSQ_Layers.COUNTER on
// RSQ_GunSide (main controller) shows a quad over the window (MODELDEF.ae, models/weapons/
// rifle/counter.md3 + counter/c00..c99.png, 7-segment). The layer is placed by
// RSQ_Place.Layer with no hook, so it sits in the gun's model space and rides the gun's
// recoil like the gun hand. Values over 99 clamp to 99; the Yutani rifle counts YPulseLoaded.
class RSQ_Counter play abstract
{
	static void Tick(PlayerInfo p, PlayerPawn mo, Actor side)
	{
		let w = p.ReadyWeapon;
		Name loaded = 'None';
		if (w is 'PulseRifle_3D') loaded = 'PulseLoaded';
		else if (w is 'YutaniRifle_3D') loaded = 'YPulseLoaded';
		if (loaded == 'None' || !side || !RSVR_VRHand.InVR(mo) || p.PendingWeapon != WP_NOCHANGE)
		{
			RSQ_HandHandler.SetLayer(p, RSQ_Layers.COUNTER, null, "");
			return;
		}
		int n = clamp(mo.CountInv(loaded), 0, 99);
		RSQ_HandHandler.SetLayer(p, RSQ_Layers.COUNTER, side, String.Format("Cnt%02d", n));	// one state per value
	}
}

// the sprite names exist because an actor's states name them (MODELDEF binds frames to them)
class RSQ_CounterSprites : Actor
{
	States
	{
	Spawn:
		RSC0 ABCDEFGHIJKLMNOPQRSTUVWXYZ[\] 0;
		RSC1 ABCDEFGHIJKLMNOPQRSTUVWXYZ[\] 0;
		RSC2 ABCDEFGHIJKLMNOPQRSTUVWXYZ[\] 0;
		RSC3 ABCDEFGHIJKLM 0;
		Stop;
	}
}
