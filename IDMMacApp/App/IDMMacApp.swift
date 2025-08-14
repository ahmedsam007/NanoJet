import SwiftUI
import AppKit
import DownloadEngine

@main
struct IDMMacApp: App {
    @StateObject private var appModel = AppViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("IDMMac", id: "main-window") {
            ContentView()
                .environmentObject(appModel)
                .onOpenURL { url in
                    // Expect: idmmac://add?url=<encoded>
                    guard url.scheme == "idmmac" else { return }
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                       components.host == "add",
                       let queryItem = components.queryItems?.first(where: { $0.name == "url" }),
                       let urlString = queryItem.value?.removingPercentEncoding {
                        appModel.enqueue(urlString: urlString)
                    }
                }
        }
        .handlesExternalEvents(matching: Set(["*"]))
        .commands {
            CommandMenu("Downloads") {
                Button("Add from Clipboard", action: appModel.addFromClipboard)
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }
        // Dedicated window/tab for Test Connection
        WindowGroup("Test Connection", id: "test-connection", for: URL.self) { $url in
            let def = URL(string: "https://clients3.google.com/generate_204")!
            TestConnectionView(testURL: (url ?? def))
                .environmentObject(appModel)
        }
        Settings {
            SettingsView()
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


