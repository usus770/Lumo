import Foundation

/// App-wide constants and configuration values.
enum AppConstants {
    
    enum Window {
        static let minWidth: CGFloat = 800
        static let minHeight: CGFloat = 500
        static let defaultWidth: CGFloat = 1100
        static let defaultHeight: CGFloat = 700
        static let miniPlayerWidth: CGFloat = 320
        static let miniPlayerHeight: CGFloat = 400
    }
    
    enum Playback {
        static let defaultVolume: Float = 0.8
        static let maxCrossfadeDuration: Double = 12.0
        static let seekStepSeconds: Double = 5.0
        static let volumeStep: Float = 0.05
    }
    
    enum Library {
        /// Supported audio file extensions (native AVFoundation).
        static let nativeFormats: Set<String> = [
            "mp3", "m4a", "m4b", "m4p", "aac", "alac",
            "wav", "aiff", "aif", "caf", "flac",
            "mp4", "m4v", "mov"
        ]
        
        /// Formats requiring external decoder (SFBAudioEngine / FFmpeg).
        static let extendedFormats: Set<String> = [
            "ogg", "oga", "opus", "wma", "ape",
            "wv",  // WavPack
            "dsf", "dff",  // DSD
            "mka", "amr", "ac3"
        ]
        
        /// All playable file extensions.
        static let allFormats: Set<String> = nativeFormats.union(extendedFormats)
        
        /// Maximum concurrent metadata parsing operations.
        static let maxConcurrentScans: Int = 8
        
        /// Batch size for incremental library updates.
        static let scanBatchSize: Int = 100
    }
    
    enum EQ {
        /// Standard 10-band equalizer frequencies in Hz.
        static let bandFrequencies: [Float] = [
            32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
        ]
        
        /// Default bandwidth (Q factor) for each band.
        static let defaultBandwidth: Float = 1.0
    }
    
    enum UI {
        static let sidebarMinWidth: CGFloat = 180
        static let sidebarMaxWidth: CGFloat = 280
        static let nowPlayingBarHeight: CGFloat = 72
        static let artworkCornerRadius: CGFloat = 8
        static let animationDuration: Double = 0.3
    }
}
