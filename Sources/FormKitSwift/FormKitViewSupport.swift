import SwiftUI

enum FormKitFocusSupport {
    static func normalizedFieldID(
        _ requestedFieldID: String?,
        in renderPlan: FormKitRenderPlan,
        isEditingLocked: Bool
    ) -> String? {
        guard !isEditingLocked,
              let requestedFieldID,
              let field = renderPlan.fields.first(where: { $0.id == requestedFieldID }),
              field.supportsStockTextInputFocus
        else {
            return nil
        }

        return field.id
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
                .keyboardType(.decimalPad)
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
            && uiComponent == nil
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
