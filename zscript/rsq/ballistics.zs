// RS enhanced ballistics for Aliens Eradication on QuestZDoom 17.x,
// rsq_ballistics 1. Ported from rs_brutal22weaponsq's zscript/rsq/ballistics.zs.
//
// It ports almost unchanged, and that is the point of how it was written: it
// owns none of the weapon set's actors and only adds to shots that have
// already happened, so nothing in it is about BD22 except the list of melee
// attacks to leave alone. That list is the only edit below -- BD22's axe,
// chainsaw and Dragonslayer out, the Aliens knife and power loader in.
//
// It does NOT need RS_Ballistics loaded beside it. Nothing here reads an
// RSBDEFS lump; the per-gun numbers that package computes are baked in where
// they are used.
// Off (the default) is BD22's own ballistics: with the cvar off nothing here
// runs. On, it only adds to shots that already happened, owning none of BD22's
// actors: impacts throw chips and dust that match the surface (SURFACES lump),
// and players' damaging projectiles get a short particle trail and the same
// impacts where they land. Hard caps keep it cheap on Quest.
//
// rsq_ballistics is a server cvar on purpose: the effects use playsim random
// numbers (stream rsqb), so every machine must make the same choice.

class RSQ_Ballistics : EventHandler
{
	const MAX_TRACERS = 24;
	const MAX_DEBRIS = 64;

	RSQ_Surfaces surf;
	int liveTracers;
	int liveDebris;

	static bool On()
	{
		let cv = CVar.FindCVar('rsq_ballistics');
		return cv && cv.GetInt() != 0;
	}

	static RSQ_Ballistics Get()
	{
		return RSQ_Ballistics(EventHandler.Find('RSQ_Ballistics'));
	}

	override void WorldThingSpawned(WorldEvent e)
	{
		if (!On())
			return;
		let a = e.Thing;
		if (!a || !a.bMISSILE || a.bNOINTERACTION || !a.target || !a.target.player)
			return;
		if (liveTracers >= MAX_TRACERS || a.GetMissileDamage(0, 1) <= 0)
			return;
		if (IsMelee(a) || MeleeHeld(a.target) || a.DamageType == 'Trample')	// 1.11: BD22's footsteps are damaging missiles too
			return;					// no trails on fists, kicks, axe, chainsaw, sword (owner, 2026-10-16)
		RSQ_Tracer.Attach(a, self);
	}

	// BD22's melee hits are short invisible projectiles: punches, kicks (KickAttack and
	// everything from it), the axe and sword strikes, a thrown axe
	static bool IsMelee(Actor a)
	{
		Name kn = 'KickAttack';
		class<Actor> kick = kn;
		if (kick && a is kick)
			return true;
		String cn = a.GetClassName();
		cn = cn.MakeLower();
		// Aliens' own melee: the knife, and the power loader's claws and stomp.
		// BD22's axe / saw / sword / Dragonslayer words are gone -- no such
		// actors here, and a word that matches nothing is just a slower loop.
		static const String words[] = { "kick", "fist", "punch", "melee", "strike", "knife", "claw", "loader", "step", "stomp", "crush" };
		for (int i = 0; i < words.Size(); i++)
			if (cn.IndexOf(words[i]) >= 0)
				return true;
		return false;
	}

	// the shooter has a melee weapon out: fists, axe, chainsaw, Dragonslayer
	static bool MeleeHeld(Actor who)
	{
		if (!who || !who.player || !who.player.ReadyWeapon)
			return false;
		let w = who.player.ReadyWeapon;
		Name n = w.GetClassName();
		return w.bMELEEWEAPON || n == 'Knife_3D' || n == 'YutaniKnife_3D'
		       || n == 'Loader_3D' || n == 'AELoader_3D'
		       || n == 'LBerserk_3D' || n == 'AEBerserk_3D';
	}

