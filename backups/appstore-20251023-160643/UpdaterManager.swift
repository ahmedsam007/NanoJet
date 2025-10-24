import Foundation
import Sparkle

/// Manages application updates using Sparkle 2 framework
@MainActor
final class UpdaterManager: ObservableObject {
    // Singleton instance
    static let shared = UpdaterManager()
    
    // Sparkle updater controller
    let updaterController: SPUStandardUpdaterController
    
    @Published var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = true
    @Published var automaticallyDownloadsUpdates = false
    
    private init() {
        // Initialize Sparkle updater with default configuration
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        
        // Sync published properties with Sparkle settings
        canCheckForUpdates = updaterController.updater.canCheckForUpdates
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updaterController.updater.automaticallyDownloadsUpdates
    }
    
    /// Manually check for updates
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
    
    /// Toggle automatic update checking
    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = enabled
    }
    
    /// Toggle automatic update downloads
    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyDownloadsUpdates = enabled
        automaticallyDownloadsUpdates = enabled
    }
    
    /// Get the last update check date
    var lastUpdateCheckDate: Date? {
        return updaterController.updater.lastUpdateCheckDate
    }
    
    /// Check if checking for updates is in progress
    var updateInProgress: Bool {
        return updaterController.updater.sessionInProgress
    }
}

