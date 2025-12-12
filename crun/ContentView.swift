import UIKit
import SwiftUI
import AppIntents
import PhotosUI
import UniformTypeIdentifiers

private let phoneNumberDetector: NSDataDetector = {
    let types = NSTextCheckingResult.CheckingType.phoneNumber.rawValue
    return try! NSDataDetector(types: types)
}()

struct AnalysisRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let instruction: String
    let summary: String
}

/// 统一管理分析历史记录的读写逻辑，避免在多个位置重复硬编码 UserDefaults key。
struct HistoryStore {
    static let storageKey = "analysisHistory"

    static func load() -> [AnalysisRecord] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([AnalysisRecord].self, from: data) else {
            return []
        }
        return decoded
    }

    /// 在主线程上保存历史数据（用于需要立即同步写入的场景）
    @MainActor
    static func save(_ history: [AnalysisRecord]) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    /// 在后台线程进行 JSON 编码，再切回主线程写入 UserDefaults，避免阻塞主线程。
    static func saveAsync(_ history: [AnalysisRecord]) {
        let snapshot = history
        Task.detached(priority: .background) {
            let data = try? JSONEncoder().encode(snapshot)
            guard let data else { return }
            await MainActor.run {
                UserDefaults.standard.set(data, forKey: storageKey)
            }
        }
    }

    /// 在线程安全的前提下读取历史数据，通过 MainActor.run 确保对 UserDefaults 的访问发生在主线程上。
    static func loadAsync() async -> [AnalysisRecord] {
        await MainActor.run {
            load()
        }
    }

    /// 供快捷指令 / AppIntent 使用的追加方法，统一处理开关和截断逻辑。
    @MainActor
    static func appendFromShortcut(instruction: String, summary: String) {
        // 如果用户在设置中关闭了历史记录，则不再追加新记录
        let enabled = UserDefaults.standard.object(forKey: "enableHistory") as? Bool ?? true
        guard enabled else { return }

        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = AnalysisRecord(
            id: UUID(),
            date: Date(),
            instruction: trimmedInstruction,
            summary: summary
        )

        var current = load()
        current.insert(record, at: 0)

        // 从设置中读取最多保留的历史条数（默认 20 条）
        let configuredMax = UserDefaults.standard.integer(forKey: "maxHistoryCount")
        let limit = configuredMax > 0 ? configuredMax : 20

        if current.count > limit {
            current = Array(current.prefix(limit))
        }

        // 使用异步保存，避免在主线程上做 JSON 编码导致卡顿
        saveAsync(current)
    }
}


struct ContentView: View {
    @SceneStorage("selectedTabIndex") private var selectedTabIndex: Int = 1
    @State private var instruction: String = ""
    @State private var summary: String? = nil
    @State private var isThinking: Bool = false
    @State private var isChatPresented: Bool = false
    @State private var isSettingsPresented: Bool = false
    @State private var screenshot: UIImage? = nil
    @State private var detectedNumbers: [String] = []
    @State private var photoPickerItem: PhotosPickerItem? = nil
    @State private var isFileImporterPresented: Bool = false
    /// 图片加载中标记，用于在预览区域显示加载指示
    @State private var isImageLoading: Bool = false

    @State private var history: [AnalysisRecord] = []

    @AppStorage("enableHistory") private var enableHistory: Bool = true
    @AppStorage("maxHistoryCount") private var maxHistoryCount: Int = 20
    @AppStorage("showTimestampInHistory") private var showTimestampInHistory: Bool = true
    @AppStorage("showInstructionInHistory") private var showInstructionInHistory: Bool = true
    @AppStorage("enableHaptics") private var enableHaptics: Bool = true
    /// 是否已经看过首屏引导
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false

    @State private var phoneTags: [String: PhoneTag] = [:]
    @State private var loadingTags: Set<String> = []
    /// 用于确保百炼模型预热只在首次进入应用时触发一次，缓解「第一次调用特别慢」的体感。
    @State private var didWarmUpModel: Bool = false
    /// 控制引导界面显示
    @State private var isOnboardingPresented: Bool = false

    @Environment(\.openURL) private var openURL

