import SwiftUI

/// A view for managing file type specific treatment rules.
struct FileTypeRulesView: View {
    @ObservedObject var settingsStore: SettingsStore
    @State private var newFileExtension: String = ""
    @State private var selectedTreatment: FileTypeTreatment = .alwaysSymlink
    @State private var showingAddRule = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Special file type rules override normal size-based behavior")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Add Rule") {
                    showingAddRule = true
                }
                .buttonStyle(.borderedProminent)
            }
            
            if !settingsStore.fileTypeTreatments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(settingsStore.fileTypeTreatments.keys.sorted()), id: \.self) { fileExtension in
                        if let treatment = settingsStore.fileTypeTreatments[fileExtension] {
                            FileTypeRuleRow(
                                fileExtension: fileExtension,
                                treatment: treatment,
                                onDelete: {
                                    settingsStore.removeFileTypeTreatment(for: fileExtension)
                                }
                            )
                        }
                    }
                }
            } else {
                Text("No file type rules configured")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $showingAddRule) {
            AddFileTypeRuleView(
                settingsStore: settingsStore,
                isPresented: $showingAddRule
            )
        }
    }
}

/// A row displaying a single file type rule.
struct FileTypeRuleRow: View {
    let fileExtension: String
    let treatment: FileTypeTreatment
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(".\(fileExtension)")
                    .font(.body)
                    .fontWeight(.medium)
                Text(treatment.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Remove") {
                onDelete()
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

/// A sheet for adding new file type rules.
struct AddFileTypeRuleView: View {
    @ObservedObject var settingsStore: SettingsStore
    @Binding var isPresented: Bool
    @State private var fileExtension: String = ""
    @State private var selectedTreatment: FileTypeTreatment = .alwaysSymlink
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add File Type Rule")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("File Extension")
                    .font(.headline)
                
                TextField("e.g., pdf, jpg, mp4", text: $fileExtension)
                    .textFieldStyle(.roundedBorder)
                    .onReceive(fileExtension.publisher.collect()) { _ in
                        // Remove dots and make lowercase
                        fileExtension = fileExtension.replacingOccurrences(of: ".", with: "").lowercased()
                    }
                
                Text("Don't include the dot (.) in the extension")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Treatment")
                    .font(.headline)
                
                Picker("Treatment", selection: $selectedTreatment) {
                    ForEach(FileTypeTreatment.allCases, id: \.self) { treatment in
                        VStack(alignment: .leading) {
                            Text(treatment.displayName)
                            Text(treatment.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .tag(treatment)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            
            Spacer()
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Add Rule") {
                    addRule()
                }
                .buttonStyle(.borderedProminent)
                .disabled(fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400, height: 350)
    }
    
    private func addRule() {
        let cleanExtension = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanExtension.isEmpty else { return }
        
        settingsStore.setFileTypeTreatment(selectedTreatment, for: cleanExtension)
        isPresented = false
        
        // Reset form
        fileExtension = ""
        selectedTreatment = .alwaysSymlink
    }
}
