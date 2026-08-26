import Foundation
import JSONSchema

extension FormKitRenderer {
    func resolveReferencesIfNeeded(
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
        guard let rawResolvedSchema = rootSchema.value(at: referencePointer)?.object else {
            reasons.append(.unresolvedReference(rawReference, location: pointer))
            return nil
        }
        let resolvedSchema = removingRenderEngineAnnotations(
            from: .object(rawResolvedSchema)
        ).object ?? [:]

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

    func propertyNames(
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

    func propertyNames(
        in properties: [String: FormKitJSONValue],
        schemaPathTokenOptions: [[String]],
        propertyOrderIndex: JSONSchemaPropertyOrderIndex,
        preferredOrder: [String] = []
    ) -> [String] {
        let declaredOrder = schemaPathTokenOptions.reduce(
            preferredOrder,
            { partialResult, schemaPathTokens in
                mergeDeclaredPropertyOrder(
                    partialResult,
                    propertyOrderIndex.propertyNames(at: schemaPathTokens),
                    properties: properties
                )
            }
        )
        return applyFormKitOrder(mergePropertyOrder(declaredOrder, [], properties: properties), properties: properties)
    }

    func requiredPropertyNames(
        in schemaObject: [String: FormKitJSONValue],
        instance: FormKitJSONValue?
    ) -> [String] {
        schemaObject["required"]?.array?.compactMap(\.string) ?? []
    }

    func humanizedPropertyKey(_ key: String) -> String {
        let withSpaces = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1 $2", options: .regularExpression)
        return withSpaces.capitalized
    }

    func accessibilityIdentifier(for pointer: String) -> String {
        let sanitized = pointer
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "~1", with: "_")
            .replacingOccurrences(of: "~0", with: "_")
        return "json_form_field\(sanitized)"
    }

    func sectionIdentifier(for pointer: String) -> String {
        "json_form_section\(pointer.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "#", with: ""))"
    }

    func pointerForChild(_ key: String, in pointerTokens: [String]) -> String {
        JSONPointer.pointerString(from: pointerTokens + [key])
    }

    func localReferencePathTokens(from reference: String) -> [String] {
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

}
