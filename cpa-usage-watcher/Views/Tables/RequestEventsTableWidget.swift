import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Column width constants (shared/stable)
private enum EventColumn {
    static let rowMark: CGFloat = 24
    static let time: CGFloat = 100
    static let model: CGFloat = 160
    static let source: CGFloat = 130
    static let authIndex: CGFloat = 90
    static let status: CGFloat = 58
    static let latency: CGFloat = 68
    static let inputTok: CGFloat = 60
    static let outputTok: CGFloat = 60
    static let reasoningTok: CGFloat = 60
    static let cacheTok: CGFloat = 60
    static let totalTok: CGFloat = 72

    static var totalWidth: CGFloat {
        rowMark + time + model + source + authIndex + status + latency
            + inputTok + outputTok + reasoningTok + cacheTok + totalTok
    }
}

struct RequestEventsTableWidget: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            filters

            if viewModel.sortedEvents.isEmpty {
                RequestEventsEmptyState(hasFilters: viewModel.hasActiveEventFilters)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        RequestEventsColumnHeader(viewModel: viewModel)
                        ForEach(Array(viewModel.sortedEvents.prefix(15).enumerated()), id: \.element.id) { index, event in
                            RequestEventsRow(
                                event: event,
                                sourceTitle: viewModel.displayedSourceTitle(
                                    source: event.source,
                                    provider: event.provider
                                ),
                                authIndexTitle: viewModel.displayedSensitiveValue(event.authIndex),
                                rowIndex: index,
                                modelTint: DashboardTheme.accent(index + 1)
                            )
                        }
                    }
                    .frame(width: EventColumn.totalWidth + 28, alignment: .topLeading)
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
                Text("請求事件明細")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(DashboardTheme.ink)
                Text("リクエストログ")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(DashboardTheme.softInk)
            }

            Spacer()

            Text("\(UsageFormatters.integer(viewModel.sortedEvents.prefix(15).count)) / \(UsageFormatters.integer(viewModel.sortedEvents.count)) 件")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardTheme.softInk)

            Button {
                export(.csv)
            } label: {
                Label("CSV", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(DashboardChromeButtonStyle(accent: DashboardTheme.orange))
            .help("导出当前过滤结果为 CSV")

            Button {
                export(.json)
            } label: {
                Label("JSON", systemImage: "curlybraces.square")
            }
            .buttonStyle(DashboardChromeButtonStyle(accent: DashboardTheme.blue))
            .help("导出当前过滤结果为 JSON")
        }
    }

    private var filters: some View {
        HStack(spacing: 8) {
            Text("FILTER")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(DashboardTheme.softInk)
                .tracking(1.4)
            RequestEventsFilterPicker(
                title: "模型",
                allTitle: "全部模型",
                options: viewModel.modelFilterOptions,
                selection: $viewModel.eventFilters.model
            )

            RequestEventsFilterPicker(
                title: "来源",
                allTitle: "全部来源",
                options: viewModel.sourceFilterOptions,
                displayTitle: viewModel.displayedSensitiveValue,
                selection: $viewModel.eventFilters.source
            )

            RequestEventsFilterPicker(
                title: "認證索引",
                allTitle: "全部認證",
                options: viewModel.authIndexFilterOptions,
                displayTitle: viewModel.displayedSensitiveValue,
                selection: $viewModel.eventFilters.authIndex
            )

            Spacer()

            Text(viewModel.refreshIntervalTitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardTheme.softInk)
        }
    }

    private func export(_ format: UsageExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = viewModel.suggestedFilteredEventsFilename(format: format)

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        Task {
            do {
                try await viewModel.exportFilteredEvents(format: format, to: url)
            } catch {
                NSSound.beep()
            }
        }
    }
}

// MARK: - Filter Picker

private struct RequestEventsFilterPicker: View {
    let title: String
    let allTitle: String
    let options: [String]
    let displayTitle: (String) -> String
    @Binding var selection: String

    init(
        title: String,
        allTitle: String,
        options: [String],
        displayTitle: @escaping (String) -> String = { $0 },
        selection: Binding<String>
    ) {
        self.title = title
        self.allTitle = allTitle
        self.options = options
        self.displayTitle = displayTitle
        self._selection = selection
    }

