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

    @State private var isShowingClearOptions: Bool = false
    @State private var searchText: String = ""
    @State private var selectedSourceApps: Set<String> = []
    @State private var pinnedOnlyFilter: Bool = false
    @State private var useDateRangeFilter: Bool = false
    @State private var startDateFilter: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDateFilter: Date = Date()
    @State private var useTextLengthFilter: Bool = false
    @State private var minTextLengthFilter: Int = 0
    @State private var maxTextLengthFilter: Int = 1000
    @State private var isShowingAdvancedFilters: Bool = false
    @State private var draftSelectedSourceApps: Set<String> = []
    @State private var draftPinnedOnlyFilter: Bool = false
    @State private var draftUseDateRangeFilter: Bool = false
    @State private var draftStartDateFilter: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var draftEndDateFilter: Date = Date()
    @State private var draftUseTextLengthFilter: Bool = false
    @State private var draftMinTextLengthFilter: Int = 0
    @State private var draftMaxTextLengthFilter: Int = 1000
    @State private var filterAppMetadata: [String] = []
    @State private var filterOldestDate: Date?
    @State private var filterNewestDate: Date?
    @State private var isLoadingFilterMetadata = false
    @State private var queriedItems: [ClipboardItem] = []
    @State private var isRunningQuery = false
    @State private var queryRequestID: Int = 0
    @State private var metadataRequestID: Int = 0
    @State private var queryTask: Task<Void, Never>?
    @State private var metadataTask: Task<Void, Never>?
    @State private var suspendAutomaticQuery = false
    @State private var isSelectionMode: Bool = false
    @State private var selectedItems: Set<UUID> = []
    @State private var lastSelectedItem: UUID? = nil

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

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldUseDatabaseQuery: Bool {
        !normalizedSearchText.isEmpty || hasActiveFilters
    }

    private var filteredItems: [ClipboardItem] {
        let sourceItems = shouldUseDatabaseQuery ? queriedItems : baseItems
        return sourceItems.sorted { first, second in
            if first.isPinned != second.isPinned {
                return first.isPinned
            }
            return first.timestamp > second.timestamp
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
                    .disabled(!shouldUseDatabaseQuery || filteredItems.isEmpty || isRunningQuery)
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
                        openAdvancedFiltersSheet()
                    } label: {
                        Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                            .symbolVariant(hasActiveFilters ? .fill : .none)
                    }
                    .help(hasActiveFilters ? "Edit active filters" : "Open filters")
                }
            }
        }
        .onAppear {
            runQueryIfNeeded()
        }
        .onChange(of: searchText) { _, _ in
            handleAutomaticQueryUpdate()
        }
        .onChange(of: selectedSourceApps) { _, _ in
            handleAutomaticQueryUpdate()
        }
        .onChange(of: pinnedOnlyFilter) { _, _ in
            handleAutomaticQueryUpdate()
        }
        .onChange(of: useDateRangeFilter) { _, _ in
            handleAutomaticQueryUpdate()
        }
        .onChange(of: startDateFilter) { _, _ in
            handleAutomaticQueryUpdate()
        }
        .onChange(of: endDateFilter) { _, _ in
            handleAutomaticQueryUpdate()
        }
        .onChange(of: useTextLengthFilter) { _, _ in
            handleAutomaticQueryUpdate()
        }
        .onChange(of: minTextLengthFilter) { _, _ in
            handleAutomaticQueryUpdate()
        }
        .onChange(of: maxTextLengthFilter) { _, _ in
            handleAutomaticQueryUpdate()
        }
        .onChange(of: historyStore.totalItemCount) { _, _ in
            handleAutomaticQueryUpdate()
        }
        .onReceive(historyStore.$items) { _ in
            handleAutomaticQueryUpdate()
        }
        .onDisappear {
            queryTask?.cancel()
            metadataTask?.cancel()
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
                        if normalizedSearchText.isEmpty {
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
                        if normalizedSearchText.isEmpty {
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
        if shouldUseDatabaseQuery && isRunningQuery {
            VStack(spacing: 10) {
                ProgressView()
                Text("Filtering ...")
                    .font(.headline)
            }
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredItems.isEmpty {
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
        if !normalizedSearchText.isEmpty {
            if hasActiveFilters {
                return "No results for \"\(normalizedSearchText)\" with current filters"
            }
            return "No results for \"\(normalizedSearchText)\" found"
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
                if isLoadingFilterMetadata {
                    Section {
                        HStack(spacing: 8) {
                            Spacer()
                            ProgressView()
                            Text("Loading filter metadata ...")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Pinned Filter") {
                    Toggle("Pinned only", isOn: $draftPinnedOnlyFilter)
                }

                Section("App Filter") {
                    if filterAppMetadata.isEmpty {
                        Text(isLoadingFilterMetadata ? "Loading app list ..." : "No app entries available yet.")
                            .foregroundColor(.secondary)
                    } else {
                        HStack {
                            Button("Select all apps") {
                                draftSelectedSourceApps = Set(filterAppMetadata)
                            }
                            .buttonStyle(.link)

                            Button("Clear app selection") {
                                draftSelectedSourceApps.removeAll()
                            }
                            .buttonStyle(.link)

                            Spacer()

                            Text("\(draftSelectedSourceApps.count) selected")
                                .foregroundColor(.secondary)
                        }

                        ForEach(filterAppMetadata, id: \.self) { appName in
                            Toggle(
                                appName,
                                isOn: Binding(
                                    get: { draftSelectedSourceApps.contains(appName) },
                                    set: { isSelected in
                                        if isSelected {
                                            draftSelectedSourceApps.insert(appName)
                                        } else {
                                            draftSelectedSourceApps.remove(appName)
                                        }
                                    }
                                )
                            )
                        }
                    }
                }

                Section("Date Range") {
                    Toggle("Enable date range filter", isOn: $draftUseDateRangeFilter)

                    if draftUseDateRangeFilter {
                        if let oldest = filterOldestDate, let newest = filterNewestDate {
                            DatePicker("Oldest date", selection: $draftStartDateFilter, in: oldest...newest, displayedComponents: [.date])
                            DatePicker("Newest date", selection: $draftEndDateFilter, in: oldest...newest, displayedComponents: [.date])
                        } else {
                            DatePicker("Oldest date", selection: $draftStartDateFilter, displayedComponents: [.date])
                            DatePicker("Newest date", selection: $draftEndDateFilter, displayedComponents: [.date])
                        }
                    }
                }

                Section("Text Length") {
                    Toggle("Enable text length filter", isOn: $draftUseTextLengthFilter)

                    if draftUseTextLengthFilter {
                        HStack {
                            Text("Minimum")
                            Spacer()
                            TextField("0", value: $draftMinTextLengthFilter, formatter: Self.integerFormatter)
                                .frame(width: 90)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("Maximum")
                            Spacer()
                            TextField("1000", value: $draftMaxTextLengthFilter, formatter: Self.integerFormatter)
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
                            resetDraftFilters()
                        }
                        Button("Apply") {
                            applyDraftFilters()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunningQuery)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 560, minHeight: 520)
            .navigationTitle("Filters")
            .onChange(of: draftMinTextLengthFilter) { _, _ in
                normalizeDraftTextLengthBounds()
            }
            .onChange(of: draftMaxTextLengthFilter) { _, _ in
                normalizeDraftTextLengthBounds()
            }
        }
    }

    private func handleAutomaticQueryUpdate() {
        guard !suspendAutomaticQuery else { return }
        runQueryIfNeeded()
    }

    private func openAdvancedFiltersSheet() {
        draftSelectedSourceApps = selectedSourceApps
        draftPinnedOnlyFilter = pinnedOnlyFilter
        draftUseDateRangeFilter = useDateRangeFilter
        draftStartDateFilter = startDateFilter
        draftEndDateFilter = endDateFilter
        draftUseTextLengthFilter = useTextLengthFilter
        draftMinTextLengthFilter = minTextLengthFilter
        draftMaxTextLengthFilter = maxTextLengthFilter
        normalizeDraftTextLengthBounds()
        isShowingAdvancedFilters = true
        loadFilterMetadataForSheet()
    }

    private func loadFilterMetadataForSheet() {
        metadataTask?.cancel()
        metadataRequestID += 1
        let requestID = metadataRequestID
        isLoadingFilterMetadata = true

        metadataTask = Task {
            let metadata = await historyStore.loadFilterMetadataAsync()
            guard !Task.isCancelled, requestID == metadataRequestID else { return }
            filterAppMetadata = metadata.appNames
            filterOldestDate = metadata.oldestDate
            filterNewestDate = metadata.newestDate
            seedDraftDateRangeIfNeeded()
            isLoadingFilterMetadata = false
        }
    }

    private func seedDraftDateRangeIfNeeded() {
        guard let oldest = filterOldestDate, let newest = filterNewestDate else { return }

        if !draftUseDateRangeFilter {
            draftStartDateFilter = oldest
            draftEndDateFilter = newest
            return
        }

        if draftStartDateFilter < oldest {
            draftStartDateFilter = oldest
        } else if draftStartDateFilter > newest {
            draftStartDateFilter = newest
        }

        if draftEndDateFilter > newest {
            draftEndDateFilter = newest
        } else if draftEndDateFilter < oldest {
            draftEndDateFilter = oldest
        }
    }

    private func applyDraftFilters() {
        normalizeDraftTextLengthBounds()
        suspendAutomaticQuery = true
        selectedSourceApps = draftSelectedSourceApps
        pinnedOnlyFilter = draftPinnedOnlyFilter
        useDateRangeFilter = draftUseDateRangeFilter
        startDateFilter = draftStartDateFilter
        endDateFilter = draftEndDateFilter
        useTextLengthFilter = draftUseTextLengthFilter
        minTextLengthFilter = draftMinTextLengthFilter
        maxTextLengthFilter = draftMaxTextLengthFilter
        suspendAutomaticQuery = false
        isShowingAdvancedFilters = false
        runQueryIfNeeded()
    }

    private func resetDraftFilters() {
        draftSelectedSourceApps.removeAll()
        draftPinnedOnlyFilter = false
        draftUseDateRangeFilter = false
        if let oldest = filterOldestDate {
            draftStartDateFilter = oldest
        } else {
            draftStartDateFilter = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        }
        if let newest = filterNewestDate {
            draftEndDateFilter = newest
        } else {
            draftEndDateFilter = Date()
        }
        draftUseTextLengthFilter = false
        draftMinTextLengthFilter = 0
        draftMaxTextLengthFilter = 1000
    }

    private func exportFilteredItemsAsJSON() {
        guard shouldUseDatabaseQuery, !filteredItems.isEmpty else {
            return
        }

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
        suspendAutomaticQuery = true
        selectedSourceApps.removeAll()
        pinnedOnlyFilter = false
        useDateRangeFilter = false
        startDateFilter = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        endDateFilter = Date()
        useTextLengthFilter = false
        minTextLengthFilter = 0
        maxTextLengthFilter = 1000
        suspendAutomaticQuery = false
        runQueryIfNeeded()
    }

    private func normalizeDraftTextLengthBounds() {
        if draftMinTextLengthFilter < 0 {
            draftMinTextLengthFilter = 0
        }

        if draftMaxTextLengthFilter < draftMinTextLengthFilter {
            draftMaxTextLengthFilter = draftMinTextLengthFilter
        }
    }

    private func runQueryIfNeeded() {
        guard shouldUseDatabaseQuery else {
            queryTask?.cancel()
            queryRequestID += 1
            isRunningQuery = false
            queriedItems = []
            pruneSelectionToVisibleItems(in: filteredItems)
            return
        }

        queryTask?.cancel()
        queryRequestID += 1
        let requestID = queryRequestID
        let queryText = normalizedSearchText
        let sourceApps = selectedSourceApps
        let pinnedOnly = pinnedOnlyFilter
        let useDateRange = useDateRangeFilter
        let startDate = startDateFilter
        let endDate = endDateFilter
        let useTextLength = useTextLengthFilter
        let minTextLength = minTextLengthFilter
        let maxTextLength = maxTextLengthFilter

        isRunningQuery = true
        queryTask = Task {
            let items = await historyStore.queryHistoryForFiltersAsync(
                searchText: queryText,
                sourceAppNames: sourceApps,
                pinnedOnly: pinnedOnly,
                useDateRange: useDateRange,
                startDate: startDate,
                endDate: endDate,
                useTextLength: useTextLength,
                minTextLength: minTextLength,
                maxTextLength: maxTextLength
            )
            guard !Task.isCancelled, requestID == queryRequestID else { return }
            queriedItems = items
            isRunningQuery = false
            pruneSelectionToVisibleItems(in: filteredItems)
        }
    }

    private func pruneSelectionToVisibleItems(in currentItems: [ClipboardItem]) {
        let visibleIDs = Set(currentItems.map(\.id))
        selectedItems = selectedItems.intersection(visibleIDs)
        if let lastSelectedItem, !visibleIDs.contains(lastSelectedItem) {
            self.lastSelectedItem = nil
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
