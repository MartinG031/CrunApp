import Foundation
import UIKit

protocol QwenServicing {
    func analyzeScreen(screenshot: UIImage?, instruction: String) async throws -> String
    func followUp(initialSummary: String, history: [ChatMessage]) async throws -> String
    func warmUp() async
}

final class QwenClient: QwenServicing {
    static let shared = QwenClient()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()

    private static let jsonEncoder: JSONEncoder = {
        JSONEncoder()
    }()

    private static let jsonDecoder: JSONDecoder = {
        JSONDecoder()
    }()

    // MARK: - Provider Config (只保留 URL + API)

    private struct ProviderConfig {
        let baseURL: URL
        let authorization: String

        var chatCompletionsURL: URL { baseURL.appendingPathComponent("v1/chat/completions") }
        var modelsURL: URL { baseURL.appendingPathComponent("v1/models") }
    }

    // 默认使用 Qwen（不在设置中暴露模型选择）
    private let defaultChatModel = "qwen-plus"
    private let defaultVisionModel = "qwen-vl-plus"

    private let apiKeyHeaderField = "Authorization"

    private func providerConfig() throws -> ProviderConfig {
        let rawBase = UserDefaults.standard.string(forKey: "provider_base_url")
        let normalizedBase = normalizeBaseURL(rawBase) ?? "https://dashscope.aliyuncs.com/compatible-mode"
        let baseURL = URL(string: normalizedBase) ?? URL(string: "https://dashscope.aliyuncs.com/compatible-mode")!

        let apiKey = try apiKeyOrThrow().trimmingCharacters(in: .whitespacesAndNewlines)
        let authorization = apiKey.lowercased().hasPrefix("bearer ") ? apiKey : "Bearer \(apiKey)"

        return ProviderConfig(baseURL: baseURL, authorization: authorization)
    }

    private func apiKeyOrThrow() throws -> String {
        // 1) Keychain（设置页保存的）
        if let v = KeychainStore.readAPIKey(),
           !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return v
        }

        // 2) 可选：Info.plist（仅建议本机调试；不要提交真实 key）
        if let v = Bundle.main.object(forInfoDictionaryKey: "DASHSCOPE_API_KEY") as? String,
           !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return v
        }

        throw NSError(
            domain: "QwenClient",
            code: -1000,
            userInfo: [NSLocalizedDescriptionKey: "API Key 未配置：请在设置中填写 API Key"]
        )
    }

    private func normalizeBaseURL(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        // 用户误填 /v1 或 /v1/ 时自动剥离
        if s.hasSuffix("/v1") { s.removeLast(3) }
        else if s.hasSuffix("/v1/") { s.removeLast(4) }
        // 去掉末尾多余斜杠
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    // MARK: - Public

    func warmUp() async {
        // warmUp 失败不影响主流程
        do {
            let cfg = try providerConfig()
            var req = URLRequest(url: cfg.modelsURL)
            req.httpMethod = "GET"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(cfg.authorization, forHTTPHeaderField: apiKeyHeaderField)
            _ = try await session.data(for: req)
        } catch { }
    }

    func analyzeScreen(screenshot: UIImage?, instruction: String) async throws -> String {
        let cfg = try providerConfig()
        let imageURL = try screenshot.flatMap { try Self.toDataURL($0) }

        let systemPrompt =
        """
        你是一个iOS助手。请根据用户给定的指令，结合截图内容进行识别与总结。要求：结构化输出，先给摘要，再给要点。
        """

        let userContent: [ChatCompletionRequest.Message.ContentItem] = {
            if let imageURL {
                return [
                    .init(type: "text", text: instruction, image_url: nil),
                    .init(type: "image_url", text: nil, image_url: .init(url: imageURL))
                ]
            } else {
                return [
                    .init(type: "text", text: instruction, image_url: nil)
                ]
            }
        }()

        let payload = ChatCompletionRequest(
            model: (screenshot == nil ? defaultChatModel : defaultVisionModel),
            messages: [
                .init(role: "system", content: [.init(type: "text", text: systemPrompt, image_url: nil)]),
                .init(role: "user", content: userContent)
            ],
            temperature: 0.2
        )

        return try await sendChatCompletion(payload: payload, cfg: cfg)
    }

    func followUp(initialSummary: String, history: [ChatMessage]) async throws -> String {
        let cfg = try providerConfig()

        let systemPrompt =
        """
        你是一个对话助手。用户在基于“initialSummary”继续追问。你需要结合 initialSummary 与历史对话，给出简洁、直接、可执行的回答。
        """

        var messages: [ChatCompletionRequest.Message] = [
            .init(role: "system", content: [.init(type: "text", text: systemPrompt, image_url: nil)]),
            .init(role: "system", content: [.init(type: "text", text: "initialSummary: \(initialSummary)", image_url: nil)])
        ]

        messages.append(contentsOf: history.map { msg in
            .init(
                role: msg.role.openAIRoleString,
                content: [.init(type: "text", text: msg.text, image_url: nil)]
            )
        })

        let payload = ChatCompletionRequest(
            model: defaultChatModel,
            messages: messages,
            temperature: 0.4
        )

        return try await sendChatCompletion(payload: payload, cfg: cfg)
    }

    // MARK: - Networking

    private func sendChatCompletion(payload: ChatCompletionRequest, cfg: ProviderConfig) async throws -> String {
        var req = URLRequest(url: cfg.chatCompletionsURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(cfg.authorization, forHTTPHeaderField: apiKeyHeaderField)

        let body = try Self.jsonEncoder.encode(payload)
        req.httpBody = body

        let (data, resp) = try await session.data(for: req)

        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "QwenClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效响应"])
        }

        guard (200...299).contains(http.statusCode) else {
            let serverText = String(data: data, encoding: .utf8) ?? ""

            if let apiError = try? Self.jsonDecoder.decode(APIErrorResponse.self, from: data),
               let message = apiError.error.message?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                throw NSError(
                    domain: "QwenClient",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "服务端错误(\(http.statusCode))：\(message)"]
                )
            }

            throw NSError(
                domain: "QwenClient",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "服务端错误(\(http.statusCode))：\(serverText)"]
            )
        }

        let decoded = try Self.jsonDecoder.decode(ChatCompletionResponse.self, from: data)
        return decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Models (OpenAI Compatible)

    private struct ChatCompletionRequest: Encodable {
        struct Message: Encodable {
            struct ContentItem: Encodable {
                struct ImageURL: Encodable { let url: String }

                let type: String
                let text: String?
                let image_url: ImageURL?
            }

            let role: String
            let content: [ContentItem]
        }

        let model: String
        let messages: [Message]
        let temperature: Double?
    }

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct APIErrorResponse: Decodable {
        struct APIError: Decodable {
            let message: String?
        }
        let error: APIError
    }

    private static func toDataURL(_ image: UIImage) throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw NSError(domain: "QwenClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "截图编码失败"])
        }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }
}

// 仅用于把你项目里的 ChatMessage.Role 映射到 OpenAI 兼容 role 字符串。
// 若你的 enum case 名不同，只改这里即可。
private extension ChatMessage.Role {
    var openAIRoleString: String {
        switch self {
        case .user: return "user"
        case .assistant: return "assistant"
        }
    }
}
