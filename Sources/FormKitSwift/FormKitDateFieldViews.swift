import SwiftUI

extension FormKitContainerView {
    @ViewBuilder
    func dateInput(
        _ field: FormKitFieldDescriptor,
        displayedComponents: DatePickerComponents,
        locked: Bool
    ) -> some View {
        if field.allowsNull {
            VStack(alignment: .trailing, spacing: 8) {
                nullableDatePicker(field, locked: locked)

                if nullableValueSelection(for: field) == .value {
                    datePicker(field, displayedComponents: displayedComponents, locked: locked)
                        .labelsHidden()
                }
            }
        } else {
            datePicker(field, displayedComponents: displayedComponents, locked: locked)
        }
    }

    private func nullableDatePicker(_ field: FormKitFieldDescriptor, locked: Bool) -> some View {
        Picker(
            field.title,
            selection: Binding(
                get: { nullableValueSelection(for: field) },
                set: { setNullableValueSelection($0, for: field) }
            )
        ) {
            if !field.isRequired {
                Text(options.labels.notSet).tag(NullableValueSelection.absent)
            }
            Text(options.labels.noValue).tag(NullableValueSelection.null)
            Text(options.labels.value).tag(NullableValueSelection.value)
        }
        .pickerStyle(.menu)
        .disabled(locked)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("\(fieldIdentifier(for: field))_date_state_picker")
    }

    private func setNullableValueSelection(
        _ selection: NullableValueSelection,
        for field: FormKitFieldDescriptor
    ) {
        switch selection {
        case .absent:
            session.unsetValue(for: field)
        case .null:
            session.setNullSelection(true, for: field)
        case .value:
            session.setDateValue(session.dateValue(for: field), for: field)
        }
    }

    private func datePicker(
        _ field: FormKitFieldDescriptor,
        displayedComponents: DatePickerComponents,
        locked: Bool
    ) -> some View {
        DatePicker(
            field.title,
            selection: Binding(
                get: { session.dateValue(for: field) },
                set: { session.setDateValue($0, for: field) }
            ),
            displayedComponents: displayedComponents
        )
        .datePickerStyle(.compact)
        .disabled(locked)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityIdentifier("\(fieldIdentifier(for: field))_date_picker")
    }
}

enum NullableValueSelection: Hashable {
    case absent
    case null
    case value
}
