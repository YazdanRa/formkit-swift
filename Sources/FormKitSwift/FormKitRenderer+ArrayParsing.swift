import Foundation
import JSONSchema

extension FormKitRenderer {
    @discardableResult
    func parseArraySchema(
        _ request: SchemaParseRequest,
        state: inout RenderPlanBuildState
    ) -> Bool {
        let pointer = JSONPointer.pointerString(from: request.pointerTokens)
        guard request.arrayContextDepth == 0 else {
            state.reasons.append(
                .unsupportedKeyword(
                    keyword: "items",
                    location: pointer,
                    message: String(
                        localized: "Nested repeatable groups are not supported in this renderer yet.",
                        bundle: .module
                    )
                )
            )
            return false
        }
        guard supportsArraySchema(
            request.schemaObject,
            pointerTokens: request.pointerTokens,
            reasons: &state.reasons
        ), let section = prepareArraySection(request, state: &state),
        let rows = makeArrayRows(section, state: &state)
        else {
            return false
        }

        state.sections.append(arraySectionDescriptor(section, rows: rows))
        return true
    }

    func prepareArraySection(
        _ request: SchemaParseRequest,
        state: inout RenderPlanBuildState
    ) -> PreparedArraySection? {
        guard let itemsValue = request.schemaObject["items"],
              let itemSchema = materializedArrayItem(itemsValue, request: request, state: &state)
        else {
            return nil
        }

        let itemType = schemaType(
            for: itemSchema.object,
            pointerTokens: request.pointerTokens + ["items"],
            reasons: &state.reasons
        )
        guard validateArrayItemType(itemType, request: request, reasons: &state.reasons) else {
            return nil
        }

        let title = request.schemaObject["title"]?.string?.trimmedForJSONSchemaForm()
            ?? request.propertyKey.map(humanizedPropertyKey)
            ?? request.fallbackTitle
        let existingItems = arraySeedValues(
            from: request.instanceValue,
            fallbackDefault: request.schemaObject["default"]
        )
        let minItems = max(0, request.schemaObject["minItems"]?.integer ?? 0)
        let placeholder = arrayPlaceholder(itemSchema.object, request: request, state: &state)
        defer { state.nextSectionOrder += 1 }
        return PreparedArraySection(
            request: request,
            itemsValue: itemsValue,
            itemSchema: itemSchema.object,
            itemType: itemType,
            itemScalarType: arrayItemScalarType(
                itemType,
                schema: itemSchema.object,
                request: request,
                state: &state
            ),
            pointer: JSONPointer.pointerString(from: request.pointerTokens),
            order: state.nextSectionOrder,
            title: title,
            description: request.schemaObject["description"]?.string?.trimmedForJSONSchemaForm()
                ?? request.fallbackDescription,
            itemTitle: itemDisplayTitle(arrayTitle: title, itemSchema: itemSchema.object),
            existingItems: existingItems,
            minItems: minItems,
            maxItems: request.schemaObject["maxItems"]?.integer,
            materializeWhenEmpty: shouldMaterializeEmptyArray(request, minItems: minItems),
            newItemPlaceholder: placeholder
        )
    }

    func materializedArrayItem(
        _ itemsValue: FormKitJSONValue,
        request: SchemaParseRequest,
        state: inout RenderPlanBuildState
    ) -> MaterializedJSONSchemaObject? {
        materializedSchemaObject(
            MaterializationRequest(
                schemaValue: itemsValue,
                rootSchema: request.rootSchema,
                instanceValue: nil,
                pointerTokens: request.pointerTokens + ["items"],
                schemaPathTokens: request.schemaPathTokens + ["items"],
                propertyOrderIndex: request.propertyOrderIndex,
                availableBaseSchema: nil
            ),
            reasons: &state.reasons
        )
    }

