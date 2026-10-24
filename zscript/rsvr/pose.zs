// THE POSE HISTORY -- the spine, 2026-10-24.
//
// From VR_MELEE_ON_QUESTZDOOM_2026-10-24.md section 9, which calls this "the single
// highest-leverage thing in the three codebases": a per-player object carrying samples of
// {point, pawn pos, pawn yaw, tic stamp}, with EVERYTHING downstream reading the history and
// nothing reading AttackPos / OffhandPos directly. "It makes the mod dt-correct, and it
// deletes the snap-turn and teleport special cases rather than tuning them."
//
// WHAT IT DELETES, and why that is the point. Every gesture test in this pack used to be
// `this tic's hand point minus last tic's`, which is wrong in three ways the document records
// as paid-for mistakes:
//
//   A TURN IS NOT A SWING. "World hand motion minus the pawn's position: a turn swings the arm
//   round the body with no translation to subtract" (BD22 1.4 -> 1.5 and 1.11). The pack's
//   answer was RSVR_HandMotion.Bogus(), which THROWS THE TIC AWAY when the yaw moved more than
//   10 degrees -- and the document's own trap table says why that fails: "an 8-deg/tic
//   snap-turn flush: a smooth-turn player above 280 deg/s trips it every tic, killing swings,
//   throws and glow prediction for the whole turn -- and below it, the turn is not subtracted
//   at all". Storing the hand IN THE PAWN'S OWN FRAME subtracts the turn exactly, at every
//   turn rate, and needs no threshold at all.
//
//   A TELEPORT IS NOT A SWING. The pawn's position is stored beside the hand, so a jump in it
//   is visible and that sample can be refused on the evidence instead of guessed at.
//
//   ONE TIC IS NOT A WINDOW. A velocity from one pair of samples cannot tell a swing from a
//   tracker glitch. With eight samples a caller can ask for displacement over a window, which
//   the document calls "the strongest single idea in the three mods' swing detectors".
//
// NOT NETWORKED. The document's version is fed by a once-a-tic netevent so every machine reads
// the same history. The owner's instruction for this pass was to skip the multiplayer work, so
// this fills from the local player's own fields -- which are, per the engine, only ever written
// for the viewing player anyway (hw_vrmodes.cpp:432-446). The shape is the networked one: if a
// netevent is ever added it feeds Push() and nothing downstream changes.
//
// UNITS. Everything returned is in the controller frame, real centimetres, with the vertical
// un-squashed: the engine divides the hand's Z by pixelstretch and not X or Y
// (hw_openxrdevice.cpp:595/608), so Z is multiplied back here, once, at the point of storage.
class RSVR_Pose play
{
	const N = 8;			// samples kept per hand, about a quarter second

	// flat arrays: [(player * 2 + hand) * N + slot]. Vector arrays are not allowed in ZScript
	// (the trap table: "Array<Vector3> is not allowed. Use three Array<double>"), and these are
	// fixed-size anyway.
	private Vector3 pt[MAXPLAYERS * 2 * N];		// hand, IN THE PAWN'S FRAME, cm
	private Vector3 org[MAXPLAYERS * 2 * N];	// where the pawn was, map units
	private int stamp[MAXPLAYERS * 2 * N];		// Level.maptime of the sample
	private int at[MAXPLAYERS * 2];				// newest slot
	private int got[MAXPLAYERS * 2];			// how many samples are real

	// RESULTS AS MEMBERS, NOT `out` PARAMETERS. The melee reference's very first trap:
	// "Multiple Vector3 returns and out Vector3 params are dropped -- silently zero, or a JIT
	// abort. SHIELD's hand orientation arrived as all zeros because of this; it now builds
	// axes in place and writes members." This file was written with three of them and the
	// engine answered exactly as promised: "Unexpected JIT error: Unknown REGT value passed to
	// EmitPARAM", three times. So the readers write here and the callers read it after a true.
	Vector3 sPt, sOrg;		// Sample()
	int sTic;
	Vector3 dStep;			// Delta()
	double dSecs;

	static RSVR_Pose Get()
	{
		return RSVR_Pose(StaticEventHandler.Find('RSVR_PoseKeeper')
			? RSVR_PoseKeeper(StaticEventHandler.Find('RSVR_PoseKeeper')).store : null);
	}

	static double Vu(PlayerPawn mo)
	{
		let c = CVar.GetCVar('vr_vunits_per_meter', mo.player);
		double v = c ? c.GetFloat() : 34.0;
		return v > 0 ? v : 34.0;
	}

	static double Ps(PlayerPawn mo)
	{
		double p = mo.Level.pixelstretch;
		return p > 0 ? p : 1.2;
	}

