import Charts
import SwiftUI

struct UsageTrendChartsView: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                trendMagazinePanel
                    .frame(minWidth: 520, maxWidth: .infinity)
                distributionMagazinePanel
                    .frame(width: 420)
            }

            VStack(alignment: .leading, spacing: 16) {
                trendMagazinePanel
                distributionMagazinePanel
            }
        }
    }

    private var trendMagazinePanel: some View {
        DashboardPanel(
            title: "請求 · Token · 花費 趨勢",
            subtitle: "時系列",
            systemImage: nil,
            accessory: {
                TrendLegend()
            }
        ) {
            if normalizedTrendPoints.isEmpty {
                DashboardEmptyStateView(
                    title: "暂无趋势",
                    message: "当前范围没有请求记录。",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                .frame(height: 300)
            } else {
                Chart(normalizedTrendPoints) { point in
                    AreaMark(
                        x: .value("時間", point.bucket),
                        y: .value("指標", point.value)
                    )
                    .foregroundStyle(by: .value("系列", point.series))
                    .opacity(0.10)

                    LineMark(
                        x: .value("時間", point.bucket),
                        y: .value("指標", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(by: .value("系列", point.series))
                    .lineStyle(.init(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                }
                .chartForegroundStyleScale([
                    "請求數": DashboardTheme.orange,
                    "Token": DashboardTheme.blue,
                    "花費": DashboardTheme.yellow
                ])
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5))
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        AxisGridLine()
                            .foregroundStyle(DashboardTheme.hairline)
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text(intValue == 100 ? "peak" : "\(intValue)")
                                    .font(.caption2)
                                    .foregroundStyle(DashboardTheme.softInk)
                            }
                        }
                    }
                }
                .frame(height: 300)
            }
        }
    }

    private var distributionMagazinePanel: some View {
        DashboardPanel(
            title: "Token 類型分布",
            subtitle: "トークン種別",
            systemImage: nil
        ) {
            if tokenDistributionSlices.isEmpty {
                DashboardEmptyStateView(
                    title: "暂无 Token 类型数据",
                    message: "当前范围没有可汇总的 Token 记录。",
                    systemImage: "chart.pie"
                )
                .frame(height: 300)
            } else {
                HStack(alignment: .center, spacing: 24) {
                    ZStack {
                        Chart(tokenDistributionSlices) { slice in
                            SectorMark(
                                angle: .value("Token", slice.value),
                                innerRadius: .ratio(0.60),
                                angularInset: 2.0
                            )
                            .foregroundStyle(slice.color)
                        }
                        .frame(width: 176, height: 176)

                        VStack(spacing: 1) {
                            Text(UsageFormatters.compactNumber(viewModel.displaySnapshot.summary.totalTokens))
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundStyle(DashboardTheme.ink)
                            Text("TOTAL")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(DashboardTheme.softInk)
                                .tracking(2)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(tokenDistributionSlices) { slice in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(slice.color)
                                    .frame(width: 11, height: 11)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(slice.title)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    Text(slice.subtitle)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(DashboardTheme.softInk)
                                }
                                Spacer(minLength: 6)
                                Text(UsageFormatters.compactNumber(slice.value))
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                Text(UsageFormatters.percent(slice.share))
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(DashboardTheme.softInk)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 300, alignment: .center)
            }
        }
    }

    private var normalizedTrendPoints: [NormalizedTrendPoint] {
        let buckets = Dictionary(grouping: trendPoints, by: \.bucket)
            .map { bucket, points in
                TrendBucketAggregate(
                    bucket: bucket,
                    requests: points.reduce(0) { $0 + $1.requests },
                    tokens: points.reduce(0) { $0 + $1.tokens },
                    cost: points.reduce(0) { $0 + ($1.cost ?? 0) }
                )
            }
            .sorted { $0.bucket < $1.bucket }

        let maxRequests = max(1, buckets.map(\.requests).max() ?? 1)
        let maxTokens = max(1, buckets.map(\.tokens).max() ?? 1)
        let maxCost = max(0.0001, buckets.map(\.cost).max() ?? 0)

        return buckets.flatMap { bucket in
            [
                NormalizedTrendPoint(
                    bucket: bucket.bucket,
                    series: "請求數",
                    value: Double(bucket.requests) / Double(maxRequests) * 100
                ),
                NormalizedTrendPoint(
                    bucket: bucket.bucket,
                    series: "Token",
                    value: Double(bucket.tokens) / Double(maxTokens) * 100
                ),
                NormalizedTrendPoint(
                    bucket: bucket.bucket,
                    series: "花費",
                    value: bucket.cost / maxCost * 100
                )
            ]
        }
    }

    private var tokenDistributionSlices: [TokenDistributionSlice] {
        let summary = viewModel.displaySnapshot.summary
        let total = max(1, summary.totalTokens)
        return [
            TokenDistributionSlice(title: "輸入 Input", subtitle: "入力", value: summary.inputTokens, color: DashboardTheme.orange, total: total),
            TokenDistributionSlice(title: "輸出 Output", subtitle: "出力", value: summary.outputTokens, color: DashboardTheme.blue, total: total),
            TokenDistributionSlice(title: "緩存 Cached", subtitle: "キャッシュ", value: summary.cachedTokens, color: DashboardTheme.yellow, total: total),
            TokenDistributionSlice(title: "思考 Thinking", subtitle: "思考", value: summary.reasoningTokens, color: DashboardTheme.purple, total: total)
        ]
        .filter { $0.value > 0 }
    }

    private var trendPoints: [UsageTrendPoint] {
        viewModel.chartTrendPoints
    }
}

private struct TrendLegend: View {
    private let items = [
        TrendLegendItem(title: "請求數", color: DashboardTheme.orange),
        TrendLegendItem(title: "Token", color: DashboardTheme.blue),
        TrendLegendItem(title: "花費", color: DashboardTheme.yellow)
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(item.color)
                        .frame(width: 8, height: 8)
                    Text(item.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(DashboardTheme.mutedInk)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(DashboardTheme.paper.opacity(0.72))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(DashboardTheme.hairline, lineWidth: 1)
                )
            }
        }
    }
}

private struct TrendLegendItem: Identifiable {
    var id: String { title }
    let title: String
    let color: Color
}

private struct TrendBucketAggregate {
    let bucket: Date
    let requests: Int
    let tokens: Int
    let cost: Double
}

private struct NormalizedTrendPoint: Identifiable {
    var id: String { "\(bucket.timeIntervalSince1970)-\(series)" }
    let bucket: Date
    let series: String
    let value: Double
}

private struct TokenDistributionSlice: Identifiable {
    var id: String { title }
    let title: String
    let subtitle: String
    let value: Int
    let color: Color
    let total: Int

    var share: Double {
        Double(value) / Double(total)
    }
}
