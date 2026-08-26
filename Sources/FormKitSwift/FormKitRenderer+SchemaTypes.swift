import Foundation
import JSONSchema

extension FormKitRenderer {
    func schemaType(
        for schemaObject: [String: FormKitJSONValue],
        pointerTokens: [String],
        reasons: inout [FormKitUnsupportedReason]
    ) -> SupportedSchemaType {
        let pointer = JSONPointer.pointerString(from: pointerTokens)
        if let constValue = schemaObject["const"], schemaObject["type"] == nil {
            return inferredSchemaType(
                from: constValue,
                allowsNull: false,
                pointer: pointer,
                reasons: &reasons
            )
        }
        if let enumValues = schemaObject["enum"]?.array, schemaObject["type"] == nil {
            return inferredEnumType(enumValues, pointer: pointer, reasons: &reasons)
        }
        guard let typeValue = schemaObject["type"] else {
            guard schemaObject["properties"] == nil, schemaObject["required"] == nil else {
                return .object
            }
            reasons.append(
                .unsupportedSchemaShape(
                    location: pointer,
                    message: String(
                        localized: "Every supported schema node must declare a type or enum.",
                        bundle: .module
                    )
                )
            )
            return .unsupported
        }
        return declaredSchemaType(typeValue, pointer: pointer, reasons: &reasons)
    }

    func inferredEnumType(
        _ values: [FormKitJSONValue],
        pointer: String,
        reasons: inout [FormKitUnsupportedReason]
    ) -> SupportedSchemaType {
        let allowsNull = values.contains(.null)
        guard let firstValue = values.first(where: { $0 != .null }) else {
            reasons.append(
                .unsupportedSchemaShape(
                    location: pointer,
                    message: String(localized: "Enums must include at least one concrete value.", bundle: .module)
                )
            )
            return .unsupported
        }
        return inferredSchemaType(
            from: firstValue,
            allowsNull: allowsNull,
            pointer: pointer,
            reasons: &reasons
        )
    }

    func inferredSchemaType(
        from value: FormKitJSONValue,
        allowsNull: Bool,
        pointer: String,
        reasons: inout [FormKitUnsupportedReason]
    ) -> SupportedSchemaType {
        switch value {
        case .string:
            return .scalar(.string, allowsNull: allowsNull)
        case .integer:
            return .scalar(.integer, allowsNull: allowsNull)
        case .number:
            return .scalar(.number, allowsNull: allowsNull)
        case .boolean:
            return .scalar(.boolean, allowsNull: allowsNull)
        case .null, .array, .object:
            reasons.append(.unsupportedType(typeDescription: value.primitive.rawValue, location: pointer))
            return .unsupported
        }
    }

    func declaredSchemaType(
        _ typeValue: FormKitJSONValue,
        pointer: String,
        reasons: inout [FormKitUnsupportedReason]
    ) -> SupportedSchemaType {
        switch typeValue {
        case .string(let typeName):
            return declaredStringSchemaType(typeName, pointer: pointer, reasons: &reasons)
        case .array(let types):
            return nullableSchemaType(types, pointer: pointer, reasons: &reasons)
        default:
            reasons.append(
                .unsupportedSchemaShape(
                    location: pointer,
                    message: String(
                        localized: "Type declarations must be strings or nullable primitive unions.",
                        bundle: .module
                    )
                )
            )
            return .unsupported
        }
    }

    func declaredStringSchemaType(
        _ typeName: String,
        pointer: String,
        reasons: inout [FormKitUnsupportedReason]
    ) -> SupportedSchemaType {
        switch typeName {
        case "object":
            return .object
        case "array":
            return .array
        case "string":
            return .scalar(.string, allowsNull: false)
        case "integer":
            return .scalar(.integer, allowsNull: false)
        case "number":
            return .scalar(.number, allowsNull: false)
        case "boolean":
            return .scalar(.boolean, allowsNull: false)
        default:
            reasons.append(.unsupportedType(typeDescription: typeName, location: pointer))
            return .unsupported
        }
    }

