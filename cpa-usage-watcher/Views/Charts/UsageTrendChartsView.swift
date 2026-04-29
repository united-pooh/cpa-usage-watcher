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
                TrendChartWithHover(points: normalizedTrendPoints, buckets: trendBuckets)
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

    // MARK: - Derived Data

    private var normalizedTrendPoints: [NormalizedTrendPoint] {
        trendBuckets.flatMap { bucket in
            [
                NormalizedTrendPoint(
                    bucket: bucket.bucket,
                    series: "請求數",
                    value: bucket.normalizedRequests
                ),
                NormalizedTrendPoint(
                    bucket: bucket.bucket,
                    series: "Token",
                    value: bucket.normalizedTokens
                ),
                NormalizedTrendPoint(
                    bucket: bucket.bucket,
                    series: "花費",
                    value: bucket.normalizedCost
                )
            ]
        }
    }

    private var trendBuckets: [TrendBucketAggregate] {
        let rawBuckets = Dictionary(grouping: trendPoints, by: \.bucket)
            .map { bucket, points in
                TrendBucketAggregate(
                    bucket: bucket,
                    requests: points.reduce(0) { $0 + $1.requests },
                    tokens: points.reduce(0) { $0 + $1.tokens },
                    cost: points.reduce(0) { $0 + ($1.cost ?? 0) },
                    normalizedRequests: 0,
                    normalizedTokens: 0,
                    normalizedCost: 0
                )
            }
            .sorted { $0.bucket < $1.bucket }

        let maxRequests = max(1, rawBuckets.map(\.requests).max() ?? 1)
        let maxTokens = max(1, rawBuckets.map(\.tokens).max() ?? 1)
        let maxCost = max(0.0001, rawBuckets.map(\.cost).max() ?? 0)

        return rawBuckets.map { b in
            TrendBucketAggregate(
                bucket: b.bucket,
                requests: b.requests,
                tokens: b.tokens,
                cost: b.cost,
                normalizedRequests: Double(b.requests) / Double(maxRequests) * 100,
                normalizedTokens: Double(b.tokens) / Double(maxTokens) * 100,
                normalizedCost: b.cost / maxCost * 100
            )
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

// MARK: - Trend Chart with Hover

private struct TrendChartWithHover: View {
    let points: [NormalizedTrendPoint]
    let buckets: [TrendBucketAggregate]

    @State private var hoverPoint: TrendHoverState? = nil

    private let seriesColors: [String: Color] = [
        "請求數": DashboardTheme.orange,
        "Token": DashboardTheme.blue,
        "花費": DashboardTheme.yellow
    ]

    var body: some View {
        Chart(points) { point in
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
            .interpolationMethod(.linear)
            .foregroundStyle(by: .value("系列", point.series))
            .lineStyle(.init(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
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
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            updateHover(at: location, proxy: proxy, geo: geo)
                        case .ended:
                            hoverPoint = nil
                        }
                    }

                if let hover = hoverPoint {
                    crosshairOverlay(hover: hover, proxy: proxy, geo: geo)
                }
            }
        }
    }

    // MARK: - Hover Interaction

    private func updateHover(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        let origin = geo[proxy.plotAreaFrame].origin
        let relX = location.x - origin.x
        let relY = location.y - origin.y

        guard relX >= 0, relY >= 0,
              relX <= proxy.plotAreaSize.width,
              relY <= proxy.plotAreaSize.height else {
            hoverPoint = nil
            return
        }

        guard let xDate: Date = proxy.value(atX: relX) else {
            hoverPoint = nil
            return
        }

        guard let nearest = nearestBucket(to: xDate) else {
            hoverPoint = nil
            return
        }

        guard let yValue: Double = proxy.value(atY: relY) else {
            hoverPoint = nil
            return
        }

        // Find nearest series by y-distance
        let seriesValues: [(String, Double)] = [
            ("請求數", nearest.normalizedRequests),
            ("Token", nearest.normalizedTokens),
            ("花費", nearest.normalizedCost)
        ]
        let nearestSeries = seriesValues.min(by: { abs($0.1 - yValue) < abs($1.1 - yValue) })?.0 ?? "請求數"

        hoverPoint = TrendHoverState(
            bucket: nearest,
            nearestSeries: nearestSeries,
            screenX: (proxy.position(forX: nearest.bucket) ?? relX) + geo[proxy.plotAreaFrame].origin.x,
            screenY: (proxy.position(forY: seriesValues.first(where: { $0.0 == nearestSeries })?.1 ?? 50) ?? relY) + geo[proxy.plotAreaFrame].origin.y,
            plotOrigin: geo[proxy.plotAreaFrame].origin,
            plotSize: proxy.plotAreaSize
        )
    }

    private func nearestBucket(to date: Date) -> TrendBucketAggregate? {
        buckets.min(by: { abs($0.bucket.timeIntervalSince(date)) < abs($1.bucket.timeIntervalSince(date)) })
    }

    // MARK: - Crosshair Drawing

    @ViewBuilder
    private func crosshairOverlay(hover: TrendHoverState, proxy _: ChartProxy, geo _: GeometryProxy) -> some View {
        let plotOrigin = hover.plotOrigin
        let plotSize = hover.plotSize
        let lineColor = seriesColors[hover.nearestSeries] ?? DashboardTheme.blue

        ZStack(alignment: .topLeading) {
            // Vertical dashed line
            Path { path in
                path.move(to: CGPoint(x: hover.screenX, y: plotOrigin.y))
                path.addLine(to: CGPoint(x: hover.screenX, y: plotOrigin.y + plotSize.height))
            }
            .stroke(
                lineColor.opacity(0.55),
                style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
            )

            // Horizontal dashed line
            Path { path in
                path.move(to: CGPoint(x: plotOrigin.x, y: hover.screenY))
                path.addLine(to: CGPoint(x: plotOrigin.x + plotSize.width, y: hover.screenY))
            }
            .stroke(
                lineColor.opacity(0.35),
                style: StrokeStyle(lineWidth: 1.0, dash: [3, 4])
            )

            // Point indicator
            Circle()
                .fill(Color.white)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(lineColor, lineWidth: 2)
                )
                .position(x: hover.screenX, y: hover.screenY)

            // Tooltip
            tooltipView(hover: hover)
                .position(
                    x: tooltipX(hoverX: hover.screenX, plotOrigin: plotOrigin, plotSize: plotSize),
                    y: tooltipY(hoverY: hover.screenY, plotOrigin: plotOrigin, plotSize: plotSize)
                )
        }
    }

    private func tooltipX(hoverX: CGFloat, plotOrigin: CGPoint, plotSize: CGSize) -> CGFloat {
        let tooltipWidth: CGFloat = 188
        let offset: CGFloat = 14
        let rightEdge = plotOrigin.x + plotSize.width
        if hoverX + offset + tooltipWidth > rightEdge {
            return hoverX - offset - tooltipWidth / 2
        }
        return hoverX + offset + tooltipWidth / 2
    }

    private func tooltipY(hoverY: CGFloat, plotOrigin: CGPoint, plotSize: CGSize) -> CGFloat {
        let tooltipHeight: CGFloat = 90
        let topEdge = plotOrigin.y
        let bottomEdge = plotOrigin.y + plotSize.height
        let clamped = min(max(hoverY, topEdge + tooltipHeight / 2), bottomEdge - tooltipHeight / 2)
        return clamped
    }

    @ViewBuilder
    private func tooltipView(hover: TrendHoverState) -> some View {
        let b = hover.bucket
        VStack(alignment: .leading, spacing: 5) {
            Text(bucketDateLabel(b.bucket))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(DashboardTheme.mutedInk)

            Divider()
                .background(DashboardTheme.hairline)

            tooltipRow(label: "請求數", value: UsageFormatters.integer(b.requests), color: DashboardTheme.orange, active: hover.nearestSeries == "請求數")
            tooltipRow(label: "Token", value: UsageFormatters.compactNumber(b.tokens), color: DashboardTheme.blue, active: hover.nearestSeries == "Token")
            tooltipRow(label: "花費", value: b.cost > 0 ? "$\(String(format: "%.4f", b.cost))" : "--", color: DashboardTheme.yellow, active: hover.nearestSeries == "花費")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 188)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DashboardTheme.panelRaised)
                .shadow(color: DashboardTheme.shadow, radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DashboardTheme.hairline, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func tooltipRow(label: String, value: String, color: Color, active: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: active ? 7 : 5, height: active ? 7 : 5)
            Text(label)
                .font(.system(size: 11, weight: active ? .semibold : .regular, design: .rounded))
                .foregroundStyle(active ? DashboardTheme.ink : DashboardTheme.softInk)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11, weight: active ? .bold : .medium, design: .monospaced))
                .foregroundStyle(active ? color : DashboardTheme.mutedInk)
        }
    }

    private func bucketDateLabel(_ date: Date) -> String {
        let dateStr = date.formatted(date: .abbreviated, time: .omitted)
        let timeStr = date.formatted(date: .omitted, time: .shortened)
        return "\(dateStr)  \(timeStr)"
    }
}

// MARK: - Trend Legend

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

// MARK: - Private Models

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
    let normalizedRequests: Double
    let normalizedTokens: Double
    let normalizedCost: Double
}

private struct NormalizedTrendPoint: Identifiable {
    var id: String { "\(bucket.timeIntervalSince1970)-\(series)" }
    let bucket: Date
    let series: String
    let value: Double
}

private struct TrendHoverState {
    let bucket: TrendBucketAggregate
    let nearestSeries: String
    let screenX: CGFloat
    let screenY: CGFloat
    let plotOrigin: CGPoint
    let plotSize: CGSize
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
