import AVFoundation
import SwiftUI

@main
struct LFOHeroApp: App {
    @StateObject private var appState = AppState()

    init() {
        // Configure audio session immediately so iOS doesn't stall the run loop waiting
        // for the audio handshake that UIBackgroundModes: audio triggers at launch.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                // Keep screen on while app is active — MIDI apps need this
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                .onDisappear {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
        }
    }
}
