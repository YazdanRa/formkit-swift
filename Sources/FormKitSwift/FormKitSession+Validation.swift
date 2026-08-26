import Foundation
import JSONSchema

extension FormKitSession {
    public func validate() -> Bool {
        hasAttemptedValidation = true
        guard renderPlan.isSupported else {
            formErrorMessage = renderPlan.unsupportedReasons.map(\.message).joined(separator: "\n")
            validationStatusMessage = String(localized: "This form isn’t supported yet.", bundle: .module)
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
            formErrorMessage = Array(NSOrderedSet(array: formMessages))
                .compactMap { $0 as? String }
                .joined(separator: "\n")
        }

        let isValid = nextFieldErrors.isEmpty && nextArrayErrors.isEmpty && formErrorMessage == nil
        validationStatusMessage = isValid
            ? String(localized: "All fields look good.", bundle: .module)
            : String(localized: "Fix the highlighted fields and try again.", bundle: .module)
        return isValid
    }

    public func setFormMessage(_ message: String?) {
        formErrorMessage = message
    }

    private func requiredFieldErrors(in instance: FormKitJSONValue) -> [String: [String]] {
        orderedFields.reduce(into: [:]) { result, field in
            guard field.isRequired, field.shouldSerialize else {
                return
            }

            let value = instance.value(at: JSONPointer(from: field.pointer))
            let isBlank = !field.allowsNull
                && value?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
            if value == nil || isBlank {
                result[field.id] = [String(localized: "This field is required.", bundle: .module)]
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
}
