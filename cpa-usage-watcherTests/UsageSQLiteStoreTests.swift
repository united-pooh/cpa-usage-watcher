import Foundation
import SQLite3

enum UsageSQLiteStoreTests {
    static func run() throws {
        try createsVersionTwoSchema()
        try createsSchemaAndReloadsEvents()
        try upsertPreventsDuplicateEventIDs()
        try queryRespectsDateRange()
        try metadataCanStayOffTheHotPath()
        try migratesVersionOneMetadataIntoColdTable()
        try dashboardSnapshotMatchesInMemoryAggregation()
        try dashboardQueryPlanAvoidsMetadataTable()
        try dashboardSnapshotMeetsPerformanceBudget()
        try rawFetchSavesPlaintextJSON()
        try rawFetchesRespectRetentionLimit()
        try sqlitePragmasAreConfigured()
        try quotaSnapshotsRoundTrip()
    }

    private static func createsVersionTwoSchema() throws {
        let store = try makeStore()
        let columns = try store.tableColumns("usage_events")

        TestExpect.equal(try store.pragmaInt("user_version"), 2, "new stores should use schema v2")
        TestExpect.equal(columns.contains("metadata_json"), false, "hot event table should not keep metadata JSON")
        TestExpect.equal(columns.contains("estimated_cost"), true, "hot event table should keep estimated cost")
        TestExpect.equal(try store.tableExists("usage_event_metadata"), true, "cold metadata table should exist")
        TestExpect.equal(
            try store.indexes("credential_quota_snapshots").contains("idx_credential_quota_snapshots_captured_at"),
            true,
            "quota snapshots should have captured_at sort index"
        )
    }

    private static func createsSchemaAndReloadsEvents() throws {
        let store = try makeStore()
        let event = RequestEvent(
            id: "event-1",
            timestamp: try requireDate("2026-04-27T10:00:00Z"),
            endpoint: "/v1/messages",
            model: "claude-sonnet",
            source: "account.json",
            provider: "claude",
            authIndex: "account-a",
            isSuccess: true,
            latencyMs: 1200,
            inputTokens: 10,
            outputTokens: 20,
            totalTokens: 30,
            estimatedCost: 0.42,
            metadata: ["plan": .string("Pro")]
        )
        try store.upsert(events: [event])

        let events = try store.events(in: .all)
        TestExpect.equal(events.count, 1, "SQLite store should reload inserted event")
        TestExpect.equal(events.first?.id, "event-1", "event id should round-trip")
        TestExpect.approx(events.first?.estimatedCost ?? -1, 0.42, "estimated cost should round-trip")
        TestExpect.equal(events.first?.metadata["plan"]?.string, "Pro", "metadata JSON should round-trip")
    }

    private static func upsertPreventsDuplicateEventIDs() throws {
        let store = try makeStore()
        let first = RequestEvent(id: "same", timestamp: try requireDate("2026-04-27T10:00:00Z"), model: "old", isSuccess: true)
        let second = RequestEvent(id: "same", timestamp: try requireDate("2026-04-27T10:05:00Z"), model: "new", isSuccess: false)
        try store.upsert(events: [first, second])

        let events = try store.events(in: .all)
        TestExpect.equal(events.count, 1, "upsert should keep one row per event id")
        TestExpect.equal(events.first?.model, "new", "upsert should update existing row")
    }

    private static func queryRespectsDateRange() throws {
        let store = try makeStore()
        try store.upsert(events: [
            RequestEvent(id: "recent", timestamp: try requireDate("2026-04-27T11:00:00Z"), isSuccess: true),
            RequestEvent(id: "old", timestamp: try requireDate("2026-04-20T11:00:00Z"), isSuccess: true)
        ])

        let events = try store.events(in: .last24Hours, now: try requireDate("2026-04-27T12:00:00Z"), calendar: Calendar(identifier: .gregorian))
        TestExpect.equal(events.map(\.id), ["recent"], "time range query should exclude old records")
    }

