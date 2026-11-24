import Foundation
import Combine
import ServiceManagement

/// Treatment options for specific file types
enum FileTypeTreatment: String, CaseIterable {
    case alwaysSymlink = "always_symlink"
    case saveNever = "save_never"
    
    var displayName: String {
        switch self {
        case .alwaysSymlink:
            return "Always Symlink"
        case .saveNever:
            return "Never Save"
        }
    }
    
    var description: String {
        switch self {
        case .alwaysSymlink:
            return "Always create symlinks regardless of file size"
        case .saveNever:
            return "Never save or symlink files of this type"
        }
    }
}

/// An observable object that manages and persists application settings.
class SettingsStore: ObservableObject {
    @Published var blacklistedAppIdentifiers: [String] {
        didSet {
            saveToPlist()
        }
    }

    @Published var startWithMainWindow: Bool {
        didSet {
            saveToPlist()
        }
    }

    // When enabled, register as a Login Item using SMAppService
    @Published var launchAtLogin: Bool {
        didSet {
            saveToPlist()
            applyLoginItemSetting()
        }
    }
    
    @Published var maxFileSize: Double {
        didSet {
            saveToPlist()
        }
    }
    
    @Published var fileSizeUnit: FileSizeUnit {
        didSet {
            saveToPlist()
        }
    }
    
    @Published var symlinkLargeFiles: Bool {
        didSet {
            saveToPlist()
        }
    }
    
    @Published var menuBarClickOpensMainWindow: Bool {
        didSet {
            saveToPlist()
        }
    }
    
    @Published var fileTypeTreatments: [String: FileTypeTreatment] {
        didSet {
            saveToPlist()
        }
    }
    
    @Published var usePhysicalFileStorage: Bool {
        didSet {
            saveToPlist()
        }
    }
    
    @Published var enableGlobalShortcut: Bool {
        didSet {
            saveToPlist()
        }
    }
    
    @Published var archiveAttachmentRetentionDays: Int {
        didSet {
            saveToPlist()
        }
    }
    
    @Published var archiveTextRetentionDays: Int {
        didSet {
            saveToPlist()
        }
    }
    
    @Published var minTextLength: Int {
        didSet {
            saveToPlist()
        }
    }

    // Number of recent, unpinned items to load initially (in addition to all pinned)
    @Published var recentUnpinnedInitialLoadLimit: Int {
        didSet {
            // Clamp to a sensible range to avoid UI or memory issues
            if recentUnpinnedInitialLoadLimit < 50 { recentUnpinnedInitialLoadLimit = 50 }
            if recentUnpinnedInitialLoadLimit > 5000 { recentUnpinnedInitialLoadLimit = 5000 }
            saveToPlist()
        }
    }

    private let settingsURL: URL
    private let legacyUserDefaultsPrefix = "com.clipster.app"

    private enum Keys {
        static let blacklist = "blacklistedAppIdentifiers"
        static let startWithMainWindow = "startWithMainWindow"
        static let launchAtLogin = "launchAtLogin"
        static let maxFileSize = "maxFileSize"
        static let fileSizeUnit = "fileSizeUnit"
        static let symlinkLargeFiles = "symlinkLargeFiles"
        static let menuBarClickOpensMainWindow = "menuBarClickOpensMainWindow"
        static let fileTypeTreatments = "fileTypeTreatments"
        static let usePhysicalFileStorage = "usePhysicalFileStorage"
        static let enableGlobalShortcut = "enableGlobalShortcut"
        static let archiveAttachmentRetentionDays = "archiveAttachmentRetentionDays"
        static let archiveTextRetentionDays = "archiveTextRetentionDays"
        static let minTextLength = "minTextLength"
        static let recentUnpinnedInitialLoadLimit = "recentUnpinnedInitialLoadLimit"
    }
    
    enum FileSizeUnit: String, CaseIterable, Codable {
        case KB = "KB"
        case MB = "MB"
        
        var displayName: String {
            return self.rawValue
        }
    }

    init() {
        // Create settings file URL in the same directory as history
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not find Application Support directory.")
        }
        let clipsterSupportURL = appSupportURL.appendingPathComponent("Clipster")
        
