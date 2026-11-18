import SwiftUI

@MainActor
enum FormKitComponentRegistry {
    static func fieldInput(
        for context: FormKitFieldComponentContext,
        dynamicOptions: (@MainActor (FormKitDynamicOptionsContext) -> FormKitDynamicOptionsSource?)? = nil
    ) -> AnyView? {
        guard let component = context.field.uiComponent else {
            return nil
        }

        switch component {
        case .dynamicOptions where !context.field.isEnum && context.field.scalarType == .string:
            guard let source = dynamicOptions?(.field(context)) else { return nil }
            return AnyView(FormKitDynamicOptionsPicker(
                title: context.field.title,
                selection: FormKitDynamicOptionsContext.field(context).selection(canSelect: source.canSelect),
                savedOptions: source.savedOptions,
                isRequired: context.field.isRequired,
                isEditingLocked: context.isEditingLocked || context.field.isDisabled,
                provider: source.provider
            ))
        case .lineOptionsChoice
            where FormKitLineOptionsChoice.supportedChoiceCounts.contains(context.field.enumOptions.count):
            return AnyView(FormKitLineOptionsChoice(context: context))
        case .fileField where isURLField(context.field):
            return AnyView(FormKitFileField(context: context))
        case .signaturePad where isURLField(context.field):
            return AnyView(FormKitSignaturePad(context: context))
        default:
            return nil
        }
    }

    static func arraySection(
        for context: FormKitArraySectionComponentContext,
        dynamicOptions: (@MainActor (FormKitDynamicOptionsContext) -> FormKitDynamicOptionsSource?)? = nil
    ) -> AnyView? {
        if context.section.uiComponent == .dynamicOptions {
            guard context.descriptor.itemKind == .scalar,
                  context.descriptor.itemScalarType == .string,
                  !context.descriptor.itemAllowsNull,
                  !context.descriptor.itemHasValueConstraint,
                  let source = dynamicOptions?(.arraySection(context))
            else { return nil }
            return AnyView(FormKitDynamicOptionsArraySection(context: context, source: source))
        }
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