    private static func metadataCanStayOffTheHotPath() throws {
        let store = try makeStore()
        let event = RequestEvent(
            id: "metadata-1",
            timestamp: try requireDate("2026-04-27T10:00:00Z"),
            endpoint: "/v1/messages",
            model: "claude-sonnet",
            source: "account.json",
            authIndex: "account-a",
            isSuccess: true,
            latencyMs: 1200,
            totalTokens: 30,
            metadata: [
                "model": .string("claude-sonnet"),
                "timestamp": .string("2026-04-27T10:00:00Z"),
                "tokens": .object(["total": .number(30)]),
                "plan": .string("Pro"),
                "extras": .object([
                    "region": .string("iad"),
                    "workspace": .string("usage-dashboard")
                ]),
                "tags": .array([.string("dashboard"), .string("round-trip")])
            ]
        )
        try store.upsert(events: [event])

        let hotEvents = try store.events(in: .all, includeMetadata: false)
        TestExpect.equal(hotEvents.first?.metadata.isEmpty, true, "hot path should not decode metadata")

        let coldEvents = try store.events(in: .all, includeMetadata: true)
        TestExpect.equal(coldEvents.first?.metadata["plan"]?.string, "Pro", "cold path should restore metadata extras")
        TestExpect.equal(coldEvents.first?.metadata["extras"]?.object?["region"]?.string, "iad", "cold path should restore nested extras")
        TestExpect.equal(coldEvents.first?.metadata["tags"]?.array?.last?.string, "round-trip", "cold path should restore metadata arrays")
        TestExpect.equal(coldEvents.first?.metadata["model"]?.string, nil, "duplicated hot metadata should be stripped")

        let metadata = try store.eventMetadata(id: "metadata-1")
        TestExpect.equal(metadata["plan"]?.string, "Pro", "eventMetadata should read cold metadata extras")
        TestExpect.equal(metadata["extras"]?.object?["workspace"]?.string, "usage-dashboard", "eventMetadata should read nested extras")
    }

    private static func migratesVersionOneMetadataIntoColdTable() throws {
        let url = try makeLegacyVersionOneDatabase()
        let store = try UsageSQLiteStore(databaseURL: url)

        TestExpect.equal(try store.pragmaInt("user_version"), 2, "legacy store should migrate to schema v2")
        TestExpect.equal(try legacyBackupExists(for: url), true, "migration should create a v1 backup")
        TestExpect.equal(try store.tableColumns("usage_events").contains("metadata_json"), false, "migrated hot table should drop metadata_json")

        let events = try store.events(in: .all)
        TestExpect.equal(events.map(\.id), ["legacy-1"], "migrated event should remain readable")
        TestExpect.equal(events.first?.metadata["plan"]?.string, "Legacy", "metadata extras should survive migration")
        TestExpect.equal(events.first?.metadata["extras"]?.object?["region"]?.string, "iad", "nested metadata extras should survive migration")
        TestExpect.equal(events.first?.metadata["model"]?.string, nil, "hot fields should be removed from cold metadata")

        let metadata = try store.eventMetadata(id: "legacy-1")
        TestExpect.equal(metadata["extras"]?.object?["workspace"]?.string, "old", "migrated eventMetadata should read cold extras")
    }