	// world point -> the pawn's own frame, in real cm. A yaw of the body does not move it.
	static Vector3 ToBody(PlayerPawn mo, Vector3 world)
	{
		Vector3 d = world - mo.pos;
		d.z *= Ps(mo);							// un-squash the vertical, once
		double a = -mo.angle;
		Vector3 r = (d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a), d.z);
		return r * 100.0 / Vu(mo);
	}

	// and back out, into the facing the player has NOW
	static Vector3 ToWorld(PlayerPawn mo, Vector3 body)
	{
		Vector3 d = body * Vu(mo) / 100.0;
		double a = mo.angle;
		return (d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a), d.z);
	}

	void Push(PlayerPawn mo, int hand, Vector3 world)
	{
		int n = mo.PlayerNumber();
		if (n < 0 || n >= MAXPLAYERS)
			return;
		int i = n * 2 + hand;
		at[i] = (at[i] + 1) % N;
		int s = i * N + at[i];
		pt[s] = ToBody(mo, world);
		org[s] = mo.pos;
		stamp[s] = mo.Level.maptime;
		if (got[i] < N)
			got[i]++;
	}

	// sample `back` tics old, in the pawn's frame. back 0 is this tic.
	// on true, sPt / sOrg / sTic hold the sample
	bool Sample(PlayerPawn mo, int hand, int back)
	{
		int n = mo.PlayerNumber();
		int i = n * 2 + hand;
		if (back < 0 || back >= got[i])
			return false;
		int s = i * N + ((at[i] - back) % N + N) % N;
		sPt = pt[s];
		sOrg = org[s];
		sTic = stamp[s];
		return true;
	}

	// How far the hand moved over the last `window` tics, in the pawn's frame, cm -- the turn
	// already removed because both ends are stored in that frame. Returns false when there is
	// no usable pair, so a caller can fall through rather than act on a zero.
	//
	// SELF-HEALING ON A TIC GAP, as the document asks: the real stamp gap is used, not the
	// requested one, so a dropped tic scales the speed correctly instead of halving it.
	// on true, dStep (cm, pawn frame) and dSecs hold the move over the window
	bool Delta(PlayerPawn mo, int hand, int window)
	{
		if (!Sample(mo, hand, 0))
			return false;
		Vector3 pNow = sPt, oNow = sOrg;
		int tNow = sTic;
		int back = window;
		while (back > 0 && !Sample(mo, hand, back))
			back--;
		if (back <= 0 || !Sample(mo, hand, back))
			return false;
		int dt = tNow - sTic;
		if (dt <= 0)
			return false;
		// A TELEPORT IS NOT A SWING: if the pawn jumped, this pair spans the jump. 64 map
		// units in a few tics is not walking.
		Vector3 jump = oNow - sOrg;
		if (jump.Length() > 64.0)
			return false;
		dStep = pNow - sPt;
		dSecs = dt / 35.0;
		return true;
	}

	// speed in cm per second over the window
	double Speed(PlayerPawn mo, int hand, int window)
	{
		if (!Delta(mo, hand, window))
			return 0.0;
		return dStep.Length() / dSecs;
	}

	// the path length actually walked over the window, cm -- the displacement test. A twitch
	// that goes out and comes back has a large Speed and a small Travel; a real swing has both.
	double Travel(PlayerPawn mo, int hand, int window)
	{
		int n = mo.PlayerNumber();
		int i = n * 2 + hand;
		double sum = 0;
		for (int k = 0; k < window && k + 1 < got[i]; k++)
		{
			if (!Sample(mo, hand, k))
				break;
			Vector3 a = sPt, oa = sOrg;
			if (!Sample(mo, hand, k + 1))
				break;
			Vector3 jump = oa - sOrg;
			if (jump.Length() > 64.0)
				break;
			Vector3 seg = a - sPt;
			sum += seg.Length();
		}
		return sum;
	}
}

// Fills it, once a tic, before anything reads it. A StaticEventHandler so the history survives
// a level change the way the document's does.
class RSVR_PoseKeeper : StaticEventHandler
{
	RSVR_Pose store;

	override void OnRegister()
	{
		store = new('RSVR_Pose');
	}

	override void WorldTick()
	{
		if (!store)
			store = new('RSVR_Pose');
		for (int n = 0; n < MAXPLAYERS; n++)
		{
			if (!playeringame[n] || !players[n].mo)
				continue;
			let mo = PlayerPawn(players[n].mo);
			if (!mo || !mo.player || !RSVR_VRHand.InVR(mo))
				continue;
			store.Push(mo, 0, RSVR_VRHand.HandPos(mo));
			store.Push(mo, 1, RSVR_VRHand.OffPos(mo));
		}
	}
}
