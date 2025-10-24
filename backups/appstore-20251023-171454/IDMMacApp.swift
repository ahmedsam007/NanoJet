import SwiftUI
import AppKit
import DownloadEngine
import Foundation
// Sparkle removed for App Store - Apple handles updates automatically

@main
struct IDMMacApp: App {
    @StateObject private var appModel = AppViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("IDMMac", id: "main-window") {
            ContentView()
                .environmentObject(appModel)
                .onOpenURL { url in
                    // Expect: idmmac://add?url=<encoded>&headers=<base64(json)>
                    guard url.scheme == "idmmac" else { return }
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                       components.host == "add" {
                        let qs = components.queryItems ?? []
                        if let rawUrlValue = qs.first(where: { $0.name == "url" })?.value,
                           let urlString = rawUrlValue.removingPercentEncoding {
                            var headers: [String: String]? = nil
                            if let rawHeadersValue = qs.first(where: { $0.name == "headers" })?.value,
                               let headersB64 = rawHeadersValue.removingPercentEncoding,
                               let headersData = Data(base64Encoded: headersB64.replacingOccurrences(of: " ", with: "+"), options: [.ignoreUnknownCharacters]),
                               let json = try? JSONSerialization.jsonObject(with: headersData) as? [String: String] {
                                headers = json
                            }
                            var extras: [String: Any]? = nil
                            if let xRaw = qs.first(where: { $0.name == "x" })?.value,
                               let xB64 = xRaw.removingPercentEncoding,
                               let xData = Data(base64Encoded: xB64.replacingOccurrences(of: " ", with: "+"), options: [.ignoreUnknownCharacters]),
                               let xJson = try? JSONSerialization.jsonObject(with: xData) as? [String: Any] {
                                extras = xJson
                            }
                            appModel.enqueue(urlString: urlString, headers: headers, extras: extras, allowDuplicate: true)
                        }
                    }
                }
        }
        .handlesExternalEvents(matching: Set(["*"]))
        .commands {
            CommandMenu("Downloads") {
                Button("Add from Clipboard", action: appModel.addFromClipboard)
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
            CommandMenu("Tools") {
                Toggle(isOn: $appModel.shutdownWhenDone) {
                    Label("Shut down when done", systemImage: appModel.shutdownWhenDone ? "power.circle.fill" : "power.circle")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button {
                    if let w = NSApp.windows.first(where: { $0.title == "IDMMac" }) {
                        NSApp.activate(ignoringOtherApps: true)
                        w.makeKeyAndOrderFront(nil)
                    } else {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                } label: {
                    Label("Show Main Window", systemImage: "macwindow")
                }
                Button {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if let w = NSApp.windows.first(where: { $0.title == "Scheduler" }) {
                        w.makeKeyAndOrderFront(nil)
                    } else {
                        let win = NSWindow(
                            contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
                            styleMask: [.titled, .closable, .miniaturizable],
                            backing: .buffered,
                            defer: false
                        )
                        win.title = "Scheduler"
                        win.contentView = NSHostingView(rootView: SchedulerView().environmentObject(appModel))
                        win.center()
                        win.makeKeyAndOrderFront(nil)
                    }
                } label: {
                    Label("Schedule Downloads", systemImage: "calendar")
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appInfo) {
                // About IDMMac is now available in the gear menu
            }
            // "Check for Updates" removed for App Store - Apple handles updates automatically
        }
        // Dedicated window/tab for Test Connection
        WindowGroup("Test Connection", id: "test-connection", for: URL.self) { $url in
            let def = URL(string: "https://clients3.google.com/generate_204")!
            TestConnectionView(testURL: (url ?? def))
                .environmentObject(appModel)
        }
        // Log viewer window per item
        WindowGroup("Log", id: "log-viewer", for: UUID.self) { $itemId in
            if let itemId, let item = appModel.items.first(where: { $0.id == itemId }) {
                LogViewer(item: item)
                    .environmentObject(appModel)
            } else {
                Text("No log available")
                    .frame(minWidth: 480, minHeight: 360)
            }
        }
        Settings {
            SettingsView()
        }
        // Simple scheduler window
        Window("Scheduler", id: "scheduler") {
            SchedulerView()
                .environmentObject(appModel)
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Re-show the main window if all are closed
            if let window = NSApp.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}

// MARK: - About Credits View (converted to NSAttributedString)
private struct AboutCreditsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("IDMMac – Internet Download Manager for macOS")
                .font(.headline)
            Text("A fast, reliable download manager with segmented downloads, pause/resume, file integrity verification, and browser integration.")
                .font(.subheadline)
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Website:")
                        .font(.subheadline.weight(.semibold))
                    Text("ahmedsam.com")
                        .underline()
                        .foregroundColor(.blue)
                }
                HStack(spacing: 6) {
                    Text("Location:")
                        .font(.subheadline.weight(.semibold))
                    Text("Gaza, Gaza Strip, Palestine")
                }
                HStack(spacing: 6) {
                    Text("LinkedIn:")
                        .font(.subheadline.weight(.semibold))
                    Text("linkedin.com/in/ahmedamouna")
                        .underline()
                        .foregroundColor(.blue)
                }
            }
            .font(.callout)
        }
        .padding()
    }
}

// MARK: - Scheduler View
private struct SchedulerView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var startAt: Date = Date().addingTimeInterval(60 * 10)
    @State private var stopAt: Date = Date().addingTimeInterval(60 * 60)
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedule Downloads")
                .font(.title3.weight(.semibold))
            Text("Set a time window to automatically start/pause the queue.")
                .foregroundStyle(.secondary)
            Divider()
            HStack {
                Label("Start at", systemImage: "play.circle")
                DatePicker("", selection: $startAt)
                    .labelsHidden()
            }
            HStack {
                Label("Stop at", systemImage: "pause.circle")
                DatePicker("", selection: $stopAt)
                    .labelsHidden()
            }
            HStack {
                Button {
                    appModel.setSchedule(start: startAt, stop: stopAt)
                    dismiss()
                } label: {
                    Label("Save Schedule", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    appModel.clearSchedule()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 220)
    }
}

private extension View {
    func asNSAttributedString() -> NSAttributedString {
        let hosting = NSHostingView(rootView: self)
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 220)
        let pdfData = hosting.dataWithPDF(inside: hosting.bounds)
        let att = try? NSAttributedString(data: pdfData, options: [:], documentAttributes: nil)
        return att ?? NSAttributedString(string: "IDMMac")
    }
}