        // Create the directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: clipsterSupportURL.path) {
            try? FileManager.default.createDirectory(at: clipsterSupportURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        self.settingsURL = clipsterSupportURL.appendingPathComponent("settings.plist")
        
        // Initialize with default values
        self.blacklistedAppIdentifiers = ["com.1password.1password"]
        self.startWithMainWindow = false
    self.launchAtLogin = false
        self.maxFileSize = 3.0
        self.fileSizeUnit = .MB
        self.symlinkLargeFiles = false
        self.menuBarClickOpensMainWindow = false
        self.fileTypeTreatments = [:]
        self.usePhysicalFileStorage = true
        self.enableGlobalShortcut = true
        self.archiveAttachmentRetentionDays = 30 // Default to 30 days for attachments
        self.archiveTextRetentionDays = -1 // Default to "Never" for text clips
        self.minTextLength = 1 // Default to 1 character (save all text)
    self.recentUnpinnedInitialLoadLimit = 500 // Default initial recent load
        
        // Perform migration and load settings
        migrateFromUserDefaults()
        loadFromPlist()
    }

    private func migrateFromUserDefaults() {
        // Check if we have old settings in UserDefaults
        let userDefaults = UserDefaults.standard
        let hasLegacyBlacklist = userDefaults.object(forKey: Keys.blacklist) != nil
        let hasLegacyStartup = userDefaults.object(forKey: Keys.startWithMainWindow) != nil
        
        // If we have legacy settings and no plist file exists, migrate
        if (hasLegacyBlacklist || hasLegacyStartup) && !FileManager.default.fileExists(atPath: settingsURL.path) {
            print("Migrating settings from UserDefaults to plist...")
            
            // Start with current default values
            var migrationData: [String: Any] = [
                Keys.blacklist: self.blacklistedAppIdentifiers, // Use new default
                Keys.startWithMainWindow: self.startWithMainWindow,
                Keys.maxFileSize: self.maxFileSize, // Use new default (3.0)
                Keys.fileSizeUnit: self.fileSizeUnit.rawValue,
                Keys.usePhysicalFileStorage: self.usePhysicalFileStorage, // Use new default (true)
                Keys.enableGlobalShortcut: self.enableGlobalShortcut,
                Keys.minTextLength: self.minTextLength
            ]
            
            // Only override specific legacy values if they exist
            if hasLegacyBlacklist {
                let legacyBlacklist = userDefaults.stringArray(forKey: Keys.blacklist) ?? []
                // Merge legacy blacklist with new default
                var combinedBlacklist = Set(self.blacklistedAppIdentifiers)
                combinedBlacklist.formUnion(legacyBlacklist)
                migrationData[Keys.blacklist] = Array(combinedBlacklist)
            }
            
            if hasLegacyStartup {
                migrationData[Keys.startWithMainWindow] = userDefaults.bool(forKey: Keys.startWithMainWindow)
            }
            
            // Save to plist
            if let plistData = try? PropertyListSerialization.data(fromPropertyList: migrationData, format: .xml, options: 0) {
                try? plistData.write(to: settingsURL)
                print("Migration completed. Settings saved to: \(settingsURL.path)")
            }
        }
    }
    
