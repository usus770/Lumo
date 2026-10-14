import SwiftUI

/// Main Entrypoint for Lumo on iOS.
@main
struct Lumo_iOSApp: App {
    init() {
        // Configure iOS Lock Screen and Control Center remote commands
        iOSNowPlayingCenter.shared.setupRemoteCommands(playbackState: iOSPlaybackState.shared)
    }
    
    var body: some Scene {
        WindowGroup {
            iOSMainTabView()
                .preferredColorScheme(.dark)
        }
    }
}
