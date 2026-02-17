# Clipster 2.0 Release

## What's New in Version 2.0

### 🗄️ Archive System
- **Smart Archive Management**: Deleted clips are now moved to an archive instead of being permanently deleted
- **Restore Functionality**: Easily restore accidentally deleted clips from the archive
- **Archive Search**: Full-text search through archived items
- **Dual Retention Policy**: Separate retention settings for text clips and file attachments
- **Physical File Preservation**: File attachments remain accessible after archiving until final deletion

### ⚙️ Enhanced Settings
- **New Defaults**: 
  - Maximum file size reduced to 3MB (from 5MB)
  - Physical file storage enabled by default
  - 1Password added to default application blacklist
- **Minimum Text Length Filter**: Filter out very short text clips (default: 1 character)
- **Improved Settings UI**: Better organization and clearer descriptions

### 🔧 Technical Improvements
- **SQLite Database Migration**: Seamless upgrade from JSON storage to SQLite
- **Improved Database Operations**: Better string binding with SQLITE_TRANSIENT
- **Enhanced Debugging**: Comprehensive debug logging system
- **Memory Optimizations**: Better handling of large clipboard items

### 🐛 Bug Fixes
- Fixed context menu functionality that was blocked by gesture conflicts
- Resolved archive items reappearing in main view after restart
- Fixed physical file deletion timing issues
- Improved database transaction handling
- Better error handling for corrupted data

## Installation

### Option 1: DMG Installer
1. Download `Clipster-2.0.dmg`
2. Double-click to mount the disk image
3. Drag Clipster.app to your Applications folder
4. Launch Clipster from Applications

### Option 2: Direct App Bundle
1. Download the `Clipster-2.0` folder
2. Copy `Clipster.app` to your Applications folder
3. Launch Clipster from Applications

## System Requirements
- macOS 13.0 or later
- Apple Silicon or Intel Mac

## Notes
- First launch will migrate existing data from version 1.x automatically
- All your existing clips and settings will be preserved
- Archive functionality is immediately available after migration

## Source Code
The complete source code is available in `Clipster-2.0-Source.zip` for developers who want to build from source or contribute to the project.

## Support
If you encounter any issues, please check the debug logs in the application and report any problems.