    private static func dashboardSnapshotMatchesInMemoryAggregation() throws {
        let store = try makeStore()
        let now = try requireDate("2026-04-27T12:00:00Z")
        let calendar = Calendar(identifier: .gregorian)
        let events = [
            RequestEvent(id: "dash-1", timestamp: try requireDate("2026-04-27T10:00:00Z"), endpoint: "/v1/messages", model: "claude-sonnet", source: "account-a", authIndex: "key-a", isSuccess: true, latencyMs: 100, inputTokens: 10, outputTokens: 20, totalTokens: 30, estimatedCost: 0.01, metadata: ["plan": .string("Pro")]),
            RequestEvent(id: "dash-2", timestamp: try requireDate("2026-04-27T11:00:00Z"), endpoint: "/v1/messages", model: "claude-haiku", source: "account-a", authIndex: "key-a", isSuccess: false, latencyMs: 300, inputTokens: 5, outputTokens: 5, totalTokens: 10, estimatedCost: 0.02)
        ]
        try store.upsert(events: events)
        let hotEvents = events.map { event -> RequestEvent in
            var event = event
            event.metadata = [:]
            return event
        }

        let expected = UsageAggregator.snapshot(
            from: hotEvents,
            timeRange: .last24Hours,
            now: now,
            calendar: calendar,
            trendGranularity: .hour,
            costCalculationBasis: .estimate
        )
        let actual = try store.dashboardSnapshot(
            in: .last24Hours,
            prices: [],
            basis: .estimate,
            now: now,
            calendar: calendar,
            trendGranularity: .hour
        )

        TestExpect.equal(actual.summary, expected.summary, "dashboard summary should match in-memory aggregation")
        TestExpect.equal(actual.endpoints, expected.endpoints, "dashboard endpoint groups should match in-memory aggregation")
        TestExpect.equal(actual.models, expected.models, "dashboard model groups should match in-memory aggregation")
        TestExpect.equal(actual.trends, expected.trends, "dashboard trends should match in-memory aggregation")
        TestExpect.equal(actual.events, expected.events, "dashboard events should match in-memory aggregation")
        TestExpect.equal(actual.events.allSatisfy { $0.metadata.isEmpty }, true, "dashboard snapshot should use hot events only")
    }

    private static func dashboardQueryPlanAvoidsMetadataTable() throws {
        let store = try makeStore()
        let plan = try store.dashboardQueryPlan(in: .last24Hours, now: try requireDate("2026-04-27T12:00:00Z"), calendar: Calendar(identifier: .gregorian))
            .joined(separator: "\n")
            .lowercased()
        TestExpect.equal(plan.contains("usage_events"), true, "dashboard query plan should read the hot usage_events table")
        TestExpect.equal(plan.contains("usage_event_metadata"), false, "dashboard query plan should not touch cold metadata")
    }

    private static func dashboardSnapshotMeetsPerformanceBudget() throws {
        let environment = ProcessInfo.processInfo.environment
        if environment["CPA_USAGE_SKIP_BENCHMARK"] == "1" ||
            (environment["CI"] != nil && environment["CPA_USAGE_STRICT_BENCHMARK"] != "1") {
            print("Skipping dashboardSnapshot benchmark; set CPA_USAGE_STRICT_BENCHMARK=1 to run it in CI.")
            return
        }

        let store = try makeStore()
        let now = try requireDate("2026-04-27T12:00:00Z")
        let start = now.addingTimeInterval(-23 * 60 * 60)
        let endpoints = ["/v1/messages", "/v1/chat/completions", "/v1/responses", "/v1/embeddings"]
        let models = ["claude-sonnet", "claude-haiku", "gpt-5.5", "deepseek-chat"]
        let providers = ["anthropic", "anthropic", "openai", "deepseek"]
        let events = (0..<25_000).map { index in
            let model = models[index % models.count]
            let totalTokens = (index % 100) + (index % 80) + (index % 20)
            return RequestEvent(
                id: "perf-\(index)",
                timestamp: start.addingTimeInterval(Double(index % 86_000)),
                endpoint: endpoints[index % endpoints.count],
                model: model,
                source: "account-\(index % 5)",
                provider: providers[index % providers.count],
                authIndex: "key-\(index % 11)",
                isSuccess: index % 17 != 0,
                statusCode: index % 17 == 0 ? 429 : 200,
                errorMessage: index % 17 == 0 ? "rate limited" : "",
                latencyMs: Double(100 + (index % 900)),
                inputTokens: index % 100,
                outputTokens: index % 80,
                cachedTokens: index % 20,
                totalTokens: totalTokens,
                estimatedCost: Double(index % 100) / 100_000,
                metadata: benchmarkMetadata(index: index, model: model, totalTokens: totalTokens)
            )
        }
        try store.upsert(events: events)

        _ = try store.dashboardSnapshot(in: .last24Hours, now: now, calendar: Calendar(identifier: .gregorian))
        var durations: [Double] = []
        for _ in 0..<10 {
            let started = DispatchTime.now().uptimeNanoseconds
            _ = try store.dashboardSnapshot(in: .last24Hours, now: now, calendar: Calendar(identifier: .gregorian))
            let ended = DispatchTime.now().uptimeNanoseconds
            durations.append(Double(ended - started) / 1_000_000)
        }

        let threshold = environment["CPA_USAGE_BENCHMARK_P95_MS"].flatMap(Double.init) ?? 100
        let p95 = percentile95(durations)
        print("dashboardSnapshot benchmark p95: \(String(format: "%.2f", p95))ms")
        if p95 >= threshold {
            TestExpect.fail("dashboardSnapshot p95 should stay under \(threshold)ms, got \(String(format: "%.2f", p95))ms")
        }
    }

