import Foundation

enum UsageTimeRange: String, CaseIterable, Identifiable, Codable, Hashable {
    case all
    case last7Hours
    case last24Hours
    case last7Days

    static let defaultSelection: UsageTimeRange = .last24Hours

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "全部时间"
        case .last7Hours:
            "最近7小时"
        case .last24Hours:
            "最近24小时"
        case .last7Days:
            "最近7天"
        }
    }

    var queryValue: String {
        switch self {
        case .all:
            "all"
        case .last7Hours:
            "7h"
        case .last24Hours:
            "24h"
        case .last7Days:
            "7d"
        }
    }

    var hourWindow: Int? {
        switch self {
        case .all:
            nil
        case .last7Hours:
            7
        case .last24Hours:
            24
        case .last7Days:
            24 * 7
        }
    }

    func startDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let hourWindow else {
            return nil
        }
        return calendar.date(byAdding: .hour, value: -hourWindow, to: now)
    }

    func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let start = startDate(now: now, calendar: calendar) else {
            return true
        }
        return date >= start && date <= now
    }
}

enum TrendGranularity: String, CaseIterable, Identifiable, Codable, Hashable {
    case hour
    case day

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hour:
            "按小时"
        case .day:
            "按天"
        }
    }
}

enum DisplayCurrency: String, CaseIterable, Identifiable, Codable, Hashable {
    case usd = "USD"
    case cny = "CNY"

    static let defaultSelection: DisplayCurrency = .usd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usd:
            "USD"
        case .cny:
            "CNY"
        }
    }

    var symbol: String {
        switch self {
        case .usd:
            "$"
        case .cny:
            "¥"
        }
    }

    func convertedCost(fromUSD usdValue: Double, usdToCNYExchangeRate: Double) -> Double {
        switch self {
        case .usd:
            usdValue
        case .cny:
            usdValue * UsageCostDisplaySettings.sanitizeExchangeRate(usdToCNYExchangeRate)
        }
    }
}

enum CostCalculationBasis: String, CaseIterable, Identifiable, Codable, Hashable {
    case saved
    case estimate

    static let defaultSelection: CostCalculationBasis = .saved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saved:
            "saved"
        case .estimate:
            "estimate"
        }
    }
}

struct UsageCostDisplaySettings: Codable, Hashable {
    static let defaultUSDToCNYExchangeRate = 7.18
    static let `default` = UsageCostDisplaySettings()

    var displayCurrency: DisplayCurrency
    var usdToCNYExchangeRate: Double
    var calculationBasis: CostCalculationBasis

    init(
        displayCurrency: DisplayCurrency = .defaultSelection,
        usdToCNYExchangeRate: Double = Self.defaultUSDToCNYExchangeRate,
        calculationBasis: CostCalculationBasis = .defaultSelection
    ) {
        self.displayCurrency = displayCurrency
        self.usdToCNYExchangeRate = Self.sanitizeExchangeRate(usdToCNYExchangeRate)
        self.calculationBasis = calculationBasis
    }

    func convertedCost(fromUSD usdValue: Double?) -> Double? {
        guard let usdValue else {
            return nil
        }
        return displayCurrency.convertedCost(
            fromUSD: usdValue,
            usdToCNYExchangeRate: usdToCNYExchangeRate
        )
    }

    static func sanitizeExchangeRate(_ exchangeRate: Double) -> Double {
        guard exchangeRate.isFinite, exchangeRate > 0 else {
            return defaultUSDToCNYExchangeRate
        }
        return exchangeRate
    }

    private enum CodingKeys: String, CodingKey {
        case displayCurrency
        case usdToCNYExchangeRate
        case calculationBasis
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            displayCurrency: container.decode(DisplayCurrency.self, forKey: .displayCurrency, default: .defaultSelection),
            usdToCNYExchangeRate: container.decodeDouble(.usdToCNYExchangeRate, default: Self.defaultUSDToCNYExchangeRate),
            calculationBasis: container.decode(CostCalculationBasis.self, forKey: .calculationBasis, default: .defaultSelection)
        )
    }
}

enum UsageLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var errorMessage: String? {
        if case let .failed(message) = self {
            return message
        }
        return nil
    }
}

nonisolated struct ConnectionSettings: Codable, Hashable {
    var baseURL: String
    var managementKey: String

    static let defaultBaseURL = "http://127.0.0.1:8317/v0/management"

    static var empty: ConnectionSettings {
        ConnectionSettings(baseURL: defaultBaseURL, managementKey: "")
    }

    var hasManagementKey: Bool {
        !managementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(baseURL: String = Self.defaultBaseURL, managementKey: String = "") {
        self.baseURL = baseURL
        self.managementKey = managementKey
    }

    private enum CodingKeys: String, CodingKey {
        case baseURL
        case managementKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            baseURL: container.decodeString(.baseURL, default: Self.defaultBaseURL),
            managementKey: container.decodeString(.managementKey)
        )
    }
}

