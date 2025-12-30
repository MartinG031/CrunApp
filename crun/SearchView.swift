import SwiftUI

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
            // 不自动聚焦搜索框，避免切到「搜索」Tab 时弹出键盘。
            isSearchFieldPresented = false
            loadHistory()
        }
        .onDisappear {
            // 离开页面时取消防抖任务并收起键盘（如果当时处于搜索状态）
            searchDebounceTask?.cancel()
            isSearchFieldPresented = false
        }
        .onChange(of: query) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return }
                await MainActor.run {
                    effectiveQuery = newValue
                }
            }
        }
        .onChange(of: effectiveQuery) { _, newValue in
            recomputeResults(for: newValue)
        }
        .onChange(of: isSearchFieldPresented) { _, presented in
            if !presented {
                searchDebounceTask?.cancel()
            }
        }
    }

    private func recomputeResults(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            return
        }
        guard isSearchFieldPresented else {
            return
        }

        let token = currentSearchToken &+ 1
        currentSearchToken = token
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
                guard self.currentSearchToken == token, self.isSearchFieldPresented else { return }
                self.searchResults = matches
            }
        }
    }

    private func loadHistory() {
        Task {
            let loaded = await HistoryStore.loadAsync()

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
                effectiveQuery = query
                recomputeResults(for: query)
            }
        }
    }
}
