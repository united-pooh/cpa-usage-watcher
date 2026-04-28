import SwiftUI

struct MetricRibbonView: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    private var summary: UsageSummary {
        viewModel.displaySnapshot.summary
    }

    private var snapshot: UsageSnapshot {
        viewModel.displaySnapshot
    }

    private var hasUsageActivity: Bool {
        summary.totalRequests > 0
            || summary.totalTokens > 0
            || !snapshot.events.isEmpty
    }

    private let desktopColumns = Array(
        repeating: GridItem(.flexible(minimum: 176), spacing: 18, alignment: .top),
        count: 5
    )

    private let adaptiveColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 18, alignment: .top)
    ]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            LazyVGrid(columns: desktopColumns, spacing: 18) {
                metricCards
            }

            LazyVGrid(columns: adaptiveColumns, spacing: 18) {
                metricCards
            }
        }
    }

    @ViewBuilder
    private var metricCards: some View {
        ReferenceMetricCard(
            title: "總請求數",
            subtitle: "リクエスト総数",
            value: requestValue,
            systemImage: "sparkle",
            tint: DashboardTheme.orange,
            badge: connectionBadge,
            trailingMetric: "RPM  \(requestRPMText)",
            progressSegments: requestProgressSegments
        )

        ReferenceMetricCard(
            title: "總 TOKEN",
            subtitle: "トークン総数",
            value: tokenValue,
            valueSuffix: "tk",
            systemImage: "bolt",
            tint: DashboardTheme.blue,
            badge: connectionBadge,
            trailingMetric: "TPM  \(tokenTPMText)",
            progressSegments: tokenProgressSegments
        )

        ReferenceMetricCard(
            title: "RPM / TPM",
            subtitle: "毎分のレート",
            value: throughputValue,
            valueSuffix: throughputSuffix,
            systemImage: "arrow.clockwise",
            tint: DashboardTheme.blue,
            detailColumns: [
                MetricDetailColumn(label: "平均延遲", value: averageLatencyText),
                MetricDetailColumn(label: "P99", value: p99LatencyText)
            ],
            progressSegments: throughputProgressSegments
        )

        ReferenceMetricCard(
            title: "緩存 / 思考",
            subtitle: "キャッシュ · 思考",
            value: cacheThinkingValue,
            valueSuffix: reasoningValue,
            systemImage: "cylinder.split.1x2",
            tint: DashboardTheme.yellow,
            chips: [
                MetricInfoChip(title: "緩存命中", value: cacheRatioText, tone: .blue),
                MetricInfoChip(title: "思考", value: reasoningRatioText, tone: .yellow)
            ],
            progressSegments: cacheThinkingProgressSegments
        )

        ReferenceMetricCard(
            title: "總花費",
            subtitle: "合計コスト",
            value: costValue,
            systemImage: "yensign",
            tint: DashboardTheme.orange,
            badge: costBasisBadge,
            trailingMetric: "每千次\n\(averageCostPerThousandRequests)",
            progressSegments: costProgressSegments
        )
    }

    private var requestValue: String {
        UsageFormatters.requestCount(summary.totalRequests)
    }

    private var requestRPMText: String {
        UsageFormatters.integer(Int(summary.rpm.rounded()))
    }

    private var tokenValue: String {
        UsageFormatters.compactNumber(summary.totalTokens)
    }

    private var tokenTPMText: String {
        UsageFormatters.compactNumber(summary.tpm)
    }

    private var throughputValue: String {
        UsageFormatters.integer(Int(summary.rpm.rounded()))
    }

    private var throughputSuffix: String {
        "/min · \(UsageFormatters.compactNumber(summary.tpm)) /"
    }

    private var averageLatencyText: String {
        return UsageFormatters.latencyCompact(summary.averageLatencyMs).replacingOccurrences(of: "ms", with: "\nms")
    }

    private var p99LatencyText: String {
        UsageFormatters.latencyCompact(p99LatencyMs)
    }

    private var cacheThinkingValue: String {
        UsageFormatters.compactNumber(summary.cachedTokens)
    }

    private var reasoningValue: String {
        "+\(UsageFormatters.compactNumber(summary.reasoningTokens))"
    }

    private var cacheRatioText: String {
        UsageFormatters.percent(cacheRatio)
    }

    private var reasoningRatioText: String {
        UsageFormatters.percent(reasoningRatio)
    }

    private var costValue: String {
        if let totalCost = summary.totalCost {
            return viewModel.formattedCost(totalCost, placeholder: "未配置", fractionLength: 2)
        }

        if !hasUsageActivity {
            return viewModel.formattedCost(0, placeholder: "未配置", fractionLength: 2)
        }

        return "未配置"
    }

    private var averageTokensPerRequestValue: Double {
        guard summary.totalRequests > 0 else {
            return 0
        }
        return Double(summary.totalTokens) / Double(summary.totalRequests)
    }

    private var averageCostPerThousandRequests: String {
        guard summary.totalRequests > 0, let totalCost = summary.totalCost else {
            return hasUsageActivity ? "未配置" : viewModel.formattedCost(0, placeholder: "未配置", fractionLength: 2)
        }
        return viewModel.formattedCost(totalCost / Double(summary.totalRequests) * 1_000, placeholder: "未配置", fractionLength: 2)
    }

    private var requestProgressSegments: [MetricProgressSegment] {
        return [
            MetricProgressSegment(Double(summary.successfulRequests), color: DashboardTheme.green),
            MetricProgressSegment(Double(summary.failedRequests), color: DashboardTheme.red)
        ]
    }

    private var tokenProgressSegments: [MetricProgressSegment] {
        return [
            MetricProgressSegment(Double(summary.inputTokens), color: DashboardTheme.orange),
            MetricProgressSegment(Double(summary.outputTokens), color: DashboardTheme.blue),
            MetricProgressSegment(Double(summary.cachedTokens), color: DashboardTheme.yellow),
            MetricProgressSegment(Double(summary.reasoningTokens), color: DashboardTheme.purple)
        ]
    }

    private var throughputProgressSegments: [MetricProgressSegment] {
        return [
            MetricProgressSegment(throughputLoad.requests, color: DashboardTheme.blue),
            MetricProgressSegment(throughputLoad.tokens, color: DashboardTheme.yellow)
        ]
    }

    private var cacheThinkingProgressSegments: [MetricProgressSegment] {
        let ordinaryTokens = summary.inputTokens + summary.outputTokens
        return [
            MetricProgressSegment(Double(summary.cachedTokens), color: DashboardTheme.blue),
            MetricProgressSegment(Double(summary.reasoningTokens), color: DashboardTheme.yellow),
            MetricProgressSegment(Double(ordinaryTokens), color: DashboardTheme.paperDeep)
        ]
    }

    private var costProgressSegments: [MetricProgressSegment] {
        let colors = [DashboardTheme.orange, DashboardTheme.purple, DashboardTheme.green, DashboardTheme.blue]
        let costs = snapshot.models
            .compactMap(\.cost)
            .filter { $0 > 0 }
            .sorted(by: >)

        if !costs.isEmpty {
            return costs.prefix(colors.count).enumerated().map { index, cost in
                MetricProgressSegment(cost, color: colors[index])
            }
        }

        if let totalCost = summary.totalCost, totalCost > 0 {
            return [MetricProgressSegment(totalCost, color: DashboardTheme.orange)]
        }

        return []
    }

    private var connectionBadge: MetricBadge {
        MetricBadge(
            title: viewModel.hasLoadedData ? "LIVE" : "待刷新",
            tone: viewModel.hasLoadedData ? .green : .neutral
        )
    }

    private var costBasisBadge: MetricBadge {
        MetricBadge(
            title: viewModel.costCalculationBasis.title.uppercased(),
            tone: .neutral
        )
    }

    private var throughputLoad: (requests: Double, tokens: Double) {
        let groupedByBucket = Dictionary(grouping: snapshot.trends, by: \.bucket)
        guard !groupedByBucket.isEmpty else {
            return (
                requests: normalizedThroughput(summary.rpm),
                tokens: normalizedThroughput(summary.tpm / max(averageTokensPerRequestValue, 1))
            )
        }

        let bucketTotals = groupedByBucket.map { bucket, points in
            (
                bucket: bucket,
                requests: points.reduce(0) { $0 + $1.requests },
                tokens: points.reduce(0) { $0 + $1.tokens }
            )
        }
        guard let latest = bucketTotals.max(by: { $0.bucket < $1.bucket }) else {
            return (0, 0)
        }

        let peakRequests = bucketTotals.map(\.requests).max() ?? 0
        let peakTokens = bucketTotals.map(\.tokens).max() ?? 0
        return (
            requests: peakRequests > 0 ? Double(latest.requests) / Double(peakRequests) : 0,
            tokens: peakTokens > 0 ? Double(latest.tokens) / Double(peakTokens) : 0
        )
    }

    private var cacheRatio: Double {
        guard tokenCompositionTotal > 0 else {
            return 0
        }
        return Double(summary.cachedTokens) / Double(tokenCompositionTotal)
    }

    private var reasoningRatio: Double {
        guard tokenCompositionTotal > 0 else {
            return 0
        }
        return Double(summary.reasoningTokens) / Double(tokenCompositionTotal)
    }

    private var tokenCompositionTotal: Int {
        summary.inputTokens + summary.outputTokens + summary.cachedTokens + summary.reasoningTokens
    }

    private var p99LatencyMs: Double {
        let latencies = snapshot.events
            .map(\.latencyMs)
            .filter { $0.isFinite && $0 > 0 }
            .sorted()
        guard !latencies.isEmpty else {
            return summary.averageLatencyMs
        }
        let index = min(latencies.count - 1, max(0, Int(ceil(Double(latencies.count) * 0.99)) - 1))
        return latencies[index]
    }

    private func normalizedThroughput(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else {
            return 0
        }
        return min(1, log1p(value) / log1p(max(value, 1)))
    }
}

