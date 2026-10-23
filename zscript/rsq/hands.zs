// VR hands for the Aliens Eradication weapon set.
//
// The classes are RSQ_*, not AE_*, and that is load-bearing in two places
// rather than a style choice:
//   * MODELDEF binds a model to a CLASS NAME. ae_gen.py has always emitted
//     "Model RSQ_GunSide" / "Model RSQ_Hands"; while these classes were called
//     AE_*, those blocks named classes that did not exist, so NO HAND DREW AT
//     ALL. A MODELDEF block pointing at an unknown class is not a parse error,
//     which is why a clean script parse said nothing about it.
//   * rsr/vreload.zs decides a player is reload-capable with
//     `OffhandWeapon is 'RSQ_Hands'` (lines 602, 790) and rsr_pump.zs does the
//     same. RSQ_Hands is the kit's interface, not BD22's private name.
//
// Cut down from BD22 VR-Reloaded's zscript/rsq/hands.zs to the hands alone:
// no reload, no fists, no dual wield. Those hang off the same three layers
// when they arrive.
//
// 2026-10-22: RECOIL-FOLLOW brought over from BD22 1.92. The set's recoil is in
// its meshes (the pistol's fire frames move the body 1.7-3.5 cm, its own reload
// swing 28 cm / 42 deg, the shotgun's pump 23 cm / 61 deg: tools/ae_kick.py), so a
// hand hooked to the READY frame was left behind the moment the gun fired. The
// gun hand and support hand now ride the gun's model frame (RSQ_GunMoves, made
// by ae_gunmoves_gen.py from the meshes, blended toward the next state the way
// the engine blends the model) and the gun layer's own offset turn, about the
// gun's pivot -- BD22's RSQ_Hands.FollowGun / ModifyBobLayer3D / RSQ_Turn.
// Verified on the Linux QuestZDoom 17.3 rig by rendering a fire frame.
// The smartguns keep the mesh-frame follow but NOT the layer-offset follow:
// their harness gimbal (rsq/smartgun.zs) swings the gun by psprite tilt while
// the hands are meant to stay put.
//
// How a hand reaches a controller, because none of this is guessable:
//   models.cpp:221 sends a psprite layer to the OFF controller only when its
//   caller is player->OffhandWeapon. Everything else goes to the main one. So
//   the gun hand and support hand are owned by a plain inventory item
//   (RSQ_GunSide) to land on the main controller, and the free hand is owned by
//   RSQ_Hands, a weapon that never fires and is parked in OffhandWeapon, to
//   land on the off controller. Swap the owners and the hands swap hands.
//
//   hw_weapon.cpp:332,941-951 then calls the OFF-HAND WEAPON's
//   ModifyBobLayer3D for every layer that is not the ready weapon's, which is
//   how RSQ_Hands gets to place layers it does not own.
//
// Placement comes from RSQ_HandTable (generated from ae_fits.json).

// Where every hand layer goes.
//
// Factored out of RSQ_Hands because the engine asks the OFF-HAND WEAPON to
// place every layer that is not the ready weapon's (hw_weapon.cpp:332,
// 941-951). While the off hand is empty that weapon is RSQ_Hands and this
// lived there -- but dual wielding puts a real gun in that slot, and the
// moment it does, a gun that does not implement this silently drops every
// hand hook on the floor. Both owners call the same code instead.
// Rest-pose tuning cvars read by RSQ_Place.Layer (see there). Hook units: x left, y up, z back.
class RSQ_HandTune abstract
{
	// ONE definition of which hand-seat family a gun belongs to, read by BOTH hands.
	//
	// FIXED 2026-10-23 (owner: "all the support poses are shared?"). The support hand was a
	// single global set: tuning it for the pulse rifle's forward grip moved the pistol's
	// cupped support hand and the smartgun's handlebar fist with it, and those three grips
	// have nothing in common. The gun hand had the same flaw one line away -- the smartgun
	// and the satchel were riding the long-gun sliders, so a rifle tweak dragged them too.
	// A slider must only ever move the guns it was aimed at. Families live here so the two
	// hands can never disagree about what a gun is.
	clearscope static String Family(int i)
	{
		if (i == 1 || i == 11)                     return "knife";
		if (i == 3 || i == 4 || i == 9 || i == 12) return "pistol";
		if (i == 7 || i == 14)                     return "satchel";
		if (i == 8 || i == 16)                     return "smart";
		return "gun";                              // flamers, shotguns, pulse rifles
	}
	clearscope static Vector3 Offset(PlayerInfo p, int i)
	{
		String g = "ae_" .. Family(i) .. "hand_";
		return (Get(p, g .. "side"), Get(p, g .. "up"), -Get(p, g .. "fwd"));
	}
	clearscope static Vector3 SupportOffset(PlayerInfo p, int i)
	{
		// knives and satchels have no support pose, so only three of these are ever read
		String g = "ae_support_" .. Family(i) .. "_";
		return (Get(p, g .. "side"), Get(p, g .. "up"), -Get(p, g .. "fwd"));
	}
	clearscope static Vector3 SatchelTurn(PlayerInfo p)
	{
		return (Get(p, "ae_satchel_yaw"), Get(p, "ae_satchel_pitch"), Get(p, "ae_satchel_roll"));
	}
	clearscope static double Get(PlayerInfo p, String n)
	{
		let c = CVar.GetCVar(n, p);
		return c ? c.GetFloat() : 0;
	}
}

