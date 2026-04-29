import Foundation

@MainActor
enum UsageDashboardViewModelTests {
    static func run() async throws {
        try await refreshPersistsAndRebuildsFromSQLite()
        try await importPersistsUploadedPayloadWhenResponseIsStatusOnly()
        try await refreshPublishesBeforePersistenceCompletes()
        try await importPublishesBeforePersistenceCompletes()
        try await refreshKeepsSnapshotWhenPersistenceFails()
        try await importKeepsSnapshotWhenPersistenceFails()
        try await refreshPublishPathStaysUnder100Milliseconds()
        try startupLoadsPersistedEventsWithoutNetwork()
        try selectedTimeRangeReloadsPersistedEmptyRange()
        try startupDashboardSnapshotMatchesStoreDashboardSnapshot()
        try await managementKeyLoadsWhenDataIsPreloaded()
    }

    private static func refreshPersistsAndRebuildsFromSQLite() async throws {
        try await withHarness(responseJSON: usageJSON(id: "refresh-1", timestamp: "2026-04-27T10:00:00Z")) { viewModel, store, performer, _ in
            viewModel.connectionSettings = ConnectionSettings(baseURL: "http://localhost:8317/v0/management", managementKey: "secret")

            await viewModel.refresh()

            TestExpect.equal(viewModel.snapshot.events.map(\.id), ["refresh-1"], "refresh should publish fetched snapshot before persistence drains")
            TestExpect.equal(viewModel.loadState, .loaded, "refresh should finish UI state before persistence drains")
            await viewModel.waitForPendingPersistence()

            let persistedEvents = try store.events(in: .all)
            TestExpect.equal(persistedEvents.map(\.id), ["refresh-1"], "refresh should persist fetched events")
            TestExpect.equal(try performer.requestCount(), 1, "refresh should perform one network request")
        }
    }

    private static func importPersistsUploadedPayloadWhenResponseIsStatusOnly() async throws {
        try await withHarness(responseJSON: #"{"message":"ok","imported":1}"#) { viewModel, store, performer, _ in
            viewModel.connectionSettings = ConnectionSettings(baseURL: "http://localhost:8317/v0/management", managementKey: "secret")

            _ = try await viewModel.importUsage(Data(usageJSON(id: "import-1", timestamp: "2026-04-27T10:00:00Z").utf8))

            TestExpect.equal(viewModel.snapshot.events.map(\.id), ["import-1"], "status-only import should publish uploaded usage JSON before persistence drains")
            await viewModel.waitForPendingPersistence()

            let persistedEvents = try store.events(in: .all)
            TestExpect.equal(persistedEvents.map(\.id), ["import-1"], "status-only import should persist uploaded usage JSON")
            TestExpect.equal(try performer.requestCount(), 1, "import should not force a follow-up refresh")
        }
    }

    private static func refreshPublishesBeforePersistenceCompletes() async throws {
        try await withHarness(responseJSON: usageJSON(id: "refresh-pending", timestamp: "2026-04-27T10:00:00Z")) { _, store, performer, _ in
            let coordinator = RecordingPersistenceCoordinator()
            let viewModel = makeViewModel(store: store, performer: performer, persistenceCoordinator: coordinator)
            viewModel.connectionSettings = ConnectionSettings(baseURL: "http://localhost:8317/v0/management", managementKey: "secret")

            await viewModel.refresh()

            TestExpect.equal(viewModel.snapshot.events.map(\.id), ["refresh-pending"], "refresh should publish snapshot while persistence is only enqueued")
            TestExpect.equal(viewModel.loadState, .loaded, "refresh should be loaded while persistence is only enqueued")
            TestExpect.equal(coordinator.jobs.map { $0.events.map(\.id) }, [["refresh-pending"]], "refresh should enqueue persistence job")
            TestExpect.equal(try store.events(in: .all).isEmpty, true, "fake pending persistence should leave SQLite untouched")

            viewModel.setCostCalculationBasis(.estimate)
            TestExpect.equal(viewModel.snapshot.events.map(\.id), ["refresh-pending"], "settings rebuild should keep the just-published snapshot while persistence is pending")

            viewModel.selectedTimeRange = .all
            TestExpect.equal(viewModel.snapshot.events.map(\.id), ["refresh-pending"], "time range rebuild should keep the live payload while persistence is pending")
        }
    }