    private func loadFromPlist() {
        guard FileManager.default.fileExists(atPath: settingsURL.path),
              let data = try? Data(contentsOf: settingsURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return
        }
        
        self.blacklistedAppIdentifiers = plist[Keys.blacklist] as? [String] ?? ["com.1password.1password"]
        self.startWithMainWindow = plist[Keys.startWithMainWindow] as? Bool ?? false
    self.launchAtLogin = plist[Keys.launchAtLogin] as? Bool ?? false
        self.maxFileSize = plist[Keys.maxFileSize] as? Double ?? 3.0
        if let unitString = plist[Keys.fileSizeUnit] as? String, let unit = FileSizeUnit(rawValue: unitString) {
            self.fileSizeUnit = unit
        } else {
            self.fileSizeUnit = .MB
        }
        self.symlinkLargeFiles = plist[Keys.symlinkLargeFiles] as? Bool ?? false
        self.menuBarClickOpensMainWindow = plist[Keys.menuBarClickOpensMainWindow] as? Bool ?? false
        self.usePhysicalFileStorage = plist[Keys.usePhysicalFileStorage] as? Bool ?? true
        self.enableGlobalShortcut = plist[Keys.enableGlobalShortcut] as? Bool ?? true
        self.archiveAttachmentRetentionDays = plist[Keys.archiveAttachmentRetentionDays] as? Int ?? 30
        self.archiveTextRetentionDays = plist[Keys.archiveTextRetentionDays] as? Int ?? -1
        self.minTextLength = plist[Keys.minTextLength] as? Int ?? 1
    self.recentUnpinnedInitialLoadLimit = plist[Keys.recentUnpinnedInitialLoadLimit] as? Int ?? 500
        
        // Load file type treatments
        if let treatmentsDict = plist[Keys.fileTypeTreatments] as? [String: String] {
            var treatments: [String: FileTypeTreatment] = [:]
            for (ext, treatmentString) in treatmentsDict {
                if let treatment = FileTypeTreatment(rawValue: treatmentString) {
                    treatments[ext] = treatment
                }
            }
            self.fileTypeTreatments = treatments
        } else {
            self.fileTypeTreatments = [:]
        }
    }

