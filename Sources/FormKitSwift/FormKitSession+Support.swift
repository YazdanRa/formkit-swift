import Foundation
import JSONSchema

extension FormKitSession {
    static func failClosed(_ renderPlan: FormKitRenderPlan) -> FormKitRenderPlan {
        guard !renderPlan.isSupported else {
            return renderPlan
        }

        return FormKitRenderPlan(
            title: renderPlan.title,
            description: renderPlan.description,
            sections: [],
            fields: [],
            fieldOrder: [],
            unsupportedReasons: renderPlan.unsupportedReasons
        )
    }

    func ensureObjectExists(
        at pointer: String,
        in rootObject: inout [String: FormKitJSONValue]
    ) {
        let path = Self.tokens(from: pointer)
        guard !path.isEmpty else {
            return
        }

        var rootValue = FormKitJSONValue.object(rootObject)
        rootValue = ensuringObject(in: rootValue, path: path)
        rootObject = rootValue.object ?? [:]
    }

    func setArray(
        _ array: [FormKitJSONValue],
        at pointer: String,
        in rootObject: inout [String: FormKitJSONValue]
    ) {
        var rootValue = FormKitJSONValue.object(rootObject)
        rootValue = inserting(.array(array), into: rootValue, path: Self.tokens(from: pointer))
        rootObject = rootValue.object ?? [:]
    }

    private func setArray(
        _ array: [FormKitJSONValue],
        at pointer: String,
        in value: inout FormKitJSONValue
    ) {
        value = inserting(.array(array), into: value, path: Self.tokens(from: pointer))
    }

    func arrayValue(
        at pointer: String,
        in value: FormKitJSONValue
    ) -> [FormKitJSONValue]? {
        value.value(at: JSONPointer(from: pointer))?.array
    }

    func insert(
        _ value: FormKitJSONValue,
        at pointer: String,
        into rootObject: inout [String: FormKitJSONValue]
    ) {
        var rootValue = FormKitJSONValue.object(rootObject)
        rootValue = inserting(value, into: rootValue, path: Self.tokens(from: pointer))
        rootObject = rootValue.object ?? [:]
    }

    func insert(
        _ value: FormKitJSONValue,
        at pointer: String,
        into rootValue: inout FormKitJSONValue
    ) {
        rootValue = inserting(value, into: rootValue, path: Self.tokens(from: pointer))
    }

    private func inserting(
        _ value: FormKitJSONValue,
        into currentValue: FormKitJSONValue,
        path: [String]
    ) -> FormKitJSONValue {
        guard let head = path.first else {
            return value
        }

        if let index = Int(head) {
            var array = currentValue.array ?? []
            if array.count <= index {
                array.append(contentsOf: repeatElement(.null, count: index - array.count + 1))
            }

            if path.count == 1 {
                array[index] = value
                return .array(array)
            }

            array[index] = inserting(
                value,
                into: normalizedContainer(
                    currentValue: array[index],
                    nextPath: Array(path.dropFirst())
                ),
                path: Array(path.dropFirst())
            )
            return .array(array)
        }

        var object = currentValue.object ?? [:]
        if path.count == 1 {
            object[head] = value
            return .object(object)
        }

        object[head] = inserting(
            value,
            into: normalizedContainer(
                currentValue: object[head] ?? .null,
                nextPath: Array(path.dropFirst())
            ),
            path: Array(path.dropFirst())
        )
        return .object(object)
    }

    func removingValue(from currentValue: FormKitJSONValue, path: [String]) -> FormKitJSONValue {
        guard let head = path.first else { return currentValue }
        if let index = Int(head) {
            guard var array = currentValue.array, array.indices.contains(index) else { return currentValue }
            if path.count == 1 {
                array.remove(at: index)
                return .array(array)
            }
            array[index] = removingValue(from: array[index], path: Array(path.dropFirst()))
            return .array(array)
        }
        guard var object = currentValue.object else { return currentValue }
        if path.count == 1 {
            object.removeValue(forKey: head)
            return .object(object)
        }
        guard let child = object[head] else { return currentValue }
        object[head] = removingValue(from: child, path: Array(path.dropFirst()))
        return .object(object)
    }

    func jsonValue(from primitive: FormKitFieldDescriptor.PrimitiveValue) -> FormKitJSONValue {
        switch primitive {
        case .string(let value):
            return .string(value)
        case .integer(let value):
            return .integer(value)
        case .number(let value):
            return .number(value)
        case .boolean(let value):
            return .boolean(value)
        case .null:
            return .null
        }
    }

    func fallbackDate(for field: FormKitFieldDescriptor) -> Date {
        if let defaultValue = field.defaultValue,
           case .string(let text) = defaultValue
        {
            switch field.scalarType {
            case .date:
                return FormKitRenderer.dateFormatter.date(from: text) ?? .now
            case .time:
                return FormKitRenderer.reanchoredTime(from: text)
                    ?? .now
            case .dateTime:
                return FormKitRenderer.dateTimeFormatter.date(from: text)
                    ?? FormKitRenderer.dateTimeFallbackFormatter.date(from: text)
                    ?? .now
            default:
                return .now
            }
        }

        return .now
    }

    static func tokens(from pointer: String) -> [String] {
        let trimmed = pointer.replacingOccurrences(of: "#/", with: "")
        guard !trimmed.isEmpty else {
            return []
        }

        return trimmed.split(separator: "/").map { token in
            token
                .replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
        }
    }

    private func ensuringObject(
        in currentValue: FormKitJSONValue,
        path: [String]
    ) -> FormKitJSONValue {
        guard let head = path.first else {
            return currentValue
        }

        if let index = Int(head) {
            var array = currentValue.array ?? []
            if array.count <= index {
                array.append(contentsOf: repeatElement(.null, count: index - array.count + 1))
            }

            if path.count == 1 {
                if array[index].object == nil {
                    array[index] = .object([:])
                }
                return .array(array)
            }

            array[index] = ensuringObject(
                in: normalizedContainer(
                    currentValue: array[index],
                    nextPath: Array(path.dropFirst())
                ),
                path: Array(path.dropFirst())
            )
            return .array(array)
        }

        var object = currentValue.object ?? [:]
        if path.count == 1 {
            if object[head]?.object == nil {
                object[head] = .object([:])
            }
            return .object(object)
        }

        object[head] = ensuringObject(
            in: normalizedContainer(
                currentValue: object[head] ?? .null,
                nextPath: Array(path.dropFirst())
            ),
            path: Array(path.dropFirst())
        )
        return .object(object)
    }

    private func normalizedContainer(
        currentValue: FormKitJSONValue,
        nextPath: [String]
    ) -> FormKitJSONValue {
        guard let next = nextPath.first else {
            return currentValue
        }

        if Int(next) != nil {
            return currentValue.array.map(FormKitJSONValue.array) ?? .array([])
        }

        return currentValue.object.map(FormKitJSONValue.object) ?? .object([:])
    }

    static func prettyJSONString(from value: FormKitJSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return string
    }

    static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.maximumFractionDigits = 12
        formatter.minimumFractionDigits = 0
        return formatter
    }()
}