struct UsageSummary: Codable, Hashable {
    var totalRequests: Int
    var successfulRequests: Int
    var failedRequests: Int
    var averageLatencyMs: Double
    var totalLatencyMs: Double
    var totalTokens: Int
    var inputTokens: Int
    var outputTokens: Int
    var cachedTokens: Int
    var reasoningTokens: Int
    var rpm: Double
    var tpm: Double
    var totalCost: Double?

    var successRate: Double {
        guard totalRequests > 0 else {
            return 0
        }
        return Double(successfulRequests) / Double(totalRequests)
    }

    var failureRate: Double {
        guard totalRequests > 0 else {
            return 0
        }
        return Double(failedRequests) / Double(totalRequests)
    }

    init(
        totalRequests: Int = 0,
        successfulRequests: Int = 0,
        failedRequests: Int = 0,
        averageLatencyMs: Double = 0,
        totalLatencyMs: Double = 0,
        totalTokens: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cachedTokens: Int = 0,
        reasoningTokens: Int = 0,
        rpm: Double = 0,
        tpm: Double = 0,
        totalCost: Double? = nil
    ) {
        self.totalRequests = totalRequests
        self.successfulRequests = successfulRequests
        self.failedRequests = failedRequests
        self.averageLatencyMs = averageLatencyMs
        self.totalLatencyMs = totalLatencyMs
        self.totalTokens = totalTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.reasoningTokens = reasoningTokens
        self.rpm = rpm
        self.tpm = tpm
        self.totalCost = totalCost
    }

    private enum CodingKeys: String, CodingKey {
        case totalRequests
        case successfulRequests
        case failedRequests
        case averageLatencyMs
        case totalLatencyMs
        case totalTokens
        case inputTokens
        case outputTokens
        case cachedTokens
        case reasoningTokens
        case rpm
        case tpm
        case totalCost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            totalRequests: container.decodeInt(.totalRequests),
            successfulRequests: container.decodeInt(.successfulRequests),
            failedRequests: container.decodeInt(.failedRequests),
            averageLatencyMs: container.decodeDouble(.averageLatencyMs),
            totalLatencyMs: container.decodeDouble(.totalLatencyMs),
            totalTokens: container.decodeInt(.totalTokens),
            inputTokens: container.decodeInt(.inputTokens),
            outputTokens: container.decodeInt(.outputTokens),
            cachedTokens: container.decodeInt(.cachedTokens),
            reasoningTokens: container.decodeInt(.reasoningTokens),
            rpm: container.decodeDouble(.rpm),
            tpm: container.decodeDouble(.tpm),
            totalCost: container.decodeOptionalDouble(.totalCost)
        )
    }
}

struct EndpointModelStat: Identifiable, Codable, Hashable {
    var id: String { "\(endpoint)|\(model)" }
    var endpoint: String
    var model: String
    var requests: Int
    var successfulRequests: Int
    var failedRequests: Int
    var totalTokens: Int
    var averageLatencyMs: Double
    var totalLatencyMs: Double
    var cost: Double?

    var successRate: Double {
        guard requests > 0 else {
            return 0
        }
        return Double(successfulRequests) / Double(requests)
    }

    var requestBreakdown: String {
        "\(requests) (\(successfulRequests) \(failedRequests))"
    }

    init(
        endpoint: String = "",
        model: String = "",
        requests: Int = 0,
        successfulRequests: Int = 0,
        failedRequests: Int = 0,
        totalTokens: Int = 0,
        averageLatencyMs: Double = 0,
        totalLatencyMs: Double = 0,
        cost: Double? = nil
    ) {
        self.endpoint = endpoint
        self.model = model
        self.requests = requests
        self.successfulRequests = successfulRequests
        self.failedRequests = failedRequests
        self.totalTokens = totalTokens
        self.averageLatencyMs = averageLatencyMs
        self.totalLatencyMs = totalLatencyMs
        self.cost = cost
    }

    private enum CodingKeys: String, CodingKey {
        case endpoint
        case model
        case requests
        case successfulRequests
        case failedRequests
        case totalTokens
        case averageLatencyMs
        case totalLatencyMs
        case cost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            endpoint: container.decodeString(.endpoint),
            model: container.decodeString(.model),
            requests: container.decodeInt(.requests),
            successfulRequests: container.decodeInt(.successfulRequests),
            failedRequests: container.decodeInt(.failedRequests),
            totalTokens: container.decodeInt(.totalTokens),
            averageLatencyMs: container.decodeOptionalDouble(.averageLatencyMs) ?? 0,
            totalLatencyMs: container.decodeOptionalDouble(.totalLatencyMs) ?? 0,
            cost: container.decodeOptionalDouble(.cost)
        )
    }
}

struct EndpointUsageStat: Identifiable, Codable, Hashable {
    var id: String { endpoint }
    var endpoint: String
    var requests: Int
    var successfulRequests: Int
    var failedRequests: Int
    var totalTokens: Int
    var averageLatencyMs: Double
    var totalLatencyMs: Double
    var cost: Double?
    var models: [EndpointModelStat]

