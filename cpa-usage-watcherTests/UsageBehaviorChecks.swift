import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

enum TestExpect {
    static func equal<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual != expected {
            fail("\(message): expected \(expected), got \(actual)")
        }
    }

    static func approx(_ actual: Double, _ expected: Double, _ message: String, tolerance: Double = 0.000001) {
        if abs(actual - expected) > tolerance {
            fail("\(message): expected \(expected), got \(actual)")
        }
    }

    static func fail(_ message: String) -> Never {
        fatalError("Test failure: \(message)")
    }
}

@main
@MainActor
enum UsageBehaviorChecks {
    static func main() async throws {
        try UsageAggregatorTests.run()
        try await UsageAPIClientTests.run()
        try UsageExportServiceTests.run()
        try UsagePreferencesStoreTests.run()
        try UsageSQLiteStoreTests.run()
        try await UsageDashboardViewModelTests.run()
        print("Usage behavior checks passed")
    }
}
