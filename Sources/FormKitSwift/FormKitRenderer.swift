import Foundation
import JSONSchema
import Observation

/// Produces a render plan and editable form session from a JSON Schema document.
@MainActor
public protocol FormKitRendering {
    func makeFormSession(
        schemaJSON: String,
        instanceJSON: String?,
        defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior?,
        validationBehavior: FormKitValidationBehavior
    ) -> FormKitSession
}

public enum FormKitValidationBehavior: Sendable, Equatable {
    case revalidateAfterFirstAttempt
    case onDemandOnly
}

public extension FormKitRendering {
    func makeFormSession(
        schemaJSON: String,
        instanceJSON: String?,
        defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior? = nil
    ) -> FormKitSession {
        makeFormSession(
            schemaJSON: schemaJSON,
            instanceJSON: instanceJSON,
            defaultConditionalRenderBehavior: defaultConditionalRenderBehavior,
            validationBehavior: .revalidateAfterFirstAttempt
        )
    }
}

/// Experimental bridge from JSON Schema documents to native iOS form metadata.
@MainActor
public final class FormKitRenderer: FormKitRendering {
    private let defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior

    public init(defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior = .hide) {
        self.defaultConditionalRenderBehavior = defaultConditionalRenderBehavior
    }

    public func makeFormSession(
        schemaJSON: String,
        instanceJSON: String? = nil,
        defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior? = nil,
        validationBehavior: FormKitValidationBehavior = .revalidateAfterFirstAttempt
    ) -> FormKitSession {
        if let defaultConditionalRenderBehavior,
           defaultConditionalRenderBehavior != self.defaultConditionalRenderBehavior
        {
            return FormKitRenderer(defaultConditionalRenderBehavior: defaultConditionalRenderBehavior)
                .makeFormSession(
                    schemaJSON: schemaJSON,
                    instanceJSON: instanceJSON,
                    defaultConditionalRenderBehavior: nil,
                    validationBehavior: validationBehavior
                )
        }

        let schemaDecoder = JSONDecoder()
        let schemaJSONValue: FormKitJSONValue
        let schemaPropertyOrderIndex: JSONSchemaPropertyOrderIndex

        do {
            schemaJSONValue = try schemaDecoder.decode(FormKitJSONValue.self, from: Data(schemaJSON.utf8))
            schemaPropertyOrderIndex = try JSONSchemaPropertyOrderIndex(schemaJSON: schemaJSON)
        } catch {
            let plan = FormKitRenderPlan(
                title: FormKitDefaults.untitledTitle,
                description: nil,
                sections: [],
                fields: [],
                fieldOrder: [],
                unsupportedReasons: [
                    .invalidSchemaJSON(error.localizedDescription)
                ]
            )
            return FormKitSession(
                renderPlan: plan,
                validator: nil,
                initialInstance: nil,
                initialFieldValues: [:],
                validationBehavior: validationBehavior,
                refreshesRenderPlanOnFieldEdit: false,
                renderPlanProvider: { _ in plan },
                fieldValueSeedProvider: { _, _ in [:] }
            )
        }

        let decodedInstance = decodeInstance(instanceJSON)
        let renderPlan = makeRenderPlan(
            from: schemaJSONValue,
            instance: decodedInstance.value,
            propertyOrderIndex: schemaPropertyOrderIndex
        )

        if !renderPlan.isSupported {
            let fieldValues = seedFieldValues(
                for: renderPlan,
                instance: decodedInstance.value
            )

            let session = FormKitSession(
                renderPlan: renderPlan,
                validator: nil,
                initialInstance: decodedInstance.value,
                initialFieldValues: fieldValues,
                validationBehavior: validationBehavior,
                refreshesRenderPlanOnFieldEdit: schemaMayChangeRenderPlanAfterFieldEdit(schemaJSONValue),
                renderPlanProvider: { [schemaJSONValue, schemaPropertyOrderIndex] instance in
                    self.makeRenderPlan(
                        from: schemaJSONValue,
                        instance: instance,
                        propertyOrderIndex: schemaPropertyOrderIndex
                    )
                },
                fieldValueSeedProvider: { plan, instance in
                    self.seedFieldValues(for: plan, instance: instance)
                }
            )
            if let message = decodedInstance.errorMessage {
                session.setFormMessage(message)
            }
            return session
        }

        guard let validator = buildValidator(for: schemaJSONValue) else {
            let plan = FormKitRenderPlan(
                title: renderPlan.title,
                description: renderPlan.description,
                sections: [],
                fields: [],
                fieldOrder: [],
                unsupportedReasons: [
                    .invalidSchema(
                        String(localized: "The schema could not be compiled for validation.")
                    )
                ]
            )
            return FormKitSession(
                renderPlan: plan,
                validator: nil,
                initialInstance: decodedInstance.value,
                initialFieldValues: [:],
                validationBehavior: validationBehavior,
                refreshesRenderPlanOnFieldEdit: false,
                renderPlanProvider: { _ in plan },
                fieldValueSeedProvider: { _, _ in [:] }
            )
        }

        let fieldValues = seedFieldValues(
            for: renderPlan,
            instance: decodedInstance.value
        )

        let session = FormKitSession(
            renderPlan: renderPlan,
            validator: validator,
            initialInstance: decodedInstance.value,
            initialFieldValues: fieldValues,
            validationBehavior: validationBehavior,
            refreshesRenderPlanOnFieldEdit: schemaMayChangeRenderPlanAfterFieldEdit(schemaJSONValue),
            renderPlanProvider: { [schemaJSONValue, schemaPropertyOrderIndex] instance in
                self.makeRenderPlan(
                    from: schemaJSONValue,
                    instance: instance,
                    propertyOrderIndex: schemaPropertyOrderIndex
                )
            },
            fieldValueSeedProvider: { plan, instance in
                self.seedFieldValues(for: plan, instance: instance)
            }
        )
        if let message = decodedInstance.errorMessage {
            session.setFormMessage(message)
        }
        return session
    }

    private func decodeInstance(_ instanceJSON: String?) -> (value: FormKitJSONValue?, errorMessage: String?) {
        guard let instanceJSON else {
            return (nil, nil)
        }

        let trimmed = instanceJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (nil, nil)
        }

