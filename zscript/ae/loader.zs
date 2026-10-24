// THE P-5000 POWER LOADER, step 1 of docs/DESIGN_2026-10-23_power_loader.md: it is heavy.
//
// Nothing is drawn differently here. What changes is that the machine has weight and answers
// your arms: it actually slows you down (for the first time -- see below), it hums and the hum
// tracks how fast you are moving the booms, the floor shakes when you walk, and an arm stopping
// hard clunks and kicks that controller.
//
// WHY THE SLOWDOWN IS NEW. `actors/weapons/mechloader.txt` has called `A_SetSpeed(0.7)` and
// `A_SetSpeed(0.35)` since it was written, and neither has ever done anything. PlayerPawn's
// MovePlayer reassigns Speed at the top of EVERY tic before using it:
//     player.zs:1374-1383   Speed = Default.Speed * 8   (VR, vr_momentum false by default)
//                           Speed = Default.Speed       (otherwise)
// so a value written from a weapon state is gone before it is read. Verified at 9afc750917.
// The TC's own `avw_speed_mult` is dead the same way (superhuman_attributes.txt writes
// pawn.Speed). The hook that WORKS is Inventory.GetSpeedFactor(), which MovePlayer multiplies
// over the whole inventory chain inside TweakSpeeds (player.zs:1313-1322) -- after the
// reassignment, on the movement itself. So the slowdown lives on a token, not in a state.
//
// ae_loader_speed is deliberately a SERVER cvar, not user. GetSpeedFactor runs inside
// MovePlayer for every player on every machine; if each machine had its own value the players
// would move differently on different machines. Movement is playsim, so it is server.
// The sound and haptic cvars below are user, because those are presentation.

// Layer ids. Verified clean against every id the pack uses: 2100, 2101, 2102-2104,
// 2120-2123, 2130, 2200, 2201, 2202, 2203, 2210. The 2300 band is untouched.
class AE_LoaderLayers abstract
{
	const ARM_MAIN = 2300;
	// There is deliberately no off-arm id here. A const of 2211 sat in this spot and
	// NOTHING ever read it: Arms() creates only ARM_MAIN, and hands.zs:694 draws the
	// left arm on RSQ_Hands' own free-hand layer (2200) with the AEArmL state. A
	// harness that checked 2211 reported "no off arm" on a loader that has one, and
	// that reached the owner as a pack bug. A constant nobody reads is worse than none.
	const BEACON   = 2304;
	// 2026-10-23 the cab cage over the operator's head. The design hangs this on the body
	// frame (step 7), but the owner cut the body and the legs, so it goes on a psprite layer
	// beside the beacon instead -- which it can, because loader_cage.md3 was carved out of
	// mechloader.md3 KEEPING ITS ORIGINAL COORDINATES, and the held mesh's origin is the
	// operator. Same mesh origin as the arms means the same MODELDEF Offset places it.
	const CAGE     = 2305;
}

// A SOUND COMES FROM THE THING THAT MAKES IT. "Playing sounds on the player: a metre-long
// blade's whoosh arrives from inside your chest, dead centre, the same whatever you do with
// your arm" -- the melee reference, three SABER commits. A 2.28 m boom is worse. This is a
// one-tic carrier to put a sound where the claw is; the document's "carried emitter at the
// thing that makes it" for a looping source is a bigger job and the hum is the only loop here.
class AE_LoaderNoise : Actor
{
	Default
	{
		Radius 1;
		Height 1;
		+NOBLOCKMAP +NOGRAVITY +NOINTERACTION +INVISIBLE
	}
	States
	{
	Spawn:
		TNT1 A 35;
		Stop;
	}
}

// The spark the cage throws when it eats a hit. mechaloader_spark.md3 already ships with the
// set; this is the actor that carries it, so no new art.
class AE_LoaderCageSpark : Actor
{
	Default
	{
		Radius 1;
		Height 1;
		// Normal, NOT Add. A model drawn with any non-Normal RenderStyle is drawn with no
		// depth test even at full alpha, so the spark mesh reads straight through walls --
		// and the arc now spawns up to four of these per strike, several times a second,
		// which turns that into a wall-hack. +BRIGHT already carries the hot look.
		RenderStyle "Normal";
		Alpha 1.0;
		Scale 0.7;
		+NOBLOCKMAP +NOGRAVITY +NOINTERACTION +BRIGHT +CLIENTSIDEONLY
	}
	States
	{
	Spawn:
		AESP ABCD 2 BRIGHT;
		Stop;
	}
}

class AE_LoaderWorn : Inventory
{
	Default
	{
		Inventory.MaxAmount 1;
		+INVENTORY.UNDROPPABLE
		+INVENTORY.UNTOSSABLE
		+INVENTORY.QUIET
	}

	// THE CAGE TAKES ITS SHARE. ModifyDamage runs on every item the victim is carrying
	// (inventory.zs), so the worn token is the right place for this -- no new actor, and it
	// stops the moment the loader comes off. Sparks are fired along the bearing the hit came
	// from, so you see where the cage saved you.
	override void ModifyDamage(int damage, Name damageType, out int newdamage, bool passive,
	                           Actor inflictor, Actor source, int flags)
	{
		if (!passive || damage <= 0 || !Owner)
			return;
		let cv = CVar.FindCVar('ae_loader_cage_absorb');
		double frac = clamp(cv ? cv.GetFloat() : 0.35, 0.0, 0.9);
		if (frac <= 0)
			return;
		int taken = int(damage * frac);
		if (taken <= 0)
			return;
		newdamage = max(1, damage - taken);		// never absorb a hit entirely

		// the bearing the blow came from, so the sparks land on the side that was struck
		Actor from = inflictor ? inflictor : source;
		double ang = from && from != Owner ? Owner.AngleTo(from) : Owner.angle;
		Owner.A_StartSound("ALIECLW1", CHAN_AUTO, CHANF_OVERLAP, 0.7);
		let sp = Owner.Spawn('AE_LoaderCageSpark',
			Owner.Vec3Angle(22.0, ang, Owner.height * 0.9), ALLOW_REPLACE);
		if (sp)
		{
			sp.target = Owner;
			sp.angle = ang;
		}
	}

	// The only hook that actually slows a VR player down. 1.0 is normal speed.
	override double GetSpeedFactor()
	{
		let cv = CVar.FindCVar('ae_loader_speed');
		double f = cv ? cv.GetFloat() : 0.35;
		return clamp(f, 0.10, 1.0);
	}

	States
	{
	// The rotating orange beacon. The sprite name exists because this state names it -- the
	// same trick RSQ_CounterSprites uses for the pulse rifle's counter, and the same one the
	// Doom patch uses for every sprite the TC owns. MODELDEF binds loader_lamp.md3 to this
	// class and this sprite (modeldef.loader.txt).
	Beacon:
		AELB A -1;
		Stop;
	// The cab cage. Same trick: the sprite name exists because this state names it.
	Cage:
		AELC A -1;
		Stop;
	Hidden:
		TNT1 A -1;
		Stop;
	}
}


// Owns the MAIN-controller arm layer. It must be an actor that is NEITHER the ready weapon nor
// the off-hand weapon: models.cpp:221 sends a layer to the off controller only when its caller
// IS the OffhandWeapon, so an inventory item puts it on the main controller.
class AE_LoaderArms : Inventory
{
	Default
	{
		Inventory.MaxAmount 1;
		+INVENTORY.UNDROPPABLE
		+INVENTORY.UNTOSSABLE
		+INVENTORY.QUIET
	}
	States
	{
	// FIFTEEN FRAMES EACH, 2026-10-24. loader_arm_r.md3 and loader_arm_l.md3 carry 21 frames
	// and MODELDEF bound exactly one, so both booms were drawn frozen at frame 0 while the
	// melee swung. Frames 0..14 are a complete punch: travel peaks at 6 and is back by 14
	// (15..20 are padding identical to 0, measured with the kit's md3read). A sprite frame
	// only exists if a state names it, and a MODELDEF FrameIndex for a frame no state names
	// is silently never drawn -- so all fifteen are named here, and the handler picks one with
	// psp.Frame, exactly as vreload.zs does for the gun's own slide frames.
	ArmR:
		AEAR ABCDEFGHIJKLMNOPQRSTU -1;
		Stop;
	ArmL:
		AEAL ABCDEFGHIJKLMNOPQRSTU -1;
		Stop;
	}
}

class AE_LoaderHandler : EventHandler
{
	// the loader classes this applies to
	static bool IsLoader(Weapon w)
	{
		return w && (w is 'Loader_3D' || w is 'AELoader_3D');
	}