    /// Reloads persisted preferences after restoring a full backup.
    /// When the backup has no settings file, use the application defaults.
    func reloadFromPlist(resetToDefaultsIfMissing: Bool = false) {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            guard resetToDefaultsIfMissing else { return }
            blacklistedAppIdentifiers = ["com.1password.1password"]
            startWithMainWindow = false
            launchAtLogin = false
            maxFileSize = 3.0
            fileSizeUnit = .MB
            symlinkLargeFiles = false
            menuBarClickOpensMainWindow = false
            fileTypeTreatments = [:]
            usePhysicalFileStorage = true
            enableGlobalShortcut = true
            archiveAttachmentRetentionDays = 30
            archiveTextRetentionDays = -1
            minTextLength = 1
            recentUnpinnedInitialLoadLimit = 500
            return
        }
        loadFromPlist()
    }
    
    private func saveToPlist() {
        // Convert file type treatments to dictionary of strings
        let treatmentsDict = fileTypeTreatments.mapValues { $0.rawValue }
        
        let settingsData: [String: Any] = [
            Keys.blacklist: blacklistedAppIdentifiers,
            Keys.startWithMainWindow: startWithMainWindow,
            Keys.launchAtLogin: launchAtLogin,
            Keys.maxFileSize: maxFileSize,
            Keys.fileSizeUnit: fileSizeUnit.rawValue,
            Keys.symlinkLargeFiles: symlinkLargeFiles,
            Keys.menuBarClickOpensMainWindow: menuBarClickOpensMainWindow,
            Keys.fileTypeTreatments: treatmentsDict,
            Keys.usePhysicalFileStorage: usePhysicalFileStorage,
            Keys.enableGlobalShortcut: enableGlobalShortcut,
            Keys.archiveAttachmentRetentionDays: archiveAttachmentRetentionDays,
            Keys.archiveTextRetentionDays: archiveTextRetentionDays,
            Keys.minTextLength: minTextLength,
            Keys.recentUnpinnedInitialLoadLimit: recentUnpinnedInitialLoadLimit
        ]
        
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: settingsData, format: .xml, options: 0)
            try data.write(to: settingsURL)
        } catch {
            print("Error saving settings to plist: \(error)")
        }
    }

    // MARK: - Login Item Management
    private func applyLoginItemSetting() {
        // Note: This uses the main app as login item via SMAppService.mainApp.
        // For hardened runtime, the app should be signed and sandboxed.
        do {
            let service = SMAppService.mainApp
            if launchAtLogin {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            print("Failed to update Login Item state: \(error)")
        }
    }

    func add(bundleIdentifier: String) {
        guard !blacklistedAppIdentifiers.contains(bundleIdentifier) else { return }
        blacklistedAppIdentifiers.append(bundleIdentifier)
    }

    func remove(at offsets: IndexSet) {
        blacklistedAppIdentifiers.remove(atOffsets: offsets)
    }
    
    /// Returns the current settings file location for debugging
    func getSettingsFileLocation() -> String {
        return settingsURL.path
    }

    /// Returns the URL of the settings plist file.
    func getSettingsFileURL() -> URL {
        return settingsURL
    }

    /// Returns the Clipster support directory URL.
    func getSupportDirectoryURL() -> URL {
        return settingsURL.deletingLastPathComponent()
    }
    
    /// Returns whether legacy UserDefaults still exist
    func hasLegacySettings() -> Bool {
        let userDefaults = UserDefaults.standard
        return userDefaults.object(forKey: Keys.blacklist) != nil || 
               userDefaults.object(forKey: Keys.startWithMainWindow) != nil
    }
    
    /// Returns the file size limit in bytes
    func getFileSizeLimitInBytes() -> Int {
        let sizeInBytes: Double
        switch fileSizeUnit {
        case .KB:
            sizeInBytes = maxFileSize * 1024
        case .MB:
            sizeInBytes = maxFileSize * 1024 * 1024
        }
        return Int(sizeInBytes)
    }
    
    /// Converts the current file size to the specified unit
    func convertFileSize(to newUnit: FileSizeUnit) -> Double {
        let currentBytes = getFileSizeLimitInBytes()
        switch newUnit {
        case .KB:
            return Double(currentBytes) / 1024
        case .MB:
            return Double(currentBytes) / (1024 * 1024)
        }
    }
    
    // MARK: - File Type Treatment Methods
    
    /// Adds or updates a file type treatment rule
    func setFileTypeTreatment(_ treatment: FileTypeTreatment, for fileExtension: String) {
        let cleanExtension = fileExtension.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        fileTypeTreatments[cleanExtension] = treatment
    }
    
    /// Removes a file type treatment rule
    func removeFileTypeTreatment(for fileExtension: String) {
        let cleanExtension = fileExtension.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        fileTypeTreatments.removeValue(forKey: cleanExtension)
    }
    
    /// Gets the treatment for a specific file extension
    func getFileTypeTreatment(for fileExtension: String) -> FileTypeTreatment? {
        let cleanExtension = fileExtension.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return fileTypeTreatments[cleanExtension]
    }
    
    /// Checks if a file should be handled according to special rules
    func shouldApplySpecialTreatment(for url: URL) -> FileTypeTreatment? {
        let fileExtension = url.pathExtension.lowercased()
        return getFileTypeTreatment(for: fileExtension)
    }
    
    // MARK: - Physical File Storage Methods
    
    /// Returns the URL for the attachments directory
    func getAttachmentsDirectoryURL() -> URL {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let clipsterSupportURL = supportURL.appendingPathComponent("Clipster")
        let attachmentsURL = clipsterSupportURL.appendingPathComponent("attachments")
        
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: attachmentsURL.path) {
            try? FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        return attachmentsURL
    }
    
    /// Saves file data physically and returns the filename
    func saveFilePhysically(_ data: Data, originalURL: URL, for itemID: UUID) -> String? {
        let attachmentsURL = getAttachmentsDirectoryURL()
        let fileExtension = originalURL.pathExtension
        let filename = itemID.uuidString + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
        let fileURL = attachmentsURL.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL)
            return filename
        } catch {
            print("Error saving file physically: \(error)")
            return nil
        }
    }
    
    /// Loads file data from physical storage
    func loadFilePhysically(filename: String) -> Data? {
        let attachmentsURL = getAttachmentsDirectoryURL()
        let fileURL = attachmentsURL.appendingPathComponent(filename)
        
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            print("Error loading physical file: \(error)")
            return nil
        }
    }
    
    /// Deletes a physically stored file
    func deletePhysicalFile(filename: String) {
        let attachmentsURL = getAttachmentsDirectoryURL()
        let fileURL = attachmentsURL.appendingPathComponent(filename)
        
        try? FileManager.default.removeItem(at: fileURL)
    }
}