    static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        TabView(selection: $selectedTabIndex) {
            Tab("历史", systemImage: "clock", value: 0) {
                HistoryScreen(
                    history: history,
                    enableHistory: enableHistory,
                    showTimestampInHistory: showTimestampInHistory,
                    showInstructionInHistory: showInstructionInHistory,
                    onClearAll: {
                        history.removeAll()
                        saveHistory()
                    },
                    onDeleteRecord: { record in
                        if let index = history.firstIndex(where: { $0.id == record.id }) {
                            history.remove(at: index)
                            saveHistory()
                        }
                    },
                    onSelectRecord: { record in
                        summary = record.summary
                        instruction = record.instruction
                        isChatPresented = true
                    },
                    onRefresh: {
                        loadHistory()
                    },
                    onTapSettings: {
                        isSettingsPresented = true
                    }
                )
            }
            Tab("分析", systemImage: "sparkles", value: 1) {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 16) {
                            header
                            screenshotPlaceholder
                            instructionSection
                            resultSection
                            phoneSection
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .navigationTitle("Crun")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                isSettingsPresented = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
                }
            }
            Tab("搜索", systemImage: "magnifyingglass", value: 2, role: .search) {
                SearchView(
                    onSelectRecord: { record in
                        summary = record.summary
                        instruction = record.instruction
                        isChatPresented = true
                    },
                    onTapSettings: {
                        isSettingsPresented = true
                    }
                )
            }
        }
        .onAppear {
            if hasSeenOnboarding {
                // 已经看过引导的用户，可以在主界面首帧之后尽快做一次预热。
                scheduleWarmUpIfNeeded()
            } else {
                // 首次启动：先让主界面出现，再稍后弹出引导，避免首屏就出现多个弹窗叠加。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !hasSeenOnboarding {
                        isOnboardingPresented = true
                    }
                }
            }
        }
        .onChange(of: summary) { _, newSummary in
            updateDetectedNumbers(from: newSummary)
        }
        .sheet(isPresented: $isOnboardingPresented) {
            OnboardingView {
                hasSeenOnboarding = true
                isOnboardingPresented = false
                scheduleWarmUpIfNeeded()
            }
        }
        .sheet(isPresented: $isChatPresented) {
            if let summary {
                ChatView(initialSummary: summary)
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                SettingsView()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }


    /// 在首帧渲染之后、且不与引导弹窗同时发生的时机安排一次模型预热。
    private func scheduleWarmUpIfNeeded() {
        guard !didWarmUpModel else { return }
        didWarmUpModel = true

        // 使用 GCD 在后台队列上延迟 1 秒执行预热逻辑，避免在 Swift Concurrency 环境中
        // 直接调用 async API 而忘记使用 await 导致编译错误，也减轻冷启动阶段的主线程压力。
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0) {
            QwenClient.shared.warmUp()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("通过 Action Button 或以下方式上传图片内容，我会帮你提炼重点内容。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var screenshotPlaceholder: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thinMaterial)

                if let screenshot {
                    Image(uiImage: screenshot)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 164)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(8)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.dashed")
                            .font(.system(size: 32))
                            .symbolRenderingMode(.hierarchical)
                        Text("还没有要分析的内容。\n可以从相册/文件选择，或从剪贴板粘贴一张图片。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 16)
                }

                if isImageLoading {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.15))
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)

            HStack(spacing: 8) {
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    Label("相册", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                }

                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("文件", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                }

                Button {
                    pasteImageFromClipboard()
                } label: {
                    Label("剪贴板", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                }
            }
            .font(.subheadline)
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [UTType.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }

                isImageLoading = true

                // 处理安全作用域的 URL，确保可以访问文件内容
                DispatchQueue.global(qos: .userInitiated).async {
                    let shouldStopAccessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if shouldStopAccessing {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }

                    do {
                        let data = try Data(contentsOf: url)
                        if let uiImage = UIImage(data: data) {
                            Task { @MainActor in
                                self.screenshot = uiImage
                                self.isImageLoading = false
                            }
                        } else {
                            Task { @MainActor in
                                self.isImageLoading = false
                            }
                        }
                    } catch {
                        Task { @MainActor in
                            self.isImageLoading = false
                        }
                    }
                }

            case .failure:
                break
            }
        }
        .onChange(of: photoPickerItem) { oldItem, newItem in
            guard let newItem else { return }
            isImageLoading = true
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        self.screenshot = uiImage
                        self.isImageLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.isImageLoading = false
                    }
                }
            }
        }
    }

    private func pasteImageFromClipboard() {
        let pasteboard = UIPasteboard.general
        if let image = pasteboard.image {
            isImageLoading = true
            // 粘贴板读取解码在系统内部完成，我们这里只负责快速更新 UI 状态
            DispatchQueue.main.async {
                self.screenshot = image
                self.isImageLoading = false
            }
        }
    }

    private var instructionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("分析")
                .font(.subheadline.bold())

            HStack(spacing: 8) {
                // 左侧：清除当前内容
                Button {
                    clearCurrentSession()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("清除当前内容")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isThinking)

                // 右侧：分析当前截图
                Button {
                    runLocalAnalysis()
                } label: {
                    HStack {
                        if isThinking {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isThinking ? "分析中…" : "分析当前内容")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor)
                    )
                    .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .disabled(isThinking)
            }
        }
    }

    private func clearCurrentSession() {
        // 清空当前这一轮的分析上下文，但不影响已经保存的历史记录
        instruction = ""
        summary = nil
        screenshot = nil
        phoneTags = [:]
        loadingTags = []
        isThinking = false
        isChatPresented = false
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("分析结果")
                .font(.subheadline.bold())

            Group {
                if let summary {
                    VStack(alignment: .leading, spacing: 12) {
                        ScrollView {
                            Text(summary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        .frame(maxHeight: 260)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.secondary.opacity(0.05))
                        )

                        Button {
                            isChatPresented = true
                        } label: {
                            HStack {
                                Image(systemName: "ellipsis.bubble")
                                Text("继续提问")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text("还没有分析结果。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.secondary.opacity(0.05))
                        )
                }
            }
        }
    }

    private var phoneSection: some View {
        let numbers: [String] = detectedNumbers

        return Group {
            if !numbers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("电话号码")
                            .font(.subheadline.bold())
                        Spacer()
                    }

                    VStack(spacing: 8) {
                        ForEach(numbers, id: \.self) { number in
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(number)
                                        .font(.body)
                                    Text("在百度搜索此号码，查看是否为骚扰电话或归属地等信息。")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    if let tag = phoneTags[number] {
                                        Text("百度号码服务：\(tag.codeType ?? "暂无标记") · 归属地：\(tag.province ?? "未知")")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("正在查询百度号码服务…")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button {
                                    openBaidu(for: number)
                                } label: {
                                    Text("百度一下")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.secondary.opacity(0.05))
                            )
                            .task {
                                loadTag(for: number)
                            }
                        }
                    }
                }
            }
        }
    }

    private func runLocalAnalysis() {
        guard !isThinking else { return }
        if enableHaptics {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
        }

        let userInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        isThinking = true

        Task {
            do {
                let result = try await QwenClient.shared.analyzeScreen(
                    screenshot: screenshot,
                    instruction: userInstruction
                )
                await MainActor.run {
                    summary = result
                    isThinking = false
                    // 每次新的分析结果会涉及新的号码集合，重置已有标记和加载状态，
                    // 让电话号码区块基于当前结果自动重新调用百度号码服务。
                    phoneTags = [:]
                    loadingTags = []
                    appendHistory(instruction: userInstruction, summary: result)
                }
            } catch {
                let nsError = error as NSError
                let message: String

                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorNotConnectedToInternet {
                    // 专门处理「无网络连接」的情况，提示用户检查 Wi‑Fi / 蜂窝网络
                    message = """
                    当前网络似乎不可用。

                    请检查 Wi‑Fi 或蜂窝数据后，再点击“分析当前内容”重试。
                    """
                } else {
                    message = """
                    分析失败：\(nsError.localizedDescription)

                    请检查网络配置，稍后重试。
                    """
                }

                await MainActor.run {
                    summary = message
                    isThinking = false
                }
            }
        }
    }

    private func appendHistory(instruction: String, summary: String) {
        // 如果用户在设置中关闭了历史记录，则不再追加新记录
        guard enableHistory else { return }

        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = AnalysisRecord(
            id: UUID(),
            date: Date(),
            instruction: trimmedInstruction,
            summary: summary
        )
        history.insert(record, at: 0)

        // 根据设置中的最多保留条数截断历史（默认 20 条）
        let limit = maxHistoryCount > 0 ? maxHistoryCount : 20
        if history.count > limit {
            history = Array(history.prefix(limit))
        }
        saveHistory()
    }

    private func loadHistory() {
        Task {
            let loaded = await HistoryStore.loadAsync()
            await MainActor.run {
                history = loaded
            }
        }
    }

    private func saveHistory() {
        // 在后台线程保存历史，避免在主线程上做 JSON 编码和磁盘写入导致首次操作卡顿
        HistoryStore.saveAsync(history)
    }

    // MARK: - Phone Numbers

    private func updateDetectedNumbers(from summary: String?) {
        guard let text = summary, !text.isEmpty else {
            detectedNumbers = []
            return
        }

        // 在主线程直接解析电话号码，避免跨 actor 调用导致 Swift 6 隔离错误
        let numbers = detectPhoneNumbersInText(text)
        detectedNumbers = numbers
    }

    /// 在百度中搜索指定号码（附带一些关键词，让结果更倾向骚扰/归属地信息）
    private func openBaidu(for number: String) {
        let query = "\(number) 骚扰 电话 归属地"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.baidu.com/s?wd=\(encoded)") else {
            return
        }
        openURL(url)
    }

    private func loadTag(for number: String) {
        guard !loadingTags.contains(number) else { return }
        loadingTags.insert(number)

        Task {
            do {
                if let tag = try await SPNSClient.shared.queryTag(for: number) {
                    await MainActor.run {
                        phoneTags[number] = tag
                        _ = loadingTags.remove(number)
                    }
                } else {
                    await MainActor.run {
                        _ = loadingTags.remove(number)
                    }
                }
            } catch {
                await MainActor.run {
                    _ = loadingTags.remove(number)
                }
            }
        }
    }
}

