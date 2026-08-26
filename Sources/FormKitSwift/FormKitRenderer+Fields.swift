import Foundation
import JSONSchema

extension FormKitRenderer {
    func makeFieldDescriptor(
        _ request: FieldDescriptorRequest,
        reasons: inout [FormKitUnsupportedReason]
    ) -> FormKitFieldDescriptor? {
        let pointer = JSONPointer.pointerString(from: request.pointerTokens)

        for keyword in Self.blockedKeywords where request.schemaObject[keyword] != nil {
            reasons.append(
                .unsupportedKeyword(
                    keyword: keyword,
                    location: pointer,
                    message: String(
                        localized: "This field shape is not supported in the native renderer yet.",
                        bundle: .module
                    )
                )
            )
        }

        let typeResult = schemaType(
            for: request.schemaObject,
            pointerTokens: request.pointerTokens,
            reasons: &reasons
        )
        switch typeResult {
        case .unsupported:
            return nil
        case .object:
            reasons.append(
                .unsupportedSchemaShape(
                    location: pointer,
                    message: String(localized: "Object nodes must be rendered as sections.", bundle: .module)
                )
            )
            return nil
        case .array:
            reasons.append(
                .unsupportedType(
                    typeDescription: "array",
                    location: pointer
                )
            )
            return nil
        case .scalar(let primitiveType, let declaredAllowsNull):
            return makeScalarFieldDescriptor(
                request,
                primitiveType: primitiveType,
                declaredAllowsNull: declaredAllowsNull,
                pointer: pointer,
                reasons: &reasons
            )
        }
    }

    func makeScalarFieldDescriptor(
        _ request: FieldDescriptorRequest,
        primitiveType: PrimitiveSchemaType,
        declaredAllowsNull: Bool,
        pointer: String,
        reasons: inout [FormKitUnsupportedReason]
    ) -> FormKitFieldDescriptor? {
        guard let fieldScalarType = scalarType(
            from: primitiveType,
            format: request.schemaObject["format"]?.string?.trimmedForJSONSchemaForm(),
            location: pointer,
            reasons: &reasons
        ) else {
            return nil
        }
        let allowsNull = declaredAllowsNull
            && (request.schemaObject["enum"]?.array.map { $0.contains(.null) } ?? true)
            && (request.schemaObject["const"].map { $0 == .null } ?? true)
        let options = enumOptions(
            from: request.schemaObject["enum"]?.array ?? request.schemaObject["const"].map { [$0] },
            scalarType: fieldScalarType,
            location: pointer,
            reasons: &reasons
        )
        let defaultValue = primitiveValue(
            from: request.schemaObject["default"],
            scalarType: fieldScalarType,
            allowsNull: allowsNull,
            normalizesEmptyText: !options.contains {
                jsonValue(from: $0.value) == request.schemaObject["default"]
            }
        )
        return FormKitFieldDescriptor(
            id: pointer,
            pointer: pointer,
            parentPointer: request.parentPointer,
            propertyKey: request.propertyKey,
            title: request.title,
            description: request.description,
            scalarType: fieldScalarType,
            enumOptions: options,
            isRequired: request.isRequired,
            allowsNull: allowsNull,
            defaultValue: defaultValue,
            uiComponent: uiComponent(from: request.schemaObject),
            renderBehavior: resolvedRenderBehavior(for: request.pointerTokens, from: request.schemaObject),
            conditionalState: conditionalRenderState(from: request.schemaObject),
            accessibilityIdentifier: accessibilityIdentifier(for: pointer)
        )
    }

    func uiComponent(from schemaObject: [String: FormKitJSONValue]) -> FormKitUIComponent? {
        guard let value = schemaObject[Self.uiComponentKey]?.string else {
            return nil
        }
        let component = FormKitUIComponent(rawValue: value)
        return component.rawValue.isEmpty ? nil : component
    }

    func resolvedRenderBehavior(
        for pointerTokens: [String],
        from schemaObject: [String: FormKitJSONValue],
        inheritedBehavior: FormKitConditionalRenderBehavior? = nil
    ) -> FormKitConditionalRenderBehavior {
        if let override = renderBehaviorOverride(for: pointerTokens) {
            return override
        }

        if let rawValue = (
            schemaObject[Self.internalResolvedRenderBehaviorKey]?.string
        )?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let behavior = FormKitConditionalRenderBehavior(rawValue: rawValue)
        {
            return behavior
        }

        return inheritedBehavior ?? defaultConditionalRenderBehavior
    }

