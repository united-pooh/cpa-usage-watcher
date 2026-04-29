import SwiftUI

// MARK: - Quota Data Model

/// A provider-agnostic quota/limit parsed from credential or request metadata.
/// GROUP-1 may add CredentialQuotaSnapshot; until then, this model parses from JSONValue metadata.
nonisolated struct CredentialQuotaItem: Identifiable {
    let id: String
    /// Display label, e.g. "RPM", "TPM", "Daily Tokens", "Monthly Budget"
    let label: String
    /// Current usage value
    let used: Double
    /// Limit value (if available)
    let limit: Double?
    /// Optional unit string, e.g. "req/min", "tokens", "USD"
    let unit: String?
    /// Whether this quota is inverted (lower = worse), e.g. remaining credits
    let isRemaining: Bool

    static func items(from snapshot: CredentialQuotaSnapshot) -> [CredentialQuotaItem] {
        [snapshot.shortWindow, snapshot.longWindow]
            .compactMap { $0 }
            .map { usage in
                CredentialQuotaItem(
                    id: usage.id,
                    label: usage.title,
                    used: usage.used ?? usage.usagePercent.map { $0 * (usage.limit ?? 100) } ?? 0,
                    limit: usage.limit,
                    unit: nil,
                    isRemaining: false
                )
            }
    }

    var fraction: Double? {
        guard let limit, limit > 0 else { return nil }
        let base = isRemaining ? (limit - used) / limit : used / limit
        return max(0, min(1, base))
    }

    var displayUsed: String {
        if used >= 1_000_000 {
            return String(format: "%.1fM", used / 1_000_000)
        }
        if used >= 1_000 {
            return String(format: "%.1fK", used / 1_000)
        }
        return String(format: "%.0f", used)
    }

    var displayLimit: String? {
        guard let limit else { return nil }
        if limit >= 1_000_000 {
            return String(format: "%.1fM", limit / 1_000_000)
        }
        if limit >= 1_000 {
            return String(format: "%.1fK", limit / 1_000)
        }
        return String(format: "%.0f", limit)
    }

    /// StatusTone based on fill fraction (warn at 80%, danger at 95%)
    var tone: DashboardStatusTone {
        guard let fraction else { return .neutral }
        if fraction >= 0.95 { return .danger }
        if fraction >= 0.80 { return .warning }
        return .success
    }
}

// MARK: - Quota Parser

/// Parses quota-like key/value pairs from JSONValue metadata.
/// Works with any provider that embeds quota or rate-limit fields.
enum CredentialQuotaParser {
    // Common quota field name sets (provider-agnostic)
    private static let usedSuffixes = ["used", "count", "current", "consumed", "spent"]
    private static let limitSuffixes = ["limit", "max", "total", "allowed", "quota"]
    private static let remainingSuffixes = ["remaining", "left", "available", "balance", "remaining_requests", "remaining_tokens"]

    private static let knownQuotaRoots = [
        "quota", "quotas", "rate_limit", "rate_limits", "rateLimits",
        "usage_limits", "usageLimits", "limits", "credits", "allowance",
        "billing", "plan", "subscription"
    ]

