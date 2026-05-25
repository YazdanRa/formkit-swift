import Foundation
import JSONSchema
import Observation

/// Editable state for a rendered JSON Schema form.
@MainActor
@Observable
public final class FormKitSession {
public private(set) var renderPlan: FormKitRenderPlan

public private(set) var fieldErrors: [String: [String]] = [:]
public private(set) var arrayErrors: [String: [String]] = [:]
public private(set) var formErrorMessage: String?
    public private(set) var validationStatusMessage: String?
    public private(set) var firstInvalidFieldID: String?
    public private(set) var hasAttemptedValidation = false
    public private(set) var revision = 0

    @ObservationIgnored
    private let validator: Schema?

    @ObservationIgnored
    private let initialInstance: FormKitJSONValue?

    @ObservationIgnored
    private let renderPlanProvider: (FormKitJSONValue?) -> FormKitRenderPlan

    @ObservationIgnored
    private let fieldValueSeedProvider: (
        FormKitRenderPlan,
        FormKitJSONValue?
    ) -> [String: FormKitFieldDescriptor.PrimitiveValue?]

    @ObservationIgnored
    private let validationBehavior: FormKitValidationBehavior

    @ObservationIgnored
    private let refreshesRenderPlanOnFieldEdit: Bool

    @ObservationIgnored
    private var fieldsByID: [String: FormKitFieldDescriptor] = [:]

    @ObservationIgnored
    private var arraySectionsByPointer: [String: FormKitRenderPlan.SectionDescriptor] = [:]

    @ObservationIgnored
    private var orderedFields: [FormKitFieldDescriptor] = []

    @ObservationIgnored
    private var cachedCurrentInstanceJSON: String?

