import Foundation
import AppKit
import SwiftUI
import Combine
import Darwin

// MARK: - Notification Types
enum NotificationType {
    case success
    case warning
    case error
    case info
    
    var icon: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.circle.fill"
        case .info:
            return "info.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        case .info:
            return .blue
        }
    }
}

// MARK: - Notification Model
struct AppNotification: Identifiable, Equatable {
    let id = UUID()
    let type: NotificationType
    let title: String
    let message: String
    let actions: [NotificationAction]
    let autoDismiss: Bool
    let dismissAfter: TimeInterval
    
    init(
        type: NotificationType,
        title: String,
        message: String,
        actions: [NotificationAction] = [],
        autoDismiss: Bool = true,
        dismissAfter: TimeInterval = 5.0
    ) {
        self.type = type
        self.title = title
        self.message = message
        self.actions = actions
        self.autoDismiss = autoDismiss
        self.dismissAfter = dismissAfter
    }
    
    static func == (lhs: AppNotification, rhs: AppNotification) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Notification Action
struct NotificationAction: Identifiable {
    let id = UUID()
    let title: String
    let style: ActionStyle
    let action: () -> Void
    
    enum ActionStyle {
        case primary
        case secondary
        case destructive
        
        var tint: Color? {
            switch self {
            case .primary:
                return nil
            case .secondary:
                return nil
            case .destructive:
                return .red
            }
        }
    }
}

// MARK: - Notification Manager
@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published private(set) var notifications: [AppNotification] = []
    private var dismissalTasks: [UUID: Task<Void, Never>] = [:]
    
    private init() {}
    
    func show(_ notification: AppNotification) {
        // Remove any existing notification with the same title to avoid duplicates
        notifications.removeAll { $0.title == notification.title }
        
        // Add the new notification
        notifications.append(notification)
        
        // Schedule auto-dismissal if enabled
        if notification.autoDismiss {
            let task = Task {
                try? await Task.sleep(nanoseconds: UInt64(notification.dismissAfter * 1_000_000_000))
                dismiss(notification.id)
            }
            dismissalTasks[notification.id] = task
        }
    }
    
    func dismiss(_ id: UUID) {
        notifications.removeAll { $0.id == id }
        dismissalTasks[id]?.cancel()
        dismissalTasks.removeValue(forKey: id)
    }
    
    func dismissAll() {
        notifications.removeAll()
        dismissalTasks.values.forEach { $0.cancel() }
        dismissalTasks.removeAll()
    }
    
    // Convenience methods for common notification types
    func showSuccess(title: String, message: String, autoDismiss: Bool = true) {
        let notification = AppNotification(
            type: .success,
            title: title,
            message: message,
            autoDismiss: autoDismiss
        )
        show(notification)
    }
    
    func showWarning(title: String, message: String, actions: [NotificationAction] = [], autoDismiss: Bool = false) {
        let notification = AppNotification(
            type: .warning,
            title: title,
            message: message,
            actions: actions,
            autoDismiss: autoDismiss
        )
        show(notification)
    }
    
    func showError(title: String, message: String, actions: [NotificationAction] = [], autoDismiss: Bool = false) {
        let notification = AppNotification(
            type: .error,
            title: title,
            message: message,
            actions: actions,
            autoDismiss: autoDismiss
        )
        show(notification)
    }
    
    func showInfo(title: String, message: String, actions: [NotificationAction] = [], autoDismiss: Bool = true) {
        let notification = AppNotification(
            type: .info,
            title: title,
            message: message,
            actions: actions,
            autoDismiss: autoDismiss
        )
        show(notification)
    }
}

@MainActor
final class YTDLPManager: ObservableObject {
    static let shared = YTDLPManager()
    
    @Published var isInstalled: Bool = false
    @Published var isInstalling: Bool = false
    @Published var installProgress: Double = 0.0
    @Published var installStatus: String = ""
    
