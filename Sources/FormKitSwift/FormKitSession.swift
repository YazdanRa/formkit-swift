import Foundation
import JSONSchema
import Observation

/// Editable state for a rendered JSON Schema form.
@MainActor
@Observable
public final class FormKitSession {
public internal(set) var renderPlan: FormKitRenderPlan

public internal(set) var fieldErrors: [String: [String]] = [:]
public internal(set) var arrayErrors: [String: [String]] = [:]
public internal(set) var formErrorMessage: String?
    public internal(set) var validationStatusMessage: String?
    public internal(set) var firstInvalidFieldID: String?
    public internal(set) var hasAttemptedValidation = false
    public internal(set) var revision = 0

    @ObservationIgnored
    let validator: Schema?

    @ObservationIgnored
    let initialInstance: FormKitJSONValue?

    @ObservationIgnored
    let renderPlanProvider: (FormKitJSONValue?) -> FormKitRenderPlan

    @ObservationIgnored
    let fieldValueSeedProvider: (
        FormKitRenderPlan,
        FormKitJSONValue?
    ) -> [String: FormKitFieldDescriptor.PrimitiveValue?]

    @ObservationIgnored
    let validationBehavior: FormKitValidationBehavior

    @ObservationIgnored
    let refreshesRenderPlanOnFieldEdit: Bool

    @ObservationIgnored
    var fieldsByID: [String: FormKitFieldDescriptor] = [:]

    @ObservationIgnored
    var arraySectionsByPointer: [String: FormKitRenderPlan.SectionDescriptor] = [:]

    @ObservationIgnored
    var orderedFields: [FormKitFieldDescriptor] = []

    @ObservationIgnored
    var cachedCurrentInstanceJSON: String?

    var fieldValues: [String: FormKitFieldDescriptor.PrimitiveValue]
    var touchedFieldIDs: Set<String> = []
    var touchedArrayIDs: Set<String> = []
    var pendingConcreteFieldIDs: Set<String> = []
    var toolValueSourceOverrides: [String: FormKitToolValueSource] = [:]

    init(
        renderPlan: FormKitRenderPlan,
        validator: Schema?,
        initialInstance: FormKitJSONValue?,
        initialFieldValues: [String: FormKitFieldDescriptor.PrimitiveValue?],
        validationBehavior: FormKitValidationBehavior,
        refreshesRenderPlanOnFieldEdit: Bool,
        renderPlanProvider: @escaping (FormKitJSONValue?) -> FormKitRenderPlan,
        fieldValueSeedProvider: @escaping (
            FormKitRenderPlan,
            FormKitJSONValue?
        ) -> [String: FormKitFieldDescriptor.PrimitiveValue?]
    ) {
        self.renderPlan = Self.failClosed(renderPlan)
        self.validator = validator
        self.initialInstance = initialInstance
        self.validationBehavior = validationBehavior
        self.refreshesRenderPlanOnFieldEdit = refreshesRenderPlanOnFieldEdit
        self.renderPlanProvider = renderPlanProvider
        self.fieldValueSeedProvider = fieldValueSeedProvider
        self.fieldValues = initialFieldValues.compactMapValues { $0 }
        rebuildRenderPlanCaches()
        self.renderPlan = Self.failClosed(renderPlanProvider(makeInstanceJSONValue()))
        rebuildRenderPlanCaches()
    }
}