    var successRate: Double {
        guard requests > 0 else {
            return 0
        }
        return Double(successfulRequests) / Double(requests)
    }

    var requestBreakdown: String {
        "\(requests) (\(successfulRequests) \(failedRequests))"
    }

    init(
        endpoint: String = "",
        requests: Int = 0,
        successfulRequests: Int = 0,
        failedRequests: Int = 0,
        totalTokens: Int = 0,
        averageLatencyMs: Double = 0,
        totalLatencyMs: Double = 0,
        cost: Double? = nil,
        models: [EndpointModelStat] = []
    ) {
        self.endpoint = endpoint
        self.requests = requests
        self.successfulRequests = successfulRequests
        self.failedRequests = failedRequests
        self.totalTokens = totalTokens
        self.averageLatencyMs = averageLatencyMs
        self.totalLatencyMs = totalLatencyMs
        self.cost = cost
        self.models = models
    }

    private enum CodingKeys: String, CodingKey {
        case endpoint
        case requests
        case successfulRequests
        case failedRequests
        case totalTokens
        case averageLatencyMs
        case totalLatencyMs
        case cost
        case models
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            endpoint: container.decodeString(.endpoint),
            requests: container.decodeInt(.requests),
            successfulRequests: container.decodeInt(.successfulRequests),
            failedRequests: container.decodeInt(.failedRequests),
            totalTokens: container.decodeInt(.totalTokens),
            averageLatencyMs: container.decodeOptionalDouble(.averageLatencyMs) ?? 0,
            totalLatencyMs: container.decodeOptionalDouble(.totalLatencyMs) ?? 0,
            cost: container.decodeOptionalDouble(.cost),
            models: container.decodeArray([EndpointModelStat].self, forKey: .models)
        )
    }
}

struct ModelUsageStat: Identifiable, Codable, Hashable {
    var id: String { model }
    var model: String
    var requests: Int
    var successfulRequests: Int
    var failedRequests: Int
    var totalTokens: Int
    var averageLatencyMs: Double
    var totalLatencyMs: Double
    var successRate: Double
    var cost: Double?

    var requestBreakdown: String {
        "\(requests) (\(successfulRequests) \(failedRequests))"
    }

    init(
        model: String = "",
        requests: Int = 0,
        successfulRequests: Int = 0,
        failedRequests: Int = 0,
        totalTokens: Int = 0,
        averageLatencyMs: Double = 0,
        totalLatencyMs: Double = 0,
        successRate: Double? = nil,
        cost: Double? = nil
    ) {
        self.model = model
        self.requests = requests
        self.successfulRequests = successfulRequests
        self.failedRequests = failedRequests
        self.totalTokens = totalTokens
        self.averageLatencyMs = averageLatencyMs
        self.totalLatencyMs = totalLatencyMs
        self.successRate = successRate ?? Self.rate(successful: successfulRequests, total: requests)
        self.cost = cost
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case requests
        case successfulRequests
        case failedRequests
        case totalTokens
        case averageLatencyMs
        case totalLatencyMs
        case successRate
        case cost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            model: container.decodeString(.model),
            requests: container.decodeInt(.requests),
            successfulRequests: container.decodeInt(.successfulRequests),
            failedRequests: container.decodeInt(.failedRequests),
            totalTokens: container.decodeInt(.totalTokens),
            averageLatencyMs: container.decodeDouble(.averageLatencyMs),
            totalLatencyMs: container.decodeDouble(.totalLatencyMs),
            successRate: container.decodeOptionalDouble(.successRate),
            cost: container.decodeOptionalDouble(.cost)
        )
    }

    private static func rate(successful: Int, total: Int) -> Double {
        guard total > 0 else {
            return 0
        }
        return Double(successful) / Double(total)
    }
}

struct RequestEvent: Identifiable, Codable, Hashable {
    var id: String
    var timestamp: Date
    var endpoint: String
    var model: String
    var source: String
    var provider: String
    var authIndex: String
    var isSuccess: Bool
    var statusCode: Int?
    var errorMessage: String
    var latencyMs: Double
    var inputTokens: Int
    var outputTokens: Int
    var reasoningTokens: Int
    var cachedTokens: Int
    var totalTokens: Int
    var metadata: [String: JSONValue]

    var resultTitle: String {
        isSuccess ? "成功" : "失败"
    }

