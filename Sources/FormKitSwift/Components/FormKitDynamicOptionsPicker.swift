import SwiftUI

/// A host-backed dynamic option selector. Lookup begins when its sheet opens.
/// Selection changes update the binding immediately. Done dismisses the sheet.
public struct FormKitDynamicOptionsPicker: View {
    private let title: String
    private let selection: FormKitDynamicSelection
    private let savedOptions: [FormKitDynamicOption]
    private let maximumSelectionCount: Int?
    private let isRequired: Bool
    private let isEditingLocked: Bool
    private let provider: FormKitDynamicOptionsProvider
    @State private var isPresented = false
    @State private var labels = FormKitDynamicOptionsPickerLabels()

    public init(
        title: String,
        selection: FormKitDynamicSelection,
        savedOptions: [FormKitDynamicOption] = [],
        isRequired: Bool = false,
        maximumSelectionCount: Int? = nil,
        isEditingLocked: Bool = false,
        provider: @escaping FormKitDynamicOptionsProvider
    ) {
        self.title = title
        self.selection = selection
        self.savedOptions = savedOptions
        self.isRequired = isRequired
        self.maximumSelectionCount = maximumSelectionCount
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
                Image(systemName: "list.bullet")
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
            FormKitDynamicOptionsPickerSheet(
                title: title,
                selection: selection,
                savedOptions: savedOptions,
                labels: labels,
                isRequired: isRequired,
                maximumSelectionCount: maximumSelectionCount,
                isEditingLocked: isEditingLocked,
                provider: provider
            )
        }
    }

    private var summary: String {
        guard !selection.ids.isEmpty else {
            return String(localized: "Choose options", bundle: .module)
        }
        return selection.ids.map { id in
            labels.displayLabel(
                for: labels.option(for: id, savedOptions: savedOptions),
                savedOptions: savedOptions
            )
        }.joined(separator: ", ")
    }
}
