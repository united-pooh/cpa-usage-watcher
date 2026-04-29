import Foundation

@MainActor
enum UsagePreferencesStoreTests {
    static func run() throws {
        try verifiesCostDisplaySettingsDefaultsAndPersistence()
        try verifiesExchangeRateSanitization()
        try verifiesViewModelDirectExchangeRateSanitizationPersists()
        try verifiesModelPriceSanitizationAndAliasCompatibility()
        try verifiesViewModelCurrencyStateAndDraftSurface()
        try verifiesRefreshSettingsDefaultsAndPersistence()
        try verifiesRefreshSettingsIntervalSanitization()
        try verifiesViewModelRefreshSettingsIntegration()
    }

    private static func verifiesCostDisplaySettingsDefaultsAndPersistence() throws {
        try withIsolatedDefaults { defaults in
            let store = UsagePreferencesStore(defaults: defaults)

            let defaultSettings = store.loadCostDisplaySettings()
            TestExpect.equal(defaultSettings.displayCurrency, .usd, "default display currency")
            TestExpect.approx(
                defaultSettings.usdToCNYExchangeRate,
                UsageCostDisplaySettings.defaultUSDToCNYExchangeRate,
                "default USD to CNY rate"
            )
            TestExpect.equal(defaultSettings.calculationBasis, .saved, "default calculation basis")

            store.saveCostDisplaySettings(
                UsageCostDisplaySettings(
                    displayCurrency: .cny,
                    usdToCNYExchangeRate: 7.42,
                    calculationBasis: .estimate
                )
            )

            let reloadedStore = UsagePreferencesStore(defaults: defaults)
            let reloadedSettings = reloadedStore.loadCostDisplaySettings()
            TestExpect.equal(reloadedSettings.displayCurrency, .cny, "persisted display currency")
            TestExpect.approx(reloadedSettings.usdToCNYExchangeRate, 7.42, "persisted exchange rate")
            TestExpect.equal(reloadedSettings.calculationBasis, .estimate, "persisted calculation basis")

            reloadedStore.saveDisplayCurrency(.usd)
            TestExpect.equal(reloadedStore.loadDisplayCurrency(), .usd, "display currency update")
            TestExpect.approx(
                reloadedStore.loadUSDToCNYExchangeRate(),
                7.42,
                "currency update should preserve exchange rate"
            )
            TestExpect.equal(
                reloadedStore.loadCostCalculationBasis(),
                .estimate,
                "currency update should preserve calculation basis"
            )

            reloadedStore.saveCostCalculationBasis(.saved)
            TestExpect.equal(reloadedStore.loadCostCalculationBasis(), .saved, "calculation basis update")
        }
    }

    private static func verifiesExchangeRateSanitization() throws {
        try withIsolatedDefaults { defaults in
            let store = UsagePreferencesStore(defaults: defaults)

            store.saveUSDToCNYExchangeRate(-1)
            TestExpect.approx(
                store.loadUSDToCNYExchangeRate(),
                UsageCostDisplaySettings.defaultUSDToCNYExchangeRate,
                "negative exchange rates should reset to default"
            )

            store.saveCostDisplaySettings(
                UsageCostDisplaySettings(displayCurrency: .cny, usdToCNYExchangeRate: .infinity)
            )
            let settings = store.loadCostDisplaySettings()
            TestExpect.equal(settings.displayCurrency, .cny, "sanitizing rate should not change currency")
            TestExpect.approx(
                settings.usdToCNYExchangeRate,
                UsageCostDisplaySettings.defaultUSDToCNYExchangeRate,
                "non-finite exchange rates should reset to default"
            )
        }
    }

