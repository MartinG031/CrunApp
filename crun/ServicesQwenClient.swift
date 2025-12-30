import Foundation
import UIKit

protocol QwenServicing {
    func analyzeScreen(screenshot: UIImage?, instruction: String) async throws -> String
    func followUp(initialSummary: String, history: [ChatMessage]) async throws -> String
    func warmUp()
}

final class QwenClient {
    static let shared = QwenClient()

    // 使用百炼（通义千问）控制台中的 DASHSCOPE_API_KEY。
    private func apiKeyOrThrow() throws -> String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "DASHSCOPE_API_KEY") as? String,
              !key.isEmpty
        else {
            throw NSError(
                domain: "QwenClient",
                code: -1000,
                userInfo: [NSLocalizedDescriptionKey: "DASHSCOPE_API_KEY 未配置，请在 Info.plist 中设置"]
            )
        }
        return key
    }

    // 北京地域 OpenAI 兼容模式 Chat 接口
    private let endpoint = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!

    private struct ChatCompletionRequest: Encodable {
        struct Message: Encodable {
            struct ContentItem: Encodable {
                struct ImageURL: Encodable {
                    let url: String
                }

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
            struct Message: Decodable {
                let content: String
            }
            let message: Message
        }
        let choices: [Choice]
    }

    /// 首次分析：基于截图 + 指令生成总结
    func analyzeScreen(screenshot: UIImage?, instruction: String) async throws -> String {
        var contents: [ChatCompletionRequest.Message.ContentItem] = []

        let hasImage = (screenshot != nil)

        let userText: String
        if instruction.isEmpty {
            userText = """
            你现在是一个屏幕助手。当前 hasImage = \(hasImage ? "有图" : "无图")。
            如果有图，请先通读截图中的所有文字和界面元素，按以下要求回答：

            1. 【内容翻译】
               - 只要屏幕上存在成段的非中文内容（例如英文新闻、英文 App 界面、英文邮件等），无论是否同时还有中文，都要优先将这些非中文内容完整翻译为简体中文。
               - 可以按段落或模块依次翻译，保持原有层次结构，方便用户对照阅读。
               - 只有在你几乎看不到任何非中文句子或段落时，才可以省略这一小节。
               - 严禁只给出总结而不翻译原文，也不要输出诸如“没有需要翻译的内容”“以下内容无需翻译”“原文已是中文，无需翻译”等句子。
               - 如果你没有识别到需要翻译的，就直接略过本部分，完全省略此部分不显示任何内容。

            2. 【总结与建议】
               - 用 1–2 句话概括当前屏幕在做什么。
               - 如果画面中包含明显的问题、提问、报错信息、警告、待办事项、选项对比等，请直接用中文给出具体的回答或建议，而不是只做转述。尽量用“简要总结 + 具体建议/回答”的结构输出。

            3. 【号码识别（如适用）】
               - 如果截图中出现电话号码、来电界面或通话记录，请额外：
                 • 明确写出你能识别到的主要电话号码；
                 • 判断这些号码更可能是哪一类（例如：正常联系人、快递/外卖、客服、营销/骚扰、诈骗等），并简要说明原因；
                 • 给出 1–2 句对用户的建议（例如是否需要谨慎对待或可以标记为骚扰电话）。
               - 如果你没有识别到任何电话号码，就直接略过本部分，完全省略此部分不显示任何内容。

            如果没有图，就只根据我提供的文字内容进行回答。对于非中文内容，同样先将关键文字完整翻译成简体中文（放在“内容翻译”部分），然后再给出“总结与建议”；如果内容本身已经是中文，就可以省略翻译部分，直接用中文简洁回答。

            【总结与建议】放到最后一部分。
            """
        } else {
            userText = """
            你现在是一个屏幕助手。当前 hasImage = \(hasImage ? "有图" : "无图")。
            如果有图，请结合截图内容，按照以下指令完成分析：\(instruction)

            在执行指令前，请先处理语言问题：
            1. 只要截图中存在成段的非中文内容（例如英文新闻、英文网页、英文 App 界面等），无论是否同时还有中文，都要优先将这些非中文内容完整翻译为简体中文，可以按段或按模块列出。
            2. 只有当你几乎看不到任何非中文句子或段落时，才可以省略翻译步骤。
            3. 严禁只给出分析结果而不翻译原文，也不要输出诸如“没有需要翻译的内容”“以下内容无需翻译”“原文已是中文，无需翻译”等句子。

            完成翻译后，再根据用户指令，用清晰的中文给出结构化回答。可以使用“内容翻译”“分析与结论”“建议”这样的分节标题，帮助用户快速理解。
            如果没有图，就只根据我提供的文字内容完成以上指令；对于非中文内容，同样需要先翻译成简体中文，再给出分析；如果内容已经是中文，就不要解释翻译流程，直接回答。
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

        let requestBody = ChatCompletionRequest(
            model: "qwen3-vl-plus",
            messages: [message]
        )

        let data = try await sendRequest(body: requestBody)
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        guard let first = response.choices.first?.message.content, !first.isEmpty else {
            throw NSError(
                domain: "QwenClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "没有收到模型回复。"]
            )
        }
        return first
    }

    /// 继续对话：基于初始总结 + 历史对话生成新的回复
    func followUp(initialSummary: String, history: [ChatMessage]) async throws -> String {
        var contents: [ChatCompletionRequest.Message.ContentItem] = []

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

        contents.append(.init(type: "text", text: context, image_url: nil))

        let message = ChatCompletionRequest.Message(role: "user", content: contents)

        let requestBody = ChatCompletionRequest(
            model: "qwen-plus",
            messages: [message]
        )

        let data = try await sendRequest(body: requestBody)
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        guard let first = response.choices.first?.message.content, !first.isEmpty else {
            throw NSError(
                domain: "QwenClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "没有收到模型回复。"]
            )
        }
        return first
    }

    /// 轻量预热：在后台发起一次极小的请求，提前完成 TLS 握手和服务端模型加载。
    func warmUp() {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            guard await (try? self.apiKeyOrThrow()) != nil else { return }

            let pingContent = ChatCompletionRequest.Message.ContentItem(
                type: "text",
                text: "你好，请简单回复“OK”即可，用于预热服务。",
                image_url: nil
            )
            let message = ChatCompletionRequest.Message(role: "user", content: [pingContent])
            let requestBody = ChatCompletionRequest(model: "qwen-plus", messages: [message])

            do {
                _ = try await self.sendRequest(body: requestBody)
            } catch {
                // 预热失败不影响主流程，静默忽略
            }
        }
    }

    // MARK: - Networking

    private func sendRequest(body: ChatCompletionRequest) async throws -> Data {
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
            throw NSError(
                domain: "QwenClient",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        return data
    }
}

extension QwenClient: QwenServicing {}