	// a hitscan shot (e.AttackPos: where it started, e.DamagePosition: where it
	// ended); look at the last few units of it to see what it hit
	override void WorldHitscanFired(WorldEvent e)
	{
		if (!On() || !e.Thing || MeleeHeld(e.Thing))
			return;
		Vector3 d = e.DamagePosition - e.AttackPos;
		double len = d.Length();
		if (len < 1)
			return;
		d /= len;
		Impact(e.Thing, e.DamagePosition - d * min(12, len), d, 24);
	}

	void Impact(Actor tracer, Vector3 from, Vector3 dir, double dist)
	{
		if (!tracer)
			return;
		FLineTraceData t;
		tracer.LineTrace(VectorAngle(dir.x, dir.y), dist, -asin(clamp(dir.z, -1, 1)),
			TRF_ABSPOSITION | TRF_THRUACTORS, from.z, from.x, from.y, t);
		Vector3 n;
		bool flat = false;
		if (t.HitType == TRACE_HitWall && t.HitLine)
		{
			Vector2 dl = t.HitLine.delta.Unit();
			n = (dl.y, -dl.x, 0);
			if (t.LineSide == 1)
				n = -n;
		}
		else if (t.HitType == TRACE_HitFloor)
		{
			n = (0, 0, 1);
			flat = true;
		}
		else if (t.HitType == TRACE_HitCeiling)
		{
			n = (0, 0, -1);
			flat = true;
		}
		else
		{
			return;		// sky, nothing, or flesh (flesh is BD22's)
		}
		if (!surf)
		{
			surf = new('RSQ_Surfaces');
			surf.Load();
		}
		Spall(t.HitLocation + n * 2, n, surf.Of(t.HitTexture, flat));
	}

	// dust or sparks or a splash, and a few chips
	void Spall(Vector3 at, Vector3 n, Name mat)
	{
		Color c = Color(150, 145, 135);		// concrete and anything unnamed
		int dust = 8, chips = 2, chipBase = 0, sparks = 0;
		switch (mat)
		{
		case 'metal':	case 'pipe':
			c = Color(120, 120, 125); dust = 3; chips = 0; sparks = 8; break;
		case 'tech':	case 'screen':	case 'light':
			c = Color(90, 95, 110); dust = 4; chips = 0; sparks = 10; break;
		case 'glass':
			c = Color(200, 225, 240); dust = 10; chips = 0; break;
		case 'wood':
			c = Color(150, 105, 60); dust = 6; chips = 3; chipBase = 4; break;
		case 'brick':
			c = Color(150, 80, 55); dust = 8; chips = 3; chipBase = 4; break;
		case 'marble':	case 'tile':
			c = Color(190, 185, 175); dust = 6; chips = 2; break;
		case 'dirt':
			c = Color(110, 85, 55); dust = 12; chips = 3; chipBase = 8; break;
		case 'liquid':
			c = Color(150, 180, 220); dust = 12; chips = 0; break;
		case 'slime':
			c = Color(110, 200, 60); dust = 12; chips = 0; break;
		case 'lava':
			c = Color(255, 130, 30); dust = 10; chips = 0; sparks = 4; break;
		}

		FSpawnParticleParams p;
		p.style = STYLE_Translucent;
		p.startalpha = 0.9;
		p.fadestep = -1;
		for (int i = 0; i < dust; i++)
		{
			p.color1 = c;
			p.lifetime = random[rsqb](14, 26);
			p.size = frandom[rsqb](2.0, 4.5);
			p.sizestep = 0.12;
			p.pos = at;
			p.vel = n * frandom[rsqb](0.6, 2.2) + (frandom[rsqb](-0.8, 0.8), frandom[rsqb](-0.8, 0.8), frandom[rsqb](-0.3, 0.9));
			p.accel = (0, 0, -0.06);
			p.flags = 0;
			Level.SpawnParticle(p);
		}
		p.style = STYLE_Add;
		for (int i = 0; i < sparks; i++)
		{
			p.color1 = mat == 'lava' ? Color(255, 160, 40) : Color(255, 220, 140);
			p.lifetime = random[rsqb](5, 10);
			p.size = frandom[rsqb](1.0, 2.0);
			p.sizestep = -0.1;
			p.pos = at;
			p.vel = n * frandom[rsqb](2.0, 5.0) + (frandom[rsqb](-2.5, 2.5), frandom[rsqb](-2.5, 2.5), frandom[rsqb](-1.0, 2.5));
			p.accel = (0, 0, -0.35);
			p.flags = SPF_FULLBRIGHT;
			Level.SpawnParticle(p);
		}
		for (int i = 0; i < chips && liveDebris < MAX_DEBRIS; i++)
		{
			let a = RSQ_Debris(Actor.Spawn('RSQ_Debris', at, NO_REPLACE));
			if (!a)
				break;
			liveDebris++;
			a.frame = chipBase + random[rsqb](0, 3);
			a.angle = frandom[rsqb](0, 360);
			a.pitch = frandom[rsqb](0, 360);
			a.spin = frandom[rsqb](-25, 25);
			a.vel = n * frandom[rsqb](1.5, 4.5) + (frandom[rsqb](-1.2, 1.2), frandom[rsqb](-1.2, 1.2), frandom[rsqb](0.5, 2.5));
		}
	}
}

