# Trinket ICD Tracker

A small World of Warcraft TBC Anniversary addon that displays an internal cooldown countdown for supported trinkets.

## Supported trinkets

- Sextant of Unstable Currents (item ID: `30626`)
  - Proc: Unstable Currents (spell ID: `38348`)
  - Internal cooldown: 45 seconds
- Serpent-Coil Braid (item ID: `30720`)
  - Trigger: consuming a Mage mana gem
  - Cooldown: 2 minutes, matching the mana-gem cooldown

## Features

- Automatically detects the trinket proc through the combat log.
- Starts a 45-second internal cooldown when the Sextant proc buff is applied to the player.
- Tracks Serpent-Coil Braid through the mana-gem use events and the shared cooldown on Mana Jade, Mana Agate, Mana Citrine, Mana Ruby, and Mana Emerald.
- Shows the Blizzard-style internal cooldown swipe directly on supported action-bar, character equipment, and TrinketMenu buttons.
- Adds the internal cooldown swipe and native countdown number to standard Blizzard action-bar buttons containing the supported trinket.
- Adds the internal cooldown to the default character-sheet trinket slots.
- Adds the internal cooldown to TrinketMenu's equipped-trinket buttons and bag menu entries when TrinketMenu is installed.
- Uses Blizzard's native cooldown number display, following the **Show Numbers for Cooldowns** interface option.
- Only displays timers for supported trinkets currently equipped.
- Keeps the timer state if the trinket is temporarily removed and shows the remaining time if it is re-equipped.
- Easy to extend by adding entries to the `TRINKETS` table in `TrinketICDTracker.lua`.
- Saves the enabled/debug settings between sessions.

## Installation

1. Download or copy the `TrinketICDTracker` folder.
2. Put it in your WoW Classic AddOns directory:
   `World of Warcraft/_anniversary_/Interface/AddOns/`
3. Make sure the folder contains:
   - `TrinketICDTracker.toc`
   - `TrinketICDTracker.lua`
4. Start the game or reload the UI with `/reload`.
5. If the addon is listed as out of date, enable **Load out of date AddOns**. The TOC targets the TBC Anniversary interface version.

## Usage

1. Equip the Sextant of Unstable Currents.
2. Place it directly on a standard Blizzard action bar, open the character equipment screen, or use TrinketMenu.
3. Trigger its spell-critical proc in combat, or consume a Mana Gem for Serpent-Coil Braid.
4. The internal cooldown swipe will appear on the matching action-bar, character-sheet, or TrinketMenu button.
5. For Serpent-Coil Braid, consume a Mana Gem while it is equipped; the tracker mirrors the gem's remaining two-minute cooldown.
6. To show the numeric countdown, enable **Show Numbers for Cooldowns** in the Blizzard interface options. The addon uses the same native cooldown text as action-bar and item cooldowns.

The internal cooldown starts when the **Unstable Currents** proc is applied, not when the 15-second buff expires.

## Slash commands

- `/tic help` — show available commands.
- `/tic debug` — toggle combat-log debug output. This is useful for checking whether the proc event is being received.
- `/tic enable` — enable the tracker.
- `/tic disable` — disable the tracker.

## Adding more trinkets

Add another entry to the `TRINKETS` table near the top of `TrinketICDTracker.lua`:

```lua
[ITEM_ID] = {
    name = "Trinket name",
    procSpellID = SPELL_ID_OF_PROC_BUFF,
    cooldown = INTERNAL_COOLDOWN_IN_SECONDS,
},
```

For example:

```lua
local TRINKETS = {
    [30626] = {
        name = "Sextant of Unstable Currents",
        procSpellID = 38348,
        cooldown = 45,
    },
    [30720] = {
        name = "Serpent-Coil Braid",
        cooldown = 120,
        trigger = "manaGem",
    },
    -- [12345] = {
    --     name = "Example trinket",
    --     procSpellID = 67890,
    --     cooldown = 60,
    -- },
}
```

After changing the table, reload the UI with `/reload`.

## Notes

This addon intentionally uses a small amount of code and has no external libraries. It tracks the internal cooldown locally and cannot reconstruct a proc that happened while the addon was disabled, the UI was reloading, or the player was offline.
