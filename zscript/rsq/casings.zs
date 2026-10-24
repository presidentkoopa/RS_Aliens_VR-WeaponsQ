// SPENT CASINGS, 2026-10-23 (owner: the casing actors exist in RS_Ballistics).
//
// The meshes and their skins are RS_Ballistics' own (models/casings, built by its
// tools/gen_casings.py in millimetres at real size and scaled 1/30.5 here, a 56-unit marine
// being 1.71 m). Copied in rather than loaded, because nothing in this pack may pull another
// package in behind the owner's back.
//
// What is NOT copied is RS_Ballistics' ejecta engine. That is a data-driven system with its
// own profile parser, tiers, styles and a shared/local netplay split, and importing it would
// drag RSBDEFS and its settings in with it. This pack already has a proven dropped-object
// actor -- RSR_DroppedMag, which the magazine and the shotgun shell have used all along:
// a bouncing projectile that lands, lies on its side and fades. The casings are that actor
// with a different mesh, which is the smallest thing that is also the right thing.
//
// WHEN ONE COMES OUT. Not from the gun's states -- the shotgun fires SEVEN ShotgunTracers per
// trigger pull and the pistol fires both DummyProjectile1 and DummyProjectile4, so counting
// either would give seven casings for one shell or two for one round. Instead the tracer
// itself is caught as it spawns and a player may eject at most ONE casing per tic. Every
// pellet of a blast spawns inside the same tic (the state is "BBBBBBB" 0, zero duration), so
// one blast is one hull, and a pistol round is one case.
//
// WHERE IT COMES OUT. Measured per gun, not placed by eye: the body mesh is sliced 3 cm
// either side of RSR_Guns.Well(i) -- the magazine's top, which is where the chamber sits --
// and the port is the 3rd percentile of that slice on the right and the 97th on top, through
// the same F/L/U mapping that reproduces RSR_Guns.MagCentre(2) exactly.
//
// NETPLAY: +NOINTERACTION, spawned from the local view of a shot and touching nothing, as
// RS_Ballistics' own local ejecta is. It is a look, not a thing.

class RSQ_Casing : RSR_DroppedMag
{
	Default
	{
		Radius 1;
		Height 1;
		BounceFactor 0.35;
		WallBounceFactor 0.35;
		Gravity 0.7;
		// NOT +NOINTERACTION. RS_Ballistics' local ejecta sets it and then moves itself by
		// hand with its own trace every tic; this one is the pack's own RSR_DroppedMag, which
		// lets the engine move and bounce it. Set the flag here and the case would hang in
		// the air where it was born.
	}
}

class RSQ_Casing9mm : RSQ_Casing {}
class RSQ_CasingRifle : RSQ_Casing {}
class RSQ_Shell12ga : RSQ_Casing { Default { Radius 2; Height 2; } }

// the sprite the MODELDEF blocks hang their meshes on; never spawned
class RSQ_CasingSprites : Actor
{
	States
	{
	Spawn:
		RSCS ABCDE 0;
		Stop;
	}
}

class RSQ_Casings : EventHandler
{
	int lastTic[MAXPLAYERS];

	// the tracer each gun fires -> which case it leaves. Anything not named here (the
	// flamethrower, the satchel, the grenade) throws nothing, which is correct.
	static Name CaseFor(Name tracer)
	{
		switch (tracer)
		{
		case 'ColPistol':
		case 'MerPistol':
		case 'SynPistol':
		case 'YutPistol':
		case 'BulletTracer':		return 'RSQ_Casing9mm';
		case 'ShotgunTracer':		return 'RSQ_Shell12ga';
		case 'HeavyTracer':			return 'RSQ_CasingRifle';
		case 'SmartgunTracer':
		case 'SmartgunTracer2':		return 'RSQ_CasingRifle';
		}
		return 'None';
	}

	// MEASURED: the body mesh sliced at RSR_Guns.Well(i), right side and top of that slice.
	// F forward, L left, U up, centimetres in the gun controller's frame.
	static Vector3 Port(int i)
	{
		switch (i)
		{
		case 1:	case 5:	case 6:	case 7:	return (-3.41, -1.76, -1.17);	// the pistols
		case 2:	case 8:						return ( 8.79, -3.16,  2.52);	// the pulse rifles
		case 3:	case 9:						return ( 6.61, -4.06, 10.89);	// the smartguns
		}
		return (0, 0, 0);
	}

	// the shotguns are not in RSR_Guns' index space; they are RSP_Guns'
	static Vector3 PumpPort(int i)
	{
		return i > 0 ? (-3.41, -2.03, 5.49) : (0, 0, 0);
	}

