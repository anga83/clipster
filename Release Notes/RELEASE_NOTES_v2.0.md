# Clipster v2.0 (Build 14) - Release Notes

## 🚀 Major Architecture Overhaul - SQLite Database Implementation

**Release Date:** July 15, 2025

---

## 🎯 **What's New in Version 2.0**

### 🗄️ **Revolutionary Database Architecture**
- **Complete SQLite Migration**: Replaced JSON-based storage with robust SQLite database
- **Superior Data Integrity**: Eliminates corruption issues that could cause data loss
- **WAL Mode**: Enabled Write-Ahead Logging for improved concurrency and performance
- **Automatic Migration**: Seamlessly upgrades existing JSON history to SQLite format

### 🗂️ **Advanced Archive System (Soft-Delete)**
- **Archive Management**: New dedicated Archive tab in Settings
- **Soft-Delete Protection**: Items are moved to archive instead of permanent deletion
- **Bulk Operations**: Select and restore/delete multiple archived items at once
- **Smart Recovery**: Easily restore accidentally deleted clipboard entries

### 📎 **Enhanced Attachment Management**
- **Configurable Retention**: Set attachment cleanup from 1 day to "Never" (default: 7 days)
- **Automatic Cleanup**: Expired attachments are automatically removed while preserving text content
- **Metadata Preservation**: Filenames and file information remain accessible even after cleanup
- **Manual Cleanup**: Trigger immediate cleanup of expired attachments

### 🔧 **Improved Settings Interface**
- **Archive Settings**: Configure attachment retention policies
- **Visual Feedback**: Clear indicators for attachment status and expiration
- **Bulk Management**: Tools for managing multiple archived items efficiently

---

## 🔥 **Key Features**

### **Database Benefits**
- ✅ **Zero Data Loss**: Robust transaction handling prevents corruption
- ✅ **Better Performance**: Indexed queries for faster searches
- ✅ **Concurrent Access**: Multiple operations without conflicts
- ✅ **Future-Proof**: Schema versioning for seamless future upgrades

### **Archive System Benefits**
- ✅ **Accidental Delete Protection**: Items can always be recovered
- ✅ **Storage Optimization**: Old attachments cleaned up automatically
- ✅ **User Control**: Flexible retention policies
- ✅ **Professional Management**: Enterprise-grade archive functionality

---

## 🛠️ **Technical Improvements**

- **Database Schema**: Dual-table design (active history + archive)
- **Foreign Key Constraints**: Ensures data consistency
- **Optimized Indexes**: Fast queries on timestamp, pinned status, and source app
- **Transaction Safety**: Atomic operations with rollback capability
- **Memory Efficiency**: Reduced memory footprint compared to JSON approach

---

## 📋 **Migration & Compatibility**

- **Automatic Migration**: Existing JSON history automatically converted to SQLite
- **Backup Creation**: Original JSON files preserved as timestamped backups
- **Settings Preserved**: All user preferences maintained during upgrade
- **Zero Downtime**: Migration happens seamlessly on first launch

---

## 🔄 **Upgrade Instructions**

1. **Automatic Process**: Simply launch Clipster v2.0
2. **Migration**: Existing data automatically migrated to SQLite
3. **Backup Safety**: Original JSON files backed up automatically
4. **New Features**: Access Archive management in Settings → Archive tab

---

## 🐛 **Bug Fixes**

- **Fixed**: History entries mysteriously disappearing (root cause eliminated)
- **Fixed**: Data corruption issues during rapid clipboard updates
- **Fixed**: Memory leaks in large clipboard histories
- **Fixed**: Inconsistent behavior with file attachments

---

## 📚 **User Guide Highlights**

### **Using the Archive System**
1. **Deleting Items**: Items move to Archive instead of permanent deletion
2. **Accessing Archive**: Go to Settings → Archive tab
3. **Restoring Items**: Select archived items and click "Restore Selected"
4. **Permanent Deletion**: Use "Delete Permanently" for final removal
5. **Attachment Cleanup**: Configure retention in Archive settings

### **Archive Retention Settings**
- **1 Day**: Aggressive cleanup for minimal storage
- **7 Days**: Default balanced approach
- **30 Days**: Extended retention for important files
- **Never**: Permanent storage (manual cleanup only)

---

## 🔮 **What's Next**

- Enhanced search capabilities across archive
- Export/import functionality for archived items
- Advanced filtering options
- Cloud synchronization preparation

---

## 📞 **Support & Feedback**

This major release represents a complete architectural overhaul designed to eliminate data loss issues and provide enterprise-grade reliability. The new SQLite-based system ensures your clipboard history is safe, fast, and future-proof.

**Previous Version:** 1.8.1 (Build 13)  
**Current Version:** 2.0 (Build 14)  
**Architecture:** SQLite Database with Archive System  
**Compatibility:** macOS 13.0+

---

*Thank you for using Clipster! This release represents months of development focused on data safety and user experience improvements.*
