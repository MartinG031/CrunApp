import Foundation

protocol PhoneTagServicing {
    func queryTag(for phoneNumber: String) async throws -> PhoneTag?
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
        let encodedPhone = trimmed

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "version", value: "1.0")
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15

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

extension SPNSClient: PhoneTagServicing {}