	// a cheap deterministic mix, so two machines that do run this agree and one that does not
	// has taken nothing from the playsim stream
	static int Hash(int a, int b)
	{
		int x = a * 73856093 ^ (b + 1) * 19349663;
		x ^= x >>> 13;
		x *= 1274126177;
		return x ^ (x >>> 16);
	}

	// 0..1 from the hash, a different slice per call
	static double Unit(int h, int k)
	{
		int x = Hash(h, k * 2654435761);
		return ((x >>> 8) & 0xFFFF) / 65535.0;
	}

	override void WorldThingSpawned(WorldEvent e)
	{
		let cv = CVar.FindCVar('ae_casings');
		if (cv && !cv.GetBool())
			return;
		let a = e.Thing;
		if (!a || !a.target || !a.target.player)
			return;
		Name cls = CaseFor(a.GetClassName());
		if (cls == 'None')
			return;
		let mo = PlayerPawn(a.target);
		if (!mo || !mo.player)
			return;
		int n = mo.PlayerNumber();
		if (n < 0 || n >= MAXPLAYERS)
			return;
		// one case per tic: a shotgun's seven pellets all spawn inside the same one
		if (lastTic[n] == mo.Level.maptime)
			return;
		lastTic[n] = mo.Level.maptime;
		Throw(mo, cls);
	}

	void Throw(PlayerPawn mo, Name cls)
	{
		let p = mo.player;
		Vector3 port;
		int gi = RSR_Guns.Index(p.ReadyWeapon);
		if (gi > 0)
			port = Port(gi);
		else
			port = PumpPort(RSP_Guns.Index(p.ReadyWeapon));
		if (port == (0, 0, 0))
			return;

		// the gun's own axes, built as switch.zs builds them
		double ps = mo.Level.pixelstretch;
		if (ps <= 0)
			ps = 1.2;
		double vu = 34.0;
		let cvv = CVar.GetCVar('vr_vunits_per_meter', p);
		if (cvv && cvv.GetFloat() > 0)
			vu = cvv.GetFloat();
		Vector3 F, L, U;
		Vector3 at;
		if (RSVR_VRHand.InVR(mo))
		{
			F = RSVR_VRHand.HandDir(mo, 0, 0, ps);
			L = RSVR_VRHand.HandDir(mo, 90, 0, ps);
			U = RSVR_VRHand.HandDir(mo, 0, 90, ps);
			at = RSVR_VRHand.HandPos(mo);
		}
		else
		{
			// desktop: the gun is on the view line, so the port hangs off that instead
			double ang = mo.angle, pit = mo.pitch;
			F = (cos(ang) * cos(pit), sin(ang) * cos(pit), -sin(pit));
			L = (cos(ang + 90), sin(ang + 90), 0);
			U = (-cos(ang) * sin(pit), -sin(ang) * sin(pit), -cos(pit));
			at = mo.Vec3Offset(0, 0, mo.player.viewheight - 4);
		}
		double cm = vu / 100.0;					// centimetres -> map units
		Vector3 w = (F * port.x + L * port.y + U * port.z) * cm;
		w.z /= ps;
		Vector3 pos = at + w;

		let c = Actor.Spawn(cls, pos, ALLOW_REPLACE);
		if (!c)
			return;
		c.target = mo;
		// THE CASING HAD NO SPRITE, so no casing has ever been drawn. RSR_DroppedMag's states
		// are `"####" "#"` -- SPR_FIXED, "keep whatever sprite the actor already has" -- so a
		// spawned casing kept its class default, never RSCS, and FindModelFrameRaw only
		// returns a mesh when the sprite matches the MODELDEF key exactly. RSQ_CasingSprites
		// exists purely to make the RSCS name and frames A..E real; this is the line that
		// points the actor at them. Same two lines the proven dropped-magazine path uses
		// (vreload.zs). All three casing classes bind every frame A..E to their own mesh, so
		// frame 0 is as good as any.
		c.sprite = Actor.GetSpriteIndex('RSCS');
		c.frame = 0;
		// Out to the right and a little up. The scatter is HASHED, never the playsim RNG:
		// this is spawned off a local view of a shot, and drawing from the playsim stream on
		// a path that does not run identically on every machine walks the stream out of step
		// and desyncs the game. RS_Ballistics' own ejecta says the same thing about itself.
		int h = Hash(mo.Level.maptime, mo.PlayerNumber());
		double side = 3.0 + Unit(h, 1) * 1.5;
		double up   = 2.0 + Unit(h, 2) * 1.0;
		Vector3 v = -L * side + U * up;
		v.z /= ps;
		c.vel = mo.vel * 0.5 + v;
		c.angle = mo.angle + (Unit(h, 3) - 0.5) * 80.0;
		c.pitch = (Unit(h, 4) - 0.5) * 120.0;
		c.roll  = Unit(h, 5) * 360.0;
	}
}