    func nullableSchemaType(
        _ types: [FormKitJSONValue],
        pointer: String,
        reasons: inout [FormKitUnsupportedReason]
    ) -> SupportedSchemaType {
        let resolvedTypes = types.compactMap(\.string)
        let concreteTypes = resolvedTypes.filter { $0 != "null" }
        guard resolvedTypes.contains("null"),
              resolvedTypes.count == 2,
              let typeName = concreteTypes.first
        else {
            reasons.append(
                .unsupportedSchemaShape(
                    location: pointer,
                    message: String(
                        localized: "Union types are only supported for nullable primitives.",
                        bundle: .module
                    )
                )
            )
            return .unsupported
        }
        switch typeName {
        case "string":
            return .scalar(.string, allowsNull: true)
        case "integer":
            return .scalar(.integer, allowsNull: true)
        case "number":
            return .scalar(.number, allowsNull: true)
        case "boolean":
            return .scalar(.boolean, allowsNull: true)
        default:
            reasons.append(.unsupportedType(typeDescription: typeName, location: pointer))
            return .unsupported
        }
    }

    func scalarType(
        from primitiveType: PrimitiveSchemaType,
        format: String?,
        location: String,
        reasons: inout [FormKitUnsupportedReason]
    ) -> FormKitFieldDescriptor.ScalarType? {
        switch primitiveType {
        case .string:
            return stringScalarType(format: format, location: location, reasons: &reasons)
        case .integer:
            return .integer
        case .number:
            return .number
        case .boolean:
            return .boolean
        }
    }

    func stringScalarType(
        format: String?,
        location: String,
        reasons: inout [FormKitUnsupportedReason]
    ) -> FormKitFieldDescriptor.ScalarType? {
        switch format {
        case nil, "":
            return .string
        case "email":
            return .email
        case "uri":
            return .uri
        case "date":
            return .date
        case "time":
            return .time
        case "date-time":
            return .dateTime
        default:
            reasons.append(
                .unsupportedKeyword(
                    keyword: "format",
                    location: location,
                    message: String(
                        localized: "Only email, uri, date, time, and date-time formats are supported in v1.",
                        bundle: .module
                    )
                )
            )
            return nil
        }
    }

    func enumOptions(
        from rawValues: [FormKitJSONValue]?,
        scalarType: FormKitFieldDescriptor.ScalarType,
        location: String,
        reasons: inout [FormKitUnsupportedReason]
    ) -> [FormKitFieldDescriptor.Choice] {
        guard let rawValues else {
            return []
        }

        var options: [FormKitFieldDescriptor.Choice] = []
        for value in rawValues {
            guard let primitiveValue = primitiveValue(
                from: value,
                scalarType: scalarType,
                allowsNull: value == .null
            ) else {
                reasons.append(
                    .unsupportedSchemaShape(
                        location: location,
                        message: String(localized: "Enum options must match the rendered field type.", bundle: .module)
                    )
                )
                return []
            }
            options.append(
                FormKitFieldDescriptor.Choice(
                    id: primitiveValue.storageKey,
                    title: primitiveValue.title,
                    value: primitiveValue
                )
            )
        }
        return options
    }

    func primitiveValue(
        from jsonValue: FormKitJSONValue?,
        scalarType: FormKitFieldDescriptor.ScalarType,
        allowsNull: Bool,
        normalizesEmptyText: Bool = true
    ) -> FormKitFieldDescriptor.PrimitiveValue? {
        guard let jsonValue else {
            return nil
        }
        switch jsonValue {
        case .null:
            return allowsNull ? .null : nil
        case .string(let value):
            return stringPrimitiveValue(
                value,
                scalarType: scalarType,
                allowsNull: allowsNull,
                normalizesEmptyText: normalizesEmptyText
            )
        case .integer(let value):
            return integerPrimitiveValue(value, scalarType: scalarType)
        case .number(let value):
            return scalarType == .number ? .number(value) : nil
        case .boolean(let value):
            return scalarType == .boolean ? .boolean(value) : nil
        case .object, .array:
            return nil
        }
    }

    func stringPrimitiveValue(
        _ value: String,
        scalarType: FormKitFieldDescriptor.ScalarType,
        allowsNull: Bool,
        normalizesEmptyText: Bool
    ) -> FormKitFieldDescriptor.PrimitiveValue? {
        if allowsNull,
           normalizesEmptyText,
           value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return .null
        }
        switch scalarType {
        case .string, .email, .uri, .date, .time, .dateTime, .integer, .number:
            return .string(value)
        case .boolean:
            return nil
        }
    }

    func integerPrimitiveValue(
        _ value: Int,
        scalarType: FormKitFieldDescriptor.ScalarType
    ) -> FormKitFieldDescriptor.PrimitiveValue? {
        switch scalarType {
        case .integer:
            return .integer(value)
        case .number:
            return .number(Double(value))
        default:
            return nil
        }
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
}
