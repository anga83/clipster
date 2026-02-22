import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

/// Manages the collection of clipboard items using SQLite database.
/// This class is an `ObservableObject` to allow SwiftUI views to react to its changes.
@MainActor
class ClipboardHistoryStore: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var isInitialLoadComplete: Bool = false
    @Published var totalItemCount: Int = 0
    private let databaseManager: DatabaseManager
    private var cancellables = Set<AnyCancellable>()
    private let debugLogger = DebugLogger.shared
    private let backupExportService = BackupExportService()
    private let countRefreshBatchSize = 10
    private var newItemsSinceLastCountRefresh = 0
    private var isRefreshingTotalCount = false
    private var exportProgressWindowController: ExportProgressWindowController?

    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        debugLogger.logFunctionEntry()
        debugLogger.log("Initializing ClipboardHistoryStore", level: .info)
        
        self.settingsStore = settingsStore
        self.databaseManager = DatabaseManager()
        debugLogger.log("DatabaseManager created", level: .info)
        
        loadItemsFromDatabase()
        debugLogger.log("Initial items loaded from database", level: .info)
        
        debugLogger.logFunctionExit()
    }

    // MARK: - Private Methods

    private func loadItemsFromDatabase() {
        debugLogger.logFunctionEntry()
        debugLogger.log("Loading items from database asynchronously (Sequoia compatibility)", level: .info)

        let db = databaseManager // capture outside to avoid actor checks in detached task
        let limitParam = max(50, min(5000, settingsStore.recentUnpinnedInitialLoadLimit))
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            // Get total count for UI while keeping list slim
            let total = db.countAllClipboardItems()
            let pinned = db.loadPinnedItems()
            let recentUnpinned = db.loadRecentUnpinnedItems(limit: limitParam)
            // Merge: pinned first (newest first), then recent unpinned (they are already newest-first)
            // Avoid duplicates if any item is pinned and also in recent unpinned
            var seen = Set<UUID>()
            var merged: [ClipboardItem] = []
            for it in pinned where !seen.contains(it.id) { merged.append(it); seen.insert(it.id) }
            for it in recentUnpinned where !seen.contains(it.id) { merged.append(it); seen.insert(it.id) }

            let totalConst = total
            let mergedConst = merged
            let pinnedCount = pinned.count
            let recentCount = recentUnpinned.count
            await MainActor.run {
                self.totalItemCount = totalConst
                self.newItemsSinceLastCountRefresh = 0
                self.items = mergedConst
                self.debugLogger.log("Loaded pinned (\(pinnedCount)) + recent unpinned (\(recentCount))", level: .info)
                // Defer enabling the monitor slightly to avoid re-entrant NSTableView delegate warnings
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.isInitialLoadComplete = true
                }
            }
        }
    }

    /// Public refresh to apply changed limits without app restart
    func refreshInitialLoad() {
        loadItemsFromDatabase()
    }

    private func refreshTotalItemCountIfNeeded(force: Bool = false) {
        guard force || newItemsSinceLastCountRefresh >= countRefreshBatchSize else {
            return
        }
        guard !isRefreshingTotalCount else {
            return
        }

        isRefreshingTotalCount = true
        newItemsSinceLastCountRefresh = 0

        let db = databaseManager
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            let latestCount = db.countAllClipboardItems()
            await MainActor.run {
                self.totalItemCount = latestCount
                self.isRefreshingTotalCount = false
            }
        }
    }

    // MARK: - Searching all history without loading everything into memory
    func searchAllHistory(_ text: String, sourceAppName: String? = nil) -> [ClipboardItem] {
        // Run synchronously using lightweight DB path; callers can update UI on main.
        let db = databaseManager
        return db.searchClipboardItems(query: text, sourceAppName: sourceAppName, limit: 2000)
    }

    /// Loads the full clipboard history for comprehensive in-memory filtering/export.
    func loadAllHistoryItemsForFiltering() -> [ClipboardItem] {
        databaseManager.loadAllClipboardItems(includeBlobs: false)
    }

    // MARK: - Public Methods

    /// Adds a new item to the top of the history.
    func addItem(_ item: ClipboardItem) {
        debugLogger.logFunctionEntry()
        debugLogger.log("Attempting to add item with ID: \(item.id)", level: .info)
        debugLogger.log("Item content: \(item.content)", level: .info)
        
        // Avoid adding duplicates of the most recent item
        if let lastItem = items.first, 
           lastItem.content == item.content, 
           lastItem.attachmentData == item.attachmentData {
            debugLogger.log("Skipping duplicate item", level: .info)
            debugLogger.logFunctionExit()
            return
        }
        
        debugLogger.log("Item is not a duplicate, proceeding with database insert", level: .info)
        
        // Insert to database first
        debugLogger.log("Calling databaseManager.insertClipboardItem", level: .info)
        databaseManager.insertClipboardItem(item)
        totalItemCount += 1
        newItemsSinceLastCountRefresh += 1
        refreshTotalItemCountIfNeeded()
        
        // Update local array on next runloop tick to avoid reentrancy in NSTableView delegate callbacks
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.items.insert(item, at: 0)
            self.debugLogger.log("Successfully added item to local array. New count: \(self.items.count)", level: .info)
        }
        
        debugLogger.logFunctionExit()
    }

    /// Removes an item and moves it to archive
    func removeItem(withId id: UUID) {
        debugLogger.logFunctionEntry()
        debugLogger.log("Attempting to remove item with ID: \(id)", level: .info)
        
        guard let index = items.firstIndex(where: { $0.id == id }) else { 
            debugLogger.log("ERROR: Item with ID \(id) not found in items array", level: .error)
            debugLogger.logFunctionExit()
            return 
        }
        
        let item = items[index]
        debugLogger.log("Found item to remove: content=\(item.content)", level: .info)
        
        // Move to archive (recently_deleted table)
        debugLogger.log("Calling databaseManager.deleteClipboardItem", level: .info)
        databaseManager.deleteClipboardItem(item)
        
        // Remove from local array - this makes it disappear from the UI
        items.remove(at: index)
        totalItemCount = max(0, totalItemCount - 1)
        debugLogger.log("Successfully removed item from local array. New count: \(items.count)", level: .info)
        
        print("ClipboardHistoryStore: Moved item \(id) to archive")
        debugLogger.logFunctionExit()
    }

    /// Removes an item and moves it to archive (does NOT delete physical files)
    func removeItemAndCleanup(_ item: ClipboardItem, settingsStore: SettingsStore) {
        // Only move to archive, don't delete physical files yet
        // Physical files should only be deleted when:
        // 1. Item is permanently deleted from archive manually
        // 2. Item expires based on retention period
        removeItem(withId: item.id)
        
        // Note: Physical files are preserved for potential restore
        print("ClipboardHistoryStore: Moved item \(item.id) to archive (physical files preserved)")
    }

    /// Toggles pin status for an item
    func togglePin(for item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        
        items[index].isPinned.toggle()
        databaseManager.updatePinnedStatus(itemId: item.id, isPinned: items[index].isPinned)
        print("ClipboardHistoryStore: Toggled pin for item \(item.id)")
    }

    /// Pins an item
    func pinItem(withId id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        
        items[index].isPinned = true
        databaseManager.updatePinnedStatus(itemId: id, isPinned: true)
    }

    /// Unpins an item
    func unpinItem(withId id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        
        items[index].isPinned = false
        databaseManager.updatePinnedStatus(itemId: id, isPinned: false)
    }

    /// Clears all non-pinned items
    func clearNonPinnedItems() {
        databaseManager.clearNonPinnedItems()
        items.removeAll { !$0.isPinned }
        refreshTotalItemCountIfNeeded(force: true)
        print("ClipboardHistoryStore: Cleared non-pinned items")
    }

    /// Clears all items including pinned ones
    func clearAllItems() {
        databaseManager.clearAllItems()
        items.removeAll()
        totalItemCount = 0
        newItemsSinceLastCountRefresh = 0
        print("ClipboardHistoryStore: Cleared all items")
    }

    /// Unpins all items
    func unpinAllItems() {
        for index in items.indices {
            items[index].isPinned = false
        }
        databaseManager.unpinAllItems()
        print("ClipboardHistoryStore: Unpinned all items")
    }

    // MARK: - Archive Management

    /// Gets all archived (recently deleted) clipboard items
    func getArchivedItems() -> [ClipboardItem] {
        debugLogger.logFunctionEntry()
        debugLogger.logArchiveOperation("Starting getArchivedItems", details: "Calling databaseManager.loadRecentlyDeletedItems()")
        
        let items = databaseManager.loadRecentlyDeletedItems()
        debugLogger.logArchiveOperation("Successfully loaded archived items", details: "Count: \(items.count)")
        
        for (index, item) in items.enumerated() {
            debugLogger.log("Item \(index): ID=\(item.id), content=\(item.content)", level: .debug)
        }
        
        debugLogger.logFunctionExit()
        return items
    }

    /// Restores an item from the archive back to active history
    func restoreFromArchive(_ itemId: UUID) {
        databaseManager.restoreFromRecentlyDeleted(itemId)
        loadItemsFromDatabase() // Refresh the view
        print("ClipboardHistoryStore: Restored item \(itemId) from archive")
    }

    /// Permanently deletes an item from the archive
    func permanentlyDeleteFromArchive(_ itemId: UUID, settingsStore: SettingsStore) {
        guard !itemId.uuidString.isEmpty else {
            print("ClipboardHistoryStore ERROR: Invalid UUID for permanent delete")
            return
        }
        
        // Get the item before deleting to clean up attachments
        if let item = databaseManager.getRecentlyDeletedItem(itemId) {
            // Clean up physical files if needed
            if let physicalFileName = item.physicalFileName {
                settingsStore.deletePhysicalFile(filename: physicalFileName)
            }
        }
        
        databaseManager.permanentlyDeleteFromArchive(itemId, settingsStore: settingsStore)
        print("ClipboardHistoryStore: Permanently deleted item \(itemId)")
    }

    /// Cleans up old archived items based on retention settings
    func cleanupOldArchivedItems(textRetentionDays: Int, attachmentRetentionDays: Int, settingsStore: SettingsStore) {
        // Skip cleanup for "Never" values (-1)
        if textRetentionDays == -1 && attachmentRetentionDays == -1 {
            print("ClipboardHistoryStore: Both retention periods set to 'Never', skipping cleanup")
            return
        }
        
        // Get physical file names that will be deleted by the cleanup
        let physicalFilenames = databaseManager.getPhysicalFilenamesForCleanup(
            textRetentionDays: textRetentionDays, 
            attachmentRetentionDays: attachmentRetentionDays
        )
        
        // Delete physical files before database cleanup
        for filename in physicalFilenames {
            let fileURL = settingsStore.getAttachmentsDirectoryURL().appendingPathComponent(filename)
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                    print("ClipboardHistoryStore: Deleted physical file for expired archive item: \(filename)")
                }
            } catch {
                print("ClipboardHistoryStore: Failed to delete physical file \(filename): \(error)")
            }
        }
        
        // Now perform the database cleanup
        databaseManager.cleanupOldArchivedItems(textRetentionDays: textRetentionDays, attachmentRetentionDays: attachmentRetentionDays)
        
        let textMsg = textRetentionDays == -1 ? "Never" : "\(textRetentionDays) days"
        let attachmentMsg = attachmentRetentionDays == -1 ? "Never" : "\(attachmentRetentionDays) days"
        print("ClipboardHistoryStore: Cleaned up archived items (Text: \(textMsg), Attachments: \(attachmentMsg))")
    }
    
    // Legacy method for backward compatibility
    func cleanupOldArchivedItems(retentionDays: Int, settingsStore: SettingsStore) {
        cleanupOldArchivedItems(textRetentionDays: retentionDays, attachmentRetentionDays: retentionDays, settingsStore: settingsStore)
    }
    
    // MARK: - Import/Export Methods
    
    /// Exports a full backup as ZIP (SQLite DB + settings + attachments).
    func exportHistory(settingsStore: SettingsStore) {
        let progressWindow = ExportProgressWindowController()
        exportProgressWindowController = progressWindow
        progressWindow.update(status: "Preparing backup ...", progress: 0.01)
        progressWindow.show()

        let supportDirectoryURL = settingsStore.getSupportDirectoryURL()
        let settingsFileURL = settingsStore.getSettingsFileURL()
        let attachmentsDirectoryURL = settingsStore.getAttachmentsDirectoryURL()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "N/A"
        let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "N/A"
        let backupService = backupExportService

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let preparedBackup = try backupService.prepareBackup(
                    supportDirectoryURL: supportDirectoryURL,
                    settingsFileURL: settingsFileURL,
                    attachmentsDirectoryURL: attachmentsDirectoryURL,
                    appVersion: appVersion,
                    appBuild: appBuild
                ) { status, progress in
                    DispatchQueue.main.async {
                        self.exportProgressWindowController?.update(status: status, progress: progress)
                    }
                }

                DispatchQueue.main.async {
                    self.finishExportPreparation(preparedBackup)
                }
            } catch {
                DispatchQueue.main.async {
                    self.handleExportFailure(error)
                }
            }
        }
    }
    
    /// Imports clipboard history from a JSON file
    func importHistory(settingsStore: SettingsStore) {
        // Placeholder for import functionality
        print("ClipboardHistoryStore: Import functionality placeholder")
    }

    private func finishExportPreparation(_ preparedBackup: BackupExportService.PreparedBackup) {
        exportProgressWindowController?.update(status: "Backup preparation finished.", progress: 1.0)
        exportProgressWindowController?.close()
        exportProgressWindowController = nil

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.zip]
        savePanel.canCreateDirectories = true
        savePanel.title = "Save Backup"
        savePanel.message = "Choose where to save your Clipster backup ZIP."
        savePanel.nameFieldStringValue = preparedBackup.suggestedFileName

        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
            try? FileManager.default.removeItem(at: preparedBackup.temporaryDirectoryURL)
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: preparedBackup.archiveURL, to: destinationURL)
        } catch {
            showExportErrorAlert(message: error.localizedDescription)
        }

        try? FileManager.default.removeItem(at: preparedBackup.temporaryDirectoryURL)
    }

    private func handleExportFailure(_ error: Error) {
        exportProgressWindowController?.close()
        exportProgressWindowController = nil
        showExportErrorAlert(message: error.localizedDescription)
    }

    private func showExportErrorAlert(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Backup Export Failed"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    // MARK: - Sample Data for Previews
    
    /// Creates sample data for SwiftUI previews
    static func createSampleData() -> [ClipboardItem] {
        return [
            ClipboardItem(
                id: UUID(),
                content: .text("Sample clipboard text 1"),
                timestamp: Date(),
                isPinned: false,
                sourceAppBundleIdentifier: "com.apple.finder",
                sourceAppName: "Finder"
            ),
            ClipboardItem(
                id: UUID(),
                content: .text("Sample clipboard text 2"),
                timestamp: Date().addingTimeInterval(-3600),
                isPinned: true,
                sourceAppBundleIdentifier: "com.apple.safari",
                sourceAppName: "Safari"
            )
        ]
    }
}
