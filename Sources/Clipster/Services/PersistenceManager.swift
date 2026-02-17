import Foundation
import AppKit // For NSOpenPanel and NSSavePanel
import UniformTypeIdentifiers // For UTType
import Compression // For ZIP operations

/// Manages the saving and loading of clipboard history to/from disk.
class PersistenceManager {
    private let historyURL: URL
    private let clipsterSupportURL: URL

    init() {
        // Find the Application Support directory and create a subdirectory for Clipster.
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not find Application Support directory.")
        }
        self.clipsterSupportURL = appSupportURL.appendingPathComponent("Clipster")

        // Create the directory if it doesn't exist.
        if !FileManager.default.fileExists(atPath: clipsterSupportURL.path) {
            try? FileManager.default.createDirectory(at: clipsterSupportURL, withIntermediateDirectories: true, attributes: nil)
        }

        self.historyURL = clipsterSupportURL.appendingPathComponent("history.json")
    }

    /// Opens the application support directory in Finder.
    func openSupportDirectory() {
        NSWorkspace.shared.open(clipsterSupportURL)
    }

    /// Loads the clipboard items from the JSON file.
    func load() -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: historyURL) else { 
            print("PersistenceManager: No history file found at \(historyURL.path)")
            return [] 
        }

        let decoder = JSONDecoder()
        do {
            let items = try decoder.decode([ClipboardItem].self, from: data)
            print("PersistenceManager: Successfully loaded \(items.count) items")
            return items
        } catch {
            print("Error decoding clipboard history: \(error)")
            
            // Create a backup of the corrupted file
            let backupURL = historyURL.appendingPathExtension("backup")
            try? data.write(to: backupURL)
            print("PersistenceManager: Created backup of corrupted history at \(backupURL.path)")
            
            return []
        }
    }

    /// Saves the clipboard items to the JSON file with backup protection.
    func save(items: [ClipboardItem]) {
        // Create backup before saving
        createBackupIfNeeded()
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted // Makes the JSON file human-readable
        do {
            let data = try encoder.encode(items)
            
            // Log the save operation
            print("PersistenceManager: Saving \(items.count) items to \(historyURL.path)")
            
            // Verify we're not about to save an empty array when we had data before
            if items.isEmpty && FileManager.default.fileExists(atPath: historyURL.path) {
                let existingData = try? Data(contentsOf: historyURL)
                if let existingData = existingData, !existingData.isEmpty {
                    print("⚠️ WARNING: Attempting to save empty history when file contains data! Skipping save to prevent data loss.")
                    return
                }
            }
            
            try data.write(to: historyURL, options: .atomic)
            print("PersistenceManager: Successfully saved \(items.count) items")
        } catch {
            print("❌ Error encoding or saving clipboard history: \(error)")
            // Try to restore from backup if save failed
            restoreFromBackupIfPossible()
        }
    }
    
    /// Creates a backup of the current history file if it exists
    private func createBackupIfNeeded() {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return }
        
        // Create timestamped backup
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let timestampedBackupURL = clipsterSupportURL.appendingPathComponent("history_backup_\(timestamp).json")
        
        do {
            // Create timestamped backup
            try FileManager.default.copyItem(at: historyURL, to: timestampedBackupURL)
            
            // Also update the main backup
            let backupURL = historyURL.appendingPathExtension("backup")
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.copyItem(at: historyURL, to: backupURL)
            
            // Clean up old backups (keep only last 5)
            cleanupOldBackups()
            
            print("PersistenceManager: Created backup \(timestampedBackupURL.lastPathComponent)")
        } catch {
            print("PersistenceManager: Failed to create backup: \(error)")
        }
    }
    
    /// Cleans up old backup files, keeping only the 5 most recent
    private func cleanupOldBackups() {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: clipsterSupportURL, includingPropertiesForKeys: [.creationDateKey], options: [])
            let backupFiles = contents.filter { $0.lastPathComponent.hasPrefix("history_backup_") }
            
            // Sort by creation date (newest first)
            let sortedBackups = try backupFiles.sorted { first, second in
                let firstDate = try first.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                let secondDate = try second.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                return firstDate > secondDate
            }
            
            // Remove old backups (keep only 5 most recent)
            if sortedBackups.count > 5 {
                for i in 5..<sortedBackups.count {
                    try FileManager.default.removeItem(at: sortedBackups[i])
                    print("PersistenceManager: Removed old backup \(sortedBackups[i].lastPathComponent)")
                }
            }
        } catch {
            print("PersistenceManager: Failed to cleanup old backups: \(error)")
        }
    }

    /// Presents a save panel to the user and exports the given items to the chosen location.
    func export(items: [ClipboardItem], settingsStore: SettingsStore) {
        // Check if any items have physical files
        let hasPhysicalFiles = items.contains { $0.physicalFileName != nil }
        
        let savePanel = NSSavePanel()
        
        if hasPhysicalFiles {
            // Export as ZIP when physical files are present
            savePanel.allowedContentTypes = [.zip]
            savePanel.nameFieldStringValue = "ClipsterHistory.zip"
        } else {
            // Export as JSON when no physical files
            savePanel.allowedContentTypes = [.json]
            savePanel.nameFieldStringValue = "ClipsterHistory.json"
        }

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        if hasPhysicalFiles {
            exportAsZip(items: items, to: url, settingsStore: settingsStore)
        } else {
            exportAsJSON(items: items, to: url)
        }
    }
    
    private func exportAsJSON(items: [ClipboardItem], to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(items)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Error exporting history: \(error)")
        }
    }
    
    private func exportAsZip(items: [ClipboardItem], to url: URL, settingsStore: SettingsStore) {
        // Create a temporary directory for the export
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // Create JSON file
            let jsonURL = tempDir.appendingPathComponent("history.json")
            exportAsJSON(items: items, to: jsonURL)
            
            // Create attachments directory and copy files
            let attachmentsDir = tempDir.appendingPathComponent("attachments")
            try FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
            
            let sourceAttachmentsDir = settingsStore.getAttachmentsDirectoryURL()
            
            for item in items {
                if let physicalFileName = item.physicalFileName {
                    let sourceFile = sourceAttachmentsDir.appendingPathComponent(physicalFileName)
                    let destFile = attachmentsDir.appendingPathComponent(physicalFileName)
                    
                    if FileManager.default.fileExists(atPath: sourceFile.path) {
                        try FileManager.default.copyItem(at: sourceFile, to: destFile)
                    }
                }
            }
            
            // Create ZIP file using system's ditto command
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc", tempDir.path, url.path]
            
            try process.run()
            process.waitUntilExit()
            
            // Clean up temporary directory
            try FileManager.default.removeItem(at: tempDir)
            
        } catch {
            print("Error creating ZIP export: \(error)")
            // Clean up on error
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    /// Presents an open panel to the user and imports items from the chosen file.
    func importHistory(settingsStore: SettingsStore) -> [ClipboardItem]? {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json, .zip]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false

        guard openPanel.runModal() == .OK, let url = openPanel.url else { return nil }
        
        if url.pathExtension.lowercased() == "zip" {
            return importFromZip(url: url, settingsStore: settingsStore)
        } else {
            return importFromJSON(url: url)
        }
    }
    
    private func importFromJSON(url: URL) -> [ClipboardItem]? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode([ClipboardItem].self, from: data)
        } catch {
            print("Error importing history: \(error)")
            return nil
        }
    }
    
    private func importFromZip(url: URL, settingsStore: SettingsStore) -> [ClipboardItem]? {
        // Create a temporary directory for extraction
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // Extract ZIP using system's ditto command
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", url.path, tempDir.path]
            
            try process.run()
            process.waitUntilExit()
            
            // Read JSON file
            let jsonURL = tempDir.appendingPathComponent("history.json")
            guard let items = importFromJSON(url: jsonURL) else {
                try? FileManager.default.removeItem(at: tempDir)
                return nil
            }
            
            // Copy attachment files to the app's attachments directory
            let extractedAttachmentsDir = tempDir.appendingPathComponent("attachments")
            let targetAttachmentsDir = settingsStore.getAttachmentsDirectoryURL()
            
            if FileManager.default.fileExists(atPath: extractedAttachmentsDir.path) {
                for item in items {
                    if let physicalFileName = item.physicalFileName {
                        let sourceFile = extractedAttachmentsDir.appendingPathComponent(physicalFileName)
                        let targetFile = targetAttachmentsDir.appendingPathComponent(physicalFileName)
                        
                        if FileManager.default.fileExists(atPath: sourceFile.path) {
                            // Remove existing file if it exists
                            try? FileManager.default.removeItem(at: targetFile)
                            try FileManager.default.copyItem(at: sourceFile, to: targetFile)
                        }
                    }
                }
            }
            
            // Clean up temporary directory
            try FileManager.default.removeItem(at: tempDir)
            
            return items
            
        } catch {
            print("Error importing ZIP history: \(error)")
            try? FileManager.default.removeItem(at: tempDir)
            return nil
        }
    }
    
    /// Attempts to restore from backup if the main file is corrupted or missing
    private func restoreFromBackupIfPossible() {
        let backupURL = historyURL.appendingPathExtension("backup")
        guard FileManager.default.fileExists(atPath: backupURL.path) else { 
            print("PersistenceManager: No backup file available for restoration")
            return 
        }
        
        do {
            if FileManager.default.fileExists(atPath: historyURL.path) {
                try FileManager.default.removeItem(at: historyURL)
            }
            try FileManager.default.copyItem(at: backupURL, to: historyURL)
            print("PersistenceManager: Successfully restored history from backup")
        } catch {
            print("❌ Failed to restore from backup: \(error)")
        }
    }
}