    var sourceTitle: String {
        provider.isEmpty ? source : "\(source) · \(provider)"
    }

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(timeIntervalSince1970: 0),
        endpoint: String = "",
        model: String = "",
        source: String = "",
        provider: String = "",
        authIndex: String = "",
        isSuccess: Bool = false,
        statusCode: Int? = nil,
        errorMessage: String = "",
        latencyMs: Double = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        reasoningTokens: Int = 0,
        cachedTokens: Int = 0,
        totalTokens: Int = 0,
        metadata: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.endpoint = endpoint
        self.model = model
        self.source = source
        self.provider = provider
        self.authIndex = authIndex
        self.isSuccess = isSuccess
        self.statusCode = statusCode
        self.errorMessage = errorMessage
        self.latencyMs = latencyMs
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.cachedTokens = cachedTokens
        self.totalTokens = totalTokens
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case endpoint
        case model
        case source
        case provider
        case authIndex
        case isSuccess
        case statusCode
        case errorMessage
        case latencyMs
        case inputTokens
        case outputTokens
        case reasoningTokens
        case cachedTokens
        case totalTokens
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: container.decodeString(.id, default: UUID().uuidString),
            timestamp: container.decodeDate(.timestamp),
            endpoint: container.decodeString(.endpoint),
            model: container.decodeString(.model),
            source: container.decodeString(.source),
            provider: container.decodeString(.provider),
            authIndex: container.decodeString(.authIndex),
            isSuccess: container.decodeBool(.isSuccess),
            statusCode: container.decodeOptionalInt(.statusCode),
            errorMessage: container.decodeString(.errorMessage),
            latencyMs: container.decodeDouble(.latencyMs),
            inputTokens: container.decodeInt(.inputTokens),
            outputTokens: container.decodeInt(.outputTokens),
            reasoningTokens: container.decodeInt(.reasoningTokens),
            cachedTokens: container.decodeInt(.cachedTokens),
            totalTokens: container.decodeInt(.totalTokens),
            metadata: container.decodeJSONDictionary(.metadata)
        )
    }
}

struct CredentialUsageStat: Identifiable, Codable, Hashable {
    var id: String {
        [credential, source, provider]
            .filter { !$0.isEmpty }
            .joined(separator: "|")
    }

    var credential: String
    var source: String
    var provider: String
    var requests: Int
    var successfulRequests: Int
    var failedRequests: Int
    var successRate: Double
    var lastUsedAt: Date?

    var displayName: String {
        let context = [source, provider].filter { !$0.isEmpty }.joined(separator: " · ")
        return context.isEmpty ? credential : "\(credential) · \(context)"
    }

    var requestBreakdown: String {
        "\(requests) (\(successfulRequests) \(failedRequests))"
    }

    init(
        credential: String = "",
        source: String = "",
        provider: String = "",
        requests: Int = 0,
        successfulRequests: Int = 0,
        failedRequests: Int = 0,
        successRate: Double? = nil,
        lastUsedAt: Date? = nil
    ) {
        self.credential = credential
        self.source = source
        self.provider = provider
        self.requests = requests
        self.successfulRequests = successfulRequests
        self.failedRequests = failedRequests
        self.successRate = successRate ?? Self.rate(successful: successfulRequests, total: requests)
        self.lastUsedAt = lastUsedAt
    }

    private enum CodingKeys: String, CodingKey {
        case credential
        case source
        case provider
        case requests
        case successfulRequests
        case failedRequests
        case successRate
        case lastUsedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            credential: container.decodeString(.credential),
            source: container.decodeString(.source),
            provider: container.decodeString(.provider),
            requests: container.decodeInt(.requests),
            successfulRequests: container.decodeInt(.successfulRequests),
            failedRequests: container.decodeInt(.failedRequests),
            successRate: container.decodeOptionalDouble(.successRate),
            lastUsedAt: container.decodeOptionalDate(.lastUsedAt)
        )
    }

    private static func rate(successful: Int, total: Int) -> Double {
        guard total > 0 else {
            return 0
        }
        return Double(successful) / Double(total)
    }
}

struct ModelPriceSetting: Identifiable, Codable, Hashable {
    static let storedCurrency: DisplayCurrency = .usd

    var id: String { model }
    var model: String
    var promptPricePerMillion: Double
    var completionPricePerMillion: Double
    var cachePricePerMillion: Double

    static let empty = ModelPriceSetting(
        model: "",
        promptPricePerMillion: 0,
        completionPricePerMillion: 0,
        cachePricePerMillion: 0
    )

    var hasConfiguredPrice: Bool {
        promptPricePerMillion > 0 || completionPricePerMillion > 0 || cachePricePerMillion > 0
    }

    var priceCurrency: DisplayCurrency {
        Self.storedCurrency
    }

    var sanitized: ModelPriceSetting {
        ModelPriceSetting(
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            promptPricePerMillion: Self.sanitizePrice(promptPricePerMillion),
            completionPricePerMillion: Self.sanitizePrice(completionPricePerMillion),
            cachePricePerMillion: Self.sanitizePrice(cachePricePerMillion)
        )
    }

    init(
        model: String = "",
        promptPricePerMillion: Double = 0,
        completionPricePerMillion: Double = 0,
        cachePricePerMillion: Double = 0
    ) {
        self.model = model
        self.promptPricePerMillion = promptPricePerMillion
        self.completionPricePerMillion = completionPricePerMillion
        self.cachePricePerMillion = cachePricePerMillion
    }