    private static func importPublishesBeforePersistenceCompletes() async throws {
        try await withHarness(responseJSON: #"{"message":"ok","imported":1}"#) { _, store, performer, _ in
            let coordinator = RecordingPersistenceCoordinator()
            let viewModel = makeViewModel(store: store, performer: performer, persistenceCoordinator: coordinator)
            viewModel.connectionSettings = ConnectionSettings(baseURL: "http://localhost:8317/v0/management", managementKey: "secret")

            _ = try await viewModel.importUsage(Data(usageJSON(id: "import-pending", timestamp: "2026-04-27T10:00:00Z").utf8))

            TestExpect.equal(viewModel.snapshot.events.map(\.id), ["import-pending"], "import should publish uploaded snapshot while persistence is only enqueued")
            TestExpect.equal(coordinator.jobs.map { $0.events.map(\.id) }, [["import-pending"]], "import should enqueue persistence job")
            TestExpect.equal(try store.events(in: .all).isEmpty, true, "fake pending import persistence should leave SQLite untouched")
        }
    }

    private static func refreshKeepsSnapshotWhenPersistenceFails() async throws {
        try await withHarness(responseJSON: usageJSON(id: "refresh-failure", timestamp: "2026-04-27T10:00:00Z")) { _, store, performer, _ in
            let coordinator = RecordingPersistenceCoordinator(errorOnEnqueue: TestFailure("synthetic persistence failure"))
            let viewModel = makeViewModel(store: store, performer: performer, persistenceCoordinator: coordinator)
            viewModel.connectionSettings = ConnectionSettings(baseURL: "http://localhost:8317/v0/management", managementKey: "secret")

            await viewModel.refresh()

            TestExpect.equal(viewModel.snapshot.events.map(\.id), ["refresh-failure"], "refresh should keep snapshot when persistence fails later")
            TestExpect.equal(viewModel.loadState, .loaded, "refresh should not become a UI failure when persistence fails later")
            TestExpect.equal(viewModel.errorMessage, nil, "refresh should not surface queued persistence failure as request error")
            TestExpect.equal(coordinator.lastPersistenceError() != nil, true, "fake coordinator should capture persistence failure")
        }
    }

    private static func importKeepsSnapshotWhenPersistenceFails() async throws {
        try await withHarness(responseJSON: #"{"message":"ok","imported":1}"#) { _, store, performer, _ in
            let coordinator = RecordingPersistenceCoordinator(errorOnEnqueue: TestFailure("synthetic import persistence failure"))
            let viewModel = makeViewModel(store: store, performer: performer, persistenceCoordinator: coordinator)
            viewModel.connectionSettings = ConnectionSettings(baseURL: "http://localhost:8317/v0/management", managementKey: "secret")

            _ = try await viewModel.importUsage(Data(usageJSON(id: "import-failure", timestamp: "2026-04-27T10:00:00Z").utf8))

            TestExpect.equal(viewModel.snapshot.events.map(\.id), ["import-failure"], "import should keep snapshot when persistence fails later")
            TestExpect.equal(viewModel.errorMessage, nil, "import should not surface queued persistence failure as request error")
            TestExpect.equal(coordinator.lastPersistenceError() != nil, true, "fake coordinator should capture import persistence failure")
        }
    }

