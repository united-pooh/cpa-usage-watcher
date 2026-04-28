import Foundation

@MainActor
enum UsageAPIClientTests {
    static func run() async throws {
        try await verifiesOriginBaseURLUsesManagementPath()
        try verifiesExplicitManagementBaseURLIsPreserved()
        try verifiesManagementPageURLUsesManagementPath()
        try await verifiesImportAndExportRequestConstruction()
    }

    private static func verifiesOriginBaseURLUsesManagementPath() async throws {
        let performer = MockUsageRequestPerformer(data: Data(#"{"usageDetails":[]}"#.utf8))
        let client = UsageAPIClient(requestPerformer: performer)
        let settings = ConnectionSettings(baseURL: "http://127.0.0.1:8317", managementKey: "test-management-key")

        _ = try await client.fetchUsage(settings: settings, timeRange: .last24Hours)

        let request = try performer.lastRequest()
        TestExpect.equal(request.url?.absoluteString, "http://127.0.0.1:8317/v0/management/usage?range=24h", "origin base should normalize to management usage path")
        TestExpect.equal(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-management-key", "management key auth header")
        TestExpect.equal(request.httpMethod, "GET", "fetch method")
    }

    private static func verifiesExplicitManagementBaseURLIsPreserved() throws {
        let client = UsageAPIClient()
        let url = try client.makeURL(
            baseURL: "http://127.0.0.1:8317/v0/management",
            path: "usage/export"
        )

        TestExpect.equal(url.absoluteString, "http://127.0.0.1:8317/v0/management/usage/export", "explicit management base")
    }

    private static func verifiesManagementPageURLUsesManagementPath() throws {
        let client = UsageAPIClient()
        let url = try client.makeURL(
            baseURL: "http://127.0.0.1:8317/management.html#/usage",
            path: "usage"
        )

        TestExpect.equal(url.absoluteString, "http://127.0.0.1:8317/v0/management/usage", "management page URL should normalize to API base")
    }

    private static func verifiesImportAndExportRequestConstruction() async throws {
        let performer = MockUsageRequestPerformer(data: Data(#"{"message":"ok","imported":2}"#.utf8))
        let client = UsageAPIClient(requestPerformer: performer)
        let settings = ConnectionSettings(baseURL: "http://localhost:8317/v0/management/", managementKey: "secret")

        _ = try await client.importUsage(Data(#"{"usageDetails":[]}"#.utf8), settings: settings)
        let importRequest = try performer.lastRequest()
        TestExpect.equal(importRequest.url?.absoluteString, "http://localhost:8317/v0/management/usage/import", "import URL")
        TestExpect.equal(importRequest.httpMethod, "POST", "import method")
        TestExpect.equal(importRequest.value(forHTTPHeaderField: "Content-Type"), "application/json", "import content type")

        performer.data = Data("{}".utf8)
        _ = try await client.exportUsage(settings: settings)
        let exportRequest = try performer.lastRequest()
        TestExpect.equal(exportRequest.url?.absoluteString, "http://localhost:8317/v0/management/usage/export", "export URL")
        TestExpect.equal(exportRequest.httpMethod, "GET", "export method")
        TestExpect.equal(exportRequest.value(forHTTPHeaderField: "Accept"), "application/json", "toolbar export should request JSON")
    }
}

@MainActor
private final class MockUsageRequestPerformer: UsageRequestPerforming {
    var data: Data
    private(set) var requests: [URLRequest] = []

    init(data: Data) {
        self.data = data
    }

    func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://localhost")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }

    func lastRequest() throws -> URLRequest {
        guard let request = requests.last else {
            throw TestFailure("Expected a captured request")
        }
        return request
    }
}
