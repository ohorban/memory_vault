import Foundation

/// Calls the Claude Messages API directly over HTTPS (there is no official Swift SDK).
struct ClaudeClient: LLMClient {
    let apiKey: String
    let model: String
    var session: URLSession = .shared

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let retryableStatuses: Set<Int> = [408, 409, 429, 500, 502, 503, 504, 529]

    func complete(_ request: LLMRequest) async throws -> String {
        var systemBlocks: [[String: Any]] = [["type": "text", "text": request.system]]
        if let context = request.context, !context.isEmpty {
            var block: [String: Any] = ["type": "text", "text": context]
            block["cache_control"] = ["type": "ephemeral"]
            systemBlocks.append(block)
        }

        var outputConfig: [String: Any] = ["effort": request.effort.rawValue]
        if let schemaText = request.jsonSchema {
            let schema = try JSONSerialization.jsonObject(with: Data(schemaText.utf8))
            var format: [String: Any] = ["type": "json_schema"]
            format["schema"] = schema
            outputConfig["format"] = format
        }

        var body: [String: Any] = [:]
        body["model"] = model
        body["max_tokens"] = request.maxTokens
        body["system"] = systemBlocks
        body["messages"] = [["role": "user", "content": request.prompt]]
        body["output_config"] = outputConfig

        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 180
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(urlRequest)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(MessagesResponse.self, from: data)

        switch response.stopReason {
        case "refusal": throw LLMError.refusal
        case "max_tokens": throw LLMError.truncated
        default: break
        }
        // Content can start with thinking blocks; only text blocks are the answer.
        let text = response.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        guard !text.isEmpty else { throw LLMError.emptyResponse }
        return text
    }

    private func send(_ request: URLRequest, attempt: Int = 0) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return data }

        if Self.retryableStatuses.contains(status), attempt < 2 {
            let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "retry-after").flatMap { Double($0) }
            let delay = min(retryAfter ?? pow(2, Double(attempt + 1)), 20)
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            return try await send(request, attempt: attempt + 1)
        }

        let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message
            ?? String(data: data, encoding: .utf8) ?? "Unknown error"
        throw LLMError.http(status: status, message: message)
    }

    private struct MessagesResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stopReason: String?
    }

    private struct ErrorResponse: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }
}
