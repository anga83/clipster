#!/usr/bin/swift

import Foundation

// Test JSON decoding with our fixed ClipboardItem
enum ClipboardContent: Codable, Equatable {
    case text(String)
    case fileURL(URL)
}

struct TestClipboardItem: Codable {
    let id: UUID
    let content: ClipboardContent
    let timestamp: Date
    let isPinned: Bool
    let sourceAppBundleIdentifier: String?
    let sourceAppName: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, content, timestamp, isPinned, sourceAppBundleIdentifier, sourceAppName
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(ClipboardContent.self, forKey: .content)
        
        // Handle timestamp - JSON uses TimeInterval since reference date
        let timestampValue = try container.decode(TimeInterval.self, forKey: .timestamp)
        timestamp = Date(timeIntervalSinceReferenceDate: timestampValue)
        
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        sourceAppBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .sourceAppBundleIdentifier)
        sourceAppName = try container.decodeIfPresent(String.self, forKey: .sourceAppName)
    }
}

let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Clipster")
let jsonURL = supportURL.appendingPathComponent("history.json")

do {
    let jsonData = try Data(contentsOf: jsonURL)
    let decoder = JSONDecoder()
    let items = try decoder.decode([TestClipboardItem].self, from: jsonData)
    
    print("Successfully decoded \(items.count) items!")
    
    for (index, item) in items.enumerated() {
        print("Item \(index + 1):")
        print("  ID: \(item.id)")
        print("  Timestamp: \(item.timestamp)")
        print("  Pinned: \(item.isPinned)")
        print("  Source: \(item.sourceAppName ?? "Unknown")")
        
        switch item.content {
        case .text(let text):
            print("  Text: \(text.prefix(50))...")
        case .fileURL(let url):
            print("  File URL: \(url)")
        }
        print()
    }
    
} catch {
    print("Decoding failed: \(error)")
}
