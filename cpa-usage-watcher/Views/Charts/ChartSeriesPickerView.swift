import SwiftUI

struct ChartSeriesPickerView: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)
    ]

    var body: some View {
        DashboardPanel(
            title: "模型曲线",
            subtitle: "最多 \(ChartSeriesSelection.maxSelectedModels) 条同时显示",
            systemImage: "line.3.horizontal.decrease.circle"
        ) {
            if viewModel.chartSeriesOptions.isEmpty {
                DashboardEmptyStateView(
                    title: "暂无模型曲线",
                    message: "刷新数据后会显示可选模型。",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        DashboardStatusBadge(
                            text: selectionBadgeText,
                            systemImage: selectionBadgeIcon,
                            tone: selectionBadgeTone
                        )

                        Text(selectionHelpText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer()

                        Button("清除选择") {
                            viewModel.clearChartSeriesSelection()
                        }
                        .controlSize(.small)
                        .disabled(viewModel.chartSeriesSelection.selectedModels.isEmpty)
                    }

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(viewModel.chartSeriesOptions, id: \.self) { model in
                            Toggle(
                                isOn: Binding(
                                    get: { viewModel.isChartSeriesSelected(model) },
                                    set: { isSelected in
                                        if isSelected {
                                            _ = viewModel.toggleChartSeries(model)
                                        } else {
                                            viewModel.setChartSeriesSelection(
                                                viewModel.chartSeriesSelection.selectedModels.subtracting([model])
                                            )
                                        }
                                    }
                                )
                            ) {
                                Text(model)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .toggleStyle(.checkbox)
                            .disabled(
                                !viewModel.isChartSeriesSelected(model)
                                && !viewModel.canSelectMoreChartSeries
                            )
                        }
                    }
                }
            }
        }
    }

    private var selectionCount: Int {
        viewModel.chartSeriesSelection.selectedModels.count
    }

    private var selectionBadgeText: String {
        selectionCount == 0 ? "自动显示" : "已选 \(selectionCount)"
    }

    private var selectionBadgeIcon: String {
        selectionCount == 0 ? "sparkles" : "checkmark.circle"
    }

    private var selectionBadgeTone: DashboardStatusTone {
        selectionCount == 0 ? .neutral : .accent
    }

    private var selectionHelpText: String {
        if selectionCount == 0 {
            return "显示前 \(ChartSeriesSelection.maxSelectedModels) 个模型"
        }
        return "手动选择曲线"
    }
}