    private static func rawFetchSavesPlaintextJSON() throws {
        let store = try makeStore()
        let payload = try decodePayload("{\"usageDetails\":[{\"id\":\"raw-1\"}]}")
        try store.saveRawFetch(payload: payload, timeRange: .last24Hours, fetchedAt: try requireDate("2026-04-27T12:00:00Z"))

        let rows = try store.rawFetches()
        TestExpect.equal(rows.count, 1, "raw fetch should be saved")
        TestExpect.equal(rows.first?.timeRange, .last24Hours, "raw fetch time range should round-trip")
        TestExpect.equal(rows.first?.rawJSON.contains("raw-1"), true, "raw JSON should remain plaintext")
    }

    private static func rawFetchesRespectRetentionLimit() throws {
        let store = try makeStore()
        let payload = try decodePayload("{\"usageDetails\":[]}")
        let start = try requireDate("2026-04-27T00:00:00Z")

        for index in 0..<210 {
            try store.saveRawFetch(
                payload: payload,
                timeRange: .last24Hours,
                fetchedAt: start.addingTimeInterval(Double(index))
            )
        }

        let rows = try store.rawFetches()
        TestExpect.equal(rows.count, 200, "raw fetch retention should keep newest 200 rows")
        TestExpect.equal(rows.first?.fetchedAt, start.addingTimeInterval(209), "newest raw fetch should be retained")
        TestExpect.equal(rows.last?.fetchedAt, start.addingTimeInterval(10), "oldest retained raw fetch should be the 11th insert")
    }

    private static func sqlitePragmasAreConfigured() throws {
        let store = try makeStore()

        TestExpect.equal(try store.pragmaText("journal_mode"), "wal", "SQLite journal mode should be WAL")
        TestExpect.equal(try store.pragmaInt("busy_timeout"), 3000, "SQLite busy timeout should be 3000ms")
        TestExpect.equal(try store.pragmaInt("synchronous"), 1, "SQLite synchronous should be NORMAL")
    }



    private static func quotaSnapshotsRoundTrip() throws {
        let store = try makeStore()
        let snapshot = CredentialQuotaSnapshot(
            id: "quota-roundtrip",
            credential: "account@example.com",
            source: "console-account",
            provider: "anthropic",
            planTitle: "Max",
            shortWindow: CredentialQuotaUsage(title: "5小时", used: 10, limit: 100),
            capturedAt: try requireDate("2026-04-27T12:00:00Z"),
            rawMetadata: ["plan": .string("Max")]
        )
        try store.upsert(quotaSnapshots: [snapshot])

        let snapshots = try store.quotaSnapshots()
        TestExpect.equal(snapshots.count, 1, "quota snapshot should round-trip")
        TestExpect.equal(snapshots.first?.provider, "anthropic", "quota provider should round-trip")
        TestExpect.approx(snapshots.first?.shortWindow?.usagePercent ?? -1, 0.1, "quota usage should round-trip")
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

    private static func makeStore() throws -> UsageSQLiteStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite3")
        return try UsageSQLiteStore(databaseURL: url)
    }

