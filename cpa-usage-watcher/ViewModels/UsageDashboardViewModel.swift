import Combine
import Foundation

@MainActor
final class UsageDashboardViewModel: ObservableObject {
    @Published var connectionSettings: ConnectionSettings
    @Published private(set) var loadState: UsageLoadState = .idle
    @Published private(set) var rawPayload: UsageRawPayload?
    @Published private(set) var snapshot: UsageSnapshot = .empty
    @Published private(set) var displaySnapshot: UsageSnapshot = .empty
    @Published private(set) var lastUpdatedAt: Date?
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var refreshSettings: UsageRefreshSettings {
        didSet {
            guard oldValue != refreshSettings else {
                return
            }
            let sanitized = UsageRefreshSettings(
                isAutoRefreshEnabled: refreshSettings.isAutoRefreshEnabled,
                intervalSeconds: UsageRefreshSettings.sanitizedInterval(refreshSettings.intervalSeconds)
            )
            if sanitized != refreshSettings {
                refreshSettings = sanitized
                return
            }
            preferencesStore.saveRefreshSettings(refreshSettings)
        }
    }
    @Published var masksSensitiveValues: Bool {
        didSet {
            guard oldValue != masksSensitiveValues else {
                return
            }
            preferencesStore.saveMasksSensitiveValues(masksSensitiveValues)
        }
    }

    @Published var displayCurrency: DisplayCurrency {
        didSet {
            guard oldValue != displayCurrency else {
                return
            }
            saveCostDisplaySettings()
        }
    }

    @Published var usdToCNYExchangeRate: Double {
        didSet {
            guard !isSanitizingExchangeRate else {
                return
            }

            let sanitizedExchangeRate = UsageCostDisplaySettings.sanitizeExchangeRate(usdToCNYExchangeRate)
            guard sanitizedExchangeRate == usdToCNYExchangeRate else {
                isSanitizingExchangeRate = true
                usdToCNYExchangeRate = sanitizedExchangeRate
                isSanitizingExchangeRate = false
                saveCostDisplaySettings()
                return
            }

            guard oldValue != usdToCNYExchangeRate else {
                return
            }
            saveCostDisplaySettings()
        }
    }

    @Published var costCalculationBasis: CostCalculationBasis {
        didSet {
            guard oldValue != costCalculationBasis else {
                return
            }
            saveCostDisplaySettings()
            rebuildSnapshot()
        }
    }

    @Published var selectedTimeRange: UsageTimeRange {
        didSet {
            guard oldValue != selectedTimeRange else {
                return
            }
            preferencesStore.saveSelectedTimeRange(selectedTimeRange)
            rebuildSnapshot()
        }
    }

    @Published var eventFilters: RequestEventFilters {
        didSet {
            guard oldValue != eventFilters else {
                return
            }
            updateDisplaySnapshot()
        }
    }

    @Published var endpointSort: EndpointSortState {
        didSet {
            guard oldValue != endpointSort else {
                return
            }
            updateDisplaySnapshot()
        }
    }

    @Published var modelSort: ModelSortState {
        didSet {
            guard oldValue != modelSort else {
                return
            }
            updateDisplaySnapshot()
        }
    }

    @Published var eventSort: EventSortState {
        didSet {
            guard oldValue != eventSort else {
                return
            }
            updateDisplaySnapshot()
        }
    }

    @Published var credentialSort: CredentialSortState {
        didSet {
            guard oldValue != credentialSort else {
                return
            }
            updateDisplaySnapshot()
        }
    }

    @Published var modelPriceSort: ModelPriceSortState

    @Published var expandedEndpointIDs: Set<String>
    @Published var selectedEndpointIDs: Set<String>
    @Published var selectedModelIDs: Set<String>
    @Published var selectedEventIDs: Set<String>
    @Published var selectedCredentialIDs: Set<String>
    @Published var selectedModelPriceIDs: Set<String>

    @Published var chartSeriesSelection: ChartSeriesSelection {
        didSet {
            guard oldValue != chartSeriesSelection else {
                return
            }
            preferencesStore.saveChartSeriesSelection(chartSeriesSelection)
            updateDisplaySnapshot()
        }
    }

    @Published var trendGranularity: TrendGranularity {
        didSet {
            guard oldValue != trendGranularity else {
                return
            }
            preferencesStore.saveTrendGranularity(trendGranularity)
            rebuildSnapshot()
        }
    }

    @Published private(set) var modelPrices: [ModelPriceSetting] {
        didSet {
            guard oldValue != modelPrices else {
                return
            }
            preferencesStore.saveModelPrices(modelPrices)
            rebuildSnapshot()
        }
    }

    let timeRangeOptions = UsageTimeRange.allCases
    let trendGranularityOptions = TrendGranularity.allCases
    let endpointSortOptions = EndpointSort.allCases
    let modelSortOptions = ModelSort.allCases
    let eventSortOptions = EventSort.allCases
    let credentialSortOptions = CredentialSort.allCases
    let modelPriceSortOptions = ModelPriceSort.allCases
    let displayCurrencyOptions = DisplayCurrency.allCases

