import SwiftUI

struct CredentialStatsTableWidget: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text("憑證統計")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(DashboardTheme.ink)

                    Text("クレデンシャル")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(DashboardTheme.softInk)
                }

                Spacer()

                Text("\(UsageFormatters.integer(viewModel.sortedCredentials.count)) 個憑證")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(DashboardTheme.softInk)
            }

            if viewModel.sortedCredentials.isEmpty {
                CredentialStatsEmptyState()
            } else {
                VStack(spacing: 0) {
                    CredentialStatsColumnHeader(viewModel: viewModel)

                    ForEach(Array(viewModel.sortedCredentials.prefix(5).enumerated()), id: \.element.id) { index, credential in
                        CredentialStatsDenseRow(
                            credential: credential,
                            sourceTitle: sourceTitle(for: credential),
                            credentialTitle: viewModel.displayedSensitiveValue(credential.credential),
                            rowIndex: index
                        )
                    }
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

    private func sourceTitle(for credential: CredentialUsageStat) -> String {
        viewModel.displayedSourceTitle(source: credential.source, provider: credential.provider)
    }
}

private struct CredentialStatsColumnHeader: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        HStack(spacing: 10) {
            sortButton(.credential, title: "憑證")
                .frame(maxWidth: .infinity, alignment: .leading)
            sortButton(.requests, title: "請求")
                .frame(width: 58, alignment: .leading)
            sortButton(.successRate, title: "成功率")
                .frame(width: 102, alignment: .leading)
            sortButton(.lastUsed, title: "最後使用")
                .frame(width: 72, alignment: .leading)
        }
        .font(.system(size: 13, weight: .black, design: .rounded))
        .foregroundStyle(DashboardTheme.mutedInk.opacity(0.75))
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(DashboardTheme.paperDeep.opacity(0.62))
    }

    private func sortButton(_ column: CredentialSort, title: String) -> some View {
        Button {
            viewModel.setCredentialSort(column)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                if viewModel.credentialSort.column == column {
                    Image(systemName: viewModel.credentialSort.direction == .descending ? "chevron.down" : "chevron.up")
                        .font(.caption2)
                }
            }
        }
        .buttonStyle(.plain)
        .help("按\(title)排序")
    }
}

private struct CredentialStatsDenseRow: View {
    let credential: CredentialUsageStat
    let sourceTitle: String
    let credentialTitle: String
    let rowIndex: Int

    var body: some View {
        HStack(spacing: 10) {
            credentialCell
                .frame(maxWidth: .infinity, alignment: .leading)

            CredentialStatsRequestBreakdownText(
                total: credential.requests,
                successful: credential.successfulRequests,
                failed: credential.failedRequests
            )
            .frame(width: 58, alignment: .leading)

            HStack(spacing: 12) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(DashboardTheme.paperDeep.opacity(0.66))
                        Capsule(style: .continuous)
                            .fill(credential.successRate > 0.985 ? DashboardTheme.green : DashboardTheme.yellow)
                            .frame(width: max(8, proxy.size.width * credential.successRate))
                    }
                }
                .frame(width: 42, height: 6)

                CredentialStatsNumericCell(UsageFormatters.percent(credential.successRate))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            .frame(width: 102, alignment: .leading)

            Text(UsageFormatters.relativeTime(credential.lastUsedAt))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardTheme.mutedInk.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 72, alignment: .leading)
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(DashboardTheme.mutedInk)
        .padding(.horizontal, 16)
        .frame(height: 62)
        .background(rowIndex.isMultiple(of: 2) ? DashboardTheme.panelRaised : DashboardTheme.panel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DashboardTheme.hairline)
                .frame(height: 0.5)
        }
    }

    private var credentialCell: some View {
        HStack(spacing: 10) {
            if credential.source.lowercased().contains("local") {
                Image(systemName: "key")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DashboardTheme.ink)
            }

            Text(displayTitle)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(DashboardTheme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var displayTitle: String {
        guard !sourceTitle.isEmpty, sourceTitle != "--" else {
            return credentialTitle
        }
        return "\(sourceTitle) / \(credentialTitle)"
    }
}

private struct CredentialStatsSortControls: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        HStack(spacing: 8) {
            Picker("排序", selection: columnBinding) {
                ForEach(viewModel.credentialSortOptions) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 116)

            Picker("方向", selection: directionBinding) {
                ForEach(UsageSortDirection.allCases) { direction in
                    Text(direction.title).tag(direction)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 116)
        }
    }

    private var columnBinding: Binding<CredentialSort> {
        Binding {
            viewModel.credentialSort.column
        } set: { column in
            viewModel.credentialSort = CredentialSortState(column: column, direction: viewModel.credentialSort.direction)
        }
    }

    private var directionBinding: Binding<UsageSortDirection> {
        Binding {
            viewModel.credentialSort.direction
        } set: { direction in
            viewModel.credentialSort = CredentialSortState(column: viewModel.credentialSort.column, direction: direction)
        }
    }
}

private struct CredentialStatsNumericCell: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct CredentialStatsRequestBreakdownText: View {
    let total: Int
    let successful: Int
    let failed: Int

    var body: some View {
        Text(UsageFormatters.integer(total))
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundStyle(DashboardTheme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CredentialStatsEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.horizontal")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("暂无凭证统计")
                .font(.headline)
            Text("刷新后会按凭证与来源汇总请求。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}
