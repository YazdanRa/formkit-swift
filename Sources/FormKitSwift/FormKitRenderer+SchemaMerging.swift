import Foundation
import JSONSchema

extension FormKitRenderer {
    func removingConsumedKeywords(
        from schemaObject: [String: FormKitJSONValue]
    ) -> [String: FormKitJSONValue] {
        var cleaned = schemaObject
        for keyword in Self.consumedKeywords {
            cleaned.removeValue(forKey: keyword)
        }
        return cleaned
    }

    func mergeSchemaObjects(
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

    func mergeInactiveSchemaObjects(
        _ base: MaterializedJSONSchemaObject,
        _ overlay: MaterializedJSONSchemaObject
    ) -> MaterializedJSONSchemaObject {
        let activeBase = activeConditionalOverlay(base, inactiveSchema: overlay).object
        let mergedObject = mergeInactiveSchemaObjects(activeBase, overlay.object)
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

    func mergePropertyOrder(
        _ base: [String],
        _ overlay: [String],
        properties: [String: FormKitJSONValue]
    ) -> [String] {
        guard !properties.isEmpty else {
            return []
        }

        var orderedKeys = mergeDeclaredPropertyOrder(
            base,
            overlay,
            properties: properties
        )
        var seenKeys = Set(orderedKeys)

        for key in properties.keys where seenKeys.insert(key).inserted {
            orderedKeys.append(key)
        }

        return orderedKeys
    }

    func mergeDeclaredPropertyOrder(
        _ base: [String],
        _ overlay: [String],
        properties: [String: FormKitJSONValue]
    ) -> [String] {
        var orderedKeys: [String] = []
        var seenKeys = Set<String>()
        let propertyKeys = Set(properties.keys)

        for key in base where propertyKeys.contains(key) && seenKeys.insert(key).inserted {
            orderedKeys.append(key)
        }

        for key in overlay where propertyKeys.contains(key) && seenKeys.insert(key).inserted {
            orderedKeys.append(key)
        }

        return orderedKeys
    }

    func mergeSchemaObjects(
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
                for overlayKey in overlayKeys
                    where !existingSet.contains(overlayKey) && !orderedKeys.contains(overlayKey)
                {
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

    func mergeInactiveSchemaObjects(
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

            case "items" where includesHiddenToolFields:
                if let baseItems = merged[key]?.object, let overlayItems = overlayValue.object {
                    merged[key] = .object(mergeInactiveSchemaObjects(baseItems, overlayItems))
                } else if merged[key] == nil {
                    merged[key] = overlayValue
                }

            default:
                guard !(includesHiddenToolFields
                    && base[Self.internalConditionalStateKey]?.string == FormKitConditionalRenderState.active.rawValue),
                    merged[key] == nil
                else {
                    continue
                }
                merged[key] = overlayValue
            }
        }

        return merged
    }

    func mergeInactiveSchemaDictionary(
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

    func mergeSchemaDictionary(
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

}
