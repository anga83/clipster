import SwiftUI

/// Advanced clear history options view with time frame and app filtering
struct ClearHistoryOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var historyStore: ClipboardHistoryStore
    @ObservedObject var settingsStore: SettingsStore
    
    @State private var selectedTimeFrame: TimeFrame = .all
    @State private var selectedApp: String? = nil
    @State private var includePinnedItems: Bool = false
    @State private var previewCount: Int = 0
    @State private var showLargeDeletionWarning: Bool = false
    
    enum TimeFrame: String, CaseIterable, Identifiable {
        case fifteenMinutes = "last_15_min"
        case hour = "last_hour"
        case today = "today"
        case yesterday = "yesterday"
        case thisWeek = "this_week"
        case thisMonth = "this_month"
        case all = "all"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .fifteenMinutes: return "Last 15 minutes"
            case .hour: return "Last hour"
            case .today: return "Today"
            case .yesterday: return "Yesterday"
            case .thisWeek: return "This week"
            case .thisMonth: return "This month"
            case .all: return "All time"
            }
        }
        
        var cutoffDate: Date? {
            let calendar = Calendar.current
            let now = Date()
            
            switch self {
            case .fifteenMinutes:
                return calendar.date(byAdding: .minute, value: -15, to: now)
            case .hour:
                return calendar.date(byAdding: .hour, value: -1, to: now)
            case .today:
                return calendar.startOfDay(for: now)
            case .yesterday:
                return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
            case .thisWeek:
                return calendar.dateInterval(of: .weekOfYear, for: now)?.start
            case .thisMonth:
                return calendar.dateInterval(of: .month, for: now)?.start
            case .all:
                return nil
            }
        }
    }
    
    private var sourceApps: [String] {
        Array(Set(historyStore.items.compactMap { $0.sourceAppName })).sorted()
    }
    
    private var itemsToDelete: [ClipboardItem] {
        var items = historyStore.items
        
        // Filter by time frame
        if let cutoffDate = selectedTimeFrame.cutoffDate {
            items = items.filter { $0.timestamp >= cutoffDate }
        }
        
        // Filter by app
        if let selectedApp = selectedApp {
            items = items.filter { $0.sourceAppName == selectedApp }
        }
        
        // Filter by pinned status
        if !includePinnedItems {
            items = items.filter { !$0.isPinned }
        }
        
        return items
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header - noch kompakter
                VStack(spacing: 4) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.red.gradient)
                    
                    Text("Clear History")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text("Choose what to delete")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            
            // Options
            VStack(spacing: 12) {
                // Time Frame Selection
                optionSection(title: "Time Range", icon: "clock.fill", iconColor: .blue) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 6) {
                        ForEach(TimeFrame.allCases) { timeFrame in
                            Button(action: {
                                selectedTimeFrame = timeFrame
                                updatePreviewCount()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: selectedTimeFrame == timeFrame ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedTimeFrame == timeFrame ? .accentColor : .secondary)
                                        .font(.system(size: 12))
                                    
                                    Text(timeFrame.displayName)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 1)
                        }
                    }
                }
                
                // App Filter Selection
                optionSection(title: "App Filter", icon: "app.fill", iconColor: .green) {
                    VStack(alignment: .leading, spacing: 4) {
                        // All Apps option
                        Button(action: {
                            selectedApp = nil
                            updatePreviewCount()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: selectedApp == nil ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedApp == nil ? .accentColor : .secondary)
                                    .font(.system(size: 12))
                                
                                Text("All applications")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // Show count of available apps
                        if sourceApps.isEmpty {
                            Text("No apps with clipboard items found")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            Divider()
                            
                            Text("\(sourceApps.count) app\(sourceApps.count == 1 ? "" : "s") available:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 2) {
                                    ForEach(sourceApps, id: \.self) { app in
                                        Button(action: {
                                            selectedApp = selectedApp == app ? nil : app
                                            updatePreviewCount()
                                        }) {
                                            HStack(spacing: 8) {
                                                Image(systemName: selectedApp == app ? "checkmark.circle.fill" : "circle")
                                                    .foregroundColor(selectedApp == app ? .accentColor : .secondary)
                                                    .font(.system(size: 12))
                                                
                                                Text(app)
                                                    .font(.caption)
                                                    .foregroundColor(.primary)
                                                
                                                Spacer()
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(maxHeight: 80)
                        }
                    }
                }
                
                // Pinned Items Option
                optionSection(title: "Pinned Items", icon: "pin.fill", iconColor: .orange) {
                    Toggle(isOn: $includePinnedItems) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Also delete pinned clips")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("Normally preserved when clearing")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .orange))
                    .onChange(of: includePinnedItems) { _ in
                        updatePreviewCount()
                    }
                }
                
                // Preview
                if previewCount > 0 {
                    previewSection()
                }
            }                // Action Buttons
                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape)
                    
                    Button("Clear \(previewCount) Item\(previewCount == 1 ? "" : "s")") {
                        // Safety check for large deletions
                        if previewCount > 50 && !showLargeDeletionWarning {
                            showLargeDeletionWarning = true
                        } else {
                            performClearOperation()
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(previewCount == 0)
                    .keyboardShortcut(.return)
                }
                .padding(.bottom, 8)
            }
        }
        .padding(16)
        .frame(width: 460, height: 520)
        .onAppear {
            updatePreviewCount()
        }
        .alert("Large Deletion Warning", isPresented: $showLargeDeletionWarning) {
            Button("Cancel", role: .cancel) {
                showLargeDeletionWarning = false
            }
            Button("Delete \(previewCount) Items", role: .destructive) {
                showLargeDeletionWarning = false
                performClearOperation()
                dismiss()
            }
        } message: {
            Text("You are about to delete \(previewCount) clipboard items. This action cannot be undone.\n\nTime frame: \(selectedTimeFrame.displayName)\nApp filter: \(selectedApp ?? "All apps")\nInclude pinned: \(includePinnedItems ? "Yes" : "No")")
        }
    }
    
    @ViewBuilder
    private func optionSection<Content: View>(
        title: String,
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            content()
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
    
    @ViewBuilder
    private func previewSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "eye.fill")
                    .foregroundColor(.purple)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                
                Text("Preview")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(previewCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text("items will be deleted")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if previewCount > 0 {
                    let pinnedCount = itemsToDelete.filter { $0.isPinned }.count
                    if pinnedCount > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(pinnedCount)")
                                .font(.callout)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                            Text("pinned")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.purple.opacity(0.1))
        .cornerRadius(6)
    }
    
    private func updatePreviewCount() {
        previewCount = itemsToDelete.count
    }
    
    private func performClearOperation() {
        let itemsToRemove = itemsToDelete
        print("ClearHistoryOptionsView: About to delete \(itemsToRemove.count) items")
        print("ClearHistoryOptionsView: Time frame: \(selectedTimeFrame.displayName)")
        print("ClearHistoryOptionsView: Selected app: \(selectedApp ?? "All apps")")
        print("ClearHistoryOptionsView: Include pinned: \(includePinnedItems)")
        
        for item in itemsToRemove {
            historyStore.removeItemAndCleanup(item, settingsStore: settingsStore)
        }
        
        print("ClearHistoryOptionsView: Completed deletion operation")
    }
}

struct ClearHistoryOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        let settings = SettingsStore()
        ClearHistoryOptionsView(historyStore: ClipboardHistoryStore(settingsStore: settings), settingsStore: settings)
    }
}
