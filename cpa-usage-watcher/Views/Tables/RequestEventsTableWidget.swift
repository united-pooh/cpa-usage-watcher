import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RequestEventsTableWidget: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            filters

            if viewModel.sortedEvents.isEmpty {
                RequestEventsEmptyState(hasFilters: viewModel.hasActiveEventFilters)
            } else {
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

            Text("自動刷新 · 5s")
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

private struct RequestEventsColumnHeader: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: 24, alignment: .leading)
            sortButton(.time, title: "时间")
                .frame(width: 84, alignment: .leading)
            sortButton(.model, title: "模型")
                .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
            sortButton(.source, title: "来源")
                .frame(width: 100, alignment: .leading)
            sortButton(.authIndex, title: "凭证")
                .frame(width: 62, alignment: .leading)
            sortButton(.result, title: "结果")
                .frame(width: 56, alignment: .leading)
            sortButton(.latency, title: "延迟")
                .frame(width: 60, alignment: .trailing)
            Text("输入")
                .frame(width: 52, alignment: .trailing)
            Text("输出")
                .frame(width: 52, alignment: .trailing)
            Text("推理")
                .frame(width: 52, alignment: .trailing)
            Text("缓存")
                .frame(width: 52, alignment: .trailing)
            sortButton(.tokens, title: "總 TOKEN")
                .frame(width: 68, alignment: .trailing)
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

private struct RequestEventsRow: View {
    let event: RequestEvent
    let sourceTitle: String
    let authIndexTitle: String
    let rowIndex: Int
    let modelTint: Color

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(isChecked ? DashboardTheme.orange : DashboardTheme.hairline, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(isChecked ? DashboardTheme.orange : Color.clear)
                    )
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(DashboardTheme.cream)
                }
            }
            .frame(width: 12, height: 12)
            .frame(width: 24, alignment: .leading)

            HStack(spacing: 5) {
                Text(UsageFormatters.dateTime(event.timestamp))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(width: 84, alignment: .leading)

            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(event.isSuccess ? modelTint : DashboardTheme.red)
                    .frame(width: 7, height: 7)
                Text(event.model)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)

            Text(sourceTitle)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 100, alignment: .leading)

            Text(authIndexTitle)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 62, alignment: .leading)

            Text(event.resultTitle)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(event.isSuccess ? DashboardTheme.green : DashboardTheme.red)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill((event.isSuccess ? DashboardTheme.green : DashboardTheme.red).opacity(0.13))
                )
                .frame(width: 56, alignment: .leading)

            RequestEventsNumericCell(UsageFormatters.latencyCompact(event.latencyMs))
                .frame(width: 60)

            RequestEventsNumericCell(UsageFormatters.tokenCount(event.inputTokens))
                .frame(width: 52)

            RequestEventsNumericCell(UsageFormatters.tokenCount(event.outputTokens))
                .frame(width: 52)

            RequestEventsNumericCell(UsageFormatters.tokenCount(event.reasoningTokens))
                .frame(width: 52)

            RequestEventsNumericCell(UsageFormatters.tokenCount(event.cachedTokens))
                .frame(width: 52)

            RequestEventsNumericCell(UsageFormatters.tokenCount(event.totalTokens))
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .frame(width: 68)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(DashboardTheme.mutedInk)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(rowIndex.isMultiple(of: 2) ? DashboardTheme.panelRaised : DashboardTheme.panel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DashboardTheme.hairline)
                .frame(height: 0.5)
        }
    }

    private var isChecked: Bool {
        rowIndex == 0 || rowIndex == 4
    }
}

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
