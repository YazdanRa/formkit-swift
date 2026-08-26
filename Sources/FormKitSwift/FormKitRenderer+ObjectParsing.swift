import Foundation
import JSONSchema

extension FormKitRenderer {
    @discardableResult
    func parseObjectSchema(
        _ request: SchemaParseRequest,
        state: inout RenderPlanBuildState
    ) -> Bool {
        guard let section = prepareObjectSection(request, state: &state) else {
            return false
        }

        let fieldIDs = section.propertyOrder.compactMap {
            parseObjectProperty($0, section: section, request: request, state: &state)
        }
        state.sections.append(objectSectionDescriptor(section, fieldIDs: fieldIDs))
        return true
    }

    func prepareObjectSection(
        _ request: SchemaParseRequest,
        state: inout RenderPlanBuildState
    ) -> PreparedObjectSection? {
        guard let resolvedSchema = materializedSchemaObject(
            MaterializationRequest(
                schemaValue: .object(request.schemaObject),
                rootSchema: request.rootSchema,
                instanceValue: request.instanceValue,
                pointerTokens: request.pointerTokens,
                schemaPathTokens: request.schemaPathTokens,
                propertyOrderIndex: request.propertyOrderIndex,
                availableBaseSchema: nil
            ),
            reasons: &state.reasons
        ), supportsObjectSchema(
            resolvedSchema.object,
            pointerTokens: request.pointerTokens,
            reasons: &state.reasons
        ) else {
            return nil
        }

        let properties = resolvedSchema.object["properties"]?.object ?? [:]
        let pointer = JSONPointer.pointerString(from: request.pointerTokens)
        defer { state.nextSectionOrder += 1 }
        return PreparedObjectSection(
            request: request,
            schema: resolvedSchema.object,
            properties: properties,
            requiredKeys: Set(requiredPropertyNames(in: resolvedSchema.object, instance: request.instanceValue)),
            pointer: pointer,
            sectionID: sectionIdentifier(for: pointer),
            parentPointer: parentPointer(for: request.pointerTokens),
            order: state.nextSectionOrder,
            title: resolvedSchema.object["title"]?.string?.trimmedForJSONSchemaForm()
                ?? request.propertyKey.map(humanizedPropertyKey)
                ?? request.fallbackTitle,
            description: resolvedSchema.object["description"]?.string?.trimmedForJSONSchemaForm()
                ?? request.fallbackDescription,
            propertyOrder: propertyNames(
                in: properties,
                schemaPathTokens: request.schemaPathTokens,
                propertyOrderIndex: request.propertyOrderIndex,
                preferredOrder: resolvedSchema.propertyOrder
            )
        )
    }

    func parseObjectProperty(
        _ name: String,
        section: PreparedObjectSection,
        request: SchemaParseRequest,
        state: inout RenderPlanBuildState
    ) -> String? {
        guard let propertySchemaObject = section.properties[name]?.object else {
            state.reasons.append(
                .unsupportedSchemaShape(
                    location: pointerForChild(name, in: request.pointerTokens),
                    message: String(localized: "Properties must resolve to schema objects.", bundle: .module)
                )
            )
            return nil
        }

        let childRequest = childParseRequest(
            propertyKey: name,
            schemaObject: propertySchemaObject,
            isRequired: section.requiredKeys.contains(name),
            parent: request
        )
        guard let resolvedChildSchema = materializedChildSchema(
            propertySchemaObject,
            childRequest: childRequest,
            parentRequest: request,
            state: &state
        ) else {
            return nil
        }

        if case .object = schemaType(
            for: resolvedChildSchema.object,
            pointerTokens: childRequest.pointerTokens,
            reasons: &state.reasons
        ) {
            _ = parseObjectSchema(childRequest, state: &state)
            return nil
        }
        if case .array = schemaType(
            for: resolvedChildSchema.object,
            pointerTokens: childRequest.pointerTokens,
            reasons: &state.reasons
        ) {
            _ = parseArraySchema(childRequest, state: &state)
            return nil
        }
        return appendObjectField(
            name,
            schemaObject: resolvedChildSchema.object,
            childRequest: childRequest,
            parentPointer: section.pointer,
            state: &state
        )
    }

    func appendObjectField(
        _ name: String,
        schemaObject: [String: FormKitJSONValue],
        childRequest: SchemaParseRequest,
        parentPointer: String,
        state: inout RenderPlanBuildState
    ) -> String? {
        guard let field = makeFieldDescriptor(
            FieldDescriptorRequest(
                propertyKey: name,
                schemaObject: schemaObject,
                pointerTokens: childRequest.pointerTokens,
                parentPointer: parentPointer,
                title: childRequest.fallbackTitle,
                description: childRequest.fallbackDescription,
                isRequired: childRequest.isRequiredInParent
            ),
            reasons: &state.reasons
        ) else {
            return nil
        }
        state.fields.append(field)
        return field.id
    }

