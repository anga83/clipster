import SwiftUI

/// The main view for the Clipster application window.
struct ContentView: View {
    // Access the shared history store from the environment.
    @EnvironmentObject var historyStore: ClipboardHistoryStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    /// Determines if the view is in a popover, which affects UI elements like the settings menu.
    let isPopover: Bool

    @State private var isShowingClearAlert: Bool    = false
    @State private var isShowingClearOptions: Bool = false
    @State private var searchText: String           = ""
    @State private var selectedSourceApp: String?
    @State private var isSelectionMode: Bool        = false
    @State private var selectedItems: Set<UUID>     = []
    @State private var lastSelectedItem: UUID?      = nil

    // Limit the number of items shown in the Menu Bar popover for responsiveness
    private let popoverMaxItems = 100

    // Base items used for filtering/grouping depending on context
    private var baseItems: [ClipboardItem] {
        if isPopover {
            // Use the most recent items only (items are already loaded newest-first from DB)
            return Array(historyStore.items.prefix(popoverMaxItems))
        }
        return historyStore.items
    }

    private var filteredItems: [ClipboardItem] {
    // When searching, query the full history from DB to include older items
    if !searchText.isEmpty {
        let results = historyStore.searchAllHistory(searchText, sourceAppName: selectedSourceApp)
        return results.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.timestamp > b.timestamp
        }
    }
    var items = baseItems

        // 1. Filter by source app if one is selected
        if let selectedApp = selectedSourceApp {
            items = items.filter { $0.sourceAppName == selectedApp }
        }

        // 2. No in-memory search here; handled above via DB-backed search
        
