import SwiftUI
import UIKit

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
