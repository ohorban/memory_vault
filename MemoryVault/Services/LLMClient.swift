import Foundation

/// How hard the model should think. Maps to Claude's `output_config.effort`.
enum LLMEffort: String {
    case low, medium, high
}

/// A provider-neutral request. Swap the provider by adding another `LLMClient`
/// and returning it from `LLMFactory`; nothing else in the app needs to change.
struct LLMRequest {
    /// Instructions for the model.
    var system: String
    /// Large, stable reference material (e.g. all your memories). Cached when the provider supports it.
    var context: String?
    /// The actual question or task.
    var prompt: String
    var maxTokens: Int = 4096
    var effort: LLMEffort = .low
    /// A JSON Schema (as a JSON string). When set, the response text is guaranteed to match it.
    var jsonSchema: String?
}

protocol LLMClient {
    func complete(_ request: LLMRequest) async throws -> String
}

enum LLMError: LocalizedError {
    case missingAPIKey
    case http(status: Int, message: String)
    case refusal
    case truncated
    case emptyResponse
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your Anthropic API key in Settings to use AI features."
        case let .http(status, message):
            "AI request failed (\(status)): \(message)"
        case .refusal:
            "The AI declined to process this request."
        case .truncated:
            "The AI response was cut off. Try again."
        case .emptyResponse:
            "The AI returned an empty response."
        case let .invalidJSON(detail):
            "Couldn't read the AI response: \(detail)"
        }
    }
}

extension LLMClient {
    func completeJSON<T: Decodable>(_ request: LLMRequest, as type: T.Type) async throws -> T {
        let text = try await complete(request)
        var jsonText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Defensive: tolerate stray prose or code fences around the object.
        if let start = jsonText.firstIndex(of: "{"), let end = jsonText.lastIndex(of: "}"), start < end {
            jsonText = String(jsonText[start...end])
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(T.self, from: Data(jsonText.utf8))
        } catch {
            throw LLMError.invalidJSON(error.localizedDescription)
        }
    }
}

enum LLMFactory {
    /// Today this always returns Claude. To try another provider, add a client and branch here.
    static func makeClient() throws -> any LLMClient {
        guard let key = Keychain.read(.anthropic) else { throw LLMError.missingAPIKey }
        return ClaudeClient(apiKey: key, model: AppSettings.claudeModel)
    }
}
