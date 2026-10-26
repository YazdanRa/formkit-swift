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

    /// Collects the rules in `rootSchema`. Conditions compile against the root, as the renderer's own
    /// conditional matching does, so local `$ref`s inside an `if` resolve.
    static func rules(in rootSchema: FormKitJSONValue) -> [FormKitConditionalRule] {
        let context = Context(dialect: .draft2020_12, formatValidators: DefaultFormatValidators.all)
        guard (try? Schema(rawSchema: rootSchema.jsonSchemaValue, context: context)) != nil else {
            return []
        }
        var collector = Collector(rootSchema: rootSchema, context: context)
        collector.collectObjectRules(rootSchema, pointerTokens: [], schemaPathTokens: [], depth: 0)
        return collector.rules
    }

    private struct Collector {
        let rootSchema: FormKitJSONValue
        let context: Context
        var rules: [FormKitConditionalRule] = []

        mutating func collectObjectRules(
            _ schema: FormKitJSONValue,
            pointerTokens: [String],
            schemaPathTokens: [String],
            depth: Int
        ) {
            guard depth < maximumDepth,
                  let object = resolvedObject(schema, rootSchema: rootSchema)
            else {
                return
            }

            collectConditionals(in: object, pointerTokens: pointerTokens, schemaPathTokens: schemaPathTokens, depth: depth)
            for property in declaredProperties(in: object, schemaPathTokens: schemaPathTokens, depth: depth) {
                collectObjectRules(
                    property.schema,
                    pointerTokens: pointerTokens + [property.key],
                    schemaPathTokens: property.schemaPathTokens,
                    depth: depth + 1
                )
            }
        }

        private mutating func collectConditionals(
            in object: [String: FormKitJSONValue],
            pointerTokens: [String],
            schemaPathTokens: [String],
            depth: Int
        ) {
            guard depth < maximumDepth else {
                return
            }
            if let condition = object["if"], let rule = rule(
                condition: condition,
                then: object["then"],
                pointerTokens: pointerTokens,
                conditionPathTokens: schemaPathTokens + ["if"]
            ) {
                rules.append(rule)
            }
            for (index, item) in (object["allOf"]?.array ?? []).enumerated() {
                guard let itemObject = resolvedObject(item, rootSchema: rootSchema) else {
                    continue
                }
                collectConditionals(
                    in: itemObject,
                    pointerTokens: pointerTokens,
                    schemaPathTokens: schemaPathTokens + ["allOf", String(index)],
                    depth: depth + 1
                )
            }
        }

        private func rule(
            condition: FormKitJSONValue,
            then: FormKitJSONValue?,
            pointerTokens: [String],
            conditionPathTokens: [String]
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
                    location: JSONPointer(from: JSONPointer.pointerString(from: conditionPathTokens)),
                    context: context
                )
            )
        }

        /// Properties declared directly on the object and inside its `allOf` members.
        private func declaredProperties(
            in object: [String: FormKitJSONValue],
            schemaPathTokens: [String],
            depth: Int
        ) -> [(key: String, schema: FormKitJSONValue, schemaPathTokens: [String])] {
            var properties = (object["properties"]?.object ?? [:])
                .sorted { $0.key < $1.key }
                .map { (key: $0.key, schema: $0.value, schemaPathTokens: schemaPathTokens + ["properties", $0.key]) }
            guard depth < maximumDepth else {
                return properties
            }
            for (index, item) in (object["allOf"]?.array ?? []).enumerated() {
                guard let itemObject = resolvedObject(item, rootSchema: rootSchema) else {
                    continue
                }
                let itemProperties = declaredProperties(
                    in: itemObject,
                    schemaPathTokens: schemaPathTokens + ["allOf", String(index)],
                    depth: depth + 1
                )
                for property in itemProperties where !properties.contains(where: { $0.key == property.key }) {
                    properties.append(property)
                }
            }
            return properties
        }
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
