import Foundation
import os.log

/// Comprehensive debug logging system for Clipster
class DebugLogger {
    static let shared = DebugLogger()
    
    private let logger = Logger(subsystem: "com.yourcompany.clipster", category: "Debug")
    
    enum LogLevel: Int, Comparable {
        case debug = 0, info = 1, warning = 2, error = 3, critical = 4
        
        static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
        
        var prefix: String {
            switch self {
            case .debug: return "🐛 DEBUG"
            case .info: return "ℹ️  INFO"
            case .warning: return "⚠️  WARNING"
            case .error: return "❌ ERROR"
            case .critical: return "🚨 CRITICAL"
            }
        }
    }
    
    // Minimum level to actually emit logs to the console / os logger
    // Keep it higher by default to avoid flooding the console (especially on first load)
    private let minLevel: LogLevel = {
        #if DEBUG
        return .warning
        #else
        return .error
        #endif
    }()
    
    private init() {}
    
    func log(_ message: String, level: LogLevel = .debug, file: String = #fileID, function: String = #function, line: Int = #line) {
        guard level >= minLevel else { return }
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let timestamp = DateFormatter.debugFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] \(level.prefix) [\(fileName):\(line)] \(function) - \(message)"
        
        print(logMessage)
        
        switch level {
        case .debug:
            logger.debug("\(logMessage)")
        case .info:
            logger.info("\(logMessage)")
        case .warning:
            logger.warning("\(logMessage)")
        case .error:
            logger.error("\(logMessage)")
        case .critical:
            logger.critical("\(logMessage)")
        }
    }
    
    func logFunctionEntry(file: String = #fileID, function: String = #function, line: Int = #line) {
        log("🔹 ENTER", level: .debug, file: file, function: function, line: line)
    }
    
    func logFunctionExit(file: String = #fileID, function: String = #function, line: Int = #line) {
        log("🔸 EXIT", level: .debug, file: file, function: function, line: line)
    }
    
    func logError(_ error: Error, context: String = "", file: String = #fileID, function: String = #function, line: Int = #line) {
        log("💥 ERROR in \(context): \(error.localizedDescription)", level: .error, file: file, function: function, line: line)
    }
    
    func logCrashPrevention(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log("🛡️ CRASH PREVENTION: \(message)", level: .critical, file: file, function: function, line: line)
    }
    
    func logArchiveOperation(_ operation: String, details: String = "", file: String = #fileID, function: String = #function, line: Int = #line) {
        log("📦 ARCHIVE: \(operation) - \(details)", level: .info, file: file, function: function, line: line)
    }
    
    func logDatabaseOperation(_ operation: String, details: String = "", file: String = #fileID, function: String = #function, line: Int = #line) {
        log("🗄️ DATABASE: \(operation) - \(details)", level: .info, file: file, function: function, line: line)
    }
}

extension DateFormatter {
    static let debugFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