    private let applicationSupportURL: URL
    private let ytdlpExecutableURL: URL
    private var embeddedYTDLPURL: URL? {
        // Look for a pre-bundled yt-dlp inside the app resources
        return Bundle.main.url(forResource: "yt-dlp", withExtension: nil)
    }
    private var nonContainerManagedURL: URL {
        // Some older builds or manual installs may have placed yt-dlp outside the sandbox container
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return home.appendingPathComponent("Library/Application Support/NanoJet/yt-dlp")
    }
    
    private init() {
        // Store yt-dlp in Application Support
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.applicationSupportURL = appSupportURL.appendingPathComponent("NanoJet", isDirectory: true)
        self.ytdlpExecutableURL = self.applicationSupportURL.appendingPathComponent("yt-dlp")
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: self.applicationSupportURL, withIntermediateDirectories: true)
        
        // If not present yet, try bootstrapping from embedded resource (if the app ships it)
        _ = bootstrapFromEmbeddedIfAvailable()
        // If a legacy copy exists outside the sandbox, migrate it
        _ = migrateFromLegacyUserAppSupportIfPresent()

        // Check if already installed
        checkInstallation()
    }

    /// If the app bundles a copy of yt-dlp in its Resources, copy it to our managed location.
    /// Returns true if we copied a fresh binary.
    @discardableResult
    private func bootstrapFromEmbeddedIfAvailable() -> Bool {
        guard let src = embeddedYTDLPURL else { return false }
        let fm = FileManager.default
        // Only bootstrap if managed binary is missing
        guard !fm.isExecutableFile(atPath: ytdlpExecutableURL.path) else { return false }
        do {
            if fm.fileExists(atPath: ytdlpExecutableURL.path) {
                try fm.removeItem(at: ytdlpExecutableURL)
            }
            try fm.copyItem(at: src, to: ytdlpExecutableURL)
            removeQuarantineAttribute(at: ytdlpExecutableURL)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ytdlpExecutableURL.path)
            return true
        } catch {
            print("YTDLPManager.bootstrapFromEmbeddedIfAvailable: failed to copy embedded yt-dlp: \(error.localizedDescription)")
            return false
        }
    }

    /// If yt-dlp exists in the user's non-container Application Support, migrate it into our sandboxed location
    /// Returns true if migration happened.
    @discardableResult
    private func migrateFromLegacyUserAppSupportIfPresent() -> Bool {
        let fm = FileManager.default
        let legacy = nonContainerManagedURL
        guard fm.isExecutableFile(atPath: legacy.path) else { return false }
        do {
            if fm.fileExists(atPath: ytdlpExecutableURL.path) {
                // Already managed; nothing to do
                return false
            }
            try fm.copyItem(at: legacy, to: ytdlpExecutableURL)
            removeQuarantineAttribute(at: ytdlpExecutableURL)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ytdlpExecutableURL.path)
            print("YTDLPManager: migrated yt-dlp from non-container to sandboxed location")
            return true
        } catch {
            print("YTDLPManager.migrateFromLegacyUserAppSupportIfPresent: failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Try to find a system-installed yt-dlp by checking common locations and the current PATH
    private func resolveSystemYTDLP() -> String? {
        let home = NSHomeDirectory()
        let candidates: [String] = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp",
            "/opt/local/bin/yt-dlp",
            "\(home)/.local/bin/yt-dlp"
        ]
        for p in candidates {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        if let envPATH = ProcessInfo.processInfo.environment["PATH"], !envPATH.isEmpty {
            for dir in envPATH.split(separator: ":") {
                let p = "\(dir)/yt-dlp"
                if FileManager.default.isExecutableFile(atPath: p) { return p }
            }
        }
        return nil
    }
    
    func checkInstallation() {
        // Check our managed location first
        print("YTDLPManager: Checking managed location: \(ytdlpExecutableURL.path)")
        if FileManager.default.isExecutableFile(atPath: ytdlpExecutableURL.path) {
            print("YTDLPManager: Found yt-dlp at managed location")
            isInstalled = true
            return
        }
        
        // Check non-container managed path first (migration scenarios)
        if FileManager.default.isExecutableFile(atPath: nonContainerManagedURL.path) {
            print("YTDLPManager: Found yt-dlp at legacy non-container location: \(nonContainerManagedURL.path)")
            isInstalled = true
        } else if let sys = resolveSystemYTDLP() {
            print("YTDLPManager: Found yt-dlp at system location: \(sys)")
            isInstalled = true
        } else {
            print("YTDLPManager: No yt-dlp found in known locations or PATH")
            isInstalled = false
        }
        print("YTDLPManager: Installation status: \(isInstalled)")
    }
    
    func getYTDLPPath() -> String? {
        // Prefer our managed installation
        print("YTDLPManager.getYTDLPPath: Checking managed path: \(ytdlpExecutableURL.path)")
        if FileManager.default.isExecutableFile(atPath: ytdlpExecutableURL.path) {
            print("YTDLPManager.getYTDLPPath: Returning managed path: \(ytdlpExecutableURL.path)")
            return ytdlpExecutableURL.path
        }
        // Fallback to non-container legacy managed path
        if FileManager.default.isExecutableFile(atPath: nonContainerManagedURL.path) {
            print("YTDLPManager.getYTDLPPath: Returning legacy non-container path: \(nonContainerManagedURL.path)")
            return nonContainerManagedURL.path
        }
        
        // Fallback to system installations (common locations + PATH)
        if let p = resolveSystemYTDLP() {
            print("YTDLPManager.getYTDLPPath: Returning system path: \(p)")
            return p
        }
        print("YTDLPManager.getYTDLPPath: No yt-dlp found, returning nil")
        return nil
    }
    
    func installYTDLP() async {
        guard !isInstalling else { return }
        
        isInstalling = true
        installProgress = 0.0
        installStatus = "Preparing to download yt-dlp..."
        
        do {
            // Fast path: if we ship an embedded yt-dlp, copy it first
            if bootstrapFromEmbeddedIfAvailable() {
                installStatus = "Verifying installation..."
                if await verifyInstallation() {
                    installProgress = 1.0
                    installStatus = "yt-dlp installed successfully!"
                    isInstalled = true
                    NotificationManager.shared.showSuccess(
                        title: "Installation Complete",
                        message: "yt-dlp has been installed from the app bundle."
                    )
                    isInstalling = false
                    return
                } else {
                    // If embedded copy fails verification, fall back to network download
                    print("YTDLPManager: embedded yt-dlp failed verification; falling back to network download")
                }
            }
            // Determine the correct binary URL based on architecture
            let architecture = getSystemArchitecture()
            let downloadURL: URL
            
            if architecture == "arm64" {
                // Apple Silicon
                downloadURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
            } else {
                // Intel Mac (universal binary works for both)
                downloadURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
            }
            
            installStatus = "Downloading yt-dlp..."
            installProgress = 0.1
            
            // Download the binary
            let (localURL, _) = try await URLSession.shared.download(from: downloadURL)
            installProgress = 0.6
            
            installStatus = "Installing yt-dlp..."
            
            // Move to our Application Support directory
            if FileManager.default.fileExists(atPath: ytdlpExecutableURL.path) {
                try FileManager.default.removeItem(at: ytdlpExecutableURL)
            }
            
            try FileManager.default.moveItem(at: localURL, to: ytdlpExecutableURL)
            installProgress = 0.8
            
            // Remove Gatekeeper quarantine attribute if present so the binary can run
            removeQuarantineAttribute(at: ytdlpExecutableURL)
            
            // Make it executable
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ytdlpExecutableURL.path)
            installProgress = 0.9
            
            // Verify installation
            installStatus = "Verifying installation..."
            let success = await verifyInstallation()
            
            if success {
                installProgress = 1.0
                installStatus = "yt-dlp installed successfully!"
                isInstalled = true
                
                // Show success notification
                NotificationManager.shared.showSuccess(
                    title: "Installation Complete",
                    message: "yt-dlp has been installed successfully and is ready to use."
                )
                
                // Clear status after a delay
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    if !isInstalling { return }
                    installStatus = ""
                    installProgress = 0.0
                }
            } else {
                throw YTDLPError.verificationFailed
            }
            
        } catch {
            installStatus = "Installation failed"
            isInstalled = false
            
            // Show error notification with retry action
            let retryAction = NotificationAction(
                title: "Retry",
                style: .primary
            ) {
                Task {
                    await self.installYTDLP()
                }
            }
            
            NotificationManager.shared.showError(
                title: "Installation Failed",
                message: "Failed to install yt-dlp: \(error.localizedDescription)",
                actions: [retryAction]
            )
        }
        
        isInstalling = false
    }
    
    func updateYTDLP() async {
        guard isInstalled else { return }
        
        isInstalling = true
        installStatus = "Checking for updates..."
        
        do {
            // Run yt-dlp --update
            guard let ytdlpPath = getYTDLPPath() else {
                throw YTDLPError.notFound
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ytdlpPath)
            process.arguments = ["--update"]
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            
            _ = try process.run()
            process.waitUntilExit()
            
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if output.contains("up-to-date") {
                installStatus = "yt-dlp is up to date"
                NotificationManager.shared.showInfo(
                    title: "Already Up to Date",
                    message: "yt-dlp is already running the latest version."
                )
            } else if output.contains("Updated") {
                installStatus = "Update completed"
                NotificationManager.shared.showSuccess(
                    title: "Update Complete",
                    message: "yt-dlp has been updated to the latest version."
                )
            } else {
                installStatus = "Update completed"
                NotificationManager.shared.showSuccess(
                    title: "Update Complete",
                    message: "yt-dlp update process completed."
                )
            }
            
            // Clear status after delay
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if !isInstalling { return }
                installStatus = ""
            }
            
        } catch {
            installStatus = "Update failed"
            
            // Show error notification with retry action
            let retryAction = NotificationAction(
                title: "Retry",
                style: .primary
            ) {
                Task {
                    await self.updateYTDLP()
                }
            }
            
            NotificationManager.shared.showError(
                title: "Update Failed",
                message: "Failed to update yt-dlp: \(error.localizedDescription)",
                actions: [retryAction]
            )
        }
        
        isInstalling = false
    }
    
    private func verifyInstallation() async -> Bool {
        guard let ytdlpPath = getYTDLPPath() else { return false }
        
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ytdlpPath)
            process.arguments = ["--version"]
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            
            _ = try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                print("YTDLPManager.verifyInstallation: yt-dlp --version failed with status \(process.terminationStatus). Output: \(output)")
            }
            return process.terminationStatus == 0
        } catch {
            print("YTDLPManager.verifyInstallation: failed to launch yt-dlp: \(error.localizedDescription)")
            return false
        }
    }
    
    private func getSystemArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
    
    enum YTDLPError: LocalizedError {
        case notFound
        case verificationFailed
        case downloadFailed
        
        var errorDescription: String? {
            switch self {
            case .notFound:
                return "yt-dlp executable not found"
            case .verificationFailed:
                return "Failed to verify yt-dlp installation"
            case .downloadFailed:
                return "Failed to download yt-dlp"
            }
        }
    }

    // MARK: - Helpers (Quarantine)
    private func removeQuarantineAttribute(at url: URL) {
        url.withUnsafeFileSystemRepresentation { fsPath in
            guard let fsPath else { return }
            "com.apple.quarantine".withCString { namePtr in
                _ = removexattr(fsPath, namePtr, 0)
            }
        }
    }
}
