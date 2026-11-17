import SwiftUI

/// A host-backed people selector. Lookup begins when its sheet opens.
/// Selection changes update the binding immediately. Done dismisses the sheet.
public struct FormKitPeoplePicker: View {
    private let title: String
    private let selection: FormKitPeopleSelection
    private let savedPeople: [FormKitPersonOption]
    private let isRequired: Bool
    private let isEditingLocked: Bool
    private let provider: FormKitPeopleProvider
    @State private var isPresented = false
    @State private var labels = FormKitPeoplePickerLabels()

    public init(
        title: String,
        selection: FormKitPeopleSelection,
        savedPeople: [FormKitPersonOption] = [],
        isRequired: Bool = false,
        isEditingLocked: Bool = false,
        provider: @escaping FormKitPeopleProvider
    ) {
        self.title = title
        self.selection = selection
        self.savedPeople = savedPeople
        self.isRequired = isRequired
        self.isEditingLocked = isEditingLocked
        self.provider = provider
    }

    public var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack {
                Text(summary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "person.crop.circle.badge.plus")
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isEditingLocked)
        .accessibilityLabel(title)
        .accessibilityValue(summary)
        .sheet(isPresented: $isPresented) {
            FormKitPeoplePickerSheet(
                title: title,
                selection: selection,
                savedPeople: savedPeople,
                labels: labels,
                isRequired: isRequired,
                isEditingLocked: isEditingLocked,
                provider: provider
            )
        }
    }

    private var summary: String {
        guard !selection.ids.isEmpty else {
            return String(localized: "Choose people", bundle: .module)
        }
        return selection.ids.map { id in
            labels.displayLabel(
                for: labels.person(for: id, savedPeople: savedPeople),
                savedPeople: savedPeople
            )
        }.joined(separator: ", ")
    }
}