class RSQ_Place abstract
{
	clearscope static Vector3, Vector3 Layer(Actor owner, Vector3 translation, Vector3 rotation,
	                                         int layer, double ticfrac)
	{
		// The real reload owns layers 2102-2104 (parts on the gun), 2201 (the
		// magazine in the off hand) and, while it is running, the free hand.
		// Those are placed by rsr/vreload.zs, which knows how far the magazine
		// has travelled this tic; this table only knows where hands rest.
		// RSR-PUMP: the pump shotguns' layers (rsr/rsr_pump.zs): the pump where the hand has it,
		// the shell at the port, the shell in the hand. PATCHED BY HAND 2026-10-22: the cut-down
		// hands.zs this pack shipped never routed these (BD22 1.92 hands.zs does), so the pump
		// part and the shell drew at the bare controller pose.
		// 2026-10-23: the launcher pump (zscript/rsq/pumpgl.zs), placed the same way -- it is
		// a part carried by the hand, so it needs a branch here or it draws at the bare
		// controller pose exactly as the shotgun's pump did before it was routed.
		if (RSQ_PumpGL.Places(layer))
		{
			Vector3 gt, gr;
			[gt, gr] = RSQ_PumpGL.Place(owner, translation, rotation, ticfrac);
			return gt, gr;
		}
		if (RSP_Handler.Places(owner, layer))
		{
			Vector3 pt, pr;
			[pt, pr] = RSP_Handler.Place(owner, translation, rotation, layer, ticfrac);
			return pt, pr;
		}
		if (layer >= RSR.LAYER_FIRST && layer <= RSR.LAYER_LAST
		    || layer == RSR.HANDMAG || layer == RSQ_Layers.FREEHAND)
		{
			Vector3 t, r;
			[t, r] = RSR_Handler.Place(owner, translation, rotation, layer, ticfrac);
			return t, r;
		}
		if (layer != RSQ_Layers.GUNHAND && layer != RSQ_Layers.SUPPORT && layer != RSQ_Layers.OFFGUN && layer != RSQ_Layers.COUNTER)
			return translation, rotation;
		let p = owner ? owner.player : null;
		if (!p)
			return translation, rotation;
		// the off-hand gun's hand is posed for the gun IT holds, not the ready one
		Weapon w = layer == RSQ_Layers.OFFGUN ? p.OffhandWeapon : p.ReadyWeapon;
		int i = RSQ_HandTable.Index(w);
		if (i <= 0)
			return translation, rotation;
		Vector3 hook = layer == RSQ_Layers.SUPPORT ? RSQ_HandTable.SupportHook(i) : RSQ_HandTable.GunHook(i);
		Vector3 rot  = layer == RSQ_Layers.SUPPORT ? RSQ_HandTable.SupportRot(i)  : RSQ_HandTable.GunRot(i);
		if (layer == RSQ_Layers.COUNTER)
		{
			hook = (0, 0, 0);	// the counter is drawn in the gun's own model space: it only follows the gun
			rot = (0, 0, 0);
		}
		if (i == 7 || i == 14)
			rot += RSQ_HandTune.SatchelTurn(p);	// 2026-10-22 (owner): the satchel hand can be turned from the menu

		// PATCHED BY HAND 2026-10-22: owner-tunable rest offset for the gun hand (Options >
		// Aliens VR > "Gun hand forward/up/side", cm). The owner tunes in the headset and
		// bakes the numbers into GunHook afterwards. Pistols and the rest have their own.
		//
		// FIXED 2026-10-23: the deltas were added straight into `hook`, which is NOT the gun's
		// frame -- RenderHUDModel appends translate(hook) after the rotations, so it is applied
		// to the vertex first and therefore comes out turned by this hand's rotation. That is
		// why Place() below adds its recoil term as Back(Rows(hookTurn), v): pre-turned by the
		// transpose so the renderer's rotation lands it straight. The slider deltas need the
		// same treatment, or "forward" is only forward on a gun whose GunRot is zero. It was
		// not forward on either smartgun (GunRot y 90, z -90), either satchel (138/126/-49) or
		// either knife (-55/42/46) -- on the smartgun the "forward" slider pushed the hand
		// sideways. A no-op on every gun with GunRot (0,0,0): Rows((0,0,0)) is the identity.
		// NOTE for whoever bakes these numbers into GunHook: the baked value is a hook, so it
		// goes in UNROTATED -- bake the slider reading itself, not this pre-turned vector.
		Vector3 tune = (0, 0, 0);
		if (layer != RSQ_Layers.SUPPORT && layer != RSQ_Layers.COUNTER)
			tune = RSQ_HandTune.Offset(p, i);
		else if (layer == RSQ_Layers.SUPPORT)
			tune = RSQ_HandTune.SupportOffset(p, i);	// per family, not one global set (see Family above)
		Vector3 u0, u1, u2;
		[u0, u1, u2] = RSQ_Turn.Rows(rot);
		hook += RSQ_Turn.Back(u0, u1, u2, tune);
		if (layer == RSQ_Layers.OFFGUN)
		{
			// the dual-wield gun hand: hooked to its gun's ready placement (no follow yet)
			let psp = p.FindPSprite(layer);
			Vector2 h = psp ? (psp.x, psp.y) : (0.0, WEAPONTOP);
			return translation + hook, rotation + rot - (h.x / 4, (h.y - WEAPONTOP) / -4, 0);
		}

		// RECOIL-FOLLOW (BD22 1.92 RSQ_Hands.ModifyBobLayer3D). The renderer turns every HUD
		// model by its own layer's offset: yaw x / 4, pitch (y - WEAPONTOP) / -4. The gun layer
		// is at y = 32 when ready and moves when it is raised, lowered or kicked by Offset; our
		// layers stay at WEAPONTOP. So the hands take the gun layer's turn instead of their
		// own, about the point the gun model turns on, plus the gun's model frame (the recoil
		// is in the meshes), blended toward the next state's frame the way the engine blends
		// the model (models.cpp CalcModelFrame). The frame data is cached in play by
		// RSQ_Hands.FollowGun (RSQ_HandHandler.WorldTick); this is ui and only reads it.
		let hands = RSQ_Hands(owner.FindInventory('RSQ_Hands'));
		PSprite gp, hp;
		for (let s = p.psprites; s; s = s.Next)
		{
			if (s.ID == PSP_WEAPON)
				gp = s;
			else if (s.ID == layer)
				hp = s;
		}
		Vector2 g = gp ? RSQ_Hands.LayerOffset(gp, ticfrac) : (0, WEAPONTOP);
		Vector2 h = hp ? RSQ_Hands.LayerOffset(hp, ticfrac) : (0, 0);
		Vector3 gunTurnNow = (g.x / 4, (g.y - WEAPONTOP) / -4, 0);
		if (RSQ_GunMoves.Mirrored(i))
			gunTurnNow.x = -gunTurnNow.x;
		if (i == 8 || i == 16)
			gunTurnNow = (0, 0, 0);		// the smartguns' gimbal tilts the gun layer on purpose; the hands stay

		Vector3 frameTurn, frameMove;
		if (hands)
		{
			frameTurn = hands.gunTurn;
			frameMove = hands.gunMove;
			if (gp && hands.gunState && gp.CurState == hands.gunState && hands.gunState.Tics > 0 && gp.Tics <= hands.gunState.Tics)
			{
				double inter = (hands.gunState.Tics - gp.Tics + ticfrac) / hands.gunState.Tics;
				frameTurn += (hands.nextTurn - hands.gunTurn) * inter;
				frameMove += (hands.nextMove - hands.gunMove) * inter;
			}
		}
		if (layer == RSQ_Layers.SUPPORT)
			frameMove += RSP_Handler.SupportShift(owner, ticfrac);	// RSR-PUMP: the support hand rides the pump (BD22 1.92)
		Vector3 t, r;
		[t, r] = RSQ_Turn.Place(hook, rot, gunTurnNow, frameTurn, frameMove, RSQ_GunMoves.Pivot(i));
		// the renderer still adds this layer's own turn on top: take it back out
		return translation + t, rotation + r - (h.x / 4, (h.y - WEAPONTOP) / -4, 0);
	}
}