    private static func benchmarkMetadata(index: Int, model: String, totalTokens: Int) -> [String: JSONValue] {
        [
            "model": .string(model),
            "timestamp": .string("2026-04-27T10:00:00Z"),
            "success": .bool(index % 17 != 0),
            "tokens": .object([
                "input": .number(Double(index % 100)),
                "output": .number(Double(index % 80)),
                "cached": .number(Double(index % 20)),
                "total": .number(Double(totalTokens))
            ]),
            "source": .string("account-\(index % 5)"),
            "latency_ms": .number(Double(100 + (index % 900))),
            "endpoint": .string(index % 2 == 0 ? "/v1/messages" : "/v1/chat/completions"),
            "auth_index": .string("key-\(index % 11)"),
            "failed": .bool(index % 17 == 0),
            "request": .object([
                "id": .string("req-\(index)"),
                "method": .string("POST"),
                "body_bytes": .number(Double(2_048 + (index % 4096))),
                "retry": .number(Double(index % 3))
            ]),
            "response": .object([
                "status": .number(index % 17 == 0 ? 429 : 200),
                "provider_request_id": .string("provider-\(index)")
            ]),
            "quota": .object([
                "limit": .number(5_000),
                "used": .number(Double(index % 5_000)),
                "remaining": .number(Double(5_000 - (index % 5_000))),
                "window": .string("5h")
            ]),
            "tags": .array([.string("dashboard"), .string("seed-\(index % 7)")])
        ]
    }

    private static func percentile95(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else {
            return 0
        }
        let rank = Int(ceil(Double(sorted.count) * 0.95))
        return sorted[min(sorted.count - 1, max(0, rank - 1))]
    }

    private static func makeLegacyVersionOneDatabase() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite3")
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw TestFailure("Unable to create legacy SQLite database")
        }
        defer { sqlite3_close(db) }
        let sql = """
        PRAGMA user_version = 1;
        CREATE TABLE usage_events (
          id TEXT PRIMARY KEY NOT NULL,
          timestamp REAL NOT NULL,
          endpoint TEXT NOT NULL,
          model TEXT NOT NULL,
          source TEXT NOT NULL,
          provider TEXT NOT NULL,
          auth_index TEXT NOT NULL,
          success INTEGER NOT NULL,
          status_code INTEGER,
          error_message TEXT NOT NULL,
          latency_ms REAL NOT NULL,
          input_tokens INTEGER NOT NULL,
          output_tokens INTEGER NOT NULL,
          reasoning_tokens INTEGER NOT NULL,
          cached_tokens INTEGER NOT NULL,
          total_tokens INTEGER NOT NULL,
          metadata_json TEXT NOT NULL
        );
        CREATE INDEX idx_usage_events_timestamp ON usage_events(timestamp);
        INSERT INTO usage_events VALUES (
          'legacy-1',
          1777284000,
          '/v1/messages',
          'claude-sonnet',
          'account.json',
          'anthropic',
          'account-a',
          1,
          200,
          '',
          1200,
          10,
          20,
          0,
          0,
          30,
          '{"model":"claude-sonnet","timestamp":"2026-04-27T10:00:00Z","tokens":{"total":30},"plan":"Legacy","estimated_cost":0.25,"extras":{"region":"iad","workspace":"old"}}'
        );
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw TestFailure("Unable to seed legacy SQLite database")
        }
        return url
    }

    private static func legacyBackupExists(for url: URL) throws -> Bool {
        if FileManager.default.fileExists(atPath: "\(url.path).backup-before-v2") {
            return true
        }

        let directory = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .contains { candidate in
                let name = candidate.lastPathComponent.lowercased()
                guard name != url.lastPathComponent.lowercased(), name.contains(stem) else {
                    return false
                }
                return name.contains("backup") || name.contains("bak") || name.contains("v1")
            }
    }
}
