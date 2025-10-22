import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("downloadDirectoryPath") private var downloadDirectoryPath: String = ""

    var body: some View {
        Form {
            HStack {
                Text("Download Directory")
                Spacer()
                Text(downloadDirectoryPath.isEmpty ? "Default" : downloadDirectoryPath)
                    .foregroundStyle(.secondary)
                Button("Change") { selectDirectory() }
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                downloadDirectoryPath = url.path
                // Persist a security-scoped bookmark for sandboxed access
                if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(bookmark, forKey: "downloadDirectoryBookmark")
                }
            }
        }
    }
}


