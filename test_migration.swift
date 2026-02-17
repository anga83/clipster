#!/usr/bin/swift

import Foundation

// Simulate the migration to test if it works
let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Clipster")
let jsonURL = supportURL.appendingPathComponent("history.json")

print("Testing JSON parsing...")

do {
    let jsonData = try Data(contentsOf: jsonURL)
    print("JSON data loaded, size: \(jsonData.count) bytes")
    
    // Try to parse as simple JSON first
    if let jsonObj = try JSONSerialization.jsonObject(with: jsonData) as? [Any] {
        print("JSON array has \(jsonObj.count) items")
        
        if let firstItem = jsonObj.first as? [String: Any] {
            print("First item keys: \(Array(firstItem.keys))")
            print("First item content keys: \(firstItem["content"] as? [String: Any] != nil ? Array((firstItem["content"] as! [String: Any]).keys) : [])")
        }
    }
    
} catch {
    print("Error: \(error)")
}