    private static func verifiesViewModelDirectExchangeRateSanitizationPersists() throws {
        try withIsolatedDefaults { defaults in
            let preferencesStore = UsagePreferencesStore(defaults: defaults)
            let connectionStore = ConnectionSettingsStore(
                defaults: defaults,
                keychain: InMemoryManagementKeyStore(),
                baseURLDefaultsKey: "test.connection.baseURL",
                keychainService: "test.cpa-usage-watcher"
            )
            let viewModel = UsageDashboardViewModel(
                apiClient: UsageAPIClient(requestPerformer: UnusedUsageRequestPerformer()),
                connectionSettingsStore: connectionStore,
                preferencesStore: preferencesStore
            )

            viewModel.displayCurrency = .cny
            viewModel.usdToCNYExchangeRate = .infinity

            TestExpect.approx(
                viewModel.usdToCNYExchangeRate,
                UsageCostDisplaySettings.defaultUSDToCNYExchangeRate,
                "direct invalid view model exchange rate should sanitize"
            )

            let persistedSettings = UsagePreferencesStore(defaults: defaults).loadCostDisplaySettings()
            TestExpect.equal(persistedSettings.displayCurrency, .cny, "direct invalid rate should preserve currency")
            TestExpect.approx(
                persistedSettings.usdToCNYExchangeRate,
                UsageCostDisplaySettings.defaultUSDToCNYExchangeRate,
                "direct sanitized view model exchange rate should persist"
            )
        }
    }

    private static func verifiesModelPriceSanitizationAndAliasCompatibility() throws {
        try withIsolatedDefaults { defaults in
            let modelPricesKey = "test.modelPrices"
            let store = UsagePreferencesStore(defaults: defaults, modelPricesKey: modelPricesKey)

            store.saveModelPrices([
                ModelPriceSetting(
                    model: "  claude-haiku  ",
                    promptPricePerMillion: -1,
                    completionPricePerMillion: 2.5,
                    cachePricePerMillion: .infinity
                )
            ])

            let sanitized = store.loadModelPrices()
            TestExpect.equal(sanitized.count, 1, "sanitized price count")
            TestExpect.equal(sanitized.first?.model, "claude-haiku", "model names should trim whitespace")
            TestExpect.approx(sanitized.first?.promptPricePerMillion ?? -1, 0, "negative prompt price")
            TestExpect.approx(sanitized.first?.completionPricePerMillion ?? -1, 2.5, "completion price")
            TestExpect.approx(sanitized.first?.cachePricePerMillion ?? -1, 0, "non-finite cache price")

            defaults.set(
                Data(
                    """
                    [
                      {
                        "model": "alias-a",
                        "inputPricePerMillion": 1.1,
                        "outputPricePerMillion": 2.2,
                        "cachedPricePerMillion": 0.3
                      },
                      {
                        "model": "alias-b",
                        "prompt": 3.3,
                        "completion": 4.4,
                        "cache": 0.5
                      }
                    ]
                    """.utf8
                ),
                forKey: modelPricesKey
            )

            let aliased = store.loadModelPrices()
            TestExpect.equal(aliased.count, 2, "aliased price count")
            TestExpect.approx(aliased[0].promptPricePerMillion, 1.1, "input alias")
            TestExpect.approx(aliased[0].completionPricePerMillion, 2.2, "output alias")
            TestExpect.approx(aliased[0].cachePricePerMillion, 0.3, "cached alias")
            TestExpect.approx(aliased[1].promptPricePerMillion, 3.3, "prompt alias")
            TestExpect.approx(aliased[1].completionPricePerMillion, 4.4, "completion alias")
            TestExpect.approx(aliased[1].cachePricePerMillion, 0.5, "cache alias")
        }
    }