    private static func refreshPublishPathStaysUnder100Milliseconds() async throws {
        let environment = ProcessInfo.processInfo.environment
        if environment["CPA_USAGE_SKIP_BENCHMARK"] == "1" ||
            (environment["CI"] != nil && environment["CPA_USAGE_STRICT_BENCHMARK"] != "1") {
            print("Skipping refresh publish benchmark; set CPA_USAGE_STRICT_BENCHMARK=1 to run it in CI.")
            return
        }

        let suiteName = "UsageDashboardViewModelTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure("Unable to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferencesStore = UsagePreferencesStore(defaults: defaults)
        preferencesStore.saveSelectedTimeRange(.last24Hours)
        let performer = ViewModelRequestPerformer(data: Data(seededUsageJSON(count: 50).utf8))
        let store = try makeStore()
        let coordinator = RecordingPersistenceCoordinator()
        let viewModel = makeViewModel(
            store: store,
            performer: performer,
            preferencesStore: preferencesStore,
            persistenceCoordinator: coordinator
        )
        viewModel.connectionSettings = ConnectionSettings(baseURL: "http://localhost:8317/v0/management", managementKey: "secret")

        await viewModel.refresh()

        guard let networkReturnTime = performer.lastReturnTime else {
            throw TestFailure("Refresh benchmark did not observe mocked network return")
        }
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - networkReturnTime.uptimeNanoseconds) / 1_000_000
        let threshold = environment["CPA_USAGE_REFRESH_PUBLISH_BENCHMARK_MS"].flatMap(Double.init) ?? 100
        print("refresh publish benchmark: \(String(format: "%.2f", elapsedMs))ms")
        if elapsedMs >= threshold {
            TestExpect.fail("refresh publish path should stay under \(threshold)ms, got \(String(format: "%.2f", elapsedMs))ms")
        }
        TestExpect.equal(viewModel.snapshot.events.count, 50, "benchmark refresh should publish seeded events")
        TestExpect.equal(coordinator.jobs.count, 1, "benchmark refresh should enqueue one persistence job")
        TestExpect.equal(coordinator.waitCallCount, 0, "refresh should not wait for queued persistence before publishing")
    }

    private static func startupLoadsPersistedEventsWithoutNetwork() throws {
        try withHarness(responseJSON: usageJSON(id: "unused", timestamp: "2026-04-27T10:00:00Z")) { viewModel, store, performer, _ in
            try store.upsert(events: [event(id: "startup-1", timestamp: "2026-04-27T10:00:00Z")])
            let relaunched = makeViewModel(store: store, performer: performer)

            TestExpect.equal(relaunched.snapshot.events.map(\.id), ["startup-1"], "startup should load persisted SQLite events")
            TestExpect.equal(try performer.requestCount(), 0, "startup should not fetch network usage")
            _ = viewModel
        }
    }

    private static func selectedTimeRangeReloadsPersistedEmptyRange() throws {
        try withHarness(responseJSON: usageJSON(id: "unused", timestamp: "2026-04-27T10:00:00Z"), selectedTimeRange: .all) { viewModel, store, _, preferencesStore in
            try store.upsert(events: [event(id: "old-1", timestamp: "2026-04-20T10:00:00Z")])
            let relaunched = makeViewModel(store: store, preferencesStore: preferencesStore)

            TestExpect.equal(relaunched.snapshot.events.map(\.id), ["old-1"], "all time should include old persisted events")
            relaunched.selectedTimeRange = .last24Hours
            TestExpect.equal(relaunched.snapshot.events.isEmpty, true, "empty persisted range should remain empty instead of using fallback data")
            TestExpect.equal(relaunched.snapshot.timeRange, .last24Hours, "empty persisted range should preserve selected range")
            _ = viewModel
        }
    }

    private static func startupDashboardSnapshotMatchesStoreDashboardSnapshot() throws {
        try withHarness(responseJSON: usageJSON(id: "unused", timestamp: "2026-04-27T10:00:00Z")) { viewModel, store, performer, preferencesStore in
            preferencesStore.saveCostDisplaySettings(UsageCostDisplaySettings(calculationBasis: .estimate))
            try store.upsert(events: dashboardEvents())

            let relaunched = makeViewModel(store: store, performer: performer, preferencesStore: preferencesStore)
            let expected = try store.dashboardSnapshot(
                in: .last24Hours,
                prices: [],
                basis: .estimate,
                now: fixedNow,
                calendar: Calendar(identifier: .gregorian),
                trendGranularity: relaunched.trendGranularity
            )

            TestExpect.equal(relaunched.snapshot.summary, expected.summary, "startup dashboard summary should match store dashboardSnapshot")
            TestExpect.equal(relaunched.snapshot.endpoints, expected.endpoints, "startup endpoint stats should match store dashboardSnapshot")
            TestExpect.equal(relaunched.snapshot.models, expected.models, "startup model stats should match store dashboardSnapshot")
            TestExpect.equal(relaunched.snapshot.trends, expected.trends, "startup trends should match store dashboardSnapshot")
            TestExpect.equal(relaunched.snapshot.events, expected.events, "startup events should match store dashboardSnapshot")
            TestExpect.equal(relaunched.snapshot.events.allSatisfy { $0.metadata.isEmpty }, true, "startup dashboard snapshot should keep hot events metadata-free")
            TestExpect.equal(try performer.requestCount(), 0, "startup dashboard snapshot should not fetch network usage")
            _ = viewModel
        }
    }

    private static func managementKeyLoadsWhenDataIsPreloaded() async throws {
        let keyStore = ViewModelTestKeyStore()
        try keyStore.saveManagementKey("persisted-secret", service: "test.cpa-usage-watcher", account: "management-key")
        let store = try makeStore()
        try store.upsert(events: [event(id: "startup-key", timestamp: "2026-04-27T10:00:00Z")])
        let viewModel = makeViewModel(store: store, keyStore: keyStore)

        TestExpect.equal(viewModel.hasLoadedData, true, "preloaded store should mark data as loaded")
        await viewModel.loadStoredConnectionSettingsIfNeeded()
        TestExpect.equal(viewModel.connectionSettings.managementKey, "persisted-secret", "preloaded data should not prevent keychain restore")
    }

    private static func withHarness(
        responseJSON: String,
        selectedTimeRange: UsageTimeRange = .last24Hours,
        _ body: (UsageDashboardViewModel, UsageSQLiteStore, ViewModelRequestPerformer, UsagePreferencesStore) async throws -> Void
    ) async throws {
        let suiteName = "UsageDashboardViewModelTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure("Unable to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferencesStore = UsagePreferencesStore(defaults: defaults)
        preferencesStore.saveSelectedTimeRange(selectedTimeRange)
        let store = try makeStore()
        let performer = ViewModelRequestPerformer(data: Data(responseJSON.utf8))
        let viewModel = makeViewModel(store: store, performer: performer, preferencesStore: preferencesStore)
        try await body(viewModel, store, performer, preferencesStore)
    }

    private static func withHarness(
        responseJSON: String,
        selectedTimeRange: UsageTimeRange = .last24Hours,
        _ body: (UsageDashboardViewModel, UsageSQLiteStore, ViewModelRequestPerformer, UsagePreferencesStore) throws -> Void
    ) throws {
        let suiteName = "UsageDashboardViewModelTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure("Unable to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferencesStore = UsagePreferencesStore(defaults: defaults)
        preferencesStore.saveSelectedTimeRange(selectedTimeRange)
        let store = try makeStore()
        let performer = ViewModelRequestPerformer(data: Data(responseJSON.utf8))
        let viewModel = makeViewModel(store: store, performer: performer, preferencesStore: preferencesStore)
        try body(viewModel, store, performer, preferencesStore)
    }

    private static func makeViewModel(
        store: UsageSQLiteStore,
        performer: ViewModelRequestPerformer = ViewModelRequestPerformer(data: Data(#"{"usageDetails":[]}"#.utf8)),
        preferencesStore: UsagePreferencesStore? = nil,
        keyStore: ViewModelTestKeyStore = ViewModelTestKeyStore(),
        persistenceCoordinator: UsagePersistenceCoordinating? = nil
    ) -> UsageDashboardViewModel {
        let preferencesStore = preferencesStore ?? UsagePreferencesStore(defaults: UserDefaults(suiteName: "UsageDashboardViewModelTests.\(UUID().uuidString)") ?? .standard)
        let connectionStore = ConnectionSettingsStore(
            defaults: UserDefaults(suiteName: "UsageDashboardViewModelConnection.\(UUID().uuidString)") ?? .standard,
            keychain: keyStore,
            baseURLDefaultsKey: "test.connection.baseURL",
            keychainService: "test.cpa-usage-watcher"
        )
        return UsageDashboardViewModel(
            apiClient: UsageAPIClient(requestPerformer: performer),
            connectionSettingsStore: connectionStore,
            preferencesStore: preferencesStore,
            sqliteStore: store,
            persistenceCoordinator: persistenceCoordinator,
            calendar: Calendar(identifier: .gregorian),
            now: { fixedNow }
        )
    }

    private static func makeStore() throws -> UsageSQLiteStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite3")
        return try UsageSQLiteStore(databaseURL: url)
    }

    private static func event(id: String, timestamp: String) throws -> RequestEvent {
        RequestEvent(
            id: id,
            timestamp: try requireDate(timestamp),
            endpoint: "/v1/messages",
            model: "claude-sonnet",
            source: "console-account",
            provider: "anthropic",
            authIndex: "account-a",
            isSuccess: true,
            latencyMs: 1200,
            inputTokens: 10,
            outputTokens: 20,
            totalTokens: 30
        )
    }

    private static func dashboardEvents() throws -> [RequestEvent] {
        [
            RequestEvent(
                id: "vm-dash-1",
                timestamp: try requireDate("2026-04-27T11:45:00Z"),
                endpoint: "/v1/messages",
                model: "claude-sonnet",
                source: "console-account",
                provider: "anthropic",
                authIndex: "account-a",
                isSuccess: true,
                statusCode: 200,
                latencyMs: 600,
                inputTokens: 1_000,
                outputTokens: 500,
                cachedTokens: 100,
                totalTokens: 1_600,
                estimatedCost: 0.03,
                metadata: ["plan": .string("Pro"), "extras": .object(["region": .string("iad")])]
            ),
            RequestEvent(
                id: "vm-dash-2",
                timestamp: try requireDate("2026-04-27T11:05:00Z"),
                endpoint: "/v1/messages",
                model: "claude-haiku",
                source: "console-account",
                provider: "anthropic",
                authIndex: "account-b",
                isSuccess: false,
                statusCode: 429,
                errorMessage: "rate limited",
                latencyMs: 900,
                inputTokens: 300,
                outputTokens: 0,
                totalTokens: 300,
                estimatedCost: 0.01,
                metadata: ["plan": .string("Team")]
            ),
            RequestEvent(
                id: "vm-dash-old",
                timestamp: try requireDate("2026-04-25T11:05:00Z"),
                endpoint: "/v1/old",
                model: "old-model",
                source: "legacy",
                provider: "legacy",
                authIndex: "old",
                isSuccess: true,
                latencyMs: 100,
                totalTokens: 9_999,
                estimatedCost: 1.0,
                metadata: ["plan": .string("Legacy")]
            )
        ]
    }

    private static func usageJSON(id: String, timestamp: String) -> String {
        """
        {"usageDetails":[{"id":"\(id)","timestamp":"\(timestamp)","endpoint":"/v1/messages","model":"claude-sonnet","source":"console-account","provider":"anthropic","authIndex":"account-a","success":true,"latencyMs":1200,"inputTokens":10,"outputTokens":20,"totalTokens":30}]}
        """
    }

    private static func seededUsageJSON(count: Int) -> String {
        let records = (0..<count).map { index in
            let minute = String(format: "%02d", index % 60)
            return """
            {"id":"seed-\(index)","timestamp":"2026-04-27T10:\(minute):00Z","endpoint":"/v1/messages","model":"model-\(index % 4)","source":"account-\(index % 5)","provider":"provider-\(index % 3)","authIndex":"key-\(index % 7)","success":\(index % 17 == 0 ? "false" : "true"),"latencyMs":\(100 + index % 900),"inputTokens":\(index % 100),"outputTokens":\(index % 80),"cachedTokens":\(index % 20),"totalTokens":\((index % 100) + (index % 80) + (index % 20)),"estimated_cost":\(Double(index % 100) / 100_000)}
            """
        }
        return #"{"usageDetails":["# + records.joined(separator: ",") + "]}"
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_777_290_400)

    private static func requireDate(_ value: String) throws -> Date {
        guard let date = UsageDateParser.parse(value) else {
            throw TestFailure("Unable to parse test date \(value)")
        }
        return date
    }
}

