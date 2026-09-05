import Foundation
import JSONSchema

extension FormKitRenderer {
    public func makeFormSession(
        schemaJSON: String,
        instanceJSON: String? = nil,
        defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior? = nil,
        validationBehavior: FormKitValidationBehavior = .revalidateAfterFirstAttempt
    ) -> FormKitSession {
        makeFormSession(
            schemaJSON: schemaJSON,
            instanceJSON: instanceJSON,
            defaultConditionalRenderBehavior: defaultConditionalRenderBehavior,
            conditionalRenderBehaviorOverrides: nil,
            validationBehavior: validationBehavior
        )
    }

    public func makeFormSession(
        schemaJSON: String,
        instanceJSON: String? = nil,
        defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior? = nil,
        conditionalRenderBehaviorOverrides: [String: FormKitConditionalRenderBehavior]? = nil,
        validationBehavior: FormKitValidationBehavior = .revalidateAfterFirstAttempt
    ) -> FormKitSession {
        if let renderer = rendererForOverrides(
            defaultBehavior: defaultConditionalRenderBehavior,
            overrides: conditionalRenderBehaviorOverrides
        ) {
            return renderer.makeFormSession(
                schemaJSON: schemaJSON,
                instanceJSON: instanceJSON,
                defaultConditionalRenderBehavior: nil,
                conditionalRenderBehaviorOverrides: nil,
                validationBehavior: validationBehavior
            )
        }

        let decodedSchema: DecodedSchema
        do {
            decodedSchema = try decodeSchema(schemaJSON)
        } catch {
            return invalidSchemaJSONSession(error: error, validationBehavior: validationBehavior)
        }

        let decodedInstance = decodeInstance(instanceJSON)
        let renderPlan = initialRenderPlan(schema: decodedSchema, instance: decodedInstance.value)
        guard renderPlan.isSupported else {
            return makeSession(
                from: SessionAssembly(
                    renderPlan: renderPlan,
                    validator: nil,
                    decodedInstance: decodedInstance,
                    decodedSchema: decodedSchema,
                    validationBehavior: validationBehavior
                )
            )
        }
        guard let validator = buildValidator(for: decodedSchema.validationSchema) else {
            return invalidCompiledSchemaSession(
                renderPlan: renderPlan,
                instance: decodedInstance.value,
                validationBehavior: validationBehavior
            )
        }
        return makeSession(
            from: SessionAssembly(
                renderPlan: renderPlan,
                validator: validator,
                decodedInstance: decodedInstance,
                decodedSchema: decodedSchema,
                validationBehavior: validationBehavior
            )
        )
    }

    func initialRenderPlan(
        schema: DecodedSchema,
        instance: FormKitJSONValue?
    ) -> FormKitRenderPlan {
        makeRenderPlan(
            from: schema.renderSchema,
            instance: instance,
            propertyOrderIndex: schema.propertyOrderIndex
        )
    }

    func rendererForOverrides(
        defaultBehavior: FormKitConditionalRenderBehavior?,
        overrides: [String: FormKitConditionalRenderBehavior]?
    ) -> FormKitRenderer? {
        let effectiveDefault = defaultBehavior ?? defaultConditionalRenderBehavior
        let effectiveOverrides = overrides.map(Self.normalizedConditionalRenderBehaviorOverrides)
            ?? conditionalRenderBehaviorOverrides
        guard effectiveDefault != defaultConditionalRenderBehavior
            || effectiveOverrides != conditionalRenderBehaviorOverrides
        else {
            return nil
        }
        return FormKitRenderer(
            defaultConditionalRenderBehavior: effectiveDefault,
            conditionalRenderBehaviorOverrides: effectiveOverrides,
            includesHiddenToolFields: includesHiddenToolFields
        )
    }

    func decodeSchema(_ schemaJSON: String) throws -> DecodedSchema {
        let validationSchema = try JSONDecoder().decode(FormKitJSONValue.self, from: Data(schemaJSON.utf8))
        return try DecodedSchema(
            validationSchema: validationSchema,
            renderSchema: removingRenderEngineAnnotations(from: validationSchema),
            propertyOrderIndex: JSONSchemaPropertyOrderIndex(schemaJSON: schemaJSON)
        )
    }

    func invalidSchemaJSONSession(error: Error, validationBehavior: FormKitValidationBehavior) -> FormKitSession {
        unsupportedSession(
            plan: FormKitRenderPlan(
                title: FormKitDefaults.untitledTitle,
                description: nil,
                sections: [],
                fields: [],
                fieldOrder: [],
                unsupportedReasons: [.invalidSchemaJSON(error.localizedDescription)]
            ),
            instance: nil,
            validationBehavior: validationBehavior
        )
    }

    func invalidCompiledSchemaSession(
        renderPlan: FormKitRenderPlan,
        instance: FormKitJSONValue?,
        validationBehavior: FormKitValidationBehavior
    ) -> FormKitSession {
        unsupportedSession(
            plan: FormKitRenderPlan(
                title: renderPlan.title,
                description: renderPlan.description,
                sections: [],
                fields: [],
                fieldOrder: [],
                unsupportedReasons: [
                    .invalidSchema(
                        String(localized: "The schema could not be compiled for validation.", bundle: .module)
                    )
                ]
            ),
            instance: instance,
            validationBehavior: validationBehavior
        )
    }

