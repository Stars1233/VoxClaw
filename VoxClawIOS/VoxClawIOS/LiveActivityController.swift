import ActivityKit
import Foundation

/// Drives the "Now reading…" Live Activity for the lifetime of a read.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<VoxClawActivityAttributes>?
    private var lastProgress: Double = -1

    /// Begin a Live Activity for the current read (no-op if Live Activities are
    /// disabled or one is already running).
    func start(snippet: String, title: String = "VoxClaw") {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activity == nil else { return }
        let attributes = VoxClawActivityAttributes(title: title)
        let state = VoxClawActivityAttributes.ContentState(snippet: snippet, progress: 0)
        activity = try? Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
        lastProgress = 0
    }

    /// Update progress/snippet, throttled to avoid ActivityKit rate limits.
    func update(snippet: String, progress: Double) async {
        guard let activity else { return }
        guard progress - lastProgress >= 0.02 || progress >= 1 else { return }
        lastProgress = progress
        // ActivityKit's update/end are internally thread-safe; Activity isn't
        // Sendable, so opt the local out of region isolation to call them.
        nonisolated(unsafe) let current = activity
        let state = VoxClawActivityAttributes.ContentState(snippet: snippet, progress: progress)
        await current.update(.init(state: state, staleDate: nil))
    }

    func end() async {
        guard let activity else { return }
        nonisolated(unsafe) let current = activity
        self.activity = nil
        lastProgress = -1
        await current.end(nil, dismissalPolicy: .immediate)
    }
}
