# SimpleMonitorBars

SimpleMonitorBars is a lightweight World of Warcraft addon for building customizable monitor bars for:

- spell charges and cooldowns
- buff stacks
- buff durations

The addon is designed for players who want compact, configurable tracking without a large UI framework or a full combat package.

## Features

- Create custom bars for cooldown, charge, stack, and duration tracking
- Build bars directly from the Blizzard cooldown viewer spell catalog
- Support player- and target-based aura monitoring
- Separate configuration for bar size, texture, color, borders, and strata
- Optional tint thresholds with two configurable threshold colors
- Optional icon display
- Independent text controls for:
  - stack / cooldown / duration text
  - spell or buff name text
- Specialization-based visibility
- Profile support with import / export
- Overview page showing enabled bars by specialization
- Integration with Blizzard cooldown viewer data for tracked buffs and cooldowns

## Requirements

- World of Warcraft Retail
- Interface versions:
  - `120001`
  - `120000`

## Installation

1. Download or clone this repository.
2. Place the `SimpleMonitorBars` folder into:

```text
World of Warcraft/_retail_/Interface/AddOns/
```

3. Restart the game or reload the UI.

## Usage

- Open the settings with:

```text
/smb
```

- Main settings sections:
  - `Class Overview`
  - `Monitor Settings`
  - `Profiles`

### Monitor Settings

In the monitor settings tab you can:

- add a new monitor bar from the spell catalog
- choose the monitored spell or aura
- select the bar type:
  - stack
  - charge / cooldown
  - duration
- configure display conditions, unit, class, and specialization visibility
- adjust size, colors, textures, borders, animation, and text options

### Profiles

The addon supports:

- per-character profiles
- config import / export
- profile copy, reset, and deletion

## Notes

- Buff stack and duration tracking rely on Blizzard cooldown viewer data for some monitored effects.
- Some auras must be tracked by Blizzard's own cooldown manager before they can be monitored correctly.
- The addon includes an Edit Mode shortcut in its settings window for easier positioning workflows.

## Slash Commands

```text
/smb
/simplemonitorbars
```

## Project Structure

```text
Core/         Defaults, config, profile transfer, and schema updates
Bars/         Runtime scanning and bar rendering
Skins/        Settings UI
Locales/      Localization files
Media/        Textures and icon assets
Libs/         Embedded libraries
```

## License

All Rights Reserved. See [LICENSE](LICENSE).