    func estimatedCost(inputTokens: Int, outputTokens: Int, cachedTokens: Int = 0) -> Double {
        let promptCost = Double(inputTokens) / 1_000_000 * promptPricePerMillion
        let completionCost = Double(outputTokens) / 1_000_000 * completionPricePerMillion
        let cacheCost = Double(cachedTokens) / 1_000_000 * cachePricePerMillion
        return promptCost + completionCost + cacheCost
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case promptPricePerMillion
        case completionPricePerMillion
        case cachePricePerMillion
    }

    private enum AliasCodingKeys: String, CodingKey {
        case prompt
        case input
        case inputPricePerMillion
        case completion
        case output
        case outputPricePerMillion
        case cache
        case cached
        case cachedPricePerMillion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let aliases = try decoder.container(keyedBy: AliasCodingKeys.self)
        self.init(
            model: container.decodeString(.model),
            promptPricePerMillion: Self.sanitizePrice(
                container.decodeDouble(
                    .promptPricePerMillion,
                    default: aliases.decodeDouble(
                        .inputPricePerMillion,
                        default: aliases.decodeDouble(
                            .prompt,
                            default: aliases.decodeDouble(.input)
                        )
                    )
                )
            ),
            completionPricePerMillion: Self.sanitizePrice(
                container.decodeDouble(
                    .completionPricePerMillion,
                    default: aliases.decodeDouble(
                        .outputPricePerMillion,
                        default: aliases.decodeDouble(
                            .completion,
                            default: aliases.decodeDouble(.output)
                        )
                    )
                )
            ),
            cachePricePerMillion: Self.sanitizePrice(
                container.decodeDouble(
                    .cachePricePerMillion,
                    default: aliases.decodeDouble(
                        .cachedPricePerMillion,
                        default: aliases.decodeDouble(
                            .cache,
                            default: aliases.decodeDouble(.cached)
                        )
                    )
                )
            )
        )
    }

    static func sanitizePrice(_ price: Double) -> Double {
        guard price.isFinite else {
            return 0
        }
        return max(price, 0)
    }
}

struct ModelPriceDraft: Codable, Hashable {
    var model: String
    var promptPricePerMillion: Double
    var completionPricePerMillion: Double
    var cachePricePerMillion: Double

    init(
        model: String = "",
        promptPricePerMillion: Double = 0,
        completionPricePerMillion: Double = 0,
        cachePricePerMillion: Double = 0
    ) {
        self.model = model
        self.promptPricePerMillion = promptPricePerMillion
        self.completionPricePerMillion = completionPricePerMillion
        self.cachePricePerMillion = cachePricePerMillion
    }

    init(price: ModelPriceSetting) {
        self.init(
            model: price.model,
            promptPricePerMillion: price.promptPricePerMillion,
            completionPricePerMillion: price.completionPricePerMillion,
            cachePricePerMillion: price.cachePricePerMillion
        )
    }

    var sanitizedPrice: ModelPriceSetting {
        ModelPriceSetting(
            model: model,
            promptPricePerMillion: promptPricePerMillion,
            completionPricePerMillion: completionPricePerMillion,
            cachePricePerMillion: cachePricePerMillion
        ).sanitized
    }

    func hasUnsavedChanges(comparedTo savedPrice: ModelPriceSetting?) -> Bool {
        sanitizedPrice != savedPrice?.sanitized
    }
}

struct UsageTrendPoint: Identifiable, Codable, Hashable {
    var id: String { "\(bucket.timeIntervalSince1970)-\(model)" }
    var bucket: Date
    var model: String
    var requests: Int
    var successfulRequests: Int
    var failedRequests: Int
    var tokens: Int
    var inputTokens: Int
    var outputTokens: Int
    var cachedTokens: Int
    var reasoningTokens: Int
    var averageLatencyMs: Double
    var cost: Double?

    var successRate: Double {
        guard requests > 0 else {
            return 0
        }
        return Double(successfulRequests) / Double(requests)
    }

    init(
        bucket: Date = Date(timeIntervalSince1970: 0),
        model: String = "",
        requests: Int = 0,
        successfulRequests: Int = 0,
        failedRequests: Int = 0,
        tokens: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cachedTokens: Int = 0,
        reasoningTokens: Int = 0,
        averageLatencyMs: Double = 0,
        cost: Double? = nil
    ) {
        self.bucket = bucket
        self.model = model
        self.requests = requests
        self.successfulRequests = successfulRequests
        self.failedRequests = failedRequests
        self.tokens = tokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.reasoningTokens = reasoningTokens
        self.averageLatencyMs = averageLatencyMs
        self.cost = cost
    }

