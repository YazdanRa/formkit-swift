import Observation

@MainActor
@Observable
final class FormKitPeoplePickerModel {
    private(set) var people: [FormKitPersonOption] = []
    let labels: FormKitPeoplePickerLabels

    var knownPeople: [String: FormKitPersonOption] { labels.people }
    private(set) var isLoading = false
    private(set) var hasError = false
    private(set) var nextCursor: String?
    private(set) var search = ""

    @ObservationIgnored private let provider: FormKitPeopleProvider
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var loadedCursors: Set<String> = []

    init(
        provider: @escaping FormKitPeopleProvider,
        labels: FormKitPeoplePickerLabels = FormKitPeoplePickerLabels()
    ) {
        self.provider = provider
        self.labels = labels
    }

    func startSearch(_ search: String) async {
        generation += 1
        self.search = search
        people = []
        nextCursor = nil
        loadedCursors = []
        await load(cursor: nil, generation: generation)
    }

    func loadMore() async {
        guard !isLoading, let nextCursor else { return }
        await load(cursor: nextCursor, generation: generation)
    }

    func retry() async {
        guard !isLoading else { return }
        await load(cursor: nextCursor, generation: generation)
    }

    func cancel() {
        generation += 1
        isLoading = false
        hasError = false
    }

    private func load(cursor: String?, generation requestGeneration: Int) async {
        isLoading = true
        hasError = false
        do {
            let page = try await provider(search, cursor)
            guard requestGeneration == generation else { return }
            guard !Task.isCancelled else {
                isLoading = false
                return
            }
            if let cursor {
                loadedCursors.insert(cursor)
            }
            labels.remember(page.people)
            var indices = Dictionary(uniqueKeysWithValues: people.enumerated().map { ($0.element.id, $0.offset) })
            for person in page.people {
                if let index = indices[person.id] {
                    people[index] = person
                } else {
                    indices[person.id] = people.count
                    people.append(person)
                }
            }
            nextCursor = page.nextCursor.flatMap { loadedCursors.contains($0) ? nil : $0 }
        } catch {
            guard requestGeneration == generation else { return }
            hasError = !(error is CancellationError) && !Task.isCancelled
        }
        isLoading = false
    }
}

@MainActor
@Observable
final class FormKitPeoplePickerLabels {
    private(set) var people: [String: FormKitPersonOption] = [:]

    func remember(_ options: [FormKitPersonOption]) {
        for person in options {
            people[person.id] = person
        }
    }

    func person(for id: String, savedPeople: [FormKitPersonOption]) -> FormKitPersonOption {
        savedPeople.first(where: { $0.id == id }) ?? people[id]
            ?? FormKitPersonOption(id: id, displayName: id)
    }

    func isDuplicate(_ person: FormKitPersonOption, savedPeople: [FormKitPersonOption]) -> Bool {
        people.values.contains { $0.id != person.id && $0.displayName == person.displayName }
            || savedPeople.contains { $0.id != person.id && $0.displayName == person.displayName }
    }

    func secondaryLabel(for person: FormKitPersonOption, savedPeople: [FormKitPersonOption]) -> String? {
        if let detail = person.detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return detail
        }
        return isDuplicate(person, savedPeople: savedPeople) ? person.id : nil
    }

    func displayLabel(for person: FormKitPersonOption, savedPeople: [FormKitPersonOption]) -> String {
        guard let secondary = secondaryLabel(for: person, savedPeople: savedPeople) else {
            return person.displayName
        }
        return "\(person.displayName), \(secondary)"
    }
}
