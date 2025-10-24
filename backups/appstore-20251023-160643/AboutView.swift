import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
    
    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // App Icon
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .cornerRadius(16)
                    .shadow(color: Color(NSColor.shadowColor).opacity(0.3), radius: 8, x: 0, y: 4)
            } else {
                // Fallback to system icon if custom icon not found
                Image(systemName: "arrow.down.circle.fill")
                    .resizable()
                    .frame(width: 128, height: 128)
                    .foregroundStyle(.blue)
            }
            
            // App Name
            Text("IDMMac")
                .font(.system(size: 28, weight: .semibold))
            
            // Version Info
            VStack(spacing: 4) {
                Text("Version \(appVersion) (Build \(buildNumber))")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                
                Text("A fast, lightweight macOS download manager")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Divider()
                .padding(.horizontal, 40)
            
            // Owner/Developer Info
            VStack(spacing: 12) {
                Link(destination: URL(string: "https://ahmedsam.com")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(.system(size: 12))
                        Text("ahmedsam.com")
                            .font(.system(size: 13))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                
                Text("© 2024-2025 Ahmed Sam")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                Text("All rights reserved")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            Divider()
                .padding(.horizontal, 40)
            
            // Features
            VStack(spacing: 8) {
                AboutFeatureRow(icon: "bolt.fill", text: "Segmented multi-connection downloads")
                AboutFeatureRow(icon: "pause.circle.fill", text: "Pause, resume & cancel support")
                AboutFeatureRow(icon: "checkmark.shield.fill", text: "SHA-256 verification")
                AboutFeatureRow(icon: "gauge.with.dots.needle.bottom.50percent", text: "Real-time speed & progress tracking")
            }
            .padding(.horizontal, 30)
            
            Spacer()
            
            // Update & Close Buttons
            HStack(spacing: 12) {
                Button("Check for Updates") {
                    UpdaterManager.shared.checkForUpdates()
                }
                .buttonStyle(.bordered)
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 10)
        }
        .padding(.vertical, 30)
        .frame(width: 420, height: 580)
    }
}

private struct AboutFeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 16)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

#Preview {
    AboutView()
}

