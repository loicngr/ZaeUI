# ZaeUI_DungeonNotes

Take personal notes for each dungeon and raid. On instance entry, a small notification appears; click it to open your notes in a floating editor window.

Works with **Midnight (12.0.0+)**. 100% local — no cross-player sync, no network traffic, no dependencies on the broken addon messaging APIs.

## Features

- **Per-dungeon notes** — one free-form multi-line note per instance, indexed by WoW `instanceMapID`
- **Per-character storage** — each character has its own set of notes (via `SavedVariablesPerCharacter`)
- **Instance-entry notification** — a discreet button appears for a few seconds when you enter a dungeon or raid, click to open the editor
- **Instance browser** — open notes for any dungeon or raid you have already visited, straight from the options panel (`/zdn browse` or "Browse all dungeons..." button)
- **Shareable profiles** — export all your notes as a text string, import it on another character or share it with a friend
- **Works everywhere** — the addon does not rely on any API that is restricted inside Mythic+, Arenas or raid encounters; everything is local to your client

## Commands

| Command | Description |
|---------|-------------|
| `/zdn` | Open the note window for the current instance |
| `/zdn browse` | Browse and open notes for any visited dungeon/raid |
| `/zdn options` | Open the options panel |
| `/zdn export` | Export your profile to a shareable string |
| `/zdn import` | Import a profile string |
| `/zdn reset` | Delete all notes (with confirmation) |
| `/zdn help` | Show all commands |

## Options

- **Show notification on instance entry** — toggle the floating button
- **Notify even when no note exists for this instance** — show the button for every instance (useful for prompting yourself to take notes)
- **Notification duration** — 5–60 seconds before the button fades out
- **Enable for 5-man dungeons** — includes normal and Mythic+
- **Enable for raids** — includes LFR, Normal, Heroic, Mythic
- **Show load message in chat** — login announcement
- **Export / Import / Delete all** — profile management buttons

## Sharing a profile

The export format is a plain text string prefixed with `ZAEDN1:`. Example:

```
ZAEDN1:{[2660]="kick prio magie sur trash 3",[2661]="boss 2: dodge left"}
```

The import parser is strict (no `loadstring`, no arbitrary code execution). Only well-formed `ZAEDN1:` strings under 50 KB are accepted.

## Requirements

- **ZaeUI_Shared** — required dependency ([install from CurseForge](https://www.curseforge.com/wow/addons/zaeui-shared))

## Why this addon?

Most guide content for dungeons and raids lives outside the game (Notion, Discord, wiki pages). Alt-tabbing to consult notes during a pull is impractical. ZaeUI_DungeonNotes lets you jot your own reminders — kick priorities, pull routes, boss mechanics you keep forgetting — and have them surface exactly when you need them, at the instance door.