	static bool ArmsOn()
	{
		let c = CVar.FindCVar('ae_loader_arms');
		return !c || c.GetFloat() > 0;
	}

	static bool Worn(PlayerPawn mo)
	{
		return mo && mo.player && IsLoader(mo.player.ReadyWeapon);
	}

	// --- per-player state. Flat arrays: index [n*2 + hand], hand 0 = main, 1 = off. -------
	Vector3 handPrev[MAXPLAYERS * 2];
	double  spRing[MAXPLAYERS * 2 * 3];		// the last three single-tic speeds
	double  spWas[MAXPLAYERS * 2];			// last tic's chosen speed, for the clunk edge
	int     quiet[MAXPLAYERS * 2];			// clunk rate limit
	Vector3 bodyPrev[MAXPLAYERS];
	double  yawPrev[MAXPLAYERS];
	double  step[MAXPLAYERS];				// footstep phase accumulator
	bool    hadPose[MAXPLAYERS];
	bool    humming[MAXPLAYERS];
	int     quakes[MAXPLAYERS];

	// STEP 4, MASS THROUGH LAG. A ring of each hand's AIM. Lagging the aim needs no frame
	// conversion -- the engine already draws the arm at the hand, and a turn added on top via
	// psp.x/y points it where the hand pointed N tics ago.
	//
	// DEFAULT OFF. The first version of this shipped at 3 tics and the owner's verdict was that
	// it looked like a cloned model that could not keep up with itself -- which is exactly what
	// pivoting a 2.28 m boom by a few degrees about its own origin looks like: the far end
	// travels a long way for a small angle. The mechanism is here and tunable; it stays at zero
	// until he dials it up, because a default nobody asked for that makes the thing look broken
	// is worse than no feature.
	const RING = 12;
	double  aimYaw[MAXPLAYERS * 2 * RING];
	double  aimPit[MAXPLAYERS * 2 * RING];
	int     ringAt[MAXPLAYERS * 2];
	bool    ringUp[MAXPLAYERS * 2];

	// STEP 5, THE CLAW. Closure per hand, 0..1, and the swing rate limit.
	double  clawShut[MAXPLAYERS * 2];	// 0..1. NOT 'claw': ZScript identifiers are
										// case-insensitive, so it would collide with Claw().
	int     swingQuiet[MAXPLAYERS * 2];
	// NOT 'punch': ZScript identifiers are CASE-INSENSITIVE, so a field punch[] and a
	// method Punch() are the same name -- "Attempt to redefine 'Punch'". The fifth time
	// this project has hit it (claw/Claw(), look/Look(), pull/Pull(), held/held).
	int     punchAt[MAXPLAYERS * 2];
	int     work[MAXPLAYERS * 2];		// 1 while that boom is welding or burning	// tics left of the arm's punch animation, 0 = at rest

	// STEP 6, GRAB / CARRY / THROW / PIN / CRUSH.
	bool    ramPrev[MAXPLAYERS * 2];	// alt fire was down last tic
	int     ramQuiet[MAXPLAYERS * 2];	// tics before this arm may ram again
	Actor   held[MAXPLAYERS * 2];
	int     crushFor[MAXPLAYERS * 2];

	// THE OFF ARM'S OWN TOOLS, 2026-10-23. The real P-5000's left boom carries the welding
	// gear, so that arm is not a second claw: trigger is the arc, alt fire is the torch.
	int     arcQuiet[MAXPLAYERS];		// tics before the arc may strike again
	int     flameAt[MAXPLAYERS];		// tics until the next flame puff
	bool    arcOn[MAXPLAYERS];			// the arc was lit last tic, for the loop sound edge
	bool    flameOn[MAXPLAYERS];
	bool    heldGrav[MAXPLAYERS * 2];
	bool    heldPain[MAXPLAYERS * 2];	// we put this one in its Pain frame; put it back
	Vector3 clawPrev[MAXPLAYERS * 2];
	// thrown things, so a thrown body hurts what it lands on
	Array<Actor> flung;
	Array<double> flungWas;				// diagnostic: footsteps actually fired
	double  spin[MAXPLAYERS];				// beacon yaw, degrees
	static double F(Name n, double def)
	{
		let c = CVar.FindCVar(n);
		return c ? c.GetFloat() : def;
	}

	override void WorldTick()
	{
		TickFlung();

		for (int n = 0; n < MAXPLAYERS; n++)
		{
			if (!playeringame[n] || !players[n].mo)
				continue;
			let mo = PlayerPawn(players[n].mo);
			if (!mo)
				continue;
			let p = mo.player;

			bool worn = Worn(mo);
			Token(mo, worn);

			// ae_loader_debug 3 is a SELF TEST for grab/carry/crush, because grabbing needs
			// hand poses and a headless run has none. It drops a barrel in front of the
			// player, fires the real net event at it, and the line below reports whether it
			// was taken. The whole path -- event, search, filter, Take, Carry -- is exercised.
			if (F('ae_loader_debug', 0.0) >= 3 && worn && level.maptime == 70)
			{
				Vector3 at = mo.pos + (cos(mo.angle), sin(mo.angle), 0) * 48.0;
				Actor b = Actor.Spawn('ExplosiveBarrel', at);
				if (b)
					EventHandler.SendNetworkEvent("ae_grab", int(at.x * 8), int(at.y * 8),
					                              int(at.z * 8) << 1);
			}

			// One-shot ammo report: what the ready weapon actually uses and what the player
			// actually has. Built to answer "are the ammo types fucked up" with facts.
			if (F('ae_loader_debug', 0.0) > 0 && level.maptime == 70)
			{
				let w = p.ReadyWeapon;
				Console.Printf("AMMO ready=%s type1=%s(%d) type2=%s(%d)",
					w ? w.GetClassName() : 'none',
					w && w.Ammo1 ? w.Ammo1.GetClassName() : 'none',
					w && w.Ammo1 ? w.Ammo1.Amount : -1,
					w && w.Ammo2 ? w.Ammo2.GetClassName() : 'none',
					w && w.Ammo2 ? w.Ammo2.Amount : -1);
				for (let inv = mo.Inv; inv; inv = inv.Inv)
					if (inv is 'Ammo')
						Console.Printf("AMMO   have %-24s %d", inv.GetClassName(), inv.Amount);
			}

			// TEMPORARY, 2026-10-23: ae_loader_debug 1 prints what this handler actually sees,
			// once a second. Built because "nothing happens in game" needs a fact, not a guess.
			if (F('ae_loader_debug', 0.0) > 0 && (level.maptime % 35) == 0)
			{
				let tok = mo.FindInventory('AE_LoaderWorn');
				Console.Printf("LOADER n=%d ready=%s worn=%d token=%d invr=%d speedfactor=%.2f beacon=%d spin=%.0f steps=%d arms=%d/%d held=%s",
					n, p.ReadyWeapon ? p.ReadyWeapon.GetClassName() : 'none',
					worn, tok ? 1 : 0, RSVR_VRHand.InVR(mo) ? 1 : 0,
					tok ? tok.GetSpeedFactor() : -1.0,
					p.FindPSprite(AE_LoaderLayers.BEACON) ? 1 : 0, spin[n], quakes[n],
					p.FindPSprite(AE_LoaderLayers.ARM_MAIN) ? 1 : 0,
					p.FindPSprite(RSQ_Layers.FREEHAND) ? 1 : 0,
					held[n * 2] ? held[n * 2].GetClassName() : 'none');
			}

			if (!worn || mo.health <= 0)
			{
				Hush(mo, n);
				hadPose[n] = false;
				continue;
			}

			// ae_loader_debug 2 shoves the player along from script so the footstep path can be
			// exercised with no input at all. A command-line +forward does not hold a key down,
			// and a feature nobody can test without a headset on gets shipped broken.
			if (F('ae_loader_debug', 0.0) >= 2 && mo.player && mo.player.onground)
				mo.vel.xy = (cos(mo.angle), sin(mo.angle)) * 6.0;	// forward, not world east

			for (int h = 0; h < 2; h++)
			{
				int ci = n * 2 + h;
				if (held[ci])
					Carry(mo, ci, RSVR_VRHand.InVR(mo) ? ClawPoint(mo, h == 1)
					                                   : held[ci].pos);
			}

			Footsteps(mo, n);
			// The beacon is bolted to the machine, not to your hands: it must NOT sit behind
			// the "are we in VR" gate below. It was, which is why it never appeared.
			Beacon(mo, n);
			// Arms() needs no hand DATA -- each layer reaches the right controller purely by
			// its caller -- so like the beacon it must not sit behind the VR gate below.
			Arms(mo, n);
			// The cage is bolted to the machine too: no hand data, so it goes above the gate
			// with the beacon and the arms.
			Cage(mo, n);

			// Everything below reads AttackPos/OffhandPos, which exist only for a local VR
			// player. Desktop and remote players get the weight and the shake but no arm
			// sounds -- which is correct, because they have no arms to move.
			if (!RSVR_VRHand.InVR(mo))
			{
				Hush(mo, n);
				hadPose[n] = false;
				continue;
			}

			Vector3 body = mo.pos;
			Vector3 bodyStep = hadPose[n] ? body - bodyPrev[n] : (0, 0, 0);
			// deltaangle() is not visible from an EventHandler, so wrap it here. We only need
			// the magnitude, to notice a snap turn.
			double yawDelta = 0.0;
			if (hadPose[n])
			{
				yawDelta = mo.angle - yawPrev[n];
				while (yawDelta > 180.0)
					yawDelta -= 360.0;
				while (yawDelta < -180.0)
					yawDelta += 360.0;
			}

			double loud = 0.0;
			for (int h = 0; h < 2; h++)
			{
				int i = n * 2 + h;
				Vector3 cur = RSVR_HandMotion.HandPos(mo, h == 1);
				double s = 0.0;
				if (hadPose[n])
				{
					Vector3 hs = cur - handPrev[i];
					s = RSVR_HandMotion.Bogus(hs, yawDelta)
					    ? 0.0 : RSVR_HandMotion.Speed(hs, bodyStep);
				}
				handPrev[i] = cur;

				// fastest of the last three tics, so a flick counts like a sweep
				spRing[i * 3 + 2] = spRing[i * 3 + 1];
				spRing[i * 3 + 1] = spRing[i * 3 + 0];
				spRing[i * 3 + 0] = s;
				double best = max(spRing[i * 3 + 0], max(spRing[i * 3 + 1], spRing[i * 3 + 2]));

				Clunk(mo, i, best, h == 1);
				// THE TWO ARMS ARE NOT THE SAME ARM, 2026-10-23 (owner: "PRIMARY MAINHAND
				// GRAB / CRUSH / ALTFIRE THROW ... OFFHAND MAIN ATTACK ELECTRICAL ARC,
				// SECONDARY ATTACK FLAMETHROWER, WITH REAL MELEE SWINGING").
				//
				// Claw() sits OUTSIDE the split on purpose: both booms swing, on their own
				// measured speed, with no animation and no button. That is the melee.
				Claw(mo, n, best, h);
				if (h == 0)
				{
					HandGrab(mo, n, 0, best);	// trigger: close, carry, crush
					Fling(mo, n, 0);			// alt fire: throw what it holds
				}
				else
				{
					Arc(mo, n);					// trigger: the welding arc
					Flame(mo, n);				// alt fire: the cutting torch
				}
				loud = max(loud, best);
			}

			bodyPrev[n] = body;
			yawPrev[n] = mo.angle;
			hadPose[n] = true;

			Hum(mo, n, loud);
			ArmLag(mo, n);
		}
	}