    private var fieldValues: [String: FormKitFieldDescriptor.PrimitiveValue]
    private var touchedFieldIDs: Set<String> = []
    private var touchedArrayIDs: Set<String> = []

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

public var currentInstanceJSON: String {
        if let cachedCurrentInstanceJSON {
            return cachedCurrentInstanceJSON
        }

        let instanceJSON = Self.prettyJSONString(from: makeInstanceJSONValue())
        cachedCurrentInstanceJSON = instanceJSON
        return instanceJSON
    }

public func errorMessages(for field: FormKitFieldDescriptor) -> [String] {
        fieldErrors[field.id] ?? []
    }

public func errorMessages(for section: FormKitRenderPlan.SectionDescriptor) -> [String] {
        arrayErrors[section.id] ?? []
    }

public func primitiveValue(for field: FormKitFieldDescriptor) -> FormKitFieldDescriptor.PrimitiveValue? {
        if let explicitValue = fieldValues[field.id] {
            return explicitValue
        }

        if touchedFieldIDs.contains(field.id) {
            return nil
        }

        return seededValue(for: field)
    }

public func isNullSelected(for field: FormKitFieldDescriptor) -> Bool {
        primitiveValue(for: field) == .null
    }

public func setNullSelection(_ isNullSelected: Bool, for field: FormKitFieldDescriptor) {
        guard field.isInteractive else {
            return
        }

        if isNullSelected {
            setPrimitiveValue(.null, for: field)
        } else {
            setPrimitiveValue(restoreConcreteValue(for: field), for: field)
        }
        handleFieldEdit(for: field)
    }

public func stringValue(for field: FormKitFieldDescriptor) -> String {
        guard let value = primitiveValue(for: field) else {
            return ""
        }

        switch value {
        case .string(let text):
            return text
        case .integer(let number):
            return String(number)
        case .number(let number):
            return Self.numberFormatter.string(from: NSNumber(value: number)) ?? String(number)
        case .boolean(let isEnabled):
            return isEnabled ? String(localized: "true") : String(localized: "false")
        case .null:
            return ""
        }
    }

public func setStringValue(_ text: String, for field: FormKitFieldDescriptor) {
        guard field.isInteractive else {
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field.scalarType {
        case .string, .email, .uri:
            if trimmed.isEmpty {
                setPrimitiveValue(field.isRequired ? .string("") : nil, for: field)
            } else {
                setPrimitiveValue(.string(text), for: field)
            }
        case .date:
            if trimmed.isEmpty {
                setPrimitiveValue(field.isRequired ? .string("") : nil, for: field)
            } else {
                setPrimitiveValue(.string(text), for: field)
            }
        case .dateTime:
            if trimmed.isEmpty {
                setPrimitiveValue(field.isRequired ? .string("") : nil, for: field)
            } else {
                setPrimitiveValue(.string(text), for: field)
            }
        case .integer:
            if trimmed.isEmpty {
                setPrimitiveValue(nil, for: field)
            } else if let value = Int(trimmed) {
                setPrimitiveValue(.integer(value), for: field)
            } else {
                setPrimitiveValue(.string(text), for: field)
            }
        case .number:
            if trimmed.isEmpty {
                setPrimitiveValue(nil, for: field)
            } else if let value = Double(trimmed) {
                setPrimitiveValue(.number(value), for: field)
            } else {
                setPrimitiveValue(.string(text), for: field)
            }
        case .boolean:
            if let value = Bool(trimmed) {
                setPrimitiveValue(.boolean(value), for: field)
            }
        }

        handleFieldEdit(for: field)
    }

public func booleanValue(for field: FormKitFieldDescriptor) -> Bool {
        if case .boolean(let value) = primitiveValue(for: field) {
            return value
        }

        if let defaultValue = field.defaultValue,
           case .boolean(let value) = defaultValue
        {
            return value
        }

        return false
    }

public func setBooleanValue(_ isOn: Bool, for field: FormKitFieldDescriptor) {
        guard field.isInteractive else {
            return
        }

        setPrimitiveValue(.boolean(isOn), for: field)
        handleFieldEdit(for: field)
    }

public func selectedEnumChoiceID(for field: FormKitFieldDescriptor) -> String? {
        guard let value = primitiveValue(for: field) else {
            return nil
        }
        return field.enumOptions.first(where: { $0.value == value })?.id
    }

public func setSelectedEnumChoiceID(_ choiceID: String?, for field: FormKitFieldDescriptor) {
        guard field.isInteractive else {
            return
        }

        guard let choiceID else {
            setPrimitiveValue(nil, for: field)
            handleFieldEdit(for: field)
            return
        }

        setPrimitiveValue(
            field.enumOptions.first(where: { $0.id == choiceID })?.value,
            for: field
        )
        handleFieldEdit(for: field)
    }

public func dateValue(for field: FormKitFieldDescriptor) -> Date {
        guard let value = primitiveValue(for: field) else {
            return fallbackDate(for: field)
        }

        switch value {
        case .string(let rawValue):
            switch field.scalarType {
            case .date:
                return FormKitRenderer.dateFormatter.date(from: rawValue) ?? fallbackDate(for: field)
            case .dateTime:
                return FormKitRenderer.dateTimeFormatter.date(from: rawValue)
                    ?? FormKitRenderer.dateTimeFallbackFormatter.date(from: rawValue)
                    ?? fallbackDate(for: field)
            default:
                return fallbackDate(for: field)
            }
        default:
            return fallbackDate(for: field)
        }
    }

public func setDateValue(_ date: Date, for field: FormKitFieldDescriptor) {
        guard field.isInteractive else {
            return
        }

        switch field.scalarType {
        case .date:
            setPrimitiveValue(.string(FormKitRenderer.dateFormatter.string(from: date)), for: field)
        case .dateTime:
            setPrimitiveValue(.string(FormKitRenderer.dateTimeFormatter.string(from: date)), for: field)
        default:
            return
        }

        handleFieldEdit(for: field)
    }

public func appendArrayRow(to section: FormKitRenderPlan.SectionDescriptor) {
        guard !section.isDisabled,
              let arrayDescriptor = section.arrayDescriptor
        else {
            return
        }

        if let maxItems = arrayDescriptor.maxItems,
           arrayDescriptor.rows.count >= maxItems
        {
            return
        }

        touchedArrayIDs.insert(section.id)
        var instance = makeInstanceJSONValue()
        let nextIndex = arrayValue(at: arrayDescriptor.pointer, in: instance)?.count ?? 0
        insert(
            arrayDescriptor.newItemPlaceholder,
            at: "\(arrayDescriptor.pointer)/\(nextIndex)",
            into: &instance
        )
        applyInstance(instance)
    }

public func removeArrayRow(
        _ row: FormKitArrayRowDescriptor,
        from section: FormKitRenderPlan.SectionDescriptor
    ) {
        guard !section.isDisabled,
              let arrayDescriptor = section.arrayDescriptor
        else {
            return
        }

        if arrayDescriptor.rows.count <= arrayDescriptor.minItems {
            return
        }

        touchedArrayIDs.insert(section.id)
        var instance = makeInstanceJSONValue()
        guard var array = arrayValue(at: arrayDescriptor.pointer, in: instance),
              array.indices.contains(row.index)
        else {
            return
        }

        array.remove(at: row.index)
        setArray(array, at: arrayDescriptor.pointer, in: &instance)
        applyInstance(instance)
    }

public func validate() -> Bool {
        hasAttemptedValidation = true
        guard renderPlan.isSupported else {
            formErrorMessage = renderPlan.unsupportedReasons.map(\.message).joined(separator: "\n")
            validationStatusMessage = String(localized: "This form isn’t supported yet.")
            return false
        }

        let instance = makeInstanceJSONValue()
        var nextFieldErrors: [String: [String]] = requiredFieldErrors(in: instance)
        var nextArrayErrors: [String: [String]] = [:]
        var formMessages: [String] = []

        if let validator {
            let result = validator.validate(instance.jsonSchemaValue)
            if let validationErrors = result.errors {
                for error in flatten(errors: validationErrors) {
                    guard error.keyword != "required" else {
                        continue
                    }

                    let fieldID = error.instanceLocation.description
                    if fieldsByID[fieldID] != nil {
                        appendError(error.message, to: fieldID, in: &nextFieldErrors)
                    } else if let arraySection = arraySectionsByPointer[fieldID] {
                        appendError(error.message, to: arraySection.id, in: &nextArrayErrors)
                    } else if !error.message.isEmpty {
                        formMessages.append(error.message)
                    }
                }
            }
        }

        fieldErrors = nextFieldErrors
        arrayErrors = nextArrayErrors
        firstInvalidFieldID = orderedFields.first(where: { !(nextFieldErrors[$0.id] ?? []).isEmpty })?.id

        if formMessages.isEmpty {
            formErrorMessage = nil
        } else {
            formErrorMessage = Array(NSOrderedSet(array: formMessages)).compactMap { $0 as? String }.joined(separator: "\n")
        }

        let isValid = nextFieldErrors.isEmpty && nextArrayErrors.isEmpty && formErrorMessage == nil
        validationStatusMessage = isValid
            ? String(localized: "All fields look good.")
            : String(localized: "Fix the highlighted fields and try again.")
        return isValid
    }

public func setFormMessage(_ message: String?) {
        formErrorMessage = message
    }

    func clearValue(for field: FormKitFieldDescriptor) {
        guard field.isInteractive else {
            return
        }

        setPrimitiveValue(nil, for: field)
        handleFieldEdit(for: field)
    }

    fileprivate func handleFieldEdit(for field: FormKitFieldDescriptor) {
        revision += 1
        fieldErrors[field.id] = nil
        if fieldErrors[field.id]?.isEmpty == true {
            fieldErrors.removeValue(forKey: field.id)
        }

        if formErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            formErrorMessage = nil
        }

        if refreshesRenderPlanOnFieldEdit {
            refreshRenderPlan()
        }
        invalidateCurrentInstanceJSON()
        if hasAttemptedValidation, validationBehavior == .revalidateAfterFirstAttempt {
            _ = validate()
        } else if validationBehavior == .onDemandOnly {
            validationStatusMessage = nil
        }
    }

