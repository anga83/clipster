import SwiftUI

/// Simple and robust view for managing archived (recently deleted) clipboard items
struct ArchiveView: View {
    @EnvironmentObject var historyStore: ClipboardHistoryStore
    @EnvironmentObject var settingsStore: SettingsStore
    
    @State private var archivedItems: [ClipboardItem] = []
    @State private var searchText: String = ""
    @State private var selectedItems: Set<UUID> = []
    @State private var showingPermanentDeleteAlert = false
    @State private var showingRestoreAlert = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showingError = false
    
    private let debugLogger = DebugLogger.shared
    
    private var filteredItems: [ClipboardItem] {
        if searchText.isEmpty {
            return archivedItems
        }
        
        let lowercasedQuery = searchText.lowercased()
        return archivedItems.filter { item in
            switch item.content {
            case .text(let content):
                return content.lowercased().contains(lowercasedQuery)
            case .fileURL(let url):
                return url.path.lowercased().contains(lowercasedQuery) || 
                       url.lastPathComponent.lowercased().contains(lowercasedQuery)
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            settingsSection
            
            if isLoading {
                loadingView
            } else if archivedItems.isEmpty {
                emptyStateView
            } else {
                searchBarView
                itemsSection
            }
        }
        .padding(20)
        .onAppear {
            debugLogger.logFunctionEntry()
            debugLogger.logArchiveOperation("ArchiveView appeared", details: "Starting initial load")
            loadArchivedItems()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { 
                errorMessage = nil 
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .alert("Restore Items", isPresented: $showingRestoreAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Restore") {
                restoreSelectedItems()
            }
        } message: {
            Text("Restore \(selectedItems.count) item(s) from archive?")
        }
        .alert("Permanent Delete", isPresented: $showingPermanentDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Permanently", role: .destructive) {
                permanentlyDeleteSelectedItems()
            }
        } message: {
            Text("Permanently delete \(selectedItems.count) item(s)? This cannot be undone.")
        }
    }
    
    private var searchBarView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search archived items...", text: $searchText)
                .textFieldStyle(.roundedBorder)
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Archive")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Manage items that have been deleted from your clipboard history.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Text Clips Retention:")
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $settingsStore.archiveTextRetentionDays) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("1 year").tag(365)
                        Text("Never").tag(-1)
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(maxWidth: 150)
                    
                    Spacer()
                }
                
                HStack {
                    Text("File Attachments Retention:")
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $settingsStore.archiveAttachmentRetentionDays) {
                        Text("1 day").tag(1)
                        Text("3 days").tag(3)
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("180 days").tag(180)
                        Text("1 year").tag(365)
                        Text("Never").tag(-1)
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(maxWidth: 150)
                    
                    Spacer()
                }
            }
            
            HStack {
                Spacer()
                Button("Clean Up Now") {
                    cleanupOldItems()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var loadingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading archived items...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "archivebox")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Archived Items")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("Items you delete from your clipboard history will appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if searchText.isEmpty {
                    Text("\(archivedItems.count) Archived Items")
                        .font(.headline)
                } else {
                    Text("\(filteredItems.count) of \(archivedItems.count) Archived Items")
                        .font(.headline)
                }
                
                Spacer()
                
                if !selectedItems.isEmpty {
                    Button("Restore Selected") {
                        showingRestoreAlert = true
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Delete Permanently") {
                        showingPermanentDeleteAlert = true
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
                
                Button("Refresh") {
                    loadArchivedItems()
                }
                .buttonStyle(.bordered)
            }
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredItems.indices, id: \.self) { index in
                        if index < filteredItems.count {
                            archiveItemRow(filteredItems[index])
                        }
                    }
                }
            }
            .frame(maxHeight: 400)
        }
    }
    
    private func archiveItemRow(_ item: ClipboardItem) -> some View {
        HStack(spacing: 12) {
            Button(action: {
                toggleSelection(item.id)
            }) {
                Image(systemName: selectedItems.contains(item.id) ? "checkmark.square.fill" : "square")
                    .foregroundColor(selectedItems.contains(item.id) ? .accentColor : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 4) {
                switch item.content {
                case .text(let text):
                    Text(text.isEmpty ? "[Empty Text]" : text)
                        .lineLimit(2)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(text.isEmpty ? .secondary : .primary)
                case .fileURL(let url):
                    Text(url.lastPathComponent.isEmpty ? "[Unknown File]" : url.lastPathComponent)
                        .font(.body)
                        .foregroundColor(.blue)
                }
                
                Text("Deleted: \(item.timestamp, formatter: dateFormatter)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Restore") {
                restoreItem(item.id)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(8)
        .background(selectedItems.contains(item.id) ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .onTapGesture {
            toggleSelection(item.id)
        }
    }
    
    private func toggleSelection(_ itemId: UUID) {
        if selectedItems.contains(itemId) {
            selectedItems.remove(itemId)
        } else {
            selectedItems.insert(itemId)
        }
    }
    
    private func loadArchivedItems() {
        debugLogger.logFunctionEntry()
        debugLogger.logArchiveOperation("Starting loadArchivedItems", details: "Current state - Loading: \(isLoading), Items: \(archivedItems.count)")
        
        isLoading = true
        errorMessage = nil
        
        debugLogger.logArchiveOperation("Loading state set", details: "isLoading = true, errorMessage cleared")
        
        Task {
            debugLogger.logArchiveOperation("Task started", details: "About to call historyStore.getArchivedItems()")
            
            let items = await MainActor.run {
                debugLogger.logArchiveOperation("MainActor.run started", details: "Calling historyStore.getArchivedItems()")
                
                let result = historyStore.getArchivedItems()
                debugLogger.logArchiveOperation("getArchivedItems completed", details: "Returned \(result.count) items")
                return result
            }
            
            debugLogger.logArchiveOperation("Items loaded", details: "Got \(items.count) items from historyStore")
            
            await MainActor.run {
                debugLogger.logArchiveOperation("Updating UI state", details: "Setting \(items.count) items, clearing selection")
                
                self.archivedItems = items
                self.selectedItems.removeAll()
                self.isLoading = false
                
                debugLogger.logArchiveOperation("UI state updated", details: "Final state - Items: \(self.archivedItems.count), Loading: \(self.isLoading)")
            }
        }
        
        debugLogger.logFunctionExit()
    }
    
    private func restoreItem(_ itemId: UUID) {
        guard !itemId.uuidString.isEmpty else {
            errorMessage = "Invalid item ID"
            showingError = true
            return
        }
        
        historyStore.restoreFromArchive(itemId)
        loadArchivedItems()
    }
    
    private func restoreSelectedItems() {
        guard !selectedItems.isEmpty else {
            errorMessage = "No items selected"
            showingError = true
            return
        }
        
        for itemId in selectedItems {
            historyStore.restoreFromArchive(itemId)
        }
        loadArchivedItems()
    }
    
    private func permanentlyDeleteSelectedItems() {
        guard !selectedItems.isEmpty else {
            errorMessage = "No items selected"
            showingError = true
            return
        }
        
        for itemId in selectedItems {
            historyStore.permanentlyDeleteFromArchive(itemId, settingsStore: settingsStore)
        }
        loadArchivedItems()
    }
    
    private func cleanupOldItems() {
        historyStore.cleanupOldArchivedItems(
            textRetentionDays: settingsStore.archiveTextRetentionDays,
            attachmentRetentionDays: settingsStore.archiveAttachmentRetentionDays,
            settingsStore: settingsStore
        )
        loadArchivedItems()
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}
