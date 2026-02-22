import SwiftUI
import UniformTypeIdentifiers

/// The main view for the Clipster application window.
struct ContentView: View {
    // Access the shared history store from the environment.
    @EnvironmentObject var historyStore: ClipboardHistoryStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.openWindow) private var openWindow

    /// Determines if the view is in a popover, which affects UI elements like the settings menu.
    let isPopover: Bool

    @State private var isShowingClearAlert: Bool    = false
    @State private var isShowingClearOptions: Bool = false
    @State private var searchText: String           = ""
    @State private var selectedSourceApps: Set<String> = []
    @State private var pinnedOnlyFilter: Bool = false
    @State private var useDateRangeFilter: Bool = false
    @State private var startDateFilter: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDateFilter: Date = Date()
    @State private var useTextLengthFilter: Bool = false
    @State private var minTextLengthFilter: Int = 0
    @State private var maxTextLengthFilter: Int = 1000
    @State private var isShowingAdvancedFilters: Bool = false
    @State private var isSelectionMode: Bool        = false
    @State private var selectedItems: Set<UUID>     = []
    @State private var lastSelectedItem: UUID?      = nil
    @State private var allHistoryItems: [ClipboardItem] = []
    @State private var hasLoadedAllHistoryItems = false
    @State private var loadedAllHistoryTotalCount = -1

    private static let filteredExportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 0
        return formatter
    }()

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

    private var hasActiveFilters: Bool {
        !selectedSourceApps.isEmpty || pinnedOnlyFilter || useDateRangeFilter || useTextLengthFilter
    }

    private var shouldUseFullHistoryForFiltering: Bool {
        !searchText.isEmpty || hasActiveFilters || isShowingAdvancedFilters
    }

    private var allItemsForFiltering: [ClipboardItem] {
        if shouldUseFullHistoryForFiltering && hasLoadedAllHistoryItems {
            return allHistoryItems
        }

        return baseItems
    }

    private var filteredItems: [ClipboardItem] {
        let sourceItems = allItemsForFiltering

        var items = sourceItems

        if !searchText.isEmpty {
            items = items.filter { item in
                switch item.content {
                case .text(let text):
                    return text.localizedCaseInsensitiveContains(searchText)
                case .fileURL(let url):
                    return url.absoluteString.localizedCaseInsensitiveContains(searchText)
                }
            }
        }

        if !selectedSourceApps.isEmpty {
            items = items.filter { item in
                guard let appName = item.sourceAppName else { return false }
                return selectedSourceApps.contains(appName)
            }
        }

        if pinnedOnlyFilter {
            items = items.filter(\.isPinned)
        }

        if useDateRangeFilter {
            let lower = min(startDateFilter, endDateFilter)
            let upper = max(startDateFilter, endDateFilter)
            let calendar = Calendar.current
            let startOfLowerDay = calendar.startOfDay(for: lower)
            let endOfUpperDay = calendar.date(
                byAdding: DateComponents(day: 1, second: -1),
                to: calendar.startOfDay(for: upper)
            ) ?? upper

            items = items.filter { $0.timestamp >= startOfLowerDay && $0.timestamp <= endOfUpperDay }
        }

        if useTextLengthFilter {
            let minLength = max(0, minTextLengthFilter)
            let maxLength = max(minLength, maxTextLengthFilter)

            items = items.filter { item in
                guard case .text(let text) = item.content else { return false }
                return text.count >= minLength && text.count <= maxLength
            }
        }

        // Sort results: pinned items first, then by timestamp (newest first)
        return items.sorted { first, second in
            if first.isPinned != second.isPinned {
                return first.isPinned // Pinned items come first
            }
            return first.timestamp > second.timestamp // Newest first within same pinned state
        }
    }

    private var sourceApps: [String] {
    let allApps = allItemsForFiltering.compactMap { $0.sourceAppName }
        return Array(Set(allApps)).sorted()
    }

    private var groupedItems: [(title: String, items: [ClipboardItem])] {
        let calendar = Calendar.current
        let now = Date()
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"

    let groups = Dictionary(grouping: filteredItems) { item -> String in
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
        .sheet(isPresented: $isShowingAdvancedFilters) {
            advancedFiltersView
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
                    Button(action: { exportFilteredItemsAsJSON() }) {
                        Label("Export Filtered JSON", systemImage: "square.and.arrow.up.on.square")
                    }
                    .disabled(filteredItems.isEmpty)
                    .help("Export currently filtered entries as JSON")
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
                if isPopover {
                    Menu {
                        Button("Reset Filters") {
                            resetFilters()
                        }

                        Divider()
                        Text("Pinned Filter")

                        Button {
                            pinnedOnlyFilter.toggle()
                        } label: {
                            Label {
                                Text("Pinned Only")
                            } icon: {
                                if pinnedOnlyFilter {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }

                        Divider()
                        Text("App Filter")

                        if !sourceApps.isEmpty {
                            ForEach(sourceApps, id: \.self) { appName in
                                Button {
                                    toggleSourceAppFilter(appName)
                                } label: {
                                    Label {
                                        Text(appName)
                                    } icon: {
                                        if selectedSourceApps.contains(appName) {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                            .symbolVariant(hasActiveFilters ? .fill : .none)
                    }
                    .help(hasActiveFilters ? "Filters active" : "Filter items")
                } else {
                    Button {
                        isShowingAdvancedFilters = true
                    } label: {
                        Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                            .symbolVariant(hasActiveFilters ? .fill : .none)
                    }
                    .help(hasActiveFilters ? "Edit active filters" : "Open filters")
                }
            }
        }
        .onAppear {
            if shouldUseFullHistoryForFiltering {
                refreshAllHistoryItemsIfNeeded()
            }
        }
        .onChange(of: searchText) { _, newValue in
            if !newValue.isEmpty {
                refreshAllHistoryItemsIfNeeded()
            }
        }
        .onChange(of: selectedSourceApps) { _, newValue in
            if !newValue.isEmpty {
                refreshAllHistoryItemsIfNeeded()
            }
        }
        .onChange(of: pinnedOnlyFilter) { _, enabled in
            if enabled {
                refreshAllHistoryItemsIfNeeded()
            }
        }
        .onChange(of: useDateRangeFilter) { _, enabled in
            if enabled {
                refreshAllHistoryItemsIfNeeded()
            }
        }
        .onChange(of: useTextLengthFilter) { _, enabled in
            if enabled {
                refreshAllHistoryItemsIfNeeded()
            }
        }
        .onChange(of: isShowingAdvancedFilters) { _, isShowing in
            if isShowing {
                refreshAllHistoryItemsIfNeeded()
            }
        }
        .onChange(of: historyStore.totalItemCount) { _, _ in
            if shouldUseFullHistoryForFiltering && hasLoadedAllHistoryItems {
                refreshAllHistoryItemsIfNeeded(force: true)
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
                        if searchText.isEmpty {
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
                    if searchText.isEmpty {
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

    /// The view to display when no items match the current search or filter.
    @ViewBuilder
    private var emptyStateView: some View {
        if (!searchText.isEmpty || hasActiveFilters) && filteredItems.isEmpty {
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
        if !searchText.isEmpty {
            if hasActiveFilters {
                return "No results for \"\(searchText)\" with current filters"
            }
            return "No results for \"\(searchText)\" found"
        }

        if hasActiveFilters {
            return "No items match current filters"
        }

        return "No Items Found"
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
                Button("Open Settings") {
                    openSettingsFromPopoverMenu()
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
    @ViewBuilder
    private var advancedFiltersView: some View {
        NavigationStack {
            Form {
                Section("Pinned Filter") {
                    Toggle("Pinned only", isOn: $pinnedOnlyFilter)
                }

                Section("App Filter") {
                    if sourceApps.isEmpty {
                        Text("No app entries available yet.")
                            .foregroundColor(.secondary)
                    } else {
                        HStack {
                            Button("Select all apps") {
                                selectedSourceApps = Set(sourceApps)
                            }
                            .buttonStyle(.link)

                            Button("Clear app selection") {
                                selectedSourceApps.removeAll()
                            }
                            .buttonStyle(.link)

                            Spacer()

                            Text("\(selectedSourceApps.count) selected")
                                .foregroundColor(.secondary)
                        }

                        ForEach(sourceApps, id: \.self) { appName in
                            Toggle(
                                appName,
                                isOn: Binding(
                                    get: { selectedSourceApps.contains(appName) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedSourceApps.insert(appName)
                                        } else {
                                            selectedSourceApps.remove(appName)
                                        }
                                    }
                                )
                            )
                        }
                    }
                }

                Section("Date Range") {
                    Toggle("Enable date range filter", isOn: $useDateRangeFilter)

                    if useDateRangeFilter {
                        DatePicker("Oldest date", selection: $startDateFilter, displayedComponents: [.date])
                        DatePicker("Newest date", selection: $endDateFilter, displayedComponents: [.date])
                    }
                }

                Section("Text Length") {
                    Toggle("Enable text length filter", isOn: $useTextLengthFilter)

                    if useTextLengthFilter {
                        HStack {
                            Text("Minimum")
                            Spacer()
                            TextField("0", value: $minTextLengthFilter, formatter: Self.integerFormatter)
                                .frame(width: 90)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("Maximum")
                            Spacer()
                            TextField("1000", value: $maxTextLengthFilter, formatter: Self.integerFormatter)
                                .frame(width: 90)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                        }

                        Text("Only text entries are included when this filter is enabled.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    HStack {
                        Text("\(filteredItems.count) filtered entries")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Reset Filters") {
                            resetFilters()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 560, minHeight: 520)
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isShowingAdvancedFilters = false
                    }
                }
            }
            .onChange(of: minTextLengthFilter) { _, _ in
                normalizeTextLengthBounds()
            }
            .onChange(of: maxTextLengthFilter) { _, _ in
                normalizeTextLengthBounds()
            }
        }
    }

    private func exportFilteredItemsAsJSON() {
        refreshAllHistoryItemsIfNeeded()

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        savePanel.title = "Export Filtered Items"
        savePanel.message = "Save only the entries matching the current filter criteria."
        let timestamp = Self.filteredExportDateFormatter.string(from: Date())
        savePanel.nameFieldStringValue = "Clipster-Filtered-\(timestamp).json"

        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(filteredItems)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try data.write(to: destinationURL, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Filtered JSON Export Failed"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func toggleSourceAppFilter(_ appName: String) {
        if selectedSourceApps.contains(appName) {
            selectedSourceApps.remove(appName)
        } else {
            selectedSourceApps.insert(appName)
        }
    }

    private func resetFilters() {
        selectedSourceApps.removeAll()
        pinnedOnlyFilter = false
        useDateRangeFilter = false
        startDateFilter = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        endDateFilter = Date()
        useTextLengthFilter = false
        minTextLengthFilter = 0
        maxTextLengthFilter = 1000
    }

    private func refreshAllHistoryItemsIfNeeded(force: Bool = false) {
        let latestTotalCount = historyStore.totalItemCount
        if !force, hasLoadedAllHistoryItems, loadedAllHistoryTotalCount == latestTotalCount {
            return
        }

        allHistoryItems = historyStore.loadAllHistoryItemsForFiltering()
        hasLoadedAllHistoryItems = true
        loadedAllHistoryTotalCount = latestTotalCount
    }

    private func normalizeTextLengthBounds() {
        if minTextLengthFilter < 0 {
            minTextLengthFilter = 0
        }

        if maxTextLengthFilter < minTextLengthFilter {
            maxTextLengthFilter = minTextLengthFilter
        }
    }

    private func openSettingsFromPopoverMenu() {
        let showSettingsAction = {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }

        if isPopover {
            closePopoverIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showSettingsAction()
            }
            return
        }

        showSettingsAction()
    }

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
