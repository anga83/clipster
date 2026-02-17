import SwiftUI
import UserNotifications

@main
struct ClipsterApp: App {
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var historyStore: ClipboardHistoryStore
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
        openWindow(id: "main-window")
        NSApplication.shared.activate(ignoringOtherApps: true)
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

                    // Set up the app icon when the app is fully loaded
                    setupAppIcon()

                    // Handle dock visibility and auto-opening based on settings
                    if settingsStore.launchAtLogin && !settingsStore.startWithMainWindow {
                        // Menu Bar only: hide from dock initially
                        NSApp.setActivationPolicy(.accessory)
                        isMainWindowOpen = false
                    } else {
                        // Regular app window on launch when desired
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                        isMainWindowOpen = true
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
                .onDisappear {
                    // Hide from dock when main window is closed
                    NSApp.setActivationPolicy(.accessory)
                    isMainWindowOpen = false
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

    private func setupAppIcon() {
        // Ensure we're on the main thread and NSApp is ready
        DispatchQueue.main.async {
            // Create the same icon used in the About dialog for the dock with blue and white colors
            let iconSize: CGFloat = 512
            let image = NSImage(size: NSSize(width: iconSize, height: iconSize))
            
            image.lockFocus()
            
            // Create the SF Symbol with palette coloring
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: iconSize * 0.8, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white, .systemBlue]))
            
            if let symbolImage = NSImage(systemSymbolName: "paperclip.circle.fill", accessibilityDescription: "Clipster") {
                let coloredSymbol = symbolImage.withSymbolConfiguration(symbolConfig) ?? symbolImage
                
                // Calculate centered position
                let symbolSize = coloredSymbol.size
                let x = (iconSize - symbolSize.width) / 2
                let y = (iconSize - symbolSize.height) / 2
                let drawRect = NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height)
                
                // Draw the palette colored symbol
                coloredSymbol.draw(in: drawRect, from: NSRect(origin: .zero, size: symbolSize), operation: .sourceOver, fraction: 1.0)
            }
            
            image.unlockFocus()
            image.isTemplate = false
            
            NSApp.applicationIconImage = image
        }
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