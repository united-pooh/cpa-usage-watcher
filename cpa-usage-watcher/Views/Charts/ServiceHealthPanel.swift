import Charts
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

                if healthBuckets.isEmpty {
                    DashboardEmptyStateView(
                        title: "暂无健康趋势",
                        message: "当前时间范围没有可绘制的请求记录。",
                        systemImage: "waveform.path.ecg"
                    )
                } else {
                    Chart(healthBuckets) { bucket in
                        BarMark(
                            x: .value("时间", bucket.bucket),
                            y: .value("请求", bucket.successfulRequests)
                        )
                        .foregroundStyle(by: .value("结果", "成功"))

                        BarMark(
                            x: .value("时间", bucket.bucket),
                            y: .value("请求", bucket.failedRequests)
                        )
                        .foregroundStyle(by: .value("结果", "失败"))
                    }
                    .chartForegroundStyleScale([
                        "成功": Color.green,
                        "失败": Color.red
                    ])
                    .chartLegend(position: .bottom, alignment: .leading)
                    .frame(height: 190)
                }
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

    private var healthBuckets: [HealthBucket] {
        let grouped = Dictionary(grouping: snapshot.trends, by: \.bucket)
        return grouped.map { bucket, points in
            return HealthBucket(
                bucket: bucket,
                successfulRequests: points.reduce(0) { $0 + $1.successfulRequests },
                failedRequests: points.reduce(0) { $0 + $1.failedRequests }
            )
        }
        .sorted { $0.bucket < $1.bucket }
    }
}

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

private struct HealthBucket: Identifiable {
    var id: Date { bucket }
    let bucket: Date
    let successfulRequests: Int
    let failedRequests: Int
}
