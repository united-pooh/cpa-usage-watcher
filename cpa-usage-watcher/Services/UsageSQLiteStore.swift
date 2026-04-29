import Foundation
import SQLite3

nonisolated final class UsageSQLiteStore: @unchecked Sendable {
    enum StoreError: Error {
        case openFailed(String)
        case prepareFailed(String)
        case stepFailed(String)
    }

    private let databaseURL: URL
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let schemaVersion = 2
    private static let rawFetchesRetentionLimit = 200
    private static let hotMetadataKeys: Set<String> = [
        "id",
        "requestid",
        "request_id",
        "uuid",
        "traceid",
        "trace_id",
        "timestamp",
        "time",
        "date",
        "datetime",
        "createdat",
        "created_at",
        "requesttime",
        "request_time",
        "endpoint",
        "apiendpoint",
        "api_endpoint",
        "path",
        "route",
        "api",
        "url",
        "model",
        "modelname",
        "model_name",
        "deployment",
        "engine",
        "source",
        "client",
        "service",
        "servicename",
        "service_name",
        "provider",
        "vendor",
        "apiprovider",
        "api_provider",
        "backend",
        "platform",
        "authindex",
        "auth_index",
        "apikeyindex",
        "api_key_index",
        "keyindex",
        "key_index",
        "credentialindex",
        "credential_index",
        "credential",
        "credentialname",
        "credential_name",
        "credentialid",
        "credential_id",
        "apikey",
        "api_key",
        "key",
        "keyname",
        "key_name",
        "authkey",
        "auth_key",
        "success",
        "issuccess",
        "is_success",
        "successful",
        "ok",
        "succeeded",
        "completed",
        "failed",
        "failure",
        "status",
        "state",
        "result",
        "outcome",
        "statuscode",
        "status_code",
        "httpstatus",
        "http_status",
        "code",
        "responsecode",
        "response_code",
        "errormessage",
        "error_message",
        "error",
        "failurereason",
        "failure_reason",
        "requestcount",
        "request_count",
        "requests",
        "totalrequests",
        "total_requests",
        "count",
        "calls",
        "callcount",
        "call_count",
        "hits",
        "successfulrequests",
        "successful_requests",
        "successcount",
        "success_count",
        "succeededrequests",
        "succeeded_requests",
        "okrequests",
        "ok_requests",
        "failedrequests",
        "failed_requests",
        "failurecount",
        "failure_count",
        "failures",
        "errors",
        "errorcount",
        "error_count",
        "failcount",
        "fail_count",
        "latency",
        "latencyms",
        "latency_ms",
        "averagelatency",
        "average_latency",
        "averagelatencyms",
        "average_latency_ms",
        "avglatency",
        "avg_latency",
        "duration",
        "durationms",
        "duration_ms",
        "elapsed",
        "elapsedms",
        "elapsed_ms",
        "responsetime",
        "response_time",
        "responsetimems",
        "response_time_ms",
        "totallatency",
        "total_latency",
        "totallatencyms",
        "total_latency_ms",
        "inputtokens",
        "input_tokens",
        "prompttokens",
        "prompt_tokens",
        "outputtokens",
        "output_tokens",
        "completiontokens",
        "completion_tokens",
        "reasoningtokens",
        "reasoning_tokens",
        "cachedtokens",
        "cached_tokens",
        "cachetokens",
        "cache_tokens",
        "totaltokens",
        "total_tokens",
        "tokens",
        "usage",
        "tokenusage",
        "token_usage",
        "tokendetails",
        "token_details",
        "usagemetadata",
        "usage_metadata",
        "messageusage",
        "message_usage",
        "metrics",
        "estimatedcost",
        "estimated_cost",
        "totalcost",
        "total_cost",
        "usagecost",
        "usage_cost",
        "estimatedcostusd",
        "estimated_cost_usd",
        "costusd",
        "cost_usd",
        "totalprice",
        "total_price",
        "cost",
        "price"
    ]

    init(databaseURL: URL? = nil) throws {
        if let databaseURL {
            self.databaseURL = databaseURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let directory = appSupport.appendingPathComponent("cpa-usage-watcher", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.databaseURL = directory.appendingPathComponent("usage.sqlite3")
        }
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        try open()
        try configurePragmas()
        try migrateSchemaIfNeeded()
    }

    deinit {
        sqlite3_close(db)
    }

    func upsert(events: [RequestEvent]) throws {
        let sql = """
        INSERT INTO usage_events (
          id, timestamp, endpoint, model, source, provider, auth_index, success, status_code, error_message,
          latency_ms, input_tokens, output_tokens, reasoning_tokens, cached_tokens, total_tokens, estimated_cost
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          timestamp=excluded.timestamp, endpoint=excluded.endpoint, model=excluded.model, source=excluded.source,
          provider=excluded.provider, auth_index=excluded.auth_index, success=excluded.success, status_code=excluded.status_code,
          error_message=excluded.error_message, latency_ms=excluded.latency_ms, input_tokens=excluded.input_tokens,
          output_tokens=excluded.output_tokens, reasoning_tokens=excluded.reasoning_tokens, cached_tokens=excluded.cached_tokens,
          total_tokens=excluded.total_tokens, estimated_cost=excluded.estimated_cost
        """
        let metadataSQL = """
        INSERT INTO usage_event_metadata (event_id, metadata_json)
        VALUES (?, ?)
        ON CONFLICT(event_id) DO UPDATE SET metadata_json=excluded.metadata_json
        """
        let deleteMetadataSQL = "DELETE FROM usage_event_metadata WHERE event_id = ?"

        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try withStatement(sql) { statement in
                try withStatement(metadataSQL) { metadataStatement in
                    try withStatement(deleteMetadataSQL) { deleteStatement in
                        for event in events {
                            sqlite3_reset(statement)
                            sqlite3_clear_bindings(statement)
                            bindEvent(event, to: statement)
                            try stepDone(statement)

                            let metadata = metadataExtras(for: event)
                            if metadata.isEmpty {
                                sqlite3_reset(deleteStatement)
                                sqlite3_clear_bindings(deleteStatement)
                                bind(event.id, to: deleteStatement, index: 1)
                                try stepDone(deleteStatement)
                            } else {
                                sqlite3_reset(metadataStatement)
                                sqlite3_clear_bindings(metadataStatement)
                                bind(event.id, to: metadataStatement, index: 1)
                                bind(jsonString(metadata), to: metadataStatement, index: 2)
                                try stepDone(metadataStatement)
                            }
                        }
                    }
                }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func events(
        in timeRange: UsageTimeRange = .all,
        now: Date = Date(),
        calendar: Calendar = .current,
        includeMetadata: Bool = true
    ) throws -> [RequestEvent] {
        let start = timeRange.startDate(now: now, calendar: calendar)
        let sql = eventsSQL(includeMetadata: includeMetadata, hasStart: start != nil)
        return try withStatement(sql) { statement in
            if let start {
                sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
                sqlite3_bind_double(statement, 2, now.timeIntervalSince1970)
            }
            var result: [RequestEvent] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                result.append(event(from: statement, metadataColumn: includeMetadata ? 17 : nil))
            }
            return result
        }
    }

    func eventMetadata(id: String) throws -> [String: JSONValue] {
        try withStatement("SELECT metadata_json FROM usage_event_metadata WHERE event_id = ?") { statement in
            bind(id, to: statement, index: 1)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return [:]
            }
            return decodeMetadata(columnText(statement, 0))
        }
    }

    func dashboardSnapshot(
        in timeRange: UsageTimeRange = .all,
        prices: [ModelPriceSetting] = [],
        basis: CostCalculationBasis = .defaultSelection,
        now: Date = Date(),
        calendar: Calendar = .current,
        trendGranularity: TrendGranularity? = nil
    ) throws -> UsageSnapshot {
        let hotEvents = try events(
            in: timeRange,
            now: now,
            calendar: calendar,
            includeMetadata: false
        )
        let quotaSnapshots = try quotaSnapshots()
        return dashboardSnapshot(
            from: hotEvents,
            timeRange: timeRange,
            prices: prices,
            basis: basis,
            now: now,
            calendar: calendar,
            trendGranularity: trendGranularity,
            credentialQuotas: quotaSnapshots
        )
    }

    func dashboardQueryPlan(
        in timeRange: UsageTimeRange = .all,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> [String] {
        let start = timeRange.startDate(now: now, calendar: calendar)
        let sql = "EXPLAIN QUERY PLAN " + eventsSQL(includeMetadata: false, hasStart: start != nil)
        return try withStatement(sql) { statement in
            if let start {
                sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
                sqlite3_bind_double(statement, 2, now.timeIntervalSince1970)
            }
            var rows: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                rows.append(columnText(statement, 3))
            }
            return rows
        }
    }

    func saveRawFetch(payload: UsageRawPayload, timeRange: UsageTimeRange, fetchedAt: Date = Date()) throws {
        let sql = "INSERT INTO raw_fetches (fetched_at, time_range, raw_json) VALUES (?, ?, ?)"
        try withStatement(sql) { statement in
            sqlite3_bind_double(statement, 1, fetchedAt.timeIntervalSince1970)
            bind(timeRange.rawValue, to: statement, index: 2)
            bind(jsonString(payload.root), to: statement, index: 3)
            try stepDone(statement)
        }
        try pruneRawFetches()
    }

    func upsert(quotaSnapshots snapshots: [CredentialQuotaSnapshot]) throws {
        let sql = """
        INSERT INTO credential_quota_snapshots (id, captured_at, provider, credential, raw_json)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          captured_at=excluded.captured_at,
          provider=excluded.provider,
          credential=excluded.credential,
          raw_json=excluded.raw_json
        """
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try withStatement(sql) { statement in
                for snapshot in snapshots {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    bind(snapshot.id, to: statement, index: 1)
                    sqlite3_bind_double(statement, 2, snapshot.capturedAt.timeIntervalSince1970)
                    bind(snapshot.provider, to: statement, index: 3)
                    bind(snapshot.credential, to: statement, index: 4)
                    bind(jsonString(snapshot), to: statement, index: 5)
                    try stepDone(statement)
                }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func quotaSnapshots() throws -> [CredentialQuotaSnapshot] {
        try withStatement("SELECT raw_json FROM credential_quota_snapshots ORDER BY captured_at DESC") { statement in
            var rows: [CredentialQuotaSnapshot] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let data = Data(columnText(statement, 0).utf8)
                if let snapshot = try? decoder.decode(CredentialQuotaSnapshot.self, from: data) {
                    rows.append(snapshot)
                }
            }
            return rows
        }
    }

    func rawFetches() throws -> [(fetchedAt: Date, timeRange: UsageTimeRange, rawJSON: String)] {
        try withStatement("SELECT fetched_at, time_range, raw_json FROM raw_fetches ORDER BY fetched_at DESC") { statement in
            var rows: [(Date, UsageTimeRange, String)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let date = Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
                let range = UsageTimeRange(rawValue: columnText(statement, 1)) ?? .all
                rows.append((date, range, columnText(statement, 2)))
            }
            return rows
        }
    }

    func pragmaText(_ name: String) throws -> String {
        try withStatement("PRAGMA \(name)") { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw StoreError.stepFailed(message)
            }
            return columnText(statement, 0)
        }
    }

    func pragmaInt(_ name: String) throws -> Int {
        try withStatement("PRAGMA \(name)") { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw StoreError.stepFailed(message)
            }
            return Int(sqlite3_column_int(statement, 0))
        }
    }

    func tableExists(_ name: String) throws -> Bool {
        try withStatement("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1") { statement in
            bind(name, to: statement, index: 1)
            return sqlite3_step(statement) == SQLITE_ROW
        }
    }

    func tableColumns(_ table: String) throws -> Set<String> {
        try withStatement("PRAGMA table_info(\(table))") { statement in
            var columns = Set<String>()
            while sqlite3_step(statement) == SQLITE_ROW {
                columns.insert(columnText(statement, 1))
            }
            return columns
        }
    }

    func indexes(_ table: String) throws -> Set<String> {
        try withStatement("PRAGMA index_list(\(table))") { statement in
            var indexes = Set<String>()
            while sqlite3_step(statement) == SQLITE_ROW {
                indexes.insert(columnText(statement, 1))
            }
            return indexes
        }
    }

    private func open() throws {
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            throw StoreError.openFailed(message)
        }
    }

    private func configurePragmas() throws {
        guard try pragmaText("journal_mode=WAL").lowercased() == "wal" else {
            throw StoreError.stepFailed(message)
        }
        try execute("PRAGMA busy_timeout=3000")
        try execute("PRAGMA synchronous=NORMAL")
    }

    private func pruneRawFetches() throws {
        try execute("""
        DELETE FROM raw_fetches
        WHERE id NOT IN (
            SELECT id FROM raw_fetches
            ORDER BY fetched_at DESC
            LIMIT \(Self.rawFetchesRetentionLimit)
        )
        """)
    }

    private func migrateSchemaIfNeeded() throws {
        if try !tableExists("usage_events") {
            try createSchemaV2()
            try execute("PRAGMA user_version = \(Self.schemaVersion)")
            return
        }

        let columns = try tableColumns("usage_events")
        if columns.contains("metadata_json") {
            try backupDatabaseBeforeV2Migration()
            try migrateVersionOneToVersionTwo()
            return
        }

        try createSchemaV2()
        try execute("PRAGMA user_version = \(Self.schemaVersion)")
    }

    private func createSchemaV2() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS usage_events (
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
          estimated_cost REAL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_usage_events_timestamp ON usage_events(timestamp);")
        try execute("""
        CREATE TABLE IF NOT EXISTS usage_event_metadata (
          event_id TEXT PRIMARY KEY NOT NULL,
          metadata_json TEXT NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS raw_fetches (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          fetched_at REAL NOT NULL,
          time_range TEXT NOT NULL,
          raw_json TEXT NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_raw_fetches_fetched_at ON raw_fetches(fetched_at);")
        try execute("""
        CREATE TABLE IF NOT EXISTS credential_quota_snapshots (
          id TEXT PRIMARY KEY NOT NULL,
          captured_at REAL NOT NULL,
          provider TEXT NOT NULL,
          credential TEXT NOT NULL,
          raw_json TEXT NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_credential_quota_snapshots_captured_at ON credential_quota_snapshots(captured_at DESC);")
    }

    private func backupDatabaseBeforeV2Migration() throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return
        }

        try? execute("PRAGMA wal_checkpoint(FULL)")
        let backupURL = URL(fileURLWithPath: databaseURL.path + ".backup-before-v2")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            return
        }
        try FileManager.default.copyItem(at: databaseURL, to: backupURL)
    }

    private func migrateVersionOneToVersionTwo() throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try execute("DROP INDEX IF EXISTS idx_usage_events_timestamp")
            try execute("ALTER TABLE usage_events RENAME TO usage_events_v1")
            try createSchemaV2()
            let legacyEvents = try readLegacyEvents()
            try upsertMigrated(events: legacyEvents)
            try execute("DROP TABLE usage_events_v1")
            try execute("PRAGMA user_version = \(Self.schemaVersion)")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func readLegacyEvents() throws -> [RequestEvent] {
        try withStatement("""
        SELECT
          id, timestamp, endpoint, model, source, provider, auth_index, success, status_code, error_message,
          latency_ms, input_tokens, output_tokens, reasoning_tokens, cached_tokens, total_tokens, metadata_json
        FROM usage_events_v1
        ORDER BY timestamp DESC
        """) { statement in
            var events: [RequestEvent] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let metadata = decodeMetadata(columnText(statement, 16))
                let estimatedCost = metadata.value(anyOf: ["estimated_cost", "estimatedCost", "cost", "price"])?.double
                var event = event(from: statement, metadataColumn: 16)
                event.estimatedCost = estimatedCost
                events.append(event)
            }
            return events
        }
    }

    private func upsertMigrated(events: [RequestEvent]) throws {
        let sql = """
        INSERT INTO usage_events (
          id, timestamp, endpoint, model, source, provider, auth_index, success, status_code, error_message,
          latency_ms, input_tokens, output_tokens, reasoning_tokens, cached_tokens, total_tokens, estimated_cost
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        let metadataSQL = "INSERT INTO usage_event_metadata (event_id, metadata_json) VALUES (?, ?)"
        try withStatement(sql) { statement in
            try withStatement(metadataSQL) { metadataStatement in
                for event in events {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    bindEvent(event, to: statement)
                    try stepDone(statement)

                    let metadata = metadataExtras(for: event)
                    guard !metadata.isEmpty else {
                        continue
                    }
                    sqlite3_reset(metadataStatement)
                    sqlite3_clear_bindings(metadataStatement)
                    bind(event.id, to: metadataStatement, index: 1)
                    bind(jsonString(metadata), to: metadataStatement, index: 2)
                    try stepDone(metadataStatement)
                }
            }
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.stepFailed(message)
        }
    }

    private func withStatement<T>(_ sql: String, body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StoreError.prepareFailed(message)
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.stepFailed(message)
        }
    }

    private func eventsSQL(includeMetadata: Bool, hasStart: Bool) -> String {
        let metadataColumn = includeMetadata ? ", COALESCE(m.metadata_json, '{}') AS metadata_json" : ""
        let metadataJoin = includeMetadata ? " LEFT JOIN usage_event_metadata m ON m.event_id = e.id" : ""
        let whereClause = hasStart ? " WHERE e.timestamp >= ? AND e.timestamp <= ?" : ""
        return """
        SELECT
          e.id, e.timestamp, e.endpoint, e.model, e.source, e.provider, e.auth_index, e.success, e.status_code, e.error_message,
          e.latency_ms, e.input_tokens, e.output_tokens, e.reasoning_tokens, e.cached_tokens, e.total_tokens, e.estimated_cost\(metadataColumn)
        FROM usage_events e\(metadataJoin)\(whereClause)
        ORDER BY e.timestamp DESC, e.id ASC
        """
    }

    private func dashboardSnapshot(
        from events: [RequestEvent],
        timeRange: UsageTimeRange,
        prices: [ModelPriceSetting],
        basis: CostCalculationBasis,
        now: Date,
        calendar: Calendar,
        trendGranularity: TrendGranularity?,
        credentialQuotas: [CredentialQuotaSnapshot]
    ) -> UsageSnapshot {
        let granularity = trendGranularity ?? inferredGranularity(for: timeRange, events: events)
        let priceLookup = modelPriceLookup(from: prices)
        var summary = DashboardAccumulator()
        var endpointAccumulators: [String: DashboardAccumulator] = [:]
        var endpointModelAccumulators: [DashboardEndpointModelKey: DashboardAccumulator] = [:]
        var modelAccumulators: [String: DashboardAccumulator] = [:]
        var credentialAccumulators: [DashboardCredentialKey: DashboardAccumulator] = [:]
        var trendAccumulators: [DashboardTrendKey: DashboardAccumulator] = [:]

        for event in events {
            let cost = dashboardCost(for: event, prices: priceLookup, basis: basis)
            summary.add(event: event, cost: cost)
            endpointAccumulators[event.endpoint, default: DashboardAccumulator()].add(event: event, cost: cost)
            endpointModelAccumulators[
                DashboardEndpointModelKey(endpoint: event.endpoint, model: event.model),
                default: DashboardAccumulator()
            ].add(event: event, cost: cost)
            modelAccumulators[event.model, default: DashboardAccumulator()].add(event: event, cost: cost)
            credentialAccumulators[
                DashboardCredentialKey(
                    credential: event.authIndex.isEmpty ? event.source : event.authIndex,
                    source: event.source,
                    provider: event.provider
                ),
                default: DashboardAccumulator()
            ].add(event: event, cost: cost)
            trendAccumulators[
                DashboardTrendKey(
                    bucket: bucketStart(for: event.timestamp, granularity: granularity, calendar: calendar),
                    model: event.model
                ),
                default: DashboardAccumulator()
            ].add(event: event, cost: cost)
        }

        let endpointModels = endpointModelAccumulators.map { key, accumulator in
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
        let modelsByEndpoint = Dictionary(grouping: endpointModels, by: \.endpoint)
        let endpoints = endpointAccumulators.map { endpoint, accumulator in
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
        let models = modelAccumulators.map { model, accumulator in
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
        let credentials = credentialAccumulators.map { key, accumulator in
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
        let trends = trendAccumulators.map { key, accumulator in
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

        let minutes = durationMinutes(events: events, timeRange: timeRange, now: now)
        return UsageSnapshot(
            summary: UsageSummary(
                totalRequests: summary.requests,
                successfulRequests: summary.successfulRequests,
                failedRequests: summary.failedRequests,
                averageLatencyMs: summary.averageLatencyMs,
                totalLatencyMs: summary.totalLatencyMs,
                totalTokens: summary.totalTokens,
                inputTokens: summary.inputTokens,
                outputTokens: summary.outputTokens,
                cachedTokens: summary.cachedTokens,
                reasoningTokens: summary.reasoningTokens,
                rpm: minutes > 0 ? Double(summary.requests) / minutes : 0,
                tpm: minutes > 0 ? Double(summary.totalTokens) / minutes : 0,
                totalCost: summary.cost
            ),
            endpoints: endpoints,
            models: models,
            events: events,
            credentials: credentials,
            credentialQuotas: credentialQuotas,
            trends: trends,
            timeRange: timeRange,
            generatedAt: now,
            sourceDescription: "本地历史记录",
            rawPayload: nil
        )
    }

    private func modelPriceLookup(from prices: [ModelPriceSetting]) -> [String: ModelPriceSetting] {
        var lookup: [String: ModelPriceSetting] = [:]
        for price in prices where !price.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && price.hasConfiguredPrice {
            lookup[normalizedModelKey(price.model)] = price
        }
        return lookup
    }

    private func dashboardCost(
        for event: RequestEvent,
        prices: [String: ModelPriceSetting],
        basis: CostCalculationBasis
    ) -> Double? {
        let savedPriceCost = prices[normalizedModelKey(event.model)]?.estimatedCost(
            inputTokens: event.inputTokens,
            outputTokens: event.outputTokens,
            cachedTokens: event.cachedTokens
        )
        switch basis {
        case .saved:
            return savedPriceCost
        case .estimate:
            return event.estimatedCost ?? savedPriceCost
        }
    }

    private func inferredGranularity(for timeRange: UsageTimeRange, events: [RequestEvent]) -> TrendGranularity {
        switch timeRange {
        case .last7Hours, .last24Hours:
            return .hour
        case .last7Days:
            return .day
        case .all:
            guard let earliest = events.map(\.timestamp).min(),
                  let latest = events.map(\.timestamp).max() else {
                return .hour
            }
            return latest.timeIntervalSince(earliest) > 48 * 60 * 60 ? .day : .hour
        }
    }

    private func bucketStart(for date: Date, granularity: TrendGranularity, calendar: Calendar) -> Date {
        switch granularity {
        case .hour:
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            return calendar.date(from: components) ?? date
        case .day:
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            return calendar.date(from: components) ?? date
        }
    }

    private func durationMinutes(events: [RequestEvent], timeRange: UsageTimeRange, now: Date) -> Double {
        if let hourWindow = timeRange.hourWindow {
            return max(Double(hourWindow) * 60, 1)
        }
        guard let earliest = events.map(\.timestamp).min(),
              let latest = events.map(\.timestamp).max() else {
            return 1
        }
        let boundedLatest = min(max(latest, earliest), now)
        return max(boundedLatest.timeIntervalSince(earliest), 60) / 60
    }

    private func normalizedModelKey(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private func bindEvent(_ event: RequestEvent, to statement: OpaquePointer) {
        bind(event.id, to: statement, index: 1)
        sqlite3_bind_double(statement, 2, event.timestamp.timeIntervalSince1970)
        bind(event.endpoint, to: statement, index: 3)
        bind(event.model, to: statement, index: 4)
        bind(event.source, to: statement, index: 5)
        bind(event.provider, to: statement, index: 6)
        bind(event.authIndex, to: statement, index: 7)
        sqlite3_bind_int(statement, 8, event.isSuccess ? 1 : 0)
        bind(event.statusCode, to: statement, index: 9)
        bind(event.errorMessage, to: statement, index: 10)
        sqlite3_bind_double(statement, 11, event.latencyMs)
        sqlite3_bind_int64(statement, 12, sqlite3_int64(event.inputTokens))
        sqlite3_bind_int64(statement, 13, sqlite3_int64(event.outputTokens))
        sqlite3_bind_int64(statement, 14, sqlite3_int64(event.reasoningTokens))
        sqlite3_bind_int64(statement, 15, sqlite3_int64(event.cachedTokens))
        sqlite3_bind_int64(statement, 16, sqlite3_int64(event.totalTokens))
        bind(event.estimatedCost ?? event.metadata.value(anyOf: ["estimated_cost", "estimatedCost", "cost", "price"])?.double, to: statement, index: 17)
    }

    private func event(from statement: OpaquePointer, metadataColumn: Int32?) -> RequestEvent {
        let metadata = metadataColumn.map { decodeMetadata(columnText(statement, $0)) } ?? [:]
        let statusCode = sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 8))
        let estimatedCost: Double?
        if metadataColumn == 17, sqlite3_column_type(statement, 16) != SQLITE_NULL {
            estimatedCost = sqlite3_column_double(statement, 16)
        } else {
            estimatedCost = metadata.value(anyOf: ["estimated_cost", "estimatedCost", "cost", "price"])?.double
        }
        return RequestEvent(
            id: columnText(statement, 0),
            timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            endpoint: columnText(statement, 2),
            model: columnText(statement, 3),
            source: columnText(statement, 4),
            provider: columnText(statement, 5),
            authIndex: columnText(statement, 6),
            isSuccess: sqlite3_column_int(statement, 7) == 1,
            statusCode: statusCode,
            errorMessage: columnText(statement, 9),
            latencyMs: sqlite3_column_double(statement, 10),
            inputTokens: Int(sqlite3_column_int64(statement, 11)),
            outputTokens: Int(sqlite3_column_int64(statement, 12)),
            reasoningTokens: Int(sqlite3_column_int64(statement, 13)),
            cachedTokens: Int(sqlite3_column_int64(statement, 14)),
            totalTokens: Int(sqlite3_column_int64(statement, 15)),
            estimatedCost: estimatedCost,
            metadata: metadata
        )
    }

    private func metadataExtras(for event: RequestEvent) -> [String: JSONValue] {
        event.metadata.filter { !Self.hotMetadataKeys.contains(Self.normalizedMetadataKey($0.key)) }
    }

    private static func normalizedMetadataKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func decodeMetadata(_ rawJSON: String) -> [String: JSONValue] {
        (try? decoder.decode([String: JSONValue].self, from: Data(rawJSON.utf8))) ?? [:]
    }

    private var message: String {
        String(cString: sqlite3_errmsg(db))
    }

    private func jsonString<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func bind(_ value: String, to statement: OpaquePointer, index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func bind(_ value: Int?, to statement: OpaquePointer, index: Int32) {
        if let value {
            sqlite3_bind_int(statement, index, Int32(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(_ value: Double?, to statement: OpaquePointer, index: Int32) {
        if let value {
            sqlite3_bind_double(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }
}

nonisolated private struct DashboardAccumulator {
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

    mutating func add(event: RequestEvent, cost eventCost: Double?) {
        requests += 1
        if event.isSuccess {
            successfulRequests += 1
        } else {
            failedRequests += 1
        }
        totalLatencyMs += event.latencyMs
        inputTokens += event.inputTokens
        outputTokens += event.outputTokens
        cachedTokens += event.cachedTokens
        reasoningTokens += event.reasoningTokens
        totalTokens += event.totalTokens
        if let currentLastUsedAt = lastUsedAt {
            lastUsedAt = max(currentLastUsedAt, event.timestamp)
        } else {
            lastUsedAt = event.timestamp
        }
        if let eventCost {
            cost = (cost ?? 0) + eventCost
        }
    }
}

nonisolated private struct DashboardEndpointModelKey: Hashable {
    var endpoint: String
    var model: String
}

nonisolated private struct DashboardCredentialKey: Hashable {
    var credential: String
    var source: String
    var provider: String
}

nonisolated private struct DashboardTrendKey: Hashable {
    var bucket: Date
    var model: String
}

nonisolated private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
