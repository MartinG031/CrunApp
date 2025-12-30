import Foundation
import UIKit

protocol QwenServicing {
    func analyzeScreen(screenshot: UIImage?, instruction: String) async throws -> String
    func followUp(initialSummary: String, history: [ChatMessage]) async throws -> String
    func warmUp() async
}

final class QwenClient: QwenServicing {
    static let shared = QwenClient()

    // MARK: - Config (DashScope OpenAI Compatible Mode)
    private let baseURL: URL = URL(string: "https://dashscope.aliyuncs.com/compatible-mode")!

    /// /v1/chat/completions
    private lazy var chatCompletionsURL: URL = baseURL.appendingPathComponent("v1/chat/completions")

    /// /v1/models (用于 warmUp，可选)
    private lazy var modelsURL: URL = baseURL.appendingPathComponent("v1/models")

    /// 与 Xcode Intelligence Provider 截图一致：Authorization
    private let apiKeyHeaderField = "Authorization"

    /// 建议在 Info.plist 配置：ALIYUNCS_API_KEY（或沿用你原来的 DASHSCOPE_API_KEY）
    /// - 如果你在 Xcode Intelligence 里 API Key 字段填的是“裸 key”，这里会自动补上 "Bearer "
    /// - 如果你填的是“Bearer xxxxxx”，这里不会重复添加
    private func authorizationValue() throws -> String {
        let key = try apiKeyOrThrow().trimmingCharacters(in: .whitespacesAndNewlines)
        if key.lowercased().hasPrefix("bearer ") { return key }
        return "Bearer \(key)"
    }

    private func apiKeyOrThrow() throws -> String {
        // 你可以只留一个；我这里做了兼容：ALIYUNCS_API_KEY 优先，其次 DASHSCOPE_API_KEY
        if let v = Bundle.main.object(forInfoDictionaryKey: "ALIYUNCS_API_KEY") as? String, !v.isEmpty {
            return v
        }
        if let v = Bundle.main.object(forInfoDictionaryKey: "DASHSCOPE_API_KEY") as? String, !v.isEmpty {
            return v
        }

        throw NSError(
            domain: "QwenClient",
            code: -1000,
            userInfo: [NSLocalizedDescriptionKey: "API Key 未配置：请在 Info.plist 配置 ALIYUNCS_API_KEY（或 DASHSCOPE_API_KEY）"]
        )
    }

    /// 让 model 名称与你 Xcode Intelligence Provider 的 Models.Identifier 对齐（例如：codeqwen1.5-7b-chat）
    /// - 你可以在 Info.plist 配置：ALIYUNCS_VISION_MODEL / ALIYUNCS_CHAT_MODEL
    private var visionModel: String {
        (Bundle.main.object(forInfoDictionaryKey: "ALIYUNCS_VISION_MODEL") as? String).nonEmpty
        ?? "qwen-vl-plus"
    }

    private var chatModel: String {
        (Bundle.main.object(forInfoDictionaryKey: "ALIYUNCS_CHAT_MODEL") as? String).nonEmpty
        ?? "codeqwen1.5-7b-chat"
    }

    // MARK: - Public

    func warmUp() async {
        // 目的：提前触发 TLS / DNS / 网络栈 warm，失败也不影响主流程
        var req = URLRequest(url: modelsURL)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            req.setValue(try authorizationValue(), forHTTPHeaderField: apiKeyHeaderField)
            _ = try await URLSession.shared.data(for: req)
        } catch {
            // 忽略 warmUp 失败
        }
    }

    func analyzeScreen(screenshot: UIImage?, instruction: String) async throws -> String {
        let imageURL = try screenshot.flatMap { try Self.toDataURL($0) } // OpenAI compatible: image_url 支持 data URL
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
            model: visionModel,
            messages: [
                .init(role: "system", content: [.init(type: "text", text: systemPrompt, image_url: nil)]),
                .init(role: "user", content: userContent)
            ],
            temperature: 0.2
        )

        return try await sendChatCompletion(payload: payload)
    }

    func followUp(initialSummary: String, history: [ChatMessage]) async throws -> String {
        // 将你的 ChatMessage 映射为 OpenAI compatible messages
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
            model: chatModel,
            messages: messages,
            temperature: 0.4
        )

        return try await sendChatCompletion(payload: payload)
    }

    // MARK: - Networking

    private func sendChatCompletion(payload: ChatCompletionRequest) async throws -> String {
        var req = URLRequest(url: chatCompletionsURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(try authorizationValue(), forHTTPHeaderField: apiKeyHeaderField)

        let body = try JSONEncoder().encode(payload)
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "QwenClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效响应"])
        }
        guard (200...299).contains(http.statusCode) else {
            let serverText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "QwenClient",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "服务端错误(\(http.statusCode))：\(serverText)"]
            )
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let text = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text
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

    // MARK: - Helpers

    private static func toDataURL(_ image: UIImage) throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw NSError(domain: "QwenClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "截图编码失败"])
        }
        let b64 = data.base64EncodedString()
        return "data:image/jpeg;base64,\(b64)"
    }
}

// MARK: - Convenience Extensions

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let s = self?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}

// 你项目里 ChatMessage 的 role 可能是 enum（例如 .user / .assistant / .system）
// 这里给一个最常见的映射：若你的命名不同，改这一个扩展即可。
private extension ChatMessage.Role {
    var openAIRoleString: String {
        switch self {
        case .user: return "user"
        case .assistant: return "assistant"
        }
    }
}
