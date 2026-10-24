// TEST ONLY: drives the power loader and reports what actually happened.
//
// Nothing in zscript/ae/loader.zs has ever executed a tic -- it compiles and the pack loads,
// and that is all anyone can say about it. This presses its buttons from script and watches
// the consequences, so each claim about it is a line in a log rather than a hope.
//
//   aet_loader  0  off
//               1  BOTH ARMS SWING, no button held. Expects ae_claw from each arm and damage
//                  on whatever is in front. This is the "independent melee" test: the two
//                  arms are driven half a sweep apart, so a tic where only one of them is
//                  moving fast proves the arms are read separately.
//               2  OFF ARM MAIN ATTACK, held: the welding arc. Expects ae_arc, damage of type
//                  Electric, and AE_LoaderCageSpark actors appearing.
//               3  OFF ARM ALT ATTACK, held: the torch. Expects ae_flame and FTFire actors.
//               4  MAIN ARM: spawn a barrel, close the claw on it, then alt fire to throw it
//                  forward. Expects held -> not held and the barrel moving away fast.
//               5  MAIN ARM: spawn a barrel, close the claw, hold it shut and crush it.
//                  Expects ae_crush and the barrel dying.
//               6  MAIN ARM alt fire with an EMPTY claw: the ram. The other half of alt fire,
//                  which script 4 does not reach.
//               7  THE CAGE: damage the player and watch AE_LoaderWorn.ModifyDamage take its
//                  share, plus the speed factor, which is the whole "it is heavy" premise.
//
// Every script reports the three psprite LAYERS first, because if the arms were never created
// then every action below still "works" and draws nothing -- which is the failure mode that
// would survive all of the above.
class AET_LoaderTest : EventHandler
{
	int started;
	int shots;
	Actor subject;
	bool said;

	static double F(Name n, double def)
	{
		let c = CVar.FindCVar(n);
		return c ? c.GetFloat() : def;
	}

	// ZScript gives no SpriteID -> name, and String.Format("%s", aSpriteID) is a VM ABORT:
	// "string format failed. Expected a string for format %s". It cost a run. All this needs
	// to answer is whether the layer shows the left arm, so compare against that sprite.
	static bool IsArmL(SpriteID s)
	{
		return s == Actor.GetSpriteIndex('AEAL');
	}

	static int Cnt(Class<Actor> c)
	{
		int n = 0;
		ThinkerIterator it = ThinkerIterator.Create(c);
		Actor a;
		while (a = Actor(it.Next()))
			n++;
		return n;
	}

	void Layers(PlayerPawn mo)
	{
		let p = mo.player;
		// THE OFF ARM IS ON 2200, NOT 2211. AE_LoaderLayers.ARM_OFF (2211) is a declared
		// constant that nothing uses: Arms() creates only ARM_MAIN, and hands.zs:694 draws the
		// left arm on RSQ_Hands' own free-hand layer with the AEArmL state. Checking 2211
		// reported "no off arm" on a loader that has one, which is a test bug, not a pack bug.
		// What matters is that 2200 exists AND is showing AEAL rather than a bare hand.
		let off = p.FindPSprite(2200);
		String osp = 'absent';
		if (off)
			osp = IsArmL(off.Sprite) ? "the left ARM (AEAL)" : "present, but NOT the arm";
		Console.Printf("LOADER layers  main(2300) %d  offarm(2200) %s  cage(2305) %d  beacon(2304) %d",
			p.FindPSprite(2300) ? 1 : 0, osp,
			p.FindPSprite(2305) ? 1 : 0, p.FindPSprite(2304) ? 1 : 0);
		let tok = mo.FindInventory('AE_LoaderWorn');
		Console.Printf("LOADER worn %d  speedfactor %.2f  (1.00 = normal walking speed)",
			tok ? 1 : 0, tok ? tok.GetSpeedFactor() : -1.0);
	}

