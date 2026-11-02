import Foundation

/// User-supplied AI endpoint (any OpenAI-compatible gateway).
/// Plain UserDefaults reads: the settings UI owns the bindings, this type only
/// resolves current values at call time.
final class AISettings {
    static let shared = AISettings()

    private let defaults = UserDefaults.standard

    var baseURL: String {
        get { defaults.string(forKey: "ai.baseURL") ?? "https://api.openai.com/v1" }
        set { defaults.set(newValue, forKey: "ai.baseURL") }
    }

    var apiKey: String {
        get { defaults.string(forKey: "ai.apiKey") ?? "" }
        set { defaults.set(newValue, forKey: "ai.apiKey") }
    }

    var model: String {
        get { defaults.string(forKey: "ai.model") ?? "gpt-4o-mini" }
        set { defaults.set(newValue, forKey: "ai.model") }
    }

    var ttsModel: String {
        get { defaults.string(forKey: "ai.ttsModel") ?? "gpt-4o-mini-tts" }
        set { defaults.set(newValue, forKey: "ai.ttsModel") }
    }

    var ttsVoice: String {
        get { defaults.string(forKey: "ai.ttsVoice") ?? "alloy" }
        set { defaults.set(newValue, forKey: "ai.ttsVoice") }
    }

    var targetLang: String {
        get { defaults.string(forKey: "ai.targetLang") ?? "中文" }
        set { defaults.set(newValue, forKey: "ai.targetLang") }
    }

    var useCloudTTS: Bool {
        get { defaults.bool(forKey: "ai.useCloudTTS") }
        set { defaults.set(newValue, forKey: "ai.useCloudTTS") }
    }

    var isConfigured: Bool { !apiKey.isEmpty && !baseURL.isEmpty }

    private func endpoint(_ path: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + path)
    }

    // MARK: - chat / translation

    func translate(_ text: String) async throws -> String {
        try await chat("""
        把下面的德语文本翻译成\(targetLang)，只输出译文，不要解释、不要加引号：
        \(text)
        """)
    }

    func explain(_ text: String) async throws -> String {
        try await chat("""
        用\(targetLang)解释这句德语，分三行：1) 直译 2) 语法要点 3) 更自然的说法。原句：
        \(text)
        """)
    }

    private func chat(_ prompt: String) async throws -> String {
        guard let url = endpoint("/chat/completions") else { throw AIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.2,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.badResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - TTS

    func synthesize(_ text: String) async throws -> Data {
        guard let url = endpoint("/audio/speech") else { throw AIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90
        let body: [String: Any] = [
            "model": ttsModel,
            "voice": ttsVoice,
            "input": text,
            "response_format": "mp3",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)
        guard !data.isEmpty else { throw AIError.badResponse }
        return data
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data.prefix(400), encoding: .utf8) ?? ""
            throw AIError.http(http.statusCode, text)
        }
    }
}

enum AIError: LocalizedError {
    case badURL
    case badResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "接口地址不合法"
        case .badResponse: return "返回内容无法解析"
        case .http(let code, let text): return "HTTP \(code)：\(text)"
        }
    }
}