    private static func verifiesViewModelCurrencyStateAndDraftSurface() throws {
        try withIsolatedDefaults { defaults in
            let preferencesStore = UsagePreferencesStore(defaults: defaults)
            let connectionStore = ConnectionSettingsStore(
                defaults: defaults,
                keychain: InMemoryManagementKeyStore(),
                baseURLDefaultsKey: "test.connection.baseURL",
                keychainService: "test.cpa-usage-watcher"
            )
            let viewModel = UsageDashboardViewModel(
                apiClient: UsageAPIClient(requestPerformer: UnusedUsageRequestPerformer()),
                connectionSettingsStore: connectionStore,
                preferencesStore: preferencesStore
            )

            viewModel.setUSDToCNYExchangeRate(7.25)
            viewModel.setCostCalculationBasis(.estimate)
            viewModel.toggleDisplayCurrency()

            TestExpect.equal(viewModel.displayCurrency, .cny, "view model display currency toggle")
            TestExpect.approx(viewModel.usdToCNYExchangeRate, 7.25, "view model exchange rate")
            TestExpect.equal(viewModel.costCalculationBasis, .estimate, "view model calculation basis")
            TestExpect.approx(viewModel.convertedCost(2) ?? -1, 14.5, "view model converted cost")
            TestExpect.equal(viewModel.formattedCost(2, fractionLength: 2), "¥14.50", "formatted cost should use selected CNY unit")
            TestExpect.equal(viewModel.formattedCost(0, placeholder: "未配置", fractionLength: 2), "¥0.00", "zero cost should still use selected CNY unit")
            viewModel.setDisplayCurrency(.usd)
            TestExpect.equal(viewModel.formattedCost(0, placeholder: "未配置", fractionLength: 2), "$0.00", "zero cost should switch back to USD unit")
            viewModel.setDisplayCurrency(.cny)

            let persistedSettings = UsagePreferencesStore(defaults: defaults).loadCostDisplaySettings()
            TestExpect.equal(persistedSettings.displayCurrency, .cny, "view model persisted currency")
            TestExpect.approx(persistedSettings.usdToCNYExchangeRate, 7.25, "view model persisted rate")
            TestExpect.equal(persistedSettings.calculationBasis, .estimate, "view model persisted basis")

            let draft = ModelPriceDraft(
                model: "  claude-haiku  ",
                promptPricePerMillion: -1,
                completionPricePerMillion: 2,
                cachePricePerMillion: .infinity
            )
            TestExpect.equal(viewModel.hasUnsavedModelPriceDraft(draft), true, "new draft should be unsaved")

            viewModel.saveModelPriceDraft(draft)
            let savedPrice = viewModel.modelPrice(for: "claude-haiku")
            TestExpect.equal(savedPrice?.model, "claude-haiku", "draft save should trim model")
            TestExpect.approx(savedPrice?.promptPricePerMillion ?? -1, 0, "draft prompt sanitization")
            TestExpect.approx(savedPrice?.completionPricePerMillion ?? -1, 2, "draft completion sanitization")
            TestExpect.approx(savedPrice?.cachePricePerMillion ?? -1, 0, "draft cache sanitization")

            TestExpect.equal(
                viewModel.hasUnsavedModelPriceDraft(ModelPriceDraft(price: savedPrice ?? .empty)),
                false,
                "draft matching saved price should not be unsaved"
            )
        }
    }

    private static func verifiesRefreshSettingsDefaultsAndPersistence() throws {
        try withIsolatedDefaults { defaults in
            let store = UsagePreferencesStore(defaults: defaults)

            let defaultSettings = store.loadRefreshSettings()
            TestExpect.equal(defaultSettings.isAutoRefreshEnabled, true, "default auto-refresh enabled")
            TestExpect.equal(defaultSettings.intervalSeconds, 60, "default interval is 60s")

            store.saveRefreshSettings(UsageRefreshSettings(isAutoRefreshEnabled: false, intervalSeconds: 30))

            let reloadedStore = UsagePreferencesStore(defaults: defaults)
            let reloaded = reloadedStore.loadRefreshSettings()
            TestExpect.equal(reloaded.isAutoRefreshEnabled, false, "persisted auto-refresh disabled")
            TestExpect.equal(reloaded.intervalSeconds, 30, "persisted interval")
        }
    }

    private static func verifiesRefreshSettingsIntervalSanitization() throws {
        try withIsolatedDefaults { defaults in
            let store = UsagePreferencesStore(defaults: defaults)

            store.saveRefreshSettings(UsageRefreshSettings(isAutoRefreshEnabled: true, intervalSeconds: 0))
            TestExpect.equal(
                store.loadRefreshSettings().intervalSeconds,
                UsageRefreshSettings.minimumIntervalSeconds,
                "interval below minimum should clamp to minimum"
            )
            TestExpect.equal(UsageRefreshSettings.sanitizedInterval(5), 10, "5s should clamp to new minimum")
            TestExpect.equal(UsageRefreshSettings.sanitizedInterval(10), 10, "10s should be accepted")

            store.saveRefreshSettings(UsageRefreshSettings(isAutoRefreshEnabled: true, intervalSeconds: 99999))
            TestExpect.equal(
                store.loadRefreshSettings().intervalSeconds,
                UsageRefreshSettings.maximumIntervalSeconds,
                "interval above maximum should clamp to maximum"
            )

            store.saveRefreshSettings(UsageRefreshSettings(isAutoRefreshEnabled: true, intervalSeconds: -5))
            TestExpect.equal(
                store.loadRefreshSettings().intervalSeconds,
                UsageRefreshSettings.minimumIntervalSeconds,
                "negative interval should clamp to minimum"
            )

            store.saveRefreshSettings(UsageRefreshSettings(isAutoRefreshEnabled: true, intervalSeconds: 120))
            TestExpect.equal(store.loadRefreshSettings().intervalSeconds, 120, "valid interval should persist unchanged")
        }
    }

