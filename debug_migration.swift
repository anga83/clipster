#!/usr/bin/swift

import Foundation
import SQLite3

// Minimal test to debug the exact migration issue
let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Clipster")
let jsonURL = supportURL.appendingPathComponent("history.json")

print("Testing migration logic...")
print("Support URL: \(supportURL.path)")
print("JSON URL: \(jsonURL.path)")
print("JSON exists: \(FileManager.default.fileExists(atPath: jsonURL.path))")

do {
    let jsonData = try Data(contentsOf: jsonURL)
    print("JSON size: \(jsonData.count) bytes")
    
    // Parse JSON to see its structure
    if let jsonObj = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
        print("Found \(jsonObj.count) items in JSON")
        
        for (index, item) in jsonObj.enumerated() {
            print("Item \(index):")
            print("  id: \(item["id"] ?? "N/A")")
            print("  timestamp: \(item["timestamp"] ?? "N/A")")
            print("  isPinned: \(item["isPinned"] ?? "N/A")")
            
            if let content = item["content"] as? [String: Any] {
                print("  content keys: \(Array(content.keys))")
                if let text = content["text"] as? String {
                    print("  text: \(text.prefix(50))...")
                }
            }
        }
    }
    
} catch {
    print("Error: \(error)")
}
