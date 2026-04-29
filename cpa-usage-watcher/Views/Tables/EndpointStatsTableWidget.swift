import SwiftUI

// MARK: - Column width constants (shared/stable)
private enum EndpointColumn {
    static let endpoint: CGFloat = 220
    static let requests: CGFloat = 90
    static let tokens: CGFloat = 130
    static let cost: CGFloat = 100
    static let errors: CGFloat = 60
    static let avgLatency: CGFloat = 100

    static var totalWidth: CGFloat {
        endpoint + requests + tokens + cost + errors + avgLatency
    }
}

struct EndpointStatsTableWidget: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if viewModel.sortedEndpoints.isEmpty {
                EndpointStatsEmptyState()
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        EndpointStatsColumnHeader(viewModel: viewModel)
                        ForEach(Array(viewModel.sortedEndpoints.prefix(5).enumerated()), id: \.element.id) { index, endpoint in
                            EndpointStatsParentRow(
                                stat: endpoint,
                                endpointTitle: viewModel.displayedSensitiveValue(endpoint.endpoint),
                                costText: viewModel.formattedCost(endpoint.cost),
                                isExpanded: viewModel.isEndpointExpanded(endpoint.id),
                                rowIndex: index
                            ) {
                                viewModel.toggleEndpointExpansion(endpoint.id)
                            }

                            if viewModel.isEndpointExpanded(endpoint.id) {
                                ForEach(endpoint.models.prefix(3)) { model in
                                    EndpointStatsModelRow(
                                        stat: model,
                                        costText: viewModel.formattedCost(model.cost)
                                    )
                                }
                            }
                        }
                    }
                    .frame(width: EndpointColumn.totalWidth + 28, alignment: .topLeading)
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
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("API 詳細統計")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(DashboardTheme.ink)
                Text("エンドポイント別")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(DashboardTheme.softInk)
            }

            Spacer()

            Text("\(UsageFormatters.integer(viewModel.sortedEndpoints.count)) 個 endpoint · 展開查看模型明細")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardTheme.softInk)
                .lineLimit(1)
        }
    }
}

// MARK: - Column Header

private struct EndpointStatsColumnHeader: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        HStack(spacing: 0) {
            sortButton(.endpoint, title: "API KEY / ENDPOINT")
                .frame(width: EndpointColumn.endpoint, alignment: .leading)
            sortButton(.requests, title: "請求數")
                .frame(width: EndpointColumn.requests, alignment: .trailing)
            sortButton(.tokens, title: "TOKEN")
                .frame(width: EndpointColumn.tokens, alignment: .trailing)
            sortButton(.cost, title: "花費")
                .frame(width: EndpointColumn.cost, alignment: .trailing)
            Text("錯誤")
                .frame(width: EndpointColumn.errors, alignment: .trailing)
            Text("平均延遲")
                .frame(width: EndpointColumn.avgLatency, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .black, design: .rounded))
        .foregroundStyle(DashboardTheme.mutedInk.opacity(0.75))
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(DashboardTheme.paperDeep.opacity(0.62))
    }

    private func sortButton(_ column: EndpointSort, title: String) -> some View {
        Button {
            viewModel.setEndpointSort(column)
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if viewModel.endpointSort.column == column {
                    Image(systemName: viewModel.endpointSort.direction == .descending ? "chevron.down" : "chevron.up")
                        .font(.caption2)
                }
            }
        }
        .buttonStyle(.plain)
        .help("按\(title)排序")
    }
}

// MARK: - Parent Row

private struct EndpointStatsParentRow: View {
    let stat: EndpointUsageStat
    let endpointTitle: String
    let costText: String
    let isExpanded: Bool
    let rowIndex: Int
    let toggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 9) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DashboardTheme.softInk)
                        .frame(width: 10)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(DashboardTheme.orange)
                        .frame(width: 25, height: 25)
                        .overlay(
                            Text("of")
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .foregroundStyle(DashboardTheme.cream)
                        )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(endpointTitle)
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(DashboardTheme.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(UsageFormatters.integer(stat.models.count)) models")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(DashboardTheme.softInk)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(width: EndpointColumn.endpoint, alignment: .leading)

            EndpointStatsRequestBreakdownText(
                total: stat.requests,
                successful: stat.successfulRequests,
                failed: stat.failedRequests
            )
            .frame(width: EndpointColumn.requests, alignment: .trailing)

            Text(UsageFormatters.tokenCount(stat.totalTokens))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .frame(width: EndpointColumn.tokens, alignment: .trailing)

            Text(costText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .frame(width: EndpointColumn.cost, alignment: .trailing)

            Text(UsageFormatters.integer(stat.failedRequests))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(stat.failedRequests > 0 ? DashboardTheme.red : DashboardTheme.softInk)
                .frame(width: EndpointColumn.errors, alignment: .trailing)

            Text(UsageFormatters.latencyCompact(stat.averageLatencyMs))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(DashboardTheme.mutedInk)
                .frame(width: EndpointColumn.avgLatency, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
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

// MARK: - Model Sub-Row

private struct EndpointStatsModelRow: View {
    let stat: EndpointModelStat
    let costText: String

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Spacer()
                    .frame(width: 38)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(DashboardTheme.blue)
                    .frame(width: 7, height: 7)
                Text(stat.model)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(DashboardTheme.mutedInk)
            }
            .frame(width: EndpointColumn.endpoint, alignment: .leading)

            EndpointStatsRequestBreakdownText(
                total: stat.requests,
                successful: stat.successfulRequests,
                failed: stat.failedRequests
            )
            .frame(width: EndpointColumn.requests, alignment: .trailing)

            Text(UsageFormatters.tokenCount(stat.totalTokens))
                .monospacedDigit()
                .frame(width: EndpointColumn.tokens, alignment: .trailing)

            Text(costText)
                .monospacedDigit()
                .frame(width: EndpointColumn.cost, alignment: .trailing)

            Text(UsageFormatters.integer(stat.failedRequests))
                .monospacedDigit()
                .foregroundStyle(stat.failedRequests > 0 ? DashboardTheme.red : DashboardTheme.softInk)
                .frame(width: EndpointColumn.errors, alignment: .trailing)

            Text(UsageFormatters.latencyCompact(stat.averageLatencyMs))
                .monospacedDigit()
                .frame(width: EndpointColumn.avgLatency, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(DashboardTheme.mutedInk)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(isHovered ? DashboardTheme.paper : DashboardTheme.panel.opacity(0.9))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DashboardTheme.hairline)
                .frame(height: 0.5)
        }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Request Breakdown

private struct EndpointStatsRequestBreakdownText: View {
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
    }
}

// MARK: - Empty State

private struct EndpointStatsEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("暂无端点用量")
                .font(.headline)
            Text("刷新后会在这里显示端点与模型层级。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}
