import Foundation

/// Represents the different types of content that can be on the clipboard.
/// For now, we only support text, but this can be expanded later.
enum ClipboardContent: Codable, Equatable {
    case text(String)
    case fileURL(URL)
    // Future cases could include: .image(Data)
}

/// A model representing a single item copied to the clipboard.
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let content: ClipboardContent
    let timestamp: Date
    var isPinned: Bool
    let sourceAppBundleIdentifier: String?
    let sourceAppName: String?
    var attachmentData: Data?
    var isSymlinked: Bool
    var physicalFileName: String? // For physical file storage
    // Indicates an inline attachment exists in the database without loading the BLOB (lightweight load)
    var hasInlineAttachment: Bool = false
    
    // Additional attachment metadata for SQLite database
    var attachmentFilename: String?
    var attachmentFileExtension: String?
    var attachmentUTI: String?

    /// Convenience initializer for creating new clipboard items.
    init(id: UUID = UUID(), content: ClipboardContent, timestamp: Date = Date(), isPinned: Bool = false, sourceAppBundleIdentifier: String? = nil, sourceAppName: String? = nil, attachmentData: Data? = nil, isSymlinked: Bool = false, physicalFileName: String? = nil, hasInlineAttachment: Bool = false, attachmentFilename: String? = nil, attachmentFileExtension: String? = nil, attachmentUTI: String? = nil) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.sourceAppBundleIdentifier = sourceAppBundleIdentifier
        self.sourceAppName = sourceAppName
        self.attachmentData = attachmentData
        self.isSymlinked = isSymlinked
        self.physicalFileName = physicalFileName
        self.hasInlineAttachment = hasInlineAttachment
        self.attachmentFilename = attachmentFilename
        self.attachmentFileExtension = attachmentFileExtension
        self.attachmentUTI = attachmentUTI
    }
    
    // Custom Codable implementation to handle backward compatibility
    private enum CodingKeys: String, CodingKey {
        case id, content, timestamp, isPinned, sourceAppBundleIdentifier, sourceAppName, attachmentData, isSymlinked, physicalFileName, attachmentFilename, attachmentFileExtension, attachmentUTI
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
        attachmentData = try container.decodeIfPresent(Data.self, forKey: .attachmentData)
        
        // Provide default value for isSymlinked if not present (backward compatibility)
        isSymlinked = try container.decodeIfPresent(Bool.self, forKey: .isSymlinked) ?? false
        
        // Provide default value for physicalFileName if not present (backward compatibility)
        physicalFileName = try container.decodeIfPresent(String.self, forKey: .physicalFileName)
        
        // Provide default values for new attachment metadata fields (backward compatibility)
        attachmentFilename = try container.decodeIfPresent(String.self, forKey: .attachmentFilename)
        attachmentFileExtension = try container.decodeIfPresent(String.self, forKey: .attachmentFileExtension)
        attachmentUTI = try container.decodeIfPresent(String.self, forKey: .attachmentUTI)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(sourceAppBundleIdentifier, forKey: .sourceAppBundleIdentifier)
        try container.encodeIfPresent(sourceAppName, forKey: .sourceAppName)
        try container.encodeIfPresent(attachmentData, forKey: .attachmentData)
        try container.encode(isSymlinked, forKey: .isSymlinked)
        try container.encodeIfPresent(physicalFileName, forKey: .physicalFileName)
        try container.encodeIfPresent(attachmentFilename, forKey: .attachmentFilename)
        try container.encodeIfPresent(attachmentFileExtension, forKey: .attachmentFileExtension)
        try container.encodeIfPresent(attachmentUTI, forKey: .attachmentUTI)
    }
    
    // MARK: - Physical File Storage Helpers
    
    /// Returns the file data, either from attachmentData or from physical storage
    func getFileData(using settingsStore: SettingsStore) -> Data? {
        if let physicalFileName = physicalFileName {
            // Load from physical storage
            return settingsStore.loadFilePhysically(filename: physicalFileName)
        } else if let attachmentData = attachmentData {
            // Load from inline data
            return attachmentData
        }
        return nil
    }
    
    /// Returns true if this item has file data (either physical or inline)
    var hasFileData: Bool {
        return physicalFileName != nil || attachmentData != nil || hasInlineAttachment
    }
}