	// Give the worn token while the loader is up, take it the moment it is not. Doing this
	// from the handler rather than the weapon's Select/Deselect states means it cannot be
	// stranded by a death, a level change or any switch path the TC takes that we do not know
	// about -- a flag set and never cleared is the bug that outlives the session.
	void Token(PlayerPawn mo, bool worn)
	{
		let has = mo.FindInventory('AE_LoaderWorn');
		if (worn && !has)
			mo.GiveInventory('AE_LoaderWorn', 1);
		else if (!worn && has)
			mo.TakeInventory('AE_LoaderWorn', 1);
	}

	// A_Quake with damrad 0 so it can never hurt anyone. Driven by mo.vel, which IS playsim,
	// so this is deterministic on every machine and needs no net event -- and everyone inside
	// tremrad feels the loader coming, which is free and correct.
	void Footsteps(PlayerPawn mo, int n)
	{
		if (!mo.player || !mo.player.onground)
		{
			step[n] = 0.0;
			return;
		}
		double gap = F('ae_loader_stride', 42.0);
		if (gap < 4.0)
			return;
		double sp = mo.vel.xy.Length();
		if (sp < 0.5)
		{
			step[n] = 0.0;
			return;
		}
		step[n] += sp;
		if (step[n] < gap)
			return;
		step[n] -= gap;
		double q = F('ae_loader_quake', 1.0);
		if (q <= 0)
			return;
		int inten = int(clamp(1.0 + sp / 12.0, 1.0, 3.0) * q);
		if (inten > 0)
		{
			mo.A_Quake(inten, 6, 0, 256, "");
			quakes[n]++;
		}
	}

	// The hum is re-asserted EVERY tic. Two lessons copied verbatim from the saber, both of
	// which cost it a round of bug reports: a volume set only where the loop starts silently
	// reverts, so it must be re-set every tic; and zero volume must STOP the channel, because
	// SoundEngine::StartSound refuses volume <= 0 and a loop started at zero leaves no channel
	// for the re-assert to act on.
	void Hum(PlayerPawn mo, int n, double armSpeed)
	{
		double vol = F('ae_loader_hum', 0.0);
		if (vol <= 0.0)
		{
			Hush(mo, n);
			return;
		}
		if (!humming[n])
		{
			mo.A_StartSound("ae/loaderhum", CHAN_7, CHANF_LOOPING, vol);
			humming[n] = true;
		}
		mo.A_SoundVolume(CHAN_7, vol);
		double ref = max(F('ae_loader_hum_ref', 90.0), 1.0);
		mo.A_SoundPitch(CHAN_7, 1.0 + clamp((armSpeed - 6.0) / ref, 0.0, 0.3));
	}

	// THE ROTATING BEACON. The mesh (loader_lamp.md3, one surface named loader_alarm), its
	// brightmap (gldefs.txt:13) and a PointLight (gldefs.txt:18) all already ship -- and all
	// three are attached to `Frame CSAWP`, the PICKUP's sprite frame. So the loader lying on
	// the floor has a glowing spinning beacon and the one you are wearing has nothing.
	//
	// MDL_ROTATING is world-path only (models.cpp:116-128); RenderHUDModel has no rotation
	// handling at all. The way to turn a HUD model from play is psp.x, which hw_weapon.cpp:108
	// reads back as model yaw in QUARTER degrees. oldx must be carried by hand: nothing in the
	// playsim advances it (p_pspr.h:114 is its only writer), so leaving it pins the beacon's
	// interpolation to zero and it judders instead of spinning. This pack has made that exact
	// mistake once already, in the dual-wield recoil follow.
	//
	// The light goes on the PAWN, not the layer -- a psprite has no sprite frame for GLDEFS to
	// key on, which is the diagnosis of why the worn loader never lit anything. Because HUD
	// models gather light from around the player (hw_weapon.cpp:988), a light on the pawn
	// washes orange across the arms, which is most of the effect.
	// THE CAB CAGE. Shown while the loader is worn and taken away when it is not. It needs no
	// hand data and no body frame -- the mesh keeps mechloader.md3's own coordinates and that
	// mesh's origin is the operator, so the layer simply draws it where it already belongs.
	void Cage(PlayerPawn mo, int n)
	{
		let p = mo.player;
		let psp = p.FindPSprite(AE_LoaderLayers.CAGE);
		bool on = F('ae_loader_cage', 1.0) > 0 && mo.FindInventory('AE_LoaderWorn');
		if (!on)
		{
			if (psp)
				p.SetPsprite(AE_LoaderLayers.CAGE, null);
			return;
		}
		if (psp)
			return;
		let worn = mo.FindInventory('AE_LoaderWorn');
		p.SetPsprite(AE_LoaderLayers.CAGE, worn.FindState('Cage'), false, worn);
		psp = p.FindPSprite(AE_LoaderLayers.CAGE);
		if (!psp)
			return;
		// it does not bob and it does not swing with the gun: it is part of the cab
		psp.bAddWeapon = false;
		psp.bAddBob = false;
		psp.y = WEAPONTOP;
		psp.oldy = psp.y;
		psp.x = 0;
		psp.oldx = 0;
	}

