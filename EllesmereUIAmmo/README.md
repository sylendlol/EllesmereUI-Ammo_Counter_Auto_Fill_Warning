# EllesmereUI Ammo Counter

An ammo counter for Hunters, built as a module for the **Dworak** section of [EllesmereUI](https://www.curseforge.com/wow/addons/ellesmereui).
It shows how much ammo you carry, warns you before you run dry, and restocks your quiver at a vendor with one click.

Made for **WoW Forever** (Interface 16001) with **EllesmereUI 9.5.4**. The `.toc` also lists the 12.0.x interface numbers.

```
[icon]  1,240           ← ammo left (Text color / Low color / Critical color)
        Jagged Arrow    ← optional: the ammo's name
```

## Features

### Counter
- **Ammo left:** counts the equipped arrows or bullets and every stack of the same ammo in your bags. With a thrown weapon, it counts the thrown stack itself.
- **Optional ammo name** on the second line.
- **Color levels:** the *Text* color (white by default) normally, the *Low* color under the Low threshold (default 400), the *Critical* color under the Critical threshold (default 100). All three colors can be changed.
- **No ammo equipped:** shows *No ammo* and tells you if matching ammo is sitting in your bags.
- Hidden with a wand or no ranged weapon. Can also stay hidden until you go under Low (*Only When Low*).

### Warnings
- A raid-warning style message on screen when the count drops under Low, under Critical, or to zero, or when no ammo is equipped.
- Optional warning sound and chat message.
- Optional check a few seconds after login and zoning, so you know before the first pull.
- Warnings fire only when the count goes down. Restocking or swapping ammo resets them quietly.

### Vendor restock
- A **Restock Ammo** button appears under the merchant window, for example `Restock Ammo +800`. Its tooltip shows what it will buy and what it costs.
- **Target:** fills your quiver or ammo pouch to capacity (slots × stack size) by default, or buys up to a fixed amount (*Restock To*, default 1000).
- Buys whole vendor bundles and never more than your bags can hold, your money covers, or the optional *Max Spend* cap (in gold) allows.
- **Best Ammo Fallback:** if the vendor doesn't sell your equipped ammo, it buys the best arrows or bullets you can use and reminds you to equip them.
- **Auto Buy** (off by default) restocks as soon as you open the vendor, without a click.

### Look
- Ammo icon with an adjustable border: 0–6 px (0 removes it), in the UI Accent Color or a custom color. Under Low or Critical, the border takes that level's color.
- Icon size, font, text size, text color, and background color and opacity can all be set.
- Movable in EllesmereUI **Unlock Mode** (group *Dworak*).
- The UI Accent Color from Global Settings applies live.
- The settings page has a live preview that cycles through the normal, low, critical and empty states.

## Requirements

- [EllesmereUI](https://www.curseforge.com/wow/addons/ellesmereui)
- **EllesmereUIDworak**, the host addon that owns the *Dworak* section of the EllesmereUI panel

## Installation

1. Copy the `EllesmereUIAmmo` folder into `World of Warcraft\_classic_beta_\Interface\AddOns\`. Use your client's own folder if it's different.
2. Make sure `EllesmereUI` and `EllesmereUIDworak` are installed and enabled.
3. Log in or `/reload`. The module appears under **EllesmereUI → Dworak → Ammo Counter**.

## Commands

| Command | What it does |
| --- | --- |
| `/ammo` or `/euiammo` | Opens the settings page |
| `/ammo debug` | Prints the detected weapon, ammo slot, count and quiver room. At a vendor, it also prints the restock plan |
| `/ammo test` | Fires a sample Critical warning |

## Settings

| Section | Options |
| --- | --- |
| Ammo Counter | On/off, Hunters Only, Low and Critical thresholds (with colors) |
| Display | Only When Low, Show Ammo Name, Show Icon, Icon Size, Icon Border, Border Color, Font, Text Size, Text Color, Background |
| Warnings | Screen Warning, Warning Sound, Chat Message, Check on Login |
| Vendor Restock | Restock Button, Auto Buy, Fill Quiver, Restock To, Max Spend (gold), Best Ammo Fallback |

Settings are saved per EllesmereUI profile in `EllesmereUIAmmoDB`.

## How it works

- **Weapon type** comes from the ranged slot's item class. Bows and crossbows use arrows and a quiver, guns use bullets and an ammo pouch, a thrown weapon counts itself, and a wand hides the counter.
- **Ammo slot:** `INVSLOT_AMMO`, falling back to `GetInventorySlotInfo("AMMOSLOT")`. If the client has no ammo slot, the counter stays hidden for bows and guns.
- **Purchases:** `BuyMerchantItem(index, quantity)` with the quantity in items, in multiples of the vendor bundle, at most `GetMerchantItemMaxStack` per call and 0.3 s apart. Buying stops if the vendor list changes in the meantime.
- **Secret values:** every value read from the client passes the 12.0 secret-value check before use.
- No EllesmereUI file is modified. The module registers through `EllesmereUIDworak.AddModule`.

## Known limitations

- **Early version, not yet tested in game.** Please report anything odd together with the `/ammo debug` output.
- Two client behaviours are assumed rather than confirmed:
  - that the WoW Forever client keeps the classic ammo slot and consumes arrows;
  - that `BuyMerchantItem` takes the quantity in items, as Blizzard's own merchant window does.
- With Best Ammo Fallback, the new ammo has to be equipped by hand (right-click it in your bags).

## Author

Dworak
