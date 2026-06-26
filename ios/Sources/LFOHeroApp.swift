import AVFoundation
import SwiftUI

@main
struct LFOHeroApp: App {
    @StateObject private var appState = AppState()
    @State private var showSplash = true

    init() {
        // Configure audio session immediately so iOS doesn't stall the run loop waiting
        // for the audio handshake that UIBackgroundModes: audio triggers at launch.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(appState)
                    .onAppear {
                        UIApplication.shared.isIdleTimerDisabled = appState.isConnected
                    }
                    .onDisappear {
                        UIApplication.shared.isIdleTimerDisabled = false
                    }
                    .onChange(of: appState.isConnected) { _, connected in
                        UIApplication.shared.isIdleTimerDisabled = connected
                    }

                if showSplash {
                    SplashScreenView()
                        .transition(.opacity)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
                }
            }
        }
    }
}
