# Boss Frames

A target plate plugin for the AC:Unreal client. Add the names of the bosses you hunt, and when one is nearby the client draws a plate on it with its name, level, health and your debuffs. Plate details come from the client's target data, which it refreshes in the background without changing your selection.

## Features

- Plates on up to 4 nearby bosses, nearest first, without selecting them.
- Name, title, level and health, stamina and mana bars.
- Your own debuffs on the boss, with timers.
- **Show boss frames** at the top of the window turns the plates, minimap diamonds and alerts on or off. Your list and settings are kept.
- Optional chat alert when a boss comes into range, in the plate color: `[Boss Frames] Elder Chaos Dragon is in range (85 m)`. One line per boss; a boss that steps out and back within 60 seconds doesn't alert again, and a respawned boss does. Only you see it.
- Optional minimap diamonds, in the plate color, for up to 16 bosses in range.
- Add bosses by typing a name, or with **Add selected**.
- Plate color, plate opacity, background opacity, bars, debuffs, level, role line, plates only on your selected target, range, chat alert and minimap diamonds (adjustable in settings). The alert and diamonds are off by default.
- Your boss list and settings are retained per character.

## Requirements

- AC:Unreal client v146 or newer.
- Works on any ACE server.

## Install

1. Download the latest zip from the [Releases](../../releases) page.
2. Unzip into `ACUnreal\Saved\ClientPlugins\Installed`. The zip contains the `BossFrames` folder, so the path ends in `Installed\BossFrames\plugin.json`.
3. Open the plugin menu, press **Refresh**, then **Enable** Boss Frames.

## Updating

Replace the files in `Installed\BossFrames` with the new download and press **Refresh** in Manage Plugins. Your boss list and settings are saved outside this folder, so they are retained.

## Good to know

- Names match exactly, ignoring letter case.
- Health on your selected target updates immediately. On other bosses it shows as a percentage and refreshes every few seconds.
- If the plugin stops with an error, the message shows in its status line in Manage Plugins.
- Debuff timers are estimates of your own successful casts. Other players' spells aren't shown.

## Permissions

The plugin uses the following service requests:

| Permission | Used for |
|---|---|
| ui | its window and the chat alert (a local line only you see) |
| markers | the plates and minimap diamonds |
| state | saving your boss list and settings |

## License

MIT. See [LICENSE](LICENSE).
