import Foundation
import JSONSchema
import Observation

/// Produces a render plan and editable form session from a JSON Schema document.
@MainActor
public protocol FormKitRendering {
    func makeFormSession(
        schemaJSON: String,
        instanceJSON: String?,
        defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior?,
        validationBehavior: FormKitValidationBehavior
    ) -> FormKitSession

    func makeFormSession(
        schemaJSON: String,
        instanceJSON: String?,
        defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior?,
        conditionalRenderBehaviorOverrides: [String: FormKitConditionalRenderBehavior]?,
        validationBehavior: FormKitValidationBehavior
    ) -> FormKitSession
}

public enum FormKitValidationBehavior: Sendable, Equatable {
    case revalidateAfterFirstAttempt
    case onDemandOnly
}

public extension FormKitRendering {
    func makeFormSession(
        schemaJSON: String,
        instanceJSON: String?,
        defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior?,
        conditionalRenderBehaviorOverrides: [String: FormKitConditionalRenderBehavior]?,
        validationBehavior: FormKitValidationBehavior
    ) -> FormKitSession {
        makeFormSession(
            schemaJSON: schemaJSON,
            instanceJSON: instanceJSON,
            defaultConditionalRenderBehavior: defaultConditionalRenderBehavior,
            validationBehavior: validationBehavior
        )
    }

    func makeFormSession(
        schemaJSON: String,
        instanceJSON: String?,
        defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior? = nil
    ) -> FormKitSession {
        makeFormSession(
            schemaJSON: schemaJSON,
            instanceJSON: instanceJSON,
            defaultConditionalRenderBehavior: defaultConditionalRenderBehavior,
            conditionalRenderBehaviorOverrides: nil,
            validationBehavior: .revalidateAfterFirstAttempt
        )
    }
}

/// Experimental bridge from JSON Schema documents to native iOS form metadata.
@MainActor
public final class FormKitRenderer: FormKitRendering {
    let includesHiddenToolFields: Bool
    let defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior
    let conditionalRenderBehaviorOverrides: [String: FormKitConditionalRenderBehavior]

    public init(
        defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior = .hide,
        conditionalRenderBehaviorOverrides: [String: FormKitConditionalRenderBehavior] = [:],
        includesHiddenToolFields: Bool = false
    ) {
        self.includesHiddenToolFields = includesHiddenToolFields
        self.defaultConditionalRenderBehavior = defaultConditionalRenderBehavior
        self.conditionalRenderBehaviorOverrides = Self.normalizedConditionalRenderBehaviorOverrides(
            conditionalRenderBehaviorOverrides
        )
    }

}
