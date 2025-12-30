import Foundation
import AppIntents
import UIKit

/// 专门用于来电场景的意图：识别来电号码，并给出简要判断。
struct LookupCallerIntent: AppIntent {
    static var title: LocalizedStringResource = "识别来电号码"
    static var description = IntentDescription("分析来电界面截图，尝试识别来电号码，并给出简要判断和建议。")

    @Parameter(title: "来电截图")
    var screenshot: IntentFile

    @Parameter(title: "附加说明", default: "")
    var note: String

    static var parameterSummary: some ParameterSummary {
        Summary("识别 \(\.$screenshot) 中的来电号码，\(\.$note)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let data = screenshot.data
        guard let image = UIImage(data: data) else {
            return .result(value: "未能读取来电截图，请确认快捷指令中已经先截取屏幕。")
        }

        let baseInstruction = """
        这是 iPhone 来电界面的截图。请你：
        1. 尽量识别出截图中的来电号码（如果有多个号码，请只关注最核心的来电号码）。
        2. 推测这个号码可能属于哪类来电（例如：通讯录联系人、快递/外卖、客服、营销/骚扰、诈骗等），并简要说明判断依据。
        3. 用 1–3 句话用中文总结，对用户给出简单建议（例如是否建议谨慎接听或标记为骚扰）。
        如果你根本看不到号码，就可以略过本部分，不需要单独说明“未在截图中找到号码”或加括号注释。
        """

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullInstruction: String
        if trimmedNote.isEmpty {
            fullInstruction = baseInstruction
        } else {
            fullInstruction = baseInstruction + "\n附加说明：" + trimmedNote
        }

        let result = try await QwenClient.shared.analyzeScreen(
            screenshot: image,
            instruction: fullInstruction
        )

        await HistoryStore.appendFromShortcut(
            instruction: "查来电" + (trimmedNote.isEmpty ? "" : "：" + trimmedNote),
            summary: result
        )

        return .result(value: result)
    }
}

/// 使用快捷指令时调用的意图：接收一张截图，调用现有的多模态分析。
struct AnalyzeScreenIntent: AppIntent {
    static var title: LocalizedStringResource = "分析屏幕截图"
    static var description = IntentDescription("分析传入的屏幕截图，并根据指令给出简要结论。")

    @Parameter(title: "截图")
    var screenshot: IntentFile

    @Parameter(title: "指令", default: "")
    var instruction: String

    static var parameterSummary: some ParameterSummary {
        Summary("分析 \(\.$screenshot)，按照 \(\.$instruction) 进行说明")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let data = screenshot.data
        guard let image = UIImage(data: data) else {
            return .result(value: "未能读取截图数据，请确认快捷指令中已经先截取屏幕。")
        }

        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try await QwenClient.shared.analyzeScreen(
            screenshot: image,
            instruction: trimmed
        )

        await HistoryStore.appendFromShortcut(instruction: trimmed, summary: result)

        return .result(value: result)
    }
}
