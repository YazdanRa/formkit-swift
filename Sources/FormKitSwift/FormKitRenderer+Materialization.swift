import Foundation
import JSONSchema

extension FormKitRenderer {
    func materializedSchemaObject(
        _ request: MaterializationRequest,
        reasons: inout [FormKitUnsupportedReason]
    ) -> MaterializedJSONSchemaObject? {
        if case .boolean = request.schemaValue {
            return MaterializedJSONSchemaObject(object: [:], propertyOrder: [])
        }
        guard var state = prepareMaterialization(request, reasons: &reasons),
              applyAllOf(to: &state, reasons: &reasons)
        else {
            return nil
        }
        applyDependentRequired(to: &state)
        guard applyDependentSchemas(to: &state, reasons: &reasons),
              applyConditionalBranches(to: &state, reasons: &reasons),
              applyComposite(keyword: "anyOf", to: &state, reasons: &reasons),
              applyComposite(keyword: "oneOf", to: &state, reasons: &reasons)
        else {
            return nil
        }
        return state.effectiveSchema
    }

    func prepareMaterialization(
        _ request: MaterializationRequest,
        reasons: inout [FormKitUnsupportedReason]
    ) -> SchemaMaterializationState? {
        guard let schemaObject = request.schemaValue.object else {
            reasons.append(
                .unsupportedSchemaShape(
                    location: JSONPointer.pointerString(from: request.pointerTokens),
                    message: String(localized: "Rendered schema nodes must resolve to objects.", bundle: .module)
                )
            )
            return nil
        }
        guard let resolvedSchema = resolveReferencesIfNeeded(
            schemaObject: schemaObject,
            rootSchema: request.rootSchema,
            pointerTokens: request.pointerTokens,
            schemaPathTokens: request.schemaPathTokens,
            reasons: &reasons
        ) else {
            return nil
        }
        let effectiveSchema = MaterializedJSONSchemaObject(
            object: removingConsumedKeywords(from: resolvedSchema.object),
            propertyOrder: propertyNames(
                in: resolvedSchema.object["properties"]?.object ?? [:],
                schemaPathTokenOptions: resolvedSchema.propertyOrderPathTokens,
                propertyOrderIndex: request.propertyOrderIndex
            )
        )
        return SchemaMaterializationState(
            request: request,
            resolvedSchema: resolvedSchema,
            effectiveSchema: effectiveSchema,
            conditionalBaseSchema: request.availableBaseSchema ?? effectiveSchema
        )
    }

    func applyAllOf(
        to state: inout SchemaMaterializationState,
        reasons: inout [FormKitUnsupportedReason]
    ) -> Bool {
        guard let schemas = state.resolvedSchema.object["allOf"]?.array else {
            return true
        }
        for (index, schema) in schemas.enumerated() {
            guard let overlay = materializedSchemaObject(
                state.request.child(
                    schemaValue: schema,
                    keyword: "allOf",
                    suffix: String(index),
                    availableBaseSchema: state.conditionalBaseSchema
                ),
                reasons: &reasons
            ) else {
                return false
            }
            state.effectiveSchema = mergeSchemaObjects(
                state.effectiveSchema,
                overlay,
                includeRequired: true
            )
        }
        return true
    }

    func applyDependentRequired(to state: inout SchemaMaterializationState) {
        guard let dependencies = state.resolvedSchema.object["dependentRequired"]?.object,
              let instanceObject = state.request.instanceValue?.object
        else {
            return
        }
        let keys = mergedRequiredKeys(
            from: state.effectiveSchema.object["required"],
            dependencyObject: dependencies,
            instanceKeys: Set(instanceObject.keys)
        )
        if !keys.isEmpty {
            state.effectiveSchema.object["required"] = .array(keys.map(FormKitJSONValue.string))
        }
    }

    func applyDependentSchemas(
        to state: inout SchemaMaterializationState,
        reasons: inout [FormKitUnsupportedReason]
    ) -> Bool {
        guard let schemas = state.resolvedSchema.object["dependentSchemas"]?.object else {
            return true
        }
        let instanceKeys = Set(state.request.instanceValue?.object?.map(\.key) ?? [])
        for key in dependentSchemaOrder(schemas, state: state) {
            guard let rawSchema = schemas[key],
                  let overlay = materializedSchemaObject(
                      state.request.child(
                          schemaValue: rawSchema,
                          keyword: "dependentSchemas",
                          suffix: key,
                          availableBaseSchema: state.conditionalBaseSchema
                      ),
                      reasons: &reasons
                  )
            else {
                return false
            }
            if instanceKeys.contains(key) {
                state.effectiveSchema = mergeSchemaObjects(
                    state.effectiveSchema,
                    overlay,
                    includeRequired: true
                )
            } else if let inactive = inactiveRenderableSchemaObject(
                from: overlay,
                pointerTokens: state.request.pointerTokens,
                within: state.conditionalBaseSchema
            ) {
                state.effectiveSchema = mergeInactiveSchemaObjects(state.effectiveSchema, inactive)
            }
        }
        return true
    }

    func dependentSchemaOrder(
        _ schemas: [String: FormKitJSONValue],
        state: SchemaMaterializationState
    ) -> [String] {
        let declared = state.resolvedSchema.propertyOrderPathTokens.reduce([]) { result, path in
            mergeDeclaredPropertyOrder(
                result,
                state.request.propertyOrderIndex.dependentSchemaNames(at: path),
                properties: schemas
            )
        }
        return mergePropertyOrder(declared, [], properties: schemas)
    }