    private let apiClient: UsageAPIClient
    private let connectionSettingsStore: ConnectionSettingsStore
    private let preferencesStore: UsagePreferencesStore
    private let sqliteStore: UsageSQLiteStore?
    private let calendar: Calendar
    private let now: () -> Date
    private var isSanitizingExchangeRate = false
    private var didStartStoredConnectionSettingsLoad = false

    init(
        apiClient: UsageAPIClient? = nil,
        connectionSettingsStore: ConnectionSettingsStore? = nil,
        preferencesStore: UsagePreferencesStore? = nil,
        sqliteStore: UsageSQLiteStore? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        let connectionSettingsStore = connectionSettingsStore ?? ConnectionSettingsStore()
        let preferencesStore = preferencesStore ?? UsagePreferencesStore()
        let resolvedSQLiteStore: UsageSQLiteStore? = sqliteStore ?? (try? UsageSQLiteStore())

        self.apiClient = apiClient ?? UsageAPIClient()
        self.connectionSettingsStore = connectionSettingsStore
        self.preferencesStore = preferencesStore
        self.sqliteStore = resolvedSQLiteStore
        self.calendar = calendar
        self.now = now

        self.connectionSettings = connectionSettingsStore.loadWithoutManagementKey()
        self.selectedTimeRange = preferencesStore.loadSelectedTimeRange()
        self.eventFilters = .empty
        self.endpointSort = EndpointSortState()
        self.modelSort = ModelSortState()
        self.eventSort = EventSortState()
        self.credentialSort = CredentialSortState()
        self.modelPriceSort = ModelPriceSortState()
        self.expandedEndpointIDs = []
        self.selectedEndpointIDs = []
        self.selectedModelIDs = []
        self.selectedEventIDs = []
        self.selectedCredentialIDs = []
        self.selectedModelPriceIDs = []
        self.chartSeriesSelection = preferencesStore.loadChartSeriesSelection()
        self.trendGranularity = preferencesStore.loadTrendGranularity()
        self.modelPrices = preferencesStore.loadModelPrices()
        self.masksSensitiveValues = preferencesStore.loadMasksSensitiveValues()
        let costDisplaySettings = preferencesStore.loadCostDisplaySettings()
        self.displayCurrency = costDisplaySettings.displayCurrency
        self.usdToCNYExchangeRate = costDisplaySettings.usdToCNYExchangeRate
        self.costCalculationBasis = costDisplaySettings.calculationBasis
        self.refreshSettings = preferencesStore.loadRefreshSettings()

        if let store = resolvedSQLiteStore {
            do {
                self.snapshot = try persistedSnapshot(from: store)
            } catch {
                self.errorMessage = Self.message(for: error)
            }
        }

        updateDisplaySnapshot()
    }

    var isLoading: Bool {
        loadState.isLoading
    }

    var hasLoadedData: Bool {
        rawPayload != nil || !snapshot.events.isEmpty || snapshot.summary.totalRequests > 0
    }

    var hasActiveEventFilters: Bool {
        eventFilters.isActive
    }

    var canSelectMoreChartSeries: Bool {
        chartSeriesSelection.selectedModels.count < ChartSeriesSelection.maxSelectedModels
    }

    var hasModelPrices: Bool {
        !modelPrices.isEmpty
    }

    var hasConfiguredModelPrices: Bool {
        modelPrices.contains(where: \.hasConfiguredPrice)
    }

    var sortedEndpoints: [EndpointUsageStat] {
        displaySnapshot.endpoints
    }

    var sortedModels: [ModelUsageStat] {
        displaySnapshot.models
    }

    var sortedEvents: [RequestEvent] {
        displaySnapshot.events
    }

    var filteredEventExportCount: Int {
        sortedEvents.count
    }

    var sortedCredentials: [CredentialUsageStat] {
        displaySnapshot.credentials
    }

    var sortedModelPrices: [ModelPriceSetting] {
        sortedModelPrices(from: modelPrices)
    }

    var selectedChartModelNames: [String] {
        let availableModels = chartSeriesOptions
        let selected = availableModels.filter { chartSeriesSelection.contains($0) }

        if selected.isEmpty {
            return Array(availableModels.prefix(ChartSeriesSelection.maxSelectedModels))
        }

        return Array(selected.prefix(ChartSeriesSelection.maxSelectedModels))
    }

    var chartTrendPoints: [UsageTrendPoint] {
        let selectedModels = Set(selectedChartModelNames)
        guard !selectedModels.isEmpty else {
            return snapshot.trends
        }
        return snapshot.trends.filter { selectedModels.contains($0.model) }
    }

