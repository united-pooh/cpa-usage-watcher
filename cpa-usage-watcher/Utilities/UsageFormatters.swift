import Foundation

enum UsageFormatters {
    static func integer(_ value: Int) -> String {
        value.formatted(.number)
    }

    static func integer(_ value: Int?, placeholder: String = "--") -> String {
        guard let value else {
            return placeholder
        }
        return integer(value)
    }

    static func requestCount(_ value: Int) -> String {
        integer(value)
    }

    static func tokenCount(_ value: Int) -> String {
        integer(value)
    }

    static func compactNumber(_ value: Int) -> String {
        let absolute = abs(value)

        if absolute >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }

        if absolute >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }

        return "\(value)"
    }

    static func compactNumber(_ value: Double) -> String {
        compactNumber(Int(value.rounded()))
    }

    static func decimal(_ value: Double, digits: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func throughput(_ value: Double, unit: String) -> String {
        "\(decimal(value, digits: value >= 10 ? 0 : 1)) \(unit)"
    }

    static func percent(_ value: Double) -> String {
        (value * 100).formatted(.number.precision(.fractionLength(1))) + "%"
    }

    static func successRate(successful: Int, total: Int) -> String {
        guard total > 0 else {
            return percent(0)
        }
        return percent(Double(successful) / Double(total))
    }

    static func latency(_ milliseconds: Double) -> String {
        guard milliseconds > 0 else {
            return "0秒"
        }

        if milliseconds < 1_000 {
            return "\(Int(milliseconds.rounded()))毫秒"
        }

        let seconds = milliseconds / 1_000
        if seconds < 60 {
            return seconds.formatted(.number.precision(.fractionLength(2))) + "秒"
        }

        let minutes = Int(seconds / 60)
        let remaining = Int(seconds.truncatingRemainder(dividingBy: 60))
        return "\(minutes)分 \(remaining)秒"
    }

    static func latencyCompact(_ milliseconds: Double) -> String {
        guard milliseconds > 0 else {
            return "0ms"
        }

        if milliseconds < 1_000 {
            return "\(Int(milliseconds.rounded()))ms"
        }

        return decimal(milliseconds / 1_000, digits: 2) + "s"
    }

    static func cost(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }

        return "$" + value.formatted(.number.precision(.fractionLength(4)))
    }

    static func costOrPlaceholder(_ value: Double?, placeholder: String = "未配置") -> String {
        guard let value else {
            return placeholder
        }
        return cost(value)
    }

    static func pricePerMillion(_ value: Double) -> String {
        "$" + value.formatted(.number.precision(.fractionLength(2))) + " / 1M"
    }

    static func tokenBreakdown(input: Int, output: Int, cached: Int, reasoning: Int) -> String {
        "输入 \(integer(input)) · 输出 \(integer(output)) · 缓存 \(integer(cached)) · 推理 \(integer(reasoning))"
    }

    static func requestBreakdown(total: Int, successful: Int, failed: Int) -> String {
        "\(integer(total)) · 成功 \(integer(successful)) · 失败 \(integer(failed))"
    }

    static func resultTitle(isSuccess: Bool) -> String {
        isSuccess ? "成功" : "失败"
    }

    static func sensitiveIdentifier(_ value: String, masked: Bool) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "--"
        }

        guard masked else {
            return trimmed
        }

        if let atIndex = trimmed.firstIndex(of: "@") {
            let name = String(trimmed[..<atIndex])
            let domainStart = trimmed.index(after: atIndex)
            let domain = String(trimmed[domainStart...])
            return "\(visiblePrefix(name, count: 2))•••@\(maskedEmailDomain(domain))"
        }

        if trimmed.count <= 8 {
            return String(repeating: "•", count: min(trimmed.count, 4))
        }

        return "\(trimmed.prefix(4))•••\(trimmed.suffix(4))"
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .year()
                .month(.twoDigits)
                .day(.twoDigits)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .second(.twoDigits)
        )
    }

    static func shortTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func bucketLabel(_ date: Date, granularity: TrendGranularity) -> String {
        switch granularity {
        case .hour:
            shortTime(date)
        case .day:
            date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
        }
    }

    static func lastUpdated(_ date: Date?) -> String {
        guard let date else {
            return "尚未更新"
        }
        return "最后更新 \(dateTime(date))"
    }

    static func relativeTime(_ date: Date?, reference: Date = Date()) -> String {
        guard let date else {
            return "--"
        }

        let interval = max(0, reference.timeIntervalSince(date))
        if interval < 60 {
            return "剛剛"
        }

        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "\(minutes) 分鐘前"
        }

        let hours = Int(interval / 3_600)
        if hours < 24 {
            return "\(hours) 小時前"
        }

        let days = Int(interval / 86_400)
        if days < 30 {
            return "\(days) 天前"
        }

        return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
    }

    nonisolated static func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") || escaped.contains("\r") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    nonisolated static func csvRow(_ values: [String]) -> String {
        values.map(csvField).joined(separator: ",")
    }

    private static func visiblePrefix(_ value: String, count: Int) -> String {
        guard !value.isEmpty else {
            return ""
        }
        return String(value.prefix(max(1, min(value.count, count))))
    }

    private static func maskedEmailDomain(_ domain: String) -> String {
        guard !domain.isEmpty else {
            return "•••"
        }

        let parts = domain.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            return "\(String(parts[0].prefix(1)))•••.\(parts[1])"
        }

        return "\(String(domain.prefix(1)))•••"
    }
}

enum UsageDateParser {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: Any?) -> Date? {
        if let date = value as? Date {
            return date
        }

        if let jsonValue = value as? JSONValue {
            switch jsonValue {
            case let .string(string):
                return parse(string)
            case let .number(number):
                return dateFromNumber(number)
            default:
                return nil
            }
        }

        if let seconds = value as? Double {
            return dateFromNumber(seconds)
        }

        if let integer = value as? Int {
            return dateFromNumber(Double(integer))
        }

        guard let string = value as? String else {
            return nil
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }

        if let number = Double(trimmed) {
            return dateFromNumber(number)
        }

        if let date = isoFormatter.date(from: trimmed) ?? isoFormatterNoFraction.date(from: trimmed) {
            return date
        }

        let formatters = [
            "yyyy/MM/dd HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        ]

        for pattern in formatters {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return nil
    }

    private static func dateFromNumber(_ number: Double) -> Date {
        if number > 10_000_000_000 {
            return Date(timeIntervalSince1970: number / 1_000)
        }

        return Date(timeIntervalSince1970: number)
    }
}
