import AVFoundation
import SwiftUI
import UIKit
import VoxClawCore

@main
struct VoxClawIOSApp: App {
    // Shared singletons so App Intents (Siri/Spotlight/Shortcuts) drive the same
    // state as the UI.
    @State private var appState = SharedIOSApp.appState
    @State private var settings = SharedIOSApp.settings
    @State private var coordinator = SharedIOSApp.coordinator

    @Environment(\.scenePhase) private var scenePhase
    @State private var lastHandledClipboardRequest: TimeInterval = 0

    // App Group shared with the widget/control extension (which can't play audio).
    private static let appGroup = "group.com.malpern.voxclaw"
    private static let pendingReadClipboardKey = "voxclaw.pendingReadClipboard"

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState, settings: settings, coordinator: coordinator)
                .task {
                    configureAudioSession()
                    #if targetEnvironment(simulator)
                    if settings.networkListenerPort == 4140 {
                        settings.networkListenerPort = 4141
                    }
                    #endif
                    coordinator.startListening(appState: appState, settings: settings)
                    coordinator.observeAudioInterruptions(appState: appState)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { handlePendingClipboardRead() }
                }
                .onChange(of: appState.queueActive) { _, active in
                    if active {
                        LiveActivityController.shared.start(
                            snippet: liveActivitySnippet(words: appState.words, index: appState.currentWordIndex),
                            title: appState.projectIndicators.first?.name ?? "VoxClaw"
                        )
                    } else {
                        Task { await LiveActivityController.shared.end() }
                    }
                }
                .onChange(of: appState.currentWordIndex) { _, idx in
                    guard appState.queueActive, appState.words.count > 1 else { return }
                    let snippet = liveActivitySnippet(words: appState.words, index: idx)
                    let progress = Double(idx) / Double(appState.words.count - 1)
                    Task { await LiveActivityController.shared.update(snippet: snippet, progress: progress) }
                }
        }
    }

    /// A short window of words around the current position for the Live Activity.
    private func liveActivitySnippet(words: [String], index: Int) -> String {
        guard !words.isEmpty else { return "Reading…" }
        let start = min(max(0, index), words.count - 1)
        let end = min(words.count, start + 8)
        let text = words[start..<end]
            .filter { $0 != ReadingSession.paragraphSentinel }
            .joined(separator: " ")
        return text.isEmpty ? "Reading…" : text
    }

    /// When the Control Center control / widget asks to read the clipboard, it
    /// opens the app and sets a timestamp in the App Group; we read it here.
    @MainActor
    private func handlePendingClipboardRead() {
        guard let defaults = UserDefaults(suiteName: Self.appGroup) else { return }
        let ts = defaults.double(forKey: Self.pendingReadClipboardKey)
        guard ts > lastHandledClipboardRequest else { return }
        lastHandledClipboardRequest = ts
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        Task { await coordinator.readText(text, appState: appState, settings: settings) }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("AVAudioSession configuration failed: \(error)")
        }
    }
}
