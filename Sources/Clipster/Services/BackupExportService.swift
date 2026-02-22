import Foundation
import SQLite3

final class BackupExportService: @unchecked Sendable {
    struct PreparedBackup {
        let archiveURL: URL
        let temporaryDirectoryURL: URL
        let suggestedFileName: String
    }

    enum BackupExportError: LocalizedError {
        case databaseMissing(URL)
        case sqliteFailure(String)
        case jsonExportFailure(String)
        case archiveFailure(String)

        var errorDescription: String? {
            switch self {
            case .databaseMissing(let url):
                return "Database file not found: \(url.path)"
            case .sqliteFailure(let details):
                return "SQLite backup failed: \(details)"
            case .jsonExportFailure(let details):
                return "JSON export failed: \(details)"
            case .archiveFailure(let details):
                return "ZIP creation failed: \(details)"
            }
        }
    }

    private let fileManager = FileManager.default

    private static let backupNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    private static let manifestDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func prepareBackup(
        supportDirectoryURL: URL,
        settingsFileURL: URL,
        attachmentsDirectoryURL: URL,
        appVersion: String,
        appBuild: String,
        progress: (String, Double) -> Void
    ) throws -> PreparedBackup {
        let timestamp = Self.backupNameFormatter.string(from: Date())
        let tempRootURL = fileManager.temporaryDirectory.appendingPathComponent("ClipsterBackup-\(UUID().uuidString)")
        let stagingDirectoryURL = tempRootURL.appendingPathComponent("ClipsterBackup")
        let archiveURL = tempRootURL.appendingPathComponent("ClipsterBackup-\(timestamp).zip")

        do {
            progress("Preparing workspace...", 0.05)
            try fileManager.createDirectory(at: stagingDirectoryURL, withIntermediateDirectories: true)

            progress("Creating SQLite snapshot...", 0.20)
            let sourceDatabaseURL = supportDirectoryURL.appendingPathComponent("clipster.db")
            let targetDatabaseURL = stagingDirectoryURL.appendingPathComponent("clipster.db")
            try createSQLiteBackup(from: sourceDatabaseURL, to: targetDatabaseURL)

            progress("Exporting items JSON...", 0.30)
            let jsonURL = stagingDirectoryURL.appendingPathComponent("history.json")
            do {
                try exportItemsJSON(from: targetDatabaseURL, to: jsonURL)
            } catch {
                // Fallback to the source DB if opening the snapshot fails on some systems.
                try exportItemsJSON(from: sourceDatabaseURL, to: jsonURL)
            }

            progress("Exporting archive JSON...", 0.36)
            let archivedURL = stagingDirectoryURL.appendingPathComponent("archived.json")
            do {
                try exportArchivedItemsJSON(from: targetDatabaseURL, to: archivedURL)
            } catch {
                // Fallback to the source DB if opening the snapshot fails on some systems.
                try exportArchivedItemsJSON(from: sourceDatabaseURL, to: archivedURL)
            }

            progress("Copying settings...", 0.40)
            if fileManager.fileExists(atPath: settingsFileURL.path) {
                try fileManager.copyItem(at: settingsFileURL, to: stagingDirectoryURL.appendingPathComponent("settings.plist"))
            }

            progress("Collecting attachments...", 0.45)
            if fileManager.fileExists(atPath: attachmentsDirectoryURL.path) {
                try copyAttachments(
                    from: attachmentsDirectoryURL,
                    to: stagingDirectoryURL.appendingPathComponent("attachments"),
                    progress: progress
                )
            }

            progress("Writing manifest...", 0.80)
            try writeManifest(
                to: stagingDirectoryURL.appendingPathComponent("backup-manifest.json"),
                appVersion: appVersion,
                appBuild: appBuild
            )

            progress("Creating ZIP archive...", 0.90)
            try createArchive(from: stagingDirectoryURL, to: archiveURL)

            progress("Backup preparation finished.", 1.00)
            return PreparedBackup(
                archiveURL: archiveURL,
                temporaryDirectoryURL: tempRootURL,
                suggestedFileName: "Clipster-Backup-\(timestamp).zip"
            )
        } catch {
            try? fileManager.removeItem(at: tempRootURL)
            throw error
        }
    }

