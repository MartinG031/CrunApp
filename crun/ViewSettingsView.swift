import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage("enableHistory") private var enableHistory: Bool = true
    @AppStorage("maxHistoryCount") private var maxHistoryCount: Int = 20
    @AppStorage("showTimestampInHistory") private var showTimestampInHistory: Bool = true
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
