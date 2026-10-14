import AppKit
import SwiftUI

/// AppDelegate handles menu bar status item and app-level lifecycle events.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    
    /// The persistent status bar item for the menu bar item.
    private var statusItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Guarantee new brand icon appears in Dock immediately
        if let iconImage = BrandAssets.appIconImage {
            NSApplication.shared.applicationIconImage = iconImage
        }
        
        setupMenuBarItem()
        startFolderWatcher()
        startCommandDispatcher()
        setupSpaceKeyHandler()
        
        // Re-start watcher whenever library folders change
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshFolderWatcher),
            name: .libraryDidUpdate,
            object: nil
        )
    }
    
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        // Re-show main window when dock icon is clicked
        if !flag {
            for window in sender.windows {
                if window.identifier?.rawValue == "main" {
                    window.makeKeyAndOrderFront(nil)
                    return true
                }
            }
        }
        return true
    }
    
    // MARK: - Menu Bar
    
    @MainActor
    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            if let templateImg = BrandAssets.menuBarTemplateImage {
                button.image = templateImg
            } else {
                button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Lumo")
            }
            button.imagePosition = .imageOnly
        }
        
        let menu = NSMenu()
        menu.delegate = self
        
        // Now Playing header item (Tag 100)
        let nowPlayingItem = NSMenuItem(title: "Not Playing", action: nil, keyEquivalent: "")
        nowPlayingItem.tag = 100
        nowPlayingItem.isEnabled = false
        menu.addItem(nowPlayingItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Show Lumo
        menu.addItem(NSMenuItem(title: "Show Lumo", action: #selector(showLumoAction), keyEquivalent: "o"))
        
        // Play / Pause (Tag 101)
        let playItem = NSMenuItem(title: "Play", action: #selector(togglePlayPauseAction), keyEquivalent: " ")
        playItem.tag = 101
        menu.addItem(playItem)
        
        // Next & Previous
        menu.addItem(NSMenuItem(title: "Next", action: #selector(nextTrackAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Previous", action: #selector(prevTrackAction), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        
        // Visualizer & About
        menu.addItem(NSMenuItem(title: "Kinetic Visualizer", action: #selector(openVisualizerAction), keyEquivalent: "v"))
        menu.addItem(NSMenuItem(title: "About Lumo", action: #selector(showAboutAction), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        menu.addItem(NSMenuItem(title: "Quit Lumo", action: #selector(quitLumoAction), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        refreshMenu(menu)
    }
    
    // MARK: - NSMenuDelegate
    
    func menuWillOpen(_ menu: NSMenu) {
        refreshMenu(menu)
    }
    
    private func refreshMenu(_ menu: NSMenu) {
        let snapshot = NowPlayingSnapshot.shared
        if let nowPlayingItem = menu.item(withTag: 100) {
            if !snapshot.title.isEmpty {
                let artistText = snapshot.artist.isEmpty ? "" : " – \(snapshot.artist)"
                nowPlayingItem.title = "Now Playing: \(snapshot.title)\(artistText)"
            } else {
                nowPlayingItem.title = "Not Playing"
            }
        }
        if let playItem = menu.item(withTag: 101) {
            playItem.title = snapshot.isPlaying ? "Pause" : "Play"
        }
    }
    
    @MainActor
    @objc private func showLumoAction() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.identifier?.rawValue == "main" || window.title == "Lumo" {
            window.makeKeyAndOrderFront(nil)
            return
        }
        if let first = NSApp.windows.first {
            first.makeKeyAndOrderFront(nil)
        }
    }
    
    @MainActor
    @objc private func togglePlayPauseAction() {
        NowPlayingSnapshot.shared.togglePlayPause()
    }
    
    @MainActor
    @objc private func nextTrackAction() {
        NowPlayingSnapshot.shared.nextTrack()
    }
    
    @MainActor
    @objc private func prevTrackAction() {
        NowPlayingSnapshot.shared.previousTrack()
    }
    
    @MainActor
    @objc private func openVisualizerAction() {
        VisualizerWindowController.shared.showFullScreen()
    }
    
    @MainActor
    @objc private func showAboutAction() {
        AboutWindowController.shared.showAboutWindow()
    }
    
    @MainActor
    @objc private func quitLumoAction() {
        NSApp.terminate(nil)
    }
    
    // MARK: - Folder Watcher
    
    private func startFolderWatcher() {
        Task.detached(priority: .background) {
            let folders = await PersistenceStore.shared.loadAll(LibraryFolder.self)
            let watchedPaths = folders.filter { $0.isWatched }.map { $0.path }
            await MainActor.run {
                FolderWatcher.shared.start(watching: watchedPaths)
            }
        }
    }
    
    @objc private func refreshFolderWatcher() {
        startFolderWatcher()
    }
    
    // MARK: - Command Dispatcher for Automation & Testing
    
    private var cmdTimer: Timer?
    
    private func startCommandDispatcher() {
        cmdTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            DispatchQueue.main.async {
                LumoCommandDispatcher.processCommandFile()
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        VisualizerWindowController.shared.closeFullScreen()
    }
    
    // MARK: - Key Monitor
    
    private var spaceKeyMonitor: Any?
    
    @MainActor
    private func setupSpaceKeyHandler() {
        spaceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // KeyCode 49 is Spacebar
            if event.keyCode == 49 {
                // If any text field or editor has first responder, allow it to type space normally!
                if let responder = NSApp.keyWindow?.firstResponder {
                    if responder is NSTextView || responder is NSTextField || responder is NSText {
                        return event
                    }
                }
                NowPlayingSnapshot.shared.togglePlayPause()
                return nil // consume event
            }
            return event
        }
    }
}

@MainActor
enum LumoCommandDispatcher {
    static func processCommandFile() {
        let path = NSHomeDirectory() + "/Library/Application Support/Lumo/cmd.json"
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        try? FileManager.default.removeItem(atPath: path)
        
        NSApp.activate(ignoringOtherApps: true)
        if let win = NSApp.windows.first(where: { $0.isVisible }) {
            win.makeKeyAndOrderFront(nil)
        }
        
        let action = json["action"] as? String ?? ""
        if action == "play", let query = json["query"] as? String {
            Task { @MainActor in
                let tracks = await PersistenceStore.shared.loadAll(Track.self)
                let sorted = tracks.sorted { $0.displayTitle < $1.displayTitle }
                if let idx = sorted.firstIndex(where: { $0.title.localizedCaseInsensitiveContains(query) || $0.fileName.localizedCaseInsensitiveContains(query) || $0.artistName.localizedCaseInsensitiveContains(query) }) {
                    let infos = sorted.map { t in
                        TrackInfo(
                            id: t.id,
                            title: t.displayTitle,
                            artist: t.displayArtist,
                            album: t.displayAlbum,
                            duration: t.duration,
                            artworkData: ArtworkCache.load(hash: t.artworkHash, filePath: t.filePath),
                            filePath: t.filePath,
                            fileExtension: t.fileExtension,
                            lyricsText: t.lyricsText,
                            hasSyncedLyrics: t.hasSyncedLyrics
                        )
                    }
                    PlaybackState.shared.play(tracks: infos, startingAt: idx)
                    let seekPos = json["seek"] as? Double ?? 15.0
                    Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        await MainActor.run {
                            PlaybackState.shared.seek(to: seekPos)
                        }
                    }
                }
            }
        } else if action == "shuffle" {
            PlaybackState.shared.toggleShuffle()
        } else if action == "visualizer" {
            VisualizerWindowController.shared.showFullScreen()
        } else if action == "close_visualizer" {
            VisualizerWindowController.shared.closeFullScreen()
        } else if action == "toggle_romanized" {
            NotificationCenter.default.post(name: Notification.Name("LumoToggleRomanized"), object: nil)
        } else if action == "toggle_debug" {
            NotificationCenter.default.post(name: Notification.Name("LumoToggleDebugOverlay"), object: nil)
        } else if action == "toggle_queue" {
            NotificationCenter.default.post(name: Notification.Name("LumoToggleQueuePopover"), object: nil)
        } else if action == "select_section", let sectionStr = json["section"] as? String {
            if let s = SidebarSection.allCases.first(where: { $0.rawValue.localizedCaseInsensitiveContains(sectionStr) }) {
                WindowManager.shared.selectedSection = s
            }
        } else if action == "seek", let pos = json["position"] as? Double {
            PlaybackState.shared.seek(to: pos)
        } else if action == "play_pause" {
            PlaybackState.shared.togglePlayPause()
            NotificationCenter.default.post(name: Notification.Name("LumoFlashPlayPauseFeedback"), object: nil)
        } else if action == "next" {
            PlaybackState.shared.nextTrack()
        } else if action == "previous" {
            PlaybackState.shared.previousTrack()
        } else if action == "volume", let v = json["value"] as? Double {
            PlaybackState.shared.volume = Float(v)
        } else if action == "mute" {
            PlaybackState.shared.toggleMute()
        } else if action == "user_activity" {
            let x = json["x"] as? Double ?? 500.0
            let y = json["y"] as? Double ?? 100.0
            NotificationCenter.default.post(name: Notification.Name("LumoVisualizerUserActivity"), object: NSPoint(x: x, y: y))
        } else if action == "set_test_track" {
            let title = json["title"] as? String ?? "Test Song"
            let artist = json["artist"] as? String ?? "Test Artist"
            let album = json["album"] as? String ?? "Test Album"
            let hasArtwork = json["has_artwork"] as? Bool ?? false
            let hasLyrics = json["has_lyrics"] as? Bool ?? false
            
            var artData: Data? = nil
            if hasArtwork {
                // Generate a simple valid 100x100 PNG
                let img = NSImage(size: NSSize(width: 100, height: 100))
                img.lockFocus()
                NSColor.systemPurple.setFill()
                NSRect(x: 0, y: 0, width: 100, height: 100).fill()
                img.unlockFocus()
                if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                    artData = rep.representation(using: .png, properties: [:])
                }
            }
            
            let lyricsText = hasLyrics ? "[00:00.00] In the neon glow of the midnight rain\n[00:05.00] Echoes of a melody calling my name\n[00:10.00] Lights fade down but the music stays alive\n[00:15.00] Reaching for the stars we will survive" : ""
            
            let testPath = "/tmp/test_\(UUID().uuidString).m4a"
            let trackInfo = TrackInfo(
                id: UUID(),
                title: title,
                artist: artist,
                album: album,
                duration: 215.0,
                artworkData: artData,
                filePath: testPath,
                fileExtension: "m4a",
                lyricsText: lyricsText,
                hasSyncedLyrics: hasLyrics
            )
            PlaybackState.shared.currentTrack = trackInfo
            PlaybackState.shared.duration = 215.0
            PlaybackState.shared.currentTime = 12.0
            PlaybackState.shared.isPlaying = true
            NowPlayingSnapshot.shared.updateLocal(
                track: trackInfo,
                isPlaying: true,
                currentTime: 12.0,
                duration: 215.0,
                rate: 1.0
            )
            if !hasLyrics {
                NowPlayingSnapshot.shared.lyricsText = nil
                NowPlayingSnapshot.shared.hasSyncedLyrics = false
            }
        } else if action == "test_event", let eventType = json["event"] as? String {
            guard let window = VisualizerWindowController.shared.window ?? NSApp.keyWindow else { return }
            if eventType == "esc" {
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53) {
                    window.sendEvent(event)
                }
            } else if eventType == "cmd_w" {
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13) {
                    window.sendEvent(event)
                }
            } else if eventType == "f" {
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "f", charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3) {
                    window.sendEvent(event)
                }
            } else if eventType == "space" {
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49) {
                    window.sendEvent(event)
                }
            } else if eventType == "left" {
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 123) {
                    window.sendEvent(event)
                }
            } else if eventType == "right" {
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124) {
                    window.sendEvent(event)
                }
            } else if eventType == "shift_left" {
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 123) {
                    window.sendEvent(event)
                }
            } else if eventType == "shift_right" {
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124) {
                    window.sendEvent(event)
                }
            } else if eventType == "up" {
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 126) {
                    window.sendEvent(event)
                }
            } else if eventType == "down" {
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 125) {
                    window.sendEvent(event)
                }
            } else if eventType == "m" {
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "m", charactersIgnoringModifiers: "m", isARepeat: false, keyCode: 46) {
                    window.sendEvent(event)
                }
            } else if eventType == "help" {
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "?", charactersIgnoringModifiers: "?", isARepeat: false, keyCode: 44) {
                    window.sendEvent(event)
                }
            } else if eventType == "top_click" {
                let topPoint = NSPoint(x: window.frame.width / 2.0, y: window.frame.height - 20.0)
                if let event = NSEvent.mouseEvent(with: .leftMouseDown, location: topPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1.0) {
                    window.sendEvent(event)
                }
            } else if eventType == "exit_button" {
                VisualizerWindowController.shared.closeFullScreen()
            }
        } else if action == "settings" {
            SettingsWindowController.shared.show()
        } else if action == "close_settings" {
            SettingsWindowController.shared.close()
        } else if action == "open_find_cover_lyrics" {
            let query = json["query"] as? String ?? ""
            Task { @MainActor in
                let tracks = await PersistenceStore.shared.loadAll(Track.self)
                if let t = tracks.first(where: { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.fileName.localizedCaseInsensitiveContains(query) }) {
                    NotificationCenter.default.post(name: Notification.Name("LumoOpenFindCoverLyrics"), object: t)
                }
            }
        } else if action == "open_autofind" {
            NotificationCenter.default.post(name: Notification.Name("LumoOpenAutoFindModal"), object: nil)
        } else if action == "apply_metadata" {
            let query = json["query"] as? String ?? ""
            let applyCover = json["apply_cover"] as? Bool ?? true
            let applyLyrics = json["apply_lyrics"] as? Bool ?? true
            Task {
                let tracks = await PersistenceStore.shared.loadAll(Track.self)
                if let t = tracks.first(where: { $0.title.localizedCaseInsensitiveContains(query) || $0.fileName.localizedCaseInsensitiveContains(query) }) {
                    let results = await MetadataFetcherCoordinator.shared.search(query: query, localTrack: t)
                    if let firstMatch = results.first {
                        let preview = await MetadataFetcherCoordinator.shared.fetchPreview(for: firstMatch, localTrack: t)
                        await MetadataFetcherCoordinator.shared.applyMatch(
                            trackId: t.id,
                            candidate: firstMatch,
                            coverCandidate: preview.coverCandidate,
                            lyricsCandidate: preview.lyricsCandidate,
                            applyCover: applyCover,
                            applyLyrics: applyLyrics
                        )
                        print("[LumoCommandDispatcher] Successfully applied metadata for: \(t.title)")
                    }
                }
            }
        } else if action == "run_autofind" {
            let scopeStr = json["scope"] as? String ?? "all"
            let scope: AutoFindScope
            switch scopeStr {
            case "missing_cover": scope = .missingCover
            case "missing_lyrics": scope = .missingLyrics
            default: scope = .all
            }
            Task {
                await MetadataFetcherCoordinator.shared.autoFindMissing(scope: scope) { _ in }
            }
        } else if action == "about" {
            AboutWindowController.shared.showAboutWindow()
        } else if action == "onboarding" {
            NotificationCenter.default.post(name: Notification.Name("LumoShowOnboarding"), object: nil)
        }
    }
}