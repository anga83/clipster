import SwiftUI

/// The main view for the application's settings window.
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var historyStore: ClipboardHistoryStore
    @State private var selectedTab: SettingsTab = .general
    @State private var selection: Set<String> = []
    @State private var isShowingClearOptions: Bool = false
    
    private let debugLogger = DebugLogger.shared

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case fileAttachments = "File Attachments"
        case blacklist = "Blacklist"
        case archive = "Archive"
        case advanced = "Advanced"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .general: return "gear"
            case .fileAttachments: return "doc.fill"
            case .blacklist: return "shield.fill"
            case .archive: return "archivebox.fill"
            case .advanced: return "wrench.and.screwdriver.fill"
            }
        }
        
        var iconColor: Color {
            switch self {
            case .general: return .blue
            case .fileAttachments: return .green
            case .blacklist: return .red
            case .archive: return .purple
            case .advanced: return .orange
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar with tabs
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "gear.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue.gradient)
                    
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .padding(.top, 20)
                .padding(.bottom, 24)
                
                // Tab List
                List(SettingsTab.allCases, selection: $selectedTab) { tab in
                    HStack(spacing: 12) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(tab.iconColor)
                            .frame(width: 20)
                        
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .medium))
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedTab = tab
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                
                Spacer()
            }
            .frame(minWidth: 240, maxWidth: 240)
            .background(Color(NSColor.textBackgroundColor))
        } detail: {
            // Main content area
            Group {
                switch selectedTab {
                case .general:
                    generalSettingsView()
                case .fileAttachments:
                    fileAttachmentsView()
                case .blacklist:
                    blacklistView()
                case .archive:
                    ArchiveView()
                        .onAppear {
                            DebugLogger.shared.logArchiveOperation("ArchiveView appeared in SettingsView")
                        }
                case .advanced:
                    advancedView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .navigationSplitViewColumnWidth(min: 240, ideal: 240, max: 240)
        .frame(width: 840, height: 600)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle("")
        .onChange(of: selectedTab) { newValue in
            debugLogger.log("SettingsView tab changed to \(newValue)", level: .info)
            if newValue == .archive {
                debugLogger.logArchiveOperation("Archive tab selected", details: "About to show ArchiveView")
            }
        }
        .sheet(isPresented: $isShowingClearOptions) {
            ClearHistoryOptionsView(historyStore: historyStore, settingsStore: settings)
                .presentationDetents([.height(520), .large])
                .presentationDragIndicator(.visible)
        }
        // Avoid any implicit animations on tab switching (mitigates UI hangs on Sequoia)
        .animation(nil, value: selectedTab)
        .transaction { txn in txn.animation = nil }
    }
    
    @ViewBuilder
    private func generalSettingsView() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerView(title: "General", subtitle: "Basic application settings", icon: "gear", iconColor: .blue)
                
                settingsSection(title: "Startup Behavior") {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle(isOn: $settings.launchAtLogin) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Launch at Login (Menu Bar only)")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("Start Clipster automatically at login as a Menu Bar app.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))

                        Toggle(isOn: $settings.startWithMainWindow) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Open main window on launch")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("Automatically show the Clipster window when the app starts")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        
                        Toggle(isOn: $settings.menuBarClickOpensMainWindow) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Menu Bar click opens main window")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("Click the menu bar icon to open the main window instead of the popover")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    }
                }
                
                settingsSection(title: "Keyboard Shortcuts") {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle(isOn: $settings.enableGlobalShortcut) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enable global shortcut")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("Press ⌥⌘V to manually capture clipboard content, bypassing blacklisted apps")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        
                        if settings.enableGlobalShortcut {
                            infoBox(text: "Use Option+Command+V to force-capture clipboard content from any app, including blacklisted ones")
                        }
                    }
                }
                
                settingsSection(title: "Text Content") {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Minimum text length")
                                .font(.headline)
                                .fontWeight(.medium)
                            
                            HStack {
                                TextField("Characters", value: $settings.minTextLength, formatter: NumberFormatter())
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                
                                Text("characters")
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                            }
                            
                            Text("Only save text clips with at least this many characters. Set to 1 to save all text.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    @ViewBuilder
    private func fileAttachmentsView() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerView(title: "File Attachments", subtitle: "Configure how files are handled", icon: "doc.fill", iconColor: .green)
                
                settingsSection(title: "Size Limits") {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Maximum file size")
                                .font(.headline)
                                .fontWeight(.medium)
                            
                            HStack(spacing: 12) {
                                TextField("Size", value: $settings.maxFileSize, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                
                                Picker("Unit", selection: $settings.fileSizeUnit) {
                                    ForEach(SettingsStore.FileSizeUnit.allCases, id: \.self) { unit in
                                        Text(unit.displayName).tag(unit)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 120)
                                .onChange(of: settings.fileSizeUnit) { newUnit in
                                    settings.maxFileSize = settings.convertFileSize(to: newUnit)
                                }
                                
                                Spacer()
                            }
                            
                            infoBox(text: "Current limit: \(formatFileSize(bytes: settings.getFileSizeLimitInBytes()))")
                        }
                    }
                }
                
                settingsSection(title: "Large File Handling") {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle(isOn: $settings.symlinkLargeFiles) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Create symbolic links for large files")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("Files larger than the limit will be referenced by path instead of stored as data. Preview and drag & drop will still work.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        
                        Toggle(isOn: $settings.usePhysicalFileStorage) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Store files physically on disk")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("Files will be saved in the Application Support directory instead of being embedded as base64. When exporting, a zip file will be created containing both the JSON and the files.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    }
                }
                
                settingsSection(title: "File Type Rules") {
                    FileTypeRulesView(settingsStore: settings)
                }
            }
            .padding(24)
        }
    }
    
    @ViewBuilder
    private func blacklistView() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerView(title: "Application Blacklist", subtitle: "Block clipboard monitoring for specific apps", icon: "shield.fill", iconColor: .red)
                
                settingsSection(title: "Blacklisted Applications") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Clipster will ignore any items copied from these applications")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        VStack(spacing: 12) {
                            List(selection: $selection) {
                                ForEach(settings.blacklistedAppIdentifiers, id: \.self) { id in
                                    HStack(spacing: 12) {
                                        Image(systemName: "app.fill")
                                            .foregroundColor(.secondary)
                                            .frame(width: 20)
                                        Text(id)
                                            .font(.system(.body, design: .monospaced))
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .frame(minHeight: 200, maxHeight: 300)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                                handleDrop(providers: providers)
                            }

                            HStack {
                                Button(action: addApp) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Add Application")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                
                                Button(action: removeSelectedApp) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "minus.circle.fill")
                                        Text("Remove Selected")
                                    }
                                }
                                .disabled(selection.isEmpty)
                                .buttonStyle(.bordered)
                                
                                Spacer()
                            }
                            
                            infoBox(text: "Drag & drop .app files from Finder or use the Add button to browse")
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    @ViewBuilder
    private func advancedView() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerView(title: "Advanced", subtitle: "System and developer settings", icon: "wrench.and.screwdriver.fill", iconColor: .orange)
                
                settingsSection(title: "Data Management") {
                    VStack(spacing: 16) {
                        advancedSettingRow(
                            icon: "folder.circle.fill",
                            iconColor: .blue,
                            title: "Open Data Directory",
                            description: "View Clipster's configuration and history files",
                            buttonTitle: "Open in Finder"
                        ) {
                            // Open Clipster support directory
                            if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                                let clipsterURL = appSupportURL.appendingPathComponent("Clipster")
                                NSWorkspace.shared.open(clipsterURL)
                            }
                        }
                        
                        advancedSettingRow(
                            icon: "square.and.arrow.up.fill",
                            iconColor: .green,
                            title: "Export History",
                            description: "Create a full ZIP backup (SQLite DB, settings, attachments)",
                            buttonTitle: "Export"
                        ) {
                            historyStore.exportHistory(settingsStore: settings)
                        }
                        
                        advancedSettingRow(
                            icon: "square.and.arrow.down.fill",
                            iconColor: .orange,
                            title: "Import History",
                            description: "Restore a full Clipster ZIP backup or merge it with existing data",
                            buttonTitle: "Import"
                        ) {
                            historyStore.importHistory(settingsStore: settings)
                        }
                        
                        advancedSettingRow(
                            icon: "trash.fill",
                            iconColor: .red,
                            title: "Clear History",
                            description: "Selectively delete clipboard items by time range or application",
                            buttonTitle: "Clear..."
                        ) {
                            isShowingClearOptions = true
                        }
                        
                        advancedSettingRow(
                            icon: "pin.slash.fill",
                            iconColor: .orange,
                            title: "Unpin All Clips",
                            description: "Remove pin status from all pinned clipboard items",
                            buttonTitle: "Unpin All"
                        ) {
                            historyStore.unpinAllItems()
                        }
                    }
                }
                
                settingsSection(title: "History Loading") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Initial recent items to load")
                            .font(.headline)
                            .fontWeight(.medium)
                        HStack(spacing: 12) {
                            Stepper(value: $settings.recentUnpinnedInitialLoadLimit, in: 50...5000, step: 50) {
                                Text("\(settings.recentUnpinnedInitialLoadLimit) items")
                            }
                            .frame(width: 240)
                            
                            Button("Apply and Reload") {
                                historyStore.refreshInitialLoad()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Text("Loads all pinned items plus this many most recent unpinned items. Searching still covers your full history.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                settingsSection(title: "Configuration") {
                    VStack(spacing: 16) {
                        advancedSettingRow(
                            icon: "doc.text.fill",
                            iconColor: .green,
                            title: "Settings Storage",
                            description: "Settings are stored in a property list file",
                            buttonTitle: nil
                        ) { }
                    }
                }
                
                settingsSection(title: "Application Info") {
                    VStack(spacing: 16) {
                        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "N/A"
                        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "N/A"
                        
                        infoRow(label: "Version", value: "\(version) (Build \(build))")
                        infoRow(label: "Data Directory", value: settings.getSettingsFileLocation().replacingOccurrences(of: "/settings.plist", with: ""))
                        infoRow(label: "File Size Limit", value: formatFileSize(bytes: settings.getFileSizeLimitInBytes()))
                        infoRow(label: "Symlink Mode", value: settings.symlinkLargeFiles ? "Enabled" : "Disabled")
                    }
                }
            }
            .padding(24)
        }
        .animation(nil, value: settings.recentUnpinnedInitialLoadLimit)
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private func headerView(title: String, subtitle: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(iconColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            
            content()
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    @ViewBuilder
    private func advancedSettingRow(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        buttonTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.title2)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let buttonTitle = buttonTitle {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
    
    @ViewBuilder
    private func infoBox(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(12)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func warningBox(title: String, message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.medium)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .fontWeight(.medium)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func formatFileSize(bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    // MARK: - Actions
    
    private func addApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application] // Only allow .app files
        panel.directoryURL = URL(fileURLWithPath: "/Applications") // Start in Applications folder

        if panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
            settings.add(bundleIdentifier: id)
        }
    }

    private func removeSelectedApp() {
        settings.blacklistedAppIdentifiers.removeAll { selection.contains($0) }
        selection.removeAll()
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    guard let url = url, url.pathExtension == "app" else { return }
                    
                    DispatchQueue.main.async {
                        if let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
                            settings.add(bundleIdentifier: id)
                        }
                    }
                }
            }
        }
        return true
    }
}