    func renderBehaviorOverride(
        for pointerTokens: [String]
    ) -> FormKitConditionalRenderBehavior? {
        let pointer = JSONPointer.pointerString(from: pointerTokens)
        if let exactOverride = conditionalRenderBehaviorOverrides[pointer] {
            return exactOverride
        }

        return conditionalRenderBehaviorOverrides
            .filter { $0.key.contains("*") }
            .sorted { lhs, rhs in
                if lhs.key.count == rhs.key.count {
                    return lhs.key < rhs.key
                }
                return lhs.key.count > rhs.key.count
            }
            .first { wildcardPointer($0.key, matches: pointer) }?
            .value
    }

    func wildcardPointer(_ pattern: String, matches pointer: String) -> Bool {
        let patternTokens = renderPointerTokens(from: pattern)
        let pointerTokens = renderPointerTokens(from: pointer)
        guard patternTokens.count == pointerTokens.count else {
            return false
        }
        return zip(patternTokens, pointerTokens).allSatisfy { patternToken, pointerToken in
            patternToken == "*" || patternToken == pointerToken
        }
    }

    func renderPointerTokens(from pointer: String) -> [String] {
        let normalized = Self.normalizedRenderBehaviorOverridePointer(pointer) ?? "#"
        guard normalized.hasPrefix("#/") else {
            return []
        }
        return normalized.dropFirst(2).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    }

    static func normalizedConditionalRenderBehaviorOverrides(
        _ overrides: [String: FormKitConditionalRenderBehavior]
    ) -> [String: FormKitConditionalRenderBehavior] {
        overrides.reduce(into: [String: FormKitConditionalRenderBehavior]()) { result, element in
            let (pointer, behavior) = element
            guard let normalizedPointer = normalizedRenderBehaviorOverridePointer(pointer) else {
                return
            }
            result[normalizedPointer] = behavior
        }
    }

    static func normalizedRenderBehaviorOverridePointer(_ pointer: String) -> String? {
        let trimmed = pointer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "#"
        }
        if trimmed == "#" || trimmed.hasPrefix("#/") {
            return trimmed
        }
        if trimmed.hasPrefix("/") {
            return "#\(trimmed)"
        }
        return trimmed
    }

    func conditionalRenderState(
        from schemaObject: [String: FormKitJSONValue]
    ) -> FormKitConditionalRenderState {
        guard schemaObject[Self.internalConditionalStateKey]?.string
            == FormKitConditionalRenderState.inactive.rawValue
        else {
            return .active
        }

        return .inactive
    }

    func seedFieldValues(
        for renderPlan: FormKitRenderPlan,
        instance: FormKitJSONValue?
    ) -> [String: FormKitFieldDescriptor.PrimitiveValue?] {
        renderPlan.fields.reduce(into: [:]) { result, field in
            let seededValue = seededValue(for: field, instance: instance)
            result[field.id] = seededValue
        }
    }

    func seededValue(
        for field: FormKitFieldDescriptor,
        instance: FormKitJSONValue?
    ) -> FormKitFieldDescriptor.PrimitiveValue? {
        if let instance,
           let instanceValue = instance.value(at: JSONPointer(from: field.pointer))
        {
            return primitiveValue(
                from: instanceValue,
                scalarType: field.scalarType,
                allowsNull: field.allowsNull,
                normalizesEmptyText: !field.enumOptions.contains {
                    jsonValue(from: $0.value) == instanceValue
                }
            )
        }

        if let defaultValue = field.defaultValue {
            return defaultValue
        }

        if field.allowsNull, field.isRequired {
            return .null
        }

        if field.enumOptions.isEmpty == false && field.isRequired {
            return field.enumOptions.first?.value
        }

        switch field.scalarType {
        case .boolean where field.isRequired:
            return .boolean(false)
        case .date where field.isRequired:
            return .string(Self.dateFormatter.string(from: .now))
        case .time where field.isRequired:
            return .string(Self.timeFormatter.string(from: .now))
        case .dateTime where field.isRequired:
            return .string(Self.dateTimeFormatter.string(from: .now))
        default:
            return nil
        }
    }

}
