import UIKit
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @SceneStorage("selectedTabIndex") private var selectedTabIndex: Int = 1
    @StateObject private var model = ContentViewModel()
    @State private var isChatPresented: Bool = false
    @State private var isSettingsPresented: Bool = false
    @State private var photoPickerItem: PhotosPickerItem? = nil
    @State private var isFileImporterPresented: Bool = false
    /// 图片加载中标记，用于在预览区域显示加载指示
    @State private var isImageLoading: Bool = false

    @AppStorage("enableHistory") private var enableHistory: Bool = true
    @AppStorage("maxHistoryCount") private var maxHistoryCount: Int = 20
    @AppStorage("showTimestampInHistory") private var showTimestampInHistory: Bool = true
    @AppStorage("showInstructionInHistory") private var showInstructionInHistory: Bool = true
    @AppStorage("enableHaptics") private var enableHaptics: Bool = true

    /// 是否已经看过首屏引导
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    /// 用于确保百炼模型预热只在首次进入应用时触发一次
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
                    history: model.history,
                    enableHistory: enableHistory,
                    showTimestampInHistory: showTimestampInHistory,
                    showInstructionInHistory: showInstructionInHistory,
                    onClearAll: {
                        model.clearHistory()
                    },
                    onDeleteRecord: { record in
                        model.deleteHistory(record: record)
                    },
                    onSelectRecord: { record in
                        model.selectRecord(record)
                        isChatPresented = true
                    },
                    onRefresh: {
                        model.refreshHistory()
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
                        model.selectRecord(record)
                        isChatPresented = true
                    },
                    onTapSettings: {
                        isSettingsPresented = true
                    }
                )
            }
        }
        .onAppear {
            model.refreshHistory()
            if hasSeenOnboarding {
                scheduleWarmUpIfNeeded()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !hasSeenOnboarding {
                        isOnboardingPresented = true
                    }
                }
            }
        }
        .sheet(isPresented: $isOnboardingPresented) {
            OnboardingView {
                hasSeenOnboarding = true
                isOnboardingPresented = false
                scheduleWarmUpIfNeeded()
            }
        }
        .sheet(isPresented: $isChatPresented) {
            if let summary = model.summary {
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

        Task.detached(priority: .background) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await QwenClient.shared.warmUp()
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

                if let screenshot = model.screenshot {
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
                                self.model.setScreenshot(uiImage)
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
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            isImageLoading = true
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        self.model.setScreenshot(uiImage)
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
            DispatchQueue.main.async {
                self.model.setScreenshot(image)
                self.isImageLoading = false
            }
        }
    }

    private var instructionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("分析")
                .font(.subheadline.bold())

            HStack(spacing: 8) {
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
                .disabled(model.isThinking)

                Button {
                    Task {
                        await model.runAnalysis()
                    }
                } label: {
                    HStack {
                        if model.isThinking {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(model.isThinking ? "分析中…" : "分析当前内容")
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
                .disabled(model.isThinking)
            }
        }
    }

    private func clearCurrentSession() {
        model.clearCurrentSession()
        isChatPresented = false
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("分析结果")
                .font(.subheadline.bold())

            Group {
                if let summary = model.summary {
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
        let numbers: [String] = model.detectedNumbers

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

                                    if let tag = model.phoneTags[number] {
                                        Text("百度号码服务：\(tag.codeType ?? "暂无标记") · 归属地：\(tag.province ?? "未知")")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    } else if model.loadingTags.contains(number) {
                                        Text("正在查询百度号码服务…")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("尚未查询号码标记。")
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
                                await model.loadTag(for: number)
                            }
                        }
                    }
                }
            }
        }
    }

    private func openBaidu(for number: String) {
        let query = "\(number) 骚扰 电话 归属地"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.baidu.com/s?wd=\(encoded)") else {
            return
        }
        openURL(url)
    }
}

#Preview {
    ContentView()
}
