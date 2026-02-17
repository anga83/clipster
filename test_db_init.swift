#!/usr/bin/swift

import Foundation

// Test DatabaseManager initialization
let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Clipster")
let dbURL = supportURL.appendingPathComponent("clipster.db")

print("Testing DatabaseManager initialization...")
print("Support URL: \(supportURL.path)")
print("DB URL: \(dbURL.path)")
print("Support directory exists: \(FileManager.default.fileExists(atPath: supportURL.path))")
print("DB file exists before: \(FileManager.default.fileExists(atPath: dbURL.path))")

// Try to simulate DatabaseManager init
if !FileManager.default.fileExists(atPath: supportURL.path) {
    do {
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true, attributes: nil)
        print("Created support directory")
    } catch {
        print("Failed to create support directory: \(error)")
    }
}

print("DB file exists after directory creation: \(FileManager.default.fileExists(atPath: dbURL.path))")
