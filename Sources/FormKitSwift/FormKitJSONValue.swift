import Foundation
import JSONSchema

/// Package-owned representation of arbitrary JSON values.
///
/// FormKitSwift keeps this type in its public API so callers never need to
/// depend on the package's validation implementation details.
public enum FormKitJSONValue: Codable, Equatable, Sendable {
    case object([String: FormKitJSONValue])
    case array([FormKitJSONValue])
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let object = try? container.decode([String: FormKitJSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([FormKitJSONValue].self) {
            self = .array(array)
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public var object: [String: FormKitJSONValue]? {
        if case .object(let value) = self { value } else { nil }
    }

    public var array: [FormKitJSONValue]? {
        if case .array(let value) = self { value } else { nil }
    }

    public var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    public var integer: Int? {
        switch self {
        case .integer(let value):
            return value
        case .number(let value) where value.rounded(.towardZero) == value:
            return Int(value)
        default:
            return nil
        }
    }

    public var number: Double? {
        switch self {
        case .integer(let value):
            return Double(value)
        case .number(let value):
            return value
        default:
            return nil
        }
    }

    public var boolean: Bool? {
        if case .boolean(let value) = self { value } else { nil }
    }

    func value(at pointer: JSONPointer) -> FormKitJSONValue? {
        value(atPointer: pointer.description)
    }

    func value(atPointer pointer: String) -> FormKitJSONValue? {
        let tokens = Self.tokens(from: pointer)
        var current = self
        for token in tokens {
            switch current {
            case .object(let object):
                guard let next = object[token] else { return nil }
                current = next
            case .array(let array):
                guard let index = Int(token), array.indices.contains(index) else {
                    return nil
                }
                current = array[index]
            default:
                return nil
            }
        }
        return current
    }

    var jsonSchemaValue: JSONSchema.JSONValue {
        let data = try! JSONEncoder().encode(self)
        return try! JSONDecoder().decode(JSONSchema.JSONValue.self, from: data)
    }

    var primitive: PrimitiveKind {
        switch self {
        case .object:
            return .object
        case .array:
            return .array
        case .string:
            return .string
        case .integer:
            return .integer
        case .number:
            return .number
        case .boolean:
            return .boolean
        case .null:
            return .null
        }
    }

    enum PrimitiveKind: String, Sendable {
        case object
        case array
        case string
        case integer
        case number
        case boolean
        case null
    }

    private static func tokens(from pointer: String) -> [String] {
        let trimmed = pointer.hasPrefix("#") ? String(pointer.dropFirst()) : pointer
        guard trimmed.hasPrefix("/") else {
            return []
        }

        return trimmed
            .dropFirst()
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { token in
                token.replacingOccurrences(of: "~1", with: "/")
                    .replacingOccurrences(of: "~0", with: "~")
            }
    }
}
