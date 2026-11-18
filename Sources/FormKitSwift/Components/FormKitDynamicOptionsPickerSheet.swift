import SwiftUI

struct FormKitDynamicOptionsPickerSheet: View {
    let title: String
    let selection: FormKitDynamicSelection
    let savedOptions: [FormKitDynamicOption]
    let labels: FormKitDynamicOptionsPickerLabels
    let maximumSelectionCount: Int?
    let isRequired: Bool
    let isEditingLocked: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var model: FormKitDynamicOptionsPickerModel
    @State private var pageTask: Task<Void, Never>?

    init(
        title: String,
        selection: FormKitDynamicSelection,
        savedOptions: [FormKitDynamicOption],
        labels: FormKitDynamicOptionsPickerLabels,
        isRequired: Bool,
        maximumSelectionCount: Int?,
        isEditingLocked: Bool,
        provider: @escaping FormKitDynamicOptionsProvider
    ) {
        self.title = title
        self.selection = selection
        self.savedOptions = savedOptions
        self.labels = labels
        self.isRequired = isRequired
        self.maximumSelectionCount = maximumSelectionCount
        self.isEditingLocked = isEditingLocked
        _model = State(initialValue: FormKitDynamicOptionsPickerModel(provider: provider, labels: labels))
    }

    var body: some View {
        NavigationStack {
            List {
                if !selectedOptions.isEmpty || showsClearSelection {
                    Section {
                        ForEach(selectedOptions) { option in
                            optionRow(option, isSelected: true)
                        }
                        if showsClearSelection {
                            Button(String(localized: "Clear selection", bundle: .module)) {
                                guard !isEditingLocked else { return }
                                selection.clear(isRequired: isRequired)
                            }
                            .disabled(isEditingLocked)
                            .accessibilityIdentifier("formkit_dynamic_clear")
                        }
                    } header: {
                        Text("Selected options", bundle: .module)
                    }
                }
                Section {
                    ForEach(model.options.filter { !selection.ids.contains($0.id) }) { option in
                        optionRow(option, isSelected: false)
                    }
                    loadingStatus
                }
            }
            .searchable(text: $search, prompt: Text("Search options", bundle: .module))
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", bundle: .module)) { dismiss() }
                        .accessibilityIdentifier("formkit_dynamic_done")
                }
            }
            .task(id: search) {
                pageTask?.cancel()
                await model.startSearch(search)
            }
            .onDisappear {
                pageTask?.cancel()
                model.cancel()
            }
        }
    }

    var showsClearSelection: Bool {
        !isRequired && (!selection.isSingle || !selection.ids.isEmpty)
    }

    private var selectedOptions: [FormKitDynamicOption] {
        var seen: Set<String> = []
        return selection.ids.filter { seen.insert($0).inserted }.map { id in
            labels.option(for: id, savedOptions: savedOptions)
        }
    }

    private func optionRow(_ option: FormKitDynamicOption, isSelected: Bool) -> some View {
        Button {
            guard !isEditingLocked else { return }
            selection.choose(option.id, isRequired: isRequired, maximumSelectionCount: maximumSelectionCount)
            if selection.isSingle {
                dismiss()
            }
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(option.label)
                        .foregroundStyle(.primary)
                    if let detail = labels.secondaryLabel(for: option, savedOptions: savedOptions) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isEditingLocked || !selection.canChoose(option.id, maximumSelectionCount: maximumSelectionCount))
        .accessibilityLabel(labels.displayLabel(for: option, savedOptions: savedOptions))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("formkit_dynamic_option_\(option.id)")
    }

    @ViewBuilder
    private var loadingStatus: some View {
        if model.isLoading {
            ProgressView(String(localized: "Loading options", bundle: .module))
        } else if model.hasError {
            Text("Options could not be loaded.", bundle: .module)
            Button(String(localized: "Retry", bundle: .module)) {
                pageTask = Task { await model.retry() }
            }
            .accessibilityIdentifier("formkit_dynamic_retry")
        } else if model.nextCursor != nil {
            Button(String(localized: "Load more", bundle: .module)) {
                pageTask = Task { await model.loadMore() }
            }
            .accessibilityIdentifier("formkit_dynamic_load_more")
        } else if model.options.isEmpty {
            Text("No options found", bundle: .module)
                .foregroundStyle(.secondary)
        }
    }
}
