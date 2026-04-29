import Foundation

nonisolated struct UsagePreparedDashboardSnapshot {
    var snapshot: UsageSnapshot
    var events: [RequestEvent]
    var quotaSnapshots: [CredentialQuotaSnapshot]
}

nonisolated enum UsageAggregator {
    static func preparedDashboardSnapshot(
        from payload: UsageRawPayload,
        timeRange: UsageTimeRange = .defaultSelection,
        prices: [ModelPriceSetting] = [],
        now: Date = Date(),
        calendar: Calendar = .current,
        trendGranularity: TrendGranularity? = nil,
        costCalculationBasis: CostCalculationBasis = .defaultSelection
    ) -> UsagePreparedDashboardSnapshot {
        let events = events(
            from: payload,
            timeRange: timeRange,
            now: now,
            calendar: calendar
        )
        let quotaSnapshots = credentialQuotaSnapshots(from: events, capturedAt: now)
        let hotEvents = events.map { event -> RequestEvent in
            var event = event
            event.metadata = [:]
            return event
        }
        let snapshot = snapshot(
            from: hotEvents,
            timeRange: timeRange,
            prices: prices,
            now: now,
            calendar: calendar,
            trendGranularity: trendGranularity,
            costCalculationBasis: costCalculationBasis,
            credentialQuotas: quotaSnapshots
        )
        return UsagePreparedDashboardSnapshot(
            snapshot: snapshot,
            events: events,
            quotaSnapshots: quotaSnapshots
        )
    }

    static func snapshot(
        from payload: UsageRawPayload,
        timeRange: UsageTimeRange = .defaultSelection,
        prices: [ModelPriceSetting] = [],
        now: Date = Date(),
        calendar: Calendar = .current,
        trendGranularity: TrendGranularity? = nil,
        costCalculationBasis: CostCalculationBasis = .defaultSelection
    ) -> UsageSnapshot {
        let records = filteredRecords(
            from: payload.root,
            timeRange: timeRange,
            now: now,
            calendar: calendar
        )
        let pricedRecords = price(records, with: prices, basis: costCalculationBasis)
        let granularity = trendGranularity ?? inferredGranularity(
            for: timeRange,
            records: records
        )

        return UsageSnapshot(
            summary: summary(from: pricedRecords, timeRange: timeRange, now: now, calendar: calendar),
            endpoints: endpointStats(from: pricedRecords),
            models: modelStats(from: pricedRecords),
            events: eventRows(from: records),
            credentials: credentialStats(from: pricedRecords),
            credentialQuotas: events(from: payload, timeRange: timeRange, now: now, calendar: calendar).compactMap { quotaSnapshot(from: $0, capturedAt: now) },
            trends: trends(from: pricedRecords, granularity: granularity, calendar: calendar),
            timeRange: timeRange,
            generatedAt: generatedAt(from: payload.root) ?? now,
            sourceDescription: sourceDescription(from: payload.root),
            rawPayload: payload
        )
    }

    static func snapshot(
        from value: JSONValue,
        timeRange: UsageTimeRange = .defaultSelection,
        prices: [ModelPriceSetting] = [],
        now: Date = Date(),
        calendar: Calendar = .current,
        trendGranularity: TrendGranularity? = nil,
        costCalculationBasis: CostCalculationBasis = .defaultSelection
    ) -> UsageSnapshot {
        snapshot(
            from: UsageRawPayload(root: value),
            timeRange: timeRange,
            prices: prices,
            now: now,
            calendar: calendar,
            trendGranularity: trendGranularity,
            costCalculationBasis: costCalculationBasis
        )
    }

    static func aggregate(
        _ payload: UsageRawPayload,
        timeRange: UsageTimeRange = .defaultSelection,
        modelPrices: [ModelPriceSetting] = [],
        now: Date = Date(),
        calendar: Calendar = .current,
        trendGranularity: TrendGranularity? = nil,
        costCalculationBasis: CostCalculationBasis = .defaultSelection
    ) -> UsageSnapshot {
        snapshot(
            from: payload,
            timeRange: timeRange,
            prices: modelPrices,
            now: now,
            calendar: calendar,
            trendGranularity: trendGranularity,
            costCalculationBasis: costCalculationBasis
        )
    }

    static func aggregate(
        _ value: JSONValue,
        timeRange: UsageTimeRange = .defaultSelection,
        modelPrices: [ModelPriceSetting] = [],
        now: Date = Date(),
        calendar: Calendar = .current,
        trendGranularity: TrendGranularity? = nil,
        costCalculationBasis: CostCalculationBasis = .defaultSelection
    ) -> UsageSnapshot {
        snapshot(
            from: value,
            timeRange: timeRange,
            prices: modelPrices,
            now: now,
            calendar: calendar,
            trendGranularity: trendGranularity,
            costCalculationBasis: costCalculationBasis
        )
    }



    static func snapshot(
        from events: [RequestEvent],
        timeRange: UsageTimeRange = .defaultSelection,
        prices: [ModelPriceSetting] = [],
        now: Date = Date(),
        calendar: Calendar = .current,
        trendGranularity: TrendGranularity? = nil,
        costCalculationBasis: CostCalculationBasis = .defaultSelection,
        credentialQuotas: [CredentialQuotaSnapshot]? = nil
    ) -> UsageSnapshot {
        let filtered = events.filter { timeRange.contains($0.timestamp, now: now, calendar: calendar) }
        let records = filtered.map { record(from: $0) }
        let pricedRecords = price(records, with: prices, basis: costCalculationBasis)
        let granularity = trendGranularity ?? inferredGranularity(for: timeRange, records: records)
        return UsageSnapshot(
            summary: summary(from: pricedRecords, timeRange: timeRange, now: now, calendar: calendar),
            endpoints: endpointStats(from: pricedRecords),
            models: modelStats(from: pricedRecords),
            events: filtered.sorted { $0.timestamp > $1.timestamp },
            credentials: credentialStats(from: pricedRecords),
            credentialQuotas: credentialQuotas ?? filtered.compactMap { quotaSnapshot(from: $0, capturedAt: now) },
            trends: trends(from: pricedRecords, granularity: granularity, calendar: calendar),
            timeRange: timeRange,
            generatedAt: now,
            sourceDescription: "本地历史记录",
            rawPayload: nil
        )
    }

    static func healthBuckets(from events: [RequestEvent], now: Date = Date(), calendar: Calendar = .current) -> [HealthBucket] {
        let bucketSeconds: TimeInterval = 10 * 60
        let totalBuckets = 7 * 24 * 6
        let alignedNow = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / bucketSeconds) * bucketSeconds)
        let firstStart = alignedNow.addingTimeInterval(-bucketSeconds * TimeInterval(totalBuckets - 1))
        let grouped = Dictionary(grouping: events) { event -> Int in
            Int(floor(event.timestamp.timeIntervalSince(firstStart) / bucketSeconds))
        }
        return (0..<totalBuckets).map { index in
            let start = firstStart.addingTimeInterval(TimeInterval(index) * bucketSeconds)
            let bucketEvents = grouped[index, default: []].filter { $0.timestamp >= start && $0.timestamp < start.addingTimeInterval(bucketSeconds) }
            guard !bucketEvents.isEmpty else {
                return HealthBucket(start: start, end: start.addingTimeInterval(bucketSeconds))
            }
            let failed = bucketEvents.filter { !$0.isSuccess }.count
            let avgLatency = bucketEvents.map(\.latencyMs).reduce(0, +) / Double(bucketEvents.count)
            let successRate = Double(bucketEvents.count - failed) / Double(bucketEvents.count)
            let status: HealthBucketStatus
            if successRate < 0.75 || failed >= 3 {
                status = .failed
            } else if successRate < 0.95 || avgLatency >= 10_000 {
                status = .degraded
            } else if failed > 0 || avgLatency >= 5_000 {
                status = .warning
            } else {
                status = .healthy
            }
            return HealthBucket(start: start, end: start.addingTimeInterval(bucketSeconds), requests: bucketEvents.count, failedRequests: failed, averageLatencyMs: avgLatency, status: status)
        }
    }

    static func credentialQuotaSnapshots(from payload: UsageRawPayload, capturedAt: Date = Date()) -> [CredentialQuotaSnapshot] {
        credentialQuotaSnapshots(from: events(from: payload, timeRange: .all, now: capturedAt), capturedAt: capturedAt)
    }

    static func credentialQuotaSnapshots(from events: [RequestEvent], capturedAt: Date = Date()) -> [CredentialQuotaSnapshot] {
        events.compactMap { quotaSnapshot(from: $0, capturedAt: capturedAt) }
    }


    static func events(
        from payload: UsageRawPayload,
        timeRange: UsageTimeRange = .defaultSelection,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [RequestEvent] {
        eventRows(
            from: filteredRecords(
                from: payload.root,
                timeRange: timeRange,
                now: now,
                calendar: calendar
            )
        )
    }

    static func events(
        from value: JSONValue,
        timeRange: UsageTimeRange = .defaultSelection,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [RequestEvent] {
        events(
            from: UsageRawPayload(root: value),
            timeRange: timeRange,
            now: now,
            calendar: calendar
        )
    }
}

private nonisolated extension UsageAggregator {
    struct NormalizedRecord: Hashable {
        var event: RequestEvent
        var credential: String
        var requestCount: Int
        var successfulRequests: Int
        var failedRequests: Int
        var totalLatencyMs: Double
        var inputTokens: Int
        var outputTokens: Int
        var cachedTokens: Int
        var reasoningTokens: Int
        var totalTokens: Int
        var estimatedCost: Double?
    }

    struct PricedRecord {
        var record: NormalizedRecord
        var cost: Double?
    }



    static func record(from event: RequestEvent) -> NormalizedRecord {
        NormalizedRecord(
            event: event,
            credential: event.authIndex.isEmpty ? event.source : event.authIndex,
            requestCount: 1,
            successfulRequests: event.isSuccess ? 1 : 0,
            failedRequests: event.isSuccess ? 0 : 1,
            totalLatencyMs: event.latencyMs,
            inputTokens: event.inputTokens,
            outputTokens: event.outputTokens,
            cachedTokens: event.cachedTokens,
            reasoningTokens: event.reasoningTokens,
            totalTokens: event.totalTokens,
            estimatedCost: event.estimatedCost ?? event.metadata.value(anyOf: ["estimated_cost", "cost", "price"])?.double
        )
    }

    static func quotaSnapshot(from event: RequestEvent, capturedAt: Date) -> CredentialQuotaSnapshot? {
        let metadata = event.metadata
        let identity = [event.source, event.provider, event.authIndex].joined(separator: " ").lowercased()
        if identity.contains("api key") || identity.contains("apikey") || identity.contains("api_key") || identity.contains("endpoint") || event.authIndex.lowercased().hasPrefix("sk-") {
            return nil
        }
        let quotaObject = metadata.value(anyOf: ["quota", "limit", "usage", "subscription", "plan", "window", "period"])?.object ?? metadata
        let limit = quotaObject.value(anyOf: ["limit", "total", "quota", "max"])?.double
        let used = quotaObject.value(anyOf: ["used", "usage", "consumed", "current"])?.double
        let remaining = quotaObject.value(anyOf: ["remaining", "left", "available"])?.double
        let percent = quotaObject.value(anyOf: ["percent", "percentage", "usage_percent", "usagePercent"])?.double.map { $0 > 1 ? $0 / 100 : $0 }
        guard limit != nil || used != nil || remaining != nil || percent != nil else {
            return nil
        }
        let resetAt = quotaObject.value(anyOf: ["reset", "reset_at", "resetAt", "resets_at", "expires_at"])?.string.flatMap(UsageDateParser.parse)
        let windowTitle = quotaObject.value(anyOf: ["window", "period", "interval", "title"])?.string ?? "额度窗口"
        let usage = CredentialQuotaUsage(title: windowTitle, used: used, limit: limit, remaining: remaining, usagePercent: percent, resetAt: resetAt)
        let planTitle = metadata.value(anyOf: ["plan", "planTitle", "subscription", "tier"])?.string ?? ""
        return CredentialQuotaSnapshot(
            id: [event.provider, event.source, event.authIndex, windowTitle].joined(separator: ":"),
            credential: event.authIndex.isEmpty ? event.source : event.authIndex,
            source: event.source,
            provider: event.provider,
            providerTitle: event.provider.isEmpty ? event.source : event.provider,
            planTitle: planTitle,
            shortWindow: usage,
            capturedAt: capturedAt,
            rawMetadata: metadata
        )
    }


    struct TokenMetrics {
        var input: Int = 0
        var output: Int = 0
        var cached: Int = 0
        var reasoning: Int = 0
        var total: Int = 0
    }

    struct UsageAccumulator {
        var requests = 0
        var successfulRequests = 0
        var failedRequests = 0
        var totalLatencyMs: Double = 0
        var inputTokens = 0
        var outputTokens = 0
        var cachedTokens = 0
        var reasoningTokens = 0
        var totalTokens = 0
        var cost: Double?
        var lastUsedAt: Date?

        var averageLatencyMs: Double {
            guard requests > 0 else {
                return 0
            }
            return totalLatencyMs / Double(requests)
        }

        var successRate: Double {
            guard requests > 0 else {
                return 0
            }
            return Double(successfulRequests) / Double(requests)
        }

        mutating func add(_ pricedRecord: PricedRecord) {
            let record = pricedRecord.record
            requests += record.requestCount
            successfulRequests += record.successfulRequests
            failedRequests += record.failedRequests
            totalLatencyMs += record.totalLatencyMs
            inputTokens += record.inputTokens
            outputTokens += record.outputTokens
            cachedTokens += record.cachedTokens
            reasoningTokens += record.reasoningTokens
            totalTokens += record.totalTokens
            if let currentLastUsedAt = lastUsedAt {
                lastUsedAt = max(currentLastUsedAt, record.event.timestamp)
            } else {
                lastUsedAt = record.event.timestamp
            }

            if let recordCost = pricedRecord.cost {
                cost = (cost ?? 0) + recordCost
            }
        }
    }

    struct EndpointModelKey: Hashable {
        var endpoint: String
        var model: String
    }

    struct CredentialKey: Hashable {
        var credential: String
        var source: String
        var provider: String
    }

    struct TrendKey: Hashable {
        var bucket: Date
        var model: String
    }

    static let unknownModel = "未知模型"
    static let unknownEndpoint = "未命名端点"
    static let unknownSource = "未知来源"
    static let unknownCredential = "未标记"

    static let recordCollectionKeys: Set<String> = [
        "usagedetails",
        "details",
        "events",
        "event",
        "requests",
        "requestevents",
        "logs",
        "records",
        "record",
        "rows",
        "items",
        "data",
        "result",
        "results"
    ]

    static let dateKeys = [
        "timestamp",
        "time",
        "date",
        "datetime",
        "createdAt",
        "created_at",
        "created",
        "requestTime",
        "request_time",
        "startedAt",
        "started_at",
        "endedAt",
        "ended_at",
        "completedAt",
        "completed_at"
    ]

    static let generatedAtKeys = [
        "generatedAt",
        "generated_at",
        "updatedAt",
        "updated_at",
        "lastUpdated",
        "last_updated",
        "timestamp"
    ]

    static let modelKeys = [
        "model",
        "modelName",
        "model_name",
        "modelId",
        "model_id",
        "deployment",
        "deploymentName",
        "engine",
        "apiModel",
        "api_model"
    ]

    static let endpointKeys = [
        "endpoint",
        "apiEndpoint",
        "api_endpoint",
        "path",
        "route",
        "url",
        "requestPath",
        "request_path",
        "apiKey",
        "api_key",
        "key",
        "keyName",
        "key_name",
        "authKey",
        "auth_key",
        "credential",
        "credentialName",
        "credential_name"
    ]

    static let sourceKeys = [
        "source",
        "client",
        "clientName",
        "client_name",
        "origin",
        "service",
        "serviceName",
        "service_name"
    ]

    static let providerKeys = [
        "provider",
        "vendor",
        "apiProvider",
        "api_provider",
        "backend",
        "platform"
    ]

    static let authIndexKeys = [
        "authIndex",
        "auth_index",
        "apiKeyIndex",
        "api_key_index",
        "keyIndex",
        "key_index",
        "credentialIndex",
        "credential_index",
        "credentialId",
        "credential_id"
    ]

    static let credentialKeys = [
        "credential",
        "credentialName",
        "credential_name",
        "credentialId",
        "credential_id",
        "apiKey",
        "api_key",
        "key",
        "keyName",
        "key_name",
        "authKey",
        "auth_key"
    ]

    static let statusCodeKeys = [
        "statusCode",
        "status_code",
        "httpStatus",
        "http_status",
        "code",
        "responseCode",
        "response_code"
    ]

    static let successValueKeys = [
        "isSuccess",
        "is_success",
        "success",
        "successful",
        "ok",
        "succeeded",
        "completed"
    ]

    static let resultKeys = [
        "result",
        "status",
        "state",
        "outcome"
    ]

    static let errorKeys = [
        "error",
        "errorMessage",
        "error_message",
        "failureReason",
        "failure_reason"
    ]

    static let costKeys = [
        "cost",
        "totalCost",
        "total_cost",
        "usageCost",
        "usage_cost",
        "estimatedCost",
        "estimated_cost",
        "estimatedCostUSD",
        "estimated_cost_usd",
        "costUSD",
        "cost_usd",
        "totalPrice",
        "total_price"
    ]

    static let requestCountKeys = [
        "requestCount",
        "request_count",
        "requests",
        "totalRequests",
        "total_requests",
        "count",
        "calls",
        "callCount",
        "call_count",
        "hits"
    ]

    static let successfulCountKeys = [
        "successfulRequests",
        "successful_requests",
        "successCount",
        "success_count",
        "succeededRequests",
        "succeeded_requests",
        "okRequests",
        "ok_requests"
    ]

    static let failedCountKeys = [
        "failedRequests",
        "failed_requests",
        "failureCount",
        "failure_count",
        "failures",
        "errors",
        "errorCount",
        "error_count",
        "failed",
        "failCount",
        "fail_count"
    ]

    static let latencyAverageKeys = [
        "latency_ms",
        "latencyMs",
        "latency",
        "averageLatencyMs",
        "average_latency_ms",
        "avgLatencyMs",
        "avg_latency_ms",
        "durationMs",
        "duration_ms",
        "elapsedMs",
        "elapsed_ms",
        "responseTimeMs",
        "response_time_ms",
        "processingTimeMs",
        "processing_time_ms",
        "timeMs",
        "time_ms",
        "latencyS",
        "latency_s",
        "latencySeconds",
        "latency_seconds",
        "durationS",
        "duration_s",
        "durationSeconds",
        "duration_seconds"
    ]

    static let latencyTotalKeys = [
        "totalLatencyMs",
        "total_latency_ms",
        "latencyTotalMs",
        "latency_total_ms",
        "durationTotalMs",
        "duration_total_ms",
        "totalDurationMs",
        "total_duration_ms",
        "totalLatencyS",
        "total_latency_s",
        "totalLatencySeconds",
        "total_latency_seconds"
    ]

    static let inputTokenKeys = [
        "inputTokens",
        "input_tokens",
        "promptTokens",
        "prompt_tokens",
        "requestTokens",
        "request_tokens",
        "tokensIn",
        "tokens_in",
        "input",
        "prompt",
        "promptTokenCount",
        "prompt_token_count"
    ]

    static let outputTokenKeys = [
        "outputTokens",
        "output_tokens",
        "completionTokens",
        "completion_tokens",
        "responseTokens",
        "response_tokens",
        "tokensOut",
        "tokens_out",
        "output",
        "completion",
        "completionTokenCount",
        "completion_token_count"
    ]

    static let cachedTokenKeys = [
        "cachedTokens",
        "cached_tokens",
        "cacheTokens",
        "cache_tokens",
        "cacheReadTokens",
        "cache_read_tokens",
        "cacheCreationTokens",
        "cache_creation_tokens",
        "cacheReadInputTokens",
        "cache_read_input_tokens",
        "cacheCreationInputTokens",
        "cache_creation_input_tokens",
        "cachedInputTokens",
        "cached_input_tokens",
        "cached",
        "cache"
    ]

    static let reasoningTokenKeys = [
        "reasoningTokens",
        "reasoning_tokens",
        "thinkingTokens",
        "thinking_tokens",
        "reasoning",
        "thinking",
        "reasoningTokenCount",
        "reasoning_token_count"
    ]

    static let totalTokenKeys = [
        "totalTokens",
        "total_tokens",
        "tokens",
        "tokenCount",
        "token_count",
        "usageTokens",
        "usage_tokens",
        "totalTokenCount",
        "total_token_count",
        "total"
    ]

    static let tokenContainerKeys = [
        "usage",
        "tokenUsage",
        "token_usage",
        "tokens",
        "tokenDetails",
        "token_details",
        "usageMetadata",
        "usage_metadata",
        "messageUsage",
        "message_usage",
        "metrics"
    ]

    static func filteredRecords(
        from value: JSONValue,
        timeRange: UsageTimeRange,
        now: Date,
        calendar: Calendar
    ) -> [NormalizedRecord] {
        normalizedRecords(from: value, now: now).filter { record in
            timeRange.contains(record.event.timestamp, now: now, calendar: calendar)
        }
    }

    static func normalizedRecords(from value: JSONValue, now: Date) -> [NormalizedRecord] {
        let rawRecords = candidateRecordValues(from: value)
        return rawRecords.enumerated().compactMap { index, value in
            normalizedRecord(from: value, index: index, now: now)
        }
    }

    static func candidateRecordValues(from value: JSONValue) -> [JSONValue] {
        let cliProxyRecords = cliProxyUsageRecordValues(from: value)
        if !cliProxyRecords.isEmpty {
            return cliProxyRecords
        }

        var records: [JSONValue] = []
        collectRecordValues(from: value, key: nil, into: &records)

        if records.isEmpty {
            let payload = UsageRawPayload(root: value)
            records = payload.records
        }

        return records.filter { $0.object != nil }
    }

    static func cliProxyUsageRecordValues(from value: JSONValue) -> [JSONValue] {
        guard let usageObject = cliProxyUsageObject(from: value),
              let apiStats = cliProxyAPIStats(from: usageObject) else {
            return []
        }

        var records: [JSONValue] = []
        for (endpointName, endpointValue) in apiStats {
            guard let endpointObject = endpointValue.object else {
                continue
            }

            if let modelStats = cliProxyModelStats(from: endpointObject), !modelStats.isEmpty {
                for (modelName, modelValue) in modelStats {
                    appendCLIProxyModelRecords(
                        endpointName: endpointName,
                        endpointObject: endpointObject,
                        modelName: modelName,
                        modelValue: modelValue,
                        into: &records
                    )
                }
            } else {
                var record = endpointObject
                applyCLIProxyContext(
                    to: &record,
                    endpointName: endpointName,
                    endpointObject: endpointObject,
                    modelName: unknownModel,
                    modelObject: [:]
                )
                records.append(.object(record))
            }
        }

        return records
    }

    static func cliProxyUsageObject(from value: JSONValue) -> [String: JSONValue]? {
        guard let object = value.object else {
            return nil
        }

        if cliProxyAPIStats(from: object) != nil {
            return object
        }

        for envelopeKey in ["usage", "data", "payload", "result"] {
            guard let nested = object.object(for: envelopeKey) else {
                continue
            }

            if cliProxyAPIStats(from: nested) != nil {
                return nested
            }

            if let usage = nested.object(for: "usage"),
               cliProxyAPIStats(from: usage) != nil {
                return usage
            }
        }

        return nil
    }

    static func cliProxyAPIStats(from object: [String: JSONValue]) -> [String: JSONValue]? {
        object.object(
            for: "apis",
            "apiStats",
            "api_stats",
            "apiDetails",
            "api_details",
            "usageByAPI",
            "usage_by_api"
        )
    }

    static func cliProxyModelStats(from object: [String: JSONValue]) -> [String: JSONValue]? {
        object.object(
            for: "models",
            "modelStats",
            "model_stats",
            "modelDetails",
            "model_details",
            "usageByModel",
            "usage_by_model"
        )
    }

    static func appendCLIProxyModelRecords(
        endpointName: String,
        endpointObject: [String: JSONValue],
        modelName: String,
        modelValue: JSONValue,
        into records: inout [JSONValue]
    ) {
        guard let modelObject = modelValue.object else {
            return
        }

        let details = cliProxyDetailValues(from: modelObject)
        if details.isEmpty {
            var record = modelObject
            applyCLIProxyContext(
                to: &record,
                endpointName: endpointName,
                endpointObject: endpointObject,
                modelName: modelName,
                modelObject: modelObject
            )
            records.append(.object(record))
            return
        }

        for detail in details {
            guard var record = detail.object else {
                continue
            }
            applyCLIProxyContext(
                to: &record,
                endpointName: endpointName,
                endpointObject: endpointObject,
                modelName: modelName,
                modelObject: modelObject
            )
            records.append(.object(record))
        }
    }

    static func cliProxyDetailValues(from object: [String: JSONValue]) -> [JSONValue] {
        for key in ["details", "usageDetails", "usage_details", "requests", "records", "logs", "items", "events"] {
            if let details = object.array(for: key) {
                return details
            }
        }
        return []
    }

    static func applyCLIProxyContext(
        to record: inout [String: JSONValue],
        endpointName: String,
        endpointObject: [String: JSONValue],
        modelName: String,
        modelObject: [String: JSONValue]
    ) {
        let endpoint = firstString(in: endpointObject, keys: endpointKeys + ["name", "api", "apiName", "api_name"])
            ?? endpointName.trimmedNonEmpty
            ?? unknownEndpoint
        let model = firstString(in: modelObject, keys: modelKeys + ["name"])
            ?? modelName.trimmedNonEmpty
            ?? unknownModel

        if firstString(in: record, keys: endpointKeys) == nil {
            record["endpoint"] = .string(endpoint)
        }

        if firstString(in: record, keys: modelKeys) == nil {
            record["model"] = .string(model)
        }

        if firstString(in: record, keys: sourceKeys) == nil {
            let source = firstString(in: modelObject, keys: sourceKeys)
                ?? firstString(in: endpointObject, keys: sourceKeys)
                ?? endpoint
            record["source"] = .string(source)
        }

        if firstString(in: record, keys: providerKeys) == nil,
           let provider = firstString(in: modelObject, keys: providerKeys)
            ?? firstString(in: endpointObject, keys: providerKeys) {
            record["provider"] = .string(provider)
        }

        if firstString(in: record, keys: authIndexKeys) == nil,
           let authIndex = firstString(in: modelObject, keys: authIndexKeys)
            ?? firstString(in: endpointObject, keys: authIndexKeys) {
            record["auth_index"] = .string(authIndex)
        }

        if firstString(in: record, keys: credentialKeys) == nil,
           let credential = firstString(in: modelObject, keys: credentialKeys)
            ?? firstString(in: endpointObject, keys: credentialKeys) {
            record["credential"] = .string(credential)
        }

        if firstValue(in: record, keys: successValueKeys) == nil,
           let failed = record.value(for: "failed", "isFailed", "is_failed", "failure")?.bool {
            record["success"] = .bool(!failed)
        }
    }

    static func collectRecordValues(from value: JSONValue, key: String?, into records: inout [JSONValue]) {
        switch value {
        case let .array(array):
            if key == nil || isRecordCollectionKey(key) {
                records.append(contentsOf: array)
            } else {
                for child in array {
                    collectRecordValues(from: child, key: nil, into: &records)
                }
            }
        case let .object(object):
            for (childKey, childValue) in object {
                if childValue.array != nil, isRecordCollectionKey(childKey) {
                    collectRecordValues(from: childValue, key: childKey, into: &records)
                } else if childValue.object != nil || childValue.array != nil {
                    collectRecordValues(from: childValue, key: childKey, into: &records)
                }
            }
        default:
            break
        }
    }

    static func isRecordCollectionKey(_ key: String?) -> Bool {
        guard let key else {
            return false
        }
        return recordCollectionKeys.contains(normalizedLookupKey(key))
    }

    static func normalizedRecord(from value: JSONValue, index: Int, now: Date) -> NormalizedRecord? {
        guard let object = value.object else {
            return nil
        }

        let timestamp = firstDate(in: object, keys: dateKeys) ?? now
        let model = firstString(in: object, keys: modelKeys) ?? unknownModel
        let provider = firstString(in: object, keys: providerKeys) ?? ""
        let rawSource = firstString(in: object, keys: sourceKeys)
        let source = rawSource ?? unknownSource
        let authIndex = firstString(in: object, keys: authIndexKeys) ?? unknownCredential
        let credential = firstString(in: object, keys: credentialKeys) ?? authIndex
        let endpoint = firstString(in: object, keys: endpointKeys) ?? rawSource ?? unknownEndpoint
        let statusCode = firstInt(in: object, keys: statusCodeKeys)
        let errorMessage = firstString(in: object, keys: errorKeys) ?? ""
        let estimatedCost = firstCost(in: object, keys: costKeys)
        let explicitSuccess = successValue(in: object, statusCode: statusCode, errorMessage: errorMessage)
        let tokens = tokenMetrics(in: object)
        let requestedCount = max(firstInt(in: object, keys: requestCountKeys) ?? 0, 0)
        let successfulCount = max(firstInt(in: object, keys: successfulCountKeys) ?? 0, 0)
        let failedCount = max(firstInt(in: object, keys: failedCountKeys) ?? 0, 0)
        let requestCount = normalizedRequestCount(
            explicitCount: requestedCount,
            successfulCount: successfulCount,
            failedCount: failedCount
        )
        let counts = normalizedResultCounts(
            requestCount: requestCount,
            successfulCount: successfulCount,
            failedCount: failedCount,
            explicitSuccess: explicitSuccess
        )
        let latency = latencyMetrics(in: object, requestCount: requestCount)
        let eventID = firstString(in: object, keys: ["id", "requestId", "request_id", "uuid", "traceId", "trace_id"]) ??
            stableID(index: index, timestamp: timestamp, endpoint: endpoint, model: model)

        let event = RequestEvent(
            id: eventID,
            timestamp: timestamp,
            endpoint: endpoint,
            model: model,
            source: source,
            provider: provider,
            authIndex: authIndex,
            isSuccess: counts.failed == 0,
            statusCode: statusCode,
            errorMessage: errorMessage,
            latencyMs: latency.average,
            inputTokens: tokens.input,
            outputTokens: tokens.output,
            reasoningTokens: tokens.reasoning,
            cachedTokens: tokens.cached,
            totalTokens: tokens.total,
            estimatedCost: estimatedCost,
            metadata: object
        )

        return NormalizedRecord(
            event: event,
            credential: credential,
            requestCount: requestCount,
            successfulRequests: counts.successful,
            failedRequests: counts.failed,
            totalLatencyMs: latency.total,
            inputTokens: tokens.input,
            outputTokens: tokens.output,
            cachedTokens: tokens.cached,
            reasoningTokens: tokens.reasoning,
            totalTokens: tokens.total,
            estimatedCost: estimatedCost
        )
    }

    static func normalizedRequestCount(
        explicitCount: Int,
        successfulCount: Int,
        failedCount: Int
    ) -> Int {
        if explicitCount > 0 {
            return explicitCount
        }

        let countedRequests = successfulCount + failedCount
        return max(countedRequests, 1)
    }

    static func normalizedResultCounts(
        requestCount: Int,
        successfulCount: Int,
        failedCount: Int,
        explicitSuccess: Bool?
    ) -> (successful: Int, failed: Int) {
        if successfulCount > 0 || failedCount > 0 {
            let successful = successfulCount > 0 ? successfulCount : max(requestCount - failedCount, 0)
            let failed = failedCount > 0 ? failedCount : max(requestCount - successful, 0)
            return (successful, failed)
        }

        if explicitSuccess ?? true {
            return (requestCount, 0)
        }

        return (0, requestCount)
    }

    static func successValue(
        in object: [String: JSONValue],
        statusCode: Int?,
        errorMessage: String
    ) -> Bool? {
        if let value = object.value(anyOf: successValueKeys)?.bool {
            return value
        }

        if let statusCode {
            return (200..<400).contains(statusCode)
        }

        if let result = firstString(in: object, keys: resultKeys) {
            let normalized = normalizedLookupKey(result)
            if ["success", "successful", "succeeded", "ok", "completed", "complete", "pass", "passed"].contains(normalized) {
                return true
            }
            if ["failure", "failed", "error", "errored", "timeout", "cancelled", "canceled", "rejected"].contains(normalized) {
                return false
            }
            if let code = Int(result.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return (200..<400).contains(code)
            }
        }

        if !errorMessage.isEmpty {
            return false
        }

        return nil
    }

    static func tokenMetrics(in object: [String: JSONValue], allowNested: Bool = true) -> TokenMetrics {
        var metrics = TokenMetrics()
        metrics.input = max(firstInt(in: object, keys: inputTokenKeys) ?? 0, 0)
        metrics.output = max(firstInt(in: object, keys: outputTokenKeys) ?? 0, 0)
        metrics.reasoning = max(firstInt(in: object, keys: reasoningTokenKeys) ?? 0, 0)
        metrics.cached = max(firstInt(in: object, keys: cachedTokenKeys) ?? 0, 0)
        let explicitTotal = max(firstInt(in: object, keys: totalTokenKeys) ?? 0, 0)

        if allowNested {
            for key in tokenContainerKeys {
                guard let nested = object.value(for: key)?.object else {
                    continue
                }
                let nestedMetrics = tokenMetrics(in: nested, allowNested: false)
                metrics.input = metrics.input.nonZero(or: nestedMetrics.input)
                metrics.output = metrics.output.nonZero(or: nestedMetrics.output)
                metrics.reasoning = metrics.reasoning.nonZero(or: nestedMetrics.reasoning)
                metrics.cached = metrics.cached.nonZero(or: nestedMetrics.cached)
                metrics.total = metrics.total.nonZero(or: nestedMetrics.total)
            }
        }

        metrics.total = explicitTotal.nonZero(or: metrics.total)
        if metrics.total == 0 {
            metrics.total = metrics.input + metrics.output + metrics.reasoning + metrics.cached
        }

        return metrics
    }

    static func latencyMetrics(
        in object: [String: JSONValue],
        requestCount: Int
    ) -> (average: Double, total: Double) {
        let explicitTotal = firstLatency(in: object, keys: latencyTotalKeys)
        var average = firstLatency(in: object, keys: latencyAverageKeys) ?? 0

        if average == 0, let explicitTotal, requestCount > 0 {
            average = explicitTotal / Double(requestCount)
        }

        let total = explicitTotal ?? average * Double(requestCount)
        return (max(average, 0), max(total, 0))
    }

    static func firstLatency(
        in object: [String: JSONValue],
        keys: [String]
    ) -> Double? {
        guard let (matchedKey, value) = firstValue(in: object, keys: keys),
              let number = value.double else {
            return nil
        }

        let normalizedKey = normalizedLookupKey(matchedKey)
        if normalizedKey.contains("second") || (normalizedKey.hasSuffix("s") && !normalizedKey.hasSuffix("ms")) {
            return number * 1_000
        }

        return number
    }

    static func price(
        _ records: [NormalizedRecord],
        with prices: [ModelPriceSetting],
        basis: CostCalculationBasis
    ) -> [PricedRecord] {
        var priceLookup: [String: ModelPriceSetting] = [:]
        for price in prices where !price.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && price.hasConfiguredPrice {
            priceLookup[normalizedModelKey(price.model)] = price
        }

        return records.map { record in
            let setting = priceLookup[normalizedModelKey(record.event.model)]
            let savedPriceCost = setting?.estimatedCost(
                inputTokens: record.inputTokens,
                outputTokens: record.outputTokens,
                cachedTokens: record.cachedTokens
            )
            let cost: Double?
            switch basis {
            case .saved:
                cost = savedPriceCost
            case .estimate:
                cost = record.estimatedCost ?? savedPriceCost
            }
            return PricedRecord(record: record, cost: cost)
        }
    }

    static func summary(
        from records: [PricedRecord],
        timeRange: UsageTimeRange,
        now: Date,
        calendar: Calendar
    ) -> UsageSummary {
        var accumulator = UsageAccumulator()
        for record in records {
            accumulator.add(record)
        }

        let minutes = durationMinutes(
            records: records.map(\.record),
            timeRange: timeRange,
            now: now,
            calendar: calendar
        )

        return UsageSummary(
            totalRequests: accumulator.requests,
            successfulRequests: accumulator.successfulRequests,
            failedRequests: accumulator.failedRequests,
            averageLatencyMs: accumulator.averageLatencyMs,
            totalLatencyMs: accumulator.totalLatencyMs,
            totalTokens: accumulator.totalTokens,
            inputTokens: accumulator.inputTokens,
            outputTokens: accumulator.outputTokens,
            cachedTokens: accumulator.cachedTokens,
            reasoningTokens: accumulator.reasoningTokens,
            rpm: minutes > 0 ? Double(accumulator.requests) / minutes : 0,
            tpm: minutes > 0 ? Double(accumulator.totalTokens) / minutes : 0,
            totalCost: accumulator.cost
        )
    }

    static func endpointStats(from records: [PricedRecord]) -> [EndpointUsageStat] {
        var endpointAccumulators: [String: UsageAccumulator] = [:]
        var modelAccumulators: [EndpointModelKey: UsageAccumulator] = [:]

        for record in records {
            let event = record.record.event
            endpointAccumulators[event.endpoint, default: UsageAccumulator()].add(record)
            modelAccumulators[EndpointModelKey(endpoint: event.endpoint, model: event.model), default: UsageAccumulator()].add(record)
        }

        let modelStats = modelAccumulators.map { key, accumulator in
            EndpointModelStat(
                endpoint: key.endpoint,
                model: key.model,
                requests: accumulator.requests,
                successfulRequests: accumulator.successfulRequests,
                failedRequests: accumulator.failedRequests,
                totalTokens: accumulator.totalTokens,
                averageLatencyMs: accumulator.averageLatencyMs,
                totalLatencyMs: accumulator.totalLatencyMs,
                cost: accumulator.cost
            )
        }

        let modelsByEndpoint = Dictionary(grouping: modelStats, by: \.endpoint)

        return endpointAccumulators.map { endpoint, accumulator in
            EndpointUsageStat(
                endpoint: endpoint,
                requests: accumulator.requests,
                successfulRequests: accumulator.successfulRequests,
                failedRequests: accumulator.failedRequests,
                totalTokens: accumulator.totalTokens,
                averageLatencyMs: accumulator.averageLatencyMs,
                totalLatencyMs: accumulator.totalLatencyMs,
                cost: accumulator.cost,
                models: (modelsByEndpoint[endpoint] ?? []).sorted {
                    if $0.requests == $1.requests {
                        return $0.model < $1.model
                    }
                    return $0.requests > $1.requests
                }
            )
        }
        .sorted {
            if $0.requests == $1.requests {
                return $0.endpoint < $1.endpoint
            }
            return $0.requests > $1.requests
        }
    }

    static func modelStats(from records: [PricedRecord]) -> [ModelUsageStat] {
        var accumulators: [String: UsageAccumulator] = [:]

        for record in records {
            accumulators[record.record.event.model, default: UsageAccumulator()].add(record)
        }

        return accumulators.map { model, accumulator in
            ModelUsageStat(
                model: model,
                requests: accumulator.requests,
                successfulRequests: accumulator.successfulRequests,
                failedRequests: accumulator.failedRequests,
                totalTokens: accumulator.totalTokens,
                averageLatencyMs: accumulator.averageLatencyMs,
                totalLatencyMs: accumulator.totalLatencyMs,
                successRate: accumulator.successRate,
                cost: accumulator.cost
            )
        }
        .sorted {
            if $0.requests == $1.requests {
                return $0.model < $1.model
            }
            return $0.requests > $1.requests
        }
    }

    static func credentialStats(from records: [PricedRecord]) -> [CredentialUsageStat] {
        var accumulators: [CredentialKey: UsageAccumulator] = [:]

        for record in records {
            let event = record.record.event
            let key = CredentialKey(
                credential: record.record.credential,
                source: event.source,
                provider: event.provider
            )
            accumulators[key, default: UsageAccumulator()].add(record)
        }

        return accumulators.map { key, accumulator in
            CredentialUsageStat(
                credential: key.credential,
                source: key.source,
                provider: key.provider,
                requests: accumulator.requests,
                successfulRequests: accumulator.successfulRequests,
                failedRequests: accumulator.failedRequests,
                successRate: accumulator.successRate,
                lastUsedAt: accumulator.lastUsedAt
            )
        }
        .sorted {
            if $0.requests == $1.requests {
                return $0.displayName < $1.displayName
            }
            return $0.requests > $1.requests
        }
    }

    static func trends(
        from records: [PricedRecord],
        granularity: TrendGranularity,
        calendar: Calendar
    ) -> [UsageTrendPoint] {
        var accumulators: [TrendKey: UsageAccumulator] = [:]

        for record in records {
            let event = record.record.event
            let key = TrendKey(
                bucket: bucketStart(for: event.timestamp, granularity: granularity, calendar: calendar),
                model: event.model
            )
            accumulators[key, default: UsageAccumulator()].add(record)
        }

        return accumulators.map { key, accumulator in
            UsageTrendPoint(
                bucket: key.bucket,
                model: key.model,
                requests: accumulator.requests,
                successfulRequests: accumulator.successfulRequests,
                failedRequests: accumulator.failedRequests,
                tokens: accumulator.totalTokens,
                inputTokens: accumulator.inputTokens,
                outputTokens: accumulator.outputTokens,
                cachedTokens: accumulator.cachedTokens,
                reasoningTokens: accumulator.reasoningTokens,
                averageLatencyMs: accumulator.averageLatencyMs,
                cost: accumulator.cost
            )
        }
        .sorted {
            if $0.bucket == $1.bucket {
                return $0.model < $1.model
            }
            return $0.bucket < $1.bucket
        }
    }

    static func eventRows(from records: [NormalizedRecord]) -> [RequestEvent] {
        records.map(\.event).sorted {
            if $0.timestamp == $1.timestamp {
                return $0.id < $1.id
            }
            return $0.timestamp > $1.timestamp
        }
    }

    static func durationMinutes(
        records: [NormalizedRecord],
        timeRange: UsageTimeRange,
        now: Date,
        calendar: Calendar
    ) -> Double {
        if let hourWindow = timeRange.hourWindow {
            return max(Double(hourWindow) * 60, 1)
        }

        guard let earliest = records.map(\.event.timestamp).min(),
              let latest = records.map(\.event.timestamp).max() else {
            return 1
        }

        let boundedLatest = min(max(latest, earliest), now)
        let seconds = max(boundedLatest.timeIntervalSince(earliest), 60)
        _ = calendar
        return seconds / 60
    }

    static func inferredGranularity(
        for timeRange: UsageTimeRange,
        records: [NormalizedRecord]
    ) -> TrendGranularity {
        switch timeRange {
        case .last7Hours, .last24Hours:
            return .hour
        case .last7Days:
            return .day
        case .all:
            guard let earliest = records.map(\.event.timestamp).min(),
                  let latest = records.map(\.event.timestamp).max() else {
                return .hour
            }
            return latest.timeIntervalSince(earliest) > 48 * 60 * 60 ? .day : .hour
        }
    }

    static func bucketStart(
        for date: Date,
        granularity: TrendGranularity,
        calendar: Calendar
    ) -> Date {
        switch granularity {
        case .hour:
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            return calendar.date(from: components) ?? date
        case .day:
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            return calendar.date(from: components) ?? date
        }
    }

    static func generatedAt(from value: JSONValue) -> Date? {
        guard let object = value.object else {
            return nil
        }
        return firstDate(in: object, keys: generatedAtKeys)
    }

    static func sourceDescription(from value: JSONValue) -> String {
        guard let object = value.object else {
            return "本地用量服务"
        }

        return firstString(
            in: object,
            keys: ["sourceDescription", "source_description", "description", "service", "serviceName", "service_name", "name"]
        ) ?? "本地用量服务"
    }

    static func firstDate(in object: [String: JSONValue], keys: [String]) -> Date? {
        for key in keys {
            guard let value = object.value(for: key),
                  let date = UsageDateParser.parse(value) else {
                continue
            }
            return date
        }
        return nil
    }

    static func firstString(in object: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            guard let string = object.value(for: key)?.string?.trimmedNonEmpty else {
                continue
            }
            return string
        }
        return nil
    }

    static func firstInt(in object: [String: JSONValue], keys: [String]) -> Int? {
        for key in keys {
            guard let int = object.value(for: key)?.int else {
                continue
            }
            return int
        }
        return nil
    }

    static func firstCost(in object: [String: JSONValue], keys: [String]) -> Double? {
        guard let (_, value) = firstValue(in: object, keys: keys),
              let cost = value.double,
              cost.isFinite,
              cost >= 0 else {
            return nil
        }
        return cost
    }

    static func firstValue(
        in object: [String: JSONValue],
        keys: [String]
    ) -> (key: String, value: JSONValue)? {
        for key in keys {
            if let exact = object[key] {
                return (key, exact)
            }

            if let matched = object.first(where: { $0.key.lowercased() == key.lowercased() }) {
                return (matched.key, matched.value)
            }

            let normalizedKey = normalizedLookupKey(key)
            if let matched = object.first(where: { normalizedLookupKey($0.key) == normalizedKey }) {
                return (matched.key, matched.value)
            }
        }

        return nil
    }

    static func stableID(index: Int, timestamp: Date, endpoint: String, model: String) -> String {
        [
            String(Int(timestamp.timeIntervalSince1970 * 1_000)),
            endpoint,
            model,
            String(index)
        ]
        .joined(separator: "-")
    }

    static func normalizedLookupKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func normalizedModelKey(_ model: String) -> String {
        normalizedLookupKey(model.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private nonisolated extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased() == "null" {
            return nil
        }
        return trimmed
    }
}

private nonisolated extension Int {
    func nonZero(or fallback: Int) -> Int {
        self == 0 ? fallback : self
    }
}