    private func restoreConcreteValue(for field: FormKitFieldDescriptor) -> FormKitFieldDescriptor.PrimitiveValue? {
        seededValue(for: field, preferInitialInstance: false)
    }

    private func makeInstanceJSONValue() -> FormKitJSONValue {
        var rootObject: [String: FormKitJSONValue] = [:]
        let requiredSectionPointers = Set(
            renderPlan.sections
                .filter(\.isRequired)
                .filter(\.shouldSerialize)
                .filter { !$0.isOwnedByArrayRow }
                .map(\.pointer)
                .filter { $0 != "#" }
        )

        for pointer in requiredSectionPointers.sorted(by: { $0.count < $1.count }) {
            ensureObjectExists(at: pointer, in: &rootObject)
        }

        let arraySections = renderPlan.sections
            .filter(\.shouldSerialize)
            .filter { !$0.isOwnedByArrayRow }
            .compactMap { section -> (FormKitRenderPlan.SectionDescriptor, FormKitArraySectionDescriptor)? in
                guard let descriptor = section.arrayDescriptor else {
                    return nil
                }
                return (section, descriptor)
            }
            .sorted { lhs, rhs in
                lhs.1.pointer.count < rhs.1.pointer.count
            }

        for (section, descriptor) in arraySections {
            if descriptor.rows.isEmpty {
                if descriptor.materializeWhenEmpty || touchedArrayIDs.contains(section.id) {
                    setArray([], at: descriptor.pointer, in: &rootObject)
                }
                continue
            }

            for row in descriptor.rows {
                insert(row.placeholderValue, at: row.pointer, into: &rootObject)
            }
        }

        for field in orderedFields {
            guard field.shouldSerialize else {
                continue
            }

            guard let storedValue = primitiveValue(for: field) else {
                continue
            }

            insert(
                jsonValue(from: storedValue),
                at: field.pointer,
                into: &rootObject
            )
        }

        return .object(rootObject)
    }

