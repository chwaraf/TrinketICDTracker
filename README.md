# Trinket ICD Tracker

A small World of Warcraft TBC Anniversary addon that displays an internal cooldown countdown for supported trinkets.

## Supported trinkets

- Sextant of Unstable Currents (item ID: `30626`)
  - Proc: Unstable Currents (spell ID: `38348`)
  - Internal cooldown: 45 seconds

## Features

- Automatically detects the trinket proc through the combat log.
- Starts a 45-second internal cooldown when the proc buff is applied to the player.
- Shows the trinket icon and Blizzard-style cooldown swipe.
- Uses Blizzard's native cooldown number display, following the **Show Numbers for Cooldowns** interface option.
- Only displays timers for supported trinkets currently equipped.
- Keeps the timer state if the trinket is temporarily removed and shows the remaining time if it is re-equipped.
- Easy to extend by adding entries to the `TRINKETS` table in `TrinketICDTracker.lua`.
- Saves the display position and settings between sessions.

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
2. Trigger its spell-critical proc in combat.
3. The Sextant icon and cooldown swipe will appear at the center of the screen by default.
4. To show the numeric countdown, enable **Show Numbers for Cooldowns** in the Blizzard interface options. The addon uses the same native cooldown text as action-bar and item cooldowns.
5. Drag the icon to move it. Use `/tic lock` to prevent accidental movement.

The internal cooldown starts when the **Unstable Currents** proc is applied, not when the 15-second buff expires.

## Slash commands

- `/tic help` — show available commands.
- `/tic debug` — toggle combat-log debug output. This is useful for checking whether the proc event is being received.
- `/tic lock` — lock the tracker position.
- `/tic unlock` — allow the tracker to be dragged.
- `/tic reset` — reset the tracker position.
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
