import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("downloadDirectoryPath") private var downloadDirectoryPath: String = ""
    @AppStorage("useExternalDownloader") private var useExternalDownloader: Bool = false
    @AppStorage("externalDownloaderDisclaimed") private var externalDownloaderDisclaimed: Bool = false
    @StateObject private var ytdlpManager = YTDLPManager.shared
    @State private var showDisclaimerAlert = false
    @State private var tempExternalDownloaderEnabled = false

    var body: some View {
        Form {
            Section {
            HStack {
                Text("Download Directory")
                Spacer()
                Text(downloadDirectoryPath.isEmpty ? "Default" : downloadDirectoryPath)
                    .foregroundStyle(.secondary)
                Button("Change") { selectDirectory() }
                }
            }
            
            Divider()
                .padding(.vertical, 8)
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("External Downloader Support", systemImage: "terminal")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Enable external downloader (yt-dlp)", isOn: $tempExternalDownloaderEnabled)
                            .onChange(of: tempExternalDownloaderEnabled) { newValue in
                                if newValue && !externalDownloaderDisclaimed {
                                    showDisclaimerAlert = true
                                } else {
                                    useExternalDownloader = newValue
                                    if !newValue {
                                        // If disabling, don't reset the disclaimer
                                        // so user doesn't see it again when re-enabling
                                    }
                                }
                            }
                        
                        if useExternalDownloader {
                            HStack(spacing: 8) {
                                Image(systemName: ytdlpManager.isUserInstalled ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundColor(ytdlpManager.isUserInstalled ? .green : .orange)
                                
                                if ytdlpManager.isUserInstalled {
                                    Text("yt-dlp found at: \(ytdlpManager.getUserInstalledPath() ?? "unknown")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("yt-dlp not found. Please install it manually.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Button {
                                    ytdlpManager.checkForUserInstalled()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .help("Refresh detection")
                            }
                            .padding(.leading, 20)
                            
                            if !ytdlpManager.isUserInstalled {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("To install yt-dlp:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("• Using Homebrew: `brew install yt-dlp`")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("• Or download from: github.com/yt-dlp/yt-dlp")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.leading, 20)
                                .padding(.top, 4)
                            }
                        }
                        
                        Text("When enabled, the app will use your system-installed yt-dlp for supported sites.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 620)
        .onAppear {
            tempExternalDownloaderEnabled = useExternalDownloader
            ytdlpManager.checkForUserInstalled()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Re-check when app becomes active (user might have installed yt-dlp in terminal)
            ytdlpManager.checkForUserInstalled()
        }
        .alert("External Downloader Terms", isPresented: $showDisclaimerAlert) {
            Button("Cancel", role: .cancel) {
                tempExternalDownloaderEnabled = false
            }
            Button("I Understand", role: .none) {
                externalDownloaderDisclaimed = true
                useExternalDownloader = true
            }
        } message: {
            Text("""
            Important: By enabling the external downloader:
            
            • You acknowledge that you must comply with the terms of service of all websites you download from
            • You are responsible for ensuring your usage respects copyright and content creators' rights
            • This app does not endorse or encourage any form of copyright infringement
            • Some sites may prohibit downloading content - please check their terms of service
            
            The external downloader (yt-dlp) is a third-party tool not affiliated with this app. Use it responsibly and legally.
            """)
        }
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


