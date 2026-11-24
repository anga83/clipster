import Foundation
import SQLite3

final class BackupExportService: @unchecked Sendable {
    enum ImportMode: Equatable, Sendable {
        case replace
        case merge
    }

    struct PreparedBackup {
        let archiveURL: URL
        let temporaryDirectoryURL: URL
        let suggestedFileName: String
    }

    struct PreparedImport: Sendable {
        let archiveURL: URL
        let temporaryDirectoryURL: URL
        let payloadDirectoryURL: URL
        let databaseURL: URL
        let settingsURL: URL?
        let attachmentsURL: URL?
    }

    enum BackupExportError: LocalizedError {
        case databaseMissing(URL)
        case sqliteFailure(String)
        case jsonExportFailure(String)
        case archiveFailure(String)
        case invalidArchive(String)
        case extractionFailure(String)
        case rollbackFailure(String)

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
            case .invalidArchive(let details):
                return "This is not a valid Clipster backup: \(details)"
            case .extractionFailure(let details):
                return "Could not extract Clipster backup: \(details)"
            case .rollbackFailure(let details):
                return "Import failed and rollback could not fully restore the previous data: \(details)"
            }
        }
    }

    private let fileManager = FileManager.default

    func prepareImport(from archiveURL: URL) throws -> PreparedImport {
        let temporaryDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("ClipsterImport-\(UUID().uuidString)", isDirectory: true)
        do {
            try validateArchiveEntryPaths(at: archiveURL)
            try fileManager.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archiveURL.path, temporaryDirectoryURL.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw BackupExportError.extractionFailure("ditto exited with status \(process.terminationStatus).")
            }

            let payloadDirectoryURL: URL
            let standardPayloadURL = temporaryDirectoryURL.appendingPathComponent("ClipsterBackup", isDirectory: true)
            if fileManager.fileExists(atPath: standardPayloadURL.path) {
                payloadDirectoryURL = standardPayloadURL
            } else if fileManager.fileExists(atPath: temporaryDirectoryURL.appendingPathComponent("backup-manifest.json").path) {
                payloadDirectoryURL = temporaryDirectoryURL
            } else {
                throw BackupExportError.invalidArchive("The ClipsterBackup folder or manifest is missing.")
            }

            try validateNoSymbolicLinks(in: payloadDirectoryURL)
            let manifestURL = payloadDirectoryURL.appendingPathComponent("backup-manifest.json")
            let manifestData = try Data(contentsOf: manifestURL)
            guard
                let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
                (manifest["formatVersion"] as? NSNumber)?.intValue == 2
            else {
                throw BackupExportError.invalidArchive("Unsupported or malformed backup manifest.")
            }

            let databaseURL = payloadDirectoryURL.appendingPathComponent("clipster.db")
            try validateDatabase(at: databaseURL)

            let settingsURL = payloadDirectoryURL.appendingPathComponent("settings.plist")
            if fileManager.fileExists(atPath: settingsURL.path) {
                let settingsData = try Data(contentsOf: settingsURL)
                guard try PropertyListSerialization.propertyList(from: settingsData, options: [], format: nil) is [String: Any] else {
                    throw BackupExportError.invalidArchive("settings.plist is not a settings dictionary.")
                }
            }

            let attachmentsURL = payloadDirectoryURL.appendingPathComponent("attachments", isDirectory: true)
            if fileManager.fileExists(atPath: attachmentsURL.path) {
                try validateAttachments(at: attachmentsURL)
            }

            return PreparedImport(
                archiveURL: archiveURL,
                temporaryDirectoryURL: temporaryDirectoryURL,
                payloadDirectoryURL: payloadDirectoryURL,
                databaseURL: databaseURL,
                settingsURL: fileManager.fileExists(atPath: settingsURL.path) ? settingsURL : nil,
                attachmentsURL: fileManager.fileExists(atPath: attachmentsURL.path) ? attachmentsURL : nil
            )
        } catch {
            try? fileManager.removeItem(at: temporaryDirectoryURL)
            throw error
        }
    }

    func applyImport(
        _ preparedImport: PreparedImport,
        mode: ImportMode,
        supportDirectoryURL: URL,
        settingsFileURL: URL,
        attachmentsDirectoryURL: URL,
        databaseManager: DatabaseManager
    ) throws {
        let rollbackDirectoryURL = supportDirectoryURL.deletingLastPathComponent()
            .appendingPathComponent(".ClipsterImportRollback-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rollbackDirectoryURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rollbackDirectoryURL) }

        let previousDatabaseURL = rollbackDirectoryURL.appendingPathComponent("clipster.db")

        switch mode {
        case .replace:
            try databaseManager.createSnapshot(at: previousDatabaseURL)
            let previousSettingsURL = rollbackDirectoryURL.appendingPathComponent("settings.plist")
            let hadSettings = fileManager.fileExists(atPath: settingsFileURL.path)
            if hadSettings { try fileManager.copyItem(at: settingsFileURL, to: previousSettingsURL) }

            let previousAttachmentsURL = rollbackDirectoryURL.appendingPathComponent("attachments", isDirectory: true)
            let hadAttachments = fileManager.fileExists(atPath: attachmentsDirectoryURL.path)
            if hadAttachments { try fileManager.moveItem(at: attachmentsDirectoryURL, to: previousAttachmentsURL) }

            do {
                if let importedAttachmentsURL = preparedImport.attachmentsURL {
                    try fileManager.copyItem(at: importedAttachmentsURL, to: attachmentsDirectoryURL)
                }
                try replaceFile(settingsFileURL, with: preparedImport.settingsURL)
                try databaseManager.replaceContents(from: preparedImport.databaseURL)
                let migrationMarkerURL = supportDirectoryURL.appendingPathComponent(".migration_completed")
                if !fileManager.fileExists(atPath: migrationMarkerURL.path) {
                    try Data().write(to: migrationMarkerURL, options: .atomic)
                }
            } catch {
                let originalError = error.localizedDescription
                var rollbackErrors: [String] = []
                do { try databaseManager.replaceContents(from: previousDatabaseURL) }
                catch { rollbackErrors.append("database: \(error.localizedDescription)") }
                do { try replaceFile(settingsFileURL, with: hadSettings ? previousSettingsURL : nil) }
                catch { rollbackErrors.append("settings: \(error.localizedDescription)") }
                do {
                    if fileManager.fileExists(atPath: attachmentsDirectoryURL.path) {
                        try fileManager.removeItem(at: attachmentsDirectoryURL)
                    }
                    if hadAttachments {
                        try fileManager.moveItem(at: previousAttachmentsURL, to: attachmentsDirectoryURL)
                    }
                } catch {
                    rollbackErrors.append("attachments: \(error.localizedDescription)")
                }

                if rollbackErrors.isEmpty { throw error }
                throw BackupExportError.rollbackFailure("\(originalError); \(rollbackErrors.joined(separator: "; "))")
            }

        case .merge:
            var copiedAttachmentURLs: [URL] = []
            let hadAttachmentsDirectory = fileManager.fileExists(atPath: attachmentsDirectoryURL.path)
            do {
                if let importedAttachmentsURL = preparedImport.attachmentsURL {
                    try fileManager.createDirectory(at: attachmentsDirectoryURL, withIntermediateDirectories: true)
                    let entries = try fileManager.contentsOfDirectory(
                        at: importedAttachmentsURL,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    )
                    for entry in entries {
                        let destinationURL = attachmentsDirectoryURL.appendingPathComponent(entry.lastPathComponent)
                        guard !fileManager.fileExists(atPath: destinationURL.path) else { continue }
                        try fileManager.copyItem(at: entry, to: destinationURL)
                        copiedAttachmentURLs.append(destinationURL)
                    }
                }
                try databaseManager.mergeContents(from: preparedImport.databaseURL)
            } catch {
                for url in copiedAttachmentURLs { try? fileManager.removeItem(at: url) }
                if !hadAttachmentsDirectory,
                   fileManager.fileExists(atPath: attachmentsDirectoryURL.path),
                   (try? fileManager.contentsOfDirectory(atPath: attachmentsDirectoryURL.path).isEmpty) == true {
                    try? fileManager.removeItem(at: attachmentsDirectoryURL)
                }
                throw error
            }
        }
    }

    private func replaceFile(_ destinationURL: URL, with sourceURL: URL?) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        if let sourceURL {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private func validateDatabase(at databaseURL: URL) throws {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw BackupExportError.invalidArchive("clipster.db is missing.")
        }
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let details = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open the database."
            sqlite3_close(database)
            throw BackupExportError.invalidArchive(details)
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA quick_check;", -1, &statement, nil) == SQLITE_OK else {
            throw BackupExportError.invalidArchive("Could not check SQLite database integrity.")
        }
        let checkResult = sqlite3_step(statement)
        let integrity = checkResult == SQLITE_ROW ? sqlite3_column_text(statement, 0).map { String(cString: $0) } : nil
        sqlite3_finalize(statement)
        guard integrity == "ok" else {
            throw BackupExportError.invalidArchive("SQLite integrity check failed.")
        }

        for table in ["clipboard_history", "recently_deleted"] {
            guard sqliteTableExists(table, in: database) else {
                throw BackupExportError.invalidArchive("Required database table \(table) is missing.")
            }
        }
    }

    private func validateArchiveEntryPaths(at archiveURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z", "-1", archiveURL.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw BackupExportError.extractionFailure(error.localizedDescription)
        }
        let listing = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BackupExportError.invalidArchive("The ZIP directory could not be read.")
        }

        let entries = String(decoding: listing, as: UTF8.self).split(whereSeparator: \.isNewline)
        guard !entries.isEmpty else {
            throw BackupExportError.invalidArchive("The ZIP archive is empty.")
        }
        for entry in entries {
            let path = String(entry)
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard
                !path.hasPrefix("/"),
                !path.contains("\\"),
                !components.contains(".."),
                !components.contains(".")
            else {
                throw BackupExportError.invalidArchive("Unsafe ZIP entry path: \(path)")
            }
        }
    }

    private func sqliteTableExists(_ table: String, in database: OpaquePointer?) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, table, -1, transient)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func validateNoSymbolicLinks(in directoryURL: URL) throws {
        let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw BackupExportError.invalidArchive("Symbolic links are not allowed in backups.")
        }
        guard values.isDirectory == true else { return }
        for child in try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            try validateNoSymbolicLinks(in: child)
        }
    }

    private func validateAttachments(at attachmentsURL: URL) throws {
        let values = try attachmentsURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw BackupExportError.invalidArchive("attachments must be a regular directory.")
        }
        for entry in try fileManager.contentsOfDirectory(at: attachmentsURL, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let entryValues = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard
                entryValues.isDirectory != true,
                entryValues.isSymbolicLink != true,
                entry.lastPathComponent != ".",
                entry.lastPathComponent != "..",
                !entry.lastPathComponent.contains("/")
            else {
                throw BackupExportError.invalidArchive("Invalid attachment entry: \(entry.lastPathComponent).")
            }
        }
    }

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
