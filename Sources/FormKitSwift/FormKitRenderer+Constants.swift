import Foundation
import JSONSchema

extension FormKitRenderer {
    struct DecodedSchema {
        let validationSchema: FormKitJSONValue
        let renderSchema: FormKitJSONValue
        let propertyOrderIndex: JSONSchemaPropertyOrderIndex
    }

    struct SessionAssembly {
        let renderPlan: FormKitRenderPlan
        let validator: Schema?
        let decodedInstance: (value: FormKitJSONValue?, errorMessage: String?)
        let decodedSchema: DecodedSchema
        let validationBehavior: FormKitValidationBehavior
    }

    struct SchemaParseRequest {
        let schemaObject: [String: FormKitJSONValue]
        let rootSchema: FormKitJSONValue
        let instanceValue: FormKitJSONValue?
        let pointerTokens: [String]
        let schemaPathTokens: [String]
        let propertyKey: String?
        let fallbackTitle: String
        let fallbackDescription: String?
        let isRequiredInParent: Bool
        let depth: Int
        let ownerArrayRowID: String?
        let arrayContextDepth: Int
        let propertyOrderIndex: JSONSchemaPropertyOrderIndex
    }

    struct RenderPlanBuildState {
        var reasons: [FormKitUnsupportedReason] = []
        var sections: [FormKitRenderPlan.SectionDescriptor] = []
        var fields: [FormKitFieldDescriptor] = []
        var nextSectionOrder = 0
    }

    struct PreparedObjectSection {
        let request: SchemaParseRequest
        let schema: [String: FormKitJSONValue]
        let properties: [String: FormKitJSONValue]
        let requiredKeys: Set<String>
        let pointer: String
        let sectionID: String
        let parentPointer: String?
        let order: Int
        let title: String
        let description: String?
        let propertyOrder: [String]
    }

    struct PreparedArraySection {
        let request: SchemaParseRequest
        let itemsValue: FormKitJSONValue
        let itemSchema: [String: FormKitJSONValue]
        let itemType: SupportedSchemaType
        let itemScalarType: FormKitFieldDescriptor.ScalarType?
        let pointer: String
        let order: Int
        let title: String
        let description: String?
        let itemTitle: String
        let existingItems: [FormKitJSONValue]
        let minItems: Int
        let maxItems: Int?
        let materializeWhenEmpty: Bool
        let newItemPlaceholder: FormKitJSONValue
    }

    enum ArrayRowBuildResult {
        case row(FormKitArrayRowDescriptor)
        case skip
        case failure
    }

    struct FieldDescriptorRequest {
        let propertyKey: String
        let schemaObject: [String: FormKitJSONValue]
        let pointerTokens: [String]
        let parentPointer: String
        let title: String
        let description: String?
        let isRequired: Bool
    }

    struct PlaceholderRequest {
        let schemaObject: [String: FormKitJSONValue]
        let rootSchema: FormKitJSONValue
        let pointerTokens: [String]
        let schemaPathTokens: [String]
        let propertyOrderIndex: JSONSchemaPropertyOrderIndex
    }

    struct ObjectPlaceholderContext {
        let request: PlaceholderRequest
        let properties: [String: FormKitJSONValue]
        let requiredKeys: Set<String>
    }

    struct MaterializationRequest {
        let schemaValue: FormKitJSONValue
        let rootSchema: FormKitJSONValue
        let instanceValue: FormKitJSONValue?
        let pointerTokens: [String]
        let schemaPathTokens: [String]
        let propertyOrderIndex: JSONSchemaPropertyOrderIndex
        let availableBaseSchema: MaterializedJSONSchemaObject?

        func child(
            schemaValue: FormKitJSONValue,
            keyword: String? = nil,
            suffix: String? = nil,
            availableBaseSchema: MaterializedJSONSchemaObject? = nil
        ) -> MaterializationRequest {
            let pathSuffix = [keyword, suffix].compactMap(\.self)
            return MaterializationRequest(
                schemaValue: schemaValue,
                rootSchema: rootSchema,
                instanceValue: instanceValue,
                pointerTokens: pointerTokens + pathSuffix,
                schemaPathTokens: schemaPathTokens + pathSuffix,
                propertyOrderIndex: propertyOrderIndex,
                availableBaseSchema: availableBaseSchema
            )
        }
    }

    struct SchemaMaterializationState {
        let request: MaterializationRequest
        let resolvedSchema: ResolvedSchemaObject
        var effectiveSchema: MaterializedJSONSchemaObject
        let conditionalBaseSchema: MaterializedJSONSchemaObject
    }

    struct CompositeMaterializationRequest {
        let keyword: String
        let schemas: [FormKitJSONValue]
        let materialization: MaterializationRequest
        let instancePointerTokens: [String]
    }

    struct CompositeSelection {
        let indices: Set<Int>
        let includeRequired: Bool
    }

    enum SupportedSchemaType: Equatable {
        case object
        case array
        case scalar(PrimitiveSchemaType, allowsNull: Bool)
        case unsupported
    }

    enum PrimitiveSchemaType: Equatable {
        case string
        case integer
        case number
        case boolean
    }

    struct CompositeOverlayCandidate {
        let index: Int
        let overlay: MaterializedJSONSchemaObject
        let isValid: Bool
        let discriminatorScore: Int?
    }

    struct CompositeOverlayMaterialization {
        let activeOverlay: MaterializedJSONSchemaObject
        let inactiveOverlays: [MaterializedJSONSchemaObject]
        let includeRequired: Bool
    }

    static let blockedKeywords: Set<String> = [
        "contains",
        "contentSchema",
        "patternProperties",
        "propertyNames",
        "unevaluatedProperties"
    ]

    static let blockedArrayKeywords: Set<String> = [
        "contains",
        "contentSchema",
        "prefixItems",
        "unevaluatedItems"
    ]

    static let consumedKeywords: Set<String> = [
        "allOf",
        "anyOf",
        "dependentRequired",
        "dependentSchemas",
        "else",
        "if",
        "oneOf",
        "then"
    ]

    static let internalResolvedRenderBehaviorKey = "x-formkit-render-behavior"
    static let internalConditionalStateKey = "x-formkit-conditional-state"
    static let uiComponentKey = "x-formkit-ui-component"
    static let renderEngineAnnotationKeys: Set<String> = [
        internalResolvedRenderBehaviorKey,
        internalConditionalStateKey
    ]
    static let schemaMemberNameMapKeys: Set<String> = [
        "$defs",
        "dependencies",
        "definitions",
        "dependentSchemas",
        "patternProperties",
        "properties"
    ]
    static let schemaValueKeys: Set<String> = [
        "additionalItems",
        "additionalProperties",
        "allOf",
        "anyOf",
        "contains",
        "contentSchema",
        "else",
        "if",
        "items",
        "not",
        "oneOf",
        "prefixItems",
        "propertyNames",
        "then",
        "unevaluatedItems",
        "unevaluatedProperties"
    ]
    static let instanceDependentRenderPlanKeywords: Set<String> = [
        "dependentRequired",
        "dependentSchemas",
        "if",
        "then",
        "else",
        "anyOf",
        "oneOf"
    ]

}