	void Beacon(PlayerPawn mo, int n)
	{
		let p = mo.player;
		bool on = F('ae_loader_beacon', 1.0) > 0;
		let psp = p.FindPSprite(AE_LoaderLayers.BEACON);

		if (!on)
		{
			if (psp)
				p.SetPsprite(AE_LoaderLayers.BEACON, null);
			mo.A_RemoveLight('aeloaderbeacon');
			return;
		}

		let worn = mo.FindInventory('AE_LoaderWorn');
		if (!worn)
			return;

		if (!psp)
		{
			p.SetPsprite(AE_LoaderLayers.BEACON, worn.FindState('Beacon'), false, worn);
			psp = p.FindPSprite(AE_LoaderLayers.BEACON);
			if (!psp)
				return;
			psp.bAddWeapon = false;
			psp.bAddBob = false;
			psp.y = WEAPONTOP;
			psp.oldy = psp.y;
			psp.x = 0;
			psp.oldx = 0;
			spin[n] = 0;
			mo.A_AttachLight('aeloaderbeacon', DynamicLight.PointLight, 0xFF7814,
			                 int(F('ae_loader_beacon_radius', 96.0)), 0, 0, (0, 0, 40));
		}

		// 90 rpm = 540 deg/s = 15.43 deg per tic. psp.x is yaw in quarter-degrees.
		double rpm = clamp(F('ae_loader_beacon_rpm', 90.0), 0.0, 600.0);
		spin[n] = (spin[n] + rpm * 6.0 / TICRATE) % 360.0;
		psp.oldx = psp.x;
		psp.x = spin[n] * 4.0;
	}



	// THE TWO ARMS, one per controller. Which controller a layer lands on is decided purely by
	// its CALLER (models.cpp:221): AE_LoaderArms is an inventory item so its layer draws on the
	// main controller; RSQ_Hands IS the off-hand weapon so its layer draws on the off one.
	// Both are "not the ready weapon's" layers, so hw_weapon.cpp:332 routes them through the
	// off-hand weapon's psprite and :943 finds ModifyBobLayer3D on RSQ_Hands, which overrides
	// it -- so unlike dual wield, both arms are placeable from script.
	//
	// The old single held model is not removed: its psprite keeps running the TC's own state
	// machine, which we do not own. It is just drawn at zero alpha, and gets its alpha back the
	// moment the loader is put away.
	void Arms(PlayerPawn mo, int n)
	{
		let p = mo.player;
		bool on = F('ae_loader_arms', 1.0) > 0;

		let gun = p.FindPSprite(PSP_WEAPON);
		if (gun)
			gun.alpha = on ? 0.0 : 1.0;

		if (!on)
		{
			if (p.FindPSprite(AE_LoaderLayers.ARM_MAIN))
				p.SetPsprite(AE_LoaderLayers.ARM_MAIN, null);
			return;
		}

		let arms = mo.FindInventory('AE_LoaderArms');
		if (!arms)
		{
			mo.GiveInventory('AE_LoaderArms', 1);
			arms = mo.FindInventory('AE_LoaderArms');
			if (!arms)
				return;
		}
		let hands = mo.FindInventory('RSQ_Hands');
		if (!hands)
			return;

		// the LEFT arm is drawn by hands.zs on RSQ_Hands' own free-hand layer
		Arm(p, AE_LoaderLayers.ARM_MAIN, Actor(arms), arms, "ArmR");
		Punch(p, n);
	}

	// THE SWING IS DRAWN, 2026-10-24. Until now Claw() landed 180 damage with both booms
	// motionless, because MODELDEF bound one frame of the 21 each arm mesh carries. Frames
	// 0..14 are the punch; this plays them over the same gap that rate-limits the swing, so
	// the animation is exactly as long as the swing it belongs to and can never overlap the
	// next one. Presentation only: it reads a counter the swing already set and touches no
	// damage, no event and nothing another machine needs to agree about.
	void Punch(PlayerInfo p, int n)
	{
		double gap = max(F('ae_loader_swing_gap', 12.0), 1.0);
		for (int h = 0; h < 2; h++)
		{
			int i = n * 2 + h;
			if (punchAt[i] > 0)
				punchAt[i]--;
			// the main boom is ours; the left one is on RSQ_Hands' free-hand layer
			let psp = p.FindPSprite(h == 0 ? AE_LoaderLayers.ARM_MAIN : RSQ_Layers.FREEHAND);
			if (!psp)
				continue;
			// only drive the free-hand layer while it really is showing the arm -- with the
			// loader off it is an ordinary hand and its frame is not ours to set
			if (h == 1 && psp.Sprite != Actor.GetSpriteIndex('AEAL'))
				continue;
			// A PUNCH OVERRIDES THE GRIP POSE: an arm cannot be swinging and holding at the
			// same time, and the punch is the bigger motion. Sprite frames A..O (0..14) are
			// the punch; P..U (15..20) are the jaws closing, model frames 21..26, added by
			// tools/claw_rig.py. clawShut is already 0..1 on the grab and >= 0.98 on the
			// crush, so it indexes the six straight off.
			int fr = 0;
			if (punchAt[i] > 0)
				fr = clamp(int(14.0 * (1.0 - punchAt[i] / gap) + 0.5), 0, 14);
			else if (work[i] > 0)
			{
				// welding or burning: stir frames 0..4 on a 16-tic cycle, a working boom
				int ph = (Level.maptime % 16);
				fr = ph < 8 ? ph / 2 : (15 - ph) / 2;
				work[i] = 0;		// set again next tic for as long as the button is held
			}
			else if (clawShut[i] > 0.02)
				fr = 15 + clamp(int(clawShut[i] * 5.0 + 0.5), 0, 5);
			if (psp.Frame != fr)
				psp.Frame = fr;
		}
	}

	void Arm(PlayerInfo p, int id, Actor caller, Actor stateOwner, String label)
	{
		// FindStateByString, as the pack's own SetLayer does -- FindState wants a StateLabel.
		State want = stateOwner.FindStateByString(label);
		let psp = p.FindPSprite(id);
		if (psp && psp.Caller == caller && psp.CurState == want)
			return;
		p.SetPsprite(id, want, false, caller);
		psp = p.FindPSprite(id);
		if (!psp)
		{
			if (F('ae_loader_debug', 0.0) > 0)
				Console.Printf("LOADER arm layer %d REFUSED: caller=%s state=%s offhand=%s",
					id, caller ? caller.GetClassName() : 'null',
					want ? "ok" : "null",
					p.OffhandWeapon ? p.OffhandWeapon.GetClassName() : 'none');
			return;
		}
		psp.bAddWeapon = false;
		psp.bAddBob = true;
		psp.y = WEAPONTOP;		// y 0 tilts a HUD model 8 degrees
		psp.oldy = psp.y;
	}


	// Push this tic's aim into the ring and return the lagged turn, relative to where the hand
	// points NOW. Overshoot carries the last step past the target.
	void Lag(PlayerPawn mo, int i, bool off, out double dYaw, out double dPit)
	{
		dYaw = 0; dPit = 0;
		// AttackDir/OffhandDir take (actor, angle, pitch) and return ANGLES: .x yaw, .y pitch,
		// already including the engine's mirror of the off controller (vrhand.zs:40, :54).
		Vector3 ap = off ? mo.OffhandDir(mo, mo.angle, mo.pitch)
		                 : mo.AttackDir(mo, mo.angle, mo.pitch);
		double yaw = ap.x, pit = ap.y;

		int at = ringAt[i];
		aimYaw[i * RING + at] = yaw;
		aimPit[i * RING + at] = pit;
		ringAt[i] = (at + 1) % RING;
		if (!ringUp[i])
		{
			for (int k = 0; k < RING; k++)
			{
				aimYaw[i * RING + k] = yaw;
				aimPit[i * RING + k] = pit;
			}
			ringUp[i] = true;
			return;
		}

		int lag = int(clamp(F('ae_loader_lag', 0.0), 0.0, RING - 2));
		if (lag <= 0)
			return;
		int old = ((at - lag) % RING + RING) % RING;
		int older = ((at - lag - 1) % RING + RING) % RING;
		double oy = aimYaw[i * RING + old], op = aimPit[i * RING + old];
		double over = clamp(F('ae_loader_overshoot', 0.0), 0.0, 1.5);
		oy += Wrap(oy - aimYaw[i * RING + older]) * over;
		op += (op - aimPit[i * RING + older]) * over;
		dYaw = Wrap(oy - yaw);
		dPit = op - pit;
	}

	static double Wrap(double a)
	{
		while (a > 180.0)
			a -= 360.0;
		while (a < -180.0)
			a += 360.0;
		return a;
	}

	// Apply the lag to whichever arm layers exist. Costs nothing while ae_loader_lag is 0.
	void ArmLag(PlayerPawn mo, int n)
	{
		if (F('ae_loader_lag', 0.0) <= 0)
			return;
		let p = mo.player;
		for (int h = 0; h < 2; h++)
		{
			let ap = p.FindPSprite(h == 0 ? AE_LoaderLayers.ARM_MAIN : RSQ_Layers.FREEHAND);
			if (!ap)
				continue;
			double dy, dp;
			Lag(mo, n * 2 + h, h == 1, dy, dp);
			// oldx/oldy carried by hand: nothing in the playsim advances them (p_pspr.h:114),
			// so leaving them makes the turn ramp from zero inside every tic -- a shake.
			ap.oldx = ap.x;
			ap.oldy = ap.y;
			ap.x = dy * 4.0;
			ap.y = WEAPONTOP - dp * 4.0;
		}
	}


