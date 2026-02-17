import AppKit // For NSPasteboard and NSWorkspace
import Combine

/// A service that monitors the system clipboard for changes.
class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private let historyStore: ClipboardHistoryStore
    private let settingsStore: SettingsStore
    // Use a GCD timer on a background queue to avoid blocking the main thread (Sequoia compatibility)
    private var timer: DispatchSourceTimer?
    private let monitorQueue = DispatchQueue(label: "clipster.clipboard.monitor", qos: .userInitiated)
    private var lastChangeCount: Int

    init(historyStore: ClipboardHistoryStore, settingsStore: SettingsStore) {
        self.historyStore = historyStore
        self.settingsStore = settingsStore
        self.lastChangeCount = pasteboard.changeCount
    }

    /// Starts monitoring the clipboard for new clipboard content.
    func startMonitoring() {
        // Create a background timer; Sequoia is stricter about long work on main thread
        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(350), leeway: .milliseconds(150))
        timer.setEventHandler { [weak self] in
            self?.checkForChanges()
        }
        timer.resume()
        self.timer = timer
    }

    /// Stops the monitoring timer.
    func stopMonitoring() {
        timer?.cancel()
        timer = nil
    }

    private func checkForChanges() {
        // Avoid mutating the data source while the initial list is being built/rendered
        let initialLoadDone: Bool = DispatchQueue.main.sync { historyStore.isInitialLoadComplete }
        if !initialLoadDone {
            return
        }

        // Read the pasteboard changeCount on the main thread (API is UI-related)
        let currentChangeCount: Int = DispatchQueue.main.sync { pasteboard.changeCount }
        guard currentChangeCount != lastChangeCount else { return }

        lastChangeCount = currentChangeCount
        print("ClipboardMonitor: Clipboard change detected (changeCount: \(currentChangeCount))")

        // Capture frontmost app info on main thread to avoid API misuse
        let (capturedSourceID, capturedSourceName): (String?, String?) = DispatchQueue.main.sync {
            let app = NSWorkspace.shared.frontmostApplication
            return (app?.bundleIdentifier, app?.localizedName)
        }
        print("ClipboardMonitor: Source app: \(capturedSourceName ?? "Unknown") (\(capturedSourceID ?? "no bundle ID"))")

        // Create a combined blacklist with our own app and user-defined apps.
        var blacklist = settingsStore.blacklistedAppIdentifiers
        if let ownIdentifier = Bundle.main.bundleIdentifier {
            blacklist.append(ownIdentifier)
        }
        guard let bundleID = capturedSourceID, !blacklist.contains(bundleID) else { 
            print("ClipboardMonitor: App is blacklisted, ignoring")
            return 
        }

        let sourceID = capturedSourceID
        let sourceName = capturedSourceName
        var newItem: ClipboardItem?

        // Prioritize file URLs, then fall back to strings.
        // Read pasteboard snapshot (URL or string) on main thread only, processing off main
        let (maybeFileURL, maybeString): (URL?, String?) = DispatchQueue.main.sync {
            let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
            let url = urls?.first(where: { $0.isFileURL })
            let str = pasteboard.string(forType: .string)
            return (url, str)
        }

        if let fileURL = maybeFileURL {
            var attachmentData: Data?
            var isSymlinked = false
            var physicalFileName: String?
            
            // Check for special file type treatment
            if let specialTreatment = settingsStore.shouldApplySpecialTreatment(for: fileURL) {
                switch specialTreatment {
                case .saveNever:
                    // Skip this file type entirely
                    return
                case .alwaysSymlink:
                    // Always symlink, regardless of size
                    isSymlinked = true
                }
            } else {
                // Apply normal size-based logic
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

        } else if let copiedString = maybeString, !copiedString.isEmpty {
            print("ClipboardMonitor: Found text content: '\(copiedString.prefix(50))...'")
            
            // Check if text meets minimum length requirement
            if copiedString.count >= settingsStore.minTextLength {
                newItem = ClipboardItem(content: .text(copiedString), sourceAppBundleIdentifier: sourceID, sourceAppName: sourceName)
            } else {
                print("ClipboardMonitor: Text too short (\(copiedString.count) chars, minimum: \(settingsStore.minTextLength)), skipping")
            }
        } else {
            print("ClipboardMonitor: No supported content found on pasteboard")
        }


        // The history store is an ObservableObject, so we must update it on the main thread.
        if let item = newItem {
            print("ClipboardMonitor: Adding item to history store")
            DispatchQueue.main.async {
                self.historyStore.addItem(item)
            }
        }
    }
}