class RSQ_Layers abstract
{
	const GUNHAND  = 2100;	// RSQ_GunSide, main controller
	const SUPPORT  = 2101;	// RSQ_GunSide, main controller
	const FREEHAND = 2200;	// RSQ_Hands,   off controller
	const OFFGUN   = 2202;	// the dual-wield gun hand, off controller
	// ADDED 2026-10-23 (BD22 1.92 RSQ_DualHands MAINGUN 2301): the MAIN gun's hand while
	// dual wielding, called by the main gun. See the comment at the dual block below for why
	// RSQ_GunSide's own GUNHAND cannot be used then.
	const MAINGUN  = 2203;	// the dual-wield MAIN gun hand, called by the main gun
	const COUNTER  = 2130;	// RSQ_GunSide, main controller: the pulse rifle's ammo counter (counter.zs)
}

class RSQ_GunSide : Inventory
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
	// the pulse rifle's ammo counter: 100 values over four sprite names (MODELDEF.ae, counter.zs)
	Counter: RSC0 A -1; Stop;
	Cnt00: RSC0 A -1; Stop;
	Cnt01: RSC0 B -1; Stop;
	Cnt02: RSC0 C -1; Stop;
	Cnt03: RSC0 D -1; Stop;
	Cnt04: RSC0 E -1; Stop;
	Cnt05: RSC0 F -1; Stop;
	Cnt06: RSC0 G -1; Stop;
	Cnt07: RSC0 H -1; Stop;
	Cnt08: RSC0 I -1; Stop;
	Cnt09: RSC0 J -1; Stop;
	Cnt10: RSC0 K -1; Stop;
	Cnt11: RSC0 L -1; Stop;
	Cnt12: RSC0 M -1; Stop;
	Cnt13: RSC0 N -1; Stop;
	Cnt14: RSC0 O -1; Stop;
	Cnt15: RSC0 P -1; Stop;
	Cnt16: RSC0 Q -1; Stop;
	Cnt17: RSC0 R -1; Stop;
	Cnt18: RSC0 S -1; Stop;
	Cnt19: RSC0 T -1; Stop;
	Cnt20: RSC0 U -1; Stop;
	Cnt21: RSC0 V -1; Stop;
	Cnt22: RSC0 W -1; Stop;
	Cnt23: RSC0 X -1; Stop;
	Cnt24: RSC0 Y -1; Stop;
	Cnt25: RSC0 Z -1; Stop;
	Cnt26: RSC0 [ -1; Stop;
	Cnt27: RSC0 \ -1; Stop;
	Cnt28: RSC0 ] -1; Stop;
	Cnt29: RSC1 A -1; Stop;
	Cnt30: RSC1 B -1; Stop;
	Cnt31: RSC1 C -1; Stop;
	Cnt32: RSC1 D -1; Stop;
	Cnt33: RSC1 E -1; Stop;
	Cnt34: RSC1 F -1; Stop;
	Cnt35: RSC1 G -1; Stop;
	Cnt36: RSC1 H -1; Stop;
	Cnt37: RSC1 I -1; Stop;
	Cnt38: RSC1 J -1; Stop;
	Cnt39: RSC1 K -1; Stop;
	Cnt40: RSC1 L -1; Stop;
	Cnt41: RSC1 M -1; Stop;
	Cnt42: RSC1 N -1; Stop;
	Cnt43: RSC1 O -1; Stop;
	Cnt44: RSC1 P -1; Stop;
	Cnt45: RSC1 Q -1; Stop;
	Cnt46: RSC1 R -1; Stop;
	Cnt47: RSC1 S -1; Stop;
	Cnt48: RSC1 T -1; Stop;
	Cnt49: RSC1 U -1; Stop;
	Cnt50: RSC1 V -1; Stop;
	Cnt51: RSC1 W -1; Stop;
	Cnt52: RSC1 X -1; Stop;
	Cnt53: RSC1 Y -1; Stop;
	Cnt54: RSC1 Z -1; Stop;
	Cnt55: RSC1 [ -1; Stop;
	Cnt56: RSC1 \ -1; Stop;
	Cnt57: RSC1 ] -1; Stop;
	Cnt58: RSC2 A -1; Stop;
	Cnt59: RSC2 B -1; Stop;
	Cnt60: RSC2 C -1; Stop;
	Cnt61: RSC2 D -1; Stop;
	Cnt62: RSC2 E -1; Stop;
	Cnt63: RSC2 F -1; Stop;
	Cnt64: RSC2 G -1; Stop;
	Cnt65: RSC2 H -1; Stop;
	Cnt66: RSC2 I -1; Stop;
	Cnt67: RSC2 J -1; Stop;
	Cnt68: RSC2 K -1; Stop;
	Cnt69: RSC2 L -1; Stop;
	Cnt70: RSC2 M -1; Stop;
	Cnt71: RSC2 N -1; Stop;
	Cnt72: RSC2 O -1; Stop;
	Cnt73: RSC2 P -1; Stop;
	Cnt74: RSC2 Q -1; Stop;
	Cnt75: RSC2 R -1; Stop;
	Cnt76: RSC2 S -1; Stop;
	Cnt77: RSC2 T -1; Stop;
	Cnt78: RSC2 U -1; Stop;
	Cnt79: RSC2 V -1; Stop;
	Cnt80: RSC2 W -1; Stop;
	Cnt81: RSC2 X -1; Stop;
	Cnt82: RSC2 Y -1; Stop;
	Cnt83: RSC2 Z -1; Stop;
	Cnt84: RSC2 [ -1; Stop;
	Cnt85: RSC2 \ -1; Stop;
	Cnt86: RSC2 ] -1; Stop;
	Cnt87: RSC3 A -1; Stop;
	Cnt88: RSC3 B -1; Stop;
	Cnt89: RSC3 C -1; Stop;
	Cnt90: RSC3 D -1; Stop;
	Cnt91: RSC3 E -1; Stop;
	Cnt92: RSC3 F -1; Stop;
	Cnt93: RSC3 G -1; Stop;
	Cnt94: RSC3 H -1; Stop;
	Cnt95: RSC3 I -1; Stop;
	Cnt96: RSC3 J -1; Stop;
	Cnt97: RSC3 K -1; Stop;
	Cnt98: RSC3 L -1; Stop;
	Cnt99: RSC3 M -1; Stop;
	// gun-hand poses, lettered by MODELDEF.ae (RQGS)
	GunA: RQGS A -1; Stop;
	GunB: RQGS B -1; Stop;
	GunC: RQGS C -1; Stop;
	GunD: RQGS D -1; Stop;
	GunE: RQGS E -1; Stop;
	GunF: RQGS F -1; Stop;
	// the gun hand with its index finger resting on the trigger,
	// and squeezing it while fire is held
	TrgA: RQGT A -1; Stop;
	SqzA: RQGU A -1; Stop;
	TrgB: RQGT B -1; Stop;
	SqzB: RQGU B -1; Stop;
	TrgC: RQGT C -1; Stop;
	SqzC: RQGU C -1; Stop;
	TrgD: RQGT D -1; Stop;
	SqzD: RQGU D -1; Stop;
	TrgE: RQGT E -1; Stop;
	SqzE: RQGU E -1; Stop;
	// support-hand poses (RQSP)
	SupA: RQSP A -1; Stop;
	SupB: RQSP B -1; Stop;
	SupC: RQSP C -1; Stop;
	Hidden: TNT1 A -1; Stop;
	}
}