    func materializedChildSchema(
        _ schemaObject: [String: FormKitJSONValue],
        childRequest: SchemaParseRequest,
        parentRequest: SchemaParseRequest,
        state: inout RenderPlanBuildState
    ) -> MaterializedJSONSchemaObject? {
        materializedSchemaObject(
            MaterializationRequest(
                schemaValue: .object(schemaObject),
                rootSchema: parentRequest.rootSchema,
                instanceValue: childRequest.instanceValue,
                pointerTokens: childRequest.pointerTokens,
                schemaPathTokens: childRequest.schemaPathTokens,
                propertyOrderIndex: parentRequest.propertyOrderIndex,
                availableBaseSchema: nil
            ),
            reasons: &state.reasons
        )
    }

    func childParseRequest(
        propertyKey: String,
        schemaObject: [String: FormKitJSONValue],
        isRequired: Bool,
        parent: SchemaParseRequest
    ) -> SchemaParseRequest {
        return SchemaParseRequest(
            schemaObject: schemaObject,
            rootSchema: parent.rootSchema,
            instanceValue: parent.instanceValue?.object?[propertyKey],
            pointerTokens: parent.pointerTokens + [propertyKey],
            schemaPathTokens: parent.schemaPathTokens + ["properties", propertyKey],
            propertyKey: propertyKey,
            fallbackTitle: schemaObject["title"]?.string?.trimmedForJSONSchemaForm()
                ?? humanizedPropertyKey(propertyKey),
            fallbackDescription: schemaObject["description"]?.string?.trimmedForJSONSchemaForm(),
            isRequiredInParent: isRequired,
            depth: parent.depth + 1,
            ownerArrayRowID: parent.ownerArrayRowID,
            arrayContextDepth: parent.arrayContextDepth,
            propertyOrderIndex: parent.propertyOrderIndex
        )
    }

    func objectSectionDescriptor(
        _ section: PreparedObjectSection,
        fieldIDs: [String]
    ) -> FormKitRenderPlan.SectionDescriptor {
        FormKitRenderPlan.SectionDescriptor(
            id: section.sectionID,
            pointer: section.pointer,
            parentPointer: section.parentPointer,
            propertyKey: section.request.propertyKey,
            title: section.title,
            description: section.description,
            depth: section.request.depth,
            isRequired: section.request.isRequiredInParent,
            order: section.order,
            fieldIDs: fieldIDs,
            propertyOrder: section.propertyOrder,
            ownerArrayRowID: section.request.ownerArrayRowID,
            uiComponent: uiComponent(from: section.schema),
            renderBehavior: resolvedRenderBehavior(
                for: section.request.pointerTokens,
                from: section.schema
            ),
            conditionalState: conditionalRenderState(from: section.schema),
            arrayDescriptor: nil
        )
    }

    func parentPointer(for pointerTokens: [String]) -> String? {
        pointerTokens.isEmpty
            ? nil
            : JSONPointer.pointerString(from: Array(pointerTokens.dropLast()))
    }

    func supportsObjectSchema(
        _ schemaObject: [String: FormKitJSONValue],
        pointerTokens: [String],
        reasons: inout [FormKitUnsupportedReason]
    ) -> Bool {
        let pointer = JSONPointer.pointerString(from: pointerTokens)
        if let additionalProperties = schemaObject["additionalProperties"],
           case .boolean = additionalProperties
        {
            // Boolean additionalProperties values do not change the rendered fields.
        } else if schemaObject["additionalProperties"] != nil {
            reasons.append(
                .unsupportedKeyword(
                    keyword: "additionalProperties",
                    location: pointer,
                    message: String(
                        localized: "Dynamic object keys are not supported in this renderer.",
                        bundle: .module
                    )
                )
            )
        }

        for keyword in Self.blockedKeywords where schemaObject[keyword] != nil {
            reasons.append(
                .unsupportedKeyword(
                    keyword: keyword,
                    location: pointer,
                    message: String(
                        localized:
                        "This keyword changes the form structure in a way the renderer does not support yet.",
                        bundle: .module
                    )
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
                    message: String(localized: "Only object schemas can create form sections.", bundle: .module)
                )
            )
            return false
        }
        return true
    }
}
