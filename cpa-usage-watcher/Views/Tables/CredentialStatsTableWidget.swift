import SwiftUI

// MARK: - Column width constants (shared/stable)
private enum CredentialColumn {
    static let credential: CGFloat = 220
    static let requests: CGFloat = 58
    static let successRate: CGFloat = 110
    static let lastUsed: CGFloat = 80

    static var totalWidth: CGFloat {
        credential + requests + successRate + lastUsed
    }
}

struct CredentialStatsTableWidget: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            if viewModel.sortedCredentials.isEmpty {
                CredentialStatsEmptyState()
            } else {
                credentialCards
            }
        }
    }

    // MARK: - Header

    private var header: some View {
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
    }

    // MARK: - Card List

    private var credentialCards: some View {
        VStack(spacing: 0) {
            CredentialStatsColumnHeader(viewModel: viewModel)

            ForEach(Array(viewModel.sortedCredentials.enumerated()), id: \.element.id) { index, credential in
                CredentialCardRow(
                    credential: credential,
                    sourceTitle: sourceTitle(for: credential),
                    credentialTitle: viewModel.displayedSensitiveValue(credential.credential),
                    quotaItems: quotaItems(for: credential),
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

    // MARK: - Helpers

    private func sourceTitle(for credential: CredentialUsageStat) -> String {
        viewModel.displayedSourceTitle(source: credential.source, provider: credential.provider)
    }

    private func quotaItems(for credential: CredentialUsageStat) -> [CredentialQuotaItem] {
        viewModel.displaySnapshot.credentialQuotas
            .filter { quota in
                quota.credential == credential.credential ||
                    quota.source == credential.source ||
                    quota.provider == credential.provider
            }
            .flatMap(CredentialQuotaItem.items)
    }
}

// MARK: - Column Header

private struct CredentialStatsColumnHeader: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        HStack(spacing: 0) {
            sortButton(.credential, title: "憑證 / 來源")
                .frame(width: CredentialColumn.credential, alignment: .leading)
            sortButton(.requests, title: "請求")
                .frame(width: CredentialColumn.requests, alignment: .leading)
            sortButton(.successRate, title: "成功率")
                .frame(width: CredentialColumn.successRate, alignment: .leading)
            sortButton(.lastUsed, title: "最後使用")
                .frame(width: CredentialColumn.lastUsed, alignment: .leading)
        }
        .font(.system(size: 11, weight: .black, design: .rounded))
        .foregroundStyle(DashboardTheme.mutedInk.opacity(0.75))
        .padding(.horizontal, 16)
        .frame(height: 34)
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

// MARK: - Credential Card Row

private struct CredentialCardRow: View {
    let credential: CredentialUsageStat
    let sourceTitle: String
    let credentialTitle: String
    let quotaItems: [CredentialQuotaItem]
    let rowIndex: Int

    @State private var isHovered = false
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            HStack(spacing: 0) {
                // Credential identity
                credentialIdentityCell
                    .frame(width: CredentialColumn.credential, alignment: .leading)

                // Request count
                CredentialStatsRequestBreakdownText(
                    total: credential.requests,
                    successful: credential.successfulRequests,
                    failed: credential.failedRequests
                )
                .frame(width: CredentialColumn.requests, alignment: .leading)

                // Success rate bar + pct
                successRateCell
                    .frame(width: CredentialColumn.successRate, alignment: .leading)

                // Last used
                Text(UsageFormatters.relativeTime(credential.lastUsedAt))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(DashboardTheme.mutedInk.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: CredentialColumn.lastUsed, alignment: .leading)

                Spacer()

                // Quota expand toggle (only when quota items exist)
                if !quotaItems.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isExpanded ? "chevron.up" : "gauge.with.needle")
                                .font(.system(size: 10, weight: .semibold))
                            Text("配額")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(isExpanded ? DashboardTheme.orange : DashboardTheme.mutedInk.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isExpanded ? DashboardTheme.orange.opacity(0.12) : DashboardTheme.paper)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(isExpanded ? DashboardTheme.orange.opacity(0.4) : DashboardTheme.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                    .help("查看配額詳情")
                }
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(DashboardTheme.mutedInk)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(rowBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isExpanded ? DashboardTheme.hairline.opacity(0.4) : DashboardTheme.hairline)
                    .frame(height: 0.5)
            }
            .onHover { isHovered = $0 }

            // Expandable quota section
            if isExpanded, !quotaItems.isEmpty {
                quotaSection
            }
        }
    }

    // MARK: Credential Identity Cell

    private var credentialIdentityCell: some View {
        HStack(spacing: 10) {
            // Provider icon
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(providerColor.opacity(0.13))
                    .frame(width: 30, height: 30)
                Image(systemName: providerIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(providerColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(credentialTitle)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DashboardTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !providerLine.isEmpty {
                    Text(providerLine)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(DashboardTheme.softInk)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    // MARK: Success Rate Cell

    private var successRateCell: some View {
        HStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(DashboardTheme.paperDeep.opacity(0.66))
                    Capsule(style: .continuous)
                        .fill(successRateColor)
                        .frame(width: max(6, proxy.size.width * credential.successRate))
                }
            }
            .frame(width: 38, height: 5)

            Text(UsageFormatters.percent(credential.successRate))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(DashboardTheme.mutedInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    // MARK: Quota Section

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            let providerName = credential.provider.isEmpty ? sourceTitle : credential.provider
            CredentialQuotaCardView(items: quotaItems, providerLabel: providerName)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardTheme.paper.opacity(0.6))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DashboardTheme.hairline)
                .frame(height: 0.5)
        }
    }

    // MARK: Computed Properties

    private var rowBackground: Color {
        isHovered ? DashboardTheme.paper : (rowIndex.isMultiple(of: 2) ? DashboardTheme.panelRaised : DashboardTheme.panel)
    }

    private var successRateColor: Color {
        credential.successRate > 0.985 ? DashboardTheme.green : DashboardTheme.yellow
    }

    private var providerLine: String {
        if sourceTitle.isEmpty || sourceTitle == "--" { return "" }
        return sourceTitle
    }

    private var providerIcon: String {
        let lower = (credential.provider + credential.source).lowercased()
        if lower.contains("local") || lower.contains("key") { return "key" }
        if lower.contains("azure") { return "cloud" }
        if lower.contains("gcp") || lower.contains("google") { return "cloud.fill" }
        if lower.contains("aws") || lower.contains("amazon") { return "cloud.bolt" }
        if lower.contains("anthropic") || lower.contains("claude") { return "sparkles" }
        if lower.contains("openai") || lower.contains("gpt") { return "wand.and.stars" }
        if lower.contains("groq") { return "bolt.fill" }
        if lower.contains("mistral") { return "wind" }
        if lower.contains("ollama") || lower.contains("local") { return "desktopcomputer" }
        return "person.badge.key"
    }

    private var providerColor: Color {
        let lower = (credential.provider + credential.source).lowercased()
        if lower.contains("anthropic") || lower.contains("claude") { return DashboardTheme.orange }
        if lower.contains("openai") || lower.contains("gpt") { return DashboardTheme.green }
        if lower.contains("azure") { return DashboardTheme.blue }
        if lower.contains("google") || lower.contains("gcp") { return DashboardTheme.yellow }
        if lower.contains("groq") { return DashboardTheme.purple }
        return DashboardTheme.mutedInk
    }
}

// MARK: - Sort Controls (retained for potential reuse)

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

// MARK: - Numeric Cell

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

// MARK: - Request Breakdown Text

private struct CredentialStatsRequestBreakdownText: View {
    let total: Int
    let successful: Int
    let failed: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(UsageFormatters.integer(total))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(DashboardTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if failed > 0 {
                Text("\(UsageFormatters.integer(failed)) 失败")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(DashboardTheme.red.opacity(0.85))
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Empty State

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
