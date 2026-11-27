import SwiftUI
import UserNotifications

@main
struct ClipsterApp: App {
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var historyStore: ClipboardHistoryStore
    @StateObject private var timelineNavigation = TimelineNavigationCoordinator()
    @Environment(\.openWindow) private var openWindow
    @State private var clipboardMonitor: ClipboardMonitor?
    @State private var globalShortcutService: GlobalShortcutService?
    @State private var isMainWindowOpen = false

    init() {
        let settings = SettingsStore()
        _settingsStore = StateObject(wrappedValue: settings)
        _historyStore = StateObject(wrappedValue: ClipboardHistoryStore(settingsStore: settings))
    }

    private func openMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        openWindow(id: "main-window")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func updateActivationPolicyForMainWindowVisibility(isVisible: Bool) {
        if isVisible {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        if settingsStore.launchAtLogin && !settingsStore.startWithMainWindow {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
        }
    }
    
    private var menuBarExtraScene: some Scene {
        MenuBarExtra {
            if settingsStore.menuBarClickOpensMainWindow {
                // Show a message that main window will open on click
                VStack(spacing: 12) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.title)
                        .foregroundColor(.accentColor)
                    Text("Click the menu bar icon to open the main window")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Button("Open Main Window") {
                        openMainWindow()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(width: 250)
            } else {
                // Default behavior - show full popover
                ContentView(isPopover: true)
                    .environmentObject(historyStore)
                    .environmentObject(settingsStore)
                    .environmentObject(timelineNavigation)
            }
        } label: {
            Button(action: {
                if settingsStore.menuBarClickOpensMainWindow {
                    openMainWindow()
                }
            }) {
                Image(systemName: "paperclip")
            }
            .buttonStyle(PlainButtonStyle())
            .onAppear {
                // Ensure services are running even when only menu bar is active
                if clipboardMonitor == nil {
                    clipboardMonitor = ClipboardMonitor(historyStore: historyStore, settingsStore: settingsStore)
                    clipboardMonitor?.startMonitoring()
                }
                
                if globalShortcutService == nil && settingsStore.enableGlobalShortcut {
                    globalShortcutService = GlobalShortcutService(historyStore: historyStore, settingsStore: settingsStore)
                    globalShortcutService?.startMonitoring()
                }
            }
            .onChange(of: settingsStore.enableGlobalShortcut) { enabled in
                if enabled && globalShortcutService == nil {
                    globalShortcutService = GlobalShortcutService(historyStore: historyStore, settingsStore: settingsStore)
                    globalShortcutService?.startMonitoring()
                } else if !enabled {
                    globalShortcutService?.stopMonitoring()
                    globalShortcutService = nil
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    var body: some Scene {
        WindowGroup(id: "main-window") {
            ContentView(isPopover: false)
                .environmentObject(historyStore)
                .environmentObject(settingsStore)
                .environmentObject(timelineNavigation)
                .onAppear {
                    // Defer background services slightly to avoid main-thread hitches at launch (Sequoia)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if clipboardMonitor == nil {
                            clipboardMonitor = ClipboardMonitor(historyStore: historyStore, settingsStore: settingsStore)
                            clipboardMonitor?.startMonitoring()
                        }

                        // Start global shortcut service if enabled
                        if globalShortcutService == nil && settingsStore.enableGlobalShortcut {
                            globalShortcutService = GlobalShortcutService(historyStore: historyStore, settingsStore: settingsStore)
                            globalShortcutService?.startMonitoring()
                        }
                    }

                    // Request notification permissions for global shortcut feedback
                    requestNotificationPermissions()

                    // If the main window is visible, the app must be regular to show menu bar entries.
                    isMainWindowOpen = true
                    updateActivationPolicyForMainWindowVisibility(isVisible: true)
                }
                .onChange(of: settingsStore.enableGlobalShortcut) { enabled in
                    if enabled && globalShortcutService == nil {
                        globalShortcutService = GlobalShortcutService(historyStore: historyStore, settingsStore: settingsStore)
                        globalShortcutService?.startMonitoring()
                    } else if !enabled {
                        globalShortcutService?.stopMonitoring()
                        globalShortcutService = nil
                    }
                }
                .onDisappear {
                    isMainWindowOpen = false
                    updateActivationPolicyForMainWindowVisibility(isVisible: false)
                }
        }
        .commands {
            // Add standard menu commands
            CommandGroup(replacing: .appInfo) {
                Button("About Clipster") {
                    openWindow(id: "about-window")
                }
            }
        }

    menuBarExtraScene

        Settings {
            SettingsView()
                .environmentObject(settingsStore)
                .environmentObject(historyStore)
        }

        WindowGroup(id: "about-window") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Error requesting notification permissions: \(error)")
            } else if granted {
                print("✅ Notification permissions granted")
            } else {
                print("⚠️ Notification permissions denied")
            }
        }
    }
}