    func applyConditionalBranches(
        to state: inout SchemaMaterializationState,
        reasons: inout [FormKitUnsupportedReason]
    ) -> Bool {
        guard let condition = state.resolvedSchema.object["if"] else {
            return true
        }
        let matches = schemaMatches(
            schemaValue: condition,
            rootSchema: state.request.rootSchema,
            instanceValue: state.request.instanceValue,
            pointerTokens: state.request.pointerTokens + ["if"],
            reasons: &reasons
        )
        let activeKeyword = matches ? "then" : "else"
        let inactiveKeyword = matches ? "else" : "then"
        guard applyConditionalBranch(
            activeKeyword,
            isActive: true,
            to: &state,
            reasons: &reasons
        ) else {
            return false
        }
        return applyConditionalBranch(
            inactiveKeyword,
            isActive: false,
            to: &state,
            reasons: &reasons
        )
    }

    func applyConditionalBranch(
        _ keyword: String,
        isActive: Bool,
        to state: inout SchemaMaterializationState,
        reasons: inout [FormKitUnsupportedReason]
    ) -> Bool {
        guard let schema = state.resolvedSchema.object[keyword] else {
            return true
        }
        guard let overlay = materializedSchemaObject(
            state.request.child(
                schemaValue: schema,
                keyword: keyword,
                availableBaseSchema: state.conditionalBaseSchema
            ),
            reasons: &reasons
        ) else {
            return false
        }
        if isActive {
            state.effectiveSchema = mergeSchemaObjects(
                state.effectiveSchema,
                overlay,
                includeRequired: true
            )
        } else if let inactive = inactiveRenderableSchemaObject(
            from: overlay,
            pointerTokens: state.request.pointerTokens,
            within: state.conditionalBaseSchema
        ) {
            state.effectiveSchema = mergeInactiveSchemaObjects(state.effectiveSchema, inactive)
        }
        return true
    }

    func applyComposite(
        keyword: String,
        to state: inout SchemaMaterializationState,
        reasons: inout [FormKitUnsupportedReason]
    ) -> Bool {
        guard let schemas = state.resolvedSchema.object[keyword]?.array else {
            return true
        }
        let request = CompositeMaterializationRequest(
            keyword: keyword,
            schemas: schemas,
            materialization: state.request.child(schemaValue: .array(schemas), keyword: keyword),
            instancePointerTokens: state.request.pointerTokens
        )
        guard let result = materializedCompositeOverlay(request, reasons: &reasons) else {
            return false
        }
        state.effectiveSchema = mergeSchemaObjects(
            state.effectiveSchema,
            result.activeOverlay,
            includeRequired: result.includeRequired
        )
        for inactive in result.inactiveOverlays {
            state.effectiveSchema = mergeInactiveSchemaObjects(state.effectiveSchema, inactive)
        }
        return true
    }

    func materializedCompositeOverlay(
        _ request: CompositeMaterializationRequest,
        reasons: inout [FormKitUnsupportedReason]
    ) -> CompositeOverlayMaterialization? {
        guard let candidates = compositeCandidates(request, reasons: &reasons) else {
            return nil
        }
        let selection = compositeSelection(keyword: request.keyword, candidates: candidates)
        var merged = MaterializedJSONSchemaObject(object: [:], propertyOrder: [])
        for candidate in candidates where selection.indices.contains(candidate.index) {
            merged = mergeSchemaObjects(
                merged,
                candidate.overlay,
                includeRequired: selection.includeRequired
            )
        }
        let inactive = candidates
            .filter { !selection.indices.contains($0.index) }
            .compactMap {
                inactiveRenderableSchemaObject(
                    from: $0.overlay,
                    pointerTokens: request.instancePointerTokens
                )
            }
        return CompositeOverlayMaterialization(
            activeOverlay: merged,
            inactiveOverlays: inactive,
            includeRequired: selection.includeRequired
        )
    }

    func compositeCandidates(
        _ request: CompositeMaterializationRequest,
        reasons: inout [FormKitUnsupportedReason]
    ) -> [CompositeOverlayCandidate]? {
        var candidates: [CompositeOverlayCandidate] = []
        for (index, rawSchema) in request.schemas.enumerated() {
            let child = request.materialization.child(
                schemaValue: rawSchema,
                suffix: String(index)
            )
            guard let overlay = materializedSchemaObject(child, reasons: &reasons) else {
                return nil
            }
            candidates.append(
                CompositeOverlayCandidate(
                    index: index,
                    overlay: overlay,
                    isValid: schemaMatches(
                        schemaValue: rawSchema,
                        rootSchema: child.rootSchema,
                        instanceValue: child.instanceValue,
                        pointerTokens: child.pointerTokens,
                        reasons: &reasons
                    ),
                    discriminatorScore: discriminatorScore(
                        for: overlay.object,
                        instanceValue: child.instanceValue
                    )
                )
            )
        }
        return candidates
    }

    func compositeSelection(
        keyword: String,
        candidates: [CompositeOverlayCandidate]
    ) -> CompositeSelection {
        let validIndices = Set(candidates.filter(\.isValid).map(\.index))
        if keyword == "oneOf", validIndices.count == 1 {
            return CompositeSelection(indices: validIndices, includeRequired: true)
        }
        if keyword == "oneOf",
           let index = uniqueDiscriminatorOverlay(from: candidates)
        {
            return CompositeSelection(indices: [index], includeRequired: true)
        }
        if keyword == "anyOf", !validIndices.isEmpty {
            return CompositeSelection(indices: validIndices, includeRequired: true)
        }
        return CompositeSelection(
            indices: Set(candidates.map(\.index)),
            includeRequired: false
        )
    }
}