// a chip of the wall: a tiny mesh that flies, tumbles, lands and goes
class RSQ_Debris : Actor
{
	double spin;
	int age;

	Default
	{
		Radius 1;
		Height 2;
		Gravity 0.7;
		-SOLID
		+NOBLOCKMAP
		+NOTELEPORT
		+DONTSPLASH
		+THRUACTORS
		+NOTRIGGER
		+CANNOTPUSH
		+DROPOFF
	}

	override void Tick()
	{
		Super.Tick();
		if (bDestroyed)
			return;
		if (pos.z > floorz + 0.5)
		{
			angle += spin;
			pitch += spin * 0.7;
		}
		else
		{
			vel.xy *= 0.6;
		}
		age++;
		if (age > 60)
		{
			scale *= 0.8;
			if (age > 72)
				Destroy();
		}
	}

	override void OnDestroy()
	{
		let h = RSQ_Ballistics.Get();
		if (h && h.liveDebris > 0)
			h.liveDebris--;
		Super.OnDestroy();
	}

	States
	{
	Spawn:
		// the spawner picks the mesh by setting `frame`; nothing changes it after
		QDBR A -1;
		Stop;
	}
}

// follows one player projectile: a short trail while it flies, and an impact
// where it lands
// what one gun's round looks like in the air: set once when the tracer attaches, read
// every tic by Trail. Colour is only half of it -- lifetime, size and points-per-tic are
// what keep a seven-pellet shotgun blast affordable on a Quest.
class RSQ_ShotLook
{
	Color col;
	int pts;	// particles spawned per tic: 2 draws a line, 1 draws a spray
	int life;	// tics a point lives
	double size;
	double alpha;
}

class RSQ_Tracer : Thinker
{
	Actor missile;
	Actor shooter;
	RSQ_Ballistics h;
	Vector3 lastPos;
	Vector3 lastVel;
	RSQ_ShotLook look;
	int age;

	static void Attach(Actor m, RSQ_Ballistics h)
	{
		let t = new('RSQ_Tracer');
		t.missile = m;
		t.shooter = m.target;
		t.h = h;
		t.lastPos = m.pos;
		t.lastVel = m.vel;
		t.look = LookFor(m);
		h.liveTracers++;
	}