    private func refreshRenderPlan() {
        let nextPlan = Self.failClosed(renderPlanProvider(makeInstanceJSONValue()))
        guard nextPlan != renderPlan else {
            return
        }

        renderPlan = nextPlan
        rebuildRenderPlanCaches()

        let visibleFieldIDs = Set(nextPlan.fields.map(\.id))
        let visibleArrayIDs: Set<String> = Set(
            nextPlan.sections.compactMap { section in
                guard section.arrayDescriptor != nil else {
                    return nil
                }
                return section.id
            }
        )
        fieldErrors = fieldErrors.filter { visibleFieldIDs.contains($0.key) }
        arrayErrors = arrayErrors.filter { visibleArrayIDs.contains($0.key) }
        if let firstInvalidFieldID, !visibleFieldIDs.contains(firstInvalidFieldID) {
            self.firstInvalidFieldID = nil
        }
    }

    private func applyInstance(_ instance: FormKitJSONValue) {
        revision += 1
        let nextPlan = Self.failClosed(renderPlanProvider(instance))
        let previousFieldValues = fieldValues
        renderPlan = nextPlan
        rebuildRenderPlanCaches()
        let seededFieldValues = fieldValueSeedProvider(nextPlan, instance).compactMapValues { $0 }
        var nextFieldValues = previousFieldValues

        for field in nextPlan.fields {
            if touchedFieldIDs.contains(field.id),
               let preservedValue = previousFieldValues[field.id]
            {
                nextFieldValues[field.id] = preservedValue
                continue
            }

            if let seededValue = seededFieldValues[field.id] {
                nextFieldValues[field.id] = seededValue
            } else {
                nextFieldValues.removeValue(forKey: field.id)
            }
        }

        fieldValues = nextFieldValues

        let visibleFieldIDs = Set(nextPlan.fields.map(\.id))
        let visibleArrayIDs: Set<String> = Set(
            nextPlan.sections.compactMap { section in
                guard section.arrayDescriptor != nil else {
                    return nil
                }
                return section.id
            }
        )
        touchedFieldIDs = touchedFieldIDs.filter { visibleFieldIDs.contains($0) }
        touchedArrayIDs = touchedArrayIDs.filter { visibleArrayIDs.contains($0) }
        fieldErrors = fieldErrors.filter { visibleFieldIDs.contains($0.key) }
        arrayErrors = arrayErrors.filter { visibleArrayIDs.contains($0.key) }
        if let firstInvalidFieldID, !visibleFieldIDs.contains(firstInvalidFieldID) {
            self.firstInvalidFieldID = nil
        }

        invalidateCurrentInstanceJSON()
        if hasAttemptedValidation, validationBehavior == .revalidateAfterFirstAttempt {
            _ = validate()
        } else if validationBehavior == .onDemandOnly {
            validationStatusMessage = nil
        }
    }

    private func invalidateCurrentInstanceJSON() {
        cachedCurrentInstanceJSON = nil
    }

    private func rebuildRenderPlanCaches() {
        fieldsByID = Dictionary(uniqueKeysWithValues: renderPlan.fields.map { ($0.id, $0) })
        orderedFields = renderPlan.fieldOrder.compactMap { fieldsByID[$0] }
        arraySectionsByPointer = Dictionary(
            uniqueKeysWithValues: renderPlan.sections.compactMap { section in
                guard section.arrayDescriptor != nil else {
                    return nil
                }
                return (section.pointer, section)
            }
        )
    }

    private func setPrimitiveValue(
        _ value: FormKitFieldDescriptor.PrimitiveValue?,
        for field: FormKitFieldDescriptor
    ) {
        touchedFieldIDs.insert(field.id)
        if let value {
            fieldValues[field.id] = value
        } else {
            fieldValues.removeValue(forKey: field.id)
        }
    }

