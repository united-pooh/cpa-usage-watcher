import Foundation

enum UsageAggregatorTests {
    static func run() throws {
        try verifiesTimeRangeAggregationAndCosts()
        try verifiesEstimatedCostBasisUsesRecordedCosts()
        try verifiesCLIProxyUsagePayloadPreservesGroupedContext()
        verifiesLatencyFormattingUsesMilliseconds()
        try verifiesSnapshotFromPersistedEvents()
        try verifiesPreparedDashboardSnapshotUsesOneEventSet()
        try verifiesHealthBucketsCoverSevenDays()
        try verifiesQuotaParsingSkipsAPICredentials()
        verifiesSensitiveIdentifierMasking()
    }

    private static func verifiesTimeRangeAggregationAndCosts() throws {
        let payload = try decodePayload(
            """
            {
              "sourceDescription": "fixture",
              "usageDetails": [
                {
                  "id": "success-1",
                  "timestamp": "2026-04-27T10:00:00Z",
                  "endpoint": "sk-test",
                  "model": "claude-haiku",
                  "source": "credential.json",
                  "provider": "claude",
                  "auth_index": "abc",
                  "success": true,
                  "latency_ms": 4000,
                  "input_tokens": 1000,
                  "output_tokens": 2000,
                  "cache_tokens": 500,
                  "reasoning_tokens": 50
                },
                {
                  "id": "failed-1",
                  "timestamp": "2026-04-27T11:00:00Z",
                  "endpoint": "sk-test",
                  "model": "claude-haiku",
                  "source": "credential.json",
                  "provider": "claude",
                  "auth_index": "abc",
                  "result": "failed",
                  "latency_ms": 1000
                },
                {
                  "id": "old-1",
                  "timestamp": "2026-04-25T10:00:00Z",
                  "endpoint": "sk-old",
                  "model": "old-model",
                  "success": true,
                  "input_tokens": 999
                }
              ]
            }
            """
        )

        let now = try requireDate("2026-04-27T12:00:00Z")
        let price = ModelPriceSetting(
            model: "claude-haiku",
            promptPricePerMillion: 1,
            completionPricePerMillion: 2,
            cachePricePerMillion: 0.5
        )
        let snapshot = UsageAggregator.snapshot(
            from: payload,
            timeRange: .last24Hours,
            prices: [price],
            now: now,
            calendar: Calendar(identifier: .gregorian),
            trendGranularity: .hour
        )

        TestExpect.equal(snapshot.summary.totalRequests, 2, "24h window should exclude old records")
        TestExpect.equal(snapshot.summary.successfulRequests, 1, "success count")
        TestExpect.equal(snapshot.summary.failedRequests, 1, "failure count")
        TestExpect.equal(snapshot.summary.totalTokens, 3550, "token total includes input/output/cache/reasoning")
        TestExpect.equal(snapshot.endpoints.count, 1, "endpoint grouping")
        TestExpect.equal(snapshot.models.first?.requests, 2, "model grouping")
        TestExpect.equal(snapshot.credentials.first?.requests, 2, "credential grouping")
        TestExpect.equal(snapshot.events.count, 2, "event rows")
        TestExpect.equal(snapshot.trends.count, 2, "hourly trend buckets")
        TestExpect.approx(snapshot.summary.averageLatencyMs, 2500, "average latency")
        TestExpect.approx(snapshot.summary.totalCost ?? -1, 0.00525, "model price cost")
    }

    private static func verifiesEstimatedCostBasisUsesRecordedCosts() throws {
        let payload = try decodePayload(
            """
            {
              "usageDetails": [
                {
                  "timestamp": "2026-04-27T10:00:00Z",
                  "endpoint": "sk-test",
                  "model": "priced-model",
                  "success": true,
                  "input_tokens": 1000,
                  "output_tokens": 1000,
                  "estimated_cost": 0.25
                }
              ]
            }
            """
        )

        let now = try requireDate("2026-04-27T12:00:00Z")
        let savedPrice = ModelPriceSetting(
            model: "priced-model",
            promptPricePerMillion: 1,
            completionPricePerMillion: 1,
            cachePricePerMillion: 0
        )

        let savedSnapshot = UsageAggregator.snapshot(
            from: payload,
            timeRange: .last24Hours,
            prices: [savedPrice],
            now: now,
            calendar: Calendar(identifier: .gregorian)
        )
        let estimateSnapshot = UsageAggregator.snapshot(
            from: payload,
            timeRange: .last24Hours,
            prices: [savedPrice],
            now: now,
            calendar: Calendar(identifier: .gregorian),
            costCalculationBasis: .estimate
        )

        TestExpect.approx(savedSnapshot.summary.totalCost ?? -1, 0.002, "saved price basis should use model price")
        TestExpect.approx(estimateSnapshot.summary.totalCost ?? -1, 0.25, "estimate basis should use recorded cost")
    }