class RSQ_Hands : Weapon
{
	// How the ready weapon's model frame has moved the gun (RSQ_GunMoves), for
	// RSQ_Place.Layer: looked up in play (FollowGun, every tic from
	// RSQ_HandHandler.WorldTick) when the gun layer changes frame, read by the renderer.
	State gunState;				// the gun layer's state, sprite and frame they are for
	int gunSprite, gunFrame;
	Vector3 gunTurn, gunMove;	// that frame
	Vector3 nextTurn, nextMove;	// the next state's frame, which the engine blends toward

	// ADDED 2026-10-23 (BD22 1.92, owner fix 2026-10-16): latch for the cup-support hand's
	// closeness rule in RSQ_HandHandler.WorldTick, so it can leave at a wider gap than it
	// enters at and not flicker on the boundary.
	bool holding;

	// Look up how the gun's model frame moves it when the gun layer shows another
	// frame. Called after the psprites have ticked, so this is the frame drawn this tic.
	void FollowGun(PlayerInfo p, int i)
	{
		let g = i > 0 ? p.FindPSprite(PSP_WEAPON) : null;
		if (!g || !g.CurState)
		{
			gunState = null;
			gunTurn = gunMove = nextTurn = nextMove = (0, 0, 0);
			return;
		}
		int spr = g.Sprite;
		if (g.CurState == gunState && spr == gunSprite && g.Frame == gunFrame)
			return;
		gunState = g.CurState;
		gunSprite = spr;
		gunFrame = g.Frame;
		Vector3 t, m;
		[t, m] = RSQ_GunMoves.Frame(i, spr, g.Frame);
		gunTurn = nextTurn = t;
		gunMove = nextMove = m;
		// The engine blends a model toward the next state's frame, unless that
		// state keeps the layer's sprite ("####": sprite index 1 or 2), which it
		// cannot look up.
		let n = gunState.NextState;
		if (RSQ_GunMoves.Blends(i) && n && n != gunState && n.sprite > 2)
		{
			[t, m] = RSQ_GunMoves.Frame(i, n.sprite, n.Frame);
			nextTurn = t;
			nextMove = m;
		}
	}

