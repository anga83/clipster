#!/usr/bin/swift

import Foundation

// Simulate ClipboardContent enum
enum ClipboardContent: Codable, Equatable {
    case text(String)
    case fileURL(URL)
}

// Simple test to decode one item
let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Clipster")
let jsonURL = supportURL.appendingPathComponent("history.json")

do {
    let jsonData = try Data(contentsOf: jsonURL)
    let decoder = JSONDecoder()
    
    // Try to decode just one item first
    if let jsonArray = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]],
       let firstItemDict = jsonArray.first {
        
        print("First item structure:")
        for (key, value) in firstItemDict {
            print("  \(key): \(type(of: value))")
        }
        
        // Try to decode the first item manually
        let itemData = try JSONSerialization.data(withJSONObject: firstItemDict)
        
        // Check timestamp format
        if let timestamp = firstItemDict["timestamp"] as? Double {
            let date = Date(timeIntervalSince1970: timestamp)
            print("Timestamp \(timestamp) converts to: \(date)")
        }
        
        print("\\nAttempting to decode as JSON...")
    }
    
} catch {
    print("Migration test error: \(error)")
}