    private static func verifiesCLIProxyUsagePayloadPreservesGroupedContext() throws {
        let payload = try decodePayload(
            """
            {
              "usage": {
                "apis": {
                  "openai-main": {
                    "provider": "openai",
                    "models": {
                      "gpt-5.5": {
                        "details": [
                          {
                            "id": "req-1",
                            "timestamp": "2026-04-27T10:00:00Z",
                            "auth_index": "sk-live",
                            "failed": false,
                            "latency_ms": 500,
                            "tokens": {
                              "input": 10,
                              "output": 20,
                              "cached": 5,
                              "reasoning": 1,
                              "total": 36
                            }
                          },
                          {
                            "id": "req-2",
                            "timestamp": "2026-04-27T11:00:00Z",
                            "auth_index": "sk-live",
                            "failed": true,
                            "latency_ms": 800,
                            "tokens": {
                              "input": 4,
                              "output": 6,
                              "cached": 2,
                              "reasoning": 1,
                              "total": 13
                            }
                          }
                        ]
                      },
                      "gpt-5.4": {
                        "total_requests": 3,
                        "successful_requests": 3,
                        "total_tokens": 90,
                        "input_tokens": 30,
                        "output_tokens": 60
                      }
                    }
                  }
                }
              }
            }
            """
        )

        let now = try requireDate("2026-04-27T12:00:00Z")
        let snapshot = UsageAggregator.snapshot(
            from: payload,
            timeRange: .last24Hours,
            now: now,
            calendar: Calendar(identifier: .gregorian)
        )

        TestExpect.equal(snapshot.summary.totalRequests, 5, "CLIProxyAPI grouped requests should flatten into records")
        TestExpect.equal(snapshot.summary.successfulRequests, 4, "failed boolean should invert into success state")
        TestExpect.equal(snapshot.summary.failedRequests, 1, "failed boolean should count as failure")
        TestExpect.equal(snapshot.summary.totalTokens, 139, "CLIProxyAPI token totals")
        TestExpect.equal(snapshot.endpoints.first?.endpoint, "openai-main", "endpoint should come from api group name")
        TestExpect.equal(snapshot.endpoints.first?.models.count, 2, "endpoint should retain grouped models")
        TestExpect.equal(snapshot.models.map(\.model).contains("gpt-5.5"), true, "details should inherit model group name")
        TestExpect.equal(snapshot.models.map(\.model).contains("gpt-5.4"), true, "aggregate model rows should be converted")

        let failedEvent = snapshot.events.first { $0.id == "req-2" }
        TestExpect.equal(failedEvent?.endpoint, "openai-main", "detail rows should inherit endpoint")
        TestExpect.equal(failedEvent?.model, "gpt-5.5", "detail rows should inherit model")
        TestExpect.equal(failedEvent?.isSuccess, false, "failed detail rows should be unsuccessful")
        TestExpect.equal(failedEvent?.authIndex, "sk-live", "auth index should survive flattening")
    }


    private static func verifiesSnapshotFromPersistedEvents() throws {
        let now = try requireDate("2026-04-27T12:00:00Z")
        let events = [
            RequestEvent(id: "persisted-1", timestamp: try requireDate("2026-04-27T11:00:00Z"), endpoint: "messages", model: "claude", source: "account", provider: "claude", authIndex: "acct", isSuccess: true, latencyMs: 100, inputTokens: 2, outputTokens: 3, totalTokens: 5),
            RequestEvent(id: "persisted-2", timestamp: try requireDate("2026-04-26T10:00:00Z"), endpoint: "old", model: "old", isSuccess: true, totalTokens: 99)
        ]

        let snapshot = UsageAggregator.snapshot(
            from: events,
            timeRange: .last24Hours,
            prices: [ModelPriceSetting(model: "claude", promptPricePerMillion: 1, completionPricePerMillion: 2)],
            now: now,
            calendar: Calendar(identifier: .gregorian),
            costCalculationBasis: .saved
        )
        TestExpect.equal(snapshot.summary.totalRequests, 1, "persisted snapshot should respect time range")
        TestExpect.equal(snapshot.events.first?.id, "persisted-1", "persisted event should be retained")
        TestExpect.equal(snapshot.sourceDescription, "本地历史记录", "persisted snapshot should describe local source")
        TestExpect.approx(snapshot.summary.totalCost ?? -1, 0.000008, "persisted snapshot should apply configured prices")
    }

