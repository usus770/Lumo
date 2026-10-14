import Foundation
import AVFoundation

/// Target audio format for conversion.
enum ConversionOutputFormat: String, CaseIterable, Identifiable, Sendable {
    case flac = "FLAC"
    case alac = "ALAC"
    case wav = "WAV"
    case aiff = "AIFF"
    
    var id: String { rawValue }
    
    var fileExtension: String {
        switch self {
        case .flac: return "flac"
        case .alac: return "m4a"
        case .wav: return "wav"
        case .aiff: return "aiff"
        }
    }
    
    var formatID: AudioFormatID {
        switch self {
        case .flac: return kAudioFormatFLAC
        case .alac: return kAudioFormatAppleLossless
        case .wav: return kAudioFormatLinearPCM
        case .aiff: return kAudioFormatLinearPCM
        }
    }
}

/// Target sample rate for conversion.
enum ConversionSampleRate: Int, CaseIterable, Identifiable, Sendable {
    case keepOriginal = 0
    case hz44100 = 44100
    case hz48000 = 48000
    case hz88200 = 88200
    case hz96000 = 96000
    case hz192000 = 192000
    
    var id: Int { rawValue }
    
    var displayName: String {
        if self == .keepOriginal { return "Keep Original" }
        return "\(rawValue / 1000) kHz"
    }
}

/// Target bit depth for conversion.
enum ConversionBitDepth: Int, CaseIterable, Identifiable, Sendable {
    case keepOriginal = 0
    case bit16 = 16
    case bit24 = 24
    case bit32Float = 32
    
    var id: Int { rawValue }
    
    var displayName: String {
        if self == .keepOriginal { return "Keep Original" }
        if self == .bit32Float { return "32-bit Float" }
        return "\(rawValue)-bit"
    }
}

/// Defines what to do if an output file already exists.
enum ConversionConflictResolution: String, CaseIterable, Identifiable, Sendable {
    case rename = "Rename"
    case overwrite = "Overwrite"
    case skip = "Skip"
    
    var id: String { rawValue }
}

/// Settings applied to a conversion job.
struct ConversionSettings: Sendable {
    var outputFormat: ConversionOutputFormat = .flac
    var sampleRate: ConversionSampleRate = .keepOriginal
    var bitDepth: ConversionBitDepth = .keepOriginal
    var outputFolder: URL? = nil
    var filenameTemplate: String = "{artist} - {title}"
    var conflictResolution: ConversionConflictResolution = .rename
    var replaceOriginal: Bool = false
    var addToLibrary: Bool = true
    var applyEnhancement: Bool = false
    var dither: Bool = true
}

/// Represents a single file conversion job.
struct ConversionJob: Identifiable, Sendable {
    let id = UUID()
    let sourceURL: URL
    let metadata: TrackMetadata? // To assist with filename template
    
    var status: JobStatus = .pending
    var progress: Double = 0.0
    var errorMessage: String? = nil
    var outputURL: URL? = nil
    var isSourceLossy: Bool = false
    var sizeEstimateBytes: Int64 = 0
    
    enum JobStatus: Equatable, Sendable {
        case pending
        case processing
        case completed
        case failed
        case cancelled
    }
}

/// Helper to pass minimal metadata if TrackInfo isn't available
struct TrackMetadata: Sendable {
    var title: String
    var artist: String
    var album: String
}
