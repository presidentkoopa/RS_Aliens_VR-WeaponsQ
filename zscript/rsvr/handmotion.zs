// RSVR_HandMotion -- how fast a hand is REALLY moving.
//
// Ported from UltraBadassQuestSaber (`zscript.txt` around :780-:930), which solved this on this
// exact engine and had the owner's bug reports beaten out of it. QuestZDoom exports no
// controller velocity, so speed has to be differenced per tic -- and the naive difference is
// wrong in three ways that the saber found the hard way:
//
//   1. WALKING IS NOT SWINGING. The hand's world position moves when the body moves. Subtract
//      the body's own step first, or every footstep reads as a swing (the owner, 10-01: "it
//      makes the swing sound every time i take a step").
//   2. A SNAP TURN IS NOT AN ATTACK. A turn moves the hand a long way in one tic through no
//      effort of the arm. Forget the history when the view yaw jumps (the owner, 10-01: "snap
//      turn registers as an attack").
//   3. ONE TIC IS TOO SHORT A WINDOW. Take the fastest of the last three single-tic steps, so a
//      quick flick counts as much as a long sweep.
//
// Everything here is PRESENTATION ONLY. It reads AttackPos/OffhandPos, which the engine writes
// only for the local player who is in VR (hw_vrmodes.cpp), so a value from here must never
// decide anything the playsim can see. Sound, haptics and where a model is drawn are fine;
// damage, movement and spawning are not -- those go through a net event, as vreload.zs does.
//
// General on purpose: named for what it does, usable by anything that needs a hand's speed.
class RSVR_HandMotion abstract
{
	// A hand that moves further than this in one tic has been teleported, snap-turned or
	// respawned rather than swung. The saber uses 48 map units; keep that.
	const JUMP = 48.0;

	// Degrees of view yaw change in one tic above which the motion history is worthless.
	const TURN = 8.0;

	// The hand's own travel, less the body's. Both arguments are this tic's minus last tic's.
	static double Speed(Vector3 handStep, Vector3 bodyStep)
	{
		return (handStep - bodyStep).Length();
	}

	// True when this tic's step cannot have come from an arm.
	static bool Bogus(Vector3 handStep, double yawDelta)
	{
		return handStep.Length() > JUMP || abs(yawDelta) > TURN;
	}

	// Where a hand is, in world units. Readonly engine fields; local player only.
	static Vector3 HandPos(PlayerPawn mo, bool off)
	{
		return off ? mo.OffhandPos : mo.AttackPos;
	}
}
