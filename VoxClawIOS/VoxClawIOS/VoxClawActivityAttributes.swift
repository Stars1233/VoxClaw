import ActivityKit
import Foundation

/// Shared between the app (which starts/updates/ends the activity) and the widget
/// extension (which renders it). Added to BOTH targets — Live Activities match the
/// attributes type by name, so the same declaration must compile into each.
struct VoxClawActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var snippet: String
        public var progress: Double
        public init(snippet: String, progress: Double) {
            self.snippet = snippet
            self.progress = progress
        }
    }

    public var title: String
    public init(title: String) { self.title = title }
}
