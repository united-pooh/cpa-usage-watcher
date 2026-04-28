import Foundation

enum UsageExportServiceTests {
    static func run() throws {
        try verifiesMaskedCSVAndJSONExports()
    }

    private static func verifiesMaskedCSVAndJSONExports() throws {
        let event = RequestEvent(
            id: "event-1",
            timestamp: Date(timeIntervalSince1970: 0),
            endpoint: "endpoint-secret-123456",
            model: "claude-haiku",
            source: "alex@example.com",
            provider: "claude",
            authIndex: "auth-secret-654321",
            isSuccess: true,
            statusCode: 200,
            errorMessage: "credential alex@example.com failed for endpoint-secret-123456 using auth-secret-654321",
            latencyMs: 125,
            inputTokens: 10,
            outputTokens: 20,
            reasoningTokens: 3,
            cachedTokens: 4,
            totalTokens: 37
        )

        let rawCSV = UsageExportService.csvString(for: [event])
        if !rawCSV.contains("endpoint-secret-123456") || !rawCSV.contains("auth-secret-654321") {
            TestExpect.fail("unmasked CSV export should preserve raw sensitive identifiers")
        }

        let maskedCSV = UsageExportService.csvString(for: [event], masked: true)
        if maskedCSV.contains("endpoint-secret-123456") || maskedCSV.contains("auth-secret-654321") {
            TestExpect.fail("masked CSV export should not leak raw sensitive identifiers")
        }
        if !maskedCSV.contains("endp") || !maskedCSV.contains("4321") {
            TestExpect.fail("masked CSV export should preserve stable outer context")
        }

        let maskedJSON = String(
            decoding: try UsageExportService.jsonData(for: [event], masked: true),
            as: UTF8.self
        )
        if maskedJSON.contains("alex@example.com") ||
            maskedJSON.contains("auth-secret-654321") ||
            maskedJSON.contains("endpoint-secret-123456") {
            TestExpect.fail("masked JSON export should not leak raw sensitive identifiers")
        }
        if !maskedJSON.contains("al") || !maskedJSON.contains("4321") {
            TestExpect.fail("masked JSON export should preserve recognizable masked values")
        }
    }
}