    func unsupportedSession(
        plan: FormKitRenderPlan,
        instance: FormKitJSONValue?,
        validationBehavior: FormKitValidationBehavior
    ) -> FormKitSession {
        FormKitSession(
            renderPlan: plan,
            validator: nil,
            initialInstance: instance,
            initialFieldValues: [:],
            validationBehavior: validationBehavior,
            refreshesRenderPlanOnFieldEdit: false,
            renderPlanProvider: { _ in plan },
            fieldValueSeedProvider: { _, _ in [:] }
        )
    }

    func makeSession(from assembly: SessionAssembly) -> FormKitSession {
        let renderSchema = assembly.decodedSchema.renderSchema
        let propertyOrderIndex = assembly.decodedSchema.propertyOrderIndex
        let session = FormKitSession(
            renderPlan: assembly.renderPlan,
            includesHiddenToolFields: includesHiddenToolFields,
            validator: assembly.validator,
            initialInstance: assembly.decodedInstance.value,
            initialFieldValues: seedFieldValues(
                for: assembly.renderPlan,
                instance: assembly.decodedInstance.value
            ),
            validationBehavior: assembly.validationBehavior,
            refreshesRenderPlanOnFieldEdit: schemaMayChangeRenderPlanAfterFieldEdit(renderSchema),
            renderPlanProvider: { [renderSchema, propertyOrderIndex] instance in
                self.makeRenderPlan(
                    from: renderSchema,
                    instance: instance,
                    propertyOrderIndex: propertyOrderIndex
                )
            },
            fieldValueSeedProvider: { plan, instance in
                self.seedFieldValues(for: plan, instance: instance)
            }
        )
        if let message = assembly.decodedInstance.errorMessage {
            session.setFormMessage(message)
        }
        return session
    }

    func decodeInstance(_ instanceJSON: String?) -> (value: FormKitJSONValue?, errorMessage: String?) {
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
                    String(localized: "The instance JSON must decode to an object.", bundle: .module)
                )
            }
            return (value, nil)
        } catch {
            return (
                nil,
                String(
                    format: String(localized: "The form data couldn’t be opened. %@", bundle: .module),
                    error.localizedDescription
                )
            )
        }
    }

    func buildValidator(for rawSchema: FormKitJSONValue) -> Schema? {
        try? Schema(
            rawSchema: rawSchema.jsonSchemaValue,
            context: Context(
                dialect: .draft2020_12,
                formatValidators: DefaultFormatValidators.all
            )
        )
    }

    func makeRenderPlan(
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
                        String(localized: "The schema root must be a JSON object.", bundle: .module)
                    )
                ]
            )
        }

        var state = RenderPlanBuildState()

        let rootTitle = rootObject["title"]?.string?.trimmedForJSONSchemaForm()
            ?? FormKitDefaults.untitledTitle
        let rootDescription = rootObject["description"]?.string?.trimmedForJSONSchemaForm()

        _ = parseObjectSchema(
            SchemaParseRequest(
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
                ownerArrayRowID: nil,
                arrayContextDepth: 0,
                propertyOrderIndex: propertyOrderIndex
            ),
            state: &state
        )

        let fieldOrder = state.fields.map(\.id)
        return FormKitRenderPlan(
            title: rootTitle,
            description: rootDescription,
            sections: state.reasons.isEmpty ? state.sections.sorted(by: { $0.order < $1.order }) : [],
            fields: state.reasons.isEmpty ? state.fields : [],
            fieldOrder: state.reasons.isEmpty ? fieldOrder : [],
            unsupportedReasons: state.reasons
        )
    }

    func schemaMayChangeRenderPlanAfterFieldEdit(_ value: FormKitJSONValue) -> Bool {
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

    func removingRenderEngineAnnotations(
        from value: FormKitJSONValue,
        preservesSchemaMemberNames: Bool = false
    ) -> FormKitJSONValue {
        switch value {
        case .object(let object):
            return .object(
                object.reduce(into: [String: FormKitJSONValue]()) { result, element in
                    let (key, value) = element
                    guard preservesSchemaMemberNames || !Self.renderEngineAnnotationKeys.contains(key) else {
                        return
                    }
                    if preservesSchemaMemberNames {
                        result[key] = removingRenderEngineAnnotations(from: value)
                    } else if Self.schemaMemberNameMapKeys.contains(key) {
                        result[key] = removingRenderEngineAnnotations(
                            from: value,
                            preservesSchemaMemberNames: true
                        )
                    } else if Self.schemaValueKeys.contains(key) {
                        result[key] = removingRenderEngineAnnotations(from: value)
                    } else {
                        result[key] = value
                    }
                }
            )
        case .array(let array):
            return .array(array.map { removingRenderEngineAnnotations(from: $0) })
        case .string, .integer, .number, .boolean, .null:
            return value
        }
    }

}