    private static func verifiesViewModelRefreshSettingsIntegration() throws {
        try withIsolatedDefaults { defaults in
            let preferencesStore = UsagePreferencesStore(defaults: defaults)
            let connectionStore = ConnectionSettingsStore(
                defaults: defaults,
                keychain: InMemoryManagementKeyStore(),
                baseURLDefaultsKey: "test.connection.baseURL",
                keychainService: "test.cpa-usage-watcher"
            )
            let viewModel = UsageDashboardViewModel(
                apiClient: UsageAPIClient(requestPerformer: UnusedUsageRequestPerformer()),
                connectionSettingsStore: connectionStore,
                preferencesStore: preferencesStore
            )

            // Default state
            TestExpect.equal(viewModel.refreshSettings.isAutoRefreshEnabled, true, "vm default auto-refresh enabled")
            TestExpect.equal(viewModel.refreshSettings.intervalSeconds, 60, "vm default interval")
            TestExpect.equal(viewModel.refreshIntervalTitle, "自動刷新 · 1m", "vm default interval title")

            // setRefreshIntervalSeconds clamps and persists
            viewModel.setRefreshIntervalSeconds(0)
            TestExpect.equal(
                viewModel.refreshSettings.intervalSeconds,
                UsageRefreshSettings.minimumIntervalSeconds,
                "setRefreshIntervalSeconds clamps below minimum"
            )

            viewModel.setRefreshIntervalSeconds(60)
            TestExpect.equal(viewModel.refreshSettings.intervalSeconds, 60, "setRefreshIntervalSeconds accepts valid value")
            TestExpect.equal(viewModel.refreshIntervalTitle, "自動刷新 · 1m", "minute title for 60s interval")

            let persisted = UsagePreferencesStore(defaults: defaults).loadRefreshSettings()
            TestExpect.equal(persisted.intervalSeconds, 60, "setRefreshIntervalSeconds persists via preferences store")

            // setAutoRefreshEnabled
            viewModel.setAutoRefreshEnabled(false)
            TestExpect.equal(viewModel.refreshSettings.isAutoRefreshEnabled, false, "setAutoRefreshEnabled false")
            TestExpect.equal(viewModel.refreshIntervalTitle, "自動刷新 · 關閉", "disabled auto-refresh title")

            let persistedDisabled = UsagePreferencesStore(defaults: defaults).loadRefreshSettings()
            TestExpect.equal(persistedDisabled.isAutoRefreshEnabled, false, "disabled state persists")
        }
    }

    private static func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "UsagePreferencesStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure("Unable to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        try body(defaults)
    }
}

private final class InMemoryManagementKeyStore: ManagementKeyStoring, @unchecked Sendable {
    private var keys: [String: String] = [:]

    func readManagementKey(service: String, account: String) throws -> String? {
        keys[key(service: service, account: account)]
    }

    func saveManagementKey(_ managementKey: String, service: String, account: String) throws {
        keys[key(service: service, account: account)] = managementKey
    }

    func deleteManagementKey(service: String, account: String) throws {
        keys.removeValue(forKey: key(service: service, account: account))
    }

    private func key(service: String, account: String) -> String {
        "\(service)|\(account)"
    }
}

private struct UnusedUsageRequestPerformer: UsageRequestPerforming {
    func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        throw TestFailure("Usage request performer should not be called by preferences tests")
    }
}
