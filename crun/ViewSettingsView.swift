import SwiftUI

struct SettingsView: View {
    var body: some View {
        ViewSettingsView()
    }
}

/// 首次使用时的引导界面
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let onDone: () -> Void
    @State private var currentPage: Int = 0
    private let pageCount: Int = 4

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
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

                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            Text("基本用法")
                                .font(.title3.bold())

                            VStack(alignment: .leading, spacing: 10) {
                                Text("📷 截一张当前屏幕").font(.body.weight(.semibold))
                                Text("用右上角的 Action Button，或者在“快捷指令”里使用“截取屏幕”。")
                                    .font(.body)
                                    .foregroundStyle(.secondary)

                                Text("🧾 打开 Crun").font(.body.weight(.semibold))
                                Text("上方会自动展示刚才的截图，也可以在应用内从相册/文件重新选择。")
                                    .font(.body)
                                    .foregroundStyle(.secondary)

                                Text("✨ 点击“分析当前内容”").font(.body.weight(.semibold))
                                Text("等待几秒，就能看到提炼好的总结和建议。")
                                    .font(.body)
                                    .foregroundStyle(.secondary)

                                Text("💬 继续提问").font(.body.weight(.semibold))
                                Text("如果还有疑问，可以在同一张截图的上下文里继续聊天。")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .tag(2)

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

struct ViewSettingsView: View {
    @Environment(\.openURL) private var openURL

    // MARK: - 模型服务（自定义 Base URL + API Key）
    @AppStorage("provider_base_url") private var providerBaseURL: String = "https://dashscope.aliyuncs.com/compatible-mode"

    // MARK: - 其他设置（沿用你项目中已被使用的 key）

    @AppStorage("enableHistory") private var enableHistory: Bool = true
    @AppStorage("maxHistoryCount") private var maxHistoryCount: Int = 20
    @AppStorage("showTimestampInHistory") private var showTimestampInHistory: Bool = true
    @AppStorage("showInstructionInHistory") private var showInstructionInHistory: Bool = true
    @AppStorage("enableHaptics") private var enableHaptics: Bool = true

    @State private var historyCount: Int = 0
    @State private var showClearHistoryConfirm = false

    @State private var apiKeyInput: String = ""
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    private var isAPIKeyConfigured: Bool {
        (KeychainStore.readAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }


    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        if version.isEmpty { return build }
        if build.isEmpty { return version }
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            // MARK: - 模型服务
            Section {
                TextField("Base URL", text: $providerBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)

                SecureField("API Key", text: $apiKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.asciiCapable)
                    .privacySensitive()

                HStack {
                    Button {
                        do {
                            try KeychainStore.upsertAPIKey(apiKeyInput)
                            apiKeyInput = ""
                            alertTitle = "已保存"
                            alertMessage = "API Key 已保存到钥匙串。"
                            showAlert = true
                        } catch {
                            alertTitle = "保存失败"
                            alertMessage = error.localizedDescription
                            showAlert = true
                        }
                    } label: {
                        Text("保存")
                    }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()

                    Button(role: .destructive) {
                        do {
                            // 恢复默认设置：重置 Base URL，并清除钥匙串中的 API Key
                            providerBaseURL = "https://dashscope.aliyuncs.com/compatible-mode"
                            try KeychainStore.deleteAPIKey()
                            apiKeyInput = ""

                            alertTitle = "已恢复默认设置"
                            alertMessage = "已重置 Base URL，并从钥匙串移除 API Key。"
                            showAlert = true
                        } catch {
                            alertTitle = "恢复失败"
                            alertMessage = error.localizedDescription
                            showAlert = true
                        }
                    } label: {
                        Text("恢复默认设置")
                    }
                    .disabled(providerBaseURL == "https://dashscope.aliyuncs.com/compatible-mode" && !isAPIKeyConfigured)
                }
            } header: {
                Text("自定义模型服务")
            } footer: {
                Text("Base URL 用于切换模型服务地址；API Key 将安全存储在系统钥匙串中（保存后自动清除内容）。")
            }


            // MARK: - 历史记录
            Section {
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

                Toggle("显示时间", isOn: $showTimestampInHistory)
                    .disabled(!enableHistory)

                Toggle("显示指令内容", isOn: $showInstructionInHistory)
                    .disabled(!enableHistory)

                HStack {
                    Text("当前条目数")
                    Spacer()
                    Text("\(historyCount)")
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    showClearHistoryConfirm = true
                } label: {
                    Text("清空历史记录")
                }
                .disabled(!enableHistory || historyCount == 0)
            } header: {
                Text("历史记录")
            } footer: {
                Text("关闭后将不再保存新的历史记录。超过上限时会自动删除最早的记录，仅保留最近的几条。")
            }

            // MARK: - 触觉反馈
            Section {
                Toggle("触觉反馈", isOn: $enableHaptics)
            } header: {
                Text("触觉反馈")
            }

            // MARK: - 快捷指令
            Section {
                Button {
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
            } header: {
                Text("快捷指令")
            }

            // MARK: - 关于
            Section {
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
            } header: {
                Text("关于")
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let items = await HistoryStore.loadAsync()
            historyCount = items.count
        }
        .onChange(of: enableHistory) { _, _ in
            Task {
                let items = await HistoryStore.loadAsync()
                historyCount = items.count
            }
        }
        .alert(isPresented: $showClearHistoryConfirm) {
            Alert(
                title: Text("确定要清空历史记录？"),
                message: Text("此操作不可撤销。"),
                primaryButton: .destructive(Text("清空")) {
                    let cleared = HistoryStore.clear()
                    historyCount = cleared.count
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
}
