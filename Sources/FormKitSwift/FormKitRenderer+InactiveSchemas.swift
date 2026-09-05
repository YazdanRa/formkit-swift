import Foundation
import JSONSchema

extension FormKitRenderer {
    func activeConditionalOverlay(
        _ schema: MaterializedJSONSchemaObject,
        inactiveSchema: MaterializedJSONSchemaObject? = nil
    ) -> MaterializedJSONSchemaObject {
        guard includesHiddenToolFields else { return schema }
        return MaterializedJSONSchemaObject(
            object: markingActiveConditionalSchema(schema.object, inactiveSchema: inactiveSchema?.object ?? [:]),
            propertyOrder: schema.propertyOrder
        )
    }

    private func markingActiveConditionalSchema(
        _ schema: [String: FormKitJSONValue],
        inactiveSchema: [String: FormKitJSONValue]
    ) -> [String: FormKitJSONValue] {
        var marked = schema
        if marked[Self.internalConditionalStateKey] == nil {
            marked[Self.internalConditionalStateKey] = .string(FormKitConditionalRenderState.active.rawValue)
        }
        if let properties = marked["properties"]?.object {
            let required = Set(schema["required"]?.array?.compactMap(\.string) ?? [])
            let inactiveRequired = Set(inactiveSchema["required"]?.array?.compactMap(\.string) ?? [])
            var markedProperties = properties
            for (key, value) in properties {
                guard let property = value.object else { continue }
                // Retain the whole subtree when only the inactive branch makes this field required.
                if inactiveRequired.contains(key), !required.contains(key),
                   property[Self.internalConditionalStateKey] == nil
                {
                    continue
                }
                markedProperties[key] = .object(markingActiveConditionalSchema(
                    property,
                    inactiveSchema: inactiveSchema["properties"]?.object?[key]?.object ?? [:]
                ))
            }
            marked["properties"] = .object(markedProperties)
        }
        if let items = marked["items"]?.object {
            marked["items"] = .object(markingActiveConditionalSchema(
                items,
                inactiveSchema: inactiveSchema["items"]?.object ?? [:]
            ))
        }
        return marked
    }

    func inactiveRenderableSchemaObject(
        from schemaObject: MaterializedJSONSchemaObject,
        pointerTokens: [String],
        within baseSchema: MaterializedJSONSchemaObject? = nil,
        inheritedBehavior: FormKitConditionalRenderBehavior? = nil
    ) -> MaterializedJSONSchemaObject? {
        let transformedObject = inactiveRenderableSchemaObject(
            from: schemaObject.object,
            pointerTokens: pointerTokens,
            inheritedBehavior: inheritedBehavior
        )

        var mergedProperties = transformedObject?["properties"]?.object ?? [:]
        let overlayRenderBehavior = resolvedRenderBehavior(
            for: pointerTokens,
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
                        pointerTokens: pointerTokens + [key],
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

    func forceInactiveSchemaObject(
        from schemaObject: [String: FormKitJSONValue],
        pointerTokens: [String],
        inheritedBehavior: FormKitConditionalRenderBehavior? = nil
    ) -> [String: FormKitJSONValue] {
        let renderBehavior = resolvedRenderBehavior(
            for: pointerTokens,
            from: schemaObject,
            inheritedBehavior: inheritedBehavior
        )

        var transformed = schemaObject

        if let properties = schemaObject["properties"]?.object {
            let transformedProperties = properties.reduce(into: [String: FormKitJSONValue]()) { result, element in
                let (key, rawPropertyValue) = element
                result[key] = {
                    guard let propertySchema = rawPropertyValue.object else {
                        return rawPropertyValue
                    }
                    return .object(
                        forceInactiveSchemaObject(
                            from: propertySchema,
                            pointerTokens: pointerTokens + [key],
                            inheritedBehavior: renderBehavior
                        )
                    )
                }()
            }
            transformed["properties"] = .object(transformedProperties)
        }

        if let itemsSchema = schemaObject["items"]?.object {
            transformed["items"] = .object(
                forceInactiveSchemaObject(
                    from: itemsSchema,
                    pointerTokens: pointerTokens + ["items"],
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

    func inactiveRenderableSchemaObject(
        from schemaObject: [String: FormKitJSONValue],
        pointerTokens: [String],
        inheritedBehavior: FormKitConditionalRenderBehavior? = nil
    ) -> [String: FormKitJSONValue]? {
        let renderBehavior = resolvedRenderBehavior(
            for: pointerTokens,
            from: schemaObject,
            inheritedBehavior: inheritedBehavior
        )

        var transformed = schemaObject

        if let properties = schemaObject["properties"]?.object {
            let renderableProperties = properties.reduce(into: [String: FormKitJSONValue]()) { result, element in
                let (key, rawPropertyValue) = element
                guard let propertySchema = rawPropertyValue.object,
                      let inactiveProperty = inactiveRenderableSchemaObject(
                        from: propertySchema,
                        pointerTokens: pointerTokens + [key],
                        inheritedBehavior: renderBehavior
                      )
                else {
                    return
                }
                result[key] = .object(inactiveProperty)
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
                pointerTokens: pointerTokens + ["items"],
                inheritedBehavior: renderBehavior
            ) {
                transformed["items"] = .object(inactiveItemsSchema)
            } else {
                transformed.removeValue(forKey: "items")
            }
        }

        let hasRenderableChildren = transformed["properties"]?.object?.isEmpty == false
            || transformed["items"] != nil

        guard includesHiddenToolFields || renderBehavior != .hide || hasRenderableChildren else {
            return nil
        }

        if includesHiddenToolFields || renderBehavior != .hide {
            transformed[Self.internalConditionalStateKey] = .string(
                FormKitConditionalRenderState.inactive.rawValue
            )
            transformed[Self.internalResolvedRenderBehaviorKey] = .string(renderBehavior.rawValue)
        }

        return transformed
    }

    func arraySeedValues(
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

    func itemDisplayTitle(
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
            return String(localized: "Item", bundle: .module)
        }

        if trimmedTitle.hasSuffix("ies") {
            return String(trimmedTitle.dropLast(3)) + "y"
        }

        if trimmedTitle.hasSuffix("s") {
            return String(trimmedTitle.dropLast())
        }

        return trimmedTitle
    }

}
