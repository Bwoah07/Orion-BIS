# Orion BiS

Raid wishlists for World of Warcraft. Pick your best-in-slot items boss by boss, see who in your guild wants what,
and get an alert when something on your list drops.

`/bis` opens the window. `/bis help` lists every command.

## Releases
To release, bump `## Version` in `OrionBiS.toc`, add a `CHANGELOG.md` entry and merge to `main`.
`.github/workflows/release.yml` sees the new version, tags it, packages the addon with the BigWigs packager and
uploads it to CurseForge and GitHub Releases. Pushes that don't change the version do nothing. The CurseForge
token lives in the repo secret `CF_API_KEY`.

## Files
- `Core.lua` lists, the ORIONBIS1 code format, guild sync, slash commands
- `Loot.lua` loot tables from the in-game Adventure Guide
- `UI/Theme.lua` the widget kit (flat colours, Inter font, no Blizzard templates)
- `UI/Main.lua` the window: Loot, My list, Guild, Settings
- `UI/Alert.lua` drop alert, roll-frame highlight, tooltip lines
- `UI/Minimap.lua` minimap button
- `Locales/` translations (English text is the key; missing strings fall back to English)

## Code format for websites
A guild site can generate a code that people paste in with `/bis import`. Example:

    ORIONBIS1;1790000000;Midnight Season 2;Raider-Draenor=1:250101b,250102u!

That's: format version, timestamp, raid name, then each player as `Name-Realm=classId:` followed by their
items. Each item is the item ID plus `b` (BiS), `u` (Upgrade) or `m` (Minor), with `!` if they already have it.
Items are separated by commas and players by semicolons. If a player shows up in two codes, the newer timestamp wins.

## Private guild data
A guild can ship its own lists in a separate addon folder named `OrionBiS_GuildData` whose Lua file sets
`ORION_BIS_DATA = { code = "ORIONBIS1;..." }`. Orion BiS loads it first and shares those lists in the guild.
Never publish that folder.

## Credits
Inter font by Rasmus Andersson, SIL Open Font License 1.1 (`Media/Fonts/Inter-LICENSE.txt`).
