import Foundation

/// Two Groq calls on OpenAI-compatible endpoints:
/// 1. Whisper Large v3 Turbo for transcription.
/// 2. A fast chat model that rewrites the raw transcript into clean, final text.
struct GroqClient {
    enum ClientError: LocalizedError {
        case http(Int, String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case let .http(code, body): return "Groq HTTP \(code): \(body)"
            case .badResponse: return "Unexpected response from Groq"
            }
        }
    }

    let config: Config
    private let base = "https://api.groq.com/openai/v1"
    private let session = URLSession.shared

    func transcribe(fileURL: URL) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "\(base)/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.groqApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let audio = try Data(contentsOf: fileURL)
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        body.appendString("Content-Type: audio/wav\r\n\r\n")
        body.append(audio)
        body.appendString("\r\n")
        appendField("model", config.transcriptionModel, to: &body, boundary: boundary)
        appendField("response_format", "text", to: &body, boundary: boundary)
        if let language = config.language, !language.isEmpty {
            appendField("language", language, to: &body, boundary: boundary)
        }
        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try Self.check(response, data)
        guard let text = String(data: data, encoding: .utf8) else { throw ClientError.badResponse }
        return text
    }

    func cleanup(transcript: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(base)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.groqApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": config.cleanupModel,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": config.systemPrompt],
                ["role": "user", "content": transcript]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        try Self.check(response, data)
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = object["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw ClientError.badResponse }
        return content
    }

    private func appendField(_ name: String, _ value: String, to body: inout Data, boundary: String) {
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.appendString("\(value)\r\n")
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ClientError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}

private extension Data {
    mutating func appendString(_ s: String) {
        if let d = s.data(using: .utf8) { append(d) }
    }
}