    var body: some View {
        Picker(title, selection: $selection) {
            Text(allTitle).tag("")
            ForEach(options, id: \.self) { option in
                Text(displayTitle(option)).tag(option)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 150)
    }
}

// MARK: - Numeric Cell

private struct RequestEventsNumericCell: View {
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

private struct RequestEventsColumnHeader: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: EventColumn.rowMark, alignment: .leading)
            sortButton(.time, title: "时间")
                .frame(width: EventColumn.time, alignment: .leading)
            sortButton(.model, title: "模型")
                .frame(width: EventColumn.model, alignment: .leading)
            sortButton(.source, title: "来源")
                .frame(width: EventColumn.source, alignment: .leading)
            sortButton(.authIndex, title: "凭证")
                .frame(width: EventColumn.authIndex, alignment: .leading)
            sortButton(.result, title: "结果")
                .frame(width: EventColumn.status, alignment: .leading)
            sortButton(.latency, title: "延迟")
                .frame(width: EventColumn.latency, alignment: .trailing)
            Text("输入")
                .frame(width: EventColumn.inputTok, alignment: .trailing)
            Text("输出")
                .frame(width: EventColumn.outputTok, alignment: .trailing)
            Text("推理")
                .frame(width: EventColumn.reasoningTok, alignment: .trailing)
            Text("缓存")
                .frame(width: EventColumn.cacheTok, alignment: .trailing)
            sortButton(.tokens, title: "TOTAL")
                .frame(width: EventColumn.totalTok, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .black, design: .rounded))
        .foregroundStyle(DashboardTheme.mutedInk.opacity(0.75))
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardTheme.paperDeep.opacity(0.62))
    }

    private func sortButton(_ column: EventSort, title: String) -> some View {
        Button {
            viewModel.setEventSort(column)
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if viewModel.eventSort.column == column {
                    Image(systemName: viewModel.eventSort.direction == .descending ? "chevron.down" : "chevron.up")
                        .font(.caption2)
                }
            }
        }
        .buttonStyle(.plain)
        .help("按\(title)排序")
    }
}

// MARK: - Row

private struct RequestEventsRow: View {
    let event: RequestEvent
    let sourceTitle: String
    let authIndexTitle: String
    let rowIndex: Int
    let modelTint: Color

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Status dot
            ZStack {
                Circle()
                    .fill(event.isSuccess ? DashboardTheme.green.opacity(0.18) : DashboardTheme.red.opacity(0.18))
                    .frame(width: 10, height: 10)
                Circle()
                    .fill(event.isSuccess ? DashboardTheme.green : DashboardTheme.red)
                    .frame(width: 5, height: 5)
            }
            .frame(width: EventColumn.rowMark, alignment: .leading)

            // Time
            HStack(spacing: 5) {
                Text(UsageFormatters.dateTime(event.timestamp))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(width: EventColumn.time, alignment: .leading)

            // Model – middle truncate
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(event.isSuccess ? modelTint : DashboardTheme.red)
                    .frame(width: 6, height: 6)
                Text(event.model)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: EventColumn.model, alignment: .leading)

            // Source – middle truncate
            Text(sourceTitle)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: EventColumn.source, alignment: .leading)

            // Auth index – middle truncate
            Text(authIndexTitle)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: EventColumn.authIndex, alignment: .leading)

            // Status pill (fixed width capsule)
            statusPill
                .frame(width: EventColumn.status, alignment: .leading)

            // Numeric columns – right aligned
            RequestEventsNumericCell(UsageFormatters.latencyCompact(event.latencyMs))
                .frame(width: EventColumn.latency)

            RequestEventsNumericCell(UsageFormatters.tokenCount(event.inputTokens))
                .frame(width: EventColumn.inputTok)

            RequestEventsNumericCell(UsageFormatters.tokenCount(event.outputTokens))
                .frame(width: EventColumn.outputTok)

            RequestEventsNumericCell(UsageFormatters.tokenCount(event.reasoningTokens))
                .frame(width: EventColumn.reasoningTok)

            RequestEventsNumericCell(UsageFormatters.tokenCount(event.cachedTokens))
                .frame(width: EventColumn.cacheTok)

            RequestEventsNumericCell(UsageFormatters.tokenCount(event.totalTokens))
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .frame(width: EventColumn.totalTok)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(DashboardTheme.mutedInk)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DashboardTheme.hairline)
                .frame(height: 0.5)
        }
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isHovered {
            return DashboardTheme.paper
        }
        return rowIndex.isMultiple(of: 2) ? DashboardTheme.panelRaised : DashboardTheme.panel
    }

    private var statusPill: some View {
        Text(event.resultTitle)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(event.isSuccess ? DashboardTheme.green : DashboardTheme.red)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill((event.isSuccess ? DashboardTheme.green : DashboardTheme.red).opacity(0.13))
            )
    }
}

// MARK: - Sort Controls (retained for potential reuse)

private struct RequestEventsSortControls: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        HStack(spacing: 8) {
            Picker("排序", selection: columnBinding) {
                ForEach(viewModel.eventSortOptions) { option in
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

    private var columnBinding: Binding<EventSort> {
        Binding {
            viewModel.eventSort.column
        } set: { column in
            viewModel.eventSort = EventSortState(column: column, direction: viewModel.eventSort.direction)
        }
    }

    private var directionBinding: Binding<UsageSortDirection> {
        Binding {
            viewModel.eventSort.direction
        } set: { direction in
            viewModel.eventSort = EventSortState(column: viewModel.eventSort.column, direction: direction)
        }
    }
}

// MARK: - Empty State

private struct RequestEventsEmptyState: View {
    let hasFilters: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: hasFilters ? "line.3.horizontal.decrease.circle" : "list.bullet.rectangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(hasFilters ? "没有匹配事件" : "暂无请求事件")
                .font(.headline)
            Text(hasFilters ? "调整筛选条件后重试。" : "刷新后会显示逐条请求明细。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

private extension UsageExportFormat {
    var contentType: UTType {
        UTType(filenameExtension: fileExtension) ?? .data
    }
}
