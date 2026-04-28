import Foundation

enum UsageExportFormat: String, CaseIterable, Identifiable, Hashable {
    case csv
    case json

    var id: String { rawValue }

    var title: String {
        switch self {
        case .csv:
            "CSV"
        case .json:
            "JSON"
        }
    }

    var fileExtension: String {
        rawValue
    }
}

enum UsageExportService {
    struct EventExportRecord: Encodable {
        var time: Date
        var endpoint: String
        var model: String
        var source: String
        var provider: String
        var authIndex: String
        var result: String
        var statusCode: Int?
        var errorMessage: String
        var latencyMs: Double
        var inputTokens: Int
        var outputTokens: Int
        var reasoningTokens: Int
        var cachedTokens: Int
        var totalTokens: Int

        init(event: RequestEvent, masked: Bool = false) {
            self.time = event.timestamp
            self.endpoint = UsageExportService.displayedSensitiveValue(event.endpoint, masked: masked)
            self.model = event.model
            self.source = UsageExportService.displayedSensitiveValue(event.source, masked: masked)
            self.provider = event.provider
            self.authIndex = UsageExportService.displayedSensitiveValue(event.authIndex, masked: masked)
            self.result = event.resultTitle
            self.statusCode = event.statusCode
            self.errorMessage = UsageExportService.displayedErrorMessage(for: event, masked: masked)
            self.latencyMs = event.latencyMs
            self.inputTokens = event.inputTokens
            self.outputTokens = event.outputTokens
            self.reasoningTokens = event.reasoningTokens
            self.cachedTokens = event.cachedTokens
            self.totalTokens = event.totalTokens
        }
    }

    static func data(
        for events: [RequestEvent],
        format: UsageExportFormat,
        masked: Bool = false
    ) throws -> Data {
        switch format {
        case .csv:
            csvData(for: events, masked: masked)
        case .json:
            try jsonData(for: events, masked: masked)
        }
    }

    static func csvData(for events: [RequestEvent], masked: Bool = false) -> Data {
        Data(csvString(for: events, masked: masked).utf8)
    }

    static func csvString(for events: [RequestEvent], masked: Bool = false) -> String {
        let headers = [
            "time",
            "endpoint",
            "model",
            "source",
            "provider",
            "auth_index",
            "result",
            "status_code",
            "error_message",
            "latency_ms",
            "input_tokens",
            "output_tokens",
            "reasoning_tokens",
            "cached_tokens",
            "total_tokens"
        ]
        let rows = events.map { csvRow(for: $0, masked: masked) }
        return ([UsageFormatters.csvRow(headers)] + rows).joined(separator: "\n") + "\n"
    }

    static func jsonData(for events: [RequestEvent], masked: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(events.map { EventExportRecord(event: $0, masked: masked) })
    }

    static func suggestedFilename(
        format: UsageExportFormat,
        now: Date = Date()
    ) -> String {
        "usage-events-\(filenameDateFormatter.string(from: now)).\(format.fileExtension)"
    }

    private static func csvRow(for event: RequestEvent, masked: Bool) -> String {
        UsageFormatters.csvRow([
            UsageFormatters.dateTime(event.timestamp),
            displayedSensitiveValue(event.endpoint, masked: masked),
            event.model,
            displayedSensitiveValue(event.source, masked: masked),
            event.provider,
            displayedSensitiveValue(event.authIndex, masked: masked),
            event.resultTitle,
            event.statusCode.map(String.init) ?? "",
            displayedErrorMessage(for: event, masked: masked),
            UsageFormatters.decimal(event.latencyMs, digits: 2),
            String(event.inputTokens),
            String(event.outputTokens),
            String(event.reasoningTokens),
            String(event.cachedTokens),
            String(event.totalTokens)
        ])
    }

    private static func displayedSensitiveValue(_ value: String, masked: Bool) -> String {
        UsageFormatters.sensitiveIdentifier(value, masked: masked)
    }

    private static func displayedErrorMessage(for event: RequestEvent, masked: Bool) -> String {
        guard masked else {
            return event.errorMessage
        }

        var scrubbed = event.errorMessage
        for rawValue in [event.endpoint, event.source, event.authIndex].filter({ !$0.isEmpty }) {
            scrubbed = scrubbed.replacingOccurrences(
                of: rawValue,
                with: displayedSensitiveValue(rawValue, masked: true)
            )
        }

        return scrubbed
    }

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
