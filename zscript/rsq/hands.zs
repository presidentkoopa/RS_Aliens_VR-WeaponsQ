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
	clearscope static Vector3 Offset(PlayerInfo p, int i)
	{
		bool pistol = i == 3 || i == 4 || i == 9 || i == 12;
		String f = pistol ? "ae_pistolhand_fwd" : "ae_gunhand_fwd";
		String u = pistol ? "ae_pistolhand_up"  : "ae_gunhand_up";
		String s = pistol ? "ae_pistolhand_side" : "ae_gunhand_side";
		return (RSQ_HandTune.Get(p, s), RSQ_HandTune.Get(p, u), -RSQ_HandTune.Get(p, f));
	}
	clearscope static Vector3 SupportOffset(PlayerInfo p)
	{
		return (Get(p, "ae_support_side"), Get(p, "ae_support_up"), -Get(p, "ae_support_fwd"));
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
		// PATCHED BY HAND 2026-10-22: owner-tunable rest offset for the gun hand (Options >
		// Aliens VR > "Gun hand forward/up/side", cm). The owner tunes in the headset and
		// bakes the numbers into GunHook afterwards. Pistols and the rest have their own.
		if (layer != RSQ_Layers.SUPPORT && layer != RSQ_Layers.COUNTER)
			hook += RSQ_HandTune.Offset(p, i);
		if (layer == RSQ_Layers.SUPPORT)
			hook += RSQ_HandTune.SupportOffset(p);	// 2026-10-22 (owner): the support hand has its own sliders
		if (i == 7 || i == 14)
			rot += RSQ_HandTune.SatchelTurn(p);	// 2026-10-22 (owner): the satchel hand can be turned from the menu
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
			SetLayer(p, RSQ_Layers.GUNHAND, gunOwner, g != "" ? gl : "Hidden");
			SetLayer(p, RSQ_Layers.SUPPORT, gunOwner, (steady && s != "") ? "Sup" .. s : "Hidden");
			// A running reload has the off hand and decides what it shows
			// (open / holding the magazine / closed on the handle). "" = idle.
			String rsr = RSR_Handler.FreeHand(mo);
			if (rsr == "")
				rsr = RSP_Handler.FreeHand(mo);	// RSR-PUMP: the shell hold / the closed hand on the pump (BD22 1.92)
			// Dual: the off hand holds a gun, so it shows that gun's grip pose
			// on OFFGUN and the free hand stands down. The pose comes from the
			// same table -- a second pistol is held the way the first one is.
			let offw = p.OffhandWeapon;
			bool dual = offw && !(offw is 'RSQ_Hands');
			int oi = dual ? RSQ_HandTable.Index(offw) : 0;
			String og = oi > 0 ? RSQ_HandTable.GunPose(oi) : "";
			String ot = oi > 0 ? RSQ_HandTable.Trigger(oi) : "";
			String ol = "Hidden";
			if (on && dual && ot != "")
				ol = ((p.cmd.buttons & BT_OFFHANDATTACK) ? "DSqz" : "DTrg") .. ot;
			else if (on && dual && og != "")
				ol = "DGun" .. og;
			// states from RSQ_Hands, caller the gun (MODELDEF.aedual binds the hand to the gun's class)
			SetLayer(p, RSQ_Layers.OFFGUN, dual ? Actor(offw) : null, ol, hands);
			SetLayer(p, RSQ_Layers.FREEHAND, freeOwner,
			         dual ? "Hidden" : rsr != "" ? rsr : (on && !steady) ? "Open" : "Hidden");
			// recoil-follow: what the gun's model frame is doing this tic (RSQ_Place.Layer reads it)
			hands.FollowGun(p, RSQ_HandTable.Index(p.ReadyWeapon));
			RSQ_Counter.Tick(p, mo, side);
		}
	}

	// Only touch a layer when its state actually changes, or the pose restarts
	// every tic and never blends.
	static void SetLayer(PlayerInfo p, int id, Actor caller, String label, Actor stateOwner = null)
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
			psp.bAddWeapon = false;
			psp.bAddBob = true;
			// a fresh layer has y 0, which tilts a HUD model 8 degrees
			psp.y = WEAPONTOP;
			psp.oldy = WEAPONTOP;
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
