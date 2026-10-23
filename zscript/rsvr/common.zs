// RS VR shared helpers. Taken verbatim from the kit's rsvr/common.zs.
//
// This file was missing from the pack and that is what "Class RSR_Go has
// unknown base class RSVR_Token" meant, twenty times over: the reload engine
// derives every one of its signal tokens from RSVR_Token, and only
// rsvr/vrhand.zs had been shipped out of that folder.

// an inventory flag: one of, never dropped
class RSVR_Token : Inventory
{
	Default
	{
		Inventory.MaxAmount 1;
		+INVENTORY.UNDROPPABLE
		+INVENTORY.UNTOSSABLE
	}
}

// The haptic pulse the reload fires at the controller. Lives in the kit's
// rsvr/melee.zs, which this pack does not ship -- vreload.zs calls
// SpawnPlayerMissile('RSVR_Buzz', ...) and an unknown class name there is a
// hard error, not a no-op. Copied verbatim rather than stubbed: a rumble that
// does not rumble is worse than no rumble, because it looks like it works.
class RSVR_Buzz : Actor
{
	Default
	{
		Projectile;
		+NOCLIP
		Radius 1;
		Height 1;
		Speed 1;
		DamageType "RSVRHaptic";
		RenderStyle "None";
	}
	States
	{
	Spawn:
		TNT1 A 1;
		Stop;
	}
}