    private func copyAttachments(
        from sourceURL: URL,
        to destinationURL: URL,
        progress: (String, Double) -> Void
    ) throws {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let allEntries = try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let totalFileCount = max(allEntries.count, 1)
        for (index, sourceEntry) in allEntries.enumerated() {
            let destinationEntry = destinationURL.appendingPathComponent(sourceEntry.lastPathComponent)
            let isDirectory = (try sourceEntry.resourceValues(forKeys: Set(keys)).isDirectory) ?? false

            if isDirectory {
                try copyDirectoryRecursively(from: sourceEntry, to: destinationEntry)
            } else {
                try fileManager.copyItem(at: sourceEntry, to: destinationEntry)
            }

            let fraction = 0.45 + (0.30 * (Double(index + 1) / Double(totalFileCount)))
            progress("Copying attachments... (\(index + 1)/\(totalFileCount))", min(fraction, 0.75))
        }
    }

    private func copyDirectoryRecursively(from sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let entries = try fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        for entry in entries {
            let destinationEntry = destinationURL.appendingPathComponent(entry.lastPathComponent)
            let isDirectory = (try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                try copyDirectoryRecursively(from: entry, to: destinationEntry)
            } else {
                try fileManager.copyItem(at: entry, to: destinationEntry)
            }
        }
    }

