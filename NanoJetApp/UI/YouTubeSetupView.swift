import SwiftUI

struct YouTubeSetupView: View {
    @StateObject private var ytdlpManager = YTDLPManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("useExternalDownloader") private var useExternalDownloader: Bool = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                    .symbolRenderingMode(.hierarchical)
                
                Text("External Downloader Setup")
                    .font(.title2.bold())
                
                Text("To download from YouTube and other sites, you need to install yt-dlp - a free, open-source tool.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .padding(.top, 8)
            
            Divider()
            
            // Installation status
            if ytdlpManager.isUserInstalled {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.green)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("yt-dlp is installed")
                                .font(.headline)
                            Text("Found at: \(ytdlpManager.getUserInstalledPath() ?? "unknown")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color.green.opacity(colorScheme == .dark ? 0.2 : 0.1))
                    .cornerRadius(12)
                    
                    if !useExternalDownloader {
                        Text("Enable 'External Downloader' in Settings to use yt-dlp")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(8)
                    }
                    
                    HStack(spacing: 12) {
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference") {
                                NSWorkspace.shared.open(url)
                            }
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Done") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else if ytdlpManager.isInstalling {
                VStack(spacing: 16) {
                    ProgressView(value: ytdlpManager.installProgress) {
                        Label(ytdlpManager.installStatus, systemImage: "arrow.down.circle")
                            .font(.callout)
                    }
                    .progressViewStyle(.linear)
                    
                }
                .padding()
            } else {
                VStack(spacing: 20) {
                    // Installation instructions
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Manual Installation Required", systemImage: "info.circle")
                            .font(.headline)
                            .foregroundStyle(.blue)
                        
                        Text("For legal compliance, yt-dlp must be installed separately by you. Choose your preferred method:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        
                    VStack(alignment: .leading, spacing: 12) {
                            InstallOptionRow(
                                method: "Homebrew (Recommended)",
                                command: "brew install yt-dlp",
                                icon: "terminal"
                            )
                            
                            InstallOptionRow(
                                method: "Direct Download",
                                command: "Visit github.com/yt-dlp/yt-dlp",
                                icon: "arrow.down.circle",
                                isLink: true
                            )
                            
                            InstallOptionRow(
                                method: "Python pip",
                                command: "pip install yt-dlp",
                                icon: "chevron.left.forwardslash.chevron.right"
                            )
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(colorScheme == .dark ? 0.2 : 0.1))
                    .cornerRadius(12)
                    
                    VStack(spacing: 8) {
                        Text("⚠️ Important Legal Notice")
                            .font(.callout.bold())
                        Text("By using yt-dlp, you agree to comply with all applicable laws and the terms of service of the websites you download from. This app does not endorse copyright infringement.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(8)
                    
                    HStack(spacing: 12) {
                        Button("Refresh") {
                            ytdlpManager.checkForUserInstalled()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Close") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Text("yt-dlp is a third-party tool • [Learn more](https://github.com/yt-dlp/yt-dlp)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
        .overlay(alignment: .top) {
            NotificationContainer()
                .padding(.top, 8)
        }
        .onAppear {
            ytdlpManager.checkForUserInstalled()
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(text)
                .font(.callout)
            
            Spacer()
        }
    }
}

private struct InstallOptionRow: View {
    let method: String
    let command: String
    let icon: String
    var isLink: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(method, systemImage: icon)
                .font(.callout.bold())
            
            HStack {
                if isLink {
                    Link(command, destination: URL(string: "https://github.com/yt-dlp/yt-dlp")!)
                        .font(.caption)
                } else {
                    Text(command)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                
                if !isLink {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    YouTubeSetupView()
}
