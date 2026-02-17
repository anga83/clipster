import SwiftUI

/// A view that displays information about the Clipster application.
struct AboutView: View {
    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "N/A"

        VStack(spacing: 16) {
            Image(systemName: "paperclip.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            VStack {
                Text("Clipster")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Version \(version)")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            Text("Build Date: 13.09.2025")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(32)
        .frame(minWidth: 320)
    }
}