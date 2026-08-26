import Foundation
import JSONSchema

extension FormKitRenderer {
    func arrayItemPlaceholder(
        _ request: PlaceholderRequest,
        reasons: inout [FormKitUnsupportedReason]
    ) -> FormKitJSONValue {
        switch schemaType(
            for: request.schemaObject,
            pointerTokens: request.pointerTokens,
            reasons: &reasons
        ) {
        case .scalar(let primitiveType, let allowsNull):
            return scalarPlaceholder(
                schemaObject: request.schemaObject,
                primitiveType: primitiveType,
                allowsNull: allowsNull,
                pointer: JSONPointer.pointerString(from: request.pointerTokens),
                reasons: &reasons
            )
        case .object:
            return objectPlaceholder(request, reasons: &reasons)
        case .array, .unsupported:
            return .null
        }
    }

    func scalarPlaceholder(
        schemaObject: [String: FormKitJSONValue],
        primitiveType: PrimitiveSchemaType,
        allowsNull: Bool,
        pointer: String,
        reasons: inout [FormKitUnsupportedReason]
    ) -> FormKitJSONValue {
        guard let scalarType = scalarType(
            from: primitiveType,
            format: schemaObject["format"]?.string?.trimmedForJSONSchemaForm(),
            location: pointer,
            reasons: &reasons
        ) else {
            return .null
        }

        let declaredValues = schemaObject["enum"]?.array ?? schemaObject["const"].map { [$0] } ?? []
        let rawDefaultValue = schemaObject["default"]
        if let defaultValue = primitiveValue(
            from: rawDefaultValue,
            scalarType: scalarType,
            allowsNull: allowsNull,
            normalizesEmptyText: !declaredValues.contains { $0 == rawDefaultValue }
        ) {
            return jsonValue(from: defaultValue)
        }
        if let firstOption = enumOptions(
            from: declaredValues,
            scalarType: scalarType,
            location: pointer,
            reasons: &reasons
        ).first?.value {
            return jsonValue(from: firstOption)
        }
        if allowsNull {
            return .null
        }
        switch scalarType {
        case .boolean:
            return .boolean(false)
        case .integer, .number, .string, .email, .uri, .date, .time, .dateTime:
            return .string("")
        }
    }

    func objectPlaceholder(
        _ request: PlaceholderRequest,
        reasons: inout [FormKitUnsupportedReason]
    ) -> FormKitJSONValue {
        let properties = request.schemaObject["properties"]?.object ?? [:]
        let context = ObjectPlaceholderContext(
            request: request,
            properties: properties,
            requiredKeys: Set(requiredPropertyNames(in: request.schemaObject, instance: nil))
        )
        let order = propertyNames(
            in: properties,
            schemaPathTokens: request.schemaPathTokens,
            propertyOrderIndex: request.propertyOrderIndex
        )
        var object: [String: FormKitJSONValue] = [:]
        for name in order {
            if let value = objectPlaceholderValue(for: name, context: context, reasons: &reasons) {
                object[name] = value
            }
        }
        return .object(object)
    }

    func objectPlaceholderValue(
        for name: String,
        context: ObjectPlaceholderContext,
        reasons: inout [FormKitUnsupportedReason]
    ) -> FormKitJSONValue? {
        guard let propertySchemaValue = context.properties[name],
              let propertySchema = materializedSchemaObject(
                  MaterializationRequest(
                      schemaValue: propertySchemaValue,
                      rootSchema: context.request.rootSchema,
                      instanceValue: nil,
                      pointerTokens: context.request.pointerTokens + [name],
                      schemaPathTokens: context.request.schemaPathTokens + ["properties", name],
                      propertyOrderIndex: context.request.propertyOrderIndex,
                      availableBaseSchema: nil
                  ),
                  reasons: &reasons
              )
        else {
            return nil
        }
        let childRequest = PlaceholderRequest(
            schemaObject: propertySchema.object,
            rootSchema: context.request.rootSchema,
            pointerTokens: context.request.pointerTokens + [name],
            schemaPathTokens: context.request.schemaPathTokens + ["properties", name],
            propertyOrderIndex: context.request.propertyOrderIndex
        )
        let placeholder = arrayItemPlaceholder(childRequest, reasons: &reasons)
        if propertySchema.object["default"] != nil {
            return placeholder
        }
        switch schemaType(
            for: propertySchema.object,
            pointerTokens: childRequest.pointerTokens,
            reasons: &reasons
        ) {
        case .object where context.requiredKeys.contains(name) || placeholder != .object([:]):
            return placeholder
        case .array where context.requiredKeys.contains(name) || placeholder != .array([]):
            return placeholder
        case .object, .array, .scalar, .unsupported:
            return nil
        }
    }

