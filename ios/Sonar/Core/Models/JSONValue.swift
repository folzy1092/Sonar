import Foundation

/// Сырой JSON ответа сервиса — как `serde_json::Value` в Rust-клиенте: разбор моделей по полям и данные,
/// которые нужно сохранить как есть (у трека SoundCloud — варианты потока и `track_authorization`).
/// Отсутствующий ключ — `.null`, поэтому цепочки `json["a"]["b"][0]` безопасны.
enum JSONValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(data: Data) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    subscript(key: String) -> JSONValue {
        if case let .object(object) = self { return object[key] ?? .null }
        return .null
    }

    subscript(index: Int) -> JSONValue {
        if case let .array(array) = self, array.indices.contains(index) { return array[index] }
        return .null
    }

    var string: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    /// Целое: число без дробной части (id, длительности, счётчики).
    var int: Int? {
        switch self {
        case let .int(value): value
        case let .double(value) where value.rounded() == value && abs(value) < 9e15: Int(value)
        default: nil
        }
    }

    var bool: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    var array: [JSONValue]? {
        if case let .array(value) = self { return value }
        return nil
    }

    var isNull: Bool { self == .null }

    var isObject: Bool {
        if case .object = self { return true }
        return false
    }

    /// id бывает и строкой, и числом.
    var idString: String? {
        string ?? int.map(String.init)
    }

    /// Пусто, если не массив.
    var items: [JSONValue] { array ?? [] }
}
