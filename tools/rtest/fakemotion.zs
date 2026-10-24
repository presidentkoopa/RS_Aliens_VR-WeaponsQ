// TEST ONLY: stands in for zscript/rsvr/handmotion.zs.
//
// WHY THIS FILE IS NEEDED AT ALL. The loader reads the arms' speed through
// RSVR_HandMotion.HandPos(), which returns mo.AttackPos / mo.OffhandPos -- the ENGINE's own
// fields, written only by a headset. fakehands.zs stands in for RSVR_VRHand, but not for
// these, so on a desktop run both booms sit perfectly still: armSpeed is 0 every tic, the
// swing threshold (ae_loader_swing, 14) is never crossed, and the melee cannot fire even
// though every line of it is reachable.
//
// So the hands are given a SWEEP here, driven off maptime, with no dependency on any test
// class -- the cvar is the whole interface, so this file and the drivers can be in different
// lumps and in any include order.
//
//   aet_swing   0  hands still, the engine's own fields (the production behaviour)
//               >0 both hands sweep, amplitude in cm; the speed scales with it
//   aet_period  tics for a full sweep. Speed is roughly 2*pi*amp/period cm per tic, so the
//               default 12 cm over 20 tics is ~3.8 cm/tic, comfortably over the 14 the
//               loader wants across its three-tic window.
//
// The sweep is a circle in the gun's own forward/up plane rather than a line, so the arm never
// stops dead and never reverses into a false "clunk" -- a line sweep registers a hard stop at
// each end, which is a different feature and would confuse the melee reading.
class RSVR_HandMotion play
{
	static double F(Name n, double def)
	{
		let c = CVar.FindCVar(n);
		return c ? c.GetFloat() : def;
	}

	static double Speed(Vector3 handStep, Vector3 bodyStep)
	{
		Vector3 d = handStep - bodyStep;
		double ps = 1.2;
		d.z *= ps;
		return d.Length() * 100.0 / 34.0;		// map units per tic -> real cm per tic
	}

	static bool Bogus(Vector3 handStep, double yawDelta)
	{
		return abs(yawDelta) > 10.0;			// a snap turn moves every hand; not a swing
	}

	static Vector3 HandPos(PlayerPawn mo, bool off)
	{
		double amp = F('aet_swing', 0.0);
		if (amp <= 0)
			return off ? mo.OffhandPos : mo.AttackPos;

		double per = max(F('aet_period', 20.0), 2.0);
		// the two arms sweep half a turn apart, so a test never has both stopping together
		double ph = 360.0 * (mo.Level.maptime / per) + (off ? 180.0 : 0.0);
		double vu = 34.0;
		Vector3 c = mo.pos + (cos(mo.angle) * 16, sin(mo.angle) * 16, 40);
		// forward and up in the player's frame, in map units
		Vector3 fwd = (cos(mo.angle), sin(mo.angle), 0);
		Vector3 up = (0, 0, 1);
		double r = amp * vu / 100.0;
		return c + fwd * (r * cos(ph)) + up * (r * sin(ph));
	}
}