	// a layer's offset as the renderer draws it this frame (hw_weapon.cpp BobWeapon3D)
	clearscope static Vector2 LayerOffset(PSprite s, double ticfrac)
	{
		if (s.firstTic)
			return (s.x, s.y);
		return (s.oldx + (s.x - s.oldx) * ticfrac, s.oldy + (s.y - s.oldy) * ticfrac);
	}

	Default
	{
		// PATCHED BY HAND 2026-10-22: +OFFHANDWEAPON and NO*SWITCH as BD22 1.92. Without
		// the flag the engine never makes the PSP_OFFHANDWEAPON psprite (player.zs
		// BringUpWeapon picks the layer by bOffhandWeapon), and hw_weapon.cpp:332 then
		// finds no off-hand psprite for the hand layers -> ModifyBobLayer3D is never
		// called -> no hook, no reload placement, no recoil follow: every hand sat at
		// the raw controller pose. Found on the Linux QZD 17.3 rig (probe listed layers
		// 1, 2100, 2101, 2200 and no 1000000).
		+WEAPON.OFFHANDWEAPON
		+WEAPON.NOHANDSWITCH
		+WEAPON.NO_AUTO_SWITCH
		+WEAPON.NOAUTOSWITCHTO
		Weapon.SelectionOrder 32767;
		Weapon.SlotNumber 0;
		+WEAPON.NOALERT
		+WEAPON.CHEATNOTWEAPON
		+INVENTORY.UNDROPPABLE
		+INVENTORY.UNTOSSABLE
		+INVENTORY.QUIET
	}

	// Place a hand layer. The hook from the table is added to whatever bob the
	// engine already computed, and the layer's own tilt is taken back out:
	// hw_weapon.cpp gives every layer pitch (y - WEAPONTOP) / -4 and yaw x / 4,
	// so a layer sitting at WEAPONTOP contributes nothing and one left at y = 0
	// would sit 8 degrees out.
	override Vector3, Vector3 ModifyBobLayer3D(Vector3 translation, Vector3 rotation, int layer, double ticfrac)
	{
		// destructured, not forwarded: ZScript will not pass a two-value return
		// straight through as the return of another two-value function
		Vector3 t, r;
		[t, r] = RSQ_Place.Layer(Owner, translation, rotation, layer, ticfrac);
		return t, r;
	}

	States
	{
	Ready:    TNT1 A 1 A_WeaponReady(WRF_NOFIRE); Loop;
	// a Weapon must define Fire or the class will not compile, even
	// one that never shoots -- this is the free hand, not a gun
	Fire:     TNT1 A 1; Goto Ready;
	Deselect: TNT1 A 1 A_Lower; Loop;
	Select:   TNT1 A 1 A_Raise; Loop;
	Spawn:    TNT1 A -1; Stop;
	// DUAL WIELD (2026-10-22): the gun hand on the OFF-HAND GUN. That layer must be called by
	// the gun (only the off-hand weapon draws on the off controller), and a weapon caller
	// refuses an inventory item's states, so the states live here (as BD22 1.92 does) and
	// the hand model is bound to the gun's class in MODELDEF.aedual, hook baked into Offset.
	// 2026-10-23 POWER LOADER: the off arm. It is drawn on RSQ_Hands' OWN free-hand layer with
	// a state that belongs to RSQ_Hands, because that is the shape every layer in this pack that
	// works already has -- a layer whose caller is RSQ_Hands but whose state lives on another
	// actor was created by the engine and gone again inside the same tic.
	AEArmL: AEAL A -1; Stop;

	DGunA: RQGS A -1; Stop;
	DGunB: RQGS B -1; Stop;
	DGunC: RQGS C -1; Stop;
	DGunD: RQGS D -1; Stop;
	DGunE: RQGS E -1; Stop;
	DGunF: RQGS F -1; Stop;
	DTrgA: RQGT A -1; Stop;
	DSqzA: RQGU A -1; Stop;
	DTrgB: RQGT B -1; Stop;
	DSqzB: RQGU B -1; Stop;
	DTrgC: RQGT C -1; Stop;
	DSqzC: RQGU C -1; Stop;
	DTrgD: RQGT D -1; Stop;
	DSqzD: RQGU D -1; Stop;
	DTrgE: RQGT E -1; Stop;
	DSqzE: RQGU E -1; Stop;
	// the free hand, drawn on the OFF controller because this actor is
	// the player's OffhandWeapon (models.cpp:221)
	// These three labels are named BY rsr/vreload.zs: RSR_Handler.FreeHand()
	// returns "FreeHand", "AmmoH" or "RsrHold" as a string and hands.zs looks
	// them up. Renaming one here silently stops the reload showing a hand.
	FreeHand: RQHN A -1; Stop;	// open
	AmmoH:    RQHN H -1; Stop;	// closed, round a charging handle
	RspShell: RQUN A -1; Stop;	// RSR-PUMP: Ermac's one-shell hold, round the gun's own shell (MODELDEF.rsrpump)
	RsrHold:  RQHN I -1; Stop;	// Ermac's hold; the magazine itself is layer 2201
	Open:     RQHN A -1; Stop;	// kept: the set's own name for the open hand
	Fist:     RQHN H -1; Stop;
	Hidden:   TNT1 A -1; Stop;
	}
}

class RSQ_HandHandler : EventHandler
{
	// hands on/off, so the set still plays without them
	transient CVar cvHands, cvSwap;

