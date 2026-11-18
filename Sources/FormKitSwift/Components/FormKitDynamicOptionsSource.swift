import SwiftUI

/// Cached labels and lazy lookup supplied by the host for one dynamic option control.
public struct FormKitDynamicOptionsSource {
    public let savedOptions: [FormKitDynamicOption]
    public let provider: FormKitDynamicOptionsProvider
    public let canSelect: @MainActor (String) -> Bool

    public init(
        savedOptions: [FormKitDynamicOption] = [],
        canSelect: @escaping @MainActor (String) -> Bool = { _ in true },
        provider: @escaping FormKitDynamicOptionsProvider
    ) {
        self.savedOptions = savedOptions
        self.canSelect = canSelect
        self.provider = provider
    }
}

/// The schema location and current selection for a host-owned dynamic option source.
@MainActor
public enum FormKitDynamicOptionsContext {
    case field(FormKitFieldComponentContext)
    case arraySection(FormKitArraySectionComponentContext)

    public var pointer: String {
        switch self {
        case .field(let context): context.field.pointer
        case .arraySection(let context): context.section.pointer
        }
    }

    public var selectedIDs: [String] { selection().ids }

    var requiresSelection: Bool {
        switch self {
        case .field(let context): context.field.isRequired && !context.field.allowsNull
        case .arraySection(let context): context.descriptor.minItems > 0
        }
    }

    func selection(canSelect: @escaping @MainActor (String) -> Bool = { _ in true }) -> FormKitDynamicSelection {
        switch self {
        case .field(let context):
            return .single(Binding(
                get: {
                    guard let field = context.session.renderPlan.fields.first(where: {
                              $0.pointer == context.field.pointer
                          }),
                          case .string(let id) = context.session.primitiveValue(for: field)
                    else { return nil }
                    return id
                },
                set: { id in
                    guard !context.isEditingLocked,
                          let field = context.session.renderPlan.fields.first(where: {
                              $0.pointer == context.field.pointer
                          }),
                          field.isInteractive, field.shouldSerialize
                    else { return }
                    if let id {
                        guard id == selectedIDs.first || canSelect(id) else { return }
                        context.session.setStringValue(id, for: field)
                    } else if field.allowsNull {
                        context.session.setNullSelection(true, for: field)
                    } else {
                        context.session.unsetValue(for: field)
                    }
                }
            ))
        case .arraySection(let context):
            return .multiple(Binding(
                get: {
                    guard let section = context.session.renderPlan.sections.first(where: {
                        $0.pointer == context.section.pointer && $0.isArraySection
                    }) else { return [] }
                    return context.session.arrayValue(for: section)?.compactMap(\.string).filter { !$0.isEmpty } ?? []
                },
                set: { ids in
                    guard !context.isEditingLocked,
                          let section = context.session.renderPlan.sections.first(where: {
                              $0.pointer == context.section.pointer && $0.isArraySection
                          })
                    else { return }
                    let currentIDs = Set(context.session.arrayValue(for: section)?.compactMap(\.string) ?? [])
                    guard Set(ids).subtracting(currentIDs).allSatisfy(canSelect) else { return }
                    context.session.setArrayValue(ids.map(FormKitJSONValue.string), for: section)
                }
            ))
        }
    }
}

struct FormKitDynamicOptionsArraySection: View {
    let context: FormKitArraySectionComponentContext
    let source: FormKitDynamicOptionsSource

    var validationMessages: [String] {
        let session = context.session
        guard let section = session.renderPlan.sections.first(where: {
            $0.pointer == context.section.pointer && $0.isArraySection
        }), section.isVisible, section.shouldSerialize else { return [] }
        let prefix = section.pointer + "/"
        let itemMessages = session.orderedFields.flatMap { field -> [String] in
            guard field.pointer.hasPrefix(prefix),
                  field.isVisible, field.shouldSerialize else { return [] }
            return session.errorMessages(for: field)
        }
        var seen: Set<String> = []
        return (session.errorMessages(for: section) + itemMessages).filter { seen.insert($0).inserted }
    }

    var body: some View {
        let messages = validationMessages
        return Section {
            FormKitDynamicOptionsPicker(
                title: context.section.title,
                selection: FormKitDynamicOptionsContext.arraySection(context).selection(canSelect: source.canSelect),
                savedOptions: source.savedOptions,
                isRequired: FormKitDynamicOptionsContext.arraySection(context).requiresSelection,
                maximumSelectionCount: context.descriptor.maxItems,
                isEditingLocked: context.isEditingLocked || context.section.isDisabled,
                provider: source.provider
            )
            if !messages.isEmpty {
                FormKitMessageRow(message: messages.joined(separator: "\n"), color: context.style.destructive)
                    .accessibilityIdentifier("\(context.section.id)_error")
            }
        } header: {
            Text(context.section.title)
        } footer: {
            VStack(alignment: .leading) {
                if let description = context.section.description, !description.isEmpty {
                    Text(description)
                }
                if context.descriptor.minItems > 0 {
                    Text("\(context.labels.minimumItemsPrefix) \(context.descriptor.minItems)")
                }
                if let maximum = context.descriptor.maxItems {
                    Text("\(context.labels.maximumItemsPrefix) \(maximum)")
                }
            }
        }
        .accessibilityIdentifier(context.section.id)
    }
}
