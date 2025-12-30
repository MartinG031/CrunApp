import Foundation
import UIKit

protocol QwenServicing {
    func analyzeScreen(screenshot: UIImage?, instruction: String) async throws -> String
    func followUp(initialSummary: String, history: [ChatMessage]) async throws -> String
    func warmUp()
}

/// 虽然类名叫 QwenClient，但实现为“OpenAI-compatible 通用客户端”
/// 只要 Base URL 提供 /v1/chat/completions，且模型名匹配即可切换非 Qwen。
final class QwenClient: QwenServicing {
    static let shared = QwenClient()

    // MARK: - Settings Keys
    private enum SettingsKey {
        static let providerBaseURL = "provider_base_url"
        static let providerTextModel = "provider_text_model"
        static let providerVisionModel = "provider_vision_model"
    }

    // MARK: - Defaults
    private let defaultBaseURL = "https://dashscope.aliyuncs.com/compatible-mode"
    private let defaultTextModel = "qwen-plus"
    private let defaultVisionModel = "qwen3-vl-plus"

    private init() {}

    // MARK: - Config getters

    private func baseURLString() -> String {
        let v = (UserDefaults.standard.string(forKey: SettingsKey.providerBaseURL) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? defaultBaseURL : v
    }

    private func textModelID() -> String {
        let v = (UserDefaults.standard.string(forKey: SettingsKey.providerTextModel) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? defaultTextModel : v
    }

    private func visionModelID() -> String {
        let v = (UserDefaults.standard.string(forKey: SettingsKey.providerVisionModel) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? defaultVisionModel : v
    }

    private func chatCompletionsURL() throws -> URL {
        var base = baseURLString().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            throw NSError(domain: "LLMClient", code: -1001, userInfo: [
                NSLocalizedDescriptionKey: "Base URL 为空，请在设置中填写。"
            ])
        }

        while base.hasSuffix("/") { base.removeLast() }

        // 支持用户填：
        // - https://api.xxx.com/v1  -> /v1/chat/completions
        // - https://api.xxx.com     -> /v1/chat/completions
        // - https://dashscope.aliyuncs.com/compatible-mode -> /v1/chat/completions
        let urlString: String
        if base.hasSuffix("/v1") {
            urlString = base + "/chat/completions"
        } else {
            urlString = base + "/v1/chat/completions"
        }

        guard let url = URL(string: urlString) else {
            throw NSError(domain: "LLMClient", code: -1002, userInfo: [
                NSLocalizedDescriptionKey: "Base URL 无法解析：\(urlString)"
            ])
        }
        return url
    }

    private func apiKeyOrThrow() throws -> String {
        // 1) 优先 Keychain（设置页保存的）
        if let key = KeychainStore.readAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty {
            return key
        }

        // 2) 可选：回退 Info.plist（兼容旧方式）
        if let key = Bundle.main.object(forInfoDictionaryKey: "DASHSCOPE_API_KEY") as? String,
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }

        throw NSError(domain: "LLMClient", code: -1000, userInfo: [
            NSLocalizedDescriptionKey: "API Key 未配置。请在设置中保存 API Key（或在 Info.plist 配置 DASHSCOPE_API_KEY）。"
        ])
    }

    // MARK: - OpenAI-compatible payload

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
    }

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }

    // MARK: - Public APIs

    func analyzeScreen(screenshot: UIImage?, instruction: String) async throws -> String {
        var contents: [ChatCompletionRequest.Message.ContentItem] = []

        let hasImage = (screenshot != nil)

        let userText: String
        if instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userText = """
            你现在是一个屏幕助手。当前 hasImage = \(hasImage ? "有图" : "无图")。
            如果有图，请先通读截图中的所有文字和界面元素，并按以下要求输出：

            1.【内容翻译】
              - 只要存在成段的非中文内容，优先完整翻译为简体中文（按模块/段落）。
              - 如果没有识别到需要翻译的内容，则完全省略此小节，不要输出“无需翻译”等说明。

            2.【总结与建议】
              - 1–2 句话概括当前屏幕在做什么。
              - 对报错/问题/待办/选项对比给出具体建议。

            3.【号码识别（如适用）】
              - 若出现电话号码/来电界面，列出号码并判断可能类型及建议。
              - 若无号码，省略此小节。

            【总结与建议】放到最后。
            """
        } else {
            userText = """
            你现在是一个屏幕助手。当前 hasImage = \(hasImage ? "有图" : "无图")。
            请结合截图内容，按以下指令分析：\(instruction)

            在分析前：
            - 若存在成段非中文内容，需先完整翻译为简体中文（按模块/段落）。
            - 若无非中文内容，则省略翻译小节，不要解释流程。

            输出建议使用“内容翻译 / 分析与结论 / 建议”等分节。
            """
        }

        contents.append(.init(type: "text", text: userText, image_url: nil))

        if let screenshot,
           let data = screenshot.jpegData(compressionQuality: 0.7) {
            let base64 = data.base64EncodedString()
            contents.append(.init(
                type: "image_url",
                text: nil,
                image_url: .init(url: "data:image/jpeg;base64,\(base64)")
            ))
        }

        let message = ChatCompletionRequest.Message(role: "user", content: contents)
        let modelID = hasImage ? visionModelID() : textModelID()

        let requestBody = ChatCompletionRequest(model: modelID, messages: [message])

        let data = try await sendRequest(body: requestBody)
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        guard let first = response.choices.first?.message.content, !first.isEmpty else {
            throw NSError(domain: "LLMClient", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "没有收到模型回复。"
            ])
        }
        return first
    }

    func followUp(initialSummary: String, history: [ChatMessage]) async throws -> String {
        var context = "下面是用户当前屏幕的总结：\n\(initialSummary)\n\n以下是此前的对话记录：\n"
        for msg in history {
            switch msg.role {
            case .user:
                context += "用户：\(msg.text)\n"
            case .assistant:
                context += "助手：\(msg.text)\n"
            }
        }
        context += "\n请基于以上内容，用清晰的中文回答用户的最新一句话。"

        let contents: [ChatCompletionRequest.Message.ContentItem] = [
            .init(type: "text", text: context, image_url: nil)
        ]
        let message = ChatCompletionRequest.Message(role: "user", content: contents)

        let requestBody = ChatCompletionRequest(model: textModelID(), messages: [message])

        let data = try await sendRequest(body: requestBody)
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        guard let first = response.choices.first?.message.content, !first.isEmpty else {
            throw NSError(domain: "LLMClient", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "没有收到模型回复。"
            ])
        }
        return first
    }

    func warmUp() {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            guard await (try? self.apiKeyOrThrow()) != nil else { return }

            let ping = ChatCompletionRequest.Message.ContentItem(
                type: "text",
                text: "你好，请简单回复“OK”即可，用于预热服务。",
                image_url: nil
            )
            let message = ChatCompletionRequest.Message(role: "user", content: [ping])

            let requestBody = await ChatCompletionRequest(model: self.textModelID(), messages: [message])
            do { _ = try await self.sendRequest(body: requestBody) } catch { }
        }
    }

    // MARK: - Networking

    private func sendRequest(body: ChatCompletionRequest) async throws -> Data {
        let endpoint = try chatCompletionsURL()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let apiKey = try apiKeyOrThrow()
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "未知错误"
            throw NSError(domain: "LLMClient", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
        return data
    }
}