    var modelFilterOptions: [String] {
        uniqueSorted(snapshot.events.map(\.model))
    }

    var sourceFilterOptions: [String] {
        uniqueSorted(snapshot.events.map(\.source))
    }

    var authIndexFilterOptions: [String] {
        uniqueSorted(snapshot.events.map(\.authIndex))
    }

    var endpointFilterOptions: [String] {
        uniqueSorted(snapshot.endpoints.map(\.endpoint))
    }

    var credentialFilterOptions: [String] {
        uniqueSorted(snapshot.credentials.map(\.credential))
    }

    var chartSeriesOptions: [String] {
        let modelNames = snapshot.models.map(\.model) + snapshot.trends.map(\.model)
        return uniqueSorted(modelNames)
    }

    var priceModelOptions: [String] {
        uniqueSorted(snapshot.models.map(\.model) + modelPrices.map(\.model))
    }

    var sensitiveValuesToggleTitle: String {
        masksSensitiveValues ? "显示敏感值" : "隐藏敏感值"
    }

    var sensitiveValuesToggleIcon: String {
        masksSensitiveValues ? "eye" : "eye.slash"
    }

    var refreshIntervalTitle: String {
        guard refreshSettings.isAutoRefreshEnabled else {
            return "自動刷新 · 關閉"
        }
        let seconds = refreshSettings.intervalSeconds
        if seconds < 60 {
            return "自動刷新 · \(seconds)s"
        } else if seconds % 60 == 0 {
            return "自動刷新 · \(seconds / 60)m"
        } else {
            return "自動刷新 · \(seconds)s"
        }
    }

    func setRefreshIntervalSeconds(_ seconds: Int) {
        refreshSettings = UsageRefreshSettings(
            isAutoRefreshEnabled: refreshSettings.isAutoRefreshEnabled,
            intervalSeconds: UsageRefreshSettings.sanitizedInterval(seconds)
        )
    }

    func setAutoRefreshEnabled(_ enabled: Bool) {
        refreshSettings = UsageRefreshSettings(
            isAutoRefreshEnabled: enabled,
            intervalSeconds: refreshSettings.intervalSeconds
        )
    }

    func loadStoredConnectionSettingsIfNeeded() async {
        guard !didStartStoredConnectionSettingsLoad else {
            return
        }
        didStartStoredConnectionSettingsLoad = true

        do {
            let store = connectionSettingsStore
            let loadedSettings = try await Task.detached(priority: .utility) {
                try store.load()
            }.value
            connectionSettings = loadedSettings
            errorMessage = nil
        } catch {
            let message = Self.message(for: error)
            errorMessage = message
            loadState = .failed(message)
        }
    }

    func refresh() async {
        guard !loadState.isLoading else {
            return
        }

        loadState = .loading
        errorMessage = nil
        successMessage = nil

        do {
            let payload = try await apiClient.fetchUsage(
                settings: connectionSettings,
                timeRange: selectedTimeRange
            )
            rawPayload = payload

            if let store = sqliteStore {
                let payloadToPersist = payload
                let timeRange = selectedTimeRange
                let capturedNow = now()
                let calendar = calendar
                let modelPrices = modelPrices
                let trendGranularity = trendGranularity
                let costCalculationBasis = costCalculationBasis
                snapshot = try await Task.detached(priority: .utility) {
                    let fetchedEvents = UsageAggregator.events(
                        from: payloadToPersist,
                        timeRange: timeRange,
                        now: capturedNow,
                        calendar: calendar
                    )
                    try store.upsert(events: fetchedEvents)
                    try store.saveRawFetch(payload: payloadToPersist, timeRange: timeRange, fetchedAt: capturedNow)
                    let quotaSnapshots = UsageAggregator.credentialQuotaSnapshots(from: fetchedEvents, capturedAt: capturedNow)
                    try store.upsert(quotaSnapshots: quotaSnapshots)
                    return try store.dashboardSnapshot(
                        in: timeRange,
                        prices: modelPrices,
                        basis: costCalculationBasis,
                        now: capturedNow,
                        calendar: calendar,
                        trendGranularity: trendGranularity
                    )
                }.value
                updateDisplaySnapshot()
                writeWidgetData()
            } else {
                rebuildSnapshot()
            }
            lastUpdatedAt = now()
            loadState = .loaded
            successMessage = "用量数据已更新。"
        } catch {
            let message = Self.message(for: error)
            errorMessage = message
            loadState = .failed(message)
        }
    }

    @discardableResult
    func exportUsage() async throws -> Data {
        do {
            let data = try await apiClient.exportUsage(settings: connectionSettings)
            successMessage = "用量数据已导出。"
            errorMessage = nil
            return data
        } catch {
            let message = Self.message(for: error)
            errorMessage = message
            successMessage = nil
            throw error
        }
    }