	// 2026-10-23 PER-GUN LOOK (owner: "get the ballistics for the guns done this pass too,
	// something lovely for quest"). This used to colour by substring -- plasma, bfg, rail,
	// fire -- and NOT ONE of the Aliens set's projectiles matches any of those words, so
	// every gun in the pack fired the same warm round. The names below are the set's own,
	// taken from the A_FireProjectile / A_FireCustomMissile calls in actors/weapons/.
	//
	// The weights matter as much as the colours on a Quest. A shotgun blast is SEVEN
	// ShotgunTracers and MAX_TRACERS is 24, so three blasts in the air would eat the whole
	// budget and starve everything else of trails. Pellets therefore get a cheap profile --
	// one point per tic instead of two, gone in four -- which is also what buckshot should
	// look like: a brief spray, not seven rifle streaks.
	// NOT Look(): ZScript identifiers are case-insensitive, so a static Look() and the
	// field `look` below are the same name and the class will not compile.
	static RSQ_ShotLook LookFor(Actor a)
	{
		let k = new('RSQ_ShotLook');
		k.pts = 2; k.life = 7; k.size = 2.5; k.alpha = 0.9;
		switch (a.GetClassName())
		{
		// pistols: brass-warm, and the two synthetic/corporate ones run cold
		case 'ColPistol':		k.col = Color(255, 200, 130); break;
		case 'MerPistol':		k.col = Color(255, 178, 105); break;
		case 'SynPistol':		k.col = Color(190, 220, 255); break;
		case 'YutPistol':		k.col = Color(160, 230, 255); break;

		// buckshot: short, dim and CHEAP -- seven of these fly per trigger pull
		case 'ShotgunTracer':
			k.col = Color(255, 170, 100); k.pts = 1; k.life = 4; k.size = 1.6; k.alpha = 0.7;
			break;

		// the pulse rifle's 10mm caseless: the gun the film is about, so it gets the
		// longest, brightest line in the set
		case 'HeavyTracer':
			k.col = Color(255, 214, 150); k.life = 9; k.size = 2.8; break;
		case 'PulseGrenade':	k.col = Color(255, 140, 60); k.life = 10; k.size = 3.2; break;

		// M56 armour-piercing: heavier and hotter than the rifle's
		case 'SmartgunTracer':
		case 'SmartgunTracer2':
			k.col = Color(255, 228, 175); k.life = 8; k.size = 3.0; break;

		case 'BulletTracer':	k.col = Color(255, 190, 130); break;
		default:
			// anything this pack does not own: the portable fallback this module shipped
			// with, so it still drops unchanged into another set (see the file header)
			String cn = a.GetClassName();
			cn = cn.MakeLower();
			if (cn.IndexOf("plasma") >= 0)			k.col = Color(120, 180, 255);
			else if (cn.IndexOf("bfg") >= 0)		k.col = Color(140, 255, 140);
			else if (cn.IndexOf("rail") >= 0)		k.col = Color(200, 160, 255);
			else if (cn.IndexOf("fire") >= 0 || cn.IndexOf("flame") >= 0)
													k.col = Color(255, 150, 60);
			else									k.col = Color(255, 190, 130);
			break;
		}
		return k;
	}

	override void Tick()
	{
		age++;
		if (missile && missile.bMISSILE && age < 350)
		{
			Trail(missile.pos);
			lastPos = missile.pos;
			lastVel = missile.vel;
			return;
		}
		// exploded (P_ExplodeMissile clears MISSILE) or gone: what it hit is
		// along its last step
		if (h)
		{
			h.liveTracers = max(0, h.liveTracers - 1);
			double sp = lastVel.Length();
			if (age < 350 && sp > 0 && shooter && RSQ_Ballistics.On())
				h.Impact(shooter, lastPos, lastVel / sp, sp * 2 + 16);
		}
		Destroy();
	}

	void Trail(Vector3 to)
	{
		if (!missile.Level)
			return;
		if (!look)
			return;
		FSpawnParticleParams p;
		p.color1 = look.col;
		p.style = STYLE_Add;
		p.flags = SPF_FULLBRIGHT;
		p.lifetime = look.life;
		p.size = look.size;
		p.sizestep = -look.size / look.life;
		p.startalpha = look.alpha;
		p.fadestep = -1;
		p.vel = (0, 0, 0);
		p.accel = (0, 0, 0);
		// two points per tic so a fast round leaves a line, not dots -- one for buckshot,
		// where seven pellets are in the air at once and the line is not worth the cost
		p.pos = to;
		missile.Level.SpawnParticle(p);
		if (look.pts > 1)
		{
			p.pos = (lastPos + to) * 0.5;
			missile.Level.SpawnParticle(p);
		}
	}
}

