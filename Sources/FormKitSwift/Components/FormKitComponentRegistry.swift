import SwiftUI

@MainActor
enum FormKitComponentRegistry {
    static func fieldInput(for context: FormKitFieldComponentContext) -> AnyView? {
        guard let component = context.field.uiComponent else {
            return nil
        }

        switch component {
        case .fileField where isURLField(context.field):
            return AnyView(FormKitFileField(context: context))
        case .signaturePad where isURLField(context.field):
            return AnyView(FormKitSignaturePad(context: context))
        default:
            return nil
        }
    }

    static func arraySection(for context: FormKitArraySectionComponentContext) -> AnyView? {
        guard context.section.uiComponent == .multipleFileField,
              context.descriptor.itemKind == .scalar,
              !context.descriptor.itemHasValueConstraint,
              isURLScalarType(context.descriptor.itemScalarType)
        else {
            return nil
        }

        return AnyView(FormKitMultipleFileField(context: context))
    }

    static func isURLField(_ field: FormKitFieldDescriptor) -> Bool {
        !field.isEnum && isURLScalarType(field.scalarType)
    }

    static func isURLScalarType(_ scalarType: FormKitFieldDescriptor.ScalarType?) -> Bool {
        scalarType == .string || scalarType == .uri
    }
}