    private enum CodingKeys: String, CodingKey {
        case bucket
        case model
        case requests
        case successfulRequests
        case failedRequests
        case tokens
        case inputTokens
        case outputTokens
        case cachedTokens
        case reasoningTokens
        case averageLatencyMs
        case cost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            bucket: container.decodeDate(.bucket),
            model: container.decodeString(.model),
            requests: container.decodeInt(.requests),
            successfulRequests: container.decodeInt(.successfulRequests),
            failedRequests: container.decodeInt(.failedRequests),
            tokens: container.decodeInt(.tokens),
            inputTokens: container.decodeInt(.inputTokens),
            outputTokens: container.decodeInt(.outputTokens),
            cachedTokens: container.decodeInt(.cachedTokens),
            reasoningTokens: container.decodeInt(.reasoningTokens),
            averageLatencyMs: container.decodeDouble(.averageLatencyMs),
            cost: container.decodeOptionalDouble(.cost)
        )
    }
}

struct UsageSnapshot: Codable, Hashable {
    var summary: UsageSummary
    var endpoints: [EndpointUsageStat]
    var models: [ModelUsageStat]
    var events: [RequestEvent]
    var credentials: [CredentialUsageStat]
    var trends: [UsageTrendPoint]
    var timeRange: UsageTimeRange
    var generatedAt: Date?
    var sourceDescription: String
    var rawPayload: UsageRawPayload?

    static let empty = UsageSnapshot()

    init(
        summary: UsageSummary = UsageSummary(),
        endpoints: [EndpointUsageStat] = [],
        models: [ModelUsageStat] = [],
        events: [RequestEvent] = [],
        credentials: [CredentialUsageStat] = [],
        trends: [UsageTrendPoint] = [],
        timeRange: UsageTimeRange = .defaultSelection,
        generatedAt: Date? = nil,
        sourceDescription: String = "未连接",
        rawPayload: UsageRawPayload? = nil
    ) {
        self.summary = summary
        self.endpoints = endpoints
        self.models = models
        self.events = events
        self.credentials = credentials
        self.trends = trends
        self.timeRange = timeRange
        self.generatedAt = generatedAt
        self.sourceDescription = sourceDescription
        self.rawPayload = rawPayload
    }

    private enum CodingKeys: String, CodingKey {
        case summary
        case endpoints
        case models
        case events
        case credentials
        case trends
        case timeRange
        case generatedAt
        case sourceDescription
        case rawPayload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            summary: container.decode(UsageSummary.self, forKey: .summary, default: UsageSummary()),
            endpoints: container.decodeArray([EndpointUsageStat].self, forKey: .endpoints),
            models: container.decodeArray([ModelUsageStat].self, forKey: .models),
            events: container.decodeArray([RequestEvent].self, forKey: .events),
            credentials: container.decodeArray([CredentialUsageStat].self, forKey: .credentials),
            trends: container.decodeArray([UsageTrendPoint].self, forKey: .trends),
            timeRange: container.decode(UsageTimeRange.self, forKey: .timeRange, default: .defaultSelection),
            generatedAt: container.decodeOptionalDate(.generatedAt),
            sourceDescription: container.decodeString(.sourceDescription, default: "未连接"),
            rawPayload: container.decodeOptional(UsageRawPayload.self, forKey: .rawPayload)
        )
    }
}

struct RequestEventFilters: Codable, Hashable {
    var model: String
    var source: String
    var authIndex: String

    static let empty = RequestEventFilters()

    var isActive: Bool {
        !model.isEmpty || !source.isEmpty || !authIndex.isEmpty
    }

    init(model: String = "", source: String = "", authIndex: String = "") {
        self.model = model
        self.source = source
        self.authIndex = authIndex
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case source
        case authIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            model: container.decodeString(.model),
            source: container.decodeString(.source),
            authIndex: container.decodeString(.authIndex)
        )
    }
}

enum UsageSortDirection: String, CaseIterable, Identifiable, Codable, Hashable {
    case ascending
    case descending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ascending:
            "升序"
        case .descending:
            "降序"
        }
    }
}

enum EndpointSort: String, CaseIterable, Identifiable, Codable, Hashable {
    case endpoint
    case requests
    case tokens
    case cost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .endpoint:
            "API端点"
        case .requests:
            "请求次数"
        case .tokens:
            "Token数量"
        case .cost:
            "花费"
        }
    }
}

enum ModelSort: String, CaseIterable, Identifiable, Codable, Hashable {
    case model
    case requests
    case tokens
    case averageLatency
    case totalLatency
    case successRate
    case cost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .model:
            "模型名称"
        case .requests:
            "请求次数"
        case .tokens:
            "Token数量"
        case .averageLatency:
            "平均延迟"
        case .totalLatency:
            "总延迟"
        case .successRate:
            "成功率"
        case .cost:
            "花费"
        }
    }
}

enum EventSort: String, CaseIterable, Identifiable, Codable, Hashable {
    case time
    case model
    case source
    case authIndex
    case result
    case latency
    case tokens

    var id: String { rawValue }

    var title: String {
        switch self {
        case .time:
            "时间"
        case .model:
            "模型"
        case .source:
            "来源"
        case .authIndex:
            "凭证"
        case .result:
            "结果"
        case .latency:
            "延迟"
        case .tokens:
            "Token"
        }
    }
}

