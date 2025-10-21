import SwiftUI

struct YouTubeSetupView: View {
    @StateObject private var ytdlpManager = YTDLPManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                    .symbolRenderingMode(.hierarchical)
                
                Text("YouTube Downloads")
                    .font(.title2.bold())
                
                Text("To download YouTube videos, we need to install yt-dlp - a free, open-source tool.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .padding(.top, 8)
            
            Divider()
            
            // Installation status
            if ytdlpManager.isInstalled {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.green)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("yt-dlp is installed")
                                .font(.headline)
                            Text("You can now download YouTube videos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color.green.opacity(colorScheme == .dark ? 0.2 : 0.1))
                    .cornerRadius(12)
                    
                    HStack(spacing: 12) {
                        Button("Check for Updates") {
                            Task {
                                await ytdlpManager.updateYTDLP()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(ytdlpManager.isInstalling)
                        
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
                    // Benefits list
                    VStack(alignment: .leading, spacing: 12) {
                        FeatureRow(icon: "checkmark.circle", text: "Download any YouTube video", color: .green)
                        FeatureRow(icon: "gauge.high", text: "Best available quality", color: .blue)
                        FeatureRow(icon: "lock.shield", text: "Safe & secure", color: .purple)
                        FeatureRow(icon: "arrow.clockwise", text: "Automatic updates", color: .orange)
                    }
                    .padding()
                    .background(Color.secondary.opacity(colorScheme == .dark ? 0.2 : 0.1))
                    .cornerRadius(12)
                    
                    
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            Task {
                                await ytdlpManager.installYTDLP()
                            }
                        } label: {
                            Label("Install yt-dlp", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    
                    Text("yt-dlp is free and open source • [Learn more](https://github.com/yt-dlp/yt-dlp)")
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
            ytdlpManager.checkInstallation()
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

#Preview {
    YouTubeSetupView()
}