        // 3. Sort results: pinned items first, then by timestamp (newest first)
        return items.sorted { first, second in
            if first.isPinned != second.isPinned {
                return first.isPinned // Pinned items come first
            }
            return first.timestamp > second.timestamp // Newest first within same pinned state
        }
    }

    private var sourceApps: [String] {
    let allApps = baseItems.compactMap { $0.sourceAppName }
        return Array(Set(allApps)).sorted()
    }

    private var groupedItems: [(title: String, items: [ClipboardItem])] {
        let calendar = Calendar.current
        let now = Date()
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"

    let groups = Dictionary(grouping: baseItems) { item -> String in
            if calendar.isDateInToday(item.timestamp) {
                return "Today"
            }
            if calendar.isDate(item.timestamp, equalTo: now, toGranularity: .weekOfYear) {
                return "This Week"
            }
            if calendar.isDate(item.timestamp, equalTo: now, toGranularity: .month) {
                return "This Month"
            }
            return monthFormatter.string(from: item.timestamp)
        }

        let sectionOrder = ["Today", "This Week", "This Month"]
        let sortedMonthKeys = groups.keys
            .filter { !sectionOrder.contains($0) }
            .sorted {
                guard let d1 = monthFormatter.date(from: $0), let d2 = monthFormatter.date(from: $1) else {
                    return false
                }
                return d1 > d2
            }

        let finalOrder = sectionOrder + sortedMonthKeys

        return finalOrder.compactMap { key in
            guard let items = groups[key] else { return nil }
            // Sort items within each group: pinned items first, then by timestamp (newest first)
            let sortedItems = items.sorted { first, second in
                if first.isPinned != second.isPinned {
                    return first.isPinned // Pinned items come first
                }
                return first.timestamp > second.timestamp // Newest first within same pinned state
            }
            return (title: key, items: sortedItems)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBarView
            mainListView
            footerView
        }
        .frame(minWidth: 480, minHeight: isPopover ? 500 : 400)
        .searchable(text: $searchText, prompt: "Search History")
        .sheet(isPresented: $isShowingClearOptions) {
            ClearHistoryOptionsView(historyStore: historyStore, settingsStore: settingsStore)
                .presentationDetents([.height(520), .large])
                .presentationDragIndicator(.visible)
        }
        .toolbar {
            if !isPopover {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { historyStore.importHistory(settingsStore: settingsStore) }) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .help("Import history from a backup file")
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { historyStore.exportHistory(settingsStore: settingsStore) }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .help("Export a full backup (database, settings, attachments)")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: { isShowingClearOptions = true }) {
                        Label("Clear History", systemImage: "trash")
                    }
                    .help("Clear clipboard history with options")
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { toggleSelectionMode() }) {
                        if isSelectionMode {
                            Label("Cancel Selection", systemImage: "xmark.circle.fill")
                        } else {
                            Label("Select Items", systemImage: "checkmark.circle")
                        }
                    }
                    .foregroundColor(isSelectionMode ? .red : .accentColor)
                    .help(isSelectionMode ? "Exit selection mode" : "Select multiple items")
                }
            }
            
            // Selection Mode Toolbar
            if isSelectionMode && !isPopover {
                ToolbarItem(placement: .status) {
                    HStack {
                        Button(selectedItems.count == filteredItems.count ? "Deselect All" : "Select All") {
                            if selectedItems.count == filteredItems.count {
                                selectedItems.removeAll()
                            } else {
                                selectedItems = Set(filteredItems.map { $0.id })
                            }
                        }
                        .disabled(filteredItems.isEmpty)
                        
                        Spacer()
                        
                        Text("\(selectedItems.count) of \(filteredItems.count) selected")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        Spacer()
                        
                        Button("Delete Selected", role: .destructive) {
                            deleteSelectedItems()
                        }
                        .disabled(selectedItems.isEmpty)
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    filterMenuItem(title: "All Apps", value: nil)

                    if !sourceApps.isEmpty {
                        Divider()
                        ForEach(sourceApps, id: \.self) { appName in
                            filterMenuItem(title: appName, value: appName)
                        }
                    }
                } label: {
                    Label("Filter by App", systemImage: "line.3.horizontal.decrease.circle")
                        .symbolVariant(selectedSourceApp == nil ? .none : .fill)
                }
                .help(selectedSourceApp == nil ? "Filter by source app" : "Filtering by: \(selectedSourceApp!)")
            }
        }
    }
    
    @ViewBuilder
    private var searchBarView: some View {
        if isPopover {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search History", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.bar.opacity(0.3))
        }
    }
    
    @ViewBuilder
    private var mainListView: some View {
        Group {
            if isPopover {
                // Use ScrollView + LazyVStack in menu bar to avoid NSTableView reentrancy and heavy list overhead
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        if searchText.isEmpty && selectedSourceApp == nil {
                            ForEach(groupedItems, id: \.title) { group in
                                Text(group.title)
                                    .font(.headline)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 10)
                                ForEach(group.items) { item in
                                    itemRowView(for: item)
                                        .padding(.horizontal, 6)
                                }
                            }
                        } else {
                            Text("Results (\(filteredItems.count))")
                                .font(.headline)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 10)
                            ForEach(filteredItems) { item in
                                itemRowView(for: item)
                                    .padding(.horizontal, 6)
                            }
                        }
                    }
                }
            } else {
                List {
                    if searchText.isEmpty && selectedSourceApp == nil {
                        ForEach(groupedItems, id: \.title) { group in
                            Section(header: Text(group.title).font(.headline).padding(.vertical, 4)) {
                                ForEach(group.items) { item in
                                    itemRowView(for: item)
                                }
                            }
                        }
                    } else {
                        Section(header: Text("Results (\(filteredItems.count))").font(.headline).padding(.vertical, 4)) {
                            ForEach(filteredItems) { item in
                                itemRowView(for: item)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                // Disable implicit animations to avoid NSTableView reentrant delegate warnings on macOS Sequoia
                .transaction { txn in txn.animation = nil }
            }
        }
        .overlay { emptyStateView }
    }
    
    @ViewBuilder
    private func itemRowView(for item: ClipboardItem) -> some View {
        // Quiet debug: removed noisy per-row print that flooded the console
        ClipboardItemRowView(
            item: item,
            deleteAction: {
                // Perform deletion without implicit list animations to avoid reentrancy
                historyStore.removeItemAndCleanup(item, settingsStore: settingsStore)
            },
            isSelectionMode: isSelectionMode,
            isSelected: selectedItems.contains(item.id),
            onSelectionToggle: {
                handleItemSelection(item.id)
            }
        )
        .id(item.id)
    }
    
    @ViewBuilder
    private var footerView: some View {
        if isPopover {
            footer
        }
    }

    /// A helper function to create a consistent menu item for the filter menu.
    @ViewBuilder
    private func filterMenuItem(title: String, value: String?) -> some View {
        Button(action: { selectedSourceApp = value }) {
            // Using Label with an explicit icon view ensures text alignment
            // is consistent whether the checkmark is present or not.
            Label {
                Text(title)
            } icon: {
                if selectedSourceApp == value {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    /// The view to display when no items match the current search or filter.
    @ViewBuilder
    private var emptyStateView: some View {
        if (!searchText.isEmpty || selectedSourceApp != nil) && filteredItems.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                Text(noResultsMessage)
                    .font(.headline)
            }
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Provides a descriptive message for why no results are being shown.
    private var noResultsMessage: String {
        switch (searchText.isEmpty, selectedSourceApp) {
        case (false, .some(let app)):
            return "No results for \"\(searchText)\" in \(app)"
        case (false, .none):
            return "No results for \"\(searchText)\" found"
        case (true, .some(let app)):
            return "No items found from \(app)"
        case (true, .none):
            // This case should not be reachable given the display logic.
            return "No Items Found"
        }
    }

    private var footer: some View {
        HStack {
            if isSelectionMode {
                // Selection mode footer
                HStack(spacing: 12) {
                    Button(selectedItems.count == filteredItems.count ? "Deselect All" : "Select All") {
                        if selectedItems.count == filteredItems.count {
                            selectedItems.removeAll()
                        } else {
                            selectedItems = Set(filteredItems.map { $0.id })
                        }
                    }
                    .disabled(filteredItems.isEmpty)
                    .font(.caption)
                    
                    Text("\(selectedItems.count) of \(filteredItems.count) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Delete Selected", role: .destructive) {
                        deleteSelectedItems()
                    }
                    .disabled(selectedItems.isEmpty)
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                }
            } else {
                // Normal footer - call existing footer content
                normalFooterMenu
            }
        }
    }
    
    private var normalFooterMenu: some View {
        HStack {
            Text("\(historyStore.totalItemCount) items")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Menu {
                Button("Open Main Window") {
                    openMainWindowFromPopoverMenu()
                }
                Button("Clear History...") {
                    isShowingClearOptions = true
                }
                Divider()
                Button("Import History...") {
                    historyStore.importHistory(settingsStore: settingsStore)
                }
                Button("Export History...") {
                    startExportHistory()
                }
                Divider()
                Button("Quit Clipster", role: .destructive) {
                    NSApp.terminate(nil)
                }
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar.opacity(0.5))
    }
}

// MARK: - Selection Mode Functions

extension ContentView {
    private func openMainWindowFromPopoverMenu() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main-window")
        NSApp.activate(ignoringOtherApps: true)

        if isPopover {
            // Keep the old behavior from v2.3: open window first, then close the menu popover.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                for window in NSApp.windows where window.className.contains("MenuBarExtra") {
                    window.close()
                }
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func startExportHistory() {
        if isPopover {
            closePopoverIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                historyStore.exportHistory(settingsStore: settingsStore)
            }
            return
        }

        historyStore.exportHistory(settingsStore: settingsStore)
    }

    private func closePopoverIfNeeded() {
        guard isPopover else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            for window in NSApp.windows where window.className.contains("MenuBarExtra") {
                window.close()
            }
        }
    }

    private func toggleSelectionMode() {
        isSelectionMode.toggle()
        if !isSelectionMode {
            selectedItems.removeAll()
            lastSelectedItem = nil
        }
    }
    
    private func handleItemSelection(_ itemId: UUID) {
        // Check if Shift key is held for range selection
        if NSEvent.modifierFlags.contains(.shift), let lastSelected = lastSelectedItem {
            selectRange(from: lastSelected, to: itemId)
        } else {
            // Normal toggle selection
            if selectedItems.contains(itemId) {
                selectedItems.remove(itemId)
            } else {
                selectedItems.insert(itemId)
            }
            lastSelectedItem = itemId
        }
    }
    
    private func selectRange(from startId: UUID, to endId: UUID) {
        // Find indices of start and end items in filtered list
        guard let startIndex = filteredItems.firstIndex(where: { $0.id == startId }),
              let endIndex = filteredItems.firstIndex(where: { $0.id == endId }) else {
            return
        }
        
        // Determine the range (handle both directions)
        let range = startIndex <= endIndex ? startIndex...endIndex : endIndex...startIndex
        
        // Select all items in the range
        for index in range {
            selectedItems.insert(filteredItems[index].id)
        }
    }
    
    private func deleteSelectedItems() {
        let itemsToDelete = historyStore.items.filter { selectedItems.contains($0.id) }
        for item in itemsToDelete {
            historyStore.removeItemAndCleanup(item, settingsStore: settingsStore)
        }
        selectedItems.removeAll()
        lastSelectedItem = nil
        
        // Exit selection mode if no items remain
        if historyStore.items.isEmpty {
            isSelectionMode = false
        }
    }
}

// Helper modifier to conditionally apply list styles without type mismatch
private struct ListStyleConditional: ViewModifier {
    let isPopover: Bool
    func body(content: Content) -> some View {
        if isPopover {
            content.listStyle(.inset)
        } else {
            content.listStyle(.sidebar)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let settings = SettingsStore()
        let sampleStore = ClipboardHistoryStore(settingsStore: settings)
        sampleStore.items = ClipboardHistoryStore.createSampleData()
        return ContentView(isPopover: true)
            .environmentObject(sampleStore)
            .environmentObject(settings)
    }
}
