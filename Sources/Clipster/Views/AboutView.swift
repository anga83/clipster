import SwiftUI

/// A view that displays information about the Clipster application.
struct AboutView: View {
    private var buildDateText: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"

        if
            let executableURL = Bundle.main.executableURL,
            let values = try? executableURL.resourceValues(forKeys: [.contentModificationDateKey]),
            let modificationDate = values.contentModificationDate
        {
            return dateFormatter.string(from: modificationDate)
        }

        return dateFormatter.string(from: Date())
    }

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

            Text("Build Date: \(buildDateText)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(32)
        .frame(minWidth: 320)
    }
}