    static func parse(from metadata: [String: JSONValue]) -> [CredentialQuotaItem] {
        var items: [CredentialQuotaItem] = []

        // 1. Look for top-level quota containers
        for rootKey in knownQuotaRoots {
            if let quotaObject = metadata.value(anyOf: [rootKey])?.object {
                items.append(contentsOf: parseQuotaObject(quotaObject, prefix: labelFromKey(rootKey)))
            }
        }

        // 2. Look for paired keys like rpm_used/rpm_limit, tokens_used/tokens_limit
        items.append(contentsOf: parsePairedKeys(from: metadata))

        // 3. Look for remaining_* keys (common in OpenAI-style headers embedded in metadata)
        items.append(contentsOf: parseRemainingKeys(from: metadata))

        // Deduplicate by id
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private static func parseQuotaObject(_ object: [String: JSONValue], prefix: String) -> [CredentialQuotaItem] {
        var items: [CredentialQuotaItem] = []

        // Direct numeric values in quota object
        for (key, value) in object {
            guard let number = value.double else { continue }
            let label = prefix.isEmpty ? labelFromKey(key) : "\(prefix) · \(labelFromKey(key))"
            items.append(CredentialQuotaItem(
                id: "quota-\(prefix)-\(key)",
                label: label,
                used: number,
                limit: nil,
                unit: unitFromKey(key),
                isRemaining: isRemainingKey(key)
            ))
        }

        // Paired used/limit in sub-objects
        for (key, value) in object {
            guard let subObj = value.object else { continue }
            items.append(contentsOf: parseQuotaSubObject(subObj, key: key, prefix: prefix))
        }

        // Paired keys within this same object level
        items.append(contentsOf: parsePairedKeys(from: object, prefix: prefix))

        return items
    }

    private static func parseQuotaSubObject(
        _ object: [String: JSONValue],
        key: String,
        prefix: String
    ) -> [CredentialQuotaItem] {
        let label = "\(prefix.isEmpty ? "" : "\(prefix) · ")\(labelFromKey(key))"

        if let used = firstDouble(in: object, suffixes: usedSuffixes),
           let limit = firstDouble(in: object, suffixes: limitSuffixes), limit > 0 {
            return [CredentialQuotaItem(
                id: "quota-\(prefix)-\(key)-pair",
                label: label,
                used: used,
                limit: limit,
                unit: unitFromKey(key),
                isRemaining: false
            )]
        }

        if let remaining = firstDouble(in: object, suffixes: remainingSuffixes),
           let limit = firstDouble(in: object, suffixes: limitSuffixes), limit > 0 {
            return [CredentialQuotaItem(
                id: "quota-\(prefix)-\(key)-remaining",
                label: label,
                used: limit - remaining,
                limit: limit,
                unit: unitFromKey(key),
                isRemaining: false
            )]
        }

        return []
    }

    private static func parsePairedKeys(
        from object: [String: JSONValue],
        prefix: String = ""
    ) -> [CredentialQuotaItem] {
        var items: [CredentialQuotaItem] = []
        let keys = Set(object.keys.map { $0.lowercased() })

        // Find keys that match pattern: <name>_used / <name>_limit
        for suffix in usedSuffixes {
            let matchingKeys = object.keys.filter { $0.lowercased().hasSuffix("_\(suffix)") || $0.lowercased().hasSuffix("\(suffix)") }
            for usedKey in matchingKeys {
                guard let usedVal = object[usedKey]?.double else { continue }
                let base = String(usedKey.dropLast(suffix.count + 1)) // e.g. "rpm"
                // Try to find a matching limit key
                let limitCandidates = limitSuffixes.flatMap { ls in ["\(base)_\(ls)", "\(base)\(ls.capitalized)"] }
                if let limitVal = firstDouble(in: object, keys: limitCandidates), limitVal > 0 {
                    let label = labelFromKey(base)
                    let fullLabel = prefix.isEmpty ? label : "\(prefix) · \(label)"
                    items.append(CredentialQuotaItem(
                        id: "\(prefix)-paired-\(usedKey)",
                        label: fullLabel,
                        used: usedVal,
                        limit: limitVal,
                        unit: unitFromKey(base),
                        isRemaining: false
                    ))
                }
            }
        }
        _ = keys
        return items
    }

    private static func parseRemainingKeys(from object: [String: JSONValue]) -> [CredentialQuotaItem] {
        var items: [CredentialQuotaItem] = []

        for suffix in remainingSuffixes {
            let matchingKeys = object.keys.filter { $0.lowercased().contains(suffix) }
            for key in matchingKeys {
                guard let remainingVal = object[key]?.double else { continue }
                // Try to find total
                let base = key.lowercased().replacingOccurrences(of: suffix, with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
                let limitCandidates = limitSuffixes.flatMap { ls in ["\(base)_\(ls)", "\(base)\(ls.capitalized)", "\(base)limit"] }
                let limit = firstDouble(in: object, keys: limitCandidates)

                items.append(CredentialQuotaItem(
                    id: "remaining-\(key)",
                    label: labelFromKey(key),
                    used: remainingVal,
                    limit: limit,
                    unit: unitFromKey(base),
                    isRemaining: true
                ))
            }
        }

        return items
    }

    // MARK: Helpers

    private static func firstDouble(in object: [String: JSONValue], suffixes: [String]) -> Double? {
        for suffix in suffixes {
            for (key, value) in object {
                if key.lowercased().hasSuffix(suffix), let d = value.double { return d }
            }
        }
        return nil
    }

    private static func firstDouble(in object: [String: JSONValue], keys: [String]) -> Double? {
        for key in keys {
            for (k, v) in object where k.lowercased() == key.lowercased() {
                if let d = v.double { return d }
            }
        }
        return nil
    }

    private static func isRemainingKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        return remainingSuffixes.contains(where: { lower.contains($0) })
    }

    private static func labelFromKey(_ key: String) -> String {
        // Convert snake_case / camelCase to readable title
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        // Insert space before capital letters (camelCase)
        var result = ""
        for (i, c) in spaced.enumerated() {
            if c.isUppercase, i > 0, result.last != " " {
                result += " "
            }
            result.append(c)
        }
        return result
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private static func unitFromKey(_ key: String) -> String? {
        let lower = key.lowercased()
        if lower.contains("rpm") || lower.contains("req") || lower.contains("request") { return "req/min" }
        if lower.contains("tpm") || lower.contains("token") { return "tok/min" }
        if lower.contains("usd") || lower.contains("dollar") || lower.contains("budget") || lower.contains("credit") { return "USD" }
        if lower.contains("cny") || lower.contains("yuan") { return "CNY" }
        if lower.contains("context") { return "ctx" }
        return nil
    }
}

// MARK: - Quota Card View

struct CredentialQuotaCardView: View {
    let items: [CredentialQuotaItem]
    let providerLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Provider badge
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DashboardTheme.orange)
                Text(providerLabel.isEmpty ? "QUOTA" : providerLabel.uppercased())
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(DashboardTheme.mutedInk)
                    .tracking(1.2)
            }