	// THE CLAW. Three things, and the third is the point of it.
	//
	// 1. CLOSURE. QuestZDoom exports no analogue trigger -- UserCmd is `buttons` plus six
	//    int16s and neither is a trigger axis -- so closure is driven by how long the trigger
	//    is HELD, 0 to 1 over ae_loader_claw_tics. What matters is that it is analogue in the
	//    dimension you can see: the jaws are at a continuous position.
	// 2. WHERE THE CLAW IS. The arm reaches 228 model units, which at the pack's own scale is
	//    about 72 map units -- the same number the TC's own A_CustomPunch(500, 72) used, so
	//    whoever wrote that had measured the same arm. The claw point is the hand's position
	//    plus that reach along the hand's own direction.
	// 3. DAMAGE WHERE THE CLAW IS, not down a line from your face. That is the whole
	//    difference between a mech arm and a punch.
	//
	// NETPLAY. AttackPos/OffhandPos are written only for the local VR player, so the detection
	// here is local and must never touch the playsim directly. It sends the claw POINT as a net
	// event and every machine runs the same search against it -- no actor ids, no lookup table,
	// the same answer everywhere. That is the shape vreload.zs uses for its grip key.
	void Claw(PlayerPawn mo, int n, double armSpeed, int h)
	{
		int i = n * 2 + h;
		if (swingQuiet[i] > 0)
			swingQuiet[i]--;

		let p = mo.player;
		// INPUT COMES THROUGH RSVR_VRHand.Buttons(), 2026-10-23. These five reads were
		// `p.cmd.buttons` direct. In production that is exactly what Buttons() returns, so
		// nothing changes -- but it is also the seam the whole reload path reads input
		// through, and reading the usercmd raw here meant the loader was the one subsystem
		// no harness could drive. Its first scripted run proved the melee and then could not
		// press a single button. One accessor for input, as the rest of the pack already has.
		//
		// Only the MAIN arm's trigger works a claw. The off arm's trigger is the arc, and
		// closing a claw on it would have that boom grabbing while it welds.
		bool squeeze = h == 0 && (RSVR_VRHand.Buttons(mo) & BT_ATTACK) != 0;
		double tics = max(F('ae_loader_claw_tics', 7.0), 1.0);
		clawShut[i] = clamp(clawShut[i] + (squeeze ? 1.0 : -1.0) / tics, 0.0, 1.0);

		// A swing lands when the claw is moving fast enough. The threshold is higher than the
		// saber's 8.0 because the claw sits on a 2.28 m boom: the same wrist turn moves it more
		// than twice as far, and a mech swing should be slower than a lightsaber flourish.
		// A BACKSWING IS NOT A STRIKE, and SPEED ALONE IS NOT A SWING. 2026-10-24, straight
		// out of VR_MELEE_ON_QUESTZDOOM_2026-10-24.md section 1.4, which is BD22's gate after
		// three owner reports: "the test used to be speed alone, so raising the axe to strike
		// was itself a hit -- it landed before the player had swung, and read as the axe being
		// wildly oversensitive". This claw had exactly that test and nothing else.
		//
		// Two gates, both from that document:
		//   DIRECTION. Motion that is mostly upward is a wind-up. BD22 ended at "must point
		//     DOWN by 0.25 of its speed" for an axe; a loader also sweeps level at something
		//     in front of it, so the default here is 0.0 -- level or down cuts, rising never
		//     does -- and ae_loader_swing_down tightens it to BD22's 0.25 if wanted.
		//   DISPLACEMENT. "The strongest single idea in the three mods' swing detectors ... a
		//     displacement test layered on a velocity test, immune to exactly the thing a
		//     velocity test cannot see: a twitch, a tracker glitch, or one noisy sample." The
		//     boom must have TRAVELLED, not merely moved fast for one sample.
		// ON ITS OWN LINE: "ZScript will not dereference .z off a parenthesised expression"
		// -- the same reference's trap table, and it rejected this exact line first time with
		// "Unable to dereference left side of Z".
		Vector3 hNow = RSVR_HandMotion.HandPos(mo, h == 1);
		double dz = hNow.z - handPrev[i].z;
		double rise = armSpeed > 0 ? dz * 100.0 * 1.2 / 34.0 / armSpeed : 0;
		if (rise > -clamp(F('ae_loader_swing_down', 0.0), 0.0, 0.9))
			return;
		double travel = spRing[i * 3 + 0] + spRing[i * 3 + 1] + spRing[i * 3 + 2];
		if (travel < F('ae_loader_swing_len', 24.0))
			return;

		// An arm with something in its claw does not swing at it. The carried object sits AT
		// the claw point by construction (Carry()), so a fast sweep put it inside its own
		// swing: a barrel went off in your hand, and anything you picked up alive died on the
		// first quick movement. The ram already refused to fire while holding; so does this.
		if (held[i])
			return;

		double cut = F('ae_loader_swing', 14.0);
		if (cut <= 0 || armSpeed < cut || swingQuiet[i] > 0)
			return;
		swingQuiet[i] = int(max(F('ae_loader_swing_gap', 12.0), 1.0));
		punchAt[i] = swingQuiet[i];		// the boom swings: Arms() plays frames 0..14 over this

		Vector3 pt = ClawPoint(mo, h == 1);
		// thousandths, so the event carries a position every machine agrees on
		EventHandler.SendNetworkEvent("ae_claw", int(pt.x * 8), int(pt.y * 8),
		                              (int(pt.z * 8) << 1) | h);
	}

	// THE RAM -- the arms' second fire mode, 2026-10-23 (owner: "we can have multiple fire
	// modes for each arm").
	//
	// The claw's own trigger is for taking hold of something: close, carry, crush, throw. That
	// is a deliberate, two-step thing, and it is no use at all when something is already on
	// you. So alt fire is the other half of a loader: a straight hydraulic shove. No grab, no
	// wind-up -- what is in front of the claw goes away from you, hard, and takes a hit doing
	// it. It is the move the machine is FOR.
	//
	// It will not fire while that arm is holding something: a hand that has hold of a barrel
	// is not free to punch with, and firing it would silently drop what you were carrying.
	void Ram(PlayerPawn mo, int n, int h)
	{
		int i = n * 2 + h;
		if (ramQuiet[i] > 0)
			ramQuiet[i]--;
		let p = mo.player;
		bool down = (RSVR_VRHand.Buttons(mo) & (h == 0 ? BT_ALTATTACK : BT_OFFHANDALTATTACK)) != 0;
		bool press = down && !ramPrev[i];
		ramPrev[i] = down;
		if (!press || ramQuiet[i] > 0 || held[i])
			return;
		if (F('ae_loader_ram', 1.0) <= 0)
			return;
		ramQuiet[i] = int(max(F('ae_loader_ram_gap', 20.0), 1.0));

		Vector3 pt = ClawPoint(mo, h == 1);
		// ONE event, as the claw sends: the point in eighths with the hand in the top byte.
		// The shove direction is taken from the claw point back to the player on the far side
		// rather than sent as a second event -- two events for one action can arrive split up,
		// and the line from you to your own claw IS the arm's forward.
		EventHandler.SendNetworkEvent("ae_ram", int(pt.x * 8), int(pt.y * 8),
		                              (int(pt.z * 8) << 1) | h);
	}

