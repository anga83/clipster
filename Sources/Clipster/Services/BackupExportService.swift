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
        case archiveFailure(String)

        var errorDescription: String? {
            switch self {
            case .databaseMissing(let url):
                return "Database file not found: \(url.path)"
            case .sqliteFailure(let details):
                return "SQLite backup failed: \(details)"
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

            progress("Copying settings...", 0.35)
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
            "contents": ["clipster.db", "settings.plist", "attachments/"]
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

    private func sqliteErrorMessage(from database: OpaquePointer?) -> String {
        guard let database else {
            return "Unknown SQLite error."
        }
        return String(cString: sqlite3_errmsg(database))
    }
}