    private func writeManifest(to manifestURL: URL, appVersion: String, appBuild: String) throws {
        let manifest: [String: Any] = [
            "formatVersion": 2,
            "createdAt": Self.manifestDateFormatter.string(from: Date()),
            "appVersion": appVersion,
            "appBuild": appBuild,
            "contents": ["clipster.db", "history.json", "archived.json", "settings.plist", "attachments/"]
        ]

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: manifestURL, options: .atomic)
    }

    private func createArchive(from sourceURL: URL, to archiveURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", sourceURL.path, archiveURL.path]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw BackupExportError.archiveFailure("ditto exited with status \(process.terminationStatus)")
        }
    }

    private func createSQLiteBackup(from sourceURL: URL, to destinationURL: URL) throws {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw BackupExportError.databaseMissing(sourceURL)
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        var sourceDB: OpaquePointer?
        var destinationDB: OpaquePointer?

        guard sqlite3_open_v2(sourceURL.path, &sourceDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(from: sourceDB)
            sqlite3_close(sourceDB)
            throw BackupExportError.sqliteFailure(message)
        }
        defer { sqlite3_close(sourceDB) }

        guard sqlite3_open_v2(destinationURL.path, &destinationDB, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(from: destinationDB)
            sqlite3_close(destinationDB)
            throw BackupExportError.sqliteFailure(message)
        }
        defer { sqlite3_close(destinationDB) }

        guard let backupHandle = sqlite3_backup_init(destinationDB, "main", sourceDB, "main") else {
            throw BackupExportError.sqliteFailure(sqliteErrorMessage(from: destinationDB))
        }

        var stepResult: Int32 = SQLITE_OK
        repeat {
            stepResult = sqlite3_backup_step(backupHandle, 256)
            if stepResult == SQLITE_BUSY || stepResult == SQLITE_LOCKED {
                sqlite3_sleep(25)
            }
        } while stepResult == SQLITE_OK || stepResult == SQLITE_BUSY || stepResult == SQLITE_LOCKED

        let finishResult = sqlite3_backup_finish(backupHandle)

        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw BackupExportError.sqliteFailure(sqliteErrorMessage(from: destinationDB))
        }
    }

    private func exportItemsJSON(from databaseURL: URL, to jsonURL: URL) throws {
        let sql = """
        SELECT id, content_type, content_text, content_url, timestamp, source_app_bundle_id, source_app_name,
               is_pinned, attachment_data, attachment_filename, attachment_file_extension, attachment_uti, physical_filename
        FROM clipboard_history
        ORDER BY timestamp DESC;
        """

        let items = try loadItemsFromDatabase(
            at: databaseURL,
            sql: sql,
            timestampColumn: 4,
            pinnedColumn: 7,
            missingTableFallbackToEmpty: false
        )
        try writeItemsJSON(items, to: jsonURL)
    }

    private func exportArchivedItemsJSON(from databaseURL: URL, to jsonURL: URL) throws {
        let sql = """
        SELECT id, content_type, content_text, content_url, original_timestamp, source_app_bundle_id, source_app_name,
               was_pinned, attachment_data, attachment_filename, attachment_file_extension, attachment_uti, physical_filename
        FROM recently_deleted
        ORDER BY deleted_timestamp DESC;
        """

        let items = try loadItemsFromDatabase(
            at: databaseURL,
            sql: sql,
            timestampColumn: 4,
            pinnedColumn: 7,
            missingTableFallbackToEmpty: true
        )
        try writeItemsJSON(items, to: jsonURL)
    }

    private func loadItemsFromDatabase(
        at databaseURL: URL,
        sql: String,
        timestampColumn: Int32,
        pinnedColumn: Int32,
        missingTableFallbackToEmpty: Bool
    ) throws -> [ClipboardItem] {
        var database: OpaquePointer?

        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(from: database)
            sqlite3_close(database)
            throw BackupExportError.jsonExportFailure("Cannot open database (\(databaseURL.path)): \(message)")
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(from: database)
            if missingTableFallbackToEmpty && message.localizedCaseInsensitiveContains("no such table") {
                return []
            }
            throw BackupExportError.jsonExportFailure("Cannot prepare SELECT statement: \(message)")
        }
        defer { sqlite3_finalize(statement) }

        var items: [ClipboardItem] = []
        var stepResult: Int32 = SQLITE_ROW
        while stepResult == SQLITE_ROW {
            stepResult = sqlite3_step(statement)
            guard stepResult == SQLITE_ROW else { break }
            let item = try decodeClipboardItem(
                from: statement,
                timestampColumn: timestampColumn,
                pinnedColumn: pinnedColumn
            )
            items.append(item)
        }

        guard stepResult == SQLITE_DONE else {
            throw BackupExportError.jsonExportFailure("Cannot iterate DB rows: \(sqliteErrorMessage(from: database))")
        }

        return items
    }

    private func decodeClipboardItem(
        from statement: OpaquePointer?,
        timestampColumn: Int32,
        pinnedColumn: Int32
    ) throws -> ClipboardItem {
        guard let statement else {
            throw BackupExportError.jsonExportFailure("Missing SQLite statement while decoding item.")
        }

        guard let idCString = sqlite3_column_text(statement, 0) else {
            throw BackupExportError.jsonExportFailure("Missing item ID in database row")
        }
        let idString = String(cString: idCString)
        guard let uuid = UUID(uuidString: idString) else {
            throw BackupExportError.jsonExportFailure("Invalid UUID in database row: \(idString)")
        }

        let contentType = sqlite3_column_int(statement, 1)
        let content: ClipboardContent
        if contentType == 0 {
            guard let textCString = sqlite3_column_text(statement, 2) else {
                throw BackupExportError.jsonExportFailure("Missing text content for item \(idString)")
            }
            content = .text(String(cString: textCString))
        } else if contentType == 1 {
            guard let urlCString = sqlite3_column_text(statement, 3) else {
                throw BackupExportError.jsonExportFailure("Missing URL content for item \(idString)")
            }
            let urlString = String(cString: urlCString)
            guard let url = URL(string: urlString) else {
                throw BackupExportError.jsonExportFailure("Invalid URL content for item \(idString)")
            }
            content = .fileURL(url)
        } else {
            throw BackupExportError.jsonExportFailure("Unknown content type \(contentType) for item \(idString)")
        }

        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, timestampColumn))
        let sourceBundleId = sqlite3_column_text(statement, 5).map { String(cString: $0) }
        let sourceAppName = sqlite3_column_text(statement, 6).map { String(cString: $0) }
        let isPinned = sqlite3_column_int(statement, pinnedColumn) == 1
        let attachmentData: Data? = {
            let blob = sqlite3_column_blob(statement, 8)
            let size = sqlite3_column_bytes(statement, 8)
            guard let blob, size > 0 else { return nil }
            return Data(bytes: blob, count: Int(size))
        }()
        let attachmentFilename = sqlite3_column_text(statement, 9).map { String(cString: $0) }
        let attachmentFileExtension = sqlite3_column_text(statement, 10).map { String(cString: $0) }
        let attachmentUTI = sqlite3_column_text(statement, 11).map { String(cString: $0) }
        let physicalFilename = sqlite3_column_text(statement, 12).map { String(cString: $0) }

        return ClipboardItem(
            id: uuid,
            content: content,
            timestamp: timestamp,
            isPinned: isPinned,
            sourceAppBundleIdentifier: sourceBundleId,
            sourceAppName: sourceAppName,
            attachmentData: attachmentData,
            isSymlinked: false,
            physicalFileName: physicalFilename,
            hasInlineAttachment: (attachmentData != nil || (physicalFilename == nil && (attachmentFilename != nil || attachmentUTI != nil))),
            attachmentFilename: attachmentFilename,
            attachmentFileExtension: attachmentFileExtension,
            attachmentUTI: attachmentUTI
        )
    }

    private func writeItemsJSON(_ items: [ClipboardItem], to jsonURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(items)
        try jsonData.write(to: jsonURL, options: .atomic)
    }

    private func sqliteErrorMessage(from database: OpaquePointer?) -> String {
        guard let database else {
            return "Unknown SQLite error."
        }
        return String(cString: sqlite3_errmsg(database))
    }
}
