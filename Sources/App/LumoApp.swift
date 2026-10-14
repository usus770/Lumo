import SwiftUI

/// Main entry point for the Lumo music player.
@main
struct LumoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    /// Shared playback state observable across views.
    @State private var playbackState = PlaybackState.shared
    
    /// Window management state.
    @State private var windowManager = WindowManager.shared
    
    init() {
        if CommandLine.arguments.contains("--run-tests") {
            Task {
                await LumoTestRunner.runAllTests()
                exit(0)
            }
            while true {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
            }
        }
        
        if CommandLine.arguments.contains("--test-shader") {
            print("Instantiating view...")
            _ = KineticVisualizerView()
            print("Success!")
            exit(0)
        }
        
        if let idx = CommandLine.arguments.firstIndex(of: "--test-parser"), idx + 1 < CommandLine.arguments.count {
            let filename = CommandLine.arguments[idx + 1]
            Task {
                let url = URL(fileURLWithPath: filename)
                let metadata = await MetadataParser.parse(url: url)
                print("Final duration: \(metadata.duration)")
                exit(0)
            }
            while true {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
            }
        }
        
        if let idx = CommandLine.arguments.firstIndex(of: "--test-resolve"), idx + 1 < CommandLine.arguments.count {
            let filename = CommandLine.arguments[idx + 1]
            Task {
                let url = URL(fileURLWithPath: filename)
                var track = Track(filePath: url.path, fileName: url.lastPathComponent, fileExtension: url.pathExtension)
                let metadata = await MetadataParser.parse(url: url)
                let art = await MetadataResolver.shared.resolve(url: url, metadata: metadata, track: &track)
                print("RESOLVE RESULT -> Title: '\(track.title)', Artist: '\(track.artistName)', Album: '\(track.albumTitle)', Source: \(track.metadataSource), Conf: \(track.metadataConfidence), Art: \(art != nil)")
                exit(0)
            }
            while true {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
            }
        }
        
        if let idx = CommandLine.arguments.firstIndex(of: "--test-lyrics"), idx + 1 < CommandLine.arguments.count {
            let query = CommandLine.arguments[idx + 1]
            Task {
                var dummyTrack = Track(filePath: "/dummy/path.mp3", fileName: "dummy.mp3", fileExtension: "mp3")
                dummyTrack.title = query
                let results = await MetadataFetcherCoordinator.shared.search(query: query, localTrack: dummyTrack)
                print("Found \(results.count) search results for '\(query)'")
                if let first = results.first {
                    print("Best match: '\(first.title)' by '\(first.artist)' (source: \(first.source))")
                    let preview = await MetadataFetcherCoordinator.shared.fetchPreview(for: first, localTrack: dummyTrack)
                    if let lyrics = preview.lyricsCandidate {
                        print("LYRICS_SUCCESS: isSynced=\(lyrics.isSynced), source='\(lyrics.source)', lines=\(lyrics.lyricsText.components(separatedBy: .newlines).count)")
                        print("Sample lyrics line: '\(lyrics.lyricsText.components(separatedBy: .newlines).first ?? "")'")
                    } else {
                        print("LYRICS_FAILED: No lyrics returned")
                    }
                } else {
                    print("No search results found")
                }
                exit(0)
            }
            while true {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
            }
        }
        
        if CommandLine.arguments.contains("--print-tracks") {
            Task {
                let defaultMusic = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music")
                await LibraryScanner.shared.scan(folderURL: defaultMusic)
                let allTracks = await PersistenceStore.shared.loadAll(Track.self)
                let sample = allTracks.shuffled().prefix(20)
                print("| File | Parsed Title | Parsed Artist | Duration | Lyrics |")
                print("|---|---|---|---|---|")
                for track in sample {
                    let filename = URL(fileURLWithPath: track.filePath).lastPathComponent
                    let dur = String(format: "%.1fs", track.duration)
                    let lyr = track.hasSyncedLyrics ? "Synced" : (track.lyricsText?.isEmpty == false ? "Plain" : "None")
                    print("| \(filename) | \(track.title) | \(track.artistName) | \(dur) | \(lyr) |")
                }
                exit(0)
            }
            while true {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
            }
        }
        
        NSLog("[LumoApp] App launched, PlaybackState shared initialized")
        NSLog("[LumoApp] Starting NowPlayingProviderManager...")
        UniversalNowPlayingManager.shared.startMonitoring()
        NSLog("[LumoApp] NowPlayingProviderManager started")
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        let docsMusic = home.appendingPathComponent("Documents/music")
        let musicFolder = FileManager.default.fileExists(atPath: docsMusic.path)
            ? docsMusic
            : (FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Music"))
        
        if CommandLine.arguments.contains("--scan-library") {
            Task {
                await LibraryScanner.shared.scan(folderURL: musicFolder)
                await LibraryScanner.shared.migrateAndDeduplicateLibrary()
                let tracks = await PersistenceStore.shared.loadAll(Track.self)
                print("SCANNED_TRACKS_COUNT:\(tracks.count)")
                exit(0)
            }
            while true {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
            }
        }
        
        Task {
            if FileManager.default.fileExists(atPath: musicFolder.path) {
                let existingFolders = await PersistenceStore.shared.loadAll(LibraryFolder.self)
                if !existingFolders.contains(where: { $0.path == musicFolder.path }) {
                    await LibraryScanner.shared.scan(folderURL: musicFolder)
                }
            }
            await LibraryScanner.shared.migrateAndDeduplicateLibrary()
            await MainActor.run {
                NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
            }
        }
    }
    
    var body: some Scene {
        // MARK: - Main Window
        WindowGroup("Lumo", id: "main") {
            MainWindowView()
                .environment(playbackState)
                .environment(windowManager)
                .frame(
                    minWidth: AppConstants.Window.minWidth,
                    minHeight: AppConstants.Window.minHeight
                )
        }
        .defaultSize(
            width: AppConstants.Window.defaultWidth,
            height: AppConstants.Window.defaultHeight
        )
        .commands {
            LumoCommands(playbackState: playbackState)
        }
        
        // MARK: - Settings Window
        Settings {
            SettingsView()
                .environment(playbackState)
        }
        
        // MARK: - Mini Player (floating window, M6)
        // WindowGroup("Mini Player", id: "mini-player") { ... }
        
        // MARK: - Converter Window
        WindowGroup("Lossless Converter", id: "converter") {
            ConverterWindowView()
        }
    }
}

