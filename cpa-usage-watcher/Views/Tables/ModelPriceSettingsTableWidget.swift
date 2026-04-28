import SwiftUI

struct ModelPriceSettingsTableWidget: View {
    @ObservedObject var viewModel: UsageDashboardViewModel
    @State private var draftModel = ""
    @State private var draftPromptPrice = 0.0
    @State private var draftCompletionPrice = 0.0
    @State private var draftCachePrice = 0.0
    @State private var editingModel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            editor
            savedPriceList
        }
        .onAppear(perform: loadInitialDraftIfNeeded)
        .onChange(of: viewModel.sortedModelPrices) { _, _ in
            loadInitialDraftIfNeeded()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text("模型價格設置")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(DashboardTheme.ink)

            Text("價格設定 · per 1M tokens")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardTheme.softInk)

            Spacer()
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                editorLabel("模型 / MODEL")
                modelSelector
            }

            HStack(spacing: 12) {
                PriceFieldBlock(title: "提示價格 · INPUT", value: $draftPromptPrice)
                PriceFieldBlock(title: "補全價格 · OUTPUT", value: $draftCompletionPrice)
            }

            PriceFieldBlock(title: "緩存價格 · CACHED", value: $draftCachePrice)

            HStack(spacing: 14) {
                Button {
                    saveDraft()
                } label: {
                    Label("保存價格", systemImage: "externaldrive.fill")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .buttonStyle(DashboardChromeButtonStyle(accent: DashboardTheme.orange, isProminent: true))
                .disabled(!canSaveDraft)

                Label(isDraftUnsaved ? "未保存修改" : "已同步", systemImage: isDraftUnsaved ? "bolt" : "checkmark")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(isDraftUnsaved ? DashboardTheme.orange : DashboardTheme.green)

                Spacer()
            }
        }
    }

    private var modelSelector: some View {
        Menu {
            ForEach(viewModel.priceModelOptions, id: \.self) { model in
                Button(model) {
                    draftModel = model
                    if let price = viewModel.modelPrice(for: model) {
                        edit(price)
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(modelSwatchColor(for: draftModel))
                    .frame(width: 12, height: 12)

                Text(draftModel.isEmpty ? "選擇模型" : draftModel)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(draftModel.isEmpty ? DashboardTheme.softInk : DashboardTheme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Image(systemName: "chevron.down")
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DashboardTheme.softInk)
                }
                .foregroundStyle(DashboardTheme.ink)
                .frame(width: 54, height: 42)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DashboardTheme.panelRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DashboardTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.priceModelOptions.isEmpty)
    }

    private var savedPriceList: some View {
        VStack(alignment: .leading, spacing: 20) {
            Rectangle()
                .fill(DashboardTheme.hairline)
                .frame(height: 0.5)

            HStack(spacing: 8) {
                Image(systemName: "tray.full")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DashboardTheme.mutedInk)

                Text("已保存價格 · \(UsageFormatters.integer(viewModel.sortedModelPrices.count)) 個模型")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(DashboardTheme.mutedInk)
            }

            if viewModel.sortedModelPrices.isEmpty {
                ModelPriceSettingsEmptyState()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.sortedModelPrices.prefix(5).enumerated()), id: \.element.id) { index, price in
                        ModelPriceDenseRow(
                            price: price,
                            inputText: viewModel.formattedPricePerMillion(price.promptPricePerMillion),
                            outputText: viewModel.formattedPricePerMillion(price.completionPricePerMillion),
                            cacheText: viewModel.formattedPricePerMillion(price.cachePricePerMillion),
                            rowIndex: index,
                            isSelected: editingModel == price.model,
                            edit: { edit(price) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func editorLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .black, design: .monospaced))
            .foregroundStyle(DashboardTheme.softInk)
            .tracking(1.2)
    }

    private var canSaveDraft: Bool {
        !draft.sanitizedPrice.model.isEmpty
    }

    private var isDraftUnsaved: Bool {
        canSaveDraft && viewModel.hasUnsavedModelPriceDraft(draft)
    }

    private var draft: ModelPriceDraft {
        ModelPriceDraft(
            model: draftModel,
            promptPricePerMillion: draftPromptPrice,
            completionPricePerMillion: draftCompletionPrice,
            cachePricePerMillion: draftCachePrice
        )
    }

    private func saveDraft() {
        guard canSaveDraft else {
            return
        }
        viewModel.saveModelPriceDraft(draft)
        editingModel = draft.sanitizedPrice.model
    }

    private func edit(_ price: ModelPriceSetting) {
        draftModel = price.model
        draftPromptPrice = price.promptPricePerMillion
        draftCompletionPrice = price.completionPricePerMillion
        draftCachePrice = price.cachePricePerMillion
        editingModel = price.model
    }

    private func loadInitialDraftIfNeeded() {
        guard editingModel == nil, draftModel.isEmpty else {
            return
        }
        guard let initialPrice = preferredInitialPrice else {
            if let firstModel = viewModel.priceModelOptions.first {
                draftModel = firstModel
            }
            return
        }
        edit(initialPrice)
    }

    private var preferredInitialPrice: ModelPriceSetting? {
        if let gpt51 = viewModel.sortedModelPrices.first(where: { price in
            let normalized = price.model.lowercased()
            return normalized.contains("gpt-5.1") && !normalized.contains("mini")
        }) {
            return gpt51
        }
        return viewModel.sortedModelPrices.first
    }

    private func modelSwatchColor(for model: String) -> Color {
        let options = viewModel.priceModelOptions
        if let index = options.firstIndex(of: model) {
            return DashboardTheme.accent(index)
        }
        return DashboardTheme.purple
    }
}

private struct PriceFieldBlock: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .foregroundStyle(DashboardTheme.softInk)
                .tracking(1.2)
                .lineLimit(1)

            HStack(spacing: 10) {
                Text("$")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(DashboardTheme.softInk)

                TextField(
                    "0.00",
                    value: $value,
                    format: .number.precision(.fractionLength(4))
                )
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .textFieldStyle(.plain)

                Text("/M")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(DashboardTheme.softInk)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DashboardTheme.panelRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DashboardTheme.hairline, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ModelPriceDenseRow: View {
    let price: ModelPriceSetting
    let inputText: String
    let outputText: String
    let cacheText: String
    let rowIndex: Int
    let isSelected: Bool
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(DashboardTheme.accent(rowIndex))
                    .frame(width: 12, height: 12)
                Text(price.model)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(DashboardTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ModelPriceNumericCell(inputText)
                .frame(width: 86)
            ModelPriceNumericCell(outputText)
                .frame(width: 86)
            ModelPriceNumericCell(cacheText)
                .frame(width: 82)

            Button(action: edit) {
                Image(systemName: isSelected ? "bolt.fill" : "checkmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(isSelected ? DashboardTheme.orange : DashboardTheme.green)
            .help("選擇")
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 42, alignment: .trailing)
        }
        .font(.system(size: 16, weight: .medium, design: .rounded))
        .foregroundStyle(DashboardTheme.mutedInk)
        .padding(.horizontal, 10)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? DashboardTheme.yellowSoft.opacity(0.52) : Color.clear)
        )
    }
}

private struct ModelPriceNumericCell: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value.replacingOccurrences(of: " / 1M", with: ""))
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct ModelPriceSettingsEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "dollarsign.square")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("暂无已保存价格")
                .font(.headline)
            Text("保存模型价格后，成本指标和趋势会重新计算。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}
