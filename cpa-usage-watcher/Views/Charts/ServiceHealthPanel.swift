import SwiftUI

struct ServiceHealthPanel: View {
    let snapshot: UsageSnapshot

    var body: some View {
        DashboardPanel(
            title: "服务健康",
            subtitle: "成功率、失败量和平均延迟",
            systemImage: "heart.text.square"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        successRateBlock

                        Divider()
                            .frame(height: 72)

                        healthFactsBlock
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        successRateBlock
                        healthFactsBlock
                    }
                }

                ServiceHealthHeatmap(snapshot: snapshot)
            }
        }
    }

    private var successRateBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(UsageFormatters.percent(snapshot.summary.successRate))
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            ProgressView(value: snapshot.summary.successRate)
                .tint(snapshot.summary.failureRate > 0.08 ? .orange : .green)
                .frame(maxWidth: 220)

            Text("成功 \(UsageFormatters.integer(snapshot.summary.successfulRequests)) · 失败 \(UsageFormatters.integer(snapshot.summary.failedRequests))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var healthFactsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HealthFactRow(
                title: "平均延迟",
                value: UsageFormatters.latencyCompact(snapshot.summary.averageLatencyMs),
                systemImage: "timer"
            )
            HealthFactRow(
                title: "总延迟",
                value: UsageFormatters.latency(snapshot.summary.totalLatencyMs),
                systemImage: "clock"
            )
            HealthFactRow(
                title: "失败率",
                value: UsageFormatters.percent(snapshot.summary.failureRate),
                systemImage: "exclamationmark.triangle"
            )
        }
    }
}

// MARK: - Service Health Heatmap

/// Fixed last-7-days SwiftUI heatmap.
/// Grid: 168 columns (7 days × 24 hours) × 6 rows (10-minute buckets per hour) = 1,008 cells.
/// No Swift Charts axis overhead — pure SwiftUI layout.
private struct ServiceHealthHeatmap: View {
    let snapshot: UsageSnapshot
    private let buckets: [HealthBucket]

    init(snapshot: UsageSnapshot) {
        self.snapshot = snapshot
        self.buckets = UsageAggregator.healthBuckets(
            from: snapshot.events,
            now: snapshot.generatedAt ?? Date(),
            calendar: Calendar.current
        )
    }

    private static let days = 7
    private static let hoursPerDay = 24
    private static let bucketsPerHour = 6
    private static let totalColumns = days * hoursPerDay
    private static let totalRows = bucketsPerHour

    private var overallHealthPercent: Double {
        let total = snapshot.summary.totalRequests
        guard total > 0 else { return 1.0 }
        return Double(snapshot.summary.successfulRequests) / Double(total)
    }

    var body: some View {
        if snapshot.trends.isEmpty && snapshot.events.isEmpty {
            DashboardEmptyStateView(
                title: "暂无健康趋势",
                message: "当前时间范围没有可绘制的请求记录。",
                systemImage: "waveform.path.ecg"
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                heatmapHeader
                heatmapGrid
                heatmapFooter
            }
        }
    }

    // MARK: - Header

    private var heatmapHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("最近 7 天")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(DashboardTheme.mutedInk)

            Spacer(minLength: 8)

            Text("整体健康  ")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardTheme.softInk)

            Text(UsageFormatters.percent(overallHealthPercent))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(healthColor(overallHealthPercent))
        }
    }

    // MARK: - Grid

    /// Fixed cell height so the overall grid height is predictable.
    private static let cellH: CGFloat = 5
    private static let hSpacing: CGFloat = 1.5
    private static let vSpacing: CGFloat = 1.5
    private static let gridHeight: CGFloat = CGFloat(totalRows) * cellH + CGFloat(totalRows - 1) * vSpacing

    private var heatmapGrid: some View {
        GeometryReader { geo in
            let totalCols = Self.totalColumns
            let totalRows = Self.totalRows
            let hSpacing = Self.hSpacing
            let vSpacing = Self.vSpacing
            let cellH = Self.cellH
            let cellW = max(1.5, (geo.size.width - hSpacing * CGFloat(totalCols - 1)) / CGFloat(totalCols))

            Canvas { context, _ in
                for col in 0 ..< totalCols {
                    for row in 0 ..< totalRows {
                        let index = col * totalRows + row
                        guard index < buckets.count else { continue }
                        let bucket = buckets[index]
                        let x = CGFloat(col) * (cellW + hSpacing)
                        let y = CGFloat(row) * (cellH + vSpacing)
                        let rect = CGRect(x: x, y: y, width: cellW, height: cellH)
                        let path = Path(roundedRect: rect, cornerRadius: 1.5)
                        context.fill(path, with: .color(cellColor(bucket)))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.gridHeight)
    }

    // MARK: - Footer

    private var heatmapFooter: some View {
        HStack(spacing: 0) {
            Text("7 天前")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardTheme.softInk)

            Spacer(minLength: 4)

            // Color legend
            HStack(spacing: 4) {
                ForEach(HealthTone.allCases, id: \.self) { tone in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(tone.color)
                            .frame(width: 9, height: 9)
                        Text(tone.label)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(DashboardTheme.softInk)
                    }
                }
            }

            Spacer(minLength: 4)

            Text("最新")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardTheme.softInk)
        }
    }

    private func cellColor(_ bucket: HealthBucket) -> Color {
        switch bucket.status {
        case .noData:
            DashboardTheme.hairline.opacity(0.6)
        case .healthy:
            DashboardTheme.green
        case .warning:
            DashboardTheme.yellow
        case .degraded:
            DashboardTheme.orange
        case .failed:
            DashboardTheme.red
        }
    }

    private func healthColor(_ rate: Double) -> Color {
        switch rate {
        case 0.95...: DashboardTheme.green
        case 0.80...: DashboardTheme.yellow
        default: DashboardTheme.red
        }
    }
}

// MARK: - Health Tone

private enum HealthTone: CaseIterable {
    case perfect
    case good
    case fair
    case poor
    case critical
    case empty

    var color: Color {
        switch self {
        case .perfect: DashboardTheme.green
        case .good: Color(red: 0.35, green: 0.78, blue: 0.52)
        case .fair: DashboardTheme.yellow
        case .poor: DashboardTheme.orange
        case .critical: DashboardTheme.red
        case .empty: DashboardTheme.hairline
        }
    }

    var label: String {
        switch self {
        case .perfect: "100%"
        case .good: "≥95%"
        case .fair: "≥80%"
        case .poor: "≥50%"
        case .critical: "<50%"
        case .empty: ""
        }
    }

    // CaseIterable for legend — exclude .empty
    static var allCases: [HealthTone] {
        [.perfect, .good, .fair, .poor, .critical]
    }
}

// MARK: - Supporting Types

// MARK: - Supporting Views

private struct HealthFactRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
        .font(.caption)
        .frame(minWidth: 190)
    }
}