            // Grid of quota items (2-column)
            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(items.prefix(6)) { item in
                    QuotaMiniCard(item: item)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DashboardTheme.compactRadius, style: .continuous)
                .fill(DashboardTheme.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.compactRadius, style: .continuous)
                .stroke(DashboardTheme.strongHairline.opacity(0.6), lineWidth: 1)
        )
    }
}

// MARK: - Mini Quota Card

private struct QuotaMiniCard: View {
    let item: CredentialQuotaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Label
            Text(item.label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(DashboardTheme.mutedInk)
                .lineLimit(1)
                .truncationMode(.tail)

            // Value row
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(item.displayUsed)
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundStyle(DashboardTheme.ink)
                    .lineLimit(1)

                if let displayLimit = item.displayLimit {
                    Text("/ \(displayLimit)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(DashboardTheme.softInk)
                        .lineLimit(1)
                }

                if let unit = item.unit {
                    Text(unit)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(DashboardTheme.softInk)
                        .lineLimit(1)
                }
            }

            // Progress bar
            if let fraction = item.fraction {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(DashboardTheme.paperDeep)
                        Capsule(style: .continuous)
                            .fill(barColor(fraction: fraction))
                            .frame(width: max(4, proxy.size.width * fraction))
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DashboardTheme.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(DashboardTheme.hairline, lineWidth: 1)
        )
    }

    private func barColor(fraction: Double) -> Color {
        if fraction >= 0.95 { return DashboardTheme.red }
        if fraction >= 0.80 { return DashboardTheme.yellow }
        return DashboardTheme.green
    }
}
