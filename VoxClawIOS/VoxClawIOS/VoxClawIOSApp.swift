import AVFoundation
import SwiftUI
import VoxClawCore

@main
struct VoxClawIOSApp: App {
    // Shared singletons so App Intents (Siri/Spotlight/Shortcuts) drive the same
    // state as the UI.
    @State private var appState = SharedIOSApp.appState
    @State private var settings = SharedIOSApp.settings
    @State private var coordinator = SharedIOSApp.coordinator

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
        }
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
