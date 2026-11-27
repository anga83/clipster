# Clipster

Clipster keeps a searchable history of text and files copied on your Mac. Use the menu bar popover for quick access or open the main window to search, filter and manage your history.

## Features

- Keeps a local history of copied text and file URLs.
- Search and filter clips by text, source app, date, length and pinned status.
- Jump from a search result to its chronological position in the main timeline, with nearby clips loaded on demand.
- Click a clip to copy its plain text. For clips with rich text, choose **Copy formatted** from the context menu to preserve formatting such as colors, bold and italics.
- Pin useful clips, preview or open file clips, and drag items into other apps.
- Recover recently deleted clips from the Archive and choose how long archived text and file attachments are retained.
- Set a minimum text length, manage apps excluded from monitoring, and configure how file attachments are stored.
- Export a ZIP backup of your database, settings and stored attachments, then restore it or merge its clips with existing history.
- Optionally capture the current clipboard with **⌥⌘V**, including from an app on the blacklist.

## Requirements

- macOS 15 or later
- Apple Silicon or Intel Mac

## Install

1. Download the latest `Clipster-<version>.dmg` from [GitHub Releases](https://github.com/anga83/clipster/releases/latest).
2. Open the DMG and drag `Clipster.app` to Applications.
3. Eject the mounted disk image and launch Clipster from Applications.

The release DMG is currently unsigned. macOS may ask you to confirm the first launch in **System Settings → Privacy & Security**.

Clipster adds a paperclip icon to the menu bar. Click it to open your clipboard history. Enable **Menu Bar click opens main window** in Settings if you prefer the full window.

## Your data and privacy

Clipboard history is stored locally in `~/Library/Application Support/Clipster/`. It is not uploaded by Clipster. This folder contains the SQLite history database, settings and (when configured) file attachments. Copied text and files can contain sensitive information; configure the application blacklist and retention settings to match your needs.

## Help and feedback

Please report issues or request features in the [GitHub issue tracker](https://github.com/anga83/clipster/issues).
