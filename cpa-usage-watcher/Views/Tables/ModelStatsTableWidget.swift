import SwiftUI

struct ModelStatsTableWidget: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if viewModel.sortedModels.isEmpty {
                ModelStatsEmptyState()
            } else {
                VStack(spacing: 0) {
                    ModelStatsColumnHeader(viewModel: viewModel)
                    ForEach(Array(viewModel.sortedModels.prefix(5).enumerated()), id: \.element.id) { index, stat in
                    ModelStatsDenseRow(
                        stat: stat,
                        shareText: modelShareText(for: stat),
                        rowIndex: index,
                        tint: DashboardTheme.accent(index + 1)
                    )
                    }
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DashboardTheme.hairline, lineWidth: 1)
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("模型統計")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(DashboardTheme.ink)
                Text("モデル別")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(DashboardTheme.softInk)
            }

            Spacer()

            Text("\(UsageFormatters.integer(viewModel.sortedModels.count)) 個模型")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardTheme.softInk)
        }
    }

    private func modelShareText(for stat: ModelUsageStat) -> String {
        let totalRequests = viewModel.displaySnapshot.summary.totalRequests
        guard totalRequests > 0 else {
            return "0.0%"
        }
        return UsageFormatters.percent(Double(stat.requests) / Double(totalRequests))
    }
}

private struct ModelStatsSortControls: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        HStack(spacing: 8) {
            Picker("排序", selection: columnBinding) {
                ForEach(viewModel.modelSortOptions) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 132)

            Picker("方向", selection: directionBinding) {
                ForEach(UsageSortDirection.allCases) { direction in
                    Text(direction.title).tag(direction)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 116)
        }
    }

    private var columnBinding: Binding<ModelSort> {
        Binding {
            viewModel.modelSort.column
        } set: { column in
            viewModel.modelSort = ModelSortState(column: column, direction: viewModel.modelSort.direction)
        }
    }

    private var directionBinding: Binding<UsageSortDirection> {
        Binding {
            viewModel.modelSort.direction
        } set: { direction in
            viewModel.modelSort = ModelSortState(column: viewModel.modelSort.column, direction: direction)
        }
    }
}

private struct ModelStatsNumericCell: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct ModelStatsColumnHeader: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        HStack(spacing: 0) {
            sortButton(.model, title: "模型")
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            sortButton(.requests, title: "请求次数")
                .frame(width: 100, alignment: .trailing)
            sortButton(.tokens, title: "Token")
                .frame(width: 120, alignment: .trailing)
            sortButton(.averageLatency, title: "平均延迟")
                .frame(width: 100, alignment: .trailing)
            sortButton(.totalLatency, title: "总延迟")
                .frame(width: 110, alignment: .trailing)
            sortButton(.successRate, title: "成功率")
                .frame(width: 110, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .black, design: .rounded))
        .foregroundStyle(DashboardTheme.mutedInk.opacity(0.75))
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(DashboardTheme.paperDeep.opacity(0.62))
    }

    private func sortButton(_ column: ModelSort, title: String) -> some View {
        Button {
            viewModel.setModelSort(column)
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if viewModel.modelSort.column == column {
                    Image(systemName: viewModel.modelSort.direction == .descending ? "chevron.down" : "chevron.up")
                        .font(.caption2)
                }
            }
        }
        .buttonStyle(.plain)
        .help("按\(title)排序")
    }
}

private struct ModelStatsDenseRow: View {
    let stat: ModelUsageStat
    let shareText: String
    let rowIndex: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(stat.model)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(DashboardTheme.ink)
                    .lineLimit(1)
                Text(shareText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(DashboardTheme.softInk)
                    .lineLimit(1)
            }
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

            ModelStatsRequestBreakdownText(
                total: stat.requests,
                successful: stat.successfulRequests,
                failed: stat.failedRequests
            )
            .frame(width: 100, alignment: .trailing)

            ModelStatsNumericCell(UsageFormatters.tokenCount(stat.totalTokens))
                .frame(width: 120)
            ModelStatsNumericCell(UsageFormatters.latencyCompact(stat.averageLatencyMs))
                .frame(width: 100)
            ModelStatsNumericCell(UsageFormatters.latency(stat.totalLatencyMs))
                .frame(width: 110)

            HStack(spacing: 10) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(DashboardTheme.paperDeep.opacity(0.65))
                        Capsule(style: .continuous)
                            .fill(tint)
                            .frame(width: max(10, proxy.size.width * stat.successRate))
                    }
                }
                .frame(width: 54, height: 4)

                Text(UsageFormatters.percent(stat.successRate))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(DashboardTheme.mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: 42, alignment: .trailing)
            }
            .frame(width: 110, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(rowIndex.isMultiple(of: 2) ? DashboardTheme.panelRaised : DashboardTheme.panel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DashboardTheme.hairline)
                .frame(height: 0.5)
        }
    }
}

private struct ModelStatsRequestBreakdownText: View {
    let total: Int
    let successful: Int
    let failed: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(UsageFormatters.integer(total))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .monospacedDigit()
            Text("成功 \(UsageFormatters.integer(successful)) / 失败 \(UsageFormatters.integer(failed))")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardTheme.softInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct ModelStatsEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("暂无模型统计")
                .font(.headline)
            Text("可用模型会在刷新用量后出现。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}
