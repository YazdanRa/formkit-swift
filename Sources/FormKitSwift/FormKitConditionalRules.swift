import Foundation
import JSONSchema

/// An `if`/`then` rule from the schema, anchored to the object it is declared in.
///
/// The render plan only keeps the outcome of conditionals, so section progress and the summary page
/// use these rules to tell which answers opened follow-up fields.
struct FormKitConditionalRule {
    /// The object the rule is declared in, such as `#` or `#/housekeeping`.
    let objectPointer: String
    /// Fields named in the rule's `if.properties`.
    let triggerFieldIDs: [String]
    /// Fields the rule's `then` requires or declares.
    let dependentFieldIDs: [String]
    let condition: Schema?

    func matches(_ instance: FormKitJSONValue) -> Bool {
        guard let condition else {
            return false
        }
        let scopedInstance = instance.value(atPointer: objectPointer) ?? .object([:])
        return condition.validate(scopedInstance.jsonSchemaValue).isValid
    }
}

enum FormKitConditionalRuleIndex {
    private static let maximumDepth = 32
    private static let maximumReferenceHops = 8

    static func rules(in rootSchema: FormKitJSONValue) -> [FormKitConditionalRule] {
        var rules: [FormKitConditionalRule] = []
        collectObjectRules(rootSchema, rootSchema: rootSchema, pointerTokens: [], depth: 0, into: &rules)
        return rules
    }

    private static func collectObjectRules(
        _ schema: FormKitJSONValue,
        rootSchema: FormKitJSONValue,
        pointerTokens: [String],
        depth: Int,
        into rules: inout [FormKitConditionalRule]
    ) {
        guard depth < maximumDepth,
              let object = resolvedObject(schema, rootSchema: rootSchema)
        else {
            return
        }

        collectConditionals(in: object, rootSchema: rootSchema, pointerTokens: pointerTokens, depth: depth, into: &rules)
        for (key, property) in declaredProperties(in: object, rootSchema: rootSchema, depth: depth) {
            collectObjectRules(
                property,
                rootSchema: rootSchema,
                pointerTokens: pointerTokens + [key],
                depth: depth + 1,
                into: &rules
            )
        }
    }

    private static func collectConditionals(
        in object: [String: FormKitJSONValue],
        rootSchema: FormKitJSONValue,
        pointerTokens: [String],
        depth: Int,
        into rules: inout [FormKitConditionalRule]
    ) {
        guard depth < maximumDepth else {
            return
        }
        if let condition = object["if"], let rule = rule(
            condition: condition,
            then: object["then"],
            rootSchema: rootSchema,
            pointerTokens: pointerTokens
        ) {
            rules.append(rule)
        }
        for item in object["allOf"]?.array ?? [] {
            guard let itemObject = resolvedObject(item, rootSchema: rootSchema) else {
                continue
            }
            collectConditionals(
                in: itemObject,
                rootSchema: rootSchema,
                pointerTokens: pointerTokens,
                depth: depth + 1,
                into: &rules
            )
        }
    }

    private static func rule(
        condition: FormKitJSONValue,
        then: FormKitJSONValue?,
        rootSchema: FormKitJSONValue,
        pointerTokens: [String]
    ) -> FormKitConditionalRule? {
        let conditionObject = resolvedObject(condition, rootSchema: rootSchema) ?? [:]
        let triggerKeys = (conditionObject["properties"]?.object ?? [:]).keys.sorted()
        let thenObject = then.flatMap { resolvedObject($0, rootSchema: rootSchema) } ?? [:]
        let requiredKeys = thenObject["required"]?.array?.compactMap(\.string) ?? []
        let declaredKeys = (thenObject["properties"]?.object ?? [:]).keys.sorted()
        var dependentKeys: [String] = []
        for key in requiredKeys + declaredKeys where !dependentKeys.contains(key) && !triggerKeys.contains(key) {
            dependentKeys.append(key)
        }
        guard !triggerKeys.isEmpty, !dependentKeys.isEmpty else {
            return nil
        }

        return FormKitConditionalRule(
            objectPointer: JSONPointer.pointerString(from: pointerTokens),
            triggerFieldIDs: triggerKeys.map { JSONPointer.pointerString(from: pointerTokens + [$0]) },
            dependentFieldIDs: dependentKeys.map { JSONPointer.pointerString(from: pointerTokens + [$0]) },
            condition: try? Schema(
                rawSchema: condition.jsonSchemaValue,
                context: Context(dialect: .draft2020_12)
            )
        )
    }

    /// Properties declared directly on the object and inside its `allOf` members.
    private static func declaredProperties(
        in object: [String: FormKitJSONValue],
        rootSchema: FormKitJSONValue,
        depth: Int
    ) -> [(String, FormKitJSONValue)] {
        var properties = (object["properties"]?.object ?? [:]).sorted { $0.key < $1.key }
        guard depth < maximumDepth else {
            return properties
        }
        for item in object["allOf"]?.array ?? [] {
            guard let itemObject = resolvedObject(item, rootSchema: rootSchema) else {
                continue
            }
            for property in declaredProperties(in: itemObject, rootSchema: rootSchema, depth: depth + 1)
                where !properties.contains(where: { $0.0 == property.0 })
            {
                properties.append(property)
            }
        }
        return properties
    }

    /// The schema object with local `$ref`s followed and sibling keywords kept.
    private static func resolvedObject(
        _ schema: FormKitJSONValue,
        rootSchema: FormKitJSONValue
    ) -> [String: FormKitJSONValue]? {
        guard var object = schema.object else {
            return nil
        }
        var hops = 0
        while let reference = object["$ref"]?.string, reference.hasPrefix("#"), hops < maximumReferenceHops {
            hops += 1
            guard let target = rootSchema.value(atPointer: reference)?.object else {
                return object
            }
            object.removeValue(forKey: "$ref")
            object = target.merging(object) { _, sibling in sibling }
        }
        return object
    }
}
