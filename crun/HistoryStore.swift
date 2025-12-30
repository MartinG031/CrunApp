import Foundation

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

    /// 统一的追加入口：供 App 内与快捷指令共用，统一处理开关与截断逻辑。
    /// - Returns: 追加后最新的历史数组（按时间倒序，最新在前）
    @MainActor
    static func append(instruction: String, summary: String) -> [AnalysisRecord] {
        // 如果用户在设置中关闭了历史记录，则不再追加新记录
        let enabled = UserDefaults.standard.object(forKey: "enableHistory") as? Bool ?? true
        guard enabled else { return load() }

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
        return current
    }

    /// 供快捷指令 / AppIntent 使用的兼容方法（保持既有调用不变）
    @MainActor
    static func appendFromShortcut(instruction: String, summary: String) {
        _ = append(instruction: instruction, summary: summary)
    }

    /// 删除指定记录
    /// - Returns: 删除后最新的历史数组
    @MainActor
    static func delete(id: UUID) -> [AnalysisRecord] {
        var current = load()
        if let index = current.firstIndex(where: { $0.id == id }) {
            current.remove(at: index)
            saveAsync(current)
        }
        return current
    }

    /// 清空全部历史
    /// - Returns: 清空后的历史数组（空数组）
    @MainActor
    static func clear() -> [AnalysisRecord] {
        let empty: [AnalysisRecord] = []
        saveAsync(empty)
        return empty
    }
}