    @discardableResult
    func importUsage(
        _ data: Data,
        contentType: String = "application/json"
    ) async throws -> UsageImportResult {
        do {
            let result = try await apiClient.importUsage(
                data,
                settings: connectionSettings,
                contentType: contentType
            )
            if let payload = importPayload(from: result, data: data, contentType: contentType) {
                rawPayload = payload
                if let store = sqliteStore {
                    let payloadToPersist = payload
                    let capturedNow = now()
                    let calendar = calendar
                    let modelPrices = modelPrices
                    let trendGranularity = trendGranularity
                    let costCalculationBasis = costCalculationBasis
                    snapshot = try await Task.detached(priority: .utility) {
                        let importedEvents = UsageAggregator.events(
                            from: payloadToPersist,
                            timeRange: .all,
                            now: capturedNow,
                            calendar: calendar
                        )
                        try store.upsert(events: importedEvents)
                        try store.saveRawFetch(payload: payloadToPersist, timeRange: .all, fetchedAt: capturedNow)
                        try store.upsert(quotaSnapshots: UsageAggregator.credentialQuotaSnapshots(from: importedEvents, capturedAt: capturedNow))
                        return try store.dashboardSnapshot(
                            in: .all,
                            prices: modelPrices,
                            basis: costCalculationBasis,
                            now: capturedNow,
                            calendar: calendar,
                            trendGranularity: trendGranularity
                        )
                    }.value
                    updateDisplaySnapshot()
                    writeWidgetData()
                }
            }
            if sqliteStore == nil {
                rebuildSnapshot()
            }
            successMessage = result.message.isEmpty ? "用量数据已导入。" : result.message
            errorMessage = nil
            return result
        } catch {
            let message = Self.message(for: error)
            errorMessage = message
            successMessage = nil
            throw error
        }
    }

    func saveConnectionSettings(_ settings: ConnectionSettings? = nil) throws {
        let settingsToSave = settings ?? connectionSettings
        do {
            try connectionSettingsStore.save(settingsToSave)
            connectionSettings = try connectionSettingsStore.load()
            successMessage = "连接设置已保存。"
            errorMessage = nil
        } catch {
            let message = Self.message(for: error)
            errorMessage = message
            successMessage = nil
            throw error
        }
    }

