# Changelog

All notable changes to this project will be documented in this file.

## 1.3.1

- Reworked charge and cooldown monitoring to follow the VFlow-style cooldown viewer mapping more closely, including better override/base spell resolution and charge cooldown progress updates during combat.
- Fixed charge bar regressions so recharge text respects the display toggle and recharge textures stay clipped inside the bar container.
- Kept the newly added monitor bar selected in the monitor-management dropdown after adding it from the catalog.
- Added vertical monitor and reverse-growth options for linear bars, and expanded size slider ranges to 5-500 for both width and height.
- Added `Asset/Skillset.txt` to document recommended default values for addable skills and buffs; `Asset/` remains excluded from packaged addon builds.
- Updated localization text, including the base-layer color label in zhCN and labels for the new orientation controls.

## Unreleased

## 1.2.1

- Initial tracked release notes for SimpleMonitorBars
