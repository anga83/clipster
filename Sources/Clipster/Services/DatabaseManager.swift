import Foundation
import SQLite3

/// Manages SQLite database operations for clipboard history storage
class DatabaseManager: @unchecked Sendable {
    private var db: OpaquePointer?
    private let dbURL: URL
    private let supportURL: URL
    private let debugLogger = DebugLogger.shared

    enum BackupTransferError: LocalizedError {
        case databaseUnavailable
        case sqlite(String)
        case invalidSnapshot(String)

        var errorDescription: String? {
            switch self {
            case .databaseUnavailable:
                return "The Clipster database is not available."
            case .sqlite(let message):
                return "SQLite backup import failed: \(message)"
            case .invalidSnapshot(let message):
                return "The backup database is invalid: \(message)"
            }
        }
    }
    
    // Database schema version for future migrations
    private let currentSchemaVersion = 2
    
    init() {
        debugLogger.logFunctionEntry()
        
        // Get Application Support directory
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not find Application Support directory.")
        }
        
        self.supportURL = appSupportURL.appendingPathComponent("Clipster")
        self.dbURL = supportURL.appendingPathComponent("clipster.db")
        
        debugLogger.logDatabaseOperation("Database path", details: dbURL.path)
        
        // Create support directory if needed
        if !FileManager.default.fileExists(atPath: supportURL.path) {
            debugLogger.logDatabaseOperation("Creating support directory", details: supportURL.path)
            do {
                try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true, attributes: nil)
                debugLogger.logDatabaseOperation("Support directory created successfully")
            } catch {
                debugLogger.logDatabaseOperation("Failed to create directory", details: error.localizedDescription)
                print("DatabaseManager: Failed to create directory: \(error)")
            }
        } else {
            debugLogger.logDatabaseOperation("Support directory already exists")
        }
        
        debugLogger.logDatabaseOperation("Opening database")
        openDatabase()
        debugLogger.logDatabaseOperation("Creating tables")
        createTables()
        debugLogger.logDatabaseOperation("Checking migration")
        checkAndPerformMigration()
        
        debugLogger.logFunctionExit()
    }
    
    deinit {
        closeDatabase()
    }
    
    // MARK: - Database Connection
    
    private func openDatabase() {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(dbURL.path, &db, flags, nil) == SQLITE_OK {
            // Enable foreign keys
            sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
            
            // Enable WAL mode for better concurrency
            sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)

            // Wait briefly for write locks instead of failing immediately under concurrent access.
            sqlite3_busy_timeout(db, 3000)
            
        } else {
            print("DatabaseManager: Unable to open database, error: \(String(cString: sqlite3_errmsg(db)))")
            db = nil
        }
    }
    
    private func closeDatabase() {
        if sqlite3_close(db) == SQLITE_OK {
            print("DatabaseManager: Database closed successfully")
        } else {
            print("DatabaseManager: Error closing database")
        }
        db = nil
    }

    func hasStoredItems() -> Bool {
        guard let db else { return false }
        return rowCount(in: "clipboard_history", database: db) > 0
            || rowCount(in: "recently_deleted", database: db) > 0
    }

    func createSnapshot(at destinationURL: URL) throws {
        guard let db else { throw BackupTransferError.databaseUnavailable }
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destinationURL)

        var destination: OpaquePointer?
        let openResult = sqlite3_open_v2(
            destinationURL.path,
            &destination,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let destination else {
            let message = sqliteErrorMessage(from: destination)
            sqlite3_close(destination)
            throw BackupTransferError.sqlite(message)
        }
        defer { sqlite3_close(destination) }
        try copyDatabase(from: db, to: destination)
    }

    func replaceContents(from snapshotURL: URL) throws {
        guard let db else { throw BackupTransferError.databaseUnavailable }
        var source: OpaquePointer?
        let openResult = sqlite3_open_v2(
            snapshotURL.path,
            &source,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let source else {
            let message = sqliteErrorMessage(from: source)
            sqlite3_close(source)
            throw BackupTransferError.invalidSnapshot(message)
        }
        defer { sqlite3_close(source) }

        try copyDatabase(from: source, to: db)
        createTables()
    }

    func mergeContents(from snapshotURL: URL) throws {
        guard let db else { throw BackupTransferError.databaseUnavailable }
        var attachStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "ATTACH DATABASE ? AS imported_backup;", -1, &attachStatement, nil) == SQLITE_OK else {
            throw BackupTransferError.sqlite(sqliteErrorMessage(from: db))
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(attachStatement, 1, snapshotURL.path, -1, transient)
        let attachResult = sqlite3_step(attachStatement)
        sqlite3_finalize(attachStatement)
        guard attachResult == SQLITE_DONE else {
            throw BackupTransferError.invalidSnapshot(sqliteErrorMessage(from: db))
        }

        var transactionStarted = false
        do {
            try executeTransferSQL("BEGIN IMMEDIATE;")
            transactionStarted = true

            for table in ["clipboard_history", "recently_deleted"] {
                let targetColumns = tableColumns(table, schema: "main", database: db)
                let sourceColumns = tableColumns(table, schema: "imported_backup", database: db)
                if sourceColumns.isEmpty {
                    if table == "clipboard_history" {
                        throw BackupTransferError.invalidSnapshot("Missing table \(table).")
                    }
                    continue
                }

                let commonColumns = targetColumns.filter { sourceColumns.contains($0) }
                guard commonColumns.contains("id"), !commonColumns.isEmpty else {
                    throw BackupTransferError.invalidSnapshot("Table \(table) has no compatible ID column.")
                }
                let columnList = commonColumns.map(quoteIdentifier).joined(separator: ", ")
                try executeTransferSQL(
                    "INSERT OR IGNORE INTO main.\(table) (\(columnList)) SELECT \(columnList) FROM imported_backup.\(table);"
                )
            }

            try executeTransferSQL("COMMIT;")
            transactionStarted = false
            try? executeTransferSQL("DETACH DATABASE imported_backup;")
        } catch {
            if transactionStarted { try? executeTransferSQL("ROLLBACK;") }
            try? executeTransferSQL("DETACH DATABASE imported_backup;")
            throw error
        }
    }

    private func copyDatabase(from source: OpaquePointer, to destination: OpaquePointer) throws {
        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw BackupTransferError.sqlite(sqliteErrorMessage(from: destination))
        }

        var result: Int32
        repeat {
            result = sqlite3_backup_step(backup, 256)
            if result == SQLITE_BUSY || result == SQLITE_LOCKED { sqlite3_sleep(25) }
        } while result == SQLITE_OK || result == SQLITE_BUSY || result == SQLITE_LOCKED

        let finishResult = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw BackupTransferError.sqlite(sqliteErrorMessage(from: destination))
        }
    }

    private func executeTransferSQL(_ sql: String) throws {
        guard let db else { throw BackupTransferError.databaseUnavailable }
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? sqliteErrorMessage(from: db)
            sqlite3_free(errorMessage)
            throw BackupTransferError.sqlite(message)
        }
        sqlite3_free(errorMessage)
    }

    private func tableColumns(_ table: String, schema: String, database: OpaquePointer) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA \(schema).table_info(\(table));", -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var columns: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) {
                columns.append(String(cString: name))
            }
        }
        return columns
    }

    private func quoteIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func rowCount(in table: String, database: OpaquePointer) -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM \(table);", -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
    }

    private func sqliteErrorMessage(from database: OpaquePointer?) -> String {
        guard let database else { return "Unknown SQLite error." }
        return String(cString: sqlite3_errmsg(database))
    }
    
    // MARK: - Table Creation
    
    private func createTables() {
        createMainHistoryTable()
        createRecentlyDeletedTable()
        createSchemaVersionTable()
    }
    
    private func createMainHistoryTable() {
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS clipboard_history (
            id TEXT PRIMARY KEY,
            content_type INTEGER NOT NULL,
            content_text TEXT,
            content_url TEXT,
            timestamp REAL NOT NULL,
            source_app_bundle_id TEXT,
            source_app_name TEXT,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            attachment_data BLOB,
            attachment_filename TEXT,
            attachment_file_extension TEXT,
            attachment_uti TEXT,
            physical_filename TEXT,
            formatted_content BLOB,
            created_at REAL NOT NULL DEFAULT (julianday('now')),
            updated_at REAL NOT NULL DEFAULT (julianday('now'))
        );
        """
        
        executeSQL(createTableSQL, errorMessage: "Failed to create clipboard_history table")
        ensureColumn("formatted_content", in: "clipboard_history", definition: "BLOB")
        
        // Create indices for better performance
        executeSQL("CREATE INDEX IF NOT EXISTS idx_timestamp ON clipboard_history(timestamp DESC);", 
                  errorMessage: "Failed to create timestamp index")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_pinned ON clipboard_history(is_pinned);", 
                  errorMessage: "Failed to create pinned index")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_source_app ON clipboard_history(source_app_name);", 
                  errorMessage: "Failed to create source_app index")
    }
    
    private func createRecentlyDeletedTable() {
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS recently_deleted (
            id TEXT PRIMARY KEY,
            content_type INTEGER NOT NULL,
            content_text TEXT,
            content_url TEXT,
            original_timestamp REAL NOT NULL,
            deleted_timestamp REAL NOT NULL DEFAULT (julianday('now')),
            source_app_bundle_id TEXT,
            source_app_name TEXT,
            was_pinned INTEGER NOT NULL DEFAULT 0,
            attachment_data BLOB,
            attachment_filename TEXT,
            attachment_file_extension TEXT,
            attachment_uti TEXT,
            physical_filename TEXT,
            formatted_content BLOB,
            attachment_deleted INTEGER NOT NULL DEFAULT 0,
            attachment_deleted_timestamp REAL
        );
        """
        
        executeSQL(createTableSQL, errorMessage: "Failed to create recently_deleted table")
        ensureColumn("formatted_content", in: "recently_deleted", definition: "BLOB")
        
        // Create indices
        executeSQL("CREATE INDEX IF NOT EXISTS idx_deleted_timestamp ON recently_deleted(deleted_timestamp DESC);", 
                  errorMessage: "Failed to create deleted_timestamp index")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_attachment_cleanup ON recently_deleted(attachment_deleted, attachment_deleted_timestamp);", 
                  errorMessage: "Failed to create attachment_cleanup index")
    }
    
    private func createSchemaVersionTable() {
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER PRIMARY KEY
        );
        """
        
        executeSQL(createTableSQL, errorMessage: "Failed to create schema_version table")
        
        // Insert current version if not exists
        let insertVersionSQL = "INSERT OR IGNORE INTO schema_version (version) VALUES (?);"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, insertVersionSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(currentSchemaVersion))
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    private func ensureColumn(_ column: String, in table: String, definition: String) {
        var statement: OpaquePointer?
        var exists = false
        if sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let name = sqlite3_column_text(statement, 1), String(cString: name) == column {
                    exists = true
                    break
                }
            }
        }
        sqlite3_finalize(statement)
        if !exists {
            executeSQL("ALTER TABLE \(table) ADD COLUMN \(column) \(definition);", errorMessage: "Failed to add \(column) to \(table)")
        }
    }
    
    // MARK: - Migration
    
    private func checkAndPerformMigration() {
        let legacyJSONURL = supportURL.appendingPathComponent("history.json")
        let migrationMarkerURL = supportURL.appendingPathComponent(".migration_completed")
        
        // Check if legacy JSON file exists and migration hasn't been completed yet
        if FileManager.default.fileExists(atPath: legacyJSONURL.path) && 
           !FileManager.default.fileExists(atPath: migrationMarkerURL.path) {
            print("DatabaseManager: Found legacy JSON file, starting migration...")
            migrateFromJSON(jsonURL: legacyJSONURL)
            
            // Create migration marker to prevent re-migration
            do {
                try Data().write(to: migrationMarkerURL)
                print("DatabaseManager: Migration completed and marked")
            } catch {
                print("DatabaseManager: Failed to create migration marker: \(error)")
            }
        }
    }
    
    private func isMainTableEmpty() -> Bool {
        let countSQL = "SELECT COUNT(*) FROM clipboard_history;"
        var statement: OpaquePointer?
        var count = 0
        
        if sqlite3_prepare_v2(db, countSQL, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        
        return count == 0
    }
    
    private func migrateFromJSON(jsonURL: URL) {
        do {
            let jsonData = try Data(contentsOf: jsonURL)
            let decoder = JSONDecoder()
            let legacyItems = try decoder.decode([ClipboardItem].self, from: jsonData)
            
            print("DatabaseManager: Migrating \(legacyItems.count) items from JSON to SQLite...")
            
            // Clear existing data before migration
            let clearSQL = "DELETE FROM clipboard_history;"
            executeSQL(clearSQL, errorMessage: "Failed to clear existing data")
            
            for item in legacyItems {
                insertClipboardItem(item)
            }
            
            // Create backup of original JSON file
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = dateFormatter.string(from: Date())
            let backupURL = jsonURL.deletingLastPathComponent().appendingPathComponent("history_migrated_\(timestamp).json")
            try FileManager.default.copyItem(at: jsonURL, to: backupURL)
            
            print("DatabaseManager: Migration completed successfully! Migrated \(legacyItems.count) items")
            print("DatabaseManager: Original JSON backed up to \(backupURL.lastPathComponent)")
            
        } catch {
            print("DatabaseManager: Migration failed: \(error)")
        }
    }
    
    // MARK: - CRUD Operations
    
    // Helper method for safe string binding with SQLITE_TRANSIENT
    private func bindString(_ statement: OpaquePointer?, _ string: String?, at index: Int32) {
        if let string = string {
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, index, string, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    // Helper method for safe blob binding with SQLITE_TRANSIENT
    private func bindBlob(_ statement: OpaquePointer?, _ data: Data?, at index: Int32) {
        guard let data else {
            sqlite3_bind_null(statement, index)
            return
        }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = data.withUnsafeBytes { rawBufferPointer in
            sqlite3_bind_blob(
                statement,
                index,
                rawBufferPointer.bindMemory(to: UInt8.self).baseAddress,
                Int32(data.count),
                SQLITE_TRANSIENT
            )
        }
    }
    
    func insertClipboardItem(_ item: ClipboardItem) {
        debugLogger.logFunctionEntry()
        debugLogger.logDatabaseOperation("Inserting clipboard item", details: "ID: \(item.id.uuidString)")
        
        print("DatabaseManager: Inserting item with ID \(item.id.uuidString)")
        
        let insertSQL = """
        INSERT OR REPLACE INTO clipboard_history 
        (id, content_type, content_text, content_url, timestamp, source_app_bundle_id, source_app_name, 
         is_pinned, attachment_data, attachment_filename, attachment_file_extension, attachment_uti, physical_filename, formatted_content)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        debugLogger.logDatabaseOperation("Prepared INSERT statement", details: insertSQL)
        
        var statement: OpaquePointer?
        
        debugLogger.logDatabaseOperation("Preparing SQLite statement")
        
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            debugLogger.logDatabaseOperation("Statement prepared successfully, binding parameters")
            
            // Bind UUID as string with SQLITE_TRANSIENT to make a copy
            let uuidString = item.id.uuidString
            debugLogger.logDatabaseOperation("Binding UUID", details: "UUID: '\(uuidString)' (length: \(uuidString.count))")
            bindString(statement, uuidString, at: 1)
            
            // Content type and data
            switch item.content {
            case .text(let text):
                debugLogger.logDatabaseOperation("Binding text content", details: "Length: \(text.count)")
                print("DatabaseManager: Inserting text content: '\(text.prefix(50))...'")
                sqlite3_bind_int(statement, 2, 0) // text type
                bindString(statement, text, at: 3)
                sqlite3_bind_null(statement, 4)
            case .fileURL(let url):
                let urlString = url.absoluteString
                debugLogger.logDatabaseOperation("Binding file URL", details: urlString)
                print("DatabaseManager: Inserting file URL: \(urlString)")
                sqlite3_bind_int(statement, 2, 1) // file URL type
                sqlite3_bind_null(statement, 3)
                bindString(statement, urlString, at: 4)
            }
            
            sqlite3_bind_double(statement, 5, item.timestamp.timeIntervalSince1970)
            
            bindString(statement, item.sourceAppBundleIdentifier, at: 6)
            bindString(statement, item.sourceAppName, at: 7)
            
            sqlite3_bind_int(statement, 8, item.isPinned ? 1 : 0)
            
            // Attachment data
            bindBlob(statement, item.attachmentData, at: 9)
            bindString(statement, item.attachmentFilename, at: 10)
            bindString(statement, item.attachmentFileExtension, at: 11)
            bindString(statement, item.attachmentUTI, at: 12)
            bindString(statement, item.physicalFileName, at: 13)
            bindBlob(statement, item.formattedContent, at: 14)
            
            debugLogger.logDatabaseOperation("All parameters bound, executing statement")
            
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                debugLogger.logDatabaseOperation("Successfully inserted clipboard item", details: "ID: \(item.id)")
                print("DatabaseManager: Successfully inserted clipboard item")
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                debugLogger.logDatabaseOperation("Failed to insert clipboard item", details: "Error: \(error)")
                print("DatabaseManager: Failed to insert clipboard item: \(error)")
            }
        } else {
            let error = String(cString: sqlite3_errmsg(db))
            debugLogger.logDatabaseOperation("Failed to prepare insert statement", details: "Error: \(error)")
            print("DatabaseManager: Failed to prepare insert statement: \(error)")
        }
        
        sqlite3_finalize(statement)
        debugLogger.logFunctionExit()
    }
    
    func loadAllClipboardItems(includeBlobs: Bool = false, limit: Int? = nil, offset: Int? = nil) -> [ClipboardItem] {
        debugLogger.logFunctionEntry()
        debugLogger.logDatabaseOperation("Loading all clipboard items from database")
        
        // Prefer a lightweight query without BLOBs for performance unless explicitly requested
        let selectSQL: String
        func limitOffsetClause(limit: Int?, offset: Int?) -> String {
            var clause = ""
            if let l = limit { clause += " LIMIT \(l)" }
            if let o = offset { clause += clause.isEmpty ? " LIMIT -1 OFFSET \(o)" : " OFFSET \(o)" }
            return clause
        }

        if includeBlobs {
            selectSQL = """
            SELECT id, content_type, content_text, content_url, timestamp, source_app_bundle_id, source_app_name,
                   is_pinned, attachment_data, attachment_filename, attachment_file_extension, attachment_uti, physical_filename, formatted_content
            FROM clipboard_history 
            ORDER BY timestamp DESC
            """.appending(limitOffsetClause(limit: limit, offset: offset)).appending(";")
        } else {
            selectSQL = """
            SELECT id, content_type, content_text, content_url, timestamp, source_app_bundle_id, source_app_name,
                   is_pinned, attachment_filename, attachment_file_extension, attachment_uti, physical_filename, formatted_content
            FROM clipboard_history 
            ORDER BY timestamp DESC
            """.appending(limitOffsetClause(limit: limit, offset: offset)).appending(";")
        }
        
        debugLogger.logDatabaseOperation("Prepared SELECT statement", details: selectSQL)
        
        var items: [ClipboardItem] = []
        var statement: OpaquePointer?
        
        debugLogger.logDatabaseOperation("Preparing SQLite statement")
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            debugLogger.logDatabaseOperation("Statement prepared successfully, executing query")
            
            var rowCount = 0
            while sqlite3_step(statement) == SQLITE_ROW {
                rowCount += 1
                debugLogger.logDatabaseOperation("Processing row \(rowCount)")
                
                if includeBlobs {
                    if let item = createClipboardItemFromRow(statement: statement) {
                        items.append(item)
                        debugLogger.logDatabaseOperation("Successfully created ClipboardItem", details: "ID: \(item.id)")
                    } else {
                        debugLogger.logDatabaseOperation("Failed to create ClipboardItem from row \(rowCount)")
                    }
                } else if let item = createClipboardItemFromRowLight(statement: statement) {
                    items.append(item)
                    debugLogger.logDatabaseOperation("Successfully created ClipboardItem", details: "ID: \(item.id)")
                } else {
                    debugLogger.logDatabaseOperation("Failed to create ClipboardItem from row \(rowCount)")
                }
            }
            
            debugLogger.logDatabaseOperation("Query complete", details: "Processed \(rowCount) rows, created \(items.count) items")
        } else {
            let error = String(cString: sqlite3_errmsg(db))
            debugLogger.logDatabaseOperation("Failed to prepare select statement", details: "Error: \(error)")
            print("DatabaseManager: Failed to prepare select statement")
        }
        
        sqlite3_finalize(statement)
        
        debugLogger.logDatabaseOperation("Returning \(items.count) items")
        debugLogger.logFunctionExit()
        return items
    }

    // Lightweight row decoder that intentionally does NOT read attachment_data BLOBs.
    // Column order for the lightweight SELECT:
    // 0:id, 1:content_type, 2:content_text, 3:content_url, 4:timestamp, 5:source_app_bundle_id,
    // 6:source_app_name, 7:is_pinned, 8:attachment_filename, 9:attachment_file_extension,
        // 10:attachment_uti, 11:physical_filename, 12:formatted_content
    private func createClipboardItemFromRowLight(statement: OpaquePointer?) -> ClipboardItem? {
        guard let statement = statement else { return nil }
        guard let idCString = sqlite3_column_text(statement, 0), let uuid = UUID(uuidString: String(cString: idCString)) else {
            return nil
        }

        let contentType = sqlite3_column_int(statement, 1)
        let content: ClipboardContent
        if contentType == 0 {
            guard let textCString = sqlite3_column_text(statement, 2) else { return nil }
            content = .text(String(cString: textCString))
        } else {
            guard let urlCString = sqlite3_column_text(statement, 3), let url = URL(string: String(cString: urlCString)) else { return nil }
            content = .fileURL(url)
        }

        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
        let bundleId: String? = {
            guard let c = sqlite3_column_text(statement, 5) else { return nil }
            return String(cString: c)
        }()
        let appName: String? = {
            guard let c = sqlite3_column_text(statement, 6) else { return nil }
            return String(cString: c)
        }()
        let isPinned = sqlite3_column_int(statement, 7) == 1

        // Intentionally do not read attachment_data; set to nil for lightweight load
        let attachmentFilename: String? = {
            guard let c = sqlite3_column_text(statement, 8) else { return nil }
            return String(cString: c)
        }()
        let attachmentFileExtension: String? = {
            guard let c = sqlite3_column_text(statement, 9) else { return nil }
            return String(cString: c)
        }()
        let attachmentUTI: String? = {
            guard let c = sqlite3_column_text(statement, 10) else { return nil }
            return String(cString: c)
        }()
        let physicalFileName: String? = {
            guard let c = sqlite3_column_text(statement, 11) else { return nil }
            return String(cString: c)
        }()
        let formattedContent: Data? = {
            guard let blob = sqlite3_column_blob(statement, 12) else { return nil }
            return Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 12)))
        }()

        return ClipboardItem(
            id: uuid,
            content: content,
            timestamp: timestamp,
            isPinned: isPinned,
            sourceAppBundleIdentifier: bundleId,
            sourceAppName: appName,
            attachmentData: nil,
            isSymlinked: false,
            physicalFileName: physicalFileName,
            hasInlineAttachment: (physicalFileName == nil && (attachmentFilename != nil || attachmentUTI != nil)),
            attachmentFilename: attachmentFilename,
            attachmentFileExtension: attachmentFileExtension,
            attachmentUTI: attachmentUTI,
            formattedContent: formattedContent
        )
    }

    // MARK: - Counts and targeted loads (lightweight)

    func countAllClipboardItems() -> Int {
        let sql = "SELECT COUNT(*) FROM clipboard_history;"
        var statement: OpaquePointer?
        var count = 0
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        return count
    }

    func loadPinnedItems() -> [ClipboardItem] {
        let sql = """
        SELECT id, content_type, content_text, content_url, timestamp, source_app_bundle_id, source_app_name,
               is_pinned, attachment_filename, attachment_file_extension, attachment_uti, physical_filename, formatted_content
        FROM clipboard_history
        WHERE is_pinned = 1
        ORDER BY timestamp DESC;
        """
        var items: [ClipboardItem] = []
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let item = createClipboardItemFromRowLight(statement: statement) {
                    items.append(item)
                }
            }
        }
        sqlite3_finalize(statement)
        return items
    }

    func loadRecentUnpinnedItems(limit: Int) -> [ClipboardItem] {
        let sql = """
        SELECT id, content_type, content_text, content_url, timestamp, source_app_bundle_id, source_app_name,
               is_pinned, attachment_filename, attachment_file_extension, attachment_uti, physical_filename, formatted_content
        FROM clipboard_history
        WHERE is_pinned = 0
        ORDER BY timestamp DESC
        LIMIT \(limit);
        """
        var items: [ClipboardItem] = []
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let item = createClipboardItemFromRowLight(statement: statement) {
                    items.append(item)
                }
            }
        }
        sqlite3_finalize(statement)
        return items
    }

    func searchClipboardItems(query: String, sourceAppName: String? = nil, limit: Int = 1000) -> [ClipboardItem] {
        // Use case-insensitive match on text/url and optional source app filter
        var sql = """
        SELECT id, content_type, content_text, content_url, timestamp, source_app_bundle_id, source_app_name,
               is_pinned, attachment_filename, attachment_file_extension, attachment_uti, physical_filename, formatted_content
        FROM clipboard_history
        WHERE (content_text LIKE ? ESCAPE '\\' OR content_url LIKE ? ESCAPE '\\')
        """
        if sourceAppName != nil {
            sql += " AND source_app_name = ?"
        }
        sql += " ORDER BY timestamp DESC LIMIT \(limit);"

        var statement: OpaquePointer?
        var items: [ClipboardItem] = []
        let pattern = "%\(escapeLike(query))%"

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            bindString(statement, pattern, at: 1)
            bindString(statement, pattern, at: 2)
            if let app = sourceAppName {
                bindString(statement, app, at: 3)
            }
            while sqlite3_step(statement) == SQLITE_ROW {
                if let item = createClipboardItemFromRowLight(statement: statement) { items.append(item) }
            }
        }
        sqlite3_finalize(statement)
        return items
    }

    func loadFilterMetadata() -> (appNames: [String], oldestDate: Date?, newestDate: Date?) {
        var appNames: [String] = []
        var appStatement: OpaquePointer?
        let appsSQL = """
        SELECT DISTINCT source_app_name
        FROM clipboard_history
        WHERE source_app_name IS NOT NULL AND source_app_name != ''
        ORDER BY source_app_name COLLATE NOCASE ASC;
        """

        if sqlite3_prepare_v2(db, appsSQL, -1, &appStatement, nil) == SQLITE_OK {
            while sqlite3_step(appStatement) == SQLITE_ROW {
                if let appNameCString = sqlite3_column_text(appStatement, 0) {
                    appNames.append(String(cString: appNameCString))
                }
            }
        }
        sqlite3_finalize(appStatement)

        var oldestDate: Date?
        var newestDate: Date?
        var rangeStatement: OpaquePointer?
        let rangeSQL = "SELECT MIN(timestamp), MAX(timestamp) FROM clipboard_history;"
        if sqlite3_prepare_v2(db, rangeSQL, -1, &rangeStatement, nil) == SQLITE_OK,
           sqlite3_step(rangeStatement) == SQLITE_ROW {
            if sqlite3_column_type(rangeStatement, 0) != SQLITE_NULL {
                oldestDate = Date(timeIntervalSince1970: sqlite3_column_double(rangeStatement, 0))
            }
            if sqlite3_column_type(rangeStatement, 1) != SQLITE_NULL {
                newestDate = Date(timeIntervalSince1970: sqlite3_column_double(rangeStatement, 1))
            }
        }
        sqlite3_finalize(rangeStatement)

        return (appNames: appNames, oldestDate: oldestDate, newestDate: newestDate)
    }

    func queryClipboardItems(
        searchText: String,
        sourceAppNames: [String],
        pinnedOnly: Bool,
        startDate: Date?,
        endDate: Date?,
        minTextLength: Int?,
        maxTextLength: Int?
    ) -> [ClipboardItem] {
        enum QueryParameter {
            case text(String)
            case int(Int)
            case double(Double)
        }

        var sql = """
        SELECT id, content_type, content_text, content_url, timestamp, source_app_bundle_id, source_app_name,
               is_pinned, attachment_filename, attachment_file_extension, attachment_uti, physical_filename, formatted_content
        FROM clipboard_history
        """

        var whereClauses: [String] = []
        var parameters: [QueryParameter] = []

        if !searchText.isEmpty {
            whereClauses.append("(content_text LIKE ? ESCAPE '\\' OR content_url LIKE ? ESCAPE '\\')")
            let pattern = "%\(escapeLike(searchText))%"
            parameters.append(.text(pattern))
            parameters.append(.text(pattern))
        }

        if !sourceAppNames.isEmpty {
            let placeholders = Array(repeating: "?", count: sourceAppNames.count).joined(separator: ", ")
            whereClauses.append("source_app_name IN (\(placeholders))")
            for appName in sourceAppNames.sorted() {
                parameters.append(.text(appName))
            }
        }

        if pinnedOnly {
            whereClauses.append("is_pinned = 1")
        }

        if let startDate {
            whereClauses.append("timestamp >= ?")
            parameters.append(.double(startDate.timeIntervalSince1970))
        }

        if let endDate {
            whereClauses.append("timestamp <= ?")
            parameters.append(.double(endDate.timeIntervalSince1970))
        }

        let hasTextLengthFilter = minTextLength != nil || maxTextLength != nil
        if hasTextLengthFilter {
            whereClauses.append("content_type = 0")
        }

        if let minTextLength {
            whereClauses.append("LENGTH(COALESCE(content_text, '')) >= ?")
            parameters.append(.int(max(0, minTextLength)))
        }

        if let maxTextLength {
            whereClauses.append("LENGTH(COALESCE(content_text, '')) <= ?")
            parameters.append(.int(max(0, maxTextLength)))
        }

        if !whereClauses.isEmpty {
            sql += " WHERE " + whereClauses.joined(separator: " AND ")
        }

        sql += " ORDER BY timestamp DESC;"

        var items: [ClipboardItem] = []
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("DatabaseManager: queryClipboardItems prepare failed: \(errorMessage)")
            sqlite3_finalize(statement)
            return []
        }

        for (index, parameter) in parameters.enumerated() {
            let parameterIndex = Int32(index + 1)
            switch parameter {
            case .text(let value):
                bindString(statement, value, at: parameterIndex)
            case .int(let value):
                sqlite3_bind_int(statement, parameterIndex, Int32(value))
            case .double(let value):
                sqlite3_bind_double(statement, parameterIndex, value)
            }
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            if let item = createClipboardItemFromRowLight(statement: statement) {
                items.append(item)
            }
        }

        sqlite3_finalize(statement)
        return items
    }

    private func escapeLike(_ s: String) -> String {
        // Escape %, _ and \ for LIKE ESCAPE '\'
        var out = ""
        for ch in s {
            if ch == "%" || ch == "_" || ch == "\\" { out.append("\\") }
            out.append(ch)
        }
        return out
    }
    
    func deleteClipboardItem(_ item: ClipboardItem) {
        debugLogger.logFunctionEntry()
        debugLogger.logDatabaseOperation("Deleting clipboard item", details: "ID: \(item.id), Content: \(item.content)")
        
        // Move to recently_deleted table first
        debugLogger.logDatabaseOperation("Moving item to recently_deleted table")
        moveToRecentlyDeleted(item)
        
        // Then remove from main table
        let deleteSQL = "DELETE FROM clipboard_history WHERE id = ?;"
        var statement: OpaquePointer?
        
        debugLogger.logDatabaseOperation("Preparing DELETE statement")
        
        if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
            bindString(statement, item.id.uuidString, at: 1)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                debugLogger.logDatabaseOperation("Successfully deleted item from main table", details: "ID: \(item.id)")
                print("DatabaseManager: Moved item \(item.id) to recently_deleted")
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                debugLogger.logDatabaseOperation("Failed to delete item from main table", details: "Error: \(error)")
                print("DatabaseManager: Failed to delete item: \(error)")
            }
        } else {
            debugLogger.logDatabaseOperation("Failed to prepare DELETE statement")
        }
        
        sqlite3_finalize(statement)
        debugLogger.logFunctionExit()
    }
    
    // MARK: - Soft Delete Operations
    
    private func moveToRecentlyDeleted(_ item: ClipboardItem) {
        debugLogger.logFunctionEntry()
        debugLogger.logDatabaseOperation("Moving item to recently_deleted", details: "ID: \(item.id)")
        
        let insertSQL = """
        INSERT INTO recently_deleted 
        (id, content_type, content_text, content_url, original_timestamp, source_app_bundle_id, source_app_name,
         was_pinned, attachment_data, attachment_filename, attachment_file_extension, attachment_uti, physical_filename, formatted_content)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        
        debugLogger.logDatabaseOperation("Preparing INSERT statement for recently_deleted")
        
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            bindString(statement, item.id.uuidString, at: 1)
            
            // Content type and data
            switch item.content {
            case .text(let text):
                sqlite3_bind_int(statement, 2, 0)
                bindString(statement, text, at: 3)
                sqlite3_bind_null(statement, 4)
            case .fileURL(let url):
                sqlite3_bind_int(statement, 2, 1)
                sqlite3_bind_null(statement, 3)
                bindString(statement, url.absoluteString, at: 4)
            }
            
            sqlite3_bind_double(statement, 5, item.timestamp.timeIntervalSince1970)
            bindString(statement, item.sourceAppBundleIdentifier, at: 6)
            bindString(statement, item.sourceAppName, at: 7)
            
            sqlite3_bind_int(statement, 8, item.isPinned ? 1 : 0)
            
            // Attachment data
            if let attachmentData = item.attachmentData {
                sqlite3_bind_blob(statement, 9, attachmentData.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress }, Int32(attachmentData.count), nil)
            } else {
                sqlite3_bind_null(statement, 9)
            }
            
            bindString(statement, item.attachmentFilename, at: 10)
            bindString(statement, item.attachmentFileExtension, at: 11)
            bindString(statement, item.attachmentUTI, at: 12)
            bindString(statement, item.physicalFileName, at: 13)
            bindBlob(statement, item.formattedContent, at: 14)
            
            debugLogger.logDatabaseOperation("Executing INSERT for recently_deleted")
            let result = sqlite3_step(statement)
            
            if result == SQLITE_DONE {
                debugLogger.logDatabaseOperation("Successfully inserted item into recently_deleted", details: "ID: \(item.id)")
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                debugLogger.logDatabaseOperation("Failed to insert into recently_deleted", details: "Error: \(error)")
            }
        } else {
            debugLogger.logDatabaseOperation("Failed to prepare INSERT statement for recently_deleted")
        }
        
        sqlite3_finalize(statement)
        debugLogger.logFunctionExit()
    }
    
    func loadRecentlyDeletedItems() -> [ClipboardItem] {
        debugLogger.logFunctionEntry()
        debugLogger.logDatabaseOperation("Starting loadRecentlyDeletedItems")
        
        let selectSQL = """
        SELECT id, content_type, content_text, content_url, original_timestamp, source_app_bundle_id, source_app_name,
               was_pinned, attachment_data, attachment_filename, attachment_file_extension, attachment_uti, 
               physical_filename, attachment_deleted, deleted_timestamp, formatted_content
        FROM recently_deleted 
        ORDER BY deleted_timestamp DESC;
        """
        
        debugLogger.logDatabaseOperation("SQL Query prepared", details: selectSQL)
        
        var items: [ClipboardItem] = []
        var statement: OpaquePointer?
        
        debugLogger.logDatabaseOperation("Preparing SQLite statement")
        
        guard db != nil else {
            debugLogger.logCrashPrevention("Database connection is nil!")
            return []
        }
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            debugLogger.logDatabaseOperation("SQLite statement prepared successfully")
            
            var rowCount = 0
            while sqlite3_step(statement) == SQLITE_ROW {
                rowCount += 1
                debugLogger.logDatabaseOperation("Processing row \(rowCount)")
                
                if let item = createClipboardItemFromDeletedRow(statement: statement) {
                    items.append(item)
                    debugLogger.logDatabaseOperation("Successfully created item from row \(rowCount)", details: "ID: \(item.id)")
                } else {
                    debugLogger.logError(NSError(domain: "DatabaseManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create item from row"]), context: "loadRecentlyDeletedItems row \(rowCount)")
                }
            }
            
            debugLogger.logDatabaseOperation("Processed \(rowCount) rows, created \(items.count) items")
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            debugLogger.logError(NSError(domain: "SQLite", code: Int(sqlite3_errcode(db)), userInfo: [NSLocalizedDescriptionKey: errorMessage]), context: "loadRecentlyDeletedItems prepare")
            debugLogger.logCrashPrevention("SQLite prepare failed, returning empty array")
        }
        
        sqlite3_finalize(statement)
        debugLogger.logDatabaseOperation("Statement finalized")
        
        debugLogger.logFunctionExit()
        debugLogger.logDatabaseOperation("loadRecentlyDeletedItems completed", details: "Returning \(items.count) items")
        
        return items
    }
    
    func restoreFromRecentlyDeleted(_ itemId: UUID) {
        // First get the item from recently_deleted
        if let item = getRecentlyDeletedItem(itemId) {
            // Insert back to main table
            insertClipboardItem(item)
            
            // Remove from recently_deleted
            let deleteSQL = "DELETE FROM recently_deleted WHERE id = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
                bindString(statement, itemId.uuidString, at: 1)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
            
            print("DatabaseManager: Restored item \(itemId) from recently_deleted")
        }
    }
    
    func permanentlyDeleteFromArchive(_ itemId: UUID, settingsStore: SettingsStore) {
        // Get the item first to clean up attachments
        if let item = getRecentlyDeletedItem(itemId) {
            // Clean up physical files if needed
            if let physicalFileName = item.physicalFileName {
                settingsStore.deletePhysicalFile(filename: physicalFileName)
            }
        }
        
        let deleteSQL = "DELETE FROM recently_deleted WHERE id = ?;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
            bindString(statement, itemId.uuidString, at: 1)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }
    
    // MARK: - Archive Management (Public API)
    
    func getArchivedItems() -> [ClipboardItem] {
        return loadRecentlyDeletedItems()
    }
    
    func restoreFromArchive(_ itemId: UUID) {
        restoreFromRecentlyDeleted(itemId)
    }
    
    func getRecentlyDeletedItem(_ itemId: UUID) -> ClipboardItem? {
        let selectSQL = """
        SELECT id, content_type, content_text, content_url, original_timestamp, source_app_bundle_id, source_app_name,
               was_pinned, attachment_data, attachment_filename, attachment_file_extension, attachment_uti, 
               physical_filename, attachment_deleted, deleted_timestamp, formatted_content
        FROM recently_deleted 
        WHERE id = ? LIMIT 1;
        """
        
        var statement: OpaquePointer?
        var item: ClipboardItem?
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            bindString(statement, itemId.uuidString, at: 1)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                item = createClipboardItemFromDeletedRow(statement: statement)
            }
        }
        
        sqlite3_finalize(statement)
        return item
    }
    
    func getPhysicalFilenamesForCleanup(textRetentionDays: Int, attachmentRetentionDays: Int) -> [String] {
        var filenames: [String] = []
        
        // Handle text cleanup if not set to "Never" (-1)
        if textRetentionDays > 0 {
            let textCutoffDate = Date().addingTimeInterval(-Double(textRetentionDays * 24 * 60 * 60))
            
            let selectTextSQL = """
            SELECT physical_filename FROM recently_deleted 
            WHERE deleted_timestamp < ? AND content_type = 0 AND physical_filename IS NOT NULL;
            """
            var textSelectStatement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, selectTextSQL, -1, &textSelectStatement, nil) == SQLITE_OK {
                sqlite3_bind_double(textSelectStatement, 1, textCutoffDate.timeIntervalSince1970)
                
                while sqlite3_step(textSelectStatement) == SQLITE_ROW {
                    if let filename = sqlite3_column_text(textSelectStatement, 0) {
                        filenames.append(String(cString: filename))
                    }
                }
            }
            sqlite3_finalize(textSelectStatement)
        }
        
        // Handle attachment cleanup if not set to "Never" (-1)
        if attachmentRetentionDays > 0 {
            let attachmentCutoffDate = Date().addingTimeInterval(-Double(attachmentRetentionDays * 24 * 60 * 60))
            
            let selectAttachmentSQL = """
            SELECT physical_filename FROM recently_deleted 
            WHERE deleted_timestamp < ? AND (content_type = 1 OR attachment_data IS NOT NULL) AND physical_filename IS NOT NULL;
            """
            var attachmentSelectStatement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, selectAttachmentSQL, -1, &attachmentSelectStatement, nil) == SQLITE_OK {
                sqlite3_bind_double(attachmentSelectStatement, 1, attachmentCutoffDate.timeIntervalSince1970)
                
                while sqlite3_step(attachmentSelectStatement) == SQLITE_ROW {
                    if let filename = sqlite3_column_text(attachmentSelectStatement, 0) {
                        filenames.append(String(cString: filename))
                    }
                }
            }
            sqlite3_finalize(attachmentSelectStatement)
        }
        
        return filenames
    }

    func cleanupOldArchivedItems(textRetentionDays: Int, attachmentRetentionDays: Int) {
        // Handle text cleanup if not set to "Never" (-1)
        if textRetentionDays > 0 {
            let textCutoffDate = Date().addingTimeInterval(-Double(textRetentionDays * 24 * 60 * 60))
            
            // First, get items to be deleted to clean up their files
            let selectTextSQL = """
            SELECT id, physical_filename FROM recently_deleted 
            WHERE deleted_timestamp < ? AND content_type = 0;
            """
            var textSelectStatement: OpaquePointer?
            var itemsToDelete: [(UUID, String?)] = []
            
            if sqlite3_prepare_v2(db, selectTextSQL, -1, &textSelectStatement, nil) == SQLITE_OK {
                sqlite3_bind_double(textSelectStatement, 1, textCutoffDate.timeIntervalSince1970)
                
                while sqlite3_step(textSelectStatement) == SQLITE_ROW {
                    let idString = String(cString: sqlite3_column_text(textSelectStatement, 0))
                    if let uuid = UUID(uuidString: idString) {
                        let physicalFileName = sqlite3_column_text(textSelectStatement, 1) != nil ? 
                            String(cString: sqlite3_column_text(textSelectStatement, 1)) : nil
                        itemsToDelete.append((uuid, physicalFileName))
                    }
                }
            }
            sqlite3_finalize(textSelectStatement)
            
            // Clean up physical files for text items
            for (_, fileName) in itemsToDelete {
                if let fileName = fileName {
                    // Note: We need access to SettingsStore here to delete files
                    // This will be handled by the calling function
                    print("DatabaseManager: Text cleanup - would delete physical file: \(fileName)")
                }
            }
            
            // Now delete the database records
            let deleteTextSQL = """
            DELETE FROM recently_deleted 
            WHERE deleted_timestamp < ? AND content_type = 0;
            """
            var textStatement: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteTextSQL, -1, &textStatement, nil) == SQLITE_OK {
                sqlite3_bind_double(textStatement, 1, textCutoffDate.timeIntervalSince1970)
                sqlite3_step(textStatement)
            }
            sqlite3_finalize(textStatement)
        }
        
        // Handle attachment cleanup if not set to "Never" (-1)
        if attachmentRetentionDays > 0 {
            let attachmentCutoffDate = Date().addingTimeInterval(-Double(attachmentRetentionDays * 24 * 60 * 60))
            
            // First, get attachment items to be deleted to clean up their files
            let selectAttachmentSQL = """
            SELECT id, physical_filename FROM recently_deleted 
            WHERE deleted_timestamp < ? AND (content_type = 1 OR attachment_data IS NOT NULL);
            """
            var attachmentSelectStatement: OpaquePointer?
            var attachmentsToDelete: [(UUID, String?)] = []
            
            if sqlite3_prepare_v2(db, selectAttachmentSQL, -1, &attachmentSelectStatement, nil) == SQLITE_OK {
                sqlite3_bind_double(attachmentSelectStatement, 1, attachmentCutoffDate.timeIntervalSince1970)
                
                while sqlite3_step(attachmentSelectStatement) == SQLITE_ROW {
                    let idString = String(cString: sqlite3_column_text(attachmentSelectStatement, 0))
                    if let uuid = UUID(uuidString: idString) {
                        let physicalFileName = sqlite3_column_text(attachmentSelectStatement, 1) != nil ? 
                            String(cString: sqlite3_column_text(attachmentSelectStatement, 1)) : nil
                        attachmentsToDelete.append((uuid, physicalFileName))
                    }
                }
            }
            sqlite3_finalize(attachmentSelectStatement)
            
            // Clean up physical files for attachments
            for (_, fileName) in attachmentsToDelete {
                if let fileName = fileName {
                    print("DatabaseManager: Attachment cleanup - would delete physical file: \(fileName)")
                }
            }
            
            // Now delete the database records
            let deleteAttachmentSQL = """
            DELETE FROM recently_deleted 
            WHERE deleted_timestamp < ? AND (content_type = 1 OR attachment_data IS NOT NULL);
            """
            var attachmentStatement: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteAttachmentSQL, -1, &attachmentStatement, nil) == SQLITE_OK {
                sqlite3_bind_double(attachmentStatement, 1, attachmentCutoffDate.timeIntervalSince1970)
                sqlite3_step(attachmentStatement)
            }
            sqlite3_finalize(attachmentStatement)
        }
    }
    
    // Legacy method for backward compatibility
    func cleanupOldArchivedItems(retentionDays: Int) {
        let cutoffDate = Date().addingTimeInterval(-Double(retentionDays * 24 * 60 * 60))
        let deleteSQL = "DELETE FROM recently_deleted WHERE deleted_timestamp < ?;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, cutoffDate.timeIntervalSince1970)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }
    
    func cleanupExpiredArchiveAttachments(olderThanDays days: Int, settingsStore: SettingsStore) {
        // This method cleans up old archived attachments
        let cutoffDate = Date().addingTimeInterval(-Double(days * 24 * 60 * 60))
        
        // Mark attachments as deleted for items older than cutoff
        let updateSQL = """
        UPDATE recently_deleted 
        SET attachment_deleted = 1, attachment_deleted_timestamp = julianday('now') 
        WHERE deleted_timestamp < ? AND attachment_deleted = 0;
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, cutoffDate.timeIntervalSince1970)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }
    
    // MARK: - Helper Methods
    
    private func executeSQL(_ sql: String, errorMessage: String) {
        if db == nil {
            print("DatabaseManager: ERROR - db is nil when trying to execute SQL!")
            return
        }
        
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            print("DatabaseManager: \(errorMessage): \(String(cString: sqlite3_errmsg(db)))")
        }
    }
    
    private func createClipboardItemFromRow(statement: OpaquePointer?) -> ClipboardItem? {
        debugLogger.logFunctionEntry()
        
        guard let statement = statement else { 
            debugLogger.log("Statement is nil", level: .error)
            debugLogger.logFunctionExit()
            return nil 
        }
        
        // Safely read UUID string
        guard let idCString = sqlite3_column_text(statement, 0) else {
            debugLogger.log("Failed to read ID from database - null pointer", level: .error)
            debugLogger.logFunctionExit()
            return nil
        }
        
        let idString = String(cString: idCString)
        debugLogger.log("Raw ID string from database: '\(idString)'", level: .debug)
        
        guard let uuid = UUID(uuidString: idString) else { 
            debugLogger.log("Failed to convert '\(idString)' to UUID", level: .error)
            debugLogger.logFunctionExit()
            return nil 
        }
        
        debugLogger.log("Successfully parsed UUID: \(uuid)", level: .debug)
        
        let contentType = sqlite3_column_int(statement, 1)
        debugLogger.log("Content type: \(contentType)", level: .debug)
        
        let content: ClipboardContent
        
        if contentType == 0 { // text
            guard let textCString = sqlite3_column_text(statement, 2) else {
                debugLogger.log("Failed to read text content - null pointer", level: .error)
                debugLogger.logFunctionExit()
                return nil
            }
            let text = String(cString: textCString)
            content = .text(text)
            debugLogger.log("Text content: '\(text.prefix(50))...'", level: .debug)
        } else { // file URL
            guard let urlCString = sqlite3_column_text(statement, 3) else {
                debugLogger.log("Failed to read URL content - null pointer", level: .error)
                debugLogger.logFunctionExit()
                return nil
            }
            let urlString = String(cString: urlCString)
            guard let url = URL(string: urlString) else { 
                debugLogger.log("Failed to parse URL: '\(urlString)'", level: .error)
                debugLogger.logFunctionExit()
                return nil 
            }
            content = .fileURL(url)
            debugLogger.log("File URL content: \(urlString)", level: .debug)
        }
        
        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
        
        // Safely read optional string fields
        let bundleId: String? = {
            guard let cString = sqlite3_column_text(statement, 5) else { return nil }
            return String(cString: cString)
        }()
        
        let appName: String? = {
            guard let cString = sqlite3_column_text(statement, 6) else { return nil }
            return String(cString: cString)
        }()
        
        let isPinned = sqlite3_column_int(statement, 7) == 1
        
        let attachmentData: Data? = {
            let blob = sqlite3_column_blob(statement, 8)
            let size = sqlite3_column_bytes(statement, 8)
            return blob != nil ? Data(bytes: blob!, count: Int(size)) : nil
        }()
        
        let attachmentFilename: String? = {
            guard let cString = sqlite3_column_text(statement, 9) else { return nil }
            return String(cString: cString)
        }()
        
        let attachmentFileExtension: String? = {
            guard let cString = sqlite3_column_text(statement, 10) else { return nil }
            return String(cString: cString)
        }()
        
        let attachmentUTI: String? = {
            guard let cString = sqlite3_column_text(statement, 11) else { return nil }
            return String(cString: cString)
        }()
        
        let physicalFileName: String? = {
            guard let cString = sqlite3_column_text(statement, 12) else { return nil }
            return String(cString: cString)
        }()
        let formattedContent: Data? = {
            guard let blob = sqlite3_column_blob(statement, 13) else { return nil }
            return Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 13)))
        }()
        debugLogger.log("Creating ClipboardItem with all parsed data", level: .debug)
        debugLogger.log("UUID: \(uuid), bundleId: \(bundleId ?? "nil"), appName: \(appName ?? "nil")", level: .debug)
        
        let item = ClipboardItem(
            id: uuid,
            content: content,
            timestamp: timestamp,
            isPinned: isPinned,
            sourceAppBundleIdentifier: bundleId,
            sourceAppName: appName,
            attachmentData: attachmentData,
            isSymlinked: false,
            physicalFileName: physicalFileName,
            attachmentFilename: attachmentFilename,
            attachmentFileExtension: attachmentFileExtension,
            attachmentUTI: attachmentUTI,
            formattedContent: formattedContent
        )
        
        debugLogger.log("Successfully created ClipboardItem with ID: \(item.id)", level: .debug)
        debugLogger.logFunctionExit()
        
        return item
    }
    
    private func createClipboardItemFromDeletedRow(statement: OpaquePointer?) -> ClipboardItem? {
        debugLogger.logFunctionEntry()
        
        guard let statement = statement else { 
            debugLogger.logCrashPrevention("Statement is nil in createClipboardItemFromDeletedRow")
            return nil 
        }
        
        // Read ID
        let idString = String(cString: sqlite3_column_text(statement, 0))
        debugLogger.logDatabaseOperation("Reading row", details: "ID string: \(idString)")
        
        guard let uuid = UUID(uuidString: idString) else { 
            debugLogger.logError(NSError(domain: "DatabaseManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid UUID string: \(idString)"]), context: "createClipboardItemFromDeletedRow")
            return nil 
        }
        
        debugLogger.logDatabaseOperation("UUID parsed successfully", details: "UUID: \(uuid)")
        
        // Read content
        let contentType = sqlite3_column_int(statement, 1)
        debugLogger.logDatabaseOperation("Content type", details: "Type: \(contentType)")
        
        let content: ClipboardContent
        
        if contentType == 0 { // text
            let text = String(cString: sqlite3_column_text(statement, 2))
            content = .text(text)
            debugLogger.logDatabaseOperation("Created text content", details: "Length: \(text.count)")
        } else { // file URL
            let urlString = String(cString: sqlite3_column_text(statement, 3))
            guard let url = URL(string: urlString) else { 
                debugLogger.logError(NSError(domain: "DatabaseManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid URL string: \(urlString)"]), context: "createClipboardItemFromDeletedRow")
                return nil 
            }
            content = .fileURL(url)
            debugLogger.logDatabaseOperation("Created URL content", details: "URL: \(urlString)")
        }
        
        // Read timestamp
        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
        debugLogger.logDatabaseOperation("Timestamp parsed", details: "Date: \(timestamp)")
        
        // Read optional fields
        let bundleId = sqlite3_column_text(statement, 5) != nil ? 
            String(cString: sqlite3_column_text(statement, 5)) : nil
        let appName = sqlite3_column_text(statement, 6) != nil ? 
            String(cString: sqlite3_column_text(statement, 6)) : nil
        
        debugLogger.logDatabaseOperation("App info", details: "Bundle: \(bundleId ?? "nil"), Name: \(appName ?? "nil")")
        
        let wasPinned = sqlite3_column_int(statement, 7) == 1
        
        let attachmentDeleted = sqlite3_column_int(statement, 13) == 1
        
        let attachmentData: Data? = {
            if attachmentDeleted { return nil }
            let blob = sqlite3_column_blob(statement, 8)
            let size = sqlite3_column_bytes(statement, 8)
            return blob != nil ? Data(bytes: blob!, count: Int(size)) : nil
        }()
        
        debugLogger.logDatabaseOperation("Attachment data", details: "Deleted: \(attachmentDeleted), Size: \(attachmentData?.count ?? 0)")
        
        let attachmentFilename = sqlite3_column_text(statement, 9) != nil ? 
            String(cString: sqlite3_column_text(statement, 9)) : nil
        let attachmentFileExtension = sqlite3_column_text(statement, 10) != nil ? 
            String(cString: sqlite3_column_text(statement, 10)) : nil
        let attachmentUTI = sqlite3_column_text(statement, 11) != nil ? 
            String(cString: sqlite3_column_text(statement, 11)) : nil
        let physicalFileName = attachmentDeleted ? nil : (sqlite3_column_text(statement, 12) != nil ? 
            String(cString: sqlite3_column_text(statement, 12)) : nil)
        let formattedContent: Data? = {
            guard let blob = sqlite3_column_blob(statement, 15) else { return nil }
            return Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 15)))
        }()
        
        debugLogger.logDatabaseOperation("Attachment metadata", details: "Filename: \(attachmentFilename ?? "nil"), Extension: \(attachmentFileExtension ?? "nil"), UTI: \(attachmentUTI ?? "nil"), Physical: \(physicalFileName ?? "nil")")
        
        let item = ClipboardItem(
            id: uuid,
            content: content,
            timestamp: timestamp,
            isPinned: wasPinned,
            sourceAppBundleIdentifier: bundleId,
            sourceAppName: appName,
            attachmentData: attachmentData,
            isSymlinked: false,
            physicalFileName: physicalFileName,
            attachmentFilename: attachmentFilename,
            attachmentFileExtension: attachmentFileExtension,
            attachmentUTI: attachmentUTI,
            formattedContent: formattedContent
        )
        
        debugLogger.logDatabaseOperation("ClipboardItem created successfully", details: "ID: \(item.id)")
        debugLogger.logFunctionExit()
        
        return item
    }
    
    func updatePinnedStatus(itemId: UUID, isPinned: Bool) {
        // Keep this update compatible with older databases that may not have `updated_at`.
        let updateSQL = "UPDATE clipboard_history SET is_pinned = ? WHERE id = ?;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, isPinned ? 1 : 0)
            bindString(statement, itemId.uuidString, at: 2)
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                let changedRows = sqlite3_changes(db)
                if changedRows == 0 {
                    print("DatabaseManager: Pin update touched 0 rows for \(itemId). Item not found in clipboard_history?")
                }
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                print("DatabaseManager: Failed to update pinned status for \(itemId): \(errorMessage)")
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("DatabaseManager: Failed to prepare pin update statement: \(errorMessage)")
        }
        sqlite3_finalize(statement)
    }
    
    func unpinAllItems() {
        // Keep this update compatible with older databases that may not have `updated_at`.
        let updateSQL = "UPDATE clipboard_history SET is_pinned = 0;"
        executeSQL(updateSQL, errorMessage: "Failed to unpin all items")
    }
    
    func clearNonPinnedItems() {
        // Move non-pinned items to recently_deleted
        let selectSQL = """
        SELECT id, content_type, content_text, content_url, timestamp, source_app_bundle_id, source_app_name,
               is_pinned, attachment_data, attachment_filename, attachment_file_extension, attachment_uti, physical_filename, formatted_content
        FROM clipboard_history 
        WHERE is_pinned = 0;
        """
        
        var statement: OpaquePointer?
        var itemsToMove: [ClipboardItem] = []
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let item = createClipboardItemFromRow(statement: statement) {
                    itemsToMove.append(item)
                }
            }
        }
        sqlite3_finalize(statement)
        
        // Move items to recently_deleted
        for item in itemsToMove {
            moveToRecentlyDeleted(item)
        }
        
        // Delete from main table
        let deleteSQL = "DELETE FROM clipboard_history WHERE is_pinned = 0;"
        executeSQL(deleteSQL, errorMessage: "Failed to clear non-pinned items")
        
        print("DatabaseManager: Moved \(itemsToMove.count) non-pinned items to archive")
    }
    
    func clearAllItems() {
        // Move all items to recently_deleted
        let allItems = loadAllClipboardItems(includeBlobs: true)
        
        for item in allItems {
            moveToRecentlyDeleted(item)
        }
        
        // Clear main table
        let deleteSQL = "DELETE FROM clipboard_history;"
        executeSQL(deleteSQL, errorMessage: "Failed to clear all items")
        
        print("DatabaseManager: Moved \(allItems.count) items to archive")
    }
}