    func arrayPlaceholder(
        _ schemaObject: [String: FormKitJSONValue],
        request: SchemaParseRequest,
        state: inout RenderPlanBuildState
    ) -> FormKitJSONValue {
        arrayItemPlaceholder(
            PlaceholderRequest(
                schemaObject: schemaObject,
                rootSchema: request.rootSchema,
                pointerTokens: request.pointerTokens + ["items"],
                schemaPathTokens: request.schemaPathTokens + ["items"],
                propertyOrderIndex: request.propertyOrderIndex
            ),
            reasons: &state.reasons
        )
    }

    func validateArrayItemType(
        _ itemType: SupportedSchemaType,
        request: SchemaParseRequest,
        reasons: inout [FormKitUnsupportedReason]
    ) -> Bool {
        guard itemType != .unsupported else {
            return false
        }
        guard case .array = itemType else {
            return true
        }
        reasons.append(
            .unsupportedType(
                typeDescription: "array",
                location: JSONPointer.pointerString(from: request.pointerTokens + ["items"])
            )
        )
        return false
    }

    func arrayItemScalarType(
        _ itemType: SupportedSchemaType,
        schema: [String: FormKitJSONValue],
        request: SchemaParseRequest,
        state: inout RenderPlanBuildState
    ) -> FormKitFieldDescriptor.ScalarType? {
        guard case .scalar(let primitiveType, _) = itemType else {
            return nil
        }
        return scalarType(
            from: primitiveType,
            format: schema["format"]?.string?.trimmedForJSONSchemaForm(),
            location: JSONPointer.pointerString(from: request.pointerTokens + ["items"]),
            reasons: &state.reasons
        )
    }

    func shouldMaterializeEmptyArray(_ request: SchemaParseRequest, minItems: Int) -> Bool {
        request.instanceValue?.array != nil
            || request.schemaObject["default"]?.array != nil
            || request.isRequiredInParent
            || minItems > 0
    }

    func makeArrayRows(
        _ section: PreparedArraySection,
        state: inout RenderPlanBuildState
    ) -> [FormKitArrayRowDescriptor]? {
        var rows: [FormKitArrayRowDescriptor] = []
        let rowCount = max(section.existingItems.count, section.minItems)
        for index in 0..<rowCount {
            switch makeArrayRow(index, section: section, state: &state) {
            case .row(let row):
                rows.append(row)
            case .skip:
                continue
            case .failure:
                return nil
            }
        }
        return rows
    }

    func makeArrayRow(
        _ index: Int,
        section: PreparedArraySection,
        state: inout RenderPlanBuildState
    ) -> ArrayRowBuildResult {
        let rowPointerTokens = section.request.pointerTokens + [String(index)]
        guard let rowItemSchema = materializedSchemaObject(
            MaterializationRequest(
                schemaValue: section.itemsValue,
                rootSchema: section.request.rootSchema,
                instanceValue: section.existingItems[safe: index],
                pointerTokens: section.request.pointerTokens + ["items"],
                schemaPathTokens: section.request.schemaPathTokens + ["items"],
                propertyOrderIndex: section.request.propertyOrderIndex,
                availableBaseSchema: nil
            ),
            reasons: &state.reasons
        ) else {
            return .skip
        }

        switch section.itemType {
        case .scalar:
            return scalarArrayRow(
                index,
                rowPointerTokens: rowPointerTokens,
                rowItemSchema: rowItemSchema.object,
                section: section,
                state: &state
            )
        case .object:
            return objectArrayRow(
                index,
                rowItemSchema: rowItemSchema.object,
                section: section,
                state: &state
            )
        case .array, .unsupported:
            return .failure
        }
    }