    private func seededValue(
        for field: FormKitFieldDescriptor,
        preferInitialInstance: Bool = true
    ) -> FormKitFieldDescriptor.PrimitiveValue? {
        if preferInitialInstance,
           let initialInstance,
           let seededFromInstance = primitiveValue(
            from: initialInstance.value(at: JSONPointer(from: field.pointer)),
            scalarType: field.scalarType,
            allowsNull: field.allowsNull
           )
        {
            return seededFromInstance
        }

        if let defaultValue = field.defaultValue {
            return defaultValue
        }

        if field.isEnum {
            return field.isRequired ? field.enumOptions.first?.value : nil
        }

        switch field.scalarType {
        case .boolean:
            return field.isRequired ? .boolean(false) : nil
        case .date:
            return field.isRequired ? .string(FormKitRenderer.dateFormatter.string(from: .now)) : nil
        case .dateTime:
            return field.isRequired ? .string(FormKitRenderer.dateTimeFormatter.string(from: .now)) : nil
        default:
            return nil
        }
    }

    private func primitiveValue(
        from jsonValue: FormKitJSONValue?,
        scalarType: FormKitFieldDescriptor.ScalarType,
        allowsNull: Bool
    ) -> FormKitFieldDescriptor.PrimitiveValue? {
        guard let jsonValue else {
            return nil
        }

        switch jsonValue {
        case .null:
            return allowsNull ? .null : nil
        case .string(let value):
            switch scalarType {
            case .string, .email, .uri, .date, .dateTime:
                return .string(value)
            case .integer, .number:
                return .string(value)
            default:
                return nil
            }
        case .integer(let value):
            switch scalarType {
            case .integer:
                return .integer(value)
            case .number:
                return .number(Double(value))
            default:
                return nil
            }
        case .number(let value):
            switch scalarType {
            case .number:
                return .number(value)
            default:
                return nil
            }
        case .boolean(let value):
            return scalarType == .boolean ? .boolean(value) : nil
        case .object, .array:
            return nil
        }
    }

    private func requiredFieldErrors(in instance: FormKitJSONValue) -> [String: [String]] {
        orderedFields.reduce(into: [:]) { result, field in
            guard field.isRequired, field.shouldSerialize else {
                return
            }

            let pointer = JSONPointer(from: field.pointer)
            if instance.value(at: pointer) == nil {
                result[field.id] = [String(localized: "This field is required.")]
            }
        }
    }

    private func flatten(errors: [ValidationError]) -> [ValidationError] {
        errors.flatMap { error in
            if let nestedErrors = error.errors, !nestedErrors.isEmpty {
                return flatten(errors: nestedErrors)
            }
            return [error]
        }
    }

    private func appendError(
        _ message: String,
        to fieldID: String,
        in fieldErrors: inout [String: [String]]
    ) {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        var messages = fieldErrors[fieldID] ?? []
        if !messages.contains(message) {
            messages.append(message)
        }
        fieldErrors[fieldID] = messages
    }

    private static func failClosed(_ renderPlan: FormKitRenderPlan) -> FormKitRenderPlan {
        guard !renderPlan.isSupported else {
            return renderPlan
        }

        return FormKitRenderPlan(
            title: renderPlan.title,
            description: renderPlan.description,
            sections: [],
            fields: [],
            fieldOrder: [],
            unsupportedReasons: renderPlan.unsupportedReasons
        )
    }

    private func ensureObjectExists(
        at pointer: String,
        in rootObject: inout [String: FormKitJSONValue]
    ) {
        let path = Self.tokens(from: pointer)
        guard !path.isEmpty else {
            return
        }

        var rootValue = FormKitJSONValue.object(rootObject)
        rootValue = ensuringObject(in: rootValue, path: path)
        rootObject = rootValue.object ?? [:]
    }

    private func setArray(
        _ array: [FormKitJSONValue],
        at pointer: String,
        in rootObject: inout [String: FormKitJSONValue]
    ) {
        var rootValue = FormKitJSONValue.object(rootObject)
        rootValue = inserting(.array(array), into: rootValue, path: Self.tokens(from: pointer))
        rootObject = rootValue.object ?? [:]
    }

    private func setArray(
        _ array: [FormKitJSONValue],
        at pointer: String,
        in value: inout FormKitJSONValue
    ) {
        value = inserting(.array(array), into: value, path: Self.tokens(from: pointer))
    }

    private func arrayValue(
        at pointer: String,
        in value: FormKitJSONValue
    ) -> [FormKitJSONValue]? {
        value.value(at: JSONPointer(from: pointer))?.array
    }

