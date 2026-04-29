import Foundation

@MainActor
enum UsageDashboardViewModelTests {
    static func run() async throws {
        try await refreshPersistsAndRebuildsFromSQLite()
        try await importPersistsUploadedPayloadWhenResponseIsStatusOnly()
        try startupLoadsPersistedEventsWithoutNetwork()
        try selectedTimeRangeReloadsPersistedEmptyRange()
        try startupDashboardSnapshotMatchesStoreDashboardSnapshot()
        try await managementKeyLoadsWhenDataIsPreloaded()
    }

    private static func refreshPersistsAndRebuildsFromSQLite() async throws {
        try await withHarness(responseJSON: usageJSON(id: "refresh-1", timestamp: "2026-04-27T10:00:00Z")) { viewModel, store, performer, _ in
            viewModel.connectionSettings = ConnectionSettings(baseURL: "http://localhost:8317/v0/management", managementKey: "secret")

            await viewModel.refresh()

            let persistedEvents = try store.events(in: .all)
            TestExpect.equal(persistedEvents.map(\.id), ["refresh-1"], "refresh should persist fetched events")
            TestExpect.equal(viewModel.snapshot.events.map(\.id), ["refresh-1"], "refresh should rebuild snapshot from SQLite")
            TestExpect.equal(try performer.requestCount(), 1, "refresh should perform one network request")
        }
    }

    private static func importPersistsUploadedPayloadWhenResponseIsStatusOnly() async throws {
        try await withHarness(responseJSON: #"{"message":"ok","imported":1}"#) { viewModel, store, performer, _ in
            viewModel.connectionSettings = ConnectionSettings(baseURL: "http://localhost:8317/v0/management", managementKey: "secret")

            _ = try await viewModel.importUsage(Data(usageJSON(id: "import-1", timestamp: "2026-04-27T10:00:00Z").utf8))

            let persistedEvents = try store.events(in: .all)
            TestExpect.equal(persistedEvents.map(\.id), ["import-1"], "status-only import should persist uploaded usage JSON")
            TestExpect.equal(viewModel.snapshot.events.map(\.id), ["import-1"], "status-only import should rebuild from SQLite")
            TestExpect.equal(try performer.requestCount(), 1, "import should not force a follow-up refresh")
        }
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
        keyStore: ViewModelTestKeyStore = ViewModelTestKeyStore()
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
        return (data, response)
    }

    func requestCount() throws -> Int {
        requests.count
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
