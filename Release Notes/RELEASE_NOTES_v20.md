# Clipster v20 (Build 15) - Hotfix Release

## 🐛 Critical Bug Fixes

### Database Persistence Issues Resolved
- **Fixed:** Clips not being saved to database and disappearing after restart
- **Fixed:** Database file being created but remaining empty (0 bytes)
- **Fixed:** Silent failures in SQLite table creation and data insertion
- **Added:** Comprehensive error handling and database connection validation

### Archive System Stability
- **Fixed:** Archive tab crashes in Settings
- **Improved:** Error handling in archive item loading and management
- **Enhanced:** Database query resilience for recently deleted items

### User Interface Improvements
- **Fixed:** Context menu not working when right-clicking clips
- **Maintained:** All existing context menu functionality (Copy, Pin/Unpin, Delete, etc.)
- **Preserved:** QuickLook preview and file operations for file-based clips

## 🔧 Technical Improvements

### Database Engine
- **Enhanced:** SQLite connection management with proper error reporting
- **Improved:** WAL mode initialization for better concurrency
- **Added:** Foreign key constraint validation
- **Secured:** Database transaction handling and rollback mechanisms

### Performance Optimizations
- **Reduced:** Debug output overhead in production builds
- **Optimized:** Memory usage in clipboard item management
- **Streamlined:** Database query execution and result processing

### Reliability Enhancements
- **Strengthened:** Application startup sequence and initialization
- **Improved:** Error recovery mechanisms for database operations
- **Enhanced:** Thread-safety in multi-threaded clipboard monitoring

## 📦 Migration & Compatibility

### Automatic Database Migration
- **Maintained:** Seamless upgrade from JSON-based storage to SQLite
- **Preserved:** All existing clipboard history during upgrade
- **Protected:** Automatic backup creation of legacy data files

### Backward Compatibility
- **Ensured:** Settings and preferences are preserved
- **Maintained:** All keyboard shortcuts and user configurations
- **Protected:** Attachment files and metadata during migration

## 🚨 Known Issues Addressed

1. **Database Persistence:** Resolved the critical issue where clipboard items would disappear after application restart
2. **Archive Tab Crashes:** Fixed the crash that occurred when accessing the Archive section in Settings
3. **Context Menu Regression:** Restored right-click context menu functionality for all clipboard items
4. **Empty Database Files:** Fixed the SQLite initialization bug that created 0-byte database files

## 🎯 Recommended Actions

### For Users Experiencing Data Loss
1. **Immediate:** Update to v20 (Build 15) to prevent further data loss
2. **Verification:** Check that clipboard items persist after restarting the application
3. **Archive Access:** Test the Archive tab in Settings to ensure it loads without crashing

### For Users Upgrading from v2.0 (Build 14)
1. **Database Check:** Your existing SQLite database will be automatically validated and repaired if needed
2. **Backup Safety:** Previous JSON backups remain untouched as safety net
3. **Feature Testing:** Verify that all archive operations work correctly

## 📊 Build Information

- **Version:** 20 (Build 15)
- **Release Date:** July 15, 2025
- **Build Size:** 736 KB
- **Minimum macOS:** 13.0
- **Architecture:** Universal (Apple Silicon + Intel)

## 🔄 Upgrade Path

### From v2.0 (Build 14)
- **Automatic:** No user intervention required
- **Safe:** Existing database will be validated and repaired
- **Instant:** All settings and data preserved

### From v1.x (JSON-based)
- **Seamless:** Automatic migration to SQLite database
- **Protected:** Original JSON files backed up with timestamp
- **Complete:** All clipboard history and attachments preserved

---

**Note:** This hotfix release specifically addresses the critical data persistence issues reported immediately after v2.0 release. All core SQLite database functionality has been validated and tested.