    private static func verifiesPreparedDashboardSnapshotUsesOneEventSet() throws {
        let payload = try decodePayload(
            """
            {
              "usageDetails": [
                {
                  "id": "prepared-1",
                  "timestamp": "2026-04-27T10:00:00Z",
                  "endpoint": "/v1/messages",
                  "model": "claude-sonnet",
                  "source": "console-account",
                  "provider": "anthropic",
                  "auth_index": "account@example.com",
                  "success": true,
                  "input_tokens": 100,
                  "output_tokens": 50,
                  "total_tokens": 150,
                  "estimated_cost": 0.12,
                  "quota": {"limit": 100, "used": 25, "window": "5小时"},
                  "plan": "Max"
                },
                {
                  "id": "prepared-old",
                  "timestamp": "2026-04-25T10:00:00Z",
                  "endpoint": "/v1/old",
                  "model": "old-model",
                  "success": true
                }
              ]
            }
            """
        )
        let now = try requireDate("2026-04-27T12:00:00Z")
        let prepared = UsageAggregator.preparedDashboardSnapshot(
            from: payload,
            timeRange: .last24Hours,
            now: now,
            calendar: Calendar(identifier: .gregorian),
            trendGranularity: .hour,
            costCalculationBasis: .estimate
        )

        TestExpect.equal(prepared.events.map(\.id), ["prepared-1"], "prepared events should respect the selected time range")
        TestExpect.equal(prepared.snapshot.events.map(\.id), ["prepared-1"], "prepared snapshot should use the same event ids")
        TestExpect.equal(prepared.snapshot.events.allSatisfy { $0.metadata.isEmpty }, true, "prepared UI snapshot should mirror the hot SQLite metadata-free path")
        TestExpect.equal(prepared.events.first?.metadata.isEmpty, false, "prepared persistence events should retain metadata for the cold table")
        TestExpect.equal(prepared.quotaSnapshots.count, 1, "prepared helper should carry quota snapshots for persistence and UI")
        TestExpect.equal(prepared.snapshot.credentialQuotas, prepared.quotaSnapshots, "prepared snapshot should use the same quota snapshots as persistence")
        TestExpect.approx(prepared.snapshot.summary.totalCost ?? -1, 0.12, "prepared snapshot should honor estimate cost basis")
    }

    private static func verifiesHealthBucketsCoverSevenDays() throws {
        let now = try requireDate("2026-04-27T12:00:00Z")
        let buckets = UsageAggregator.healthBuckets(from: [
            RequestEvent(id: "health-1", timestamp: try requireDate("2026-04-27T11:55:00Z"), isSuccess: false, latencyMs: 12_000)
        ], now: now, calendar: Calendar(identifier: .gregorian))

        TestExpect.equal(buckets.count, 1008, "7 days of 10-minute buckets should produce 1008 cells")
        let bucket = buckets.first { $0.requests == 1 }
        TestExpect.equal(bucket?.status, .failed, "failed slow event should mark bucket failed")
        TestExpect.equal(bucket?.averageLatencyMs, 12_000, "health bucket should preserve latency")
    }

    private static func verifiesQuotaParsingSkipsAPICredentials() throws {
        let payload = try decodePayload(
            """
            {
              "usageDetails": [
                {
                  "id": "quota-1",
                  "timestamp": "2026-04-27T10:00:00Z",
                  "source": "console-account",
                  "provider": "anthropic",
                  "auth_index": "account@example.com",
                  "success": true,
                  "quota": {"limit": 100, "used": 25, "window": "5小时", "reset_at": "2026-04-27T15:00:00Z"},
                  "plan": "Max"
                },
                {
                  "id": "quota-2",
                  "timestamp": "2026-04-27T10:00:00Z",
                  "source": "api endpoint",
                  "provider": "openai",
                  "auth_index": "sk-live",
                  "success": true,
                  "quota": {"limit": 100, "used": 25}
                }
              ]
            }
            """
        )

        let snapshots = UsageAggregator.credentialQuotaSnapshots(from: payload, capturedAt: try requireDate("2026-04-27T12:00:00Z"))
        let snapshot = UsageAggregator.snapshot(from: payload, timeRange: .all, now: try requireDate("2026-04-27T12:00:00Z"))
        TestExpect.equal(snapshots.count, 1, "quota parser should include non-API credentials only")
        TestExpect.equal(snapshots.first?.provider, "anthropic", "provider should be preserved")
        TestExpect.approx(snapshots.first?.shortWindow?.usagePercent ?? -1, 0.25, "usage percent should derive from used/limit")
        TestExpect.equal(snapshot.credentialQuotas.count, 1, "snapshots should expose shared quota source for UI")
    }

    private static func verifiesLatencyFormattingUsesMilliseconds() {
        TestExpect.equal(UsageFormatters.latency(4000), "4.00秒", "latency_ms should format as seconds")
        TestExpect.equal(UsageFormatters.latencyCompact(4000), "4.00s", "compact latency")
    }

    private static func verifiesSensitiveIdentifierMasking() {
        TestExpect.equal(
            UsageFormatters.sensitiveIdentifier("Atri.114514", masked: false),
            "Atri.114514",
            "unmasked identifiers should keep the original value"
        )
        TestExpect.equal(
            UsageFormatters.sensitiveIdentifier("Atri.114514", masked: true),
            "Atri•••4514",
            "long identifiers should keep only stable outer context"
        )
        TestExpect.equal(
            UsageFormatters.sensitiveIdentifier("alex@example.com", masked: true),
            "al•••@e•••.com",
            "email identifiers should preserve recognizable shape"
        )
        TestExpect.equal(
            UsageFormatters.sensitiveIdentifier("", masked: true),
            "--",
            "empty sensitive identifiers should use a placeholder"
        )
    }

    private static func decodePayload(_ json: String) throws -> UsageRawPayload {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(UsageRawPayload.self, from: data)
    }

    private static func requireDate(_ value: String) throws -> Date {
        guard let date = UsageDateParser.parse(value) else {
            throw TestFailure("Unable to parse test date \(value)")
        }
        return date
    }
}
