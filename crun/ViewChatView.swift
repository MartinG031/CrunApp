import SwiftUI

struct ChatView: View {
    let initialSummary: String

    @Environment(\.dismiss) private var dismiss
    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @FocusState private var isInputFocused: Bool

    private var recentMessages: [ChatMessage] {
        let limit = 50
        return messages.count > limit ? Array(messages.suffix(limit)) : messages
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
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    isInputFocused = false
                }

                // iMessage 风格输入条
                composerBar
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
            }
        }
    }

    private var composerBar: some View {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmpty = trimmed.isEmpty

        return VStack(spacing: 0) {
            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                TextField("再继续问些什么？", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .focused($isInputFocused)
                    .onSubmit {
                        sendMessage()
                    }

                Button("发送") {
                    sendMessage()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func setupInitialMessages() {
        guard messages.isEmpty else { return }
        messages = [ChatMessage(role: .assistant, text: initialSummary)]
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

                    请检查 Wi-Fi 或蜂窝数据连接正常后，再试一次。
                    """
                } else {
                    text = """
                    继续对话失败：\(nsError.localizedDescription)

                    请检查网络配置，稍后再试。
                    """
                }

                await MainActor.run {
                    messages.append(ChatMessage(role: .assistant, text: text))
                }
            }
        }
    }
}