	override void WorldTick()
	{
		int s = int(F('aet_loader', 0));
		if (s <= 0 || !playeringame[0] || !players[0].mo)
			return;
		let mo = PlayerPawn(players[0].mo);
		if (!mo || !mo.player)
			return;
		let p = mo.player;
		int t = Level.maptime;

		if (!said && t > 40)
		{
			said = true;
			Layers(mo);
		}
		if (t < 60)
			return;

		int n = t - 60;		// tics since the test proper began

		// something to hit, 60 units in front, for the melee and arc scripts
		if ((s == 1 || s == 2 || s == 3) && n == 1)
		{
			Vector3 at = mo.pos + (cos(mo.angle), sin(mo.angle), 0) * 60.0;
			subject = Actor.Spawn('ExplosiveBarrel', at);
			Console.Printf("LOADER target %s at %.0f units", subject ? 'barrel' : 'NONE', 60.0);
		}
		// a barrel within the claw's reach for grab / throw / crush
		if ((s == 4 || s == 5) && n == 1)
		{
			Vector3 at = mo.pos + (cos(mo.angle), sin(mo.angle), 0) * 40.0;
			at.z += 20;
			subject = Actor.Spawn('ExplosiveBarrel', at);
			Console.Printf("LOADER barrel spawned at %s", subject ? "40 units ahead" : "NOWHERE");
		}

		// --- the buttons ---------------------------------------------------------------
		// usercmd buttons cannot be written from here, so the fake hands' Buttons() is what
		// carries them; this sets the cvars it reads.
		int want = 0;
		if (s == 2)
			want |= 1;				// off main
		if (s == 3)
			want |= 2;				// off alt
		// THROW: grab with a SHORT squeeze, then let go of the trigger, then alt fire.
		// Holding the trigger shut for ae_loader_crush_tics (12) IS the crush -- the first
		// version held it 90 tics and crushed the barrel before the throw could run, so the
		// test destroyed its own subject and reported the wrong feature.
		// THE THROW'S WINDOW IS NARROW and both earlier attempts missed it in opposite ways.
		// clawShut needs ae_loader_claw_tics (7) to close; ae_grab fires then; crushFor starts
		// counting from that tic and ae_crush lands ae_loader_crush_tics (12) later. And
		// Fling() needs held[i], so the trigger must STAY down. So alt fire has to arrive
		// between about tic 8 and tic 18 with the trigger still held: hold 4 throughout, add
		// 8 at tic 12, and be finished before 19.
		if (s == 4)
			want |= (n < 19) ? (4 | ((n >= 12 && n < 16) ? 8 : 0)) : 0;
		if (s == 5)
			want |= 4;				// main trigger, held, to crush
		if (s == 6)
			want |= 8;				// main alt with nothing held: the ram
		let bc = CVar.FindCVar('aet_buttons');
		if (bc && bc.GetInt() != want)
			bc.SetInt(want);

		// THE CAGE: `god` has to be OFF or the player takes nothing and ModifyDamage never
		// runs. The first version set god at t=10 and reported "health 100 -> 100" as if the
		// cage had eaten everything.
		if (s == 7 && n == 10)
			mo.bINVULNERABLE = false;
		if (s == 7 && n == 20 && mo.health > 40)
		{
			Console.Printf("LOADER health before %d", mo.health);
			mo.DamageMobj(null, null, 30, 'Melee');
			Console.Printf("LOADER health after  %d  (30 dealt; the cage should have eaten part)", mo.health);
		}

		if ((n % 35) == 0)
		{
			String sub = 'none';
			if (subject)
				sub = String.Format("%s hp %d vel %.1f", subject.GetClassName(), subject.health,
				                    subject.vel.Length());
			Console.Printf("LOADER t%d s%d  sparks %d  flames %d  mags %d | target %s",
				t, s, Cnt('AE_LoaderCageSpark'), Cnt('FTFire'), Cnt('RSR_DroppedMag'), sub);
		}
	}

	override void WorldThingDamaged(WorldEvent e)
	{
		if (!e.Thing || !e.Inflictor && !e.DamageSource)
			return;
		if (e.Thing.player)
			return;
		Console.Printf("LOADER HIT %s dmg %d type %s  (hp now %d)",
			e.Thing.GetClassName(), e.Damage, e.DamageType, e.Thing.health);
	}

	override void WorldThingDestroyed(WorldEvent e)
	{
		if (e.Thing && e.Thing is 'ExplosiveBarrel')
			Console.Printf("LOADER the barrel is gone");
	}
}