	// THE MAIN ARM'S ALT FIRE: THROW IT, 2026-10-23 (owner: "PRIMARY MAINHAND GRAB / CRUSH /
	// ALTFIRE THROW").
	//
	// Letting the claw open while you swing already lets go at the speed the arm was moving,
	// which is how you put something down or sling it off to one side. This is the other
	// thing: a deliberate throw, DOWN THE LINE THE ARM IS POINTING, whether the arm is moving
	// or not. You aim it and it goes there, which is what a throw is and what a release is not.
	//
	// With an empty claw the arm has nothing to throw, so alt fire stays the ram it already
	// was -- that mode is not lost, it is what the arm does when its hand is free.
	void Fling(PlayerPawn mo, int n, int h)
	{
		int i = n * 2 + h;
		if (!held[i])
		{
			Ram(mo, n, h);
			return;
		}

		let p = mo.player;
		bool down = (RSVR_VRHand.Buttons(mo) & (h == 0 ? BT_ALTATTACK : BT_OFFHANDALTATTACK)) != 0;
		bool press = down && !ramPrev[i];
		ramPrev[i] = down;			// one flag for the arm's alt fire, whichever mode it took
		if (!press)
			return;

		// out along the arm, with a little lift, so a barrel flies instead of skidding
		Vector3 pt = ClawPoint(mo, h == 1);
		Vector3 away = pt - mo.pos;
		double len = away.Length();
		if (len < 1)
			return;
		away /= len;
		double sp = F2('ae_loader_fling', 42.0);
		Vector3 v = away * sp + (0, 0, sp * F2('ae_loader_fling_lift', 0.22));

		clawPrev[i] = pt;
		clawShut[i] = 0.0;			// the claw opens to let it go
		EventHandler.SendNetworkEvent("ae_drop", int(v.x * 64), int(v.y * 64),
		                              (int(v.z * 64) << 1) | h);
		Say(mo, pt, "SYNTPN2", 0.8);
	}

	// THE OFF ARM'S TRIGGER: THE WELDING ARC, 2026-10-23 (owner: "OFFHAND MAIN ATTACK
	// ELECTRICAL ARC").
	//
	// Held, not tapped: it strikes on a rate while you keep the trigger down, so it reads as a
	// continuous arc rather than a pistol. It jumps between bodies, because an arc does -- and
	// the chain is found from positions, not from RNG, so every machine builds the same chain.
	void Arc(PlayerPawn mo, int n)
	{
		if (arcQuiet[n] > 0)
			arcQuiet[n]--;
		// THE OFF BOOM MOVES WHILE IT WORKS, 2026-10-24. The punch animation is bound to both
		// arms now, but only a swing drove it -- so the arc and the torch fired off an arm as
		// still as a photograph. A weld is not a punch, so this is not the full 0..14 throw:
		// it stirs the first third, frames 0..4, on a slow cycle, which reads as the boom
		// working rather than swinging. Presentation only; Punch() does the drawing.
		if ((RSVR_VRHand.Buttons(mo) & BT_OFFHANDATTACK) && punchAt[n * 2 + 1] <= 0)
			work[n * 2 + 1] = 1;
		let p = mo.player;
		bool down = (RSVR_VRHand.Buttons(mo) & BT_OFFHANDATTACK) != 0;
		if (!down || F('ae_loader_arc', 1.0) <= 0)
		{
			arcOn[n] = false;
			return;
		}
		arcOn[n] = true;
		if (arcQuiet[n] > 0)
			return;
		arcQuiet[n] = int(max(F('ae_loader_arc_gap', 7.0), 1.0));

		Vector3 pt = ClawPoint(mo, true);
		EventHandler.SendNetworkEvent("ae_arc", int(pt.x * 8), int(pt.y * 8),
		                              (int(pt.z * 8) << 1) | 1);
	}

	// THE OFF ARM'S ALT FIRE: THE CUTTING TORCH, 2026-10-23 (owner: "SECONDARY ATTACK
	// FLAMETHROWER").
	//
	// It throws the TC's OWN flame, FTFire -- the same actor actors/weapons/flamethrower.txt
	// fires -- so there is no new art, no new projectile and no new balance to invent: a
	// loader torch burns exactly as hard as an M240 does. It leaves the claw, not your face.
	void Flame(PlayerPawn mo, int n)
	{
		let p = mo.player;
		bool down = (RSVR_VRHand.Buttons(mo) & BT_OFFHANDALTATTACK) != 0;
		if (down && punchAt[n * 2 + 1] <= 0)
			work[n * 2 + 1] = 1;		// the torch stirs the boom too, as the arc does
		if (!down || F('ae_loader_flame', 1.0) <= 0)
		{
			flameOn[n] = false;
			flameAt[n] = 0;
			return;
		}
		flameOn[n] = true;
		if (flameAt[n] > 0)
		{
			flameAt[n]--;
			return;
		}
		flameAt[n] = int(max(F('ae_loader_flame_rate', 3.0), 1.0));

		Vector3 pt = ClawPoint(mo, true);
		EventHandler.SendNetworkEvent("ae_flame", int(pt.x * 8), int(pt.y * 8),
		                              (int(pt.z * 8) << 1) | 1);
	}

	static Vector3 ClawPoint(PlayerPawn mo, bool off)
	{
		double ps = mo.Level.pixelstretch;
		if (ps <= 0)
			ps = 1.2;
		Vector3 d = off ? RSVR_VRHand.OffDir(mo, 0, 0, ps) : RSVR_VRHand.HandDir(mo, 0, 0, ps);
		Vector3 o = off ? mo.OffhandPos : mo.AttackPos;
		double reach = F2('ae_loader_reach', 72.0);
		return o + d * reach;
	}

	static double F2(Name n, double def)
	{
		let c = CVar.FindCVar(n);
		return c ? c.GetFloat() : def;
	}

