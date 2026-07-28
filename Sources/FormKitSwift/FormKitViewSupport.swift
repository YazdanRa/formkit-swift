import SwiftUI

struct FormKitResolvedComponents {
    let fieldInputs: [String: AnyView]
    let arraySections: [String: AnyView]
    let fieldStates: [String: FormKitFieldVisualState]
    let focusableFieldIDs: Set<String>
}

enum FormKitFocusSupport {
    @MainActor
    static func resolvedComponents(
        session: FormKitSession,
        options: FormKitOptions
    ) -> FormKitResolvedComponents {
        let arraySections = session.renderPlan.sections.reduce(into: [String: AnyView]()) { result, section in
            guard section.isVisible, let descriptor = section.arrayDescriptor else {
                return
            }
            let context = FormKitArraySectionComponentContext(
                session: session,
                section: section,
                descriptor: descriptor,
                errors: session.errorMessages(for: section),
                isEditingLocked: options.mode == .readOnly,
                style: options.style,
                labels: options.labels,
                uploadHandler: options.uploadHandler
            )
            if let arraySection = options.components.arraySection?(context)
                ?? FormKitComponentRegistry.arraySection(for: context)
            {
                result[section.id] = arraySection
            }
        }
        let replacedRowPointers = Set(
            session.renderPlan.sections
                .filter { arraySections[$0.id] != nil }
                .flatMap { $0.arrayDescriptor?.rows.map(\.pointer) ?? [] }
        )
        let fields = session.renderPlan.fields.filter { field in
            field.isVisible && !replacedRowPointers.contains {
                field.pointer == $0 || field.pointer.hasPrefix("\($0)/")
            }
        }
        let fieldStates = Dictionary(uniqueKeysWithValues: fields.map { ($0.id, options.fieldState($0)) })
        let fieldInputs: [String: AnyView] = if options.components.field == nil {
            fields.reduce(into: [:]) { result, field in
                let state = fieldStates[field.id] ?? .normal
                let context = FormKitFieldComponentContext(
                    session: session,
                    field: field,
                    errors: session.errorMessages(for: field),
                    state: state,
                    isEditingLocked: options.mode == .readOnly || state == .locked,
                    style: options.style,
                    uploadHandler: options.uploadHandler
                )
                if let input = options.components.fieldInput?(context)
                    ?? FormKitComponentRegistry.fieldInput(for: context)
                {
                    result[field.id] = input
                }
            }
        } else {
            [:]
        }

        let focusableFieldIDs: Set<String> = if options.mode == .editable, options.components.field == nil {
            Set(fields.compactMap { field in
                guard field.supportsStockTextInputFocus,
                      fieldStates[field.id] != .locked,
                      fieldInputs[field.id] == nil
                else {
                    return nil
                }
                return field.id
            })
        } else {
            []
        }

        return FormKitResolvedComponents(
            fieldInputs: fieldInputs,
            arraySections: arraySections,
            fieldStates: fieldStates,
            focusableFieldIDs: focusableFieldIDs
        )
    }

    static func normalizedFieldID(
        _ requestedFieldID: String?,
        focusableFieldIDs: Set<String>
    ) -> String? {
        guard let requestedFieldID, focusableFieldIDs.contains(requestedFieldID) else {
            return nil
        }

        return requestedFieldID
    }
}

enum FormKitTextInputTraits: Equatable {
    case standard
    case email
    case url
    case integer
    case decimal

    init(scalarType: FormKitFieldDescriptor.ScalarType) {
        switch scalarType {
        case .email:
            self = .email
        case .uri:
            self = .url
        case .integer:
            self = .integer
        case .number:
            self = .decimal
        default:
            self = .standard
        }
    }

}

private struct FormKitTextInputModifier: ViewModifier {
    let traits: FormKitTextInputTraits

    func body(content: Content) -> some View {
        #if os(iOS) || os(visionOS)
        switch traits {
        case .standard:
            content
                .keyboardType(.default)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
        case .email:
            content
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.emailAddress)
        case .url:
            content
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.URL)
        case .integer:
            content
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        case .decimal:
            content
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        #else
        content
        #endif
    }
}

extension View {
    func formKitTextInputTraits(_ traits: FormKitTextInputTraits) -> some View {
        modifier(FormKitTextInputModifier(traits: traits))
    }
}

extension FormKitFieldDescriptor {
    var supportsStockTextInputFocus: Bool {
        isVisible
            && isInteractive
            && !isEnum
            && scalarType.isTextInput
    }
}

private extension FormKitFieldDescriptor.ScalarType {
    var isTextInput: Bool {
        switch self {
        case .string, .email, .uri, .integer, .number:
            return true
        case .date, .dateTime, .boolean:
            return false
        }
    }
}

extension FormKitFieldVisualState {
    var formKitAccessibilityValue: String {
        switch self {
        case .changed:
            return String(localized: "Changed", bundle: .module)
        case .normal, .locked:
            return ""
        }
    }
}
