// TEST ONLY: stands in for zscript/rsvr/vrhand.zs, which says itself that "the headless test
// stands in for this file". Modelled on the kit's
// kit/kit/team/reload_merged/rtest/vrhand_rsr.zs, with its RSB_TestDriver branches removed --
// that is the break-open driver, this set has no break-open gun, and naming a class the pack
// does not define is a compile error rather than a silent miss.
//
// The gun hand is 16 units in front of the player at chest height, level, facing where the
// player faces. The off hand is a scripted "player" (RSR_TestDriver) that performs each step
// of a real reload with its position, its grip and its trigger:
//   the grip goes through the same path as a real key -- an rsr_grip network event, which is
//     what RSR_Handler.InputProcess sends;
//   the trigger is BT_OFFHANDATTACK added to this tic's usercmd buttons (Buttons below);
//   Steadied can be faked, because the engine sets WF_TWOHANDSTABILIZED only from a headset.
//
// Every signature here matches the production file one for one. That is not luck: this pack's
// zscript/rsr/vreload.zs was ported from the same BD22 1.92 source the kit's driver was
// written against, so the hand surface is the same eight statics.
class RSVR_VRHand play
{
	// In the real file this is `PlayInVR && OverrideAttackPosDir`, which only a headset sets.
	// Here it is simply "there is a player", which is what makes every VR-gated path in the
	// pack reachable without one.
	static bool InVR(PlayerPawn mo) { return mo && mo.player; }

	static Vector3 HandPos(PlayerPawn mo)
	{
		return mo.pos + (cos(mo.angle) * 16, sin(mo.angle) * 16, 40);
	}

	static Vector3 HandDir(PlayerPawn mo, double yaw, double pitch, double ps)
	{
		Vector3 d = (cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), sin(pitch));
		double a = mo.angle;
		return (d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a), d.z);
	}

	static Vector3 OffDir(PlayerPawn mo, double yaw, double pitch, double ps)
	{
		// the scripted off hand may be pitched about its own left axis (RSR_TestDriver.offPitch,
		// degrees, + up); 0 = the gun hand's frame
		let d = RSR_TestDriver(EventHandler.Find('RSR_TestDriver'));
		double op = d ? d.offPitch : 0;
		if (op == 0)
			return HandDir(mo, yaw, pitch, ps);
		Vector3 f = HandDir(mo, 0, 0, ps);
		Vector3 u = HandDir(mo, 0, 90, ps);
		if (pitch >= 89)
			return u * cos(op) - f * sin(op);
		if (yaw >= 89)
			return HandDir(mo, 90, 0, ps);
		return f * cos(op) + u * sin(op);
	}

	// the driver's off hand (cm, gun frame) -> world
	static Vector3 OffPos(PlayerPawn mo)
	{
		let d = RSR_TestDriver(EventHandler.Find('RSR_TestDriver'));
		Vector3 c = d ? d.off : (2.0, 10.0, -6.0);
		double ps = mo.Level.pixelstretch;
		if (ps <= 0)
			ps = 1.2;
		Vector3 w = HandDir(mo, 0, 0, ps) * c.x + HandDir(mo, 90, 0, ps) * c.y
		          + HandDir(mo, 0, 90, ps) * c.z;
		w *= 34.0 / 100.0;
		w.z /= ps;
		return HandPos(mo) + w;
	}

	static int Buttons(PlayerPawn mo)
	{
		let d = RSR_TestDriver(EventHandler.Find('RSR_TestDriver'));
		return mo.player.cmd.buttons | (d && d.trig ? BT_OFFHANDATTACK : 0);
	}

	static bool Steadied(PlayerPawn mo)
	{
		let d = RSR_TestDriver(EventHandler.Find('RSR_TestDriver'));
		return (mo.player.WeaponState & WF_TWOHANDSTABILIZED) != 0 || (d && d.steady);
	}

	// as the production one: OffPos - HandPos in real cm
	static double SteadyGap(PlayerPawn mo)
	{
		double ps = mo.Level.pixelstretch;
		if (ps <= 0)
			ps = 1.2;
		Vector3 w = OffPos(mo) - HandPos(mo);
		w.z *= ps;
		return w.Length() * 100.0 / 34.0;
	}
}