// MARK: - App Commands

/// Custom menu bar commands for playback control.
struct LumoCommands: Commands {
    let playbackState: PlaybackState
    @Environment(\.openWindow) private var openWindow
    
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Lumo") {
                AboutWindowController.shared.showAboutWindow()
            }
        }
        
        // Standard Edit / Pasteboard Commands for TextFields
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("x", modifiers: .command)
            
            Button("Copy") {
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("c", modifiers: .command)
            
            Button("Paste") {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("v", modifiers: .command)
            
            Button("Select All") {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("a", modifiers: .command)
        }
        
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
            }
            .keyboardShortcut("z", modifiers: .command)
            
            Button("Redo") {
                NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        
        // Playback menu
        CommandMenu("Playback") {
            Button("Lossless Converter...") {
                openWindow(id: "converter")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            
            Divider()
            
            Button("Play / Pause") {
                NowPlayingSnapshot.shared.togglePlayPause()
            }
            
            Divider()
            
            Button("Next Track") {
                NowPlayingSnapshot.shared.nextTrack()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            
            Button("Previous Track") {
                NowPlayingSnapshot.shared.previousTrack()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            
            Divider()
            
            Button("Volume Up") {
                playbackState.adjustVolume(by: 0.05)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            
            Button("Volume Down") {
                playbackState.adjustVolume(by: -0.05)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            
            Divider()
            
            Button("Shuffle") {
                playbackState.toggleShuffle()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            
            Button("Repeat") {
                playbackState.cycleRepeatMode()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        
        CommandMenu("Window") {
            Button("Kinetic Visualizer") {
                openWindow(id: "visualizer")
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        }
    }
}