    func uniqueDiscriminatorOverlay(
        from candidates: [CompositeOverlayCandidate]
    ) -> Int? {
        let scoredCandidates = candidates.compactMap { candidate -> (index: Int, score: Int)? in
            guard let score = candidate.discriminatorScore else {
                return nil
            }
            return (candidate.index, score)
        }

        guard let bestScore = scoredCandidates.map(\.score).max(),
              bestScore > 0
        else {
            return nil
        }

        let bestCandidates = scoredCandidates.filter { $0.score == bestScore }
        guard bestCandidates.count == 1 else {
            return nil
        }

        return bestCandidates[0].index
    }

    func discriminatorScore(
        for schemaObject: [String: FormKitJSONValue],
        instanceValue: FormKitJSONValue?
    ) -> Int? {
        guard let instanceObject = instanceValue?.object else {
            return nil
        }

        let properties = schemaObject["properties"]?.object ?? [:]
        var score = 0
        var matchedDiscriminator = false

        for (key, propertyValue) in properties {
            guard let propertySchema = propertyValue.object,
                  let instancePropertyValue = instanceObject[key]
            else {
                continue
            }

            if let constValue = propertySchema["const"] {
                matchedDiscriminator = true
                guard constValue == instancePropertyValue else {
                    return nil
                }
                score += 2
                continue
            }

            if let enumValues = propertySchema["enum"]?.array {
                matchedDiscriminator = true
                guard enumValues.contains(instancePropertyValue) else {
                    return nil
                }
                score += 1
            }
        }

        return matchedDiscriminator ? score : nil
    }

    func schemaMatches(
        schemaValue: FormKitJSONValue,
        rootSchema: FormKitJSONValue,
        instanceValue: FormKitJSONValue?,
        pointerTokens: [String],
        reasons: inout [FormKitUnsupportedReason]
    ) -> Bool {
        let context = Context(
            dialect: .draft2020_12,
            formatValidators: DefaultFormatValidators.all
        )

        do {
            _ = try Schema(rawSchema: rootSchema.jsonSchemaValue, context: context)
            let schema = try Schema(
                rawSchema: schemaValue.jsonSchemaValue,
                location: JSONPointer(from: JSONPointer.pointerString(from: pointerTokens)),
                context: context
            )
            let result = schema.validate(
                (instanceValue ?? defaultEvaluationInstance(for: schemaValue)).jsonSchemaValue
            )
            return result.isValid
        } catch {
            reasons.append(.invalidSchema(error.localizedDescription))
            return false
        }
    }

    func defaultEvaluationInstance(for schemaValue: FormKitJSONValue) -> FormKitJSONValue {
        guard let schemaObject = schemaValue.object else {
            return .null
        }

        if schemaObject["type"]?.string == "object"
            || schemaObject["properties"] != nil
            || schemaObject["required"] != nil
            || schemaObject["dependentRequired"] != nil
            || schemaObject["dependentSchemas"] != nil
        {
            return .object([:])
        }

        if schemaObject["type"]?.string == "array" {
            return .array([])
        }

        return .null
    }

    func mergedRequiredKeys(
        from existingRequired: FormKitJSONValue?,
        dependencyObject: [String: FormKitJSONValue],
        instanceKeys: Set<String>
    ) -> [String] {
        var orderedKeys = existingRequired?.array?.compactMap(\.string) ?? []
        var requiredKeys = Set(orderedKeys)

        for (key, rawValues) in dependencyObject where instanceKeys.contains(key) {
            for dependencyKey in rawValues.array?.compactMap(\.string) ?? []
                where !requiredKeys.contains(dependencyKey)
            {
                requiredKeys.insert(dependencyKey)
                orderedKeys.append(dependencyKey)
            }
        }

        return orderedKeys
    }
}