    func reloadConnectionSettings() {
        do {
            connectionSettings = try connectionSettingsStore.load()
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func clearManagementKey() throws {
        do {
            try connectionSettingsStore.clearManagementKey()
            connectionSettings.managementKey = ""
            successMessage = "管理密钥已清除。"
            errorMessage = nil
        } catch {
            let message = Self.message(for: error)
            errorMessage = message
            successMessage = nil
            throw error
        }
    }

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }

    func clearEventFilters() {
        eventFilters = .empty
    }

    func toggleSensitiveValuesMask() {
        masksSensitiveValues.toggle()
    }

    var costDisplaySettings: UsageCostDisplaySettings {
        UsageCostDisplaySettings(
            displayCurrency: displayCurrency,
            usdToCNYExchangeRate: usdToCNYExchangeRate,
            calculationBasis: costCalculationBasis
        )
    }

    var displayedTotalCost: Double? {
        convertedCost(displaySnapshot.summary.totalCost)
    }

    func setDisplayCurrency(_ currency: DisplayCurrency) {
        displayCurrency = currency
    }

    func toggleDisplayCurrency() {
        displayCurrency = displayCurrency == .usd ? .cny : .usd
    }

    func setUSDToCNYExchangeRate(_ exchangeRate: Double) {
        usdToCNYExchangeRate = UsageCostDisplaySettings.sanitizeExchangeRate(exchangeRate)
    }

    func setCostCalculationBasis(_ basis: CostCalculationBasis) {
        costCalculationBasis = basis
    }

    func setCostDisplaySettings(_ settings: UsageCostDisplaySettings) {
        displayCurrency = settings.displayCurrency
        usdToCNYExchangeRate = settings.usdToCNYExchangeRate
        costCalculationBasis = settings.calculationBasis
    }

    func convertedCost(_ usdValue: Double?) -> Double? {
        costDisplaySettings.convertedCost(fromUSD: usdValue)
    }

    func formattedCost(
        _ usdValue: Double?,
        placeholder: String = "--",
        fractionLength: Int = 4
    ) -> String {
        guard let convertedValue = convertedCost(usdValue) else {
            return placeholder
        }
        return formattedCurrency(convertedValue, fractionLength: fractionLength)
    }

    func formattedPricePerMillion(_ usdPrice: Double, fractionLength: Int = 2) -> String {
        let convertedPrice = convertedCost(usdPrice) ?? 0
        return formattedCurrency(convertedPrice, fractionLength: fractionLength) + " / 1M"
    }

    func makeModelPriceDraft(for model: String) -> ModelPriceDraft {
        if let price = modelPrice(for: model) {
            return ModelPriceDraft(price: price)
        }

        return ModelPriceDraft(model: model)
    }

    func makeModelPriceDraft(from price: ModelPriceSetting) -> ModelPriceDraft {
        ModelPriceDraft(price: price.sanitized)
    }

    func hasUnsavedModelPriceDraft(_ draft: ModelPriceDraft) -> Bool {
        draft.hasUnsavedChanges(comparedTo: modelPrice(for: draft.model))
    }

    func saveModelPriceDraft(_ draft: ModelPriceDraft) {
        upsertModelPrice(draft.sanitizedPrice)
    }

    func displayedSensitiveValue(_ value: String) -> String {
        UsageFormatters.sensitiveIdentifier(value, masked: masksSensitiveValues)
    }

    func displayedSourceTitle(source: String, provider: String) -> String {
        let sourceTitle = displayedSensitiveValue(source)
        let providerTitle = provider.trimmingCharacters(in: .whitespacesAndNewlines)

        if sourceTitle == "--" {
            return providerTitle.isEmpty ? "--" : providerTitle
        }

        if providerTitle.isEmpty {
            return sourceTitle
        }

        return "\(sourceTitle) · \(providerTitle)"
    }

    func filteredEventsExportData(format: UsageExportFormat) throws -> Data {
        try UsageExportService.data(for: sortedEvents, format: format, masked: masksSensitiveValues)
    }

    func suggestedFilteredEventsFilename(format: UsageExportFormat) -> String {
        UsageExportService.suggestedFilename(format: format, now: now())
    }

    func exportFilteredEvents(
        format: UsageExportFormat,
        to url: URL
    ) async throws {
        do {
            let data = try filteredEventsExportData(format: format)
            try await Task.detached(priority: .utility) {
                try data.write(to: url, options: .atomic)
            }.value
            successMessage = "\(filteredEventExportCount) 条请求事件已导出为 \(format.title)。"
            errorMessage = nil
        } catch {
            let message = Self.message(for: error)
            errorMessage = message
            successMessage = nil
            throw error
        }
    }

    func setEventFilter(model: String? = nil, source: String? = nil, authIndex: String? = nil) {
        eventFilters = RequestEventFilters(
            model: model ?? eventFilters.model,
            source: source ?? eventFilters.source,
            authIndex: authIndex ?? eventFilters.authIndex
        )
    }

    func setEndpointSort(_ column: EndpointSort) {
        endpointSort = EndpointSortState(
            column: column,
            direction: toggledDirection(currentColumn: endpointSort.column, selectedColumn: column, currentDirection: endpointSort.direction)
        )
    }

    func setModelSort(_ column: ModelSort) {
        modelSort = ModelSortState(
            column: column,
            direction: toggledDirection(currentColumn: modelSort.column, selectedColumn: column, currentDirection: modelSort.direction)
        )
    }

    func setEventSort(_ column: EventSort) {
        eventSort = EventSortState(
            column: column,
            direction: toggledDirection(currentColumn: eventSort.column, selectedColumn: column, currentDirection: eventSort.direction)
        )
    }

    func setCredentialSort(_ column: CredentialSort) {
        credentialSort = CredentialSortState(
            column: column,
            direction: toggledDirection(currentColumn: credentialSort.column, selectedColumn: column, currentDirection: credentialSort.direction)
        )
    }

    func setModelPriceSort(_ column: ModelPriceSort) {
        modelPriceSort = ModelPriceSortState(
            column: column,
            direction: toggledDirection(currentColumn: modelPriceSort.column, selectedColumn: column, currentDirection: modelPriceSort.direction)
        )
    }

    func isEndpointExpanded(_ endpointID: String) -> Bool {
        expandedEndpointIDs.contains(endpointID)
    }

    func toggleEndpointExpansion(_ endpointID: String) {
        if expandedEndpointIDs.contains(endpointID) {
            expandedEndpointIDs.remove(endpointID)
        } else {
            expandedEndpointIDs.insert(endpointID)
        }
    }

    func collapseAllEndpoints() {
        expandedEndpointIDs.removeAll()
    }

    func expandAllEndpoints() {
        expandedEndpointIDs = Set(snapshot.endpoints.map(\.id))
    }

    func clearRowSelections() {
        selectedEndpointIDs.removeAll()
        selectedModelIDs.removeAll()
        selectedEventIDs.removeAll()
        selectedCredentialIDs.removeAll()
        selectedModelPriceIDs.removeAll()
    }

    func isChartSeriesSelected(_ model: String) -> Bool {
        chartSeriesSelection.contains(model)
    }

    @discardableResult
    func toggleChartSeries(_ model: String) -> Bool {
        if chartSeriesSelection.contains(model) {
            chartSeriesSelection = chartSeriesSelection.removing(model)
            return true
        }

        guard canSelectMoreChartSeries else {
            errorMessage = "最多只能同时选择 \(ChartSeriesSelection.maxSelectedModels) 条模型曲线。"
            return false
        }

        chartSeriesSelection = chartSeriesSelection.adding(model)
        return true
    }

    func setChartSeriesSelection(_ models: Set<String>) {
        chartSeriesSelection = ChartSeriesSelection(selectedModels: models)
    }

    func clearChartSeriesSelection() {
        chartSeriesSelection = ChartSeriesSelection()
    }

    func modelPrice(for model: String) -> ModelPriceSetting? {
        let key = normalizedModelKey(model)
        return modelPrices.first { normalizedModelKey($0.model) == key }
    }

    func upsertModelPrice(_ price: ModelPriceSetting) {
        let sanitized = sanitizedModelPrice(price)
        guard !sanitized.model.isEmpty else {
            return
        }

        let key = normalizedModelKey(sanitized.model)
        var prices = modelPrices.filter { normalizedModelKey($0.model) != key }
        prices.append(sanitized)
        modelPrices = prices.sorted {
            $0.model.localizedStandardCompare($1.model) == .orderedAscending
        }
        successMessage = "模型价格已保存。"
        errorMessage = nil
    }

    func saveModelPrice(
        model: String,
        promptPricePerMillion: Double,
        completionPricePerMillion: Double,
        cachePricePerMillion: Double
    ) {
        upsertModelPrice(
            ModelPriceSetting(
                model: model,
                promptPricePerMillion: promptPricePerMillion,
                completionPricePerMillion: completionPricePerMillion,
                cachePricePerMillion: cachePricePerMillion
            )
        )
    }

    func deleteModelPrice(model: String) {
        let key = normalizedModelKey(model)
        modelPrices.removeAll { normalizedModelKey($0.model) == key }
        selectedModelPriceIDs.remove(model)
        successMessage = "模型价格已删除。"
        errorMessage = nil
    }

    func deleteSelectedModelPrices() {
        guard !selectedModelPriceIDs.isEmpty else {
            return
        }

        let selectedKeys = Set(selectedModelPriceIDs.map(normalizedModelKey))
        modelPrices.removeAll { selectedKeys.contains(normalizedModelKey($0.model)) }
        selectedModelPriceIDs.removeAll()
        successMessage = "选中的模型价格已删除。"
        errorMessage = nil
    }

    func clearModelPrices() {
        modelPrices = []
        selectedModelPriceIDs.removeAll()
        successMessage = "模型价格已清空。"
        errorMessage = nil
    }

    private func saveCostDisplaySettings() {
        preferencesStore.saveCostDisplaySettings(costDisplaySettings)
    }

    private func formattedCurrency(_ value: Double, fractionLength: Int) -> String {
        displayCurrency.symbol + value.formatted(.number.precision(.fractionLength(fractionLength)))
    }

    private func rebuildSnapshot() {
        if let store = sqliteStore {
            do {
                snapshot = try persistedSnapshot(from: store)
                errorMessage = nil
            } catch {
                errorMessage = Self.message(for: error)
                if rawPayload == nil {
                    snapshot = UsageSnapshot(timeRange: selectedTimeRange)
                }
            }
            if rawPayload == nil || errorMessage == nil {
                updateDisplaySnapshot()
                writeWidgetData()
                return
            }
        }

        if let rawPayload {
            snapshot = UsageAggregator.aggregate(
                rawPayload,
                timeRange: selectedTimeRange,
                modelPrices: modelPrices,
                now: now(),
                calendar: calendar,
                trendGranularity: trendGranularity,
                costCalculationBasis: costCalculationBasis
            )
            updateDisplaySnapshot()
            writeWidgetData()
            return
        }

        snapshot = UsageSnapshot(timeRange: selectedTimeRange)
        updateDisplaySnapshot()
    }

    private func persistedSnapshot(from store: UsageSQLiteStore) throws -> UsageSnapshot {
        try store.dashboardSnapshot(
            in: selectedTimeRange,
            prices: modelPrices,
            basis: costCalculationBasis,
            now: now(),
            calendar: calendar,
            trendGranularity: trendGranularity
        )
    }

    private func persist(payload: UsageRawPayload, to store: UsageSQLiteStore, timeRange: UsageTimeRange) throws {
        let importedEvents = UsageAggregator.events(
            from: payload,
            timeRange: timeRange,
            now: now(),
            calendar: calendar
        )
        try store.upsert(events: importedEvents)
        try store.saveRawFetch(payload: payload, timeRange: timeRange, fetchedAt: now())
        try store.upsert(quotaSnapshots: UsageAggregator.credentialQuotaSnapshots(from: importedEvents, capturedAt: now()))
    }

    private func importPayload(from result: UsageImportResult, data: Data, contentType: String) -> UsageRawPayload? {
        let localPayload = localImportPayload(from: data, contentType: contentType)
        guard let responsePayload = result.rawPayload else {
            return localPayload
        }
        if UsageAggregator.events(from: responsePayload, timeRange: .all, now: now(), calendar: calendar).isEmpty,
           let localPayload,
           !UsageAggregator.events(from: localPayload, timeRange: .all, now: now(), calendar: calendar).isEmpty {
            return localPayload
        }
        return responsePayload
    }

    private func localImportPayload(from data: Data, contentType: String) -> UsageRawPayload? {
        guard contentType.localizedCaseInsensitiveContains("json") || contentType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return try? JSONDecoder().decode(UsageRawPayload.self, from: data)
    }

    private func writeWidgetData() {
        let s = snapshot.summary
        let costFmt = formattedCost(s.totalCost, placeholder: "--", fractionLength: 2)
        let avgCostFmt: String
        if let totalCost = s.totalCost, s.totalRequests > 0 {
            avgCostFmt = formattedCost(totalCost / Double(s.totalRequests) * 1_000, placeholder: "--", fractionLength: 2)
        } else {
            avgCostFmt = "--"
        }
        WidgetDataBridge.write(
            snapshot: snapshot,
            costFormatted: costFmt,
            avgCostPerKFormatted: avgCostFmt,
            costBasisTitle: costCalculationBasis.title.uppercased(),
            hasLiveData: hasLoadedData
        )
    }

    private func updateDisplaySnapshot() {
        var nextSnapshot = snapshot
        nextSnapshot.endpoints = sortedEndpoints(from: snapshot.endpoints)
        nextSnapshot.models = sortedModels(from: snapshot.models)
        nextSnapshot.events = sortedEvents(from: filteredEvents(from: snapshot.events))
        nextSnapshot.credentials = sortedCredentials(from: snapshot.credentials)
        nextSnapshot.trends = chartTrendPoints
        displaySnapshot = nextSnapshot
    }

    private func filteredEvents(from events: [RequestEvent]) -> [RequestEvent] {
        events.filter { event in
            let modelMatches = eventFilters.model.isEmpty || event.model == eventFilters.model
            let sourceMatches = eventFilters.source.isEmpty || event.source == eventFilters.source
            let authIndexMatches = eventFilters.authIndex.isEmpty || event.authIndex == eventFilters.authIndex
            return modelMatches && sourceMatches && authIndexMatches
        }
    }

    private func sortedEndpoints(from endpoints: [EndpointUsageStat]) -> [EndpointUsageStat] {
        sorted(endpoints, direction: endpointSort.direction) { lhs, rhs in
            switch endpointSort.column {
            case .endpoint:
                compare(lhs.endpoint, rhs.endpoint)
            case .requests:
                compare(lhs.requests, rhs.requests, tieBreaker: compare(lhs.endpoint, rhs.endpoint))
            case .tokens:
                compare(lhs.totalTokens, rhs.totalTokens, tieBreaker: compare(lhs.endpoint, rhs.endpoint))
            case .cost:
                compare(lhs.cost, rhs.cost, tieBreaker: compare(lhs.endpoint, rhs.endpoint))
            }
        }
    }

    private func sortedModels(from models: [ModelUsageStat]) -> [ModelUsageStat] {
        sorted(models, direction: modelSort.direction) { lhs, rhs in
            switch modelSort.column {
            case .model:
                compare(lhs.model, rhs.model)
            case .requests:
                compare(lhs.requests, rhs.requests, tieBreaker: compare(lhs.model, rhs.model))
            case .tokens:
                compare(lhs.totalTokens, rhs.totalTokens, tieBreaker: compare(lhs.model, rhs.model))
            case .averageLatency:
                compare(lhs.averageLatencyMs, rhs.averageLatencyMs, tieBreaker: compare(lhs.model, rhs.model))
            case .totalLatency:
                compare(lhs.totalLatencyMs, rhs.totalLatencyMs, tieBreaker: compare(lhs.model, rhs.model))
            case .successRate:
                compare(lhs.successRate, rhs.successRate, tieBreaker: compare(lhs.model, rhs.model))
            case .cost:
                compare(lhs.cost, rhs.cost, tieBreaker: compare(lhs.model, rhs.model))
            }
        }
    }

    private func sortedEvents(from events: [RequestEvent]) -> [RequestEvent] {
        sorted(events, direction: eventSort.direction) { lhs, rhs in
            switch eventSort.column {
            case .time:
                compare(lhs.timestamp, rhs.timestamp, tieBreaker: compare(lhs.id, rhs.id))
            case .model:
                compare(lhs.model, rhs.model, tieBreaker: compare(lhs.timestamp, rhs.timestamp))
            case .source:
                compare(lhs.sourceTitle, rhs.sourceTitle, tieBreaker: compare(lhs.timestamp, rhs.timestamp))
            case .authIndex:
                compare(lhs.authIndex, rhs.authIndex, tieBreaker: compare(lhs.timestamp, rhs.timestamp))
            case .result:
                compare(lhs.resultTitle, rhs.resultTitle, tieBreaker: compare(lhs.timestamp, rhs.timestamp))
            case .latency:
                compare(lhs.latencyMs, rhs.latencyMs, tieBreaker: compare(lhs.timestamp, rhs.timestamp))
            case .tokens:
                compare(lhs.totalTokens, rhs.totalTokens, tieBreaker: compare(lhs.timestamp, rhs.timestamp))
            }
        }
    }

    private func sortedCredentials(from credentials: [CredentialUsageStat]) -> [CredentialUsageStat] {
        sorted(credentials, direction: credentialSort.direction) { lhs, rhs in
            switch credentialSort.column {
            case .credential:
                compare(lhs.displayName, rhs.displayName)
            case .provider:
                compare(lhs.sourceTitle, rhs.sourceTitle, tieBreaker: compare(lhs.displayName, rhs.displayName))
            case .requests:
                compare(lhs.requests, rhs.requests, tieBreaker: compare(lhs.displayName, rhs.displayName))
            case .successRate:
                compare(lhs.successRate, rhs.successRate, tieBreaker: compare(lhs.displayName, rhs.displayName))
            case .lastUsed:
                compare(lhs.lastUsedAt, rhs.lastUsedAt, tieBreaker: compare(lhs.displayName, rhs.displayName))
            }
        }
    }

    private func sortedModelPrices(from prices: [ModelPriceSetting]) -> [ModelPriceSetting] {
        sorted(prices, direction: modelPriceSort.direction) { lhs, rhs in
            switch modelPriceSort.column {
            case .model:
                compare(lhs.model, rhs.model)
            case .promptPrice:
                compare(lhs.promptPricePerMillion, rhs.promptPricePerMillion, tieBreaker: compare(lhs.model, rhs.model))
            case .completionPrice:
                compare(lhs.completionPricePerMillion, rhs.completionPricePerMillion, tieBreaker: compare(lhs.model, rhs.model))
            case .cachePrice:
                compare(lhs.cachePricePerMillion, rhs.cachePricePerMillion, tieBreaker: compare(lhs.model, rhs.model))
            }
        }
    }

    private func sorted<T>(
        _ values: [T],
        direction: UsageSortDirection,
        by comparator: (T, T) -> ComparisonResult
    ) -> [T] {
        values.sorted { lhs, rhs in
            let result = comparator(lhs, rhs)
            switch direction {
            case .ascending:
                return result == .orderedAscending
            case .descending:
                return result == .orderedDescending
            }
        }
    }

    private func compare(_ lhs: String, _ rhs: String, tieBreaker: ComparisonResult = .orderedSame) -> ComparisonResult {
        let result = lhs.localizedStandardCompare(rhs)
        return result == .orderedSame ? tieBreaker : result
    }

    private func compare(_ lhs: Int, _ rhs: Int, tieBreaker: ComparisonResult = .orderedSame) -> ComparisonResult {
        compare(Double(lhs), Double(rhs), tieBreaker: tieBreaker)
    }

    private func compare(_ lhs: Double, _ rhs: Double, tieBreaker: ComparisonResult = .orderedSame) -> ComparisonResult {
        if lhs < rhs {
            return .orderedAscending
        }
        if lhs > rhs {
            return .orderedDescending
        }
        return tieBreaker
    }

    private func compare(_ lhs: Date, _ rhs: Date, tieBreaker: ComparisonResult = .orderedSame) -> ComparisonResult {
        if lhs < rhs {
            return .orderedAscending
        }
        if lhs > rhs {
            return .orderedDescending
        }
        return tieBreaker
    }

    private func compare(_ lhs: Double?, _ rhs: Double?, tieBreaker: ComparisonResult = .orderedSame) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return compare(lhs, rhs, tieBreaker: tieBreaker)
        case (nil, nil):
            return tieBreaker
        case (nil, _):
            return .orderedAscending
        case (_, nil):
            return .orderedDescending
        }
    }

    private func compare(_ lhs: Date?, _ rhs: Date?, tieBreaker: ComparisonResult = .orderedSame) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return compare(lhs, rhs, tieBreaker: tieBreaker)
        case (nil, nil):
            return tieBreaker
        case (nil, _):
            return .orderedAscending
        case (_, nil):
            return .orderedDescending
        }
    }

    private func toggledDirection<Column: Equatable>(
        currentColumn: Column,
        selectedColumn: Column,
        currentDirection: UsageSortDirection
    ) -> UsageSortDirection {
        guard currentColumn == selectedColumn else {
            return .descending
        }

        return currentDirection == .descending ? .ascending : .descending
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        Set(
            values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func sanitizedModelPrice(_ price: ModelPriceSetting) -> ModelPriceSetting {
        price.sanitized
    }

    private func normalizedModelKey(_ model: String) -> String {
        model.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

private extension CredentialUsageStat {
    var sourceTitle: String {
        [source, provider]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
