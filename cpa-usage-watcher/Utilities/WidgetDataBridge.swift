import Foundation
import WidgetKit

enum WidgetDataBridge {
    static let appGroupID = "group.united-pooh.cpa-usage-watcher"
    static let snapshotKey = "cpa.widget.snapshot"

    // Must match WidgetSnapshot in the widget extension (same JSON structure).
    private struct WidgetSnapshotPayload: Codable {
        var totalRequests: Int
        var successfulRequests: Int
        var failedRequests: Int
        var totalTokens: Int
        var inputTokens: Int
        var outputTokens: Int
        var cachedTokens: Int
        var reasoningTokens: Int
        var rpm: Double
        var tpm: Double
        var averageLatencyMs: Double
        var hasLiveData: Bool
        var costFormatted: String
        var avgCostPerKFormatted: String
        var costBasisTitle: String
        var hasCostData: Bool
        var updatedAt: Date
    }

    static func write(
        snapshot: UsageSnapshot,
        costFormatted: String,
        avgCostPerKFormatted: String,
        costBasisTitle: String,
        hasLiveData: Bool
    ) {
        let s = snapshot.summary
        let payload = WidgetSnapshotPayload(
            totalRequests: s.totalRequests,
            successfulRequests: s.successfulRequests,
            failedRequests: s.failedRequests,
            totalTokens: s.totalTokens,
            inputTokens: s.inputTokens,
            outputTokens: s.outputTokens,
            cachedTokens: s.cachedTokens,
            reasoningTokens: s.reasoningTokens,
            rpm: s.rpm,
            tpm: s.tpm,
            averageLatencyMs: s.averageLatencyMs,
            hasLiveData: hasLiveData,
            costFormatted: costFormatted,
            avgCostPerKFormatted: avgCostPerKFormatted,
            costBasisTitle: costBasisTitle,
            hasCostData: s.totalCost != nil,
            updatedAt: Date()
        )
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(payload)
        else { return }
        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
