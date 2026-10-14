import Foundation

public struct LyricsAligner {
    
    public static func align(referenceText: String, whisperWords: [GroqWhisperResponse.WhisperWord]) -> ParsedLyrics {
        // Simple line splitting
        let refLines = referenceText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        var alignedLines: [LyricLine] = []
        var whisperIdx = 0
        
        for refLine in refLines {
            let refWords = refLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            var lineWords: [LyricWord] = []
            
            for refW in refWords {
                let cleanRef = clean(refW)
                let romanRef = Romanizer.romanize(text: cleanRef)
                
                var matched = false
                // Lookahead window of 5 words
                for lookahead in 0..<min(5, whisperWords.count - whisperIdx) {
                    let wWord = whisperWords[whisperIdx + lookahead]
                    let cleanW = clean(wWord.word)
                    let romanW = Romanizer.romanize(text: cleanW)
                    
                    if cleanW == cleanRef || romanW == romanRef || (romanRef.count >= 4 && (romanRef.contains(romanW) || romanW.contains(romanRef))) {
                        lineWords.append(LyricWord(text: refW, start: wWord.start, end: wWord.end))
                        whisperIdx += lookahead + 1
                        matched = true
                        break
                    }
                }
                
                if !matched {
                    // Interpolate
                    let start = lineWords.last?.end ?? (alignedLines.last?.words.last?.end ?? 0)
                    lineWords.append(LyricWord(text: refW, start: start + 0.1, end: start + 0.4))
                }
            }
            
            if !lineWords.isEmpty {
                alignedLines.append(LyricLine(time: lineWords.first!.start, text: refLine, words: lineWords))
            }
        }
        
        return ParsedLyrics(lines: alignedLines, isSynced: true)
    }
    
    private static func clean(_ word: String) -> String {
        return word.lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
    }
}
