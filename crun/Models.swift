import Foundation

struct AnalysisRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let instruction: String
    let summary: String
}

struct ChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
}

/// 来自百度号码服务的基础标记信息
struct PhoneTag {
    let code: Int?
    let codeType: String?
    let province: String?
}
