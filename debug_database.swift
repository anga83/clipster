#!/usr/bin/env swift

import Foundation
import SQLite3

// Find the database file
guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
    print("❌ Could not find Application Support directory")
    exit(1)
}

let supportURL = appSupportURL.appendingPathComponent("Clipster")
let dbURL = supportURL.appendingPathComponent("clipster.db")

print("🔍 Database location: \(dbURL.path)")
print("📁 Database exists: \(FileManager.default.fileExists(atPath: dbURL.path))")

guard FileManager.default.fileExists(atPath: dbURL.path) else {
    print("❌ Database file does not exist!")
    exit(1)
}

// Open database
var db: OpaquePointer?
guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
    print("❌ Failed to open database")
    exit(1)
}

print("✅ Database opened successfully")

// Check tables
print("\n📊 Checking tables...")

let tablesSQL = "SELECT name FROM sqlite_master WHERE type='table';"
var statement: OpaquePointer?

if sqlite3_prepare_v2(db, tablesSQL, -1, &statement, nil) == SQLITE_OK {
    print("📋 Tables found:")
    while sqlite3_step(statement) == SQLITE_ROW {
        if let tableName = sqlite3_column_text(statement, 0) {
            let name = String(cString: tableName)
            print("  - \(name)")
        }
    }
} else {
    print("❌ Failed to query tables")
}
sqlite3_finalize(statement)

// Check clipboard_history count
print("\n📝 Checking clipboard_history table...")
let countSQL = "SELECT COUNT(*) FROM clipboard_history;"
if sqlite3_prepare_v2(db, countSQL, -1, &statement, nil) == SQLITE_OK {
    if sqlite3_step(statement) == SQLITE_ROW {
        let count = sqlite3_column_int(statement, 0)
        print("📊 clipboard_history count: \(count)")
    }
} else {
    print("❌ Failed to count clipboard_history")
}
sqlite3_finalize(statement)

// Show recent items
print("\n📋 Recent clipboard items:")
let recentSQL = "SELECT id, content_type, content_text, content_url, timestamp FROM clipboard_history ORDER BY timestamp DESC LIMIT 5;"
if sqlite3_prepare_v2(db, recentSQL, -1, &statement, nil) == SQLITE_OK {
    var itemCount = 0
    while sqlite3_step(statement) == SQLITE_ROW {
        itemCount += 1
        
        let id = String(cString: sqlite3_column_text(statement, 0))
        let contentType = sqlite3_column_int(statement, 1)
        
        var content = "NULL"
        if contentType == 0 { // text
            if let contentText = sqlite3_column_text(statement, 2) {
                content = String(cString: contentText)
            }
        } else { // file URL
            if let contentUrl = sqlite3_column_text(statement, 3) {
                content = "URL: " + String(cString: contentUrl)
            }
        }
        
        let timestamp = sqlite3_column_double(statement, 4)
        let date = Date(timeIntervalSince1970: timestamp)
        
        print("  \(itemCount). ID: \(id)")
        print("     Type: \(contentType == 0 ? "text" : "fileURL")")
        print("     Content: \(content.prefix(50))...")
        print("     Date: \(date)")
        print()
    }
    
    if itemCount == 0 {
        print("  ⚠️  No items found in clipboard_history")
    }
} else {
    print("❌ Failed to query recent items")
}
sqlite3_finalize(statement)

// Check recently_deleted count
print("\n🗑️ Checking recently_deleted table...")
let deletedCountSQL = "SELECT COUNT(*) FROM recently_deleted;"
if sqlite3_prepare_v2(db, deletedCountSQL, -1, &statement, nil) == SQLITE_OK {
    if sqlite3_step(statement) == SQLITE_ROW {
        let count = sqlite3_column_int(statement, 0)
        print("📊 recently_deleted count: \(count)")
    }
} else {
    print("❌ Failed to count recently_deleted")
}
sqlite3_finalize(statement)

sqlite3_close(db)
print("\n✅ Database check complete")
