# Clipster

A powerful clipboard manager for macOS that keeps track of your clipboard history with advanced features.

## Features

- ✅ **Modern Interface** - Clean SwiftUI design with both main window and menu bar modes
- ✅ **Smart Search** - Search through your clipboard history with real-time filtering
- ✅ **App Filtering** - Filter clipboard items by source application
- ✅ **File Attachments** - Handle files with configurable size limits and symlink support
- ✅ **QuickLook Preview** - Preview file attachments directly in the app
- ✅ **Drag & Drop** - Drag clipboard items to other applications
- ✅ **Settings Management** - Modern tabbed settings window with sidebar navigation
- ✅ **App Blacklist** - Exclude specific applications from clipboard monitoring
- ✅ **Export/Import** - Backup and restore your clipboard history
- ✅ **Pinned Items** - Pin important clipboard items to keep them accessible

## System Requirements

- macOS 13.0 or later
- 64-bit Intel or Apple Silicon Mac

## Installation

1. Download the latest `Clipster-vX.X.dmg` from releases
2. Mount the DMG file
3. Drag Clipster.app to your Applications folder
4. Launch Clipster from Applications

## Quick Start

1. Launch Clipster - it will appear in your menu bar
2. Copy some text or files to build your clipboard history
3. Click the menu bar icon to access your history
4. Use the search bar to find specific items
5. Click any item to copy it back to the clipboard

## Building from Source

### Quick Development Build

```bash
# Build and run for development
./Scripts/dev.sh run

# Just build
./Scripts/dev.sh build

# Clean build artifacts
./Scripts/dev.sh clean
```

### Release Build

```bash
# Create a complete release with DMG
./Scripts/release.sh
```

This will:
- Prompt for version and build numbers
- Create an optimized release build
- Generate a proper app bundle
- Create a DMG installer ready for distribution

## Configuration

Clipster stores its configuration in `~/Library/Application Support/Clipster/`:
- `history.json` - Your clipboard history
- `settings.plist` - Application settings

### Settings Include:
- **Startup Behavior** - Auto-open main window
- **File Attachments** - Size limits, symlink options
- **Application Blacklist** - Apps to ignore
- **Advanced Options** - Data directory access

## File Handling

Clipster intelligently handles different file types:

- **Small Files** (< limit): Stored as data for full portability
- **Large Files** (> limit): Can be symlinked to preserve disk space
- **Symlinked Files**: Show special link icon and copy on drag & drop

## Keyboard Shortcuts

- **⌘+Click** - Pin/unpin clipboard items
- **Search** - Start typing to filter results
- **⌘+W** - Close main window (app stays in menu bar)

## Development

### Project Structure

```
Sources/Clipster/
├── App/                 # App lifecycle and configuration
├── Data/                # Data models and storage
├── Model/               # Core data structures
├── Resources/           # App icons and Info.plist
├── Services/            # Background services
└── Views/               # SwiftUI interface

Scripts/
├── release.sh           # Automated release builds
├── dev.sh              # Development builds
└── README.md           # Build script documentation
```

### Architecture

- **SwiftUI** - Modern declarative UI framework
- **Combine** - Reactive programming for data flow
- **ObservableObject** - State management
- **MenuBarExtra** - Native menu bar integration
- **QuickLook** - File preview integration

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `./Scripts/dev.sh run`
5. Create a pull request

## License

Copyright © 2026 Clipster. All rights reserved.

## Changelog

### v1.3
- Modern tabbed settings window with sidebar navigation
- Improved symlinked file handling with proper icons
- Enhanced drag & drop for symlinked files (copy instead of move)
- Better error handling and user feedback

### v1.2
- Added configurable file attachment settings
- Symlink support for large files
- Improved Settings UI design
- Migration to plist-based configuration

### v1.1
- QuickLook preview integration
- Enhanced file attachment handling
- Improved menu bar interface
- Search functionality in menu bar

### v1.0
- Initial release
- Basic clipboard history management
- SwiftUI interface
- Menu bar and main window modes