        do {
            let value = try JSONDecoder().decode(FormKitJSONValue.self, from: Data(trimmed.utf8))
            guard case .object = value else {
                return (
                    nil,
                    String(localized: "The instance JSON must decode to an object.")
                )
            }
            return (value, nil)
        } catch {
            return (
                nil,
                String(
                    format: String(localized: "The form data couldn’t be opened. %@"),
                    error.localizedDescription
                )
            )
        }
    }

    private func buildValidator(for rawSchema: FormKitJSONValue) -> Schema? {
        try? Schema(
            rawSchema: rawSchema.jsonSchemaValue,
            context: Context(
                dialect: .draft2020_12,
                formatValidators: DefaultFormatValidators.all
            )
        )
    }

    private func makeRenderPlan(
        from rawSchema: FormKitJSONValue,
        instance: FormKitJSONValue?,
        propertyOrderIndex: JSONSchemaPropertyOrderIndex
    ) -> FormKitRenderPlan {
        guard let rootObject = rawSchema.object else {
            return FormKitRenderPlan(
                title: FormKitDefaults.untitledTitle,
                description: nil,
                sections: [],
                fields: [],
                fieldOrder: [],
                unsupportedReasons: [
                    .invalidSchema(
                        String(localized: "The schema root must be a JSON object.")
                    )
                ]
            )
        }

        var reasons: [FormKitUnsupportedReason] = []
        var sections: [FormKitRenderPlan.SectionDescriptor] = []
        var fields: [FormKitFieldDescriptor] = []
        var nextSectionOrder = 0

        let rootTitle = rootObject["title"]?.string?.trimmedForJSONSchemaForm()
            ?? FormKitDefaults.untitledTitle
        let rootDescription = rootObject["description"]?.string?.trimmedForJSONSchemaForm()

        _ = parseObjectSchema(
            schemaObject: rootObject,
            rootSchema: rawSchema,
            instanceValue: instance,
            pointerTokens: [],
            schemaPathTokens: [],
            propertyKey: nil,
            fallbackTitle: rootTitle,
            fallbackDescription: rootDescription,
            isRequiredInParent: true,
            depth: 0,
            propertyOrderIndex: propertyOrderIndex,
            reasons: &reasons,
            sections: &sections,
            fields: &fields,
            nextSectionOrder: &nextSectionOrder
        )

        let fieldOrder = fields.map(\.id)
        return FormKitRenderPlan(
            title: rootTitle,
            description: rootDescription,
            sections: reasons.isEmpty ? sections.sorted(by: { $0.order < $1.order }) : [],
            fields: reasons.isEmpty ? fields : [],
            fieldOrder: reasons.isEmpty ? fieldOrder : [],
            unsupportedReasons: reasons
        )
    }

    private func schemaMayChangeRenderPlanAfterFieldEdit(_ value: FormKitJSONValue) -> Bool {
        if let object = value.object {
            if object.keys.contains(where: Self.instanceDependentRenderPlanKeywords.contains) {
                return true
            }

            return object.values.contains { schemaMayChangeRenderPlanAfterFieldEdit($0) }
        }

        if let array = value.array {
            return array.contains { schemaMayChangeRenderPlanAfterFieldEdit($0) }
        }

        return false
    }

    @discardableResult
    private func parseObjectSchema(
        schemaObject: [String: FormKitJSONValue],
        rootSchema: FormKitJSONValue,
        instanceValue: FormKitJSONValue?,
        pointerTokens: [String],
        schemaPathTokens: [String],
        propertyKey: String?,
        fallbackTitle: String,
        fallbackDescription: String?,
        isRequiredInParent: Bool,
        depth: Int,
        ownerArrayRowID: String? = nil,
        arrayContextDepth: Int = 0,
        propertyOrderIndex: JSONSchemaPropertyOrderIndex,
        reasons: inout [FormKitUnsupportedReason],
        sections: inout [FormKitRenderPlan.SectionDescriptor],
        fields: inout [FormKitFieldDescriptor],
        nextSectionOrder: inout Int
    ) -> Bool {
        let resolved = materializedSchemaObject(
            schemaValue: .object(schemaObject),
            rootSchema: rootSchema,
            instanceValue: instanceValue,
            pointerTokens: pointerTokens,
            schemaPathTokens: schemaPathTokens,
            propertyOrderIndex: propertyOrderIndex,
            reasons: &reasons
        )

        guard let resolvedSchema = resolved else {
            return false
        }

        guard supportsObjectSchema(
            resolvedSchema.object,
            pointerTokens: pointerTokens,
            reasons: &reasons
        ) else {
            return false
        }

        let properties = resolvedSchema.object["properties"]?.object ?? [:]
        let requiredKeyOrder = requiredPropertyNames(
            in: resolvedSchema.object,
            instance: instanceValue
        )
        let requiredKeys = Set(requiredKeyOrder)
        let pointer = JSONPointer.pointerString(from: pointerTokens)
        let sectionID = sectionIdentifier(for: pointer)
        let parentPointer = pointerTokens.isEmpty
            ? nil
            : JSONPointer.pointerString(from: Array(pointerTokens.dropLast()))
        let sectionOrder = nextSectionOrder
        nextSectionOrder += 1
        let sectionTitle = resolvedSchema.object["title"]?.string?.trimmedForJSONSchemaForm()
            ?? propertyKey.map(humanizedPropertyKey)
            ?? fallbackTitle
        let sectionDescription = resolvedSchema.object["description"]?.string?.trimmedForJSONSchemaForm()
            ?? fallbackDescription
        let sectionRenderBehavior = resolvedRenderBehavior(from: resolvedSchema.object)
        let sectionConditionalState = conditionalRenderState(from: resolvedSchema.object)

        var sectionFieldIDs: [String] = []
        let propertyOrder = propertyNames(
            in: properties,
            schemaPathTokens: schemaPathTokens,
            propertyOrderIndex: propertyOrderIndex,
            preferredOrder: resolvedSchema.propertyOrder
        )
        for name in propertyOrder {
            guard let propertyValue = properties[name] else {
                continue
            }

            guard let propertySchemaObject = propertyValue.object else {
                reasons.append(
                    .unsupportedSchemaShape(
                        location: pointerForChild(name, in: pointerTokens),
                        message: String(localized: "Properties must resolve to schema objects.")
                    )
                )
                continue
            }

            let childTokens = pointerTokens + [name]
            let childTitle = propertySchemaObject["title"]?.string?.trimmedForJSONSchemaForm()
                ?? humanizedPropertyKey(name)
            let childDescription = propertySchemaObject["description"]?.string?.trimmedForJSONSchemaForm()
            let childInstanceValue = instanceValue?.object?[name]

            let resolvedChildSchema = materializedSchemaObject(
                schemaValue: .object(propertySchemaObject),
                rootSchema: rootSchema,
                instanceValue: childInstanceValue,
                pointerTokens: childTokens,
                schemaPathTokens: schemaPathTokens + ["properties", name],
                propertyOrderIndex: propertyOrderIndex,
                reasons: &reasons
            )

            guard let resolvedChildSchema else {
                continue
            }

            if case .object = schemaType(
                for: resolvedChildSchema.object,
                pointerTokens: childTokens,
                reasons: &reasons
            ) {
                _ = parseObjectSchema(
                    schemaObject: propertySchemaObject,
                    rootSchema: rootSchema,
                    instanceValue: childInstanceValue,
                    pointerTokens: childTokens,
                    schemaPathTokens: schemaPathTokens + ["properties", name],
                    propertyKey: name,
                    fallbackTitle: childTitle,
                    fallbackDescription: childDescription,
                    isRequiredInParent: requiredKeys.contains(name),
                    depth: depth + 1,
                    ownerArrayRowID: ownerArrayRowID,
                    arrayContextDepth: arrayContextDepth,
                    propertyOrderIndex: propertyOrderIndex,
                    reasons: &reasons,
                    sections: &sections,
                    fields: &fields,
                    nextSectionOrder: &nextSectionOrder
                )
                continue
            }

            if case .array = schemaType(
                for: resolvedChildSchema.object,
                pointerTokens: childTokens,
                reasons: &reasons
            ) {
                _ = parseArraySchema(
                    schemaObject: propertySchemaObject,
                    rootSchema: rootSchema,
                    instanceValue: childInstanceValue,
                    pointerTokens: childTokens,
                    schemaPathTokens: schemaPathTokens + ["properties", name],
                    propertyKey: name,
                    fallbackTitle: childTitle,
                    fallbackDescription: childDescription,
                    isRequiredInParent: requiredKeys.contains(name),
                    depth: depth + 1,
                    ownerArrayRowID: ownerArrayRowID,
                    arrayContextDepth: arrayContextDepth,
                    propertyOrderIndex: propertyOrderIndex,
                    reasons: &reasons,
                    sections: &sections,
                    fields: &fields,
                    nextSectionOrder: &nextSectionOrder
                )
                continue
            }

            if let field = makeFieldDescriptor(
                propertyKey: name,
                schemaObject: resolvedChildSchema.object,
                pointerTokens: childTokens,
                parentPointer: pointer,
                title: childTitle,
                description: childDescription,
                isRequired: requiredKeys.contains(name),
                reasons: &reasons
            ) {
                fields.append(field)
                sectionFieldIDs.append(field.id)
            }
        }

        sections.append(
            FormKitRenderPlan.SectionDescriptor(
                id: sectionID,
                pointer: pointer,
                parentPointer: parentPointer,
                propertyKey: propertyKey,
                title: sectionTitle,
                description: sectionDescription,
                depth: depth,
                isRequired: isRequiredInParent,
                order: sectionOrder,
                fieldIDs: sectionFieldIDs,
                propertyOrder: propertyOrder,
                ownerArrayRowID: ownerArrayRowID,
                renderBehavior: sectionRenderBehavior,
                conditionalState: sectionConditionalState,
                arrayDescriptor: nil
            )
        )

        return true
    }

    private func supportsObjectSchema(
        _ schemaObject: [String: FormKitJSONValue],
        pointerTokens: [String],
        reasons: inout [FormKitUnsupportedReason]
    ) -> Bool {
        let pointer = JSONPointer.pointerString(from: pointerTokens)
        if let additionalProperties = schemaObject["additionalProperties"] {
            switch additionalProperties {
            case .boolean:
                break
            default:
                reasons.append(
                    .unsupportedKeyword(
                        keyword: "additionalProperties",
                        location: pointer,
                        message: String(localized: "Dynamic object keys are not supported in this renderer.")
                    )
                )
            }
        }

        for keyword in Self.blockedKeywords where schemaObject[keyword] != nil {
            reasons.append(
                .unsupportedKeyword(
                    keyword: keyword,
                    location: pointer,
                    message: String(localized: "This keyword changes the form structure in a way the renderer does not support yet.")
                )
            )
        }

        guard case .object = schemaType(
            for: schemaObject,
            pointerTokens: pointerTokens,
            reasons: &reasons
        ) else {
            reasons.append(
                .unsupportedSchemaShape(
                    location: pointer,
                    message: String(localized: "Only object schemas can create form sections.")
                )
            )
            return false
        }

        return true
    }

    @discardableResult
    private func parseArraySchema(
        schemaObject: [String: FormKitJSONValue],
        rootSchema: FormKitJSONValue,
        instanceValue: FormKitJSONValue?,
        pointerTokens: [String],
        schemaPathTokens: [String],
        propertyKey: String?,
        fallbackTitle: String,
        fallbackDescription: String?,
        isRequiredInParent: Bool,
        depth: Int,
        ownerArrayRowID: String? = nil,
        arrayContextDepth: Int,
        propertyOrderIndex: JSONSchemaPropertyOrderIndex,
        reasons: inout [FormKitUnsupportedReason],
        sections: inout [FormKitRenderPlan.SectionDescriptor],
        fields: inout [FormKitFieldDescriptor],
        nextSectionOrder: inout Int
    ) -> Bool {
        let pointer = JSONPointer.pointerString(from: pointerTokens)

        guard arrayContextDepth == 0 else {
            reasons.append(
                .unsupportedKeyword(
                    keyword: "items",
                    location: pointer,
                    message: String(localized: "Nested repeatable groups are not supported in this renderer yet.")
                )
            )
            return false
        }

        guard supportsArraySchema(
            schemaObject,
            pointerTokens: pointerTokens,
            reasons: &reasons
        ) else {
            return false
        }

        guard let itemsValue = schemaObject["items"] else {
            reasons.append(
                .unsupportedKeyword(
                    keyword: "items",
                    location: pointer,
                    message: String(localized: "Array rendering requires a single supported items schema.")
                )
            )
            return false
        }

        guard let materializedItemSchema = materializedSchemaObject(
            schemaValue: itemsValue,
            rootSchema: rootSchema,
            instanceValue: nil,
            pointerTokens: pointerTokens + ["items"],
            schemaPathTokens: schemaPathTokens + ["items"],
            propertyOrderIndex: propertyOrderIndex,
            reasons: &reasons
        ) else {
            return false
        }

        let itemType = schemaType(
            for: materializedItemSchema.object,
            pointerTokens: pointerTokens + ["items"],
            reasons: &reasons
        )

        guard itemType != .unsupported else {
            return false
        }

        if case .array = itemType {
            reasons.append(
                .unsupportedType(
                    typeDescription: "array",
                    location: JSONPointer.pointerString(from: pointerTokens + ["items"])
                )
            )
            return false
        }

        let sectionPointer = JSONPointer.pointerString(from: pointerTokens)
        let sectionID = sectionIdentifier(for: sectionPointer)
        let parentPointer = pointerTokens.isEmpty
            ? nil
            : JSONPointer.pointerString(from: Array(pointerTokens.dropLast()))
        let sectionOrder = nextSectionOrder
        nextSectionOrder += 1
        let sectionTitle = schemaObject["title"]?.string?.trimmedForJSONSchemaForm()
            ?? propertyKey.map(humanizedPropertyKey)
            ?? fallbackTitle
        let sectionDescription = schemaObject["description"]?.string?.trimmedForJSONSchemaForm()
            ?? fallbackDescription
        let sectionRenderBehavior = resolvedRenderBehavior(from: schemaObject)
        let sectionConditionalState = conditionalRenderState(from: schemaObject)
        let itemTitle = itemDisplayTitle(
            arrayTitle: sectionTitle,
            itemSchema: materializedItemSchema.object
        )
        let existingItems = arraySeedValues(
            from: instanceValue,
            fallbackDefault: schemaObject["default"]
        )
        let minItems = max(0, schemaObject["minItems"]?.integer ?? 0)
        let maxItems = schemaObject["maxItems"]?.integer
        let rowCount = max(existingItems.count, minItems)
        let materializeWhenEmpty = instanceValue?.array != nil
            || schemaObject["default"]?.array != nil
            || isRequiredInParent
            || minItems > 0
        let newItemPlaceholder = arrayItemPlaceholder(
            from: materializedItemSchema.object,
            rootSchema: rootSchema,
            pointerTokens: pointerTokens + ["items"],
            schemaPathTokens: schemaPathTokens + ["items"],
            propertyOrderIndex: propertyOrderIndex,
            reasons: &reasons
        )

        var rows: [FormKitArrayRowDescriptor] = []
        for index in 0..<rowCount {
            let rowPointerTokens = pointerTokens + [String(index)]
            let rowPointer = JSONPointer.pointerString(from: rowPointerTokens)
            let rowTitle = String(
                format: String(localized: "%@ %d"),
                itemTitle,
                index + 1
            )
            let rowPlaceholder = existingItems[safe: index] ?? newItemPlaceholder
            let rowItemSchema = materializedSchemaObject(
                schemaValue: itemsValue,
                rootSchema: rootSchema,
                instanceValue: existingItems[safe: index],
                pointerTokens: pointerTokens + ["items"],
                schemaPathTokens: schemaPathTokens + ["items"],
                propertyOrderIndex: propertyOrderIndex,
                reasons: &reasons
            )

            switch itemType {
            case .scalar:
                guard let rowItemSchema else {
                    continue
                }
                let fieldTitle = String(
                    format: String(localized: "%@ %d"),
                    itemTitle,
                    index + 1
                )
                guard let field = makeFieldDescriptor(
                    propertyKey: String(index),
                    schemaObject: rowItemSchema.object,
                    pointerTokens: rowPointerTokens,
                    parentPointer: sectionPointer,
                    title: fieldTitle,
                    description: rowItemSchema.object["description"]?.string?.trimmedForJSONSchemaForm(),
                    isRequired: true,
                    reasons: &reasons
                ) else {
                    return false
                }
                fields.append(field)
                rows.append(
                    FormKitArrayRowDescriptor(
                        id: rowPointer,
                        pointer: rowPointer,
                        index: index,
                        title: rowTitle,
                        placeholderValue: rowPlaceholder,
                        fieldIDs: [field.id],
                        sectionIDs: []
                    )
                )

            case .object:
                guard let rowItemSchema else {
                    continue
                }
                let sectionCountBefore = sections.count
                guard parseObjectSchema(
                    schemaObject: itemsValue.object ?? rowItemSchema.object,
                    rootSchema: rootSchema,
                    instanceValue: existingItems[safe: index],
                    pointerTokens: rowPointerTokens,
                    schemaPathTokens: schemaPathTokens + ["items"],
                    propertyKey: propertyKey,
                    fallbackTitle: rowTitle,
                    fallbackDescription: rowItemSchema.object["description"]?.string?.trimmedForJSONSchemaForm(),
                    isRequiredInParent: true,
                    depth: depth + 1,
                    ownerArrayRowID: rowPointer,
                    arrayContextDepth: arrayContextDepth + 1,
                    propertyOrderIndex: propertyOrderIndex,
                    reasons: &reasons,
                    sections: &sections,
                    fields: &fields,
                    nextSectionOrder: &nextSectionOrder
                )
                else {
                    return false
                }

                let sectionIDs = sections[sectionCountBefore...].map(\.id)
                rows.append(
                    FormKitArrayRowDescriptor(
                        id: rowPointer,
                        pointer: rowPointer,
                        index: index,
                        title: rowTitle,
                        placeholderValue: rowPlaceholder,
                        fieldIDs: [],
                        sectionIDs: sectionIDs
                    )
                )

            case .array, .unsupported:
                return false
            }
        }

        let itemKind: FormKitArraySectionDescriptor.ItemKind = {
            switch itemType {
            case .scalar:
                return .scalar
            case .object:
                return .object
            case .array, .unsupported:
                return .object
            }
        }()

        sections.append(
            FormKitRenderPlan.SectionDescriptor(
                id: sectionID,
                pointer: sectionPointer,
                parentPointer: parentPointer,
                propertyKey: propertyKey,
                title: sectionTitle,
                description: sectionDescription,
                depth: depth,
                isRequired: isRequiredInParent,
                order: sectionOrder,
                fieldIDs: [],
                propertyOrder: [],
                ownerArrayRowID: ownerArrayRowID,
                renderBehavior: sectionRenderBehavior,
                conditionalState: sectionConditionalState,
                arrayDescriptor: FormKitArraySectionDescriptor(
                    pointer: sectionPointer,
                    propertyKey: propertyKey,
                    itemKind: itemKind,
                    itemTitle: itemTitle,
                    minItems: minItems,
                    maxItems: maxItems,
                    materializeWhenEmpty: materializeWhenEmpty,
                    newItemPlaceholder: newItemPlaceholder,
                    rows: rows
                )
            )
        )

        return true
    }

    private func supportsArraySchema(
        _ schemaObject: [String: FormKitJSONValue],
        pointerTokens: [String],
        reasons: inout [FormKitUnsupportedReason]
    ) -> Bool {
        let pointer = JSONPointer.pointerString(from: pointerTokens)
        var isSupported = true

        guard case .array = schemaType(
            for: schemaObject,
            pointerTokens: pointerTokens,
            reasons: &reasons
        ) else {
            reasons.append(
                .unsupportedSchemaShape(
                    location: pointer,
                    message: String(localized: "Only array schemas can create repeatable groups.")
                )
            )
            return false
        }

        for keyword in Self.blockedArrayKeywords where schemaObject[keyword] != nil {
            isSupported = false
            reasons.append(
                .unsupportedKeyword(
                    keyword: keyword,
                    location: pointer,
                    message: String(localized: "This array shape is not supported in the native renderer yet.")
                )
            )
        }

        guard isSupported else {
            return false
        }

        guard schemaObject["items"] != nil else {
            reasons.append(
                .unsupportedKeyword(
                    keyword: "items",
                    location: pointer,
                    message: String(localized: "Array schemas must declare a single items schema.")
                )
            )
            return false
        }

        return isSupported
    }

    private func materializedSchemaObject(
        schemaValue: FormKitJSONValue,
        rootSchema: FormKitJSONValue,
        instanceValue: FormKitJSONValue?,
        pointerTokens: [String],
        schemaPathTokens: [String],
        propertyOrderIndex: JSONSchemaPropertyOrderIndex,
        availableBaseSchema: MaterializedJSONSchemaObject? = nil,
        reasons: inout [FormKitUnsupportedReason]
    ) -> MaterializedJSONSchemaObject? {
        if case .boolean = schemaValue {
            return MaterializedJSONSchemaObject(object: [:], propertyOrder: [])
        }

        guard let schemaObject = schemaValue.object else {
            reasons.append(
                .unsupportedSchemaShape(
                    location: JSONPointer.pointerString(from: pointerTokens),
                    message: String(localized: "Rendered schema nodes must resolve to objects.")
                )
            )
            return nil
        }

        guard let resolvedSchema = resolveReferencesIfNeeded(
            schemaObject: schemaObject,
            rootSchema: rootSchema,
            pointerTokens: pointerTokens,
            schemaPathTokens: schemaPathTokens,
            reasons: &reasons
        ) else {
            return nil
        }

        var effectiveSchema = MaterializedJSONSchemaObject(
            object: removingConsumedKeywords(from: resolvedSchema.object),
            propertyOrder: propertyNames(
                in: resolvedSchema.object["properties"]?.object ?? [:],
                schemaPathTokenOptions: resolvedSchema.propertyOrderPathTokens,
                propertyOrderIndex: propertyOrderIndex
            )
        )
        let conditionalBaseSchema = availableBaseSchema ?? effectiveSchema

        if let allOfSchemas = resolvedSchema.object["allOf"]?.array {
            for (index, rawSubschema) in allOfSchemas.enumerated() {
                guard let overlay = materializedSchemaObject(
                    schemaValue: rawSubschema,
                    rootSchema: rootSchema,
                    instanceValue: instanceValue,
                    pointerTokens: pointerTokens + ["allOf", String(index)],
                    schemaPathTokens: schemaPathTokens + ["allOf", String(index)],
                    propertyOrderIndex: propertyOrderIndex,
                    availableBaseSchema: conditionalBaseSchema,
                    reasons: &reasons
                ) else {
                    return nil
                }
                effectiveSchema = mergeSchemaObjects(effectiveSchema, overlay, includeRequired: true)
            }
        }

        if let dependencyObject = resolvedSchema.object["dependentRequired"]?.object,
           let instanceObject = instanceValue?.object
        {
            let requiredKeys = mergedRequiredKeys(
                from: effectiveSchema.object["required"],
                dependencyObject: dependencyObject,
                instanceKeys: Set(instanceObject.keys)
            )
            if !requiredKeys.isEmpty {
                effectiveSchema.object["required"] = .array(requiredKeys.map(FormKitJSONValue.string))
            }
        }

        if let dependencySchemas = resolvedSchema.object["dependentSchemas"]?.object {
            let instanceKeys = Set(instanceValue?.object?.map(\.key) ?? [])
            for (key, rawSubschema) in dependencySchemas {
                let schemaPointerTokens = pointerTokens + ["dependentSchemas", key]
                guard let overlay = materializedSchemaObject(
                    schemaValue: rawSubschema,
                    rootSchema: rootSchema,
                    instanceValue: instanceValue,
                    pointerTokens: schemaPointerTokens,
                    schemaPathTokens: schemaPathTokens + ["dependentSchemas", key],
                    propertyOrderIndex: propertyOrderIndex,
                    availableBaseSchema: conditionalBaseSchema,
                    reasons: &reasons
                ) else {
                    return nil
                }

                if instanceKeys.contains(key) {
                    effectiveSchema = mergeSchemaObjects(effectiveSchema, overlay, includeRequired: true)
                } else if let inactiveOverlay = inactiveRenderableSchemaObject(
                    from: overlay,
                    within: conditionalBaseSchema
                ) {
                    effectiveSchema = mergeInactiveSchemaObjects(effectiveSchema, inactiveOverlay)
                }
            }
        }

        if let ifSchema = resolvedSchema.object["if"] {
            let conditionMet = schemaMatches(
                schemaValue: ifSchema,
                rootSchema: rootSchema,
                instanceValue: instanceValue,
                pointerTokens: pointerTokens + ["if"],
                reasons: &reasons
            )

            let activeBranchKeyword = conditionMet ? "then" : "else"
            let inactiveBranchKeyword = conditionMet ? "else" : "then"
            if let branchSchema = resolvedSchema.object[activeBranchKeyword] {
                guard let overlay = materializedSchemaObject(
                    schemaValue: branchSchema,
                    rootSchema: rootSchema,
                    instanceValue: instanceValue,
                    pointerTokens: pointerTokens + [activeBranchKeyword],
                    schemaPathTokens: schemaPathTokens + [activeBranchKeyword],
                    propertyOrderIndex: propertyOrderIndex,
                    availableBaseSchema: conditionalBaseSchema,
                    reasons: &reasons
                ) else {
                    return nil
                }
                effectiveSchema = mergeSchemaObjects(effectiveSchema, overlay, includeRequired: true)
            }

            if let branchSchema = resolvedSchema.object[inactiveBranchKeyword] {
                guard let overlay = materializedSchemaObject(
                    schemaValue: branchSchema,
                    rootSchema: rootSchema,
                    instanceValue: instanceValue,
                    pointerTokens: pointerTokens + [inactiveBranchKeyword],
                    schemaPathTokens: schemaPathTokens + [inactiveBranchKeyword],
                    propertyOrderIndex: propertyOrderIndex,
                    availableBaseSchema: conditionalBaseSchema,
                    reasons: &reasons
                ) else {
                    return nil
                }

                if let inactiveOverlay = inactiveRenderableSchemaObject(
                    from: overlay,
                    within: conditionalBaseSchema
                ) {
                    effectiveSchema = mergeInactiveSchemaObjects(effectiveSchema, inactiveOverlay)
                }
            }
        }

        if let anyOfSchemas = resolvedSchema.object["anyOf"]?.array {
            guard let materialization = materializedCompositeOverlay(
                keyword: "anyOf",
                schemas: anyOfSchemas,
                rootSchema: rootSchema,
                instanceValue: instanceValue,
                pointerTokens: pointerTokens + ["anyOf"],
                schemaPathTokens: schemaPathTokens + ["anyOf"],
                propertyOrderIndex: propertyOrderIndex,
                reasons: &reasons
            ) else {
                return nil
            }
            effectiveSchema = mergeSchemaObjects(
                effectiveSchema,
                materialization.activeOverlay,
                includeRequired: materialization.includeRequired
            )
            for inactiveOverlay in materialization.inactiveOverlays {
                effectiveSchema = mergeInactiveSchemaObjects(effectiveSchema, inactiveOverlay)
            }
        }

        if let oneOfSchemas = resolvedSchema.object["oneOf"]?.array {
            guard let materialization = materializedCompositeOverlay(
                keyword: "oneOf",
                schemas: oneOfSchemas,
                rootSchema: rootSchema,
                instanceValue: instanceValue,
                pointerTokens: pointerTokens + ["oneOf"],
                schemaPathTokens: schemaPathTokens + ["oneOf"],
                propertyOrderIndex: propertyOrderIndex,
                reasons: &reasons
            ) else {
                return nil
            }
            effectiveSchema = mergeSchemaObjects(
                effectiveSchema,
                materialization.activeOverlay,
                includeRequired: materialization.includeRequired
            )
            for inactiveOverlay in materialization.inactiveOverlays {
                effectiveSchema = mergeInactiveSchemaObjects(effectiveSchema, inactiveOverlay)
            }
        }

        return effectiveSchema
    }

    private func materializedCompositeOverlay(
        keyword: String,
        schemas: [FormKitJSONValue],
        rootSchema: FormKitJSONValue,
        instanceValue: FormKitJSONValue?,
        pointerTokens: [String],
        schemaPathTokens: [String],
        propertyOrderIndex: JSONSchemaPropertyOrderIndex,
        reasons: inout [FormKitUnsupportedReason]
    ) -> CompositeOverlayMaterialization? {
        var candidates: [CompositeOverlayCandidate] = []

        for (index, rawSubschema) in schemas.enumerated() {
            guard let overlay = materializedSchemaObject(
                schemaValue: rawSubschema,
                rootSchema: rootSchema,
                instanceValue: instanceValue,
                pointerTokens: pointerTokens + [String(index)],
                schemaPathTokens: schemaPathTokens + [String(index)],
                propertyOrderIndex: propertyOrderIndex,
                reasons: &reasons
            ) else {
                return nil
            }

            let isValid = schemaMatches(
                schemaValue: rawSubschema,
                rootSchema: rootSchema,
                instanceValue: instanceValue,
                pointerTokens: pointerTokens + [String(index)],
                reasons: &reasons
            )

            candidates.append(
                CompositeOverlayCandidate(
                    index: index,
                    overlay: overlay,
                    isValid: isValid,
                    discriminatorScore: discriminatorScore(
                        for: overlay.object,
                        instanceValue: instanceValue
                    )
                )
            )
        }

        let selectedIndices: Set<Int>
        let includeRequired: Bool
        let validIndices = Set(candidates.filter(\.isValid).map(\.index))
        if keyword == "oneOf", validIndices.count == 1 {
            selectedIndices = validIndices
            includeRequired = true
        } else if keyword == "oneOf",
                  let discriminatedIndex = uniqueDiscriminatorOverlay(from: candidates)
        {
            selectedIndices = [discriminatedIndex]
            includeRequired = true
        } else if keyword == "anyOf", !validIndices.isEmpty {
            selectedIndices = validIndices
            includeRequired = true
        } else {
            selectedIndices = Set(candidates.map(\.index))
            includeRequired = false
        }

        var merged = MaterializedJSONSchemaObject(object: [:], propertyOrder: [])
        for candidate in candidates where selectedIndices.contains(candidate.index) {
            merged = mergeSchemaObjects(merged, candidate.overlay, includeRequired: includeRequired)
        }

        let inactiveOverlays = candidates
            .filter { !selectedIndices.contains($0.index) }
            .compactMap {
                inactiveRenderableSchemaObject(from: $0.overlay)
            }

        return CompositeOverlayMaterialization(
            activeOverlay: merged,
            inactiveOverlays: inactiveOverlays,
            includeRequired: includeRequired
        )
    }

    private func inactiveRenderableSchemaObject(
        from schemaObject: MaterializedJSONSchemaObject,
        within baseSchema: MaterializedJSONSchemaObject? = nil,
        inheritedBehavior: FormKitConditionalRenderBehavior? = nil
    ) -> MaterializedJSONSchemaObject? {
        let transformedObject = inactiveRenderableSchemaObject(
            from: schemaObject.object,
            inheritedBehavior: inheritedBehavior
        )

        var mergedProperties = transformedObject?["properties"]?.object ?? [:]
        let overlayRenderBehavior = resolvedRenderBehavior(
            from: schemaObject.object,
            inheritedBehavior: inheritedBehavior
        )
        if let baseProperties = baseSchema?.object["properties"]?.object {
            let requiredKeys = schemaObject.object["required"]?.array?.compactMap(\.string) ?? []
            for key in requiredKeys where mergedProperties[key] == nil {
                guard let basePropertySchema = baseProperties[key]?.object else {
                    continue
                }
                mergedProperties[key] = .object(
                    forceInactiveSchemaObject(
                        from: basePropertySchema,
                        inheritedBehavior: overlayRenderBehavior
                    )
                )
            }
        }

        var effectiveObject = transformedObject ?? [:]
        if mergedProperties.isEmpty {
            effectiveObject.removeValue(forKey: "properties")
        } else {
            effectiveObject["properties"] = .object(mergedProperties)
        }

        let hasRenderableChildren = effectiveObject["properties"]?.object?.isEmpty == false
            || effectiveObject["items"] != nil
        guard transformedObject != nil || hasRenderableChildren else {
            return nil
        }

        let propertyOrder = mergePropertyOrder(
            schemaObject.propertyOrder,
            baseSchema?.propertyOrder ?? [],
            properties: effectiveObject["properties"]?.object ?? [:]
        )
        return MaterializedJSONSchemaObject(
            object: effectiveObject,
            propertyOrder: propertyOrder
        )
    }

    private func forceInactiveSchemaObject(
        from schemaObject: [String: FormKitJSONValue],
        inheritedBehavior: FormKitConditionalRenderBehavior? = nil
    ) -> [String: FormKitJSONValue] {
        let renderBehavior = resolvedRenderBehavior(
            from: schemaObject,
            inheritedBehavior: inheritedBehavior
        )

        var transformed = schemaObject

        if let properties = schemaObject["properties"]?.object {
            transformed["properties"] = .object(
                properties.compactMapValues { rawPropertyValue -> FormKitJSONValue? in
                    guard let propertySchema = rawPropertyValue.object else {
                        return rawPropertyValue
                    }
                    return .object(
                        forceInactiveSchemaObject(
                            from: propertySchema,
                            inheritedBehavior: renderBehavior
                        )
                    )
                }
            )
        }

        if let itemsSchema = schemaObject["items"]?.object {
            transformed["items"] = .object(
                forceInactiveSchemaObject(
                    from: itemsSchema,
                    inheritedBehavior: renderBehavior
                )
            )
        }

        transformed[Self.internalConditionalStateKey] = .string(
            FormKitConditionalRenderState.inactive.rawValue
        )
        transformed[Self.internalResolvedRenderBehaviorKey] = .string(renderBehavior.rawValue)
        return transformed
    }

    private func inactiveRenderableSchemaObject(
        from schemaObject: [String: FormKitJSONValue],
        inheritedBehavior: FormKitConditionalRenderBehavior? = nil
    ) -> [String: FormKitJSONValue]? {
        let renderBehavior = resolvedRenderBehavior(
            from: schemaObject,
            inheritedBehavior: inheritedBehavior
        )

        var transformed = schemaObject

        if let properties = schemaObject["properties"]?.object {
            let renderableProperties = properties.compactMapValues { rawPropertyValue -> FormKitJSONValue? in
                guard let propertySchema = rawPropertyValue.object,
                      let inactiveProperty = inactiveRenderableSchemaObject(
                        from: propertySchema,
                        inheritedBehavior: renderBehavior
                      )
                else {
                    return nil
                }
                return .object(inactiveProperty)
            }

            if renderableProperties.isEmpty {
                transformed.removeValue(forKey: "properties")
            } else {
                transformed["properties"] = .object(renderableProperties)
            }
        }

        if let itemsSchema = schemaObject["items"]?.object {
            if let inactiveItemsSchema = inactiveRenderableSchemaObject(
                from: itemsSchema,
                inheritedBehavior: renderBehavior
            ) {
                transformed["items"] = .object(inactiveItemsSchema)
            } else {
                transformed.removeValue(forKey: "items")
            }
        }

        let hasRenderableChildren = transformed["properties"]?.object?.isEmpty == false
            || transformed["items"] != nil

        guard renderBehavior != .hide || hasRenderableChildren else {
            return nil
        }

        if renderBehavior != .hide {
            transformed[Self.internalConditionalStateKey] = .string(
                FormKitConditionalRenderState.inactive.rawValue
            )
            transformed[Self.internalResolvedRenderBehaviorKey] = .string(renderBehavior.rawValue)
        }

        return transformed
    }

    private func arraySeedValues(
        from instanceValue: FormKitJSONValue?,
        fallbackDefault: FormKitJSONValue?
    ) -> [FormKitJSONValue] {
        if let items = instanceValue?.array {
            return items
        }

        if let items = fallbackDefault?.array {
            return items
        }

        return []
    }

    private func itemDisplayTitle(
        arrayTitle: String,
        itemSchema: [String: FormKitJSONValue]
    ) -> String {
        if let explicitTitle = itemSchema["title"]?.string?.trimmedForJSONSchemaForm(),
           !explicitTitle.isEmpty
        {
            return explicitTitle
        }

        let trimmedTitle = arrayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.count > 1 else {
            return String(localized: "Item")
        }

        if trimmedTitle.hasSuffix("ies") {
            return String(trimmedTitle.dropLast(3)) + "y"
        }

        if trimmedTitle.hasSuffix("s") {
            return String(trimmedTitle.dropLast())
        }

        return trimmedTitle
    }

    private func arrayItemPlaceholder(
        from schemaObject: [String: FormKitJSONValue],
        rootSchema: FormKitJSONValue,
        pointerTokens: [String],
        schemaPathTokens: [String],
        propertyOrderIndex: JSONSchemaPropertyOrderIndex,
        reasons: inout [FormKitUnsupportedReason]
    ) -> FormKitJSONValue {
        switch schemaType(
            for: schemaObject,
            pointerTokens: pointerTokens,
            reasons: &reasons
        ) {
        case .scalar(let primitiveType, let allowsNull):
            guard let scalarType = scalarType(
                from: primitiveType,
                format: schemaObject["format"]?.string?.trimmedForJSONSchemaForm(),
                location: JSONPointer.pointerString(from: pointerTokens),
                reasons: &reasons
            ) else {
                return .null
            }

            if let defaultValue = primitiveValue(
                from: schemaObject["default"],
                scalarType: scalarType,
                allowsNull: allowsNull
            ) {
                return jsonValue(from: defaultValue)
            }

            if let firstOption = enumOptions(
                from: schemaObject["enum"]?.array ?? schemaObject["const"].map { [$0] },
                scalarType: scalarType,
                location: JSONPointer.pointerString(from: pointerTokens),
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
            case .integer, .number:
                return .string("")
            case .string, .email, .uri, .date, .dateTime:
                return .string("")
            }

        case .object:
            var object: [String: FormKitJSONValue] = [:]
            let requiredKeys = Set(requiredPropertyNames(in: schemaObject, instance: nil))
            let properties = schemaObject["properties"]?.object ?? [:]
            for name in propertyNames(
                in: properties,
                schemaPathTokens: schemaPathTokens,
                propertyOrderIndex: propertyOrderIndex
            ) {
                guard let propertySchemaValue = properties[name],
                      let propertySchemaObject = materializedSchemaObject(
                        schemaValue: propertySchemaValue,
                        rootSchema: rootSchema,
                        instanceValue: nil,
                        pointerTokens: pointerTokens + [name],
                        schemaPathTokens: schemaPathTokens + ["properties", name],
                        propertyOrderIndex: propertyOrderIndex,
                        reasons: &reasons
                      )
                else {
                    continue
                }

                let childPlaceholder = arrayItemPlaceholder(
                    from: propertySchemaObject.object,
                    rootSchema: rootSchema,
                    pointerTokens: pointerTokens + [name],
                    schemaPathTokens: schemaPathTokens + ["properties", name],
                    propertyOrderIndex: propertyOrderIndex,
                    reasons: &reasons
                )

                let childType = schemaType(
                    for: propertySchemaObject.object,
                    pointerTokens: pointerTokens + [name],
                    reasons: &reasons
                )

                if propertySchemaObject.object["default"] != nil {
                    object[name] = childPlaceholder
                    continue
                }

                switch childType {
                case .object:
                    if requiredKeys.contains(name) || childPlaceholder != .object([:]) {
                        object[name] = childPlaceholder
                    }
                case .array:
                    if requiredKeys.contains(name) || childPlaceholder != .array([]) {
                        object[name] = childPlaceholder
                    }
                case .scalar, .unsupported:
                    continue
                }
            }
            return .object(object)

        case .array, .unsupported:
            return .null
        }
    }

    private func uniqueDiscriminatorOverlay(
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

    private func discriminatorScore(
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

    private func schemaMatches(
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

    private func defaultEvaluationInstance(for schemaValue: FormKitJSONValue) -> FormKitJSONValue {
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

    private func mergedRequiredKeys(
        from existingRequired: FormKitJSONValue?,
        dependencyObject: [String: FormKitJSONValue],
        instanceKeys: Set<String>
    ) -> [String] {
        var orderedKeys = existingRequired?.array?.compactMap(\.string) ?? []
        var requiredKeys = Set(orderedKeys)

        for (key, rawValues) in dependencyObject where instanceKeys.contains(key) {
            for dependencyKey in rawValues.array?.compactMap(\.string) ?? [] where !requiredKeys.contains(dependencyKey) {
                requiredKeys.insert(dependencyKey)
                orderedKeys.append(dependencyKey)
            }
        }

        return orderedKeys
    }

    private func removingConsumedKeywords(
        from schemaObject: [String: FormKitJSONValue]
    ) -> [String: FormKitJSONValue] {
        var cleaned = schemaObject
        for keyword in Self.consumedKeywords {
            cleaned.removeValue(forKey: keyword)
        }
        return cleaned
    }

    private func mergeSchemaObjects(
        _ base: MaterializedJSONSchemaObject,
        _ overlay: MaterializedJSONSchemaObject,
        includeRequired: Bool
    ) -> MaterializedJSONSchemaObject {
        let mergedObject = mergeSchemaObjects(base.object, overlay.object, includeRequired: includeRequired)
        let mergedPropertyOrder = mergePropertyOrder(
            base.propertyOrder,
            overlay.propertyOrder,
            properties: mergedObject["properties"]?.object ?? [:]
        )
        return MaterializedJSONSchemaObject(
            object: mergedObject,
            propertyOrder: mergedPropertyOrder
        )
    }

    private func mergeInactiveSchemaObjects(
        _ base: MaterializedJSONSchemaObject,
        _ overlay: MaterializedJSONSchemaObject
    ) -> MaterializedJSONSchemaObject {
        let mergedObject = mergeInactiveSchemaObjects(base.object, overlay.object)
        let mergedPropertyOrder = mergePropertyOrder(
            base.propertyOrder,
            overlay.propertyOrder,
            properties: mergedObject["properties"]?.object ?? [:]
        )
        return MaterializedJSONSchemaObject(
            object: mergedObject,
            propertyOrder: mergedPropertyOrder
        )
    }

    private func mergePropertyOrder(
        _ base: [String],
        _ overlay: [String],
        properties: [String: FormKitJSONValue]
    ) -> [String] {
        guard !properties.isEmpty else {
            return []
        }

        var orderedKeys: [String] = []
        var seenKeys = Set<String>()
        let propertyKeys = Set(properties.keys)

        for key in base where propertyKeys.contains(key) && seenKeys.insert(key).inserted {
            orderedKeys.append(key)
        }

        for key in overlay where propertyKeys.contains(key) && seenKeys.insert(key).inserted {
            orderedKeys.append(key)
        }

        for key in properties.keys where seenKeys.insert(key).inserted {
            orderedKeys.append(key)
        }

        return orderedKeys
    }

    private func mergeSchemaObjects(
        _ base: [String: FormKitJSONValue],
        _ overlay: [String: FormKitJSONValue],
        includeRequired: Bool
    ) -> [String: FormKitJSONValue] {
        var merged = base

        for (key, overlayValue) in overlay {
            switch key {
            case "required":
                guard includeRequired else {
                    continue
                }

                let existingKeys = merged[key]?.array?.compactMap(\.string) ?? []
                let overlayKeys = overlayValue.array?.compactMap(\.string) ?? []
                var orderedKeys = existingKeys
                let existingSet = Set(existingKeys)
                for overlayKey in overlayKeys where !existingSet.contains(overlayKey) && !orderedKeys.contains(overlayKey) {
                    orderedKeys.append(overlayKey)
                }
                merged[key] = .array(orderedKeys.map(FormKitJSONValue.string))

            case "properties", "$defs", "definitions":
                let existingObject = merged[key]?.object ?? [:]
                let overlayObject = overlayValue.object ?? [:]
                merged[key] = .object(
                    mergeSchemaDictionary(
                        existingObject,
                        overlayObject,
                        includeRequired: includeRequired
                    )
                )

            default:
                if let existingObject = merged[key]?.object,
                   let overlayObject = overlayValue.object
                {
                    merged[key] = .object(
                        mergeSchemaObjects(
                            existingObject,
                            overlayObject,
                            includeRequired: includeRequired
                        )
                    )
                } else {
                    merged[key] = overlayValue
                }
            }
        }

        return merged
    }

    private func mergeInactiveSchemaObjects(
        _ base: [String: FormKitJSONValue],
        _ overlay: [String: FormKitJSONValue]
    ) -> [String: FormKitJSONValue] {
        var merged = base

        for (key, overlayValue) in overlay {
            switch key {
            case "required":
                continue

            case "properties", "$defs", "definitions":
                let existingObject = merged[key]?.object ?? [:]
                let overlayObject = overlayValue.object ?? [:]
                merged[key] = .object(
                    mergeInactiveSchemaDictionary(existingObject, overlayObject)
                )

            default:
                guard merged[key] == nil else {
                    continue
                }
                merged[key] = overlayValue
            }
        }

        return merged
    }

    private func mergeInactiveSchemaDictionary(
        _ base: [String: FormKitJSONValue],
        _ overlay: [String: FormKitJSONValue]
    ) -> [String: FormKitJSONValue] {
        var merged = base
        for (key, overlayValue) in overlay {
            if let existingObject = merged[key]?.object,
               let overlayObject = overlayValue.object
            {
                merged[key] = .object(
                    mergeInactiveSchemaObjects(existingObject, overlayObject)
                )
            } else if merged[key] == nil {
                merged[key] = overlayValue
            }
        }
        return merged
    }

    private func mergeSchemaDictionary(
        _ base: [String: FormKitJSONValue],
        _ overlay: [String: FormKitJSONValue],
        includeRequired: Bool
    ) -> [String: FormKitJSONValue] {
        var merged = base
        for (key, overlayValue) in overlay {
            if let existingObject = merged[key]?.object,
               let overlayObject = overlayValue.object
            {
                merged[key] = .object(
                    mergeSchemaObjects(
                        existingObject,
                        overlayObject,
                        includeRequired: includeRequired
                    )
                )
            } else {
                merged[key] = overlayValue
            }
        }
        return merged
    }

    private func makeFieldDescriptor(
        propertyKey: String,
        schemaObject: [String: FormKitJSONValue],
        pointerTokens: [String],
        parentPointer: String,
        title: String,
        description: String?,
        isRequired: Bool,
        reasons: inout [FormKitUnsupportedReason]
    ) -> FormKitFieldDescriptor? {
        let pointer = JSONPointer.pointerString(from: pointerTokens)

        for keyword in Self.blockedKeywords where schemaObject[keyword] != nil {
            reasons.append(
                .unsupportedKeyword(
                    keyword: keyword,
                    location: pointer,
                    message: String(localized: "This field shape is not supported in the native renderer yet.")
                )
            )
        }

        let typeResult = schemaType(for: schemaObject, pointerTokens: pointerTokens, reasons: &reasons)
        switch typeResult {
        case .unsupported:
            return nil
        case .object:
            reasons.append(
                .unsupportedSchemaShape(
                    location: pointer,
                    message: String(localized: "Object nodes must be rendered as sections.")
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
        case .scalar(let primitiveType, let allowsNull):
            let fieldScalarType = scalarType(
                from: primitiveType,
                format: schemaObject["format"]?.string?.trimmedForJSONSchemaForm(),
                location: pointer,
                reasons: &reasons
            )

            guard let fieldScalarType else {
                return nil
            }

            let enumOptions = enumOptions(
                from: schemaObject["enum"]?.array ?? schemaObject["const"].map { [$0] },
                scalarType: fieldScalarType,
                location: pointer,
                reasons: &reasons
            )

            let defaultValue = primitiveValue(
                from: schemaObject["default"],
                scalarType: fieldScalarType,
                allowsNull: allowsNull
            )

            return FormKitFieldDescriptor(
                id: pointer,
                pointer: pointer,
                parentPointer: parentPointer,
                propertyKey: propertyKey,
                title: title,
                description: description,
                scalarType: fieldScalarType,
                enumOptions: enumOptions,
                isRequired: isRequired,
                allowsNull: allowsNull,
                defaultValue: defaultValue,
                renderBehavior: resolvedRenderBehavior(from: schemaObject),
                conditionalState: conditionalRenderState(from: schemaObject),
                accessibilityIdentifier: accessibilityIdentifier(for: pointer)
            )
        }
    }

    private func resolvedRenderBehavior(
        from schemaObject: [String: FormKitJSONValue],
        inheritedBehavior: FormKitConditionalRenderBehavior? = nil
    ) -> FormKitConditionalRenderBehavior {
        if let rawValue = (
            schemaObject[Self.renderBehaviorAnnotationKey]?.string
                ?? schemaObject[Self.legacyRenderBehaviorAnnotationKey]?.string
                ?? schemaObject[Self.internalResolvedRenderBehaviorKey]?.string
        )?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let behavior = FormKitConditionalRenderBehavior(rawValue: rawValue)
        {
            return behavior
        }

        return inheritedBehavior ?? defaultConditionalRenderBehavior
    }

    private func conditionalRenderState(
        from schemaObject: [String: FormKitJSONValue]
    ) -> FormKitConditionalRenderState {
        guard schemaObject[Self.internalConditionalStateKey]?.string == FormKitConditionalRenderState.inactive.rawValue else {
            return .active
        }

        return .inactive
    }

    private func seedFieldValues(
        for renderPlan: FormKitRenderPlan,
        instance: FormKitJSONValue?
    ) -> [String: FormKitFieldDescriptor.PrimitiveValue?] {
        renderPlan.fields.reduce(into: [:]) { result, field in
            let seededValue = seededValue(for: field, instance: instance)
            result[field.id] = seededValue
        }
    }

    private func seededValue(
        for field: FormKitFieldDescriptor,
        instance: FormKitJSONValue?
    ) -> FormKitFieldDescriptor.PrimitiveValue? {
        if let instance,
           let instanceValue = instance.value(at: JSONPointer(from: field.pointer))
        {
            return primitiveValue(
                from: instanceValue,
                scalarType: field.scalarType,
                allowsNull: field.allowsNull
            )
        }

        if let defaultValue = field.defaultValue {
            return defaultValue
        }

        if field.enumOptions.isEmpty == false && field.isRequired {
            return field.enumOptions.first?.value
        }

        switch field.scalarType {
        case .boolean where field.isRequired:
            return .boolean(false)
        case .date where field.isRequired:
            return .string(Self.dateFormatter.string(from: .now))
        case .dateTime where field.isRequired:
            return .string(Self.dateTimeFormatter.string(from: .now))
        default:
            return nil
        }
    }

    private func schemaType(
        for schemaObject: [String: FormKitJSONValue],
        pointerTokens: [String],
        reasons: inout [FormKitUnsupportedReason]
    ) -> SupportedSchemaType {
        let pointer = JSONPointer.pointerString(from: pointerTokens)

        if let constValue = schemaObject["const"],
           schemaObject["type"] == nil
        {
            switch constValue {
            case .string:
                return .scalar(.string, allowsNull: false)
            case .integer:
                return .scalar(.integer, allowsNull: false)
            case .number:
                return .scalar(.number, allowsNull: false)
            case .boolean:
                return .scalar(.boolean, allowsNull: false)
            case .null, .array, .object:
                reasons.append(
                    .unsupportedType(
                        typeDescription: constValue.primitive.rawValue,
                        location: pointer
                    )
                )
                return .unsupported
            }
        }

        if let enumValues = schemaObject["enum"]?.array,
           schemaObject["type"] == nil
        {
            let allowsNull = enumValues.contains(.null)
            let nonNullValues = enumValues.filter { $0 != .null }
            guard let firstValue = nonNullValues.first else {
                reasons.append(.unsupportedSchemaShape(location: pointer, message: String(localized: "Enums must include at least one concrete value.")))
                return .unsupported
            }

            switch firstValue {
            case .string:
                return .scalar(.string, allowsNull: allowsNull)
            case .integer:
                return .scalar(.integer, allowsNull: allowsNull)
            case .number:
                return .scalar(.number, allowsNull: allowsNull)
            case .boolean:
                return .scalar(.boolean, allowsNull: allowsNull)
            case .null, .array, .object:
                reasons.append(.unsupportedType(typeDescription: firstValue.primitive.rawValue, location: pointer))
                return .unsupported
            }
        }

        guard let typeValue = schemaObject["type"] else {
            if schemaObject["properties"] != nil || schemaObject["required"] != nil {
                return .object
            }

            reasons.append(
                .unsupportedSchemaShape(
                    location: pointer,
                    message: String(localized: "Every supported schema node must declare a type or enum.")
                )
            )
            return .unsupported
        }

        switch typeValue {
        case .string(let typeString):
            switch typeString {
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
                reasons.append(.unsupportedType(typeDescription: typeString, location: pointer))
                return .unsupported
            }

        case .array(let types):
            let resolvedTypes = types.compactMap(\.string)
            let nonNullTypes = resolvedTypes.filter { $0 != "null" }
            let allowsNull = resolvedTypes.contains("null")

            guard allowsNull,
                  resolvedTypes.count == 2,
                  let onlyType = nonNullTypes.first
            else {
                reasons.append(
                    .unsupportedSchemaShape(
                        location: pointer,
                        message: String(localized: "Union types are only supported for nullable primitives.")
                    )
                )
                return .unsupported
            }

            switch onlyType {
            case "string":
                return .scalar(.string, allowsNull: true)
            case "integer":
                return .scalar(.integer, allowsNull: true)
            case "number":
                return .scalar(.number, allowsNull: true)
            case "boolean":
                return .scalar(.boolean, allowsNull: true)
            default:
                reasons.append(.unsupportedType(typeDescription: onlyType, location: pointer))
                return .unsupported
            }

        default:
            reasons.append(
                .unsupportedSchemaShape(
                    location: pointer,
                    message: String(localized: "Type declarations must be strings or nullable primitive unions.")
                )
            )
            return .unsupported
        }
    }

    private func scalarType(
        from primitiveType: PrimitiveSchemaType,
        format: String?,
        location: String,
        reasons: inout [FormKitUnsupportedReason]
    ) -> FormKitFieldDescriptor.ScalarType? {
        switch primitiveType {
        case .string:
            switch format {
            case nil, "":
                return .string
            case "email":
                return .email
            case "uri":
                return .uri
            case "date":
                return .date
            case "date-time":
                return .dateTime
            default:
                reasons.append(
                    .unsupportedKeyword(
                        keyword: "format",
                        location: location,
                        message: String(localized: "Only email, uri, date, and date-time formats are supported in v1.")
                    )
                )
                return nil
            }
        case .integer:
            return .integer
        case .number:
            return .number
        case .boolean:
            return .boolean
        }
    }

    private func enumOptions(
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
                        message: String(localized: "Enum options must match the rendered field type.")
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

    private func primitiveValue(
        from jsonValue: FormKitJSONValue?,
        scalarType: FormKitFieldDescriptor.ScalarType,
        allowsNull: Bool
    ) -> FormKitFieldDescriptor.PrimitiveValue? {
        guard let jsonValue else {
            return nil
        }

        switch jsonValue {
        case .null:
            return allowsNull ? .null : nil
        case .string(let value):
            switch scalarType {
            case .string, .email, .uri, .date, .dateTime:
                return .string(value)
            case .integer, .number:
                return .string(value)
            default:
                return nil
            }
        case .integer(let value):
            switch scalarType {
            case .integer:
                return .integer(value)
            case .number:
                return .number(Double(value))
            default:
                return nil
            }
        case .number(let value):
            switch scalarType {
            case .number:
                return .number(value)
            default:
                return nil
            }
        case .boolean(let value):
            guard scalarType == .boolean else {
                return nil
            }
            return .boolean(value)
        case .object, .array:
            return nil
        }
    }

    private func jsonValue(from primitive: FormKitFieldDescriptor.PrimitiveValue) -> FormKitJSONValue {
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

    private func resolveReferencesIfNeeded(
        schemaObject: [String: FormKitJSONValue],
        rootSchema: FormKitJSONValue,
        pointerTokens: [String],
        schemaPathTokens: [String],
        reasons: inout [FormKitUnsupportedReason]
    ) -> ResolvedSchemaObject? {
        guard let rawReference = schemaObject["$ref"]?.string?.trimmedForJSONSchemaForm() else {
            return ResolvedSchemaObject(
                object: schemaObject,
                propertyOrderPathTokens: [schemaPathTokens]
            )
        }

        let pointer = JSONPointer.pointerString(from: pointerTokens)
        guard rawReference.hasPrefix("#") else {
            reasons.append(.remoteReference(rawReference, location: pointer))
            return nil
        }

        let referencePathTokens = localReferencePathTokens(from: rawReference)
        let referencePointer = JSONPointer(from: rawReference)
        guard let resolvedSchema = rootSchema.value(at: referencePointer)?.object else {
            reasons.append(.unresolvedReference(rawReference, location: pointer))
            return nil
        }

        var merged = resolvedSchema
        for (key, value) in schemaObject where key != "$ref" {
            if let existingObject = merged[key]?.object,
               let overlayObject = value.object
            {
                merged[key] = .object(
                    mergeSchemaObjects(
                        existingObject,
                        overlayObject,
                        includeRequired: true
                    )
                )
            } else {
                merged[key] = value
            }
        }
        return ResolvedSchemaObject(
            object: merged,
            propertyOrderPathTokens: [
                referencePathTokens,
                schemaPathTokens
            ]
        )
    }

    private func propertyNames(
        in properties: [String: FormKitJSONValue],
        schemaPathTokens: [String],
        propertyOrderIndex: JSONSchemaPropertyOrderIndex,
        preferredOrder: [String] = []
    ) -> [String] {
        propertyNames(
            in: properties,
            schemaPathTokenOptions: [schemaPathTokens],
            propertyOrderIndex: propertyOrderIndex,
            preferredOrder: preferredOrder
        )
    }

    private func propertyNames(
        in properties: [String: FormKitJSONValue],
        schemaPathTokenOptions: [[String]],
        propertyOrderIndex: JSONSchemaPropertyOrderIndex,
        preferredOrder: [String] = []
    ) -> [String] {
        let declaredOrder = schemaPathTokenOptions.reduce(
            preferredOrder,
            { partialResult, schemaPathTokens in
                mergePropertyOrder(
                    partialResult,
                    propertyOrderIndex.propertyNames(at: schemaPathTokens),
                    properties: properties
                )
            }
        )
        if !declaredOrder.isEmpty {
            return declaredOrder
        }
        return mergePropertyOrder(declaredOrder, [], properties: properties)
    }

    private func requiredPropertyNames(
        in schemaObject: [String: FormKitJSONValue],
        instance: FormKitJSONValue?
    ) -> [String] {
        schemaObject["required"]?.array?.compactMap(\.string) ?? []
    }

    private func humanizedPropertyKey(_ key: String) -> String {
        let withSpaces = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1 $2", options: .regularExpression)
        return withSpaces.capitalized
    }

    private func accessibilityIdentifier(for pointer: String) -> String {
        let sanitized = pointer
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "~1", with: "_")
            .replacingOccurrences(of: "~0", with: "_")
        return "json_form_field\(sanitized)"
    }

    private func sectionIdentifier(for pointer: String) -> String {
        "json_form_section\(pointer.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "#", with: ""))"
    }

    private func pointerForChild(_ key: String, in pointerTokens: [String]) -> String {
        JSONPointer.pointerString(from: pointerTokens + [key])
    }

    private func localReferencePathTokens(from reference: String) -> [String] {
        let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedReference.hasPrefix("#") else {
            return []
        }

        let rawPath = String(trimmedReference.dropFirst())
        guard !rawPath.isEmpty else {
            return []
        }

        return rawPath
            .split(separator: "/")
            .map(String.init)
            .map {
                $0
                    .replacingOccurrences(of: "~1", with: "/")
                    .replacingOccurrences(of: "~0", with: "~")
            }
    }

    private struct MaterializedJSONSchemaObject {
        var object: [String: FormKitJSONValue]
        var propertyOrder: [String]
    }

    private struct ResolvedSchemaObject {
        let object: [String: FormKitJSONValue]
        let propertyOrderPathTokens: [[String]]
    }

    private struct JSONSchemaPropertyOrderIndex {
        private let propertyNamesBySchemaPointer: [String: [String]]

        init(schemaJSON: String) throws {
            var propertyNamesBySchemaPointer: [String: [String]] = [:]
            var scanner = JSONSchemaPropertyOrderScanner(source: schemaJSON)
            try scanner.collectPropertyOrder(into: &propertyNamesBySchemaPointer)
            self.propertyNamesBySchemaPointer = propertyNamesBySchemaPointer
        }

        func propertyNames(at schemaPathTokens: [String]) -> [String] {
            propertyNamesBySchemaPointer[JSONPointer.pointerString(from: schemaPathTokens)] ?? []
        }
    }

    private struct JSONSchemaPropertyOrderScanner {
        private let characters: [Character]
        private var index: Int = 0

        init(source: String) {
            self.characters = Array(source)
        }

        mutating func collectPropertyOrder(
            into propertyNamesBySchemaPointer: inout [String: [String]]
        ) throws {
            try parseValue(
                at: [],
                propertyNamesBySchemaPointer: &propertyNamesBySchemaPointer
            )
            skipWhitespace()
            guard isAtEnd else {
                throw error("Unexpected trailing content.")
            }
        }

        private var isAtEnd: Bool {
            index >= characters.count
        }

        private mutating func parseValue(
            at schemaPathTokens: [String],
            propertyNamesBySchemaPointer: inout [String: [String]]
        ) throws {
            skipWhitespace()
            guard let character = currentCharacter else {
                throw error("Unexpected end of JSON input.")
            }

            switch character {
            case "{":
                try parseObject(
                    at: schemaPathTokens,
                    propertyNamesBySchemaPointer: &propertyNamesBySchemaPointer
                )
            case "[":
                try parseArray(
                    at: schemaPathTokens,
                    propertyNamesBySchemaPointer: &propertyNamesBySchemaPointer
                )
            case "\"":
                _ = try parseString()
            case "t":
                try consumeLiteral("true")
            case "f":
                try consumeLiteral("false")
            case "n":
                try consumeLiteral("null")
            case "-", "0"..."9":
                try parseNumber()
            default:
                throw error("Unexpected character \(character).")
            }
        }

        private mutating func parseObject(
            at schemaPathTokens: [String],
            propertyNamesBySchemaPointer: inout [String: [String]]
        ) throws {
            try consume("{")
            skipWhitespace()
            guard currentCharacter != "}" else {
                index += 1
                return
            }

            while true {
                let key = try parseString()
                skipWhitespace()
                try consume(":")

                if key == "properties" {
                    let propertyNames = try parsePropertiesObject(
                        at: schemaPathTokens,
                        propertyNamesBySchemaPointer: &propertyNamesBySchemaPointer
                    )
                    propertyNamesBySchemaPointer[JSONPointer.pointerString(from: schemaPathTokens)] = propertyNames
                } else {
                    try parseValue(
                        at: schemaPathTokens + [key],
                        propertyNamesBySchemaPointer: &propertyNamesBySchemaPointer
                    )
                }

                skipWhitespace()
                if currentCharacter == "," {
                    index += 1
                    skipWhitespace()
                    continue
                }

                try consume("}")
                return
            }
        }

        private mutating func parsePropertiesObject(
            at schemaPathTokens: [String],
            propertyNamesBySchemaPointer: inout [String: [String]]
        ) throws -> [String] {
            try consume("{")
            skipWhitespace()
            guard currentCharacter != "}" else {
                index += 1
                return []
            }

            var propertyNames: [String] = []
            while true {
                let key = try parseString()
                propertyNames.append(key)
                skipWhitespace()
                try consume(":")
                try parseValue(
                    at: schemaPathTokens + ["properties", key],
                    propertyNamesBySchemaPointer: &propertyNamesBySchemaPointer
                )

                skipWhitespace()
                if currentCharacter == "," {
                    index += 1
                    skipWhitespace()
                    continue
                }

                try consume("}")
                return propertyNames
            }
        }

        private mutating func parseArray(
            at schemaPathTokens: [String],
            propertyNamesBySchemaPointer: inout [String: [String]]
        ) throws {
            try consume("[")
            skipWhitespace()
            guard currentCharacter != "]" else {
                index += 1
                return
            }

            var itemIndex = 0
            while true {
                try parseValue(
                    at: schemaPathTokens + [String(itemIndex)],
                    propertyNamesBySchemaPointer: &propertyNamesBySchemaPointer
                )
                itemIndex += 1

                skipWhitespace()
                if currentCharacter == "," {
                    index += 1
                    skipWhitespace()
                    continue
                }

                try consume("]")
                return
            }
        }

        private mutating func parseString() throws -> String {
            try consume("\"")
            var result = ""

            while let character = currentCharacter {
                index += 1
                switch character {
                case "\"":
                    return result
                case "\\":
                    guard let escaped = currentCharacter else {
                        throw error("Unterminated escape sequence.")
                    }
                    index += 1
                    switch escaped {
                    case "\"", "\\", "/":
                        result.append(escaped)
                    case "b":
                        result.append("\u{08}")
                    case "f":
                        result.append("\u{0C}")
                    case "n":
                        result.append("\n")
                    case "r":
                        result.append("\r")
                    case "t":
                        result.append("\t")
                    case "u":
                        result.append(try parseUnicodeEscape())
                    default:
                        throw error("Invalid escape sequence.")
                    }
                default:
                    result.append(character)
                }
            }

            throw error("Unterminated string literal.")
        }

        private mutating func parseUnicodeEscape() throws -> String {
            let firstScalarValue = try parseUnicodeEscapeScalarValue()
            if (0xD800...0xDBFF).contains(firstScalarValue) {
                try consume("\\")
                try consume("u")
                let secondScalarValue = try parseUnicodeEscapeScalarValue()
                guard (0xDC00...0xDFFF).contains(secondScalarValue) else {
                    throw error("Invalid unicode escape.")
                }

                let combinedScalarValue = 0x10000
                    + ((firstScalarValue - 0xD800) << 10)
                    + (secondScalarValue - 0xDC00)
                guard let scalar = UnicodeScalar(combinedScalarValue) else {
                    throw error("Invalid unicode escape.")
                }
                return String(scalar)
            }

            guard !(0xDC00...0xDFFF).contains(firstScalarValue),
                  let scalar = UnicodeScalar(firstScalarValue)
            else {
                throw error("Invalid unicode escape.")
            }
            return String(scalar)
        }

        private mutating func parseUnicodeEscapeScalarValue() throws -> UInt32 {
            let hex = try consumeHexDigits(count: 4)
            guard let scalarValue = UInt32(hex, radix: 16) else {
                throw error("Invalid unicode escape.")
            }
            return scalarValue
        }

        private mutating func parseNumber() throws {
            guard currentCharacter != nil else {
                throw error("Unexpected end of number.")
            }

            if currentCharacter == "-" {
                index += 1
            }

            try consumeDigits(minimumCount: 1)

            if currentCharacter == "." {
                index += 1
                try consumeDigits(minimumCount: 1)
            }

            if currentCharacter == "e" || currentCharacter == "E" {
                index += 1
                if currentCharacter == "+" || currentCharacter == "-" {
                    index += 1
                }
                try consumeDigits(minimumCount: 1)
            }
        }

        private mutating func consumeLiteral(_ literal: String) throws {
            for character in literal {
                try consume(character)
            }
        }

        private mutating func consumeDigits(minimumCount: Int) throws {
            var count = 0
            while let character = currentCharacter, character.isNumber {
                index += 1
                count += 1
            }

            guard count >= minimumCount else {
                throw error("Expected digit.")
            }
        }

        private mutating func consumeHexDigits(count: Int) throws -> String {
            var hex = ""
            for _ in 0..<count {
                guard let character = currentCharacter,
                      character.isHexDigit
                else {
                    throw error("Expected hex digit.")
                }
                hex.append(character)
                index += 1
            }
            return hex
        }

        private mutating func consume(_ expected: Character) throws {
            skipWhitespace()
            guard currentCharacter == expected else {
                throw error("Expected \(expected).")
            }
            index += 1
        }

        private mutating func skipWhitespace() {
            while let character = currentCharacter, character.isWhitespace {
                index += 1
            }
        }

        private var currentCharacter: Character? {
            guard index < characters.count else {
                return nil
            }
            return characters[index]
        }

        private func error(_ message: String) -> NSError {
            NSError(
                domain: "JSONSchemaPropertyOrderScanner",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    private enum SupportedSchemaType: Equatable {
        case object
        case array
        case scalar(PrimitiveSchemaType, allowsNull: Bool)
        case unsupported
    }

    private enum PrimitiveSchemaType: Equatable {
        case string
        case integer
        case number
        case boolean
    }

    private struct CompositeOverlayCandidate {
        let index: Int
        let overlay: MaterializedJSONSchemaObject
        let isValid: Bool
        let discriminatorScore: Int?
    }

    private struct CompositeOverlayMaterialization {
        let activeOverlay: MaterializedJSONSchemaObject
        let inactiveOverlays: [MaterializedJSONSchemaObject]
        let includeRequired: Bool
    }

    private static let blockedKeywords: Set<String> = [
        "contains",
        "contentSchema",
        "patternProperties",
        "propertyNames",
        "unevaluatedProperties"
    ]

    private static let blockedArrayKeywords: Set<String> = [
        "contains",
        "contentSchema",
        "prefixItems",
        "unevaluatedItems"
    ]

    private static let consumedKeywords: Set<String> = [
        "allOf",
        "anyOf",
        "dependentRequired",
        "dependentSchemas",
        "else",
        "if",
        "oneOf",
        "then",
        "x-conditions"
    ]

    private static let renderBehaviorAnnotationKey = "x-render-behavior"
    private static let legacyRenderBehaviorAnnotationKey = "xRenderBehavior"
    private static let internalResolvedRenderBehaviorKey = "x-formkit-render-behavior"
    private static let internalConditionalStateKey = "x-formkit-conditional-state"
    private static let instanceDependentRenderPlanKeywords: Set<String> = [
        "dependentRequired",
        "dependentSchemas",
        "if",
        "then",
        "else",
        "anyOf",
        "oneOf"
    ]

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let dateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static let dateTimeFallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

public struct FormKitRenderPlan: Sendable, Equatable {
    public struct SectionDescriptor: Identifiable, Sendable, Equatable {
        public let id: String
        public let pointer: String
        public let parentPointer: String?
        public let propertyKey: String?
        public let title: String
        public let description: String?
        public let depth: Int
        public let isRequired: Bool
        public let order: Int
        public let fieldIDs: [String]
        public let propertyOrder: [String]
        public let ownerArrayRowID: String?
        public let renderBehavior: FormKitConditionalRenderBehavior
        public let conditionalState: FormKitConditionalRenderState
        public let arrayDescriptor: FormKitArraySectionDescriptor?

        public var isOwnedByArrayRow: Bool {
            ownerArrayRowID != nil
        }

        public var isArraySection: Bool {
            arrayDescriptor != nil
        }

        public var isConditionallyInactive: Bool {
            conditionalState == .inactive
        }

        public var isDisabled: Bool {
            isConditionallyInactive && renderBehavior == .disable
        }

        public var isVisible: Bool {
            conditionalState == .active || renderBehavior != .hide
        }

        public var shouldSerialize: Bool {
            conditionalState == .active || renderBehavior == .ignore
        }
    }

    public let title: String
    public let description: String?
    public let sections: [SectionDescriptor]
    public let fields: [FormKitFieldDescriptor]
    public let fieldOrder: [String]
    public let unsupportedReasons: [FormKitUnsupportedReason]

    public var isSupported: Bool {
        unsupportedReasons.isEmpty
    }
}

public enum FormKitConditionalRenderBehavior: String, Sendable, Equatable, Codable {
    case hide
    case disable
    case ignore
}

public enum FormKitConditionalRenderState: String, Sendable, Equatable {
    case active
    case inactive
}

public struct FormKitArraySectionDescriptor: Sendable, Equatable {
    public enum ItemKind: String, Sendable, Equatable {
        case scalar
        case object
    }

    public let pointer: String
    public let propertyKey: String?
    public let itemKind: ItemKind
    public let itemTitle: String
    public let minItems: Int
    public let maxItems: Int?
    public let materializeWhenEmpty: Bool
    public let newItemPlaceholder: FormKitJSONValue
    public let rows: [FormKitArrayRowDescriptor]
}

public struct FormKitArrayRowDescriptor: Identifiable, Sendable, Equatable {
    public let id: String
    public let pointer: String
    public let index: Int
    public let title: String
    public let placeholderValue: FormKitJSONValue
    public let fieldIDs: [String]
    public let sectionIDs: [String]
}

public struct FormKitFieldDescriptor: Identifiable, Sendable, Equatable {
    public enum ScalarType: String, Sendable, Equatable {
        case string
        case email
        case uri
        case date
        case dateTime
        case integer
        case number
        case boolean
    }

    public enum PrimitiveValue: Sendable, Equatable {
        case string(String)
        case integer(Int)
        case number(Double)
        case boolean(Bool)
        case null

        fileprivate var title: String {
            switch self {
            case .string(let value):
                return value
            case .integer(let value):
                return String(value)
            case .number(let value):
                return String(value)
            case .boolean(let value):
                return value ? String(localized: "On") : String(localized: "Off")
            case .null:
                return String(localized: "No Value")
            }
        }

        fileprivate var storageKey: String {
            switch self {
            case .string(let value):
                return "string:\(value)"
            case .integer(let value):
                return "integer:\(value)"
            case .number(let value):
                return "number:\(value)"
            case .boolean(let value):
                return "boolean:\(value)"
            case .null:
                return "null"
            }
        }
    }

    public struct Choice: Identifiable, Sendable, Equatable {
        public let id: String
        public let title: String
        public let value: PrimitiveValue
    }

    public let id: String
    public let pointer: String
    public let parentPointer: String
    public let propertyKey: String
    public let title: String
    public let description: String?
    public let scalarType: ScalarType
    public let enumOptions: [Choice]
    public let isRequired: Bool
    public let allowsNull: Bool
    public let defaultValue: PrimitiveValue?
    public let renderBehavior: FormKitConditionalRenderBehavior
    public let conditionalState: FormKitConditionalRenderState
    public let accessibilityIdentifier: String

    public var isEnum: Bool {
        !enumOptions.isEmpty
    }

    public var isConditionallyInactive: Bool {
        conditionalState == .inactive
    }

    public var isDisabled: Bool {
        isConditionallyInactive && renderBehavior == .disable
    }

    public var isVisible: Bool {
        conditionalState == .active || renderBehavior != .hide
    }

    public var shouldSerialize: Bool {
        conditionalState == .active || renderBehavior == .ignore
    }

    public var isInteractive: Bool {
        !isDisabled
    }
}

public enum FormKitUnsupportedReason: Sendable, Equatable {
    case invalidSchemaJSON(String)
    case invalidSchema(String)
    case unsupportedKeyword(keyword: String, location: String, message: String)
    case unsupportedType(typeDescription: String, location: String)
    case unsupportedSchemaShape(location: String, message: String)
    case unresolvedReference(String, location: String)
    case remoteReference(String, location: String)

    public var title: String {
        switch self {
        case .invalidSchemaJSON:
            return String(localized: "Invalid Schema JSON")
        case .invalidSchema:
            return String(localized: "Invalid Schema")
        case .unsupportedKeyword:
            return String(localized: "Unsupported Keyword")
        case .unsupportedType:
            return String(localized: "Unsupported Type")
        case .unsupportedSchemaShape:
            return String(localized: "Unsupported Schema Shape")
        case .unresolvedReference:
            return String(localized: "Unresolved Reference")
        case .remoteReference:
            return String(localized: "Remote Reference")
        }
    }

    public var message: String {
        switch self {
        case .invalidSchemaJSON(let message):
            return message
        case .invalidSchema(let message):
            return message
        case .unsupportedKeyword(let keyword, let location, let message):
            return "\(keyword) at \(location): \(message)"
        case .unsupportedType(let typeDescription, let location):
            return String(
                format: String(localized: "Type '%@' at %@ is not supported in this renderer."),
                typeDescription,
                location
            )
        case .unsupportedSchemaShape(let location, let message):
            return "\(location): \(message)"
        case .unresolvedReference(let reference, let location):
            return String(
                format: String(localized: "The local reference %@ could not be resolved from %@."),
                reference,
                location
            )
        case .remoteReference(let reference, let location):
            return String(
                format: String(localized: "Remote reference %@ at %@ is not supported in this renderer."),
                reference,
                location
            )
        }
    }
}

private extension String {
    func trimmedForJSONSchemaForm() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