enum CredentialSort: String, CaseIterable, Identifiable, Codable, Hashable {
    case credential
    case provider
    case requests
    case successRate
    case lastUsed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .credential:
            "凭证"
        case .provider:
            "来源"
        case .requests:
            "请求次数"
        case .successRate:
            "成功率"
        case .lastUsed:
            "最后使用"
        }
    }
}

enum ModelPriceSort: String, CaseIterable, Identifiable, Codable, Hashable {
    case model
    case promptPrice
    case completionPrice
    case cachePrice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .model:
            "模型"
        case .promptPrice:
            "输入价格"
        case .completionPrice:
            "输出价格"
        case .cachePrice:
            "缓存价格"
        }
    }
}

enum UsageChartMetric: String, CaseIterable, Identifiable, Codable, Hashable {
    case requests
    case tokens
    case inputTokens
    case outputTokens
    case cachedTokens
    case reasoningTokens
    case cost
    case latency

    var id: String { rawValue }

    var title: String {
        switch self {
        case .requests:
            "请求"
        case .tokens:
            "总Token"
        case .inputTokens:
            "输入Token"
        case .outputTokens:
            "输出Token"
        case .cachedTokens:
            "缓存Token"
        case .reasoningTokens:
            "推理Token"
        case .cost:
            "花费"
        case .latency:
            "延迟"
        }
    }
}

struct EndpointSortState: Codable, Hashable {
    var column: EndpointSort
    var direction: UsageSortDirection

    init(column: EndpointSort = .requests, direction: UsageSortDirection = .descending) {
        self.column = column
        self.direction = direction
    }

    private enum CodingKeys: String, CodingKey {
        case column
        case direction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            column: container.decode(EndpointSort.self, forKey: .column, default: .requests),
            direction: container.decode(UsageSortDirection.self, forKey: .direction, default: .descending)
        )
    }
}

struct ModelSortState: Codable, Hashable {
    var column: ModelSort
    var direction: UsageSortDirection

    init(column: ModelSort = .requests, direction: UsageSortDirection = .descending) {
        self.column = column
        self.direction = direction
    }

    private enum CodingKeys: String, CodingKey {
        case column
        case direction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            column: container.decode(ModelSort.self, forKey: .column, default: .requests),
            direction: container.decode(UsageSortDirection.self, forKey: .direction, default: .descending)
        )
    }
}

struct EventSortState: Codable, Hashable {
    var column: EventSort
    var direction: UsageSortDirection

    init(column: EventSort = .time, direction: UsageSortDirection = .descending) {
        self.column = column
        self.direction = direction
    }

    private enum CodingKeys: String, CodingKey {
        case column
        case direction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            column: container.decode(EventSort.self, forKey: .column, default: .time),
            direction: container.decode(UsageSortDirection.self, forKey: .direction, default: .descending)
        )
    }
}

struct CredentialSortState: Codable, Hashable {
    var column: CredentialSort
    var direction: UsageSortDirection

    init(column: CredentialSort = .requests, direction: UsageSortDirection = .descending) {
        self.column = column
        self.direction = direction
    }

    private enum CodingKeys: String, CodingKey {
        case column
        case direction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            column: container.decode(CredentialSort.self, forKey: .column, default: .requests),
            direction: container.decode(UsageSortDirection.self, forKey: .direction, default: .descending)
        )
    }
}

struct ModelPriceSortState: Codable, Hashable {
    var column: ModelPriceSort
    var direction: UsageSortDirection

    init(column: ModelPriceSort = .model, direction: UsageSortDirection = .ascending) {
        self.column = column
        self.direction = direction
    }

    private enum CodingKeys: String, CodingKey {
        case column
        case direction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            column: container.decode(ModelPriceSort.self, forKey: .column, default: .model),
            direction: container.decode(UsageSortDirection.self, forKey: .direction, default: .ascending)
        )
    }
}

struct ChartSeriesSelection: Codable, Hashable {
    static let maxSelectedModels = 9

    var selectedModels: Set<String>

    init(selectedModels: Set<String> = []) {
        self.selectedModels = Set(selectedModels.prefix(Self.maxSelectedModels))
    }

    func contains(_ model: String) -> Bool {
        selectedModels.contains(model)
    }

    func adding(_ model: String) -> ChartSeriesSelection {
        guard !model.isEmpty, selectedModels.count < Self.maxSelectedModels else {
            return self
        }
        var copy = selectedModels
        copy.insert(model)
        return ChartSeriesSelection(selectedModels: copy)
    }

    func removing(_ model: String) -> ChartSeriesSelection {
        var copy = selectedModels
        copy.remove(model)
        return ChartSeriesSelection(selectedModels: copy)
    }

    private enum CodingKeys: String, CodingKey {
        case selectedModels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(selectedModels: container.decodeStringSet(.selectedModels))
    }
}

struct UsageRawPayload: Codable, Hashable {
    var root: JSONValue

