#!/usr/bin/swift

import Foundation
import SQLite3

// Simple DatabaseManager test
class TestDatabaseManager {
    private var db: OpaquePointer?
    private let dbURL: URL
    private let supportURL: URL
    
    init() {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not find Application Support directory.")
        }
        
        self.supportURL = appSupportURL.appendingPathComponent("Clipster")
        self.dbURL = supportURL.appendingPathComponent("clipster.db")
        
        print("TestDatabaseManager: Support URL: \(supportURL.path)")
        print("TestDatabaseManager: DB URL: \(dbURL.path)")
        
        // Create support directory if needed
        if !FileManager.default.fileExists(atPath: supportURL.path) {
            do {
                try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true, attributes: nil)
                print("TestDatabaseManager: Created support directory")
            } catch {
                print("TestDatabaseManager: Failed to create directory: \(error)")
            }
        }
        
        openDatabase()
        createTables()
    }
    
    private func openDatabase() {
        print("TestDatabaseManager: Attempting to open database...")
        if sqlite3_open(dbURL.path, &db) == SQLITE_OK {
            print("TestDatabaseManager: Successfully opened database")
            
            // Enable foreign keys
            if sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil) == SQLITE_OK {
                print("TestDatabaseManager: Foreign keys enabled")
            } else {
                print("TestDatabaseManager: Failed to enable foreign keys")
            }
            
            // Enable WAL mode
            if sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil) == SQLITE_OK {
                print("TestDatabaseManager: WAL mode enabled")
            } else {
                print("TestDatabaseManager: Failed to enable WAL mode")
            }
        } else {
            print("TestDatabaseManager: Failed to open database: \(String(cString: sqlite3_errmsg(db)))")
            db = nil
        }
    }
    
    private func createTables() {
        print("TestDatabaseManager: Creating tables...")
        
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS clipboard_history (
            id TEXT PRIMARY KEY,
            content_type INTEGER NOT NULL,
            content_text TEXT,
            timestamp REAL NOT NULL
        );
        """
        
        if sqlite3_exec(db, createTableSQL, nil, nil, nil) == SQLITE_OK {
            print("TestDatabaseManager: Successfully created clipboard_history table")
        } else {
            print("TestDatabaseManager: Failed to create table: \(String(cString: sqlite3_errmsg(db)))")
        }
    }
    
    func testInsert() {
        print("TestDatabaseManager: Testing insert...")
        
        let insertSQL = "INSERT INTO clipboard_history (id, content_type, content_text, timestamp) VALUES (?, ?, ?, ?);"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, "test-id", -1, nil)
            sqlite3_bind_int(statement, 2, 0)
            sqlite3_bind_text(statement, 3, "test content", -1, nil)
            sqlite3_bind_double(statement, 4, Date().timeIntervalSince1970)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                print("TestDatabaseManager: Successfully inserted test row")
            } else {
                print("TestDatabaseManager: Failed to insert: \(String(cString: sqlite3_errmsg(db)))")
            }
        } else {
            print("TestDatabaseManager: Failed to prepare statement: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        sqlite3_finalize(statement)
    }
    
    func testCount() {
        print("TestDatabaseManager: Testing count...")
        
        let countSQL = "SELECT COUNT(*) FROM clipboard_history;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, countSQL, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                let count = sqlite3_column_int(statement, 0)
                print("TestDatabaseManager: Row count: \(count)")
            } else {
                print("TestDatabaseManager: Failed to get count")
            }
        } else {
            print("TestDatabaseManager: Failed to prepare count statement")
        }
        
        sqlite3_finalize(statement)
    }
}

print("=== Testing DatabaseManager ===")
let testDB = TestDatabaseManager()
testDB.testInsert()
testDB.testCount()

// Check file size
let dbURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Clipster").appendingPathComponent("clipster.db")
if let attributes = try? FileManager.default.attributesOfItem(atPath: dbURL.path) {
    let fileSize = attributes[.size] as? Int64 ?? 0
    print("Database file size: \(fileSize) bytes")
} else {
    print("Could not get file attributes")
}
