#if os(macOS)
import Combine
import Sparkle

/// Wraps Sparkle's updater so SwiftUI can drive a "Check for Updates…" command
/// and reflect whether a check is currently allowed.
///
/// `SUFeedURL` (the appcast) and `SUPublicEDKey` (the EdDSA public key) are read
/// from the app's Info.plist — see `Scripts/package_app.sh`, which writes both.
@MainActor
final class VoxClawUpdater: ObservableObject {
    private let controller: SPUStandardUpdaterController

    /// Drives the enabled state of the "Check for Updates…" menu item.
    @Published var canCheckForUpdates = false

    init() {
        // startingUpdater: true begins Sparkle's scheduled background update checks.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Triggers a user-initiated update check (shows Sparkle's UI).
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
#endif
