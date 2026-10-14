import SwiftUI

/// The main application window layout: sidebar + content + now-playing bar.
struct MainWindowView: View {
    @Environment(PlaybackState.self) private var playbackState
    @Environment(WindowManager.self) private var windowManager
    @Environment(\.openWindow) private var openWindow
    @State private var settings = SettingsStore.shared
    @State private var showOnboarding = false
    @State private var showSplash = true
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Main content area
                NavigationSplitView {
                    SidebarView()
                        .frame(
                            minWidth: AppConstants.UI.sidebarMinWidth,
                            maxWidth: AppConstants.UI.sidebarMaxWidth
                        )
                        .toolbar(removing: .sidebarToggle)
                        .navigationSplitViewColumnWidth(
                            min: AppConstants.UI.sidebarMinWidth,
                            ideal: 220,
                            max: AppConstants.UI.sidebarMaxWidth
                        )
                } detail: {
                    ContentView()
                }
                .navigationSplitViewStyle(.balanced)
                
                // Bottom now-playing bar
                NowPlayingBar()
            }
            .background(LumoTheme.bg1)
            
            // Non-blocking, short animated brand splash (< 1.2s, skippable)
            if showSplash {
                SplashView(isPresented: $showSplash)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarItems
            }
        }
        .onAppear {
            if !settings.hasCompletedOnboarding {
                // Present onboarding right after the splash completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                    showOnboarding = true
                }
            }
            
            // D2: Background Batch Fetching
            Task.detached {
                let musicDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Music")
                await LibraryScanner.shared.scan(folderURL: musicDir)
                await LyricsBatchFetcher.shared.startBackgroundFetch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LumoShowOnboarding"))) { _ in
            showOnboarding = true
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
        }
    }
    
    @ViewBuilder
    private var toolbarItems: some View {
        Button {
            windowManager.isQueueVisible.toggle()
        } label: {
            Image(systemName: "list.bullet")
                .foregroundStyle(
                    windowManager.isQueueVisible
                        ? LumoTheme.accentPink
                        : LumoTheme.textSecondary
                )
        }
        .help("Toggle Queue")
        
        Button {
            VisualizerWindowController.shared.showFullScreen()
        } label: {
            Image(systemName: "quote.bubble")
                .foregroundStyle(LumoTheme.textSecondary)
        }
        .help("Open Visualizer")
    }
}