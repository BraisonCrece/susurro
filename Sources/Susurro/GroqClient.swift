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
        var request = makeRequest(path: "audio/transcriptions",
                                  contentType: "multipart/form-data; boundary=\(boundary)")

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

        let data = try await send(request)
        guard let text = String(data: data, encoding: .utf8) else { throw ClientError.badResponse }
        return text
    }

    func cleanup(transcript: String, context: String?) async throws -> String {
        var request = makeRequest(path: "chat/completions", contentType: "application/json")
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: config.cleanupModel,
            temperature: 0.1,
            messages: [
                .init(role: "system", content: PromptBuilder.systemPrompt(config: config, context: context)),
                .init(role: "user", content: transcript)
            ]
        ))

        let data = try await send(request)
        guard let reply = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = reply.choices.first?.message.content
        else { throw ClientError.badResponse }
        return content
    }

    // MARK: - Wire types

    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let temperature: Double
        let messages: [Message]
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String }

        let choices: [Choice]
    }

    // MARK: - Plumbing

    private func makeRequest(path: String, contentType: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(base)/\(path)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.groqApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func appendField(_ name: String, _ value: String, to body: inout Data, boundary: String) {
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.appendString("\(value)\r\n")
    }
}

private extension Data {
    mutating func appendString(_ s: String) {
        if let d = s.data(using: .utf8) { append(d) }
    }
}
