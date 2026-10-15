import Foundation

enum TranscriptionError: LocalizedError {
    case missingAPIKey
    case http(status: Int, message: String)
    case empty

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add your OpenAI API key in Settings to record by voice."
        case let .http(status, message): "Transcription failed (\(status)): \(message)"
        case .empty: "No speech was detected in the recording."
        }
    }
}

/// Speech-to-text via OpenAI's audio transcription endpoint. Returns the transcript verbatim.
struct TranscriptionService {
    let apiKey: String
    let model: String
    var session: URLSession = .shared

    private static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    static func makeDefault() throws -> TranscriptionService {
        guard let key = Keychain.read(.openAI) else { throw TranscriptionError.missingAPIKey }
        return TranscriptionService(apiKey: key, model: AppSettings.transcriptionModel)
    }

    /// - Parameter vocabulary: Names that may appear (helps spell people correctly).
    func transcribe(fileURL: URL, vocabulary: [String] = []) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        field("model", model)
        field("response_format", "json")
        if !vocabulary.isEmpty {
            let names = vocabulary.prefix(150).joined(separator: ", ")
            field("prompt", "A personal story told out loud. Names that may come up: \(names).")
        }

        let audio = try Data(contentsOf: fileURL)
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"memory.m4a\"\r\n".utf8))
        body.append(Data("Content-Type: audio/m4a\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message
                ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.http(status: status, message: message)
        }
        let text = try JSONDecoder().decode(TranscriptionResponse.self, from: data).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscriptionError.empty }
        return text
    }

    private struct TranscriptionResponse: Decodable { let text: String }

    private struct ErrorResponse: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }
}