    func scalarArrayRow(
        _ index: Int,
        rowPointerTokens: [String],
        rowItemSchema: [String: FormKitJSONValue],
        section: PreparedArraySection,
        state: inout RenderPlanBuildState
    ) -> ArrayRowBuildResult {
        let rowPointer = JSONPointer.pointerString(from: rowPointerTokens)
        let rowTitle = String(
            format: String(localized: "%@ %d", bundle: .module),
            section.itemTitle,
            index + 1
        )
        guard let field = makeFieldDescriptor(
            FieldDescriptorRequest(
                propertyKey: String(index),
                schemaObject: rowItemSchema,
                pointerTokens: rowPointerTokens,
                parentPointer: section.pointer,
                title: rowTitle,
                description: rowItemSchema["description"]?.string?.trimmedForJSONSchemaForm(),
                isRequired: true
            ),
            reasons: &state.reasons
        ) else {
            return .failure
        }
        state.fields.append(field)
        return .row(
            FormKitArrayRowDescriptor(
                id: rowPointer,
                pointer: rowPointer,
                index: index,
                title: rowTitle,
                placeholderValue: section.existingItems[safe: index] ?? section.newItemPlaceholder,
                fieldIDs: [field.id],
                sectionIDs: []
            )
        )
    }

    func objectArrayRow(
        _ index: Int,
        rowItemSchema: [String: FormKitJSONValue],
        section: PreparedArraySection,
        state: inout RenderPlanBuildState
    ) -> ArrayRowBuildResult {
        let rowPointer = JSONPointer.pointerString(from: section.request.pointerTokens + [String(index)])
        let rowTitle = String(
            format: String(localized: "%@ %d", bundle: .module),
            section.itemTitle,
            index + 1
        )
        let sectionCountBefore = state.sections.count
        let rowRequest = SchemaParseRequest(
            schemaObject: section.itemsValue.object ?? rowItemSchema,
            rootSchema: section.request.rootSchema,
            instanceValue: section.existingItems[safe: index],
            pointerTokens: section.request.pointerTokens + [String(index)],
            schemaPathTokens: section.request.schemaPathTokens + ["items"],
            propertyKey: section.request.propertyKey,
            fallbackTitle: rowTitle,
            fallbackDescription: rowItemSchema["description"]?.string?.trimmedForJSONSchemaForm(),
            isRequiredInParent: true,
            depth: section.request.depth + 1,
            ownerArrayRowID: rowPointer,
            arrayContextDepth: section.request.arrayContextDepth + 1,
            propertyOrderIndex: section.request.propertyOrderIndex
        )
        guard parseObjectSchema(rowRequest, state: &state) else {
            return .failure
        }
        return .row(
            FormKitArrayRowDescriptor(
                id: rowPointer,
                pointer: rowPointer,
                index: index,
                title: rowTitle,
                placeholderValue: section.existingItems[safe: index] ?? section.newItemPlaceholder,
                fieldIDs: [],
                sectionIDs: state.sections[sectionCountBefore...].map(\.id)
            )
        )
    }

    func arraySectionDescriptor(
        _ section: PreparedArraySection,
        rows: [FormKitArrayRowDescriptor]
    ) -> FormKitRenderPlan.SectionDescriptor {
        FormKitRenderPlan.SectionDescriptor(
            id: sectionIdentifier(for: section.pointer),
            pointer: section.pointer,
            parentPointer: parentPointer(for: section.request.pointerTokens),
            propertyKey: section.request.propertyKey,
            title: section.title,
            description: section.description,
            depth: section.request.depth,
            isRequired: section.request.isRequiredInParent,
            order: section.order,
            fieldIDs: [],
            propertyOrder: [],
            ownerArrayRowID: section.request.ownerArrayRowID,
            uiComponent: uiComponent(from: section.request.schemaObject),
            renderBehavior: resolvedRenderBehavior(
                for: section.request.pointerTokens,
                from: section.request.schemaObject
            ),
            conditionalState: conditionalRenderState(from: section.request.schemaObject),
            arrayDescriptor: FormKitArraySectionDescriptor(
                pointer: section.pointer,
                propertyKey: section.request.propertyKey,
                itemKind: section.itemType == .object ? .object : .scalar,
                itemScalarType: section.itemScalarType,
                itemHasValueConstraint: section.itemSchema["enum"] != nil
                    || section.itemSchema["const"] != nil,
                itemTitle: section.itemTitle,
                minItems: section.minItems,
                maxItems: section.maxItems,
                materializeWhenEmpty: section.materializeWhenEmpty,
                newItemPlaceholder: section.newItemPlaceholder,
                rows: rows
            )
        )
    }

}
