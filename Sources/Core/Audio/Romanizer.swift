import Foundation

public enum SupportedScript: String, CaseIterable, Sendable {
    case devanagari = "Devanagari"
    case bengali = "Bengali"
    case gurmukhi = "Gurmukhi"
    case gujarati = "Gujarati"
    case tamil = "Tamil"
    case telugu = "Telugu"
    case kannada = "Kannada"
    case malayalam = "Malayalam"
    case arabic = "Arabic"
    case hebrew = "Hebrew"
    case cyrillic = "Cyrillic"
    case cjk = "CJK"
    case hangul = "Hangul"
    case thai = "Thai"
    case latin = "Latin"
}

public enum LyricsScriptMode: String, CaseIterable, Codable, Sendable {
    case original = "Original"
    case romanized = "Romanized"
    case both = "Both"
}

public struct Romanizer {
    /// Detects non-Latin scripts present in the text
    public static func detectScript(in text: String) -> SupportedScript? {
        let sample = text.prefix(200)
        for scalar in sample.unicodeScalars {
            let val = scalar.value
            if val >= 0x0900 && val <= 0x097F { return .devanagari }
            if val >= 0x0980 && val <= 0x09FF { return .bengali }
            if val >= 0x0A00 && val <= 0x0A7F { return .gurmukhi }
            if val >= 0x0A80 && val <= 0x0AFF { return .gujarati }
            if val >= 0x0B00 && val <= 0x0B7F { return .tamil }
            if val >= 0x0B80 && val <= 0x0BFF { return .telugu }
            if val >= 0x0C80 && val <= 0x0CFF { return .kannada }
            if val >= 0x0D00 && val <= 0x0D7F { return .malayalam }
            if val >= 0x0600 && val <= 0x06FF { return .arabic }
            if val >= 0x0590 && val <= 0x05FF { return .hebrew }
            if val >= 0x0400 && val <= 0x04FF { return .cyrillic }
            if (val >= 0x4E00 && val <= 0x9FFF) || (val >= 0x3040 && val <= 0x309F) || (val >= 0x30A0 && val <= 0x30FF) { return .cjk }
            if (val >= 0xAC00 && val <= 0xD7AF) || (val >= 0x1100 && val <= 0x11FF) { return .hangul }
            if val >= 0x0E00 && val <= 0x0E7F { return .thai }
        }
        return nil
    }
    
    public static func hasNonLatinScript(text: String) -> Bool {
        return detectScript(in: text) != nil
    }
    
    /// Checks if a string contains significant CJK or Hangul characters.
    public static func isCJK(text: String) -> Bool {
        let script = detectScript(in: text)
        return script == .cjk || script == .hangul
    }
    
    /// Converts non-Latin text to Latin/Romanized text using built-in CoreFoundation transforms.
    public static func romanize(text: String) -> String {
        let mutableString = NSMutableString(string: text)
        CFStringTransform(mutableString, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        return mutableString as String
    }
}
