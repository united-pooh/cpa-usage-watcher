import Foundation

final class UsagePreferencesStore {
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let timeRangeKey: String
    private let chartSeriesKey: String
    private let trendGranularityKey: String
    private let modelPricesKey: String
    private let maskSensitiveValuesKey: String
    private let costDisplaySettingsKey: String

    init(
        defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        timeRangeKey: String = "usage.dashboard.selectedTimeRange",
        chartSeriesKey: String = "usage.dashboard.chartSeriesSelection",
        trendGranularityKey: String = "usage.dashboard.trendGranularity",
        modelPricesKey: String = "usage.dashboard.modelPrices",
        maskSensitiveValuesKey: String = "usage.dashboard.maskSensitiveValues",
        costDisplaySettingsKey: String = "usage.dashboard.costDisplaySettings"
    ) {
        self.defaults = defaults
        self.encoder = encoder
        self.decoder = decoder
        self.timeRangeKey = timeRangeKey
        self.chartSeriesKey = chartSeriesKey
        self.trendGranularityKey = trendGranularityKey
        self.modelPricesKey = modelPricesKey
        self.maskSensitiveValuesKey = maskSensitiveValuesKey
        self.costDisplaySettingsKey = costDisplaySettingsKey
    }

    func loadSelectedTimeRange() -> UsageTimeRange {
        load(UsageTimeRange.self, forKey: timeRangeKey, default: .defaultSelection)
    }

    func saveSelectedTimeRange(_ timeRange: UsageTimeRange) {
        save(timeRange, forKey: timeRangeKey)
    }

    func loadChartSeriesSelection() -> ChartSeriesSelection {
        load(ChartSeriesSelection.self, forKey: chartSeriesKey, default: ChartSeriesSelection())
    }

    func saveChartSeriesSelection(_ selection: ChartSeriesSelection) {
        save(ChartSeriesSelection(selectedModels: selection.selectedModels), forKey: chartSeriesKey)
    }

    func loadTrendGranularity() -> TrendGranularity {
        load(TrendGranularity.self, forKey: trendGranularityKey, default: .hour)
    }

    func saveTrendGranularity(_ granularity: TrendGranularity) {
        save(granularity, forKey: trendGranularityKey)
    }

    func loadModelPrices() -> [ModelPriceSetting] {
        sanitizeModelPrices(load([ModelPriceSetting].self, forKey: modelPricesKey, default: []))
    }

    func saveModelPrices(_ prices: [ModelPriceSetting]) {
        save(sanitizeModelPrices(prices), forKey: modelPricesKey)
    }

    func loadCostDisplaySettings() -> UsageCostDisplaySettings {
        sanitizeCostDisplaySettings(
            load(UsageCostDisplaySettings.self, forKey: costDisplaySettingsKey, default: .default)
        )
    }

    func saveCostDisplaySettings(_ settings: UsageCostDisplaySettings) {
        save(sanitizeCostDisplaySettings(settings), forKey: costDisplaySettingsKey)
    }

    func loadDisplayCurrency() -> DisplayCurrency {
        loadCostDisplaySettings().displayCurrency
    }

    func saveDisplayCurrency(_ displayCurrency: DisplayCurrency) {
        var settings = loadCostDisplaySettings()
        settings.displayCurrency = displayCurrency
        saveCostDisplaySettings(settings)
    }

    func loadUSDToCNYExchangeRate() -> Double {
        loadCostDisplaySettings().usdToCNYExchangeRate
    }

    func saveUSDToCNYExchangeRate(_ exchangeRate: Double) {
        var settings = loadCostDisplaySettings()
        settings.usdToCNYExchangeRate = UsageCostDisplaySettings.sanitizeExchangeRate(exchangeRate)
        saveCostDisplaySettings(settings)
    }

    func loadCostCalculationBasis() -> CostCalculationBasis {
        loadCostDisplaySettings().calculationBasis
    }

    func saveCostCalculationBasis(_ calculationBasis: CostCalculationBasis) {
        var settings = loadCostDisplaySettings()
        settings.calculationBasis = calculationBasis
        saveCostDisplaySettings(settings)
    }

    func loadMasksSensitiveValues() -> Bool {
        guard defaults.object(forKey: maskSensitiveValuesKey) != nil else {
            return false
        }
        return defaults.bool(forKey: maskSensitiveValuesKey)
    }

    func saveMasksSensitiveValues(_ masksSensitiveValues: Bool) {
        defaults.set(masksSensitiveValues, forKey: maskSensitiveValuesKey)
    }

    func reset() {
        defaults.removeObject(forKey: timeRangeKey)
        defaults.removeObject(forKey: chartSeriesKey)
        defaults.removeObject(forKey: trendGranularityKey)
        defaults.removeObject(forKey: modelPricesKey)
        defaults.removeObject(forKey: maskSensitiveValuesKey)
        defaults.removeObject(forKey: costDisplaySettingsKey)
    }

    private func load<T: Decodable>(_ type: T.Type, forKey key: String, default defaultValue: T) -> T {
        guard let data = defaults.data(forKey: key),
              let value = try? decoder.decode(type, from: data) else {
            return defaultValue
        }
        return value
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? encoder.encode(value) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    private func sanitizeModelPrices(_ prices: [ModelPriceSetting]) -> [ModelPriceSetting] {
        var sanitizedByModel: [String: ModelPriceSetting] = [:]

        for price in prices {
            let model = price.model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else {
                continue
            }

            sanitizedByModel[normalizedModelKey(model)] = ModelPriceSetting(
                model: model,
                promptPricePerMillion: ModelPriceSetting.sanitizePrice(price.promptPricePerMillion),
                completionPricePerMillion: ModelPriceSetting.sanitizePrice(price.completionPricePerMillion),
                cachePricePerMillion: ModelPriceSetting.sanitizePrice(price.cachePricePerMillion)
            )
        }

        return sanitizedByModel.values.sorted {
            $0.model.localizedStandardCompare($1.model) == .orderedAscending
        }
    }

    private func sanitizeCostDisplaySettings(_ settings: UsageCostDisplaySettings) -> UsageCostDisplaySettings {
        UsageCostDisplaySettings(
            displayCurrency: settings.displayCurrency,
            usdToCNYExchangeRate: settings.usdToCNYExchangeRate,
            calculationBasis: settings.calculationBasis
        )
    }

    private func normalizedModelKey(_ model: String) -> String {
        model.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