/// 从文本中识别电话号码（例如模型在总结中写出的来电号码）
private func detectPhoneNumbersInText(_ text: String) -> [String] {
    let matches = phoneNumberDetector.matches(
        in: text,
        options: [],
        range: NSRange(location: 0, length: (text as NSString).length)
    )
    let numbers = matches.compactMap { $0.phoneNumber }
    // 去重后排序，避免重复展示
    return Array(Set(numbers)).sorted()
}


// MARK: - Screens

/// 历史 Tab 对应的独立视图
struct HistoryScreen: View {
    let history: [AnalysisRecord]
    let enableHistory: Bool
    let showTimestampInHistory: Bool
    let showInstructionInHistory: Bool
    let onClearAll: () -> Void
    let onDeleteRecord: (AnalysisRecord) -> Void
    let onSelectRecord: (AnalysisRecord) -> Void
    let onRefresh: () -> Void
    let onTapSettings: () -> Void

    @State private var didLoadOnce: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("历史记录")
                                .font(.subheadline.bold())
                            Spacer()
                            if enableHistory, !history.isEmpty {
                                Button("清空") {
                                    onClearAll()
                                }
                                .font(.caption)
                            }
                        }

                        if !enableHistory {
                            Text("当前已关闭保存历史记录。\n可以在设置中开启“保存历史记录”，让新的分析结果出现在这里。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if history.isEmpty {
                            Text("暂无历史记录。\n每次成功分析后会在这里显示最近的结果。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(history) { record in
                                    Button {
                                        onSelectRecord(record)
                                    } label: {
                                        HStack(alignment: .top, spacing: 8) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                if showTimestampInHistory {
                                                    Text(ContentView.historyDateFormatter.string(from: record.date))
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }

                                                if showInstructionInHistory, !record.instruction.isEmpty {
                                                    Text("指令：\(record.instruction)")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }

                                                Text(record.summary)
                                                    .font(.footnote)
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.leading)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color.secondary.opacity(0.05))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            UIPasteboard.general.string = record.summary
                                        } label: {
                                            Label("复制摘要", systemImage: "doc.on.doc")
                                        }

                                        if !record.instruction.isEmpty {
                                            Button {
                                                UIPasteboard.general.string = record.instruction
                                            } label: {
                                                Label("复制指令", systemImage: "text.quote")
                                            }
                                        }

                                        Button(role: .destructive) {
                                            onDeleteRecord(record)
                                        } label: {
                                            Label("删除这条记录", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .refreshable {
                onRefresh()
            }
            .task {
                // 首次展示历史页面时，懒加载一次历史数据，而不是在应用启动时就加载
                if !didLoadOnce {
                    didLoadOnce = true
                    onRefresh()
                }
            }
            .navigationTitle("Crun")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onTapSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }
}

/// 分析 Tab 对应的独立视图
struct AnalyzeScreen: View {
    @Binding var instruction: String
    @Binding var summary: String?
    @Binding var screenshot: UIImage?
    @Binding var detectedNumbers: [String]
    @Binding var isThinking: Bool
    @Binding var phoneTags: [String: PhoneTag]
    @Binding var loadingTags: Set<String>
    let enableHaptics: Bool
    let onAppendHistory: (String, String) -> Void
    let onPresentChat: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    screenshotPlaceholder
                    instructionSection
                    resultSection
                    phoneSection
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .navigationTitle("Crun")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // 以下 header / screenshotPlaceholder / instructionSection / resultSection / phoneSection
    // 可以直接从原 ContentView 拷贝，对内部引用做少量替换（用绑定代替原来的 state）。
    // 这里略写结构，具体实现已存在，可以直接搬运：
    private var header: some View { /* 使用现有 header 实现 */ EmptyView() }
    private var screenshotPlaceholder: some View { /* 使用现有 screenshotPlaceholder 实现 */ EmptyView() }
    private var instructionSection: some View { /* 使用现有 instructionSection 实现 */ EmptyView() }
    private var resultSection: some View { /* 使用现有 resultSection 实现 */ EmptyView() }
    private var phoneSection: some View { /* 使用现有 phoneSection 实现 */ EmptyView() }
}

/// 搜索 Tab 已经是独立的 `SearchView`，保留现状即可。

// MARK: - Chat

struct ChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
}

