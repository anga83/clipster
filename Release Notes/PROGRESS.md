# Clipster - Progress & To-Do

This document tracks the development progress of the Clipster application.

## Implemented Features

- [x] **Project Setup:**
    - Created `Package.swift` for command-line builds (`swift build`/`swift run`).
    - Set up the basic file structure.
    - Created the main application entry point (`ClipsterApp.swift`).
    - Created a placeholder main view (`ContentView.swift`).

## To-Do List

- [x] **Core Clipboard Logic:**
    - [x] Implement a service to monitor the `NSPasteboard`.
    - [x] Create the `ClipboardItem` data model (ID, Content, Timestamp, Source).
    - [x] Implement a store to manage the clipboard history (in-memory for now).
- [x] **UI - Main Window:**
    - [x] Create a list view to display clipboard history.
    - [x] Design a cell for each `ClipboardItem` (`ClipboardItemRowView`).
    - [x] Display app name instead of bundle identifier.
    - [x] Display formatted timestamp for each item.
    - [x] Group items by "Today", "This Week", and Month.
    - [x] Implement hover highlighting on rows.
    - [x] Implement re-copying an item on click.
    - [x] Add a search bar to filter history.
    - [x] Add a filter menu for source application.
    - [x] Add controls for deleting individual items (context menu).
    - [x] Add controls for clearing the entire history (popover and main window).
- [x] **UI - Menu Bar:**
    - [x] Create the menu bar icon (`NSStatusItem`).
    - [x] Implement a popover window attached to the menu bar icon to show the history.
    - [x] Add logic to show/hide the Dock icon, making it a true menu bar utility.
    - [x] Add option to open a persistent main window from the popover.
    - [x] Add a proper application icon (programmatically from SF Symbol).
- [x] **Persistence & Data:**
    - [x] Implement saving and loading clipboard history to a file on disk.
    - [x] Implement import/export functionality.
- [x] **Styling & Polish:**
    - [x] Apply modern macOS design language (e.g., integrated title bar, vibrancy).
    - [x] Fetch and display actual application icons next to each item.

## Future Enhancements

- [x] **File Attachments:**
    - [x] When a file path is copied, if the file size is below a configurable limit (default 5MB), attach the file data to the clipboard item.
    - [x] Visualize the attachment with an icon in the `ClipboardItemRowView`.
    - [x] Clicking the icon copies the file back to the clipboard.
    - [x] A right-click context menu on the icon should offer: "Copy to clipboard", "Open", "Preview in QuickLook", "Delete attachment".
    - [x] Update data persistence and import/export to handle file attachment data.
- [x] **Blacklisted Apps:**
    - Implement a settings view where users can add applications (by bundle identifier) to a blacklist.
    - [x] Implement a settings view for blacklist and startup options.
    - [x] The `ClipboardMonitor` now ignores clipboard changes from blacklisted apps.
    - [x] Clipster is now blacklisted by default.