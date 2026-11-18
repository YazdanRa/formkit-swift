import SwiftUI

struct FormKitPeoplePickerSheet: View {
    let title: String
    let selection: FormKitPeopleSelection
    let savedPeople: [FormKitPersonOption]
    let labels: FormKitPeoplePickerLabels
    let maximumSelectionCount: Int?
    let isRequired: Bool
    let isEditingLocked: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var model: FormKitPeoplePickerModel
    @State private var pageTask: Task<Void, Never>?

    init(
        title: String,
        selection: FormKitPeopleSelection,
        savedPeople: [FormKitPersonOption],
        labels: FormKitPeoplePickerLabels,
        isRequired: Bool,
        maximumSelectionCount: Int?,
        isEditingLocked: Bool,
        provider: @escaping FormKitPeopleProvider
    ) {
        self.title = title
        self.selection = selection
        self.savedPeople = savedPeople
        self.labels = labels
        self.isRequired = isRequired
        self.maximumSelectionCount = maximumSelectionCount
        self.isEditingLocked = isEditingLocked
        _model = State(initialValue: FormKitPeoplePickerModel(provider: provider, labels: labels))
    }

    var body: some View {
        NavigationStack {
            List {
                if !selectedPeople.isEmpty {
                    Section {
                        ForEach(selectedPeople) { person in
                            personRow(person, isSelected: true)
                        }
                        if !isRequired {
                            Button(String(localized: "Clear selection", bundle: .module)) {
                                guard !isEditingLocked else { return }
                                selection.clear(isRequired: isRequired)
                            }
                            .disabled(isEditingLocked)
                            .accessibilityIdentifier("formkit_people_clear")
                        }
                    } header: {
                        Text("Selected people", bundle: .module)
                    }
                }
                Section {
                    ForEach(model.people.filter { !selection.ids.contains($0.id) }) { person in
                        personRow(person, isSelected: false)
                    }
                    loadingStatus
                }
            }
            .searchable(text: $search, prompt: Text("Search people", bundle: .module))
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", bundle: .module)) { dismiss() }
                        .accessibilityIdentifier("formkit_people_done")
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

    private var selectedPeople: [FormKitPersonOption] {
        var seen: Set<String> = []
        return selection.ids.filter { seen.insert($0).inserted }.map { id in
            labels.person(for: id, savedPeople: savedPeople)
        }
    }

    private func personRow(_ person: FormKitPersonOption, isSelected: Bool) -> some View {
        Button {
            guard !isEditingLocked else { return }
            selection.choose(person.id, isRequired: isRequired, maximumSelectionCount: maximumSelectionCount)
            if selection.isSingle {
                dismiss()
            }
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(person.displayName)
                        .foregroundStyle(.primary)
                    if let detail = labels.secondaryLabel(for: person, savedPeople: savedPeople) {
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
        .disabled(isEditingLocked || !selection.canChoose(person.id, maximumSelectionCount: maximumSelectionCount))
        .accessibilityLabel(labels.displayLabel(for: person, savedPeople: savedPeople))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("formkit_person_\(person.id)")
    }

    @ViewBuilder
    private var loadingStatus: some View {
        if model.isLoading {
            ProgressView(String(localized: "Loading people", bundle: .module))
        } else if model.hasError {
            Text("People could not be loaded.", bundle: .module)
            Button(String(localized: "Retry", bundle: .module)) {
                pageTask = Task { await model.retry() }
            }
            .accessibilityIdentifier("formkit_people_retry")
        } else if model.nextCursor != nil {
            Button(String(localized: "Load more", bundle: .module)) {
                pageTask = Task { await model.loadMore() }
            }
            .accessibilityIdentifier("formkit_people_load_more")
        } else if model.people.isEmpty {
            Text("No people found", bundle: .module)
                .foregroundStyle(.secondary)
        }
    }
}
