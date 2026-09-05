import SwiftUI

extension FormKitContainerView {
    @ViewBuilder
    func fieldCard(
        _ field: FormKitFieldDescriptor,
        renderIndex: FormKitRenderIndex,
        components: FormKitResolvedComponents
    ) -> some View {
        let errors = session.errorMessages(for: field)
        let state = components.fieldStates[field.id] ?? options.fieldState(field)
        let locked = isEditingLocked || state == .locked
        let componentContext = FormKitFieldComponentContext(
            session: session,
            field: field,
            errors: errors,
            state: state,
            isEditingLocked: locked,
            style: options.style,
            uploadHandler: options.uploadHandler
        )

        if let customField = options.components.field {
            customField(componentContext)
        } else {
            stockFieldCard(
                field,
                renderIndex: renderIndex,
                components: components,
                context: componentContext
            )
        }
    }

    private func stockFieldCard(
        _ field: FormKitFieldDescriptor,
        renderIndex: FormKitRenderIndex,
        components: FormKitResolvedComponents,
        context: FormKitFieldComponentContext
    ) -> some View {
        let componentInput = components.fieldInputs[field.id]
            ?? FormKitComponentRegistry.fieldInput(for: context)
        let usesStackedLabel = componentInput != nil
            || (!field.isEnum && ![.boolean, .date, .time, .dateTime].contains(field.scalarType))

        return VStack(alignment: .leading, spacing: options.style.fieldSpacing) {
            fieldCardLabel(field, componentInput: componentInput, usesStackedLabel: usesStackedLabel)
            fieldCardInput(
                componentInput,
                field: field,
                renderIndex: renderIndex,
                context: context,
                usesStackedLabel: usesStackedLabel
            )
            fieldErrors(context.errors, field: field)
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .id(field.id)
        .disabled(field.isDisabled || context.isEditingLocked)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(fieldIdentifier(for: field))
        .accessibilityValue(context.state.formKitAccessibilityValue)
    }

    @ViewBuilder
    private func fieldCardLabel(
        _ field: FormKitFieldDescriptor,
        componentInput: AnyView?,
        usesStackedLabel: Bool
    ) -> some View {
        if usesStackedLabel {
            Text(field.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(options.style.secondaryText)
                .accessibilityHidden(componentInput == nil)
        }

        if let description = field.description, !description.isEmpty {
            Text(description)
                .font(.caption)
                .foregroundStyle(options.style.secondaryText)
        }
    }

    @ViewBuilder
    private func fieldCardInput(
        _ componentInput: AnyView?,
        field: FormKitFieldDescriptor,
        renderIndex: FormKitRenderIndex,
        context: FormKitFieldComponentContext,
        usesStackedLabel: Bool
    ) -> some View {
        if usesStackedLabel {
            resolvedFieldInput(
                componentInput,
                field: field,
                renderIndex: renderIndex,
                locked: context.isEditingLocked
            )
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(fieldBackground(field, locked: context.isEditingLocked))
            .overlay(
                RoundedRectangle(cornerRadius: options.style.cornerRadius, style: .continuous)
                    .stroke(
                        borderColor(for: field, state: context.state, hasErrors: !context.errors.isEmpty),
                        lineWidth: 1.5
                    )
            )
        } else {
            resolvedFieldInput(
                componentInput,
                field: field,
                renderIndex: renderIndex,
                locked: context.isEditingLocked
            )
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
    }

    private func fieldBackground(_ field: FormKitFieldDescriptor, locked: Bool) -> some View {
        RoundedRectangle(cornerRadius: options.style.cornerRadius, style: .continuous)
            .fill(
                locked || field.isDisabled
                    ? options.style.disabledFieldBackground
                    : options.style.fieldBackground
            )
    }

    @ViewBuilder
    private func fieldErrors(_ errors: [String], field: FormKitFieldDescriptor) -> some View {
        if !errors.isEmpty {
            FormKitMessageRow(message: errors.joined(separator: "\n"), color: options.style.destructive)
                .padding(.top, 4)
                .accessibilityIdentifier("\(fieldIdentifier(for: field))_error")
        }
    }

    @ViewBuilder
    private func resolvedFieldInput(
        _ componentInput: AnyView?,
        field: FormKitFieldDescriptor,
        renderIndex: FormKitRenderIndex,
        locked: Bool
    ) -> some View {
        if let componentInput {
            componentInput
        } else {
            fieldInput(field, renderIndex: renderIndex, locked: locked)
        }
    }

    @ViewBuilder
    private func fieldInput(
        _ field: FormKitFieldDescriptor,
        renderIndex: FormKitRenderIndex,
        locked: Bool
    ) -> some View {
        if field.isEnum {
            enumInput(field, locked: locked)
        } else {
            switch field.scalarType {
            case .boolean:
                booleanInput(field, locked: locked)
            case .date, .time, .dateTime:
                if let displayedComponents = field.scalarType.datePickerComponents {
                    dateInput(field, displayedComponents: displayedComponents, locked: locked)
                }
            default:
                textInput(field, renderIndex: renderIndex, locked: locked)
            }
        }
    }

    private func enumInput(_ field: FormKitFieldDescriptor, locked: Bool) -> some View {
        Picker(
            field.title,
            selection: Binding(
                get: { session.selectedEnumChoiceID(for: field) },
                set: { session.setSelectedEnumChoiceID($0, for: field) }
            )
        ) {
            if !field.isRequired {
                Text(options.labels.notSet).tag(String?.none)
            }
            ForEach(field.enumOptions) { choice in
                Text(choice.title).tag(Optional(choice.id))
            }
        }
        .disabled(locked)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("\(fieldIdentifier(for: field))_picker")
    }

    @ViewBuilder
    private func booleanInput(_ field: FormKitFieldDescriptor, locked: Bool) -> some View {
        if field.allowsNull {
            nullableBooleanPicker(field, locked: locked)
        } else {
            Toggle(
                field.title,
                isOn: Binding(
                    get: { session.booleanValue(for: field) },
                    set: { session.setBooleanValue($0, for: field) }
                )
            )
            .toggleStyle(.switch)
            .disabled(locked)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("\(fieldIdentifier(for: field))_toggle")
        }
    }

    private func nullableBooleanPicker(_ field: FormKitFieldDescriptor, locked: Bool) -> some View {
        Picker(
            field.title,
            selection: Binding(
                get: { nullableBooleanSelection(for: field) },
                set: { setNullableBooleanSelection($0, for: field) }
            )
        ) {
            if !field.isRequired {
                Text(options.labels.notSet).tag(NullableBooleanSelection.absent)
            }
            Text(options.labels.noValue).tag(NullableBooleanSelection.null)
            Text("Off", bundle: .module).tag(NullableBooleanSelection.boolean(false))
            Text("On", bundle: .module).tag(NullableBooleanSelection.boolean(true))
        }
        .pickerStyle(.menu)
        .disabled(locked)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("\(fieldIdentifier(for: field))_picker")
    }

    private func setNullableBooleanSelection(
        _ selection: NullableBooleanSelection,
        for field: FormKitFieldDescriptor
    ) {
        switch selection {
        case .absent:
            session.unsetValue(for: field)
        case .null:
            session.setNullSelection(true, for: field)
        case .boolean(let value):
            session.setBooleanValue(value, for: field)
        }
    }

    private func textInput(
        _ field: FormKitFieldDescriptor,
        renderIndex: FormKitRenderIndex,
        locked: Bool
    ) -> some View {
        FormKitDebouncedTextInputField(
            fieldID: field.id,
            accessibilityIdentifier: "\(fieldIdentifier(for: field))_input",
            accessibilityLabel: field.title,
            prompt: fieldPrompt(for: field),
            canonicalText: session.stringValue(for: field),
            submitLabel: renderIndex.nextFocusableFieldID(after: field.id) == nil ? .done : .next,
            focusedFieldID: $focusedFieldID,
            inputTraits: FormKitTextInputTraits(scalarType: field.scalarType),
            isEditingLocked: locked,
            onDraftChange: { draft in
                pendingTextDrafts[field.id] = draft
            },
            onSubmit: {
                advanceFocus(after: field.id)
            },
            onCommit: { updatedText in
                guard pendingTextDrafts.removeValue(forKey: field.id) != nil else {
                    return
                }
                session.setStringValue(updatedText, for: field)
            }
        )
    }
}