    init(root: JSONValue = .object([:])) {
        self.root = root
    }

    init(from decoder: Decoder) throws {
        root = try JSONValue(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try root.encode(to: encoder)
    }

    var object: [String: JSONValue] {
        root.object ?? [:]
    }

    var records: [JSONValue] {
        if let array = root.array {
            return array
        }

        let recordKeys = ["events", "requests", "records", "rows", "items", "usage"]
        if let array = object.value(anyOf: recordKeys)?.array {
            return array
        }

        for envelopeKey in ["data", "payload", "result"] {
            guard let nested = object.value(for: envelopeKey)?.object else {
                continue
            }
            if let array = nested.value(anyOf: recordKeys)?.array {
                return array
            }
        }

        return []
    }
}

struct UsageImportResult: Codable, Hashable {
    var importedCount: Int
    var skippedCount: Int
    var message: String
    var rawPayload: UsageRawPayload?

    init(
        importedCount: Int = 0,
        skippedCount: Int = 0,
        message: String = "",
        rawPayload: UsageRawPayload? = nil
    ) {
        self.importedCount = importedCount
        self.skippedCount = skippedCount
        self.message = message
        self.rawPayload = rawPayload
    }

    private enum CodingKeys: String, CodingKey {
        case importedCount
        case skippedCount
        case message
        case rawPayload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            importedCount: container.decodeInt(.importedCount),
            skippedCount: container.decodeInt(.skippedCount),
            message: container.decodeString(.message),
            rawPayload: container.decodeOptional(UsageRawPayload.self, forKey: .rawPayload)
        )
    }
}

private extension KeyedDecodingContainer {
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: T) -> T {
        (try? decodeIfPresent(type, forKey: key)) ?? defaultValue
    }

    func decodeOptional<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }

    func decodeArray<T: Decodable>(_ type: [T].Type, forKey key: Key, default defaultValue: [T] = []) -> [T] {
        (try? decodeIfPresent(type, forKey: key)) ?? defaultValue
    }

    nonisolated func decodeString(_ key: Key, default defaultValue: String = "") -> String {
        if let value = try? decodeIfPresent(JSONValue.self, forKey: key),
           let string = value.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !string.isEmpty {
            return string
        }

        return (try? decodeIfPresent(String.self, forKey: key)) ?? defaultValue
    }

    func decodeInt(_ key: Key, default defaultValue: Int = 0) -> Int {
        if let value = try? decodeIfPresent(JSONValue.self, forKey: key),
           let int = value.int {
            return int
        }

        return (try? decodeIfPresent(Int.self, forKey: key)) ?? defaultValue
    }

    func decodeOptionalInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(JSONValue.self, forKey: key) {
            return value.int
        }

        return try? decodeIfPresent(Int.self, forKey: key)
    }

    func decodeDouble(_ key: Key, default defaultValue: Double = 0) -> Double {
        if let value = try? decodeIfPresent(JSONValue.self, forKey: key),
           let double = value.double {
            return double
        }

        return (try? decodeIfPresent(Double.self, forKey: key)) ?? defaultValue
    }

    func decodeOptionalDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(JSONValue.self, forKey: key) {
            return value.double
        }

        return try? decodeIfPresent(Double.self, forKey: key)
    }

    func decodeBool(_ key: Key, default defaultValue: Bool = false) -> Bool {
        if let value = try? decodeIfPresent(JSONValue.self, forKey: key),
           let bool = value.bool {
            return bool
        }

        return (try? decodeIfPresent(Bool.self, forKey: key)) ?? defaultValue
    }

    func decodeDate(_ key: Key, default defaultValue: Date = Date(timeIntervalSince1970: 0)) -> Date {
        decodeOptionalDate(key) ?? defaultValue
    }

    func decodeOptionalDate(_ key: Key) -> Date? {
        if let date = try? decodeIfPresent(Date.self, forKey: key) {
            return date
        }

        guard let value = try? decodeIfPresent(JSONValue.self, forKey: key) else {
            return nil
        }

        switch value {
        case let .string(string):
            return UsageDateParser.parse(string)
        case let .number(number):
            return UsageDateParser.parse(number)
        default:
            return nil
        }
    }

    func decodeStringSet(_ key: Key) -> Set<String> {
        if let values = try? decodeIfPresent([String].self, forKey: key) {
            return Set(values)
        }

        guard let value = try? decodeIfPresent(JSONValue.self, forKey: key) else {
            return []
        }

        if let array = value.array {
            return Set(array.compactMap { $0.string })
        }

        if let string = value.string, !string.isEmpty {
            return [string]
        }

        return []
    }

    func decodeJSONDictionary(_ key: Key, default defaultValue: [String: JSONValue] = [:]) -> [String: JSONValue] {
        if let value = try? decodeIfPresent([String: JSONValue].self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(JSONValue.self, forKey: key),
           let object = value.object {
            return object
        }

        return defaultValue
    }
}