	// Every machine runs this against the same point, so it stays in step.
	override void NetworkProcess(ConsoleEvent e)
	{
		int hand = 0;
		if (e.Name == "ae_grab" || e.Name == "ae_drop" || e.Name == "ae_crush"
		    || e.Name == "ae_claw" || e.Name == "ae_ram"
		    || e.Name == "ae_arc" || e.Name == "ae_flame")
			// SIGN-SAFE PACKING, 2026-10-23. Arg 2 used to be `int(z * 8) | (hand << 24)`,
			// unpacked with `& 0xFFFFFF` and `>> 24`. ZScript's `>>` is ARITHMETIC (the pack
			// uses `>>>` where it wants the unsigned one -- casings.zs), so a NEGATIVE z
			// filled the top bits: the hand bit always read 1, and the z came back as about
			// two million map units. Every claw point below the controller did it, which is
			// most of them -- aim a boom at the floor and the arm grabbed, rammed, welded and
			// swung at a point high above the map, while the grab attached to an arm that
			// cannot let go. Now the hand is the LOW bit and z is shifted up one, so the sign
			// survives the round trip. One bit of range is given up; it was +-1M units.
			hand = e.Name == "ae_crush" ? clamp(e.Args[0], 0, 1) : (e.Args[2] & 1);
		else
			return;
		int n = e.Player;
		if (n < 0 || n >= MAXPLAYERS || !playeringame[n] || !players[n].mo)
			return;
		let mo = PlayerPawn(players[n].mo);
		if (!mo || !Worn(mo))
			return;


		if (e.Name == "ae_grab")
		{
			int i = n * 2 + hand;
			if (held[i])
				return;
			Vector3 g = (e.Args[0] / 8.0, e.Args[1] / 8.0, (e.Args[2] >> 1) / 8.0);
			double rad = F2('ae_loader_grab_radius', 48.0);
			Actor best = null;
			double bestd = 1e9;
			let git = BlockThingsIterator.CreateFromPos(g.x, g.y, g.z, 0, rad, false);
			while (git.Next())
			{
				let t = git.thing;
				if (!Grabbable(t, mo))
					continue;
				// BlockThingsIterator is a 2D blockmap walk: it hands back everything in the
				// 128-unit blocks it touches, at any height, so the radius has to be tested
				// here. Without this the claw took things a couple of hundred units away and
				// on other floors -- every sibling handler (ram, arc, swing) already gates it.
				double d = (t.pos - g).Length();
				if (d > rad + t.radius)
					continue;
				if (d < bestd)
				{
					bestd = d;
					best = t;
				}
			}
			if (best)
				Take(mo, i, best);
			return;
		}

		if (e.Name == "ae_drop")
		{
			Vector3 v = (e.Args[0] / 64.0, e.Args[1] / 64.0,
			             (e.Args[2] >> 1) / 64.0);
			Drop(n * 2 + hand, v);
			return;
		}

		if (e.Name == "ae_ram")
		{
			Vector3 pt = (e.Args[0] / 8.0, e.Args[1] / 8.0, (e.Args[2] >> 1) / 8.0);
			// the shove runs from the player out through the claw: that line is the arm
			Vector3 away = pt - mo.pos;
			double len = away.Length();
			if (len < 1)
				return;
			away /= len;
			double rad = F2('ae_loader_ram_radius', 56.0);
			int dmg = int(F2('ae_loader_ram_damage', 60.0));
			double push = F2('ae_loader_ram_push', 26.0);
			bool any = false;
			let it = BlockThingsIterator.CreateFromPos(pt.x, pt.y, pt.z, 0, rad, false);
			while (it.Next())
			{
				let t = it.thing;
				if (!t || t == mo || !t.bSHOOTABLE || t.health <= 0)
					continue;
				if ((t.pos - pt).Length() > rad + t.radius)
					continue;
				// a shove throws things OFF you: out along the arm and a little up, so a body
				// leaves the floor instead of grinding along it
				// REACHABILITY: the ram shoved through doors. Same trap as the swing.
				if (!Reaches(mo, pt, t))
					continue;
				t.vel += away * push + (0, 0, push * 0.35);
				// NOT thrustless -- the velocity above IS the shove, and the document's
				// complaint about DMG_THRUSTLESS is bodies that do not move. They move here.
				t.DamageMobj(mo, mo, dmg, 'Melee', DMG_THRUSTLESS);
				any = true;
			}
			Say(mo, pt, any ? "melee/hitwall" : "ALIECLW1", 0.9);
			if (any)
				RSQ_MeleeHandler.Buzz(mo);
			return;
		}

		if (e.Name == "ae_arc")
		{
			Vector3 pt = (e.Args[0] / 8.0, e.Args[1] / 8.0, (e.Args[2] >> 1) / 8.0);
			double rad = F2('ae_loader_arc_radius', 44.0);
			int dmg = int(F2('ae_loader_arc_damage', 26.0));
			int chain = int(clamp(F2('ae_loader_arc_chain', 3.0), 1.0, 8.0));
			double creep = F2('ae_loader_arc_jump', 72.0);

			Spark(mo, pt, 0.55);

			// walk the chain: each link starts at the last body it found, so the arc crawls
			// from one to the next. Nearest-first, by position, so it is the same chain on
			// every machine -- no RNG anywhere on this path.
			Vector3 from = pt;
			double reach = rad;
			Array<Actor> hit;
			for (int link = 0; link < chain; link++)
			{
				Actor best = null;
				double bestd = 1e9;
				let it = BlockThingsIterator.CreateFromPos(from.x, from.y, from.z, 0,
				                                           reach, false);
				while (it.Next())
				{
					let t = it.thing;
					if (!t || t == mo || t.player || !t.bSHOOTABLE || t.health <= 0)
						continue;
					if (hit.Find(t) != hit.Size())
						continue;
					double d = (t.pos - from).Length();
					if (d > reach + t.radius || d >= bestd)
						continue;
					bestd = d;
					best = t;
				}
				if (!best)
					break;
				// REACHABILITY: an arc that welds through a wall is not an arc. Checked from
				// the previous link, so the chain has to have line of sight along its path.
				if (!Reaches(mo, from, best))
					break;
				hit.Push(best);
				Spark(mo, best.pos + (0, 0, best.height * 0.6), 0.8);
				// DMG_THRUSTLESS: an arc burns, it does not shove. A shove here would walk
				// bodies out of the chain between links.
				best.DamageMobj(mo, mo, dmg, 'Electric', DMG_THRUSTLESS);
				from = best.pos + (0, 0, best.height * 0.5);
				reach = creep;
			}
			Say(mo, pt, "LODRALTF", hit.Size() > 0 ? 0.75 : 0.45, 1.35);
			return;
		}

		if (e.Name == "ae_flame")
		{
			// the TC's own flame, so there is no second flamethrower to balance
			Class<Actor> fc = 'FTFire';
			if (!fc)
				return;
			Vector3 pt = (e.Args[0] / 8.0, e.Args[1] / 8.0, (e.Args[2] >> 1) / 8.0);
			Vector3 away = pt - mo.pos;
			double len = away.Length();
			if (len < 1)
				return;
			away /= len;
			let f = Actor.Spawn(fc, pt, ALLOW_REPLACE);
			if (!f)
				return;
			f.target = mo;
			f.angle = atan2(away.y, away.x);
			f.pitch = -asin(clamp(away.z, -1.0, 1.0));
			double sp = f.Speed > 0 ? f.Speed : 20.0;
			f.vel = away * sp;
			Say(mo, pt, "FLAMETHR", 0.7);
			return;
		}

		if (e.Name == "ae_crush")
		{
			int i = n * 2 + hand;
			let t = held[i];
			if (!t)
				return;
			Drop(i);
			// past the gib threshold, so it comes apart rather than just dying. Not A_Die,
			// which deals exactly health and leaves it whole; never Destroy, which gives no
			// death, no gibs, no kill credit and no drop.
			t.DamageMobj(mo, mo, t.health + abs(t.GetGibHealth()) + 1, 'Crush', DMG_FORCED);
			// the jaws meet: sparks off the claw, since by now it is fully shut (owner:
			// "then all the way with an effect like sparks"), and the crunch comes from the
			// claw rather than from inside the player
			Vector3 cp = ClawPoint(mo, hand == 1);
			Say(mo, cp, "melee/hitwall", 1.0, 0.7);
			for (int k = 0; k < 3; k++)
				Spark(mo, cp + (0, 0, k * 2.0 - 2.0), 0.9);
			return;
		}

		Vector3 pt = (e.Args[0] / 8.0, e.Args[1] / 8.0, (e.Args[2] >> 1) / 8.0);
		double rad = F2('ae_loader_claw_radius', 40.0);
		int dmg = int(F2('ae_loader_damage', 180.0));

		let it = BlockThingsIterator.CreateFromPos(pt.x, pt.y, pt.z, 0, rad, false);
		int hits = 0;
		while (it.Next() && hits < 8)
		{
			let t = it.thing;
			if (!t || t == mo || !t.bShootable || t.health <= 0)
				continue;
			if ((t.pos - pt).Length() > rad + t.radius)
				continue;
			// REACHABILITY, 2026-10-24. "A cut iterator with no reachability test: a swing
			// near a thin wall or a closed door killed what was behind it" -- the melee
			// reference's trap table, paid for twice (SABER e825d10, SHIELD 2d10397). This
			// was a bare blockmap sweep: the boom swung through walls.
			//
			// The trace runs from the CLAW to the body, not from the player's eyes -- the
			// same document warns that guessing a muzzle off the body cost SHIELD most of its
			// guard. TRF_THRUACTORS so only geometry blocks; another monster in the way is
			// not a reason to spare this one.
			if (!Reaches(mo, pt, t))
				continue;
			hits++;
			t.DamageMobj(mo, mo, dmg, 'Melee');
			// and the sound comes from the thing that was hit, not from inside the player's
			// chest: "a metre-long blade's whoosh arrives from inside your chest, dead
			// centre, the same whatever you do with your arm" (SABER, three commits).
			t.A_StartSound("melee/hitwall", CHAN_AUTO, 0, 1.0, ATTN_NORM);
		}
	}


	// play it AT a point, not on the player
	static void Say(PlayerPawn mo, Vector3 at, String snd, double vol = 1.0, double pitch = 1.0)
	{
		if (snd == "")
			return;
		let e = Actor.Spawn('AE_LoaderNoise', at, ALLOW_REPLACE);
		if (!e)
		{
			mo.A_StartSound(snd, CHAN_AUTO, CHANF_OVERLAP, vol, ATTN_NORM, pitch);
			return;
		}
		e.target = mo;
		e.A_StartSound(snd, CHAN_AUTO, CHANF_OVERLAP, vol, ATTN_NORM, pitch);
	}

	// Can the claw actually reach it, or is there a wall in between?
	static bool Reaches(PlayerPawn mo, Vector3 from, Actor t)
	{
		Vector3 d = t.pos + (0, 0, t.height * 0.5) - from;
		double dist = d.Length();
		if (dist < 1)
			return true;
		FLineTraceData lt;
		// TRF_ABSPOSITION: the three offsets are literal coordinates, not offsets -- the trap
		// table records a trace that began at the map origin because they were read as offsets.
		bool hitSomething = mo.LineTrace(atan2(d.y, d.x), dist,
			-asin(clamp(d.z / dist, -1.0, 1.0)),
			TRF_THRUACTORS | TRF_ABSPOSITION, from.z, from.x, from.y, lt);
		// geometry in the way, short of the body
		return !hitSomething || lt.Distance >= dist - 4.0;
	}

	// The arc's flash. AE_LoaderCageSpark already ships with the set and already has
	// mechaloader_spark.md3 bound to it in modeldef.loader.txt, so the arc costs no new art
	// and no new MODELDEF block. It is +NOINTERACTION +CLIENTSIDEONLY, so each machine draws
	// its own and nothing about it has to stay in step.
	void Spark(Actor by, Vector3 at, double scale)
	{
		let s = Actor.Spawn('AE_LoaderCageSpark', at, ALLOW_REPLACE);
		if (!s)
			return;
		s.target = by;
		s.A_SetScale(s.Default.Scale.x * scale, s.Default.Scale.y * scale);
	}

