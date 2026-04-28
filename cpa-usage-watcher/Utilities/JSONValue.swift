import Foundation

nonisolated enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(any value: Any?) {
        switch value {
        case nil:
            self = .null
        case is NSNull:
            self = .null
        case let value as JSONValue:
            self = value
        case let value as String:
            self = .string(value)
        case let value as Bool:
            self = .bool(value)
        case let value as Int:
            self = .number(Double(value))
        case let value as Int64:
            self = .number(Double(value))
        case let value as Double:
            self = .number(value)
        case let value as Decimal:
            self = .number(NSDecimalNumber(decimal: value).doubleValue)
        case let value as [Any?]:
            self = .array(value.map(JSONValue.init(any:)))
        case let value as [String: Any?]:
            self = .object(value.mapValues(JSONValue.init(any:)))
        case let value as [String: Any]:
            self = .object(value.mapValues(JSONValue.init(any:)))
        default:
            self = .string(String(describing: value!))
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            let object = try container.decode([String: JSONValue].self)
            self = .object(object)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var rawValue: Any {
        switch self {
        case let .string(value):
            return value
        case let .number(value):
            return value
        case let .bool(value):
            return value
        case let .object(value):
            var object: [String: Any] = [:]
            for (key, jsonValue) in value {
                object[key] = jsonValue.rawValue
            }
            return object
        case let .array(value):
            return value.map(\.rawValue)
        case .null:
            return NSNull()
        }
    }

    var isNull: Bool {
        if case .null = self {
            return true
        }
        return false
    }

    var object: [String: JSONValue]? {
        if case let .object(value) = self {
            return value
        }
        return nil
    }

    var array: [JSONValue]? {
        if case let .array(value) = self {
            return value
        }
        return nil
    }

    var string: String? {
        switch self {
        case let .string(value):
            value
        case let .number(value):
            if value.rounded(.towardZero) == value,
               value >= Double(Int64.min),
               value <= Double(Int64.max) {
                String(Int64(value))
            } else {
                String(value)
            }
        case let .bool(value):
            value ? "true" : "false"
        default:
            nil
        }
    }

    var double: Double? {
        switch self {
        case let .number(value):
            value
        case let .string(value):
            Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            nil
        }
    }

    var int: Int? {
        switch self {
        case let .number(value):
            return Int(value.rounded())
        case let .string(value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let integer = Int(trimmed) {
                return integer
            }
            return Double(trimmed).map { Int($0.rounded()) }
        default:
            return nil
        }
    }

    var bool: Bool? {
        switch self {
        case let .bool(value):
            return value
        case let .string(value):
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1", "true", "yes", "y", "on", "success", "ok", "succeeded"].contains(normalized) {
                return true
            }
            if ["0", "false", "no", "n", "off", "failed", "failure", "error"].contains(normalized) {
                return false
            }
            return nil
        case let .number(value):
            return value != 0
        default:
            return nil
        }
    }

    subscript(key: String) -> JSONValue? {
        object?.value(for: key)
    }

    subscript(index: Int) -> JSONValue? {
        guard let array, array.indices.contains(index) else {
            return nil
        }
        return array[index]
    }

    func value(at path: String...) -> JSONValue? {
        value(at: path)
    }

    func value(at path: [String]) -> JSONValue? {
        var current: JSONValue? = self

        for component in path {
            guard let object = current?.object,
                  let next = object.value(for: component) else {
                return nil
            }
            current = next
        }

        return current
    }
}

nonisolated extension Dictionary where Key == String, Value == JSONValue {
    private static func normalizedLookupKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    func value(for candidates: String...) -> JSONValue? {
        value(anyOf: candidates)
    }

    func value(anyOf candidates: [String]) -> JSONValue? {
        for candidate in candidates {
            if let exact = self[candidate] {
                return exact
            }

            if let matched = first(where: { $0.key.lowercased() == candidate.lowercased() })?.value {
                return matched
            }

            let normalizedCandidate = Self.normalizedLookupKey(candidate)
            if let matched = first(where: { Self.normalizedLookupKey($0.key) == normalizedCandidate })?.value {
                return matched
            }
        }

        return nil
    }

    func object(for candidates: String...) -> [String: JSONValue]? {
        value(anyOf: candidates)?.object
    }

    func array(for candidates: String...) -> [JSONValue]? {
        value(anyOf: candidates)?.array
    }

    func optionalString(for candidates: String...) -> String? {
        optionalString(anyOf: candidates)
    }

    func optionalString(anyOf candidates: [String]) -> String? {
        value(anyOf: candidates)?
            .string?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func string(for candidates: String..., default defaultValue: String = "") -> String {
        optionalString(anyOf: candidates) ?? defaultValue
    }

    func int(for candidates: String..., default defaultValue: Int = 0) -> Int {
        value(anyOf: candidates)?.int ?? defaultValue
    }

    func double(for candidates: String..., default defaultValue: Double = 0) -> Double {
        value(anyOf: candidates)?.double ?? defaultValue
    }

    func bool(for candidates: String..., default defaultValue: Bool = false) -> Bool {
        value(anyOf: candidates)?.bool ?? defaultValue
    }
}
