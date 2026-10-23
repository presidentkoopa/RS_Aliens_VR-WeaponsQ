AliensVR Weapons -- Hands, Reload, Dual, Smartgun
=================================================

ONE FILE. This REPLACES _A03_AliensEradication_VR_addon_v1.0.pk3 -- it is that
addon with the VR weapon work merged in, so Quest players load three things
instead of four and cannot get the order or the versions wrong:

    _A01_ALIENS_ERADICATION_TC_2_0.pk3
    _A02_ERADICATION_MAPSET_2_0.wad
    AliensVR_Weapons.pk3          <- this, instead of _A03

Do NOT load _A03 as well. Every actor in it is in here.

WHAT IS ADDED ON TOP OF A03
  * VR hands on all 16 weapon classes, with a trigger finger on the 12 guns
  * Real VR reload: magazine out, grab a fresh one, insert it on the axis;
    the M37A2 feeds shells one at a time
  * Dual wield (pistol / shotgun / pulse rifle / flamer): each hand keeps its
    own magazine, both draw from one shared reserve
  * Body holsters: seven weapon slots, seven places on you to reach for
  * Flick down to reload
  * M56 Smartgun: its lock-on restored (A03 ships it bypassed by an
    unconditional A_Jump that makes its own target check unreachable), a
    harness gimbal that swings the gun onto a target while your hands stay
    put, and a physical fire selector on the receiver
  * Shotgun slug alt fire
  * Left handed

Options: Options -> Aliens VR Weapons.
The Dual key is bindable under Customize Controls -> Aliens VR Weapons.

WHAT CHANGED IN A03'S OWN FILES
  actors/weapons/{pistol,rifle,shotgun,smartgun,flamethrower}.txt
      the reload hook (each gun's ReloadWork enters the VR reload, its
      original kept as ReloadWork_Stock), the shotgun's slug mode, and the
      smartgun's lock-on
  mapinfo.txt
      the new event handlers, as AddEventHandlers. They are a second line
      rather than extra names on A03's own, because "EventHandlers =" replaces
      the list instead of adding to it.
Everything else in A03 is untouched.
