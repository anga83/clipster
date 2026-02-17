import SwiftUI
import QuickLook

/// A view that displays a single row in the clipboard history list.
struct ClipboardItemRowView: View {
    let item: ClipboardItem
    let deleteAction: () -> Void
    let isSelectionMode: Bool
    let isSelected: Bool
    let onSelectionToggle: () -> Void
    
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var historyStore: ClipboardHistoryStore

    @State private var isHovering = false
    @State private var quickLookURL: URL?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Selection button (only shown in selection mode)
            if isSelectionMode {
                Button(action: onSelectionToggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                switch item.content {
                case .text(let text):
                    Text(text)
                        .lineLimit(2)
                        .font(.body)
                case .fileURL(let url):
                    HStack {
                        if item.isSymlinked {
                            Image(systemName: "link")
                                .foregroundColor(.primary)
                        } else if item.hasFileData {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.primary)
                        } else {
                            Image(systemName: "doc")
                        }
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.body)
                    }
                }

                HStack {
                    // We can use the bundle ID later to fetch the actual app icon.
                    Image(systemName: "app.badge")
                    Text(item.sourceAppName ?? "Unknown App")
                    Text("•")
                    Text(Self.timeFormatter.string(from: item.timestamp))
                    if item.hasFileData || item.isSymlinked {
                        Text("•")
                        if item.isSymlinked {
                            Image(systemName: "link")
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "paperclip")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            // Pin Icon
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(10)
        .background(isHovering ? Color.primary.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .onHover { hovering in
            isHovering = hovering
        }
        .contentShape(Rectangle())
        .onTapGesture {
            print("🔴 DEBUG: Item tapped - ID: \(item.id)")
            copyItemToClipboard()
        }
        .contextMenu {
            contextMenuItems()
        }
        .quickLookPreview($quickLookURL)
    }

    @ViewBuilder
    private func contextMenuItems() -> some View {
        Button("Copy", action: {
            print("🔴 DEBUG: Copy button tapped")
            copyItemToClipboard()
        })
        .keyboardShortcut("c", modifiers: .command)

        if case .fileURL(let url) = item.content {
            Button("Quick Look") {
                print("🔴 DEBUG: Quick Look button tapped")
                previewInQuickLook(url: url)
            }
            .keyboardShortcut(.space)

            Button("Open") {
                print("🔴 DEBUG: Open button tapped")
                NSWorkspace.shared.open(url)
            }
            .keyboardShortcut(.return, modifiers: [])
        }

        Divider()

        Button(item.isPinned ? "Unpin" : "Pin") {
            print("🔴 DEBUG: Pin/Unpin button tapped, current state: \(item.isPinned)")
            historyStore.togglePin(for: item)
        }
        .keyboardShortcut("p", modifiers: .command)

        Button("Delete", role: .destructive, action: {
            print("🔴 DEBUG: Delete button tapped")
            deleteAction()
        })
        .keyboardShortcut(.delete, modifiers: [])
    }

    private func copyItemToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.content {
        case .text(let string):
            pasteboard.setString(string, forType: .string)
        case .fileURL(let url):
            pasteboard.writeObjects([url as NSURL])
        }

        NotificationCenter.default.post(
            name: .clipsterDidWritePasteboard,
            object: nil,
            userInfo: ["changeCount": pasteboard.changeCount]
        )
    }
    
    private func createTemporaryFileProvider(url: URL, data: Data) -> NSItemProvider {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        
        do {
            try data.write(to: tempURL)
            return NSItemProvider(object: tempURL as NSURL)
        } catch {
            // Fallback to text representation if file creation fails
            return NSItemProvider(object: url.path as NSString)
        }
    }
    
    private func previewInQuickLook(url: URL) {
        var previewURL = url
        
        // If we have file data (physical or inline), create a temporary file for QuickLook
        if let fileData = item.getFileData(using: settingsStore) {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            do {
                try fileData.write(to: tempURL)
                previewURL = tempURL
            } catch {
                print("Error creating temporary file for QuickLook: \(error)")
            }
        }
        
        quickLookURL = previewURL
    }
    
    private func createFileProviderForSymlink(url: URL) -> NSItemProvider {
        // For symlinked files, we want to copy the actual file content, not move the original
        // Check if the file exists at the symlinked path
        guard FileManager.default.fileExists(atPath: url.path) else {
            // If file doesn't exist, fallback to text representation
            return NSItemProvider(object: "File not found: \(url.path)" as NSString)
        }
        
        // Read the file data and create a temporary copy for drag & drop
        do {
            let fileData = try Data(contentsOf: url)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try fileData.write(to: tempURL)
            
            // Return the temporary file URL - this will be copied, not moved
            return NSItemProvider(object: tempURL as NSURL)
        } catch {
            print("Error creating file provider for symlink: \(error)")
            // Fallback to text representation
            return NSItemProvider(object: "Error reading symlinked file: \(url.lastPathComponent)" as NSString)
        }
    }
}