private struct ReferenceMetricCard: View {
    let title: String
    let subtitle: String
    let value: String
    var valueSuffix: String = ""
    let systemImage: String
    let tint: Color
    var badge: MetricBadge?
    var trailingMetric: String?
    var detailColumns: [MetricDetailColumn] = []
    var chips: [MetricInfoChip] = []
    var progressSegments: [MetricProgressSegment] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(DashboardTheme.softInk)
                    .tracking(3)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DashboardTheme.softInk)
                    .lineLimit(1)
            }

            HStack(alignment: .lastTextBaseline, spacing: 7) {
                Text(value)
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(DashboardTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.42)

                if !valueSuffix.isEmpty {
                    Text(valueSuffix)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(DashboardTheme.mutedInk.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                }
            }

            contentRow

            Spacer(minLength: 0)

            ReferenceMetricProgressBar(segments: progressSegments, fallbackTint: tint)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 226, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DashboardTheme.cardRadius, style: .continuous)
                .fill(DashboardTheme.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.cardRadius, style: .continuous)
                .stroke(DashboardTheme.hairline, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 88, height: 88)
                    .offset(x: 24, y: -26)

                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DashboardTheme.mutedInk.opacity(0.78))
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DashboardTheme.paper.opacity(0.72))
                    )
                    .offset(x: -14, y: 18)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private var contentRow: some View {
        if !detailColumns.isEmpty {
            HStack(alignment: .top, spacing: 18) {
                ForEach(detailColumns) { column in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(column.label)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(DashboardTheme.mutedInk)
                            .lineLimit(1)

                        Text(column.value)
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                            .foregroundStyle(DashboardTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else if !chips.isEmpty {
            HStack(spacing: 12) {
                ForEach(chips) { chip in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(chip.title)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        Text(chip.value)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(chip.foreground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(minWidth: 66, alignment: .leading)
                    .background(
                        Capsule(style: .continuous)
                            .fill(chip.background)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(chip.foreground.opacity(0.18), lineWidth: 1)
                    )
                }
            }
        } else {
            HStack(alignment: .center, spacing: 14) {
                if let badge {
                    Text(badge.title)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(badge.foreground)
                        .lineLimit(2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(badge.background)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(badge.foreground.opacity(0.18), lineWidth: 1)
                        )
                }

                if let trailingMetric {
                    Text(trailingMetric)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(DashboardTheme.mutedInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct MetricBadge {
    let title: String
    let tone: Tone

    enum Tone {
        case green
        case neutral
    }

    var foreground: Color {
        switch tone {
        case .green:
            DashboardTheme.green
        case .neutral:
            DashboardTheme.mutedInk
        }
    }

    var background: Color {
        switch tone {
        case .green:
            Color(red: 0.804, green: 0.940, blue: 0.864)
        case .neutral:
            DashboardTheme.paper
        }
    }
}

private struct MetricDetailColumn: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

private struct MetricInfoChip: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let tone: Tone

    enum Tone {
        case blue
        case yellow
    }

    var foreground: Color {
        switch tone {
        case .blue:
            DashboardTheme.blueDeep
        case .yellow:
            Color(red: 0.528, green: 0.374, blue: 0.030)
        }
    }

    var background: Color {
        switch tone {
        case .blue:
            DashboardTheme.blueSoft
        case .yellow:
            DashboardTheme.yellowSoft
        }
    }
}

private struct ReferenceMetricProgressBar: View {
    let segments: [MetricProgressSegment]
    let fallbackTint: Color

    private var activeSegments: [MetricProgressSegment] {
        segments.filter { $0.value.isFinite && $0.value > 0 }
    }

    private var total: Double {
        activeSegments.reduce(0) { $0 + $1.value }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(DashboardTheme.paperDeep.opacity(0.82))

                if total > 0 {
                    HStack(spacing: 2) {
                        ForEach(Array(activeSegments.enumerated()), id: \.offset) { _, segment in
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .fill(segment.color)
                                .frame(width: max(5, proxy.size.width * segment.value / total))
                        }
                    }
                    .clipShape(Capsule(style: .continuous))
                } else {
                    Capsule(style: .continuous)
                        .fill(fallbackTint.opacity(0.26))
                        .frame(width: 18)
                }
            }
        }
        .frame(height: 6)
    }
}
