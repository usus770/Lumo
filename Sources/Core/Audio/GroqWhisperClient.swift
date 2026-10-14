import Foundation

public struct GroqWhisperResponse: Decodable, Sendable {
    public let text: String
    public let words: [WhisperWord]?
    public let segments: [WhisperSegment]?
    
    public struct WhisperWord: Decodable, Sendable {
        public let word: String
        public let start: TimeInterval
        public let end: TimeInterval
    }
    
    public struct WhisperSegment: Decodable, Sendable {
        public let id: Int
        public let start: TimeInterval
        public let end: TimeInterval
        public let text: String
        public let tokens: [Int]
        public let temperature: Double
        public let avg_logprob: Double
        public let compression_ratio: Double
        public let no_speech_prob: Double
    }
}

public actor GroqWhisperClient {
    public static let shared = GroqWhisperClient()
    
    private var isTranscribing = false
    
    private init() {}
    
    public func transcribe(audioData: Data, language: String = "Auto", model: String = "whisper-large-v3-turbo") async throws -> GroqWhisperResponse {
        guard let apiKey = GroqKeychain.getKey(), !apiKey.isEmpty else {
            throw NSError(domain: "GroqWhisper", code: 401, userInfo: [NSLocalizedDescriptionKey: "No API Key found"])
        }
        
        guard !isTranscribing else {
            throw NSError(domain: "GroqWhisper", code: 429, userInfo: [NSLocalizedDescriptionKey: "Already transcribing"])
        }
        
        isTranscribing = true
        defer { isTranscribing = false }
        
        let url = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Model
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)
        
        // Response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("verbose_json\r\n".data(using: .utf8)!)
        
        // Timestamp granularities
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"timestamp_granularities[]\"\r\n\r\n".data(using: .utf8)!)
        body.append("word\r\n".data(using: .utf8)!)
        
        // Language
        if language != "Auto" {
            let langCode = languageCode(for: language)
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(langCode)\r\n".data(using: .utf8)!)
        }
        
        // File
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode != 200 {
                let errStr = String(data: data, encoding: .utf8) ?? "Unknown Error"
                throw NSError(domain: "GroqWhisper", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(errStr)"])
            }
        }
        
        return try JSONDecoder().decode(GroqWhisperResponse.self, from: data)
    }
    
    private func languageCode(for string: String) -> String {
        switch string {
        case "English": return "en"
        case "Hindi": return "hi"
        case "Punjabi": return "pa"
        case "Korean": return "ko"
        case "Japanese": return "ja"
        case "Spanish": return "es"
        case "French": return "fr"
        case "German": return "de"
        default: return "en"
        }
    }
}