	override void WorldTick()
	{
		for (int n = 0; n < MAXPLAYERS; n++)
		{
			if (!playeringame[n])
				continue;
			let p = players[n];
			let mo = p.mo;
			if (!mo || mo.health <= 0)
				continue;

			let side = RSQ_GunSide(mo.FindInventory('RSQ_GunSide'));
			if (!side)
			{
				mo.GiveInventory('RSQ_GunSide', 1);
				side = RSQ_GunSide(mo.FindInventory('RSQ_GunSide'));
			}
			let hands = RSQ_Hands(mo.FindInventory('RSQ_Hands'));
			if (!hands)
			{
				mo.GiveInventory('RSQ_Hands', 1);
				hands = RSQ_Hands(mo.FindInventory('RSQ_Hands'));
			}
			if (!side || !hands)
				continue;
			// park it as the off-hand weapon: without this the free hand draws
			// on the MAIN controller (models.cpp:221) and nothing is placed
			// PATCHED BY HAND 2026-10-22: through PendingWeapon as BD22 does, so the
			// engine brings it up and makes its PSP_OFFHANDWEAPON psprite (see Default)
			if (!p.OffhandWeapon && p.PendingWeapon == WP_NOCHANGE)
				p.PendingWeapon = hands;

			if (!cvHands)
				cvHands = CVar.GetCVar('ae_hands', p);
			bool on = !cvHands || cvHands.GetInt() != 0;
			if (!cvSwap)
				cvSwap = CVar.GetCVar('ae_lefthanded', p);
			bool swap = cvSwap && cvSwap.GetBool();

			// Even with hands off, the off-hand weapon has to be present and
			// parked: the magazine carried during a reload is one of its layers.
			int i = on ? RSQ_HandTable.Index(p.ReadyWeapon) : 0;
			String g = i > 0 ? RSQ_HandTable.GunPose(i) : "";
			String s = i > 0 ? RSQ_HandTable.SupportPose(i) : "";
			// the support hand shows only while the engine is two-hand
			// steadying, as BD22 does: otherwise the off hand is free
			bool steady = (p.WeaponState & WF_TWOHANDSTABILIZED) != 0;

			// Handedness: which ACTOR owns a layer decides which controller draws
			// it -- models.cpp:221 sends a layer to the off controller only when
			// its caller is the player's OffhandWeapon. So swapping the owners
			// swaps the hands, and no fit, hook or pose changes.
			Actor gunOwner  = swap ? Actor(hands) : Actor(side);
			Actor freeOwner = swap ? Actor(side)  : Actor(hands);
			// the index finger rests on the trigger and squeezes while fire is held
			String tf = i > 0 ? RSQ_HandTable.Trigger(i) : "";
			String gl = tf != "" ? ((p.cmd.buttons & BT_ATTACK) ? "Sqz" .. tf : "Trg" .. tf)
			                     : "Gun" .. g;
			// FIXED 2026-10-23: dual detection moved up from below, because it decides whether
			// RSQ_GunSide's hands may be drawn at all.
			//
			// While a gun is in the off hand, hw_weapon.cpp GetWeaponPosition3D (:332) routes
			// EVERY layer whose caller is not the ready weapon through the OFF-HAND weapon's
			// psprite, and :943-948 then looks ModifyBobLayer3D up on that actor's class and
			// nulls it unless that class overrides it. The off-hand weapon is then an AE_Off_*
			// copy from DECORATE.aedual, which cannot override a ZScript virtual (a ZScript
			// class may not inherit a DECORATE actor -- verified on this engine: "Class ... has
			// unknown base class M4A3Pistol_3D"). So the hook, the recoil follow and the frame
			// follow are all lost for the gun hand, the support hand and the ammo counter --
			// they would sit at the raw controller pose. BD22 1.92 hit this and did not fight
			// it (zscript/rsq/dualhands.zs): it stands RSQ_Hands' own layers down and draws
			// each gun's hand on a layer CALLED BY THAT GUN, hook baked into Offset. This pack
			// had ported only the off-hand half of that, so turning dual on moved the MAIN
			// hand off the gun too. The main half is MAINGUN below.
			let offw = p.OffhandWeapon;
			bool dual = offw && !(offw is 'RSQ_Hands');

			// A running reload has the off hand and decides what it shows (open / holding the
			// magazine / closed on the handle). "" = idle. Moved above the support hand
			// 2026-10-23: the closeness rule below must not fire mid-reload.
			String rsr = RSR_Handler.FreeHand(mo);
			if (rsr == "")
				rsr = RSP_Handler.FreeHand(mo);	// RSR-PUMP: the shell hold / the closed hand on the pump (BD22 1.92)

			// ADDED 2026-10-23, ported from BD22 1.92 hands.zs (owner's fix of 2026-10-16):
			// on a CUP-SUPPORT gun the support hand shows by CLOSENESS, not only while the
			// engine is two-hand steadying. The engine's steadying aims the gun along the
			// hand-to-hand line, which is right for a long gun and wrong for a two-hand pistol
			// grip -- so bring the off hand to the grip and both hands are on the gun while it
			// still aims from the gun hand alone. Pressing grip steadies as stock, untouched.
			// Support pose "A" is Ermac's pistol cup, which here is exactly the four pistols
			// (SupportPose indices 3, 4, 9, 12). 13 cm in, 18 cm out so it cannot flicker.
			bool hold = steady;
			// InVR gate added 2026-10-23: SteadyGap reads AttackPos/OffhandPos, which the engine
			// writes ONLY for a local player who is actually in VR (hw_vrmodes.cpp). Without the
			// gate they both read zero in desktop play and for every other player in a co-op
			// game, the gap computes as 0 cm, and this hand would be glued on for every pistol.
			// counter.zs gates the same way.
			if (!hold && !dual && i > 0 && hands && RSVR_VRHand.InVR(mo)
			    && RSQ_HandTable.SupportPose(i) == "A" && rsr == "")
				hold = RSVR_VRHand.SteadyGap(mo) < (hands.holding ? 18.0 : 13.0);
			if (hands)
				hands.holding = hold;

			// 2026-10-23: the gun hand's OWN pose changes with the second hand, as BD22 1.92
			// does (`String g = hold ? GunTwo(i) : GunOne(i)`). Until now this pack had one
			// letter per gun and it was the two-handed grip, so a pistol held in one hand was
			// still posed as though the other hand were on it. The letters and their trigger
			// frames came out of BD22's own hand.md3 -- the same Ermac mesh, no new art.
			// Recomputed here rather than at the top because `hold` is not known until now.
			if (i > 0)
			{
				g = hold ? RSQ_HandTable.GunTwo(i) : RSQ_HandTable.GunOne(i);
				String t1 = hold ? RSQ_HandTable.Trigger(i) : RSQ_HandTable.TriggerOne(i);
				gl = t1 != "" ? ((p.cmd.buttons & BT_ATTACK) ? "Sqz" .. t1 : "Trg" .. t1)
				              : "Gun" .. g;
			}

			SetLayer(p, RSQ_Layers.GUNHAND, gunOwner, (!dual && g != "") ? gl : "Hidden");
			SetLayer(p, RSQ_Layers.SUPPORT, gunOwner, (!dual && hold && s != "") ? "Sup" .. s : "Hidden");
			// Dual: the off hand holds a gun, so it shows that gun's grip pose
			// on OFFGUN and the free hand stands down. The pose comes from the
			// same table -- a second pistol is held the way the first one is.
			int oi = dual ? RSQ_HandTable.Index(offw) : 0;
			String og = oi > 0 ? RSQ_HandTable.GunPose(oi) : "";
			String ot = oi > 0 ? RSQ_HandTable.Trigger(oi) : "";
			// A baked Offset cannot carry a rotation, so only guns whose GunRot is (0,0,0) can
			// be held this way -- BD22 1.92 gates on exactly this to skip its axe and chainsaw
			// (dualhands.zs Hand()). Here it rules out the smartguns, satchels and knives.
			bool obake = oi > 0 && RSQ_HandTable.GunRot(oi) == (0, 0, 0);
			String ol = "Hidden";
			if (on && dual && obake && ot != "")
				ol = ((p.cmd.buttons & BT_OFFHANDATTACK) ? "DSqz" : "DTrg") .. ot;
			else if (on && dual && obake && og != "")
				ol = "DGun" .. og;
			// states from RSQ_Hands, caller the gun (MODELDEF.aedual binds the hand to the gun's class)
			SetLayer(p, RSQ_Layers.OFFGUN, dual ? Actor(offw) : null, ol, hands, true);
			// ADDED 2026-10-23 (BD22 1.92 dualhands.zs MAINGUN): the main gun's hand, called by
			// the main gun so its block in MODELDEF.aemain places it with the hook baked into
			// Offset. Same GunRot gate as the off hand; same states, from RSQ_Hands.
			String ml = "Hidden";
			if (on && dual && i > 0 && RSQ_HandTable.GunRot(i) == (0, 0, 0))
			{
				if (tf != "")
					ml = ((p.cmd.buttons & BT_ATTACK) ? "DSqz" : "DTrg") .. tf;
				else if (g != "")
					ml = "DGun" .. g;
			}
			SetLayer(p, RSQ_Layers.MAINGUN, dual ? Actor(p.ReadyWeapon) : null, ml, hands, true);

			// 2026-10-23: the other half of the follow. PSPF_ADDWEAPON above carries the gun's
			// OFFSET animation; the mesh recoil does not live in Offset -- it is in the model
			// frames, measured per gun by the kit's ae_gunmoves_gen.py into RSQ_GunMoves. The
			// non-dual hands get it through RSQ_Place.Layer, which these layers never reach. So
			// add it here by writing the layer's own x/y, which hw_weapon.cpp:108 reads back as
			// (mx / 4, (my - WEAPONTOP) / -4) degrees of yaw and pitch: to ask for a turn,
			// x = yaw * 4 and y = WEAPONTOP - pitch * 4, on top of the 0 rest value set above.
			// Only the turn can be carried this way -- frameMove is a translation and MODELDEF
			// Offset is static -- so the hand turns with the kick but does not travel with it.
			// Applied below, after FollowGun has refreshed the cache for THIS tic. Only the main
			// gun's hand gets it: RSQ_Hands.gunTurn is the READY weapon's frame turn, and there
			// is no equivalent cache for the off gun, so using it on the off hand would turn
			// that hand by the wrong gun's recoil. The off hand keeps the Offset follow only.
			// 2026-10-23: wearing the Power Loader replaces the free hand with the loader's
			// left arm. Same layer, same caller, same owner -- only the state differs.
			bool ldr = AE_LoaderHandler.Worn(mo) && AE_LoaderHandler.ArmsOn();
			SetLayer(p, RSQ_Layers.FREEHAND, freeOwner,
			         ldr ? "AEArmL"
			             : dual ? "Hidden" : rsr != "" ? rsr : (on && !hold) ? "Open" : "Hidden");
			// recoil-follow: what the gun's model frame is doing this tic (RSQ_Place.Layer reads it)
			hands.FollowGun(p, RSQ_HandTable.Index(p.ReadyWeapon));

			// 2026-10-23, the mesh half of the dual-hand recoil follow (see MAINGUN above).
			// Done here because FollowGun has just refreshed gunTurn for this tic.
			if (dual)
			{
				let mp = p.FindPSprite(RSQ_Layers.MAINGUN);
				if (mp)
				{
					// oldx/oldy MUST be carried by hand. Nothing in the playsim advances them:
					// p_pspr.h:114 ResetInterpolation() is the only thing that writes them, and
					// hw_weapon.cpp calls it on firstTic only, then interpolates
					// oldx + (x - oldx) * ticFrac every frame. Leave them and they stay at 0
					// for good, so the turn ramps from zero to target inside EVERY tic -- a
					// shake, not a follow. Setting old to last tic's value is what makes it
					// smooth; this runs exactly once per tic (WorldTick).
					double nx = hands.gunTurn.x * 4;
					double ny = -hands.gunTurn.y * 4;	// rest is 0 on this layer, not WEAPONTOP
					mp.oldx = mp.x;
					mp.oldy = mp.y;
					mp.x = nx;
					mp.y = ny;
				}
			}
			// 2026-10-23: the counter is on RSQ_GunSide, so while dual it cannot be placed
			// either (same nulling). A null owner makes Tick clear the layer -- the LED window
			// goes dark rather than sliding off the receiver, which is BD22's rule of clearing
			// what it can no longer place.
			RSQ_Counter.Tick(p, mo, dual ? null : side);
		}
	}

