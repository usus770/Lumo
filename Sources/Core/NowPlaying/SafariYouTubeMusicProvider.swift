import Foundation
import AppKit

/// Provider for YouTube Music in Safari (including Safari Web Apps / PWAs)
/// Uses JavaScript for Automation (JXA) to inject into Safari's web content
final class SafariYouTubeMusicProvider: NowPlayingProvider, @unchecked Sendable {
    let appName = "YouTube Music (Safari)"
    weak var delegate: NowPlayingProviderDelegate?
    
    var isAvailable: Bool { true }
    
    var isRunning: Bool {
        // Check for regular Safari
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.apple.Safari" }) {
            return true
        }
        // Check for Safari Web Apps (PWAs) - they have bundle IDs like com.apple.Safari.WebApp.*
        if NSWorkspace.shared.runningApplications.contains(where: { 
            $0.bundleIdentifier?.hasPrefix("com.apple.Safari.WebApp.") == true 
        }) {
            return true
        }
        return false
    }
    
    func startMonitoring() {}
    func stopMonitoring() {}
    
    func fetchAndNotify() {
        Task {
            if let state = await fetchState() {
                await MainActor.run {
                    delegate?.nowPlayingProvider(self, didUpdateState: state)
                }
            }
        }
    }
    
    func fetchState() async -> ExternalPlayerState? {
        guard isRunning else { return nil }
        
        // Use JXA (JavaScript for Automation) to find YouTube Music tab in Safari
        let jxaScript = """
        var Safari = Application('Safari');
        Safari.includeStandardAdditions = true;
        
        function getYTMusicInfo() {
            try {
                var windows = Safari.windows();
                for (var w = 0; w < windows.length; w++) {
                    var tabs = windows[w].tabs();
                    for (var t = 0; t < tabs.length; t++) {
                        var tab = tabs[t];
                        var url = tab.url();
                        if (url && (url.includes('music.youtube.com') || url.includes('youtube.com/music'))) {
                            // Found YouTube Music tab, now inject JS to get playback info
                            var result = tab.doJavaScript(`
                                try {
                                    var v = document.querySelector('video');
                                    var m = navigator.mediaSession.metadata;
                                    var isP = !v.paused;
                                    var t = m ? m.title : '';
                                    var a = m ? m.artist : '';
                                    var al = m ? m.album : '';
                                    var d = v.duration || 0;
                                    var c = v.currentTime || 0;
                                    return (isP ? 'playing' : 'paused') + '|!|' + t + '|!|' + a + '|!|' + al + '|!|' + d + '|!|' + c;
                                } catch(e) {
                                    return 'error';
                                }
                            `);
                            if (result && result !== 'error') {
                                return result;
                            }
                        }
                    }
                }
                return 'not found';
            }
            
            getYTMusicInfo();
        """
        
        let output = await runJXAScript(jxaScript)
        NSLog("[SafariYouTubeMusicProvider] JXA output: \(output ?? "nil")")
        
        guard let output = output, output != "error", output != "not found", !output.isEmpty else {
            return nil
        }
        
        let components = output.components(separatedBy: "|!|")
        guard components.count >= 6 else { return nil }
        
        return ExternalPlayerState(
            isPlaying: components[0] == "playing",
            trackName: components[1].isEmpty ? "Unknown" : components[1],
            artistName: components[2],
            albumName: components[3],
            duration: Double(components[4]) ?? 0,
            currentTime: Double(components[5]) ?? 0,
            artworkData: nil,
            appName: "YouTube Music"
        )
    }
    
    func playPause() {
        Task { await executeJXA("document.querySelector('video').paused ? document.querySelector('video').play() : document.querySelector('video').pause()") }
    }
    
    func nextTrack() {
        Task { await executeJXA("document.querySelector('.next-button')?.click()") }
    }
    
    func previousTrack() {
        Task { await executeJXA("document.querySelector('.previous-button')?.click()") }
    }
    
    func seek(to time: TimeInterval) {
        Task { await executeJXA("document.querySelector('video').currentTime = \(time)") }
    }
    
    private func executeJXA(_ js: String) async {
        let jxaScript = """
        var Safari = Application('Safari');
        var windows = Safari.windows();
        for (var w = 0; w < windows.length; w++) {
            var tabs = windows[w].tabs();
            for (var t = 0; t < tabs.length; t++) {
                var tab = tabs[t];
                var url = tab.url();
                if (url && (url.includes('music.youtube.com') || url.includes('youtube.com/music'))) {
                    tab.doJavaScript(`\(js.replacingOccurrences(of: "`", with: "\\`").replacingOccurrences(of: "$", with: "\\$"))`);
                    return;
                }
            }
        }
        """
        await runJXAScript(jxaScript)
    }
    
    @discardableResult
    private func runJXAScript(_ script: String) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-l", "JavaScript", "-e", script]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(returning: nil)
                }
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}