# Boss Frames

A target plate plugin for the AC:Unreal client. Add the names of the bosses you hunt, and when one is nearby the client draws a plate on it with its name, level, health and your debuffs. Plate details come from the client's target data, which it refreshes in the background without changing your selection.

<img width="1317" height="1370" alt="ACUnreal Screenshot 2026 10 26 - 15 18 58 46" src="https://github.com/user-attachments/assets/9f66389f-d817-41d6-94ce-0fec3945617d" />

## Features

- Plates on up to 4 nearby bosses, nearest first, without selecting them.
- Name, title, level and health, stamina and mana bars.
- Your own debuffs on the boss, with timers.
- A Nearby list with a **Select** button for each boss in range.
- Add bosses by typing a name, or with **Add selected**.
- Plate color, plate opacity, background opacity, bars, debuffs, level, role line, plates only on your selected target, and range (adjustable in settings).
- Your boss list and settings are retained per character.

## Requirements

- AC:Unreal client build 137 (2026.10.25) or newer. Plate opacity needs build 138 (2026.10.26).

## Install

1. Download the latest zip from the [Releases](../../releases) page.
2. Unzip into `ACUnreal\Saved\ClientPlugins\Installed`. The zip contains the `BossFrames` folder, so the path ends in `Installed\BossFrames\plugin.json`.
3. Open the plugin menu, press **Refresh**, then **Enable** Boss Frames.

## Good to know

- Names match exactly, ignoring letter case.
- Health on your selected target updates immediately. On other bosses it shows as a percentage and refreshes every few seconds.
- Debuff timers are estimates of your own successful casts. Other players' spells aren't shown.

## Permissions

The plugin uses the following service requests:

| Permission | Used for |
|---|---|
| ui | its window |
| markers | the plates |
| state | saving your boss list and settings |

## License

MIT. See [LICENSE](LICENSE).
