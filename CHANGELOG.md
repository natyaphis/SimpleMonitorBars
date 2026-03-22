# Changelog

All notable changes to this project will be documented in this file.

## 1.4.3

- Refined monitor settings and configuration handling.

## 1.4.2

- Refined monitor settings and configuration handling.
- Updated localization text across supported locales.

## 1.4.1

- Refined monitor settings and configuration handling.
- Updated localization text across supported locales.

## 1.4.0

- Refined monitor settings and configuration handling.
- Updated localization text across supported locales.

## 1.3.9

- Adjusted monitor bar runtime behavior.

## 1.3.8

- Updated localization text across supported locales.

## 1.3.7

- Adjusted monitor bar runtime behavior.

## 1.3.6

- Adjusted monitor bar runtime behavior and rendering logic.

## 1.3.5

- Adjusted linear duration bars so they now drain from full to empty by default, matching expected buff-duration behavior.
- Kept `Reverse Growth` available for players who want the duration bar to fill in the opposite direction.

## Unreleased

- Maintenance update

## 1.3.4

- Removed ring monitor support from duration bars, including the related rendering path, settings, localization entries, and bundled ring textures.
- Normalized migrated monitor bar configs to use the standard bar shape and cleared obsolete ring-only settings from saved data.
- Kept the standard bar mask path intact after the ring cleanup so monitor bars still build and render normally.

## 1.3.3

- Maintenance update.

## 1.3.2

Changes since 1.3.2:

- Updated `Bars/Bars.lua`

## 1.3.1

- Fixed charge bar regressions so recharge text respects the display toggle and recharge textures stay clipped inside the bar container.
- Kept the newly added monitor bar selected in the monitor-management dropdown after adding it from the catalog.
- Added vertical monitor and reverse-growth options for linear bars, and expanded size slider ranges to 5-500 for both width and height.
- Added `Asset/Skillset.txt` to document recommended default values for addable skills and buffs; `Asset/` remains excluded from packaged addon builds.
- Updated localization text, including the base-layer color label in zhCN and labels for the new orientation controls.

## 1.2.1

- Initial tracked release notes for SimpleMonitorBars
