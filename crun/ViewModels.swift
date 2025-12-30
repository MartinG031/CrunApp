import Foundation
import Combine
import SwiftUI
import UIKit

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var instruction: String = ""

    @Published var summary: String? = nil {
        didSet {
            updateDetectedNumbers(from: summary)
        }
    }

    @Published var isThinking: Bool = false
    @Published var screenshot: UIImage? = nil
    @Published private(set) var detectedNumbers: [String] = []

    @Published var history: [AnalysisRecord] = []

    @Published var phoneTags: [String: PhoneTag] = [:]
    @Published var loadingTags: Set<String> = []

    private let qwen: any QwenServicing
    private let phoneTagService: any PhoneTagServicing

    init(
        qwen: (any QwenServicing)? = nil,
        phoneTagService: (any PhoneTagServicing)? = nil
    ) {
        self.qwen = qwen ?? QwenClient.shared
        self.phoneTagService = phoneTagService ?? SPNSClient.shared
    }

    func refreshHistory() {
        Task {
            await loadHistory()
        }
    }

    func loadHistory() async {
        let loaded = await HistoryStore.loadAsync()
        history = loaded
    }

    func clearHistory() {
        history = HistoryStore.clear()
    }

    func deleteHistory(record: AnalysisRecord) {
        history = HistoryStore.delete(id: record.id)
    }

    func selectRecord(_ record: AnalysisRecord) {
        summary = record.summary
        instruction = record.instruction
    }

    func clearCurrentSession() {
        instruction = ""
        summary = nil
        screenshot = nil
        phoneTags = [:]
        loadingTags = []
        isThinking = false
    }

    func setScreenshot(_ image: UIImage?) {
        screenshot = image
    }

    func runAnalysis() async {
        guard !isThinking else { return }

        let userInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        isThinking = true

        do {
            let result = try await qwen.analyzeScreen(
                screenshot: screenshot,
                instruction: userInstruction
            )

            summary = result
            isThinking = false

            // 每次新的分析结果会涉及新的号码集合，重置已有标记和加载状态。
            phoneTags = [:]
            loadingTags = []

            history = HistoryStore.append(instruction: userInstruction, summary: result)
        } catch {
            let nsError = error as NSError
            let message: String

            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorNotConnectedToInternet {
                message = """
                当前网络似乎不可用。

                请检查 Wi-Fi 或蜂窝数据后，再点击“分析当前内容”重试。
                """
            } else {
                message = """
                分析失败：\(nsError.localizedDescription)

                请检查网络配置，稍后重试。
                """
            }

            summary = message
            isThinking = false
        }
    }

    func loadTag(for number: String) async {
        guard !number.isEmpty else { return }
        guard phoneTags[number] == nil else { return }
        guard !loadingTags.contains(number) else { return }

        loadingTags.insert(number)
        defer {
            loadingTags.remove(number)
        }

        do {
            if let tag = try await phoneTagService.queryTag(for: number) {
                phoneTags[number] = tag
            }
        } catch {
            // 查询失败时静默忽略，避免干扰主流程
        }
    }

    private func updateDetectedNumbers(from summary: String?) {
        guard let text = summary, !text.isEmpty else {
            detectedNumbers = []
            return
        }
        detectedNumbers = detectPhoneNumbersInText(text)
    }
}
