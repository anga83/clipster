import AppKit
import Carbon
import UserNotifications

/// A service that handles global keyboard shortcuts for Clipster.
class GlobalShortcutService {
    private let historyStore: ClipboardHistoryStore
    private let settingsStore: SettingsStore
    private var eventHandler: EventHandlerRef?
    private let pasteboard = NSPasteboard.general
    
    // Shortcut: Option + Cmd + V
    private let shortcutKeyCode: UInt32 = 9 // 'V' key
    private let shortcutModifiers: UInt32 = UInt32(optionKey | cmdKey)
    
    init(historyStore: ClipboardHistoryStore, settingsStore: SettingsStore) {
        self.historyStore = historyStore
        self.settingsStore = settingsStore
    }
    
    /// Starts monitoring for global keyboard shortcuts.
    func startMonitoring() {
        // Check if the shortcut is already in use by another app
        guard !isShortcutInUse() else {
            print("⚠️ Global shortcut Option+Cmd+V is already in use by another application")
            return
        }
        
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let hotKeyID = EventHotKeyID(signature: fourCharCodeFrom("CLPS"), id: 1)
        
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcutKeyCode,
            shortcutModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status != noErr {
            print("❌ Failed to register global shortcut: \(status)")
            return
        }
        
        // Install event handler
        let callback: EventHandlerUPP = { (_, event, userData) -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let service = Unmanaged<GlobalShortcutService>.fromOpaque(userData).takeUnretainedValue()
            service.handleShortcut()
            return noErr
        }
        
        let status2 = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        
        if status2 == noErr {
            print("✅ Global shortcut Option+Cmd+V registered successfully")
        } else {
            print("❌ Failed to install event handler: \(status2)")
        }
    }
    
    /// Stops monitoring for global keyboard shortcuts.
    func stopMonitoring() {
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
            print("✅ Global shortcut unregistered")
        }
    }
    
    /// Handles the global shortcut when pressed.
    private func handleShortcut() {
        // Force capture current clipboard content, ignoring blacklist
        captureCurrentClipboard()
    }
    
    /// Captures the current clipboard content, bypassing blacklist restrictions.
    private func captureCurrentClipboard() {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let sourceID = frontmostApp?.bundleIdentifier
        let sourceName = frontmostApp?.localizedName
        var newItem: ClipboardItem?
        
        // Prioritize file URLs, then fall back to strings.
        if let fileURL = pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL, fileURL.isFileURL {
            var attachmentData: Data?
            var isSymlinked = false
            var physicalFileName: String?
            
            // Check for special file type treatment
            if let specialTreatment = settingsStore.shouldApplySpecialTreatment(for: fileURL) {
                switch specialTreatment {
                case .saveNever:
                    // For manual capture, we'll still save it but note the restriction
                    print("ℹ️ Manually capturing file type that would normally be skipped: \(fileURL.pathExtension)")
                case .alwaysSymlink:
                    // Always symlink, regardless of size
                    isSymlinked = true
                }
            }
            
            // Apply normal size-based logic if not force-symlinked
            if !isSymlinked {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let fileSize = attributes[.size] as? NSNumber {
                    
                    let fileSizeBytes = fileSize.intValue
                    let limitBytes = settingsStore.getFileSizeLimitInBytes()
                    
                    if fileSizeBytes <= limitBytes {
                        // File is within limit - either save physically or as base64
                        if let fileData = try? Data(contentsOf: fileURL) {
                            if settingsStore.usePhysicalFileStorage {
                                // Save physically and store filename
                                let itemID = UUID()
                                physicalFileName = settingsStore.saveFilePhysically(fileData, originalURL: fileURL, for: itemID)
                                // Create item with the predetermined ID
                                newItem = ClipboardItem(id: itemID, content: .fileURL(fileURL), sourceAppBundleIdentifier: sourceID, sourceAppName: sourceName, attachmentData: nil, isSymlinked: false, physicalFileName: physicalFileName)
                            } else {
                                // Save as base64 in JSON
                                attachmentData = fileData
                            }
                        }
                    } else if settingsStore.symlinkLargeFiles {
                        // File is too large but user wants symlinks
                        isSymlinked = true
                    }
                }
            }
            
            // Create item if not already created above
            if newItem == nil {
                newItem = ClipboardItem(content: .fileURL(fileURL), sourceAppBundleIdentifier: sourceID, sourceAppName: sourceName, attachmentData: attachmentData, isSymlinked: isSymlinked, physicalFileName: physicalFileName)
            }
            
        } else if let copiedString = pasteboard.string(forType: .string), !copiedString.isEmpty {
            newItem = ClipboardItem(content: .text(copiedString), sourceAppBundleIdentifier: sourceID, sourceAppName: sourceName)
        }
        
        // Add item to history store on main thread
        if let item = newItem {
            DispatchQueue.main.async {
                self.historyStore.addItem(item)
                
                // Show brief notification
                self.showCaptureNotification(sourceApp: sourceName ?? "Unknown App")
            }
        }
    }
    
    /// Shows a brief notification that content was manually captured.
    private func showCaptureNotification(sourceApp: String) {
        // Use modern UserNotifications framework
        let content = UNMutableNotificationContent()
        content.title = "Clipster"
        content.body = "Manually captured clipboard from \(sourceApp)"
        content.sound = nil // Silent notification
        
        let request = UNNotificationRequest(
            identifier: "manual-capture-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error showing notification: \(error)")
            }
        }
    }
    
    /// Checks if the shortcut combination is already in use by another application.
    private func isShortcutInUse() -> Bool {
        // This is a simplified check - in a real implementation, you might want to
        // check the system's shortcut registry more thoroughly
        return false
    }
    
    /// Helper function to create a four character code from a string.
    private func fourCharCodeFrom(_ string: String) -> FourCharCode {
        let data = string.data(using: .ascii) ?? Data()
        return data.withUnsafeBytes { bytes in
            guard bytes.count >= 4 else { return 0 }
            return bytes.load(as: FourCharCode.self)
        }
    }
}
