import Foundation

protocol UsageRequestPerforming {
    func perform(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: UsageRequestPerforming {
    func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

enum UsageAPIClientError: LocalizedError {
    case invalidBaseURL(String)
    case missingManagementKey
    case invalidResponse
    case httpStatus(Int, String)
    case timedOut(TimeInterval)
    case decodingFailed(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case let .invalidBaseURL(value):
            return "连接地址无效：\(value)"
        case .missingManagementKey:
            return "请先填写管理密钥。"
        case .invalidResponse:
            return "服务返回了无法识别的响应。"
        case let .httpStatus(statusCode, message):
            return "服务请求失败（HTTP \(statusCode)）：\(message)"
        case let .timedOut(timeout):
            return "服务请求超时（\(Int(timeout))秒）。"
        case let .decodingFailed(message):
            return "使用数据解析失败：\(message)"
        case let .transport(message):
            return "服务连接失败：\(message)"
        }
    }
}

final class UsageAPIClient {
    private static let defaultManagementPath = "/v0/management"

    private let requestPerformer: UsageRequestPerforming
    private let timeoutInterval: TimeInterval
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        requestPerformer: UsageRequestPerforming = URLSession.shared,
        timeoutInterval: TimeInterval = 15,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.requestPerformer = requestPerformer
        self.timeoutInterval = timeoutInterval
        self.decoder = decoder
        self.encoder = encoder
    }

    func fetchUsage(
        settings: ConnectionSettings,
        timeRange: UsageTimeRange? = nil
    ) async throws -> UsageRawPayload {
        let queryItems = timeRange.map { [URLQueryItem(name: "range", value: $0.queryValue)] } ?? []
        let request = try makeRequest(
            settings: settings,
            path: "usage",
            method: "GET",
            queryItems: queryItems,
            accept: "application/json"
        )

        let data = try await performDataRequest(request)
        return try decodeRawPayload(from: data)
    }

    func exportUsage(settings: ConnectionSettings) async throws -> Data {
        let request = try makeRequest(
            settings: settings,
            path: "usage/export",
            method: "GET",
            accept: "application/json"
        )

        return try await performDataRequest(request)
    }

    func importUsage(
        _ data: Data,
        settings: ConnectionSettings,
        contentType: String = "application/json"
    ) async throws -> UsageImportResult {
        let request = try makeRequest(
            settings: settings,
            path: "usage/import",
            method: "POST",
            body: data,
            accept: "application/json, text/plain, */*",
            contentType: contentType
        )

        let responseData = try await performDataRequest(request)
        return try decodeImportResult(from: responseData)
    }

    func importUsage(
        payload: UsageRawPayload,
        settings: ConnectionSettings
    ) async throws -> UsageImportResult {
        let data = try encoder.encode(payload)
        return try await importUsage(data, settings: settings, contentType: "application/json")
    }

    static func normalizedBaseURL(from rawValue: String) throws -> URL {
        var trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw UsageAPIClientError.invalidBaseURL(rawValue)
        }

        if !trimmed.contains("://") {
            trimmed = "http://\(trimmed)"
        }

        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty else {
            throw UsageAPIClientError.invalidBaseURL(rawValue)
        }

        components.scheme = scheme
        components.query = nil
        components.fragment = nil

        var path = components.percentEncodedPath
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        if path == "/management.html" {
            path = defaultManagementPath
        }
        components.percentEncodedPath = path.isEmpty || path == "/" ? defaultManagementPath : path

        guard let url = components.url else {
            throw UsageAPIClientError.invalidBaseURL(rawValue)
        }
        return url
    }

    func makeURL(
        baseURL rawBaseURL: String,
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        let baseURL = try Self.normalizedBaseURL(from: rawBaseURL)
        var url = baseURL

        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component))
        }

        guard !queryItems.isEmpty else {
            return url
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw UsageAPIClientError.invalidBaseURL(rawBaseURL)
        }
        components.queryItems = (components.queryItems ?? []) + queryItems

        guard let finalURL = components.url else {
            throw UsageAPIClientError.invalidBaseURL(rawBaseURL)
        }
        return finalURL
    }

    private func makeRequest(
        settings: ConnectionSettings,
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        accept: String,
        contentType: String? = nil
    ) throws -> URLRequest {
        let managementKey = settings.managementKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !managementKey.isEmpty else {
            throw UsageAPIClientError.missingManagementKey
        }

        let url = try makeURL(baseURL: settings.baseURL, path: path, queryItems: queryItems)
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(managementKey)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")

        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func performDataRequest(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await requestPerformer.perform(request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw UsageAPIClientError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw UsageAPIClientError.httpStatus(
                    httpResponse.statusCode,
                    Self.errorMessage(from: data)
                )
            }

            return data
        } catch let error as UsageAPIClientError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw UsageAPIClientError.timedOut(timeoutInterval)
        } catch {
            throw UsageAPIClientError.transport(error.localizedDescription)
        }
    }

    private func decodeRawPayload(from data: Data) throws -> UsageRawPayload {
        guard !data.isEmpty else {
            return UsageRawPayload()
        }

        do {
            return try decoder.decode(UsageRawPayload.self, from: data)
        } catch {
            throw UsageAPIClientError.decodingFailed(error.localizedDescription)
        }
    }

    private func decodeImportResult(from data: Data) throws -> UsageImportResult {
        guard !data.isEmpty else {
            return UsageImportResult(message: "导入已提交")
        }

        if let rawPayload = try? decoder.decode(UsageRawPayload.self, from: data) {
            guard let object = rawPayload.root.object else {
                return UsageImportResult(message: "导入已完成", rawPayload: rawPayload)
            }

            let message = object.optionalString(for: "message", "detail", "status") ?? "导入已完成"
            return UsageImportResult(
                importedCount: object.int(for: "importedCount", "imported", "inserted", "count"),
                skippedCount: object.int(for: "skippedCount", "skipped", "ignored"),
                message: message,
                rawPayload: rawPayload
            )
        }

        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return UsageImportResult(message: text)
        }

        throw UsageAPIClientError.decodingFailed("导入响应不是有效的 JSON 或文本。")
    }

    private static func errorMessage(from data: Data) -> String {
        if let payload = try? JSONDecoder().decode(UsageRawPayload.self, from: data),
           let object = payload.root.object,
           let message = object.optionalString(for: "message", "error", "detail"),
           !message.isEmpty {
            return message
        }

        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }

        return "无错误详情"
    }
}