struct ChatView: View {
    let initialSummary: String

    @Environment(\.dismiss) private var dismiss
    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @FocusState private var isInputFocused: Bool

    /// 仅渲染最近的若干条消息，避免在对话较长时每次输入都重绘过多行
    private var recentMessages: [ChatMessage] {
        let limit = 50
        if messages.count > limit {
            return Array(messages.suffix(limit))
        } else {
            return messages
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(recentMessages) { message in
                    HStack {
                        if message.role == .assistant {
                            Text(message.text)
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Spacer()
                        } else {
                            Spacer()
                            Text(message.text)
                                .padding(8)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)

                Divider()

                HStack {
                    TextField("继续问点什么？", text: $input)
                        .textFieldStyle(.roundedBorder)
                        .focused($isInputFocused)

                    Button("发送") {
                        sendMessage()
                    }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle("继续对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                setupInitialMessages()
                // 视图出现后稍作延迟再聚焦输入框，提升键盘唤起成功率
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isInputFocused = true
                }
            }
        }
    }

    private func setupInitialMessages() {
        guard messages.isEmpty else { return }
        messages = [
            ChatMessage(role: .assistant, text: initialSummary)
        ]
    }

    private func sendMessage() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(ChatMessage(role: .user, text: trimmed))
        input = ""

        Task {
            do {
                let replyText = try await QwenClient.shared.followUp(
                    initialSummary: initialSummary,
                    history: messages
                )
                await MainActor.run {
                    messages.append(ChatMessage(role: .assistant, text: replyText))
                }
            } catch {
                let nsError = error as NSError
                let text: String

                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorNotConnectedToInternet {
                    text = """
                    继续对话失败：当前网络似乎不可用。

                    请检查 Wi‑Fi 或蜂窝数据连接正常后，再试一次。
                    """
                } else {
                    text = """
                    继续对话失败：\(nsError.localizedDescription)

                    请检查网络配置，稍后再试。
                    """
                }

                await MainActor.run {
                    messages.append(
                        ChatMessage(
                            role: .assistant,
                            text: text
                        )
                    )
                }
            }
        }
    }
}


struct SearchView: View {
    @State private var query: String = ""
    @State private var history: [AnalysisRecord] = []
    /// 预先为每条历史记录构建一份小写索引，避免每次按键时反复 lowercased()
    @State private var indexedHistory: [(record: AnalysisRecord, summaryLower: String, instructionLower: String)] = []
    /// 实际用于过滤的查询词，经过简单防抖处理，减少每次输入触发完整过滤的次数
    @State private var effectiveQuery: String = ""
    /// 当前根据 effectiveQuery 得到的筛选结果，避免在 body 里直接做重计算
    @State private var searchResults: [AnalysisRecord] = []
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    @State private var isSearchFieldPresented: Bool = false
    /// 当前搜索请求的编号，用于避免过期的搜索结果在键盘动画期间回写 UI，导致掉帧
    @State private var currentSearchToken: Int = 0