	// Only touch a layer when its state actually changes, or the pose restarts
	// every tic and never blends.
	// followGun (2026-10-23): for the DUAL hand layers only. Those are called by their gun, so
	// hw_weapon.cpp nulls ModifyBobLayer3D for them and RSQ_Place.Layer never runs -- the hook
	// is baked into MODELDEF instead. But the firing animation still has to reach the hand, and
	// it can without the hook: hw_weapon.cpp:108 draws a HUD model at
	//     rotation + (mx / 4, (my - WEAPONTOP) / -4, 0)
	// and :432 adds the GUN psprite's own x/y into this layer's mx/my for any layer carrying
	// PSPF_ADDWEAPON that is not PSP_WEAPON/PSP_OFFHANDWEAPON. So the gun's Offset -- which is
	// what its fire and reload animations move -- turns the hand with it, for free.
	// With the flag on, this layer's own y must be 0: the gun now supplies WEAPONTOP, and
	// keeping both is the 8-degree tilt the note below warns about ((32+32-32)/-4 = -8).
	static void SetLayer(PlayerInfo p, int id, Actor caller, String label, Actor stateOwner = null,
	                     bool followGun = false)
	{
		if (!caller)
		{
			let old = p.FindPSprite(id);
			if (old)
				old.Destroy();
			return;
		}
		State want = (stateOwner ? stateOwner : caller).FindStateByString(label);
		let psp = p.FindPSprite(id);
		if (psp && psp.Caller == caller && psp.CurState == want)
			return;
		p.SetPsprite(id, want, false, caller);
		psp = p.FindPSprite(id);
		if (psp)
		{
			psp.bAddWeapon = followGun;
			psp.bAddBob = true;
			// a fresh layer has y 0, which tilts a HUD model 8 degrees -- unless followGun is on,
			// in which case the gun layer's own y is added and 0 is the correct rest value.
			psp.y = followGun ? 0 : WEAPONTOP;
			psp.oldy = psp.y;
		}
	}
}