// What textures are made of: the SURFACES lump(s), `surface name { walls = ...
// flats = ... any = ... }`, * any run and ? one character, later rules win,
// `surface none` un-tags. Untagged textures count as concrete.
class RSQ_SurfRule
{
	String pat;
	String surface;
	int kind;		// 0 walls, 1 flats, 2 any
}

class RSQ_Surfaces
{
	Array<RSQ_SurfRule> rules;
	Map<String, String> cache;
	bool loaded;

	static bool Glob(String pat, String str)
	{
		pat = pat.MakeUpper();
		str = str.MakeUpper();
		int p = 0, s = 0, star = -1, mark = 0;
		int pl = pat.Length(), sl = str.Length();
		while (s < sl)
		{
			if (p < pl && (pat.ByteAt(p) == 63 || pat.ByteAt(p) == str.ByteAt(s)))
			{
				p++;
				s++;
			}
			else if (p < pl && pat.ByteAt(p) == 42)
			{
				star = p;
				p++;
				mark = s;
			}
			else if (star >= 0)
			{
				p = star + 1;
				mark++;
				s = mark;
			}
			else
			{
				return false;
			}
		}
		while (p < pl && pat.ByteAt(p) == 42)
			p++;
		return p == pl;
	}

	static String Trim(String s)
	{
		int a = 0, b = s.Length();
		while (a < b && (s.ByteAt(a) == 32 || s.ByteAt(a) == 9 || s.ByteAt(a) == 13))
			a++;
		while (b > a && (s.ByteAt(b - 1) == 32 || s.ByteAt(b - 1) == 9 || s.ByteAt(b - 1) == 13))
			b--;
		return s.Mid(a, b - a);
	}

	void Load()
	{
		if (loaded)
			return;
		loaded = true;
		int lump = -1;
		while ((lump = Wads.FindLump("SURFACES", lump + 1, Wads.GlobalNamespace)) >= 0)
			Parse(Wads.ReadLump(lump));
	}

	void Parse(String text)
	{
		Array<String> lines;
		text.Split(lines, "\n");
		String cur = "";
		for (int i = 0; i < lines.Size(); i++)
		{
			String ln = lines[i];
			int c = ln.IndexOf("//");
			if (c >= 0)
				ln = ln.Left(c);
			ln = Trim(ln);
			if (ln.Length() == 0 || ln == "{" || ln == "}")
				continue;
			if (ln.Left(8).MakeLower() == "surface ")
			{
				cur = Trim(ln.Mid(8));
				continue;
			}
			int eq = ln.IndexOf("=");
			if (eq < 0)
				continue;
			String key = Trim(ln.Left(eq)).MakeLower();
			int kind = key == "walls" ? 0 : key == "flats" ? 1 : key == "any" ? 2 : -1;
			if (kind < 0)
				continue;
			Array<String> parts;
			ln.Mid(eq + 1).Split(parts, ",");
			for (int k = 0; k < parts.Size(); k++)
			{
				String v = parts[k];
				v.Replace("\"", "");
				v = Trim(v);
				if (v.Length() == 0)
					continue;
				let r = new('RSQ_SurfRule');
				r.pat = v;
				r.surface = cur;
				r.kind = kind;
				rules.Push(r);
			}
		}
	}

	Name Of(TextureID tex, bool flat)
	{
		if (!tex.IsValid())
			return 'concrete';
		String tn = TexMan.GetName(tex);
		if (tn.Length() == 0)
			return 'concrete';
		String key = (flat ? "f:" : "w:") .. tn;
		if (cache.CheckKey(key))
			return Name(cache.Get(key));
		String found = "concrete";
		for (int i = rules.Size() - 1; i >= 0; i--)
		{
			let r = rules[i];
			if ((r.kind == 0 && flat) || (r.kind == 1 && !flat))
				continue;
			if (Glob(r.pat, tn))
			{
				found = r.surface.MakeLower() == "none" ? "concrete" : r.surface;
				break;
			}
		}
		cache.Insert(key, found);
		return Name(found);
	}
}
