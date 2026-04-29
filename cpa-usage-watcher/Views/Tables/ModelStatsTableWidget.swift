import SwiftUI

// MARK: - Column width constants (shared/stable)
private enum ModelColumn {
    static let model: CGFloat = 200
    static let requests: CGFloat = 110
    static let tokens: CGFloat = 120
    static let avgLatency: CGFloat = 100
    static let totalLatency: CGFloat = 110
    static let successRate: CGFloat = 120
    static let cost: CGFloat = 100

    static var totalWidth: CGFloat {
        model + requests + tokens + avgLatency + totalLatency + successRate + cost
    }
}

struct ModelStatsTableWidget: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if viewModel.sortedModels.isEmpty {
                ModelStatsEmptyState()
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ModelStatsColumnHeader(viewModel: viewModel)
                        ForEach(Array(viewModel.sortedModels.prefix(5).enumerated()), id: \.element.id) { index, stat in
                            ModelStatsDenseRow(
                                stat: stat,
                                shareText: modelShareText(for: stat),
                                costText: viewModel.formattedCost(stat.cost),
                                rowIndex: index,
                                tint: DashboardTheme.accent(index + 1)
                            )
                        }
                    }
                    .frame(width: ModelColumn.totalWidth + 28, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
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

// MARK: - Sort Controls (retained for potential reuse)

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

// MARK: - Numeric Cell

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

// MARK: - Column Header

private struct ModelStatsColumnHeader: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        HStack(spacing: 0) {
            sortButton(.model, title: "模型")
                .frame(width: ModelColumn.model, alignment: .leading)
            sortButton(.requests, title: "请求次数")
                .frame(width: ModelColumn.requests, alignment: .trailing)
            sortButton(.tokens, title: "Token")
                .frame(width: ModelColumn.tokens, alignment: .trailing)
            sortButton(.averageLatency, title: "平均延迟")
                .frame(width: ModelColumn.avgLatency, alignment: .trailing)
            sortButton(.totalLatency, title: "总延迟")
                .frame(width: ModelColumn.totalLatency, alignment: .trailing)
            sortButton(.successRate, title: "成功率")
                .frame(width: ModelColumn.successRate, alignment: .trailing)
            sortButton(.cost, title: "花费")
                .frame(width: ModelColumn.cost, alignment: .trailing)
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

// MARK: - Row

private struct ModelStatsDenseRow: View {
    let stat: ModelUsageStat
    let shareText: String
    let costText: String
    let rowIndex: Int
    let tint: Color

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Model name + share pct
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(stat.model)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(DashboardTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(shareText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(DashboardTheme.softInk)
                    .lineLimit(1)
            }
            .frame(width: ModelColumn.model, alignment: .leading)

            // Requests breakdown
            ModelStatsRequestBreakdownText(
                total: stat.requests,
                successful: stat.successfulRequests,
                failed: stat.failedRequests
            )
            .frame(width: ModelColumn.requests, alignment: .trailing)

            // Tokens
            ModelStatsNumericCell(UsageFormatters.tokenCount(stat.totalTokens))
                .frame(width: ModelColumn.tokens)

            // Avg latency
            ModelStatsNumericCell(UsageFormatters.latencyCompact(stat.averageLatencyMs))
                .frame(width: ModelColumn.avgLatency)

            // Total latency
            ModelStatsNumericCell(UsageFormatters.latency(stat.totalLatencyMs))
                .frame(width: ModelColumn.totalLatency)

            // Success rate with bar
            HStack(spacing: 8) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(DashboardTheme.paperDeep.opacity(0.65))
                        Capsule(style: .continuous)
                            .fill(tint)
                            .frame(width: max(6, proxy.size.width * stat.successRate))
                    }
                }
                .frame(width: 44, height: 4)

                Text(UsageFormatters.percent(stat.successRate))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(DashboardTheme.mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: 42, alignment: .trailing)
            }
            .frame(width: ModelColumn.successRate, alignment: .trailing)

            // Cost
            Text(costText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: ModelColumn.cost, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DashboardTheme.hairline)
                .frame(height: 0.5)
        }
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        isHovered ? DashboardTheme.paper : (rowIndex.isMultiple(of: 2) ? DashboardTheme.panelRaised : DashboardTheme.panel)
    }
}

// MARK: - Request Breakdown

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

// MARK: - Empty State

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