// Turns the way ModifyBobLayer3D gives them: models.cpp RenderHUDModel turns
// yaw about y, then pitch about x, then roll about z (degrees), in the hand
// models' frame before the MODELDEF scale (x left, y up, z back). A turn is
// kept as the three rows of its matrix.
class RSQ_Turn abstract
{
	clearscope static Vector3, Vector3, Vector3 Rows(Vector3 a)
	{
		double cx = cos(a.x), sx = sin(a.x);
		double cy = cos(a.y), sy = sin(a.y);
		double cz = cos(a.z), sz = sin(a.z);
		return (cx * cz + sx * sy * sz, -cx * sz + sx * sy * cz, sx * cy),
			(cy * sz, cy * cz, -sy),
			(-sx * cz + cx * sy * sz, sx * sz + cx * sy * cz, cx * cy);
	}

	clearscope static Vector3 Angles(Vector3 r0, Vector3 r1, Vector3 r2)
	{
		return (atan2(r0.z, r2.z), asin(clamp(-r1.z, -1., 1.)), atan2(r1.x, r1.y));
	}

	// the rows of a * b
	clearscope static Vector3, Vector3, Vector3 Mul(Vector3 a0, Vector3 a1, Vector3 a2, Vector3 b0, Vector3 b1, Vector3 b2)
	{
		Vector3 c0 = (b0.x, b1.x, b2.x);
		Vector3 c1 = (b0.y, b1.y, b2.y);
		Vector3 c2 = (b0.z, b1.z, b2.z);
		return (a0 dot c0, a0 dot c1, a0 dot c2), (a1 dot c0, a1 dot c1, a1 dot c2), (a2 dot c0, a2 dot c1, a2 dot c2);
	}

	// v turned back (by the transpose)
	clearscope static Vector3 Back(Vector3 r0, Vector3 r1, Vector3 r2, Vector3 v)
	{
		return r0 * v.x + r1 * v.y + r2 * v.z;
	}

	// Where a gun-side hand goes, and how it turns, so that it stays where it
	// holds the gun. hook / hookTurn: its place on the gun at rest (the hand
	// table). gunTurn: the gun layer's turn, about pivot (the gun model's turning
	// point from the hands'). frameTurn / frameMove: how the gun's model frame
	// has moved it off its ready frame. rsq_gunmoves_gen.py checks this against
	// RenderHUDModel's chain.
	clearscope static Vector3, Vector3 Place(Vector3 hook, Vector3 hookTurn, Vector3 gunTurn, Vector3 frameTurn, Vector3 frameMove, Vector3 pivot)
	{
		Vector3 q0, q1, q2, k0, k1, k2, h0, h1, h2, a0, a1, a2, e0, e1, e2;
		[q0, q1, q2] = Rows(gunTurn);
		[k0, k1, k2] = Rows(frameTurn);
		[h0, h1, h2] = Rows(hookTurn);
		[a0, a1, a2] = Mul(q0, q1, q2, k0, k1, k2);
		[e0, e1, e2] = Mul(a0, a1, a2, h0, h1, h2);
		Vector3 v = frameMove + Back(k0, k1, k2, Back(q0, q1, q2, pivot) - pivot);
		return hook + Back(h0, h1, h2, v), Angles(e0, e1, e2);
	}
}