	// WHAT CAN BE PICKED UP. Data, not a class list: mass and flags agree with each other, so
	// a barrel (Mass 100) and a drone pass while a Baron or Cyberdemon (1000, and +BOSS) do
	// not. ExplosiveBarrel qualifies on its own merits and is never named.
	static bool Grabbable(Actor t, Actor by)
	{
		if (!t || t == by || t.player)
			return false;
		if (t.bBOSS || t.bNOTARGET || t.bINVULNERABLE || t.bNODAMAGE)
			return false;
		if (!t.bShootable && !t.bCORPSE)
			return false;
		return t.Mass <= 700 && t.Height <= 80;
	}

	// Carry is a VELOCITY SPRING, never SetOrigin. SetOrigin is a teleport: it would shove a
	// monster THROUGH the wall you are pinning it against, and there would be nothing to pin.
	// Asking its velocity to point at the claw lets the engine's own movement code do the
	// collision -- so pinning is not a feature anyone writes, it is what happens when the claw
	// keeps asking and the wall keeps refusing.
	void Carry(PlayerPawn mo, int i, Vector3 pt)
	{
		// hold the pain frame. Some pain states are a short run rather than one frame, and a
		// run would walk itself off the -1 we set; re-asserting it each tic costs nothing.
		if (heldPain[i] && held[i] && held[i].health > 0 && held[i].tics >= 0)
			held[i].tics = -1;
		let t = held[i];
		if (!t || t.health <= 0 && !t.bCORPSE)
		{
			Drop(i);
			return;
		}
		Vector3 d = pt - t.pos;
		double k = clamp(F2('ae_loader_carry', 0.35), 0.05, 1.0);
		t.vel = d * k;
		if (t.vel.Length() > 40)
			t.vel = t.vel.Unit() * 40;
	}

	void Take(PlayerPawn mo, int i, Actor t)
	{
		if (!t)
			return;
		held[i] = t;
		heldGrav[i] = t.bNOGRAVITY;
		t.bNOGRAVITY = true;
		t.bTHRUACTORS = true;
		crushFor[i] = 0;

		// FROZEN IN PAIN WHILE IT IS HELD, 2026-10-24 (owner: "I EXPECT WHATEVER MONSTER IN MY
		// CLAWS TO BE DRAWN IN THE CLAW IN A FROZEN PAIN STATE"). Until now a grabbed drone
		// went on walking, turning and swinging in the claw, animating as if nothing had it.
		//
		// A state with tics -1 never advances, so putting it in Pain and setting tics -1 holds
		// that frame for as long as we keep hold. Not bNOINTERACTION and not a freeze flag: it
		// must still be damageable, because crushing it is the point.
		//
		// A corpse has no Pain state and a barrel has no Pain state; FindState returns null
		// for both and they are left exactly as they are.
		heldPain[i] = false;
		if (!t.bCORPSE && t.health > 0)
		{
			State pn = t.FindState('Pain');
			if (pn)
			{
				t.SetState(pn);
				t.tics = -1;
				heldPain[i] = true;
			}
		}
	}

	// Let go, restoring exactly what we changed. A flag set and never put back is the bug that
	// outlives the session.
	void Drop(int i, Vector3 throwVel = (0, 0, 0))
	{
		let t = held[i];
		held[i] = null;
		crushFor[i] = 0;
		if (!t)
			return;
		t.bNOGRAVITY = heldGrav[i];
		t.bTHRUACTORS = false;
		// let it move again: back to See if it has one, else Spawn. Without this a released
		// monster keeps the -1 tic and stands in its pain frame for ever.
		if (heldPain[i] && t.health > 0)
		{
			State go = t.FindState('See');
			if (!go)
				go = t.FindState('Spawn');
			if (go)
			{
				t.SetState(go);
				if (t.tics < 0)
					t.tics = 1;
			}
		}
		heldPain[i] = false;
		if (throwVel.Length() > 0.1)
		{
			t.vel = throwVel;
			flung.Push(t);
			flungWas.Push(throwVel.Length());
		}
	}

	// A thrown thing hurts what it lands on, and itself. Done with our own tracker rather than
	// +MISSILE: making a Cacodemon a missile sends it to its Death state on the first doorframe
	// it clips, and permanently mutates an actor that survives the throw.
	// NOT Flung(): ZScript identifiers are case-insensitive and `flung` is the array.
	void TickFlung()
	{
		for (int i = flung.Size() - 1; i >= 0; i--)
		{
			let t = flung[i];
			if (!t || t.health <= 0 && !t.bCORPSE)
			{
				flung.Delete(i); flungWas.Delete(i);
				continue;
			}
			double now = t.vel.Length();
			double was = flungWas[i];
			flungWas[i] = now;
			if (was < 8.0)
			{
				flung.Delete(i); flungWas.Delete(i);
				continue;
			}
			if (now > was * 0.5)
				continue;		// still flying

			// it stopped: that is the impact
			int dmg = int(clamp(was * F2('ae_loader_throw_dmg', 6.0), 0, 400));
			let it = BlockThingsIterator.CreateFromPos(t.pos.x, t.pos.y, t.pos.z, 0,
			                                           t.radius + 24, false);
			while (it.Next())
			{
				let o = it.thing;
				if (!o || o == t || !o.bShootable || o.health <= 0 || o.player)
					continue;
				o.DamageMobj(t, t, dmg, 'Melee');
			}
			if (t.bShootable && t.health > 0)
				t.DamageMobj(t, t, dmg / 2, 'Melee');
			flung.Delete(i); flungWas.Delete(i);
		}
	}


	// The local half: decide, then SEND. Nothing here touches the playsim, because the claw
	// point comes from AttackPos/OffhandPos which only this machine has.
	void HandGrab(PlayerPawn mo, int n, int h, double armSpeed)
	{
		int i = n * 2 + h;
		let p = mo.player;
		bool shut = clawShut[i] > 0.6;
		Vector3 pt = ClawPoint(mo, h == 1);

		if (!held[i])
		{
			if (shut && clawShut[i] >= 1.0)
				EventHandler.SendNetworkEvent("ae_grab", int(pt.x * 8), int(pt.y * 8),
				                              (int(pt.z * 8) << 1) | h);
			return;
		}

		// holding: let go when the claw opens, and throw at the speed the arm was moving
		if (!shut)
		{
			Vector3 v = (pt - ClawWas(i)) * F2('ae_loader_throw', 1.6);
			clawPrev[i] = pt;
			EventHandler.SendNetworkEvent("ae_drop", int(v.x * 64), int(v.y * 64),
			                              (int(v.z * 64) << 1) | h);
			return;
		}
		clawPrev[i] = pt;

		// squeezed shut and held: crush. Deliberate, because a barrel crushed in your hands
		// goes off in your face -- which is correct, and worth having to mean.
		if (clawShut[i] >= 0.98)
		{
			crushFor[i]++;
			if (crushFor[i] == int(max(F2('ae_loader_crush_tics', 12.0), 1.0)))
				EventHandler.SendNetworkEvent("ae_crush", h, 0, 0);
		}
		else
		{
			crushFor[i] = 0;
		}
	}

	Vector3 ClawWas(int i)
	{
		return clawPrev[i];
	}

	void Hush(PlayerPawn mo, int n)
	{
		if (humming[n])
		{
			mo.A_StopSound(CHAN_7);
			humming[n] = false;
		}
	}

	// An arm that was moving fast and has just stopped: a servo clunk and a kick in THAT
	// controller. Per-hand haptics do exist on this engine -- SpawnPlayerMissile fires a
	// 150 ms pulse at 0.8 on the hand chosen by ALF_ISOFFHAND (p_mobj.cpp:7546-7563), gated on
	// a non-zero DamageType, which is exactly why RSVR_Buzz carries DamageType "RSVRHaptic".
	void Clunk(PlayerPawn mo, int i, double now, bool off)
	{
		if (quiet[i] > 0)
			quiet[i]--;
		double trip = F('ae_loader_clunk', 18.0);
		double was = spWas[i];
		spWas[i] = now;
		if (trip <= 0 || quiet[i] > 0)
			return;
		if (was < trip || now > trip / 3.0)
			return;
		quiet[i] = 10;
		mo.A_StartSound("melee/hitwall", CHAN_AUTO, 0, clamp(was / 40.0, 0.4, 1.0), ATTN_NORM,
		                clamp(0.7 + was / 120.0, 0.7, 1.0));
		if (F('ae_loader_haptic', 1.0) > 0)
			mo.SpawnPlayerMissile('RSVR_Buzz', mo.angle, noautoaim: true,
			                      aimflags: off ? ALF_ISOFFHAND : 0);
	}
}
