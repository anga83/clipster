# Clipster v1.7 Release Notes

## 🎯 New Features

### Individual Item Selection System
- **macOS/iOS Style Selection**: Added individual item selection with familiar circular checkboxes
- **Selection Mode Toggle**: New button in the toolbar to enter/exit selection mode
- **Bulk Operations**: Select All/Deselect All and Delete Selected functionality
- **Adaptive UI**: Clean interface that only shows selection controls when needed
- **Smooth Animations**: Elegant transitions between normal and selection modes

## 🔧 Technical Improvements

### User Experience
- **Precise Item Management**: Alternative to bulk clear history for targeted deletions
- **Intuitive Interface**: Follows macOS/iOS design patterns for familiarity
- **Conditional Display**: Selection checkboxes only appear in selection mode
- **Efficient State Management**: Uses `Set<UUID>` for optimal performance

### Implementation Details
- Enhanced `ContentView.swift` with selection mode state management
- Modified `ClipboardItemRowView.swift` for conditional selection interface
- Integrated selection controls into footer for popover interface
- Added proper cleanup when exiting selection mode

## 🏗️ Build Information

- **Version**: 1.7 (Build 10)
- **Bundle ID**: com.clipster.app
- **Minimum macOS**: 13.0
- **DMG Size**: 905K
- **Build Time**: 67.74s

## 📋 Previous Features (Preserved)

- Advanced clear history options with time frame and app filtering
- Scrollable clear history interface with optimized sizing
- Physical file storage system with ZIP export/import
- Comprehensive pinning system with sophisticated sorting
- Modern sidebar-based Settings UI
- Configurable file attachments with symlink support
- Automated release pipeline with DMG creation
- File type treatment rules system
- QuickLook preview integration

## 🧪 Testing Recommendations

1. **Selection Mode**: Test entering/exiting selection mode via toolbar button
2. **Individual Selection**: Verify circular checkboxes appear and function correctly
3. **Bulk Operations**: Test Select All/Deselect All and Delete Selected
4. **UI Adaptation**: Confirm selection controls integrate properly in both window and popover modes
5. **State Management**: Verify proper cleanup when selection mode is disabled

## 💾 Installation

1. Mount the `Clipster-v1.7.dmg` file
2. Drag `Clipster.app` to your Applications folder
3. Launch Clipster from Applications or Spotlight

---

**Individual Item Selection** brings precise clipboard management to Clipster with the familiar macOS/iOS selection interface. This release focuses on user experience improvements while maintaining all existing functionality.
