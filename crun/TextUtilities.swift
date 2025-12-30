import Foundation
import UIKit

private let phoneNumberDetector: NSDataDetector = {
    let types = NSTextCheckingResult.CheckingType.phoneNumber.rawValue
    return try! NSDataDetector(types: types)
}()

/// 从文本中识别电话号码（例如模型在总结中写出的来电号码）
func detectPhoneNumbersInText(_ text: String) -> [String] {
    let matches = phoneNumberDetector.matches(
        in: text,
        options: [],
        range: NSRange(location: 0, length: (text as NSString).length)
    )
    let numbers = matches.compactMap { $0.phoneNumber }
    // 去重后排序，避免重复展示
    return Array(Set(numbers)).sorted()
}

// MARK: - 中英文自动空格

extension String {
    /// 在中文字符与英文/数字之间自动插入空格，类似 Apple 在中文界面中对中英混排的排版风格。
    func autoCJKSpacing() -> String {
        var result = self

        // 1) 中文后面紧跟英文/数字：中英之间加空格
        if let regex = try? NSRegularExpression(
            pattern: "(?<=[\\p{Han}\\p{Hiragana}\\p{Katakana}])(?=[A-Za-z0-9])",
            options: []
        ) {
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
        }

        // 2) 英文/数字后面紧跟中文：英中之间加空格
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