private final class ViewModelRequestPerformer: UsageRequestPerforming {
    var data: Data
    private(set) var lastReturnTime: DispatchTime?
    private var requests: [URLRequest] = []

    init(data: Data) {
        self.data = data
    }

    func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://localhost")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        lastReturnTime = DispatchTime.now()
        return (data, response)
    }

    func requestCount() throws -> Int {
        requests.count
    }
}

private final class RecordingPersistenceCoordinator: UsagePersistenceCoordinating {
    private(set) var jobs: [UsagePersistenceJob] = []
    private(set) var waitCallCount = 0
    private var persistenceError: Error?
    private let errorOnEnqueue: Error?

    init(
        errorOnEnqueue: Error? = nil
    ) {
        self.errorOnEnqueue = errorOnEnqueue
    }

    func dashboardSnapshot(
        in timeRange: UsageTimeRange,
        prices: [ModelPriceSetting],
        basis: CostCalculationBasis,
        now: Date,
        calendar: Calendar,
        trendGranularity: TrendGranularity?
    ) throws -> UsageSnapshot {
        UsageSnapshot(timeRange: timeRange)
    }

    func enqueue(_ job: UsagePersistenceJob) {
        jobs.append(job)
        if let errorOnEnqueue {
            persistenceError = errorOnEnqueue
        }
    }

    func waitForPendingWrites() async {
        waitCallCount += 1
    }

    func lastPersistenceError() -> Error? {
        persistenceError
    }
}

private final class ViewModelTestKeyStore: ManagementKeyStoring, @unchecked Sendable {
    private var keys: [String: String] = [:]

    func readManagementKey(service: String, account: String) throws -> String? {
        keys["\(service)|\(account)"]
    }

    func saveManagementKey(_ managementKey: String, service: String, account: String) throws {
        keys["\(service)|\(account)"] = managementKey
    }

    func deleteManagementKey(service: String, account: String) throws {
        keys.removeValue(forKey: "\(service)|\(account)")
    }
}