    private func insert(
        _ value: FormKitJSONValue,
        at pointer: String,
        into rootObject: inout [String: FormKitJSONValue]
    ) {
        var rootValue = FormKitJSONValue.object(rootObject)
        rootValue = inserting(value, into: rootValue, path: Self.tokens(from: pointer))
        rootObject = rootValue.object ?? [:]
    }

    private func insert(
        _ value: FormKitJSONValue,
        at pointer: String,
        into rootValue: inout FormKitJSONValue
    ) {
        rootValue = inserting(value, into: rootValue, path: Self.tokens(from: pointer))
    }

    private func inserting(
        _ value: FormKitJSONValue,
        into currentValue: FormKitJSONValue,
        path: [String]
    ) -> FormKitJSONValue {
        guard let head = path.first else {
            return value
        }

        if let index = Int(head) {
            var array = currentValue.array ?? []
            if array.count <= index {
                array.append(contentsOf: repeatElement(.null, count: index - array.count + 1))
            }

            if path.count == 1 {
                array[index] = value
                return .array(array)
            }

            array[index] = inserting(
                value,
                into: normalizedContainer(
                    currentValue: array[index],
                    nextPath: Array(path.dropFirst())
                ),
                path: Array(path.dropFirst())
            )
            return .array(array)
        }

        var object = currentValue.object ?? [:]
        if path.count == 1 {
            object[head] = value
            return .object(object)
        }

        object[head] = inserting(
            value,
            into: normalizedContainer(
                currentValue: object[head] ?? .null,
                nextPath: Array(path.dropFirst())
            ),
            path: Array(path.dropFirst())
        )
        return .object(object)
    }

    private func jsonValue(from primitive: FormKitFieldDescriptor.PrimitiveValue) -> FormKitJSONValue {
        switch primitive {
        case .string(let value):
            return .string(value)
        case .integer(let value):
            return .integer(value)
        case .number(let value):
            return .number(value)
        case .boolean(let value):
            return .boolean(value)
        case .null:
            return .null
        }
    }

    private func fallbackDate(for field: FormKitFieldDescriptor) -> Date {
        if let defaultValue = field.defaultValue,
           case .string(let text) = defaultValue
        {
            switch field.scalarType {
            case .date:
                return FormKitRenderer.dateFormatter.date(from: text) ?? .now
            case .dateTime:
                return FormKitRenderer.dateTimeFormatter.date(from: text)
                    ?? FormKitRenderer.dateTimeFallbackFormatter.date(from: text)
                    ?? .now
            default:
                return .now
            }
        }

        return .now
    }

    private static func tokens(from pointer: String) -> [String] {
        let trimmed = pointer.replacingOccurrences(of: "#/", with: "")
        guard !trimmed.isEmpty else {
            return []
        }

        return trimmed.split(separator: "/").map { token in
            token
                .replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
        }
    }

    private func ensuringObject(
        in currentValue: FormKitJSONValue,
        path: [String]
    ) -> FormKitJSONValue {
        guard let head = path.first else {
            return currentValue
        }

        if let index = Int(head) {
            var array = currentValue.array ?? []
            if array.count <= index {
                array.append(contentsOf: repeatElement(.null, count: index - array.count + 1))
            }

            if path.count == 1 {
                if array[index].object == nil {
                    array[index] = .object([:])
                }
                return .array(array)
            }

            array[index] = ensuringObject(
                in: normalizedContainer(
                    currentValue: array[index],
                    nextPath: Array(path.dropFirst())
                ),
                path: Array(path.dropFirst())
            )
            return .array(array)
        }

        var object = currentValue.object ?? [:]
        if path.count == 1 {
            if object[head]?.object == nil {
                object[head] = .object([:])
            }
            return .object(object)
        }

        object[head] = ensuringObject(
            in: normalizedContainer(
                currentValue: object[head] ?? .null,
                nextPath: Array(path.dropFirst())
            ),
            path: Array(path.dropFirst())
        )
        return .object(object)
    }

    private func normalizedContainer(
        currentValue: FormKitJSONValue,
        nextPath: [String]
    ) -> FormKitJSONValue {
        guard let next = nextPath.first else {
            return currentValue
        }

        if Int(next) != nil {
            return currentValue.array.map(FormKitJSONValue.array) ?? .array([])
        }

        return currentValue.object.map(FormKitJSONValue.object) ?? .object([:])
    }

    private static func prettyJSONString(from value: FormKitJSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return string
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.maximumFractionDigits = 12
        formatter.minimumFractionDigits = 0
        return formatter
    }()
}
