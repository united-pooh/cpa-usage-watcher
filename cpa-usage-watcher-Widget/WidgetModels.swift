import Foundation
import SwiftUI

let widgetAppGroupID = "group.united-pooh.cpa-usage-watcher"
let widgetSnapshotKey = "cpa.widget.snapshot"

struct WidgetSnapshot: Codable {
    var totalRequests: Int = 0
    var successfulRequests: Int = 0
    var failedRequests: Int = 0
    var totalTokens: Int = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cachedTokens: Int = 0
    var reasoningTokens: Int = 0
    var rpm: Double = 0
    var tpm: Double = 0
    var averageLatencyMs: Double = 0
    var hasLiveData: Bool = false
    var costFormatted: String = "--"
    var avgCostPerKFormatted: String = "--"
    var costBasisTitle: String = "SAVED"
    var hasCostData: Bool = false
    var updatedAt: Date = .distantPast

    static let placeholder = WidgetSnapshot(
        totalRequests: 1_240,
        successfulRequests: 1_230,
        failedRequests: 10,
        totalTokens: 41_800,
        inputTokens: 20_000,
        outputTokens: 15_000,
        cachedTokens: 4_600_000,
        reasoningTokens: 0,
        rpm: 5,
        tpm: 99,
        averageLatencyMs: 234,
        hasLiveData: true,
        costFormatted: "$3.11",
        avgCostPerKFormatted: "$37.06",
        costBasisTitle: "SAVED",
        hasCostData: true,
        updatedAt: Date()
    )

    static func load() -> WidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: widgetAppGroupID),
              let data = defaults.data(forKey: widgetSnapshotKey),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return WidgetSnapshot() }
        return snap
    }

    var cacheRatioText: String {
        let total = Double(inputTokens + outputTokens + cachedTokens + reasoningTokens)
        guard total > 0 else { return "0.0%" }
        return String(format: "%.1f%%", Double(cachedTokens) / total * 100)
    }

    var reasoningRatioText: String {
        let total = Double(inputTokens + outputTokens + cachedTokens + reasoningTokens)
        guard total > 0 else { return "0.0%" }
        return String(format: "%.1f%%", Double(reasoningTokens) / total * 100)
    }
}

func wCompact(_ value: Int) -> String {
    if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
    return "\(value)"
}

func wCompact(_ value: Double) -> String {
    wCompact(Int(value.rounded()))
}

enum WidgetTheme {
    static let cream = Color(red: 253 / 255, green: 251 / 255, blue: 248 / 255)
    static let paperDeep = Color(red: 0.937, green: 0.910, blue: 0.843)
    static let ink = Color(red: 0.165, green: 0.149, blue: 0.125)
    static let mutedInk = Color(red: 0.435, green: 0.396, blue: 0.341)
    static let softInk = Color(red: 0.165, green: 0.149, blue: 0.125).opacity(0.42)
    static let orange = Color(red: 1.0, green: 0.478, blue: 0.271)
    static let blue = Color(red: 0.271, green: 0.718, blue: 1.0)
    static let blueDeep = Color(red: 0.122, green: 0.561, blue: 0.851)
    static let blueSoft = Color(red: 0.784, green: 0.910, blue: 0.984)
    static let yellow = Color(red: 1.0, green: 0.824, blue: 0.271)
    static let yellowSoft = Color(red: 1.0, green: 0.937, blue: 0.722)
    static let green = Color(red: 0.180, green: 0.651, blue: 0.416)
    static let greenSoft = Color(red: 0.804, green: 0.940, blue: 0.864)
    static let red = Color(red: 0.898, green: 0.282, blue: 0.302)
    static let purple = Color(red: 0.486, green: 0.337, blue: 0.855)
}