    let onSelectRecord: (AnalysisRecord) -> Void
    let onTapSettings: () -> Void

    private var trimmedQuery: String {
        effectiveQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty {
                    Text("输入关键字，在历史摘要和指令中搜索。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else if history.isEmpty {
                    Text("暂无历史记录。\n分析完成后，可以在这里搜索以往的摘要和指令。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else if searchResults.isEmpty {
                    Text("没有找到匹配的记录。\n可以尝试更换关键词。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(searchResults) { record in
                        Button {
                            onSelectRecord(record)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ContentView.historyDateFormatter.string(from: record.date))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                if !record.instruction.isEmpty {
                                    Text("指令：\(record.instruction)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Text(record.summary)
                                    .font(.footnote)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onTapSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .searchable(text: $query, isPresented: $isSearchFieldPresented, prompt: "在历史摘要和指令中搜索")
        .onAppear {
            // 首次进入搜索页时自动展开搜索栏并唤起键盘
            isSearchFieldPresented = true
            loadHistory()
        }
        .onChange(of: query) { _, newValue in
            // 对搜索输入做一个非常轻量的防抖，避免每个字符都立即触发完整过滤
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                // 等用户停顿约 200ms 再更新实际搜索词
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return }
                await MainActor.run {
                    effectiveQuery = newValue
                }
            }
        }
        .onChange(of: effectiveQuery) { _, newValue in
            // 每当经过防抖处理后的查询词发生变化时，在后台重新计算匹配结果
            recomputeResults(for: newValue)
        }
        .onChange(of: isSearchFieldPresented) { _, presented in
            if !presented {
                // 用户收起搜索栏或键盘时，取消待执行的搜索任务，避免在动画期间触发新的结果更新
                searchDebounceTask?.cancel()
            }
        }
    }

    /// 根据当前查询词重新计算搜索结果，将重计算放到后台线程，减轻主线程压力
    private func recomputeResults(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // 查询词太短（例如只有 0–1 个字符）时，不执行全文过滤，避免每次按键都触发大量计算。
        guard trimmed.count >= 2 else {
            searchResults = []
            return
        }

        // 如果搜索栏已经收起（键盘已关闭），本次搜索不再触发结果更新，避免干扰收起动画
        guard isSearchFieldPresented else {
            return
        }

        // 生成当前搜索请求的 token，用于防止过期任务在动画期间回写 UI
        let token = currentSearchToken &+ 1
        currentSearchToken = token

        // 在主线程先做一次快照，避免在后台任务中直接访问 @State 数组
        let snapshot = indexedHistory

        Task.detached(priority: .userInitiated) {
            let lower = trimmed.lowercased()
            let matches: [AnalysisRecord] = snapshot.compactMap { item in
                if item.summaryLower.contains(lower) || item.instructionLower.contains(lower) {
                    return item.record
                } else {
                    return nil
                }
            }

            await MainActor.run {
                // 仅当该任务仍然是最新的一次搜索，且搜索栏仍处于展开状态时，才更新 UI，
                // 避免在键盘收起动画过程中发生大量 List diff，导致掉帧。
                guard self.currentSearchToken == token, self.isSearchFieldPresented else { return }
                self.searchResults = matches
            }
        }
    }

    private func loadHistory() {
        Task {
            // 先在后台读取原始历史记录
            let loaded = await HistoryStore.loadAsync()

            // 在后台线程构建小写索引，避免在主线程上对大量文本做 lowercased() 导致首次进入搜索页时卡顿
            let indexed = await Task.detached(priority: .userInitiated) { () -> [(record: AnalysisRecord, summaryLower: String, instructionLower: String)] in
                return loaded.map { record in
                    let summaryLower = record.summary.lowercased()
                    let instructionLower = record.instruction.lowercased()
                    return (record: record, summaryLower: summaryLower, instructionLower: instructionLower)
                }
            }.value

            await MainActor.run {
                history = loaded
                indexedHistory = indexed
                // 初次进入页面时，用当前查询初始化实际搜索词并触发一次计算
                effectiveQuery = query
                recomputeResults(for: query)
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// 是否保存历史记录
    @AppStorage("enableHistory") private var enableHistory: Bool = true

    /// 通过 AppStorage 存储“最多保留多少条历史记录”
    @AppStorage("maxHistoryCount") private var maxHistoryCount: Int = 20

    /// 历史列表是否显示时间戳
    @AppStorage("showTimestampInHistory") private var showTimestampInHistory: Bool = true

    /// 历史列表是否显示指令内容
    @AppStorage("showInstructionInHistory") private var showInstructionInHistory: Bool = true

    @AppStorage("enableHaptics") private var enableHaptics: Bool = true


    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }


    var body: some View {
        Form {
            Section(header: Text("应用偏好")) {
                Toggle("触觉反馈", isOn: $enableHaptics)
            }

            Section(header: Text("历史记录")) {
                Toggle("保存历史记录", isOn: $enableHistory)

                Picker("最多保留条数", selection: $maxHistoryCount) {
                    Text("5 条").tag(5)
                    Text("10 条").tag(10)
                    Text("20 条").tag(20)
                    Text("50 条").tag(50)
                    Text("100 条").tag(100)
                    Text("200 条").tag(200)
                    Text("500 条").tag(500)
                }
                .pickerStyle(.menu)
                .disabled(!enableHistory)

                Text("超过上限时会自动删除最早的记录，仅保留最近的几条。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("列表显示")) {
                Toggle("显示时间", isOn: $showTimestampInHistory)
                Toggle("显示指令内容", isOn: $showInstructionInHistory)

                Text("可以根据个人习惯，控制历史列表的信息密度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("快捷指令")) {
                Button {
                    // 打开 iCloud 分享的 Crun 快捷指令链接，方便用户一键添加到“快捷指令”App
                    if let url = URL(string: "https://www.icloud.com/shortcuts/11019da16f4f44919524aa83fcc2b8b8") {
                        openURL(url)
                    }
                } label: {
                    HStack {
                        Text("添加或管理 Crun 快捷指令")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }

                Text("将共享链接添加到“快捷指令”App 后，可以在设置 ▸ 动作按钮中选择「Crun」一键分析当前屏幕。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("关于")) {
                HStack {
                    Text("版本")
                    Spacer()
                    Text(appVersionString)
                        .foregroundStyle(.secondary)
                }

                Button {
                    if let url = URL(string: "mailto:martinjay200031@gmail.com?subject=Crun 反馈") {
                        openURL(url)
                    }
                } label: {
                    HStack {
                        Text("发送反馈")
                        Spacer()
                        Image(systemName: "envelope")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
    }
}

/// 首次使用时的引导界面：介绍 Crun 是做什么的，以及如何配合快捷指令/Action Button 使用。
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// 关闭时的回调，由外层负责更新 hasSeenOnboarding
    let onDone: () -> Void

    /// 当前引导页索引（0 开始）
    @State private var currentPage: Int = 0

    private let pageCount: Int = 4

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    // 第 0 页：权限说明
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("获取所需权限")
                                    .font(.title2.bold())
                                Text("Crun 需要少量系统权限才能正常工作，你可以在后续使用中按需授权。")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("📶 网络访问：用于连接云端模型，分析截图内容。".autoCJKSpacing())
                                Text("🖼️ 相册访问：用于从“照片”中选择要分析的图片。".autoCJKSpacing())
                                Text("📂 文件访问：用于从“文件”App中选择图片文件进行分析。".autoCJKSpacing())
                                Text("📋 剪贴板：用于粘贴剪贴板中的图片进行快速分析。".autoCJKSpacing())
                            }
                            .font(.body)

                            Text("系统会在你第一次使用相关功能时弹出权限提示。建议在信任的前提下选择“允许”，以获得完整体验。")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .tag(0)

                    // 第 1 页：欢迎 & 能力介绍
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("欢迎使用 Crun")
                                    .font(.title2.bold())
                                Text("一个帮你“读懂当前屏幕”的小助手。")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("它能帮你做什么")
                                    .font(.headline)
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("📋 总结长截图里的关键信息")
                                    Text("🧩 解释复杂页面、表格、代码或报错")
                                    Text("📞 识别号码并判断是否可能为骚扰电话")
                                    Text("💬 继续提问，它会记住当前这张截图的上下文")
                                }
                                .font(.body)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .tag(1)

                    // 第 2 页：基本用法
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            Text("基本用法")
                                .font(.title3.bold())

                            VStack(alignment: .leading, spacing: 10) {
                                Text("📷 截一张当前屏幕")
                                    .font(.body.weight(.semibold))
                                Text("用右上角的 Action Button，或者在“快捷指令”里使用“截取屏幕”。")
                                    .font(.body)
                                    .foregroundStyle(.secondary)

                                Text("🧾 打开 Crun")
                                    .font(.body.weight(.semibold))
                                Text("上方会自动展示刚才的截图，也可以在应用内从相册/文件重新选择。")
                                    .font(.body)
                                    .foregroundStyle(.secondary)

                                Text("✨ 点击“分析当前内容”")
                                    .font(.body.weight(.semibold))
                                Text("等待几秒，就能看到提炼好的总结和建议。")
                                    .font(.body)
                                    .foregroundStyle(.secondary)

                                Text("💬 继续提问")
                                    .font(.body.weight(.semibold))
                                Text("如果还有疑问，可以在同一张截图的上下文里继续聊天。")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .tag(2)

                    // 第 3 页：快捷指令 & 小贴士
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("配合快捷指令使用")
                                    .font(.title3.bold())
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("🧩 在“快捷指令”App 中，创建名为「Crun」的快捷指令，包含：截屏 → 调用“分析屏幕截图” → 显示结果。")
                                    Text("⚙️ 在 iPhone 设置 ▸ 动作按钮（或侧边按钮）中，将操作设置为“快捷指令”，然后选择「Crun」。")
                                    Text("🔘 之后按一下 Action Button，系统会自动截屏并调用 Crun 进行分析。")
                                }
                                .font(.body)
                            }

                            Button {
                                // 打开 iCloud 分享的 Crun 快捷指令，一步添加到“快捷指令”App 中
                                if let url = URL(string: "https://www.icloud.com/shortcuts/11019da16f4f44919524aa83fcc2b8b8") {
                                    openURL(url)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "square.and.pencil")
                                    Text("一键添加 Crun 快捷指令")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("小贴士")
                                    .font(.headline)
                                Text("💡 如果只想分析相册/文件中的图片，也可以在 Crun 内直接选择，不一定要用截屏。")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                Text("⚙️ 历史记录和触觉反馈等可以在“设置”中按个人习惯调整。")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // 底部分页指示 + 下一步/开始使用 按钮
                HStack {
                    HStack(spacing: 6) {
                        ForEach(0..<pageCount, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                                .frame(width: index == currentPage ? 8 : 6, height: index == currentPage ? 8 : 6)
                        }
                    }

                    Spacer()

                    Button {
                        if currentPage < pageCount - 1 {
                            withAnimation {
                                currentPage += 1
                            }
                        } else {
                            onDone()
                            dismiss()
                        }
                    } label: {
                        Text(currentPage < pageCount - 1 ? "下一步" : "开始使用")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Crun 使用引导")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("跳过") {
                        onDone()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Qwen Client

final class QwenClient {
    static let shared = QwenClient()

    // 使用百炼（通义千问）控制台中的 DASHSCOPE_API_KEY。
    // 建议通过 Info.plist / Keychain 配置，而不是直接写死在代码里。
    private let apiKey: String = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "DASHSCOPE_API_KEY") as? String,
              !key.isEmpty
        else {
            fatalError("DASHSCOPE_API_KEY 未配置，请在 Info.plist 中设置")
        }
        return key
    }()

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

        contents.append(.init(
            type: "text",
            text: userText,
            image_url: nil
        ))

        if let screenshot,
           let data = screenshot.jpegData(compressionQuality: 0.7) {
            let base64 = data.base64EncodedString()
            contents.append(.init(
                type: "image_url",
                text: nil,
                image_url: .init(url: "data:image/jpeg;base64,\(base64)")
            ))
        }

        let message = ChatCompletionRequest.Message(
            role: "user",
            content: contents
        )

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

        // 用一段文本承载上下文（总结 + 历史对话）
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

        contents.append(.init(
            type: "text",
            text: context,
            image_url: nil
        ))

        let message = ChatCompletionRequest.Message(
            role: "user",
            content: contents
        )

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
    /// 这样用户第一次真正点击「分析当前截图」时，体感会明显更顺滑。
    func warmUp() {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }

            // 如果 API Key 未配置，这里直接返回（实际情况下 apiKey 未配置会在初始化时触发 fatalError）
            guard !self.apiKey.isEmpty else { return }

            // 构造一个极简的对话请求，尽量降低 token 消耗。
            let pingContent = ChatCompletionRequest.Message.ContentItem(
                type: "text",
                text: "你好，请简单回复“OK”即可，用于预热服务。",
                image_url: nil
            )
            let message = ChatCompletionRequest.Message(
                role: "user",
                content: [pingContent]
            )
            let requestBody = ChatCompletionRequest(
                model: "qwen-plus",
                messages: [message]
            )

            // 通过已有的 sendRequest 走一遍完整链路（DNS、TLS、认证、路由等），
            // 但完全忽略返回结果和错误，以免打扰正常使用。
            do {
                _ = try await self.sendRequest(body: requestBody)
            } catch {
                // 预热失败不影响主流程，这里静默忽略。
            }
        }
    }

    // MARK: - Networking

    private func sendRequest(body: ChatCompletionRequest) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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

// MARK: - App Intents for Shortcuts / Action Button

/// 专门用于来电场景的意图：识别来电号码，并给出简要判断。
struct LookupCallerIntent: AppIntent {
    static var title: LocalizedStringResource = "识别来电号码"
    static var description = IntentDescription("分析来电界面截图，尝试识别来电号码，并给出简要判断和建议。")

    /// 来电截图（由“截取屏幕”动作传入）
    @Parameter(title: "来电截图")
    var screenshot: IntentFile

    /// 可选的附加说明（例如：更关注是否为骚扰电话）
    @Parameter(title: "附加说明", default: "")
    var note: String

    static var parameterSummary: some ParameterSummary {
        Summary("识别 \(\.$screenshot) 中的来电号码，\(\.$note)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // 从 IntentFile 里取出 Data -> UIImage
        let data = screenshot.data
        guard let image = UIImage(data: data) else {
            return .result(value: "未能读取来电截图，请确认快捷指令中已经先截取屏幕。")
        }

        // 为来电识别构造更明确的指令
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

        // 将结果写入与 App 共用的历史记录
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

    /// 快捷指令里“截取屏幕”动作传进来的图片文件
    @Parameter(title: "截图")
    var screenshot: IntentFile

    /// 可选的文字指令
    @Parameter(title: "指令", default: "")
    var instruction: String

    static var parameterSummary: some ParameterSummary {
        Summary("分析 \(\.$screenshot)，按照 \(\.$instruction) 进行说明")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // 从 IntentFile 里取出 Data -> UIImage
        let data = screenshot.data
        guard let image = UIImage(data: data) else {
            return .result(value: "未能读取截图数据，请确认快捷指令中已经先截取屏幕。")
        }

        // 调用现有的多模态客户端
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try await QwenClient.shared.analyzeScreen(
            screenshot: image,
            instruction: trimmed
        )

        // 将结果写入与 App 共用的历史记录
        await HistoryStore.appendFromShortcut(instruction: trimmed, summary: result)

        return .result(value: result)
    }
}

#Preview {
    ContentView()
}

// MARK: - Baidu SPNS (Phone Tag) Client

/// 来自百度号码服务的基础标记信息
struct PhoneTag {
    let code: Int?
    let codeType: String?
    let province: String?
}

final class SPNSClient {
    static let shared = SPNSClient()

    // TODO: 在百度智能云控制台申请以下参数
    private let appKey = "YOUR_BAIDU_SPNS_APPKEY"
    private let accessKey = "YOUR_BAIDU_SPNS_ACCESS_KEY"   // AK
    private let secretKey = "YOUR_BAIDU_SPNS_SECRET_KEY"   // SK

    private let endpoint = URL(string: "https://pnvs.baidubce.com/haoma-cloud/openapi/phone-tag/1.0")!

    private struct RequestBody: Encodable {
        let appkey: String
        let phone: String
    }

    private struct ResponseBody: Decodable {
        struct Result: Decodable {
            struct Location: Decodable {
                let province: String?
            }
            struct RemarkTypes: Decodable {
                let code: Int?
                let code_type: String?
            }

            let phone: String
            let location: Location?
            let remark_types: RemarkTypes?
        }

        let code: String
        let msg: String
        let result: Result?
    }

    /// 查询指定号码在百度号码服务中的标记信息
    /// 注意：当前实现仅为骨架，phone 字段的加密以及 Authorization 签名需要你按文档自行完善。
    func queryTag(for phoneNumber: String) async throws -> PhoneTag? {
        let trimmed = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // TODO: 按文档要求对手机号做 SHA1 或加密后再传给 phone 字段。
        // 这里先直接使用原始号码作为占位，方便你后续替换实现。
        let encodedPhone = trimmed

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "version", value: "1.0")
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let body = RequestBody(appkey: appKey, phone: encodedPhone)
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // TODO: 替换为基于 AK/SK 的 BCE 鉴权头。当前占位实现无法通过线上鉴权，只用于保证编译通过。
        request.setValue("bce-auth-v1/\(accessKey)/dummy/3600//", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard decoded.code == "10000", let result = decoded.result else {
            return nil
        }

        let province = result.location?.province
        let code = result.remark_types?.code
        let codeType = result.remark_types?.code_type

        return PhoneTag(code: code, codeType: codeType, province: province)
    }
}


// MARK: - 中英文自动空格

extension String {
    /// 在中文字符与英文/数字之间自动插入空格，类似 Apple 在中文界面中对中英混排的排版风格。
    /// 例如：
    ///   "打开App看一下" -> "打开 App 看一下"
    ///   "从文件App中选择" -> "从 文件 App 中选择"
    ///
    /// 规则：
    /// - 在 CJK（中日韩）字符与 ASCII 字母/数字之间插入一个空格；
    /// - 已经存在空格的位置不会重复插入。
    func autoCJKSpacing() -> String {
        var result = self

        // 1. 中文后面紧跟英文/数字：中英之间加空格
        //    例如："打开App" -> "打开 App"
        if let regex = try? NSRegularExpression(
            pattern: "(?<=[\\p{Han}\\p{Hiragana}\\p{Katakana}])(?=[A-Za-z0-9])",
            options: []
        ) {
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
        }

        // 2. 英文/数字后面紧跟中文：英中之间加空格
        //    例如："App商店" -> "App 商店"
        if let regex = try? NSRegularExpression(
            pattern: "(?<=[A-Za-z0-9])(?=[\\p{Han}\\p{Hiragana}\\p{Katakana}])",
            options: []
        ) {
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
        }

        return result
    }
}

