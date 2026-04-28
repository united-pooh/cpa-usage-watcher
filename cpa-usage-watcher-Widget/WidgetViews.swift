import SwiftUI
import WidgetKit

private struct WidgetProgressBar: View {
    let segments: [(Double, Color)]
    let tint: Color

    private var active: [(Double, Color)] { segments.filter { $0.0 > 0 } }
    private var total: Double { active.reduce(0) { $0 + $1.0 } }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetTheme.paperDeep)
                if total > 0 {
                    HStack(spacing: 1) {
                        ForEach(Array(active.enumerated()), id: \.offset) { _, seg in
                            RoundedRectangle(cornerRadius: 999)
                                .fill(seg.1)
                                .frame(width: max(4, geo.size.width * seg.0 / total))
                        }
                    }
                    .clipShape(Capsule())
                } else {
                    Capsule().fill(tint.opacity(0.32)).frame(width: 12)
                }
            }
        }
        .frame(height: 4)
    }
}

private struct WidgetHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(WidgetTheme.softInk)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetTheme.softInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint.opacity(0.82))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(0.13))
                )
        }
    }
}

private struct BadgeLabel: View {
    let text: String
    let foreground: Color
    let background: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(background))
    }
}

struct TotalRequestsWidgetView: View {
    let entry: CpaWidgetEntry
    private var s: WidgetSnapshot { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "總請求數", subtitle: "リクエスト総数", icon: "sparkle", tint: WidgetTheme.orange)

            Spacer(minLength: 6)

            Text(wCompact(s.totalRequests))
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Spacer(minLength: 4)

            HStack(alignment: .center, spacing: 8) {
                BadgeLabel(
                    text: s.hasLiveData ? "LIVE" : "─",
                    foreground: s.hasLiveData ? WidgetTheme.green : WidgetTheme.mutedInk,
                    background: s.hasLiveData ? WidgetTheme.greenSoft : WidgetTheme.paperDeep
                )
                Text("RPM  \(Int(s.rpm.rounded()))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetTheme.mutedInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            WidgetProgressBar(
                segments: [
                    (Double(s.successfulRequests), WidgetTheme.green),
                    (Double(s.failedRequests), WidgetTheme.red)
                ],
                tint: WidgetTheme.orange
            )
        }
        .padding(12)
        .containerBackground(WidgetTheme.cream, for: .widget)
    }
}

struct TotalTokensWidgetView: View {
    let entry: CpaWidgetEntry
    private var s: WidgetSnapshot { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "總 TOKEN", subtitle: "トークン総数", icon: "bolt", tint: WidgetTheme.blue)

            Spacer(minLength: 6)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(wCompact(s.totalTokens))
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("tk")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(WidgetTheme.mutedInk)
            }

            Spacer(minLength: 4)

            HStack(alignment: .center, spacing: 8) {
                BadgeLabel(
                    text: s.hasLiveData ? "LIVE" : "─",
                    foreground: s.hasLiveData ? WidgetTheme.green : WidgetTheme.mutedInk,
                    background: s.hasLiveData ? WidgetTheme.greenSoft : WidgetTheme.paperDeep
                )
                Text("TPM  \(wCompact(s.tpm))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetTheme.mutedInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            WidgetProgressBar(
                segments: [
                    (Double(s.inputTokens), WidgetTheme.orange),
                    (Double(s.outputTokens), WidgetTheme.blue),
                    (Double(s.cachedTokens), WidgetTheme.yellow),
                    (Double(s.reasoningTokens), WidgetTheme.purple)
                ],
                tint: WidgetTheme.blue
            )
        }
        .padding(12)
        .containerBackground(WidgetTheme.cream, for: .widget)
    }
}

struct ThroughputWidgetView: View {
    let entry: CpaWidgetEntry
    private var s: WidgetSnapshot { entry.snapshot }

    private var latencyText: String {
        let ms = s.averageLatencyMs
        guard ms > 0 else { return "0ms" }
        if ms < 1000 { return "\(Int(ms.rounded()))ms" }
        return String(format: "%.1fs", ms / 1000)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "RPM / TPM", subtitle: "毎分のレート", icon: "arrow.clockwise", tint: WidgetTheme.blue)

            Spacer(minLength: 6)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(Int(s.rpm.rounded()))")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("/min")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetTheme.mutedInk)
            }

            Spacer(minLength: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("TPM  \(wCompact(s.tpm))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetTheme.mutedInk)
                    .lineLimit(1)
                Text("avg \(latencyText)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetTheme.softInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            WidgetProgressBar(
                segments: [
                    (s.rpm, WidgetTheme.blue),
                    (s.tpm / max(1, s.tpm / max(1, s.rpm)), WidgetTheme.yellow)
                ],
                tint: WidgetTheme.blue
            )
        }
        .padding(12)
        .containerBackground(WidgetTheme.cream, for: .widget)
    }
}

struct CacheThinkingWidgetView: View {
    let entry: CpaWidgetEntry
    private var s: WidgetSnapshot { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "緩存 / 思考", subtitle: "キャッシュ · 思考", icon: "cylinder.split.1x2", tint: WidgetTheme.yellow)

            Spacer(minLength: 6)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(wCompact(s.cachedTokens))
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("+\(wCompact(s.reasoningTokens))")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(WidgetTheme.mutedInk)
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("緩存命中")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                    Text(s.cacheRatioText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(WidgetTheme.blueDeep)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(WidgetTheme.blueSoft))

                VStack(alignment: .leading, spacing: 1) {
                    Text("思考")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                    Text(s.reasoningRatioText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(Color(red: 0.528, green: 0.374, blue: 0.030))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(WidgetTheme.yellowSoft))
            }

            Spacer(minLength: 6)

            WidgetProgressBar(
                segments: [
                    (Double(s.cachedTokens), WidgetTheme.blue),
                    (Double(s.reasoningTokens), WidgetTheme.yellow),
                    (Double(s.inputTokens + s.outputTokens), WidgetTheme.paperDeep)
                ],
                tint: WidgetTheme.yellow
            )
        }
        .padding(12)
        .containerBackground(WidgetTheme.cream, for: .widget)
    }
}

struct TotalCostWidgetView: View {
    let entry: CpaWidgetEntry
    private var s: WidgetSnapshot { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "總花費", subtitle: "合計コスト", icon: "yensign", tint: WidgetTheme.orange)

            Spacer(minLength: 6)

            Text(s.costFormatted)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.42)

            Spacer(minLength: 4)

            HStack(alignment: .center, spacing: 8) {
                BadgeLabel(
                    text: s.costBasisTitle,
                    foreground: WidgetTheme.mutedInk,
                    background: WidgetTheme.paperDeep
                )
                VStack(alignment: .leading, spacing: 0) {
                    Text("每千次")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(WidgetTheme.softInk)
                    Text(s.avgCostPerKFormatted)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(WidgetTheme.mutedInk)
                }
            }

            Spacer(minLength: 6)

            WidgetProgressBar(
                segments: [
                    (s.hasCostData ? 1 : 0, WidgetTheme.orange),
                    (0.15, WidgetTheme.purple)
                ],
                tint: WidgetTheme.orange
            )
        }
        .padding(12)
        .containerBackground(WidgetTheme.cream, for: .widget)
    }
}
