import Observation

@MainActor
@Observable
final class FormKitDynamicOptionsPickerModel {
    private(set) var options: [FormKitDynamicOption] = []
    let labels: FormKitDynamicOptionsPickerLabels

    var knownOptions: [String: FormKitDynamicOption] { labels.options }
    private(set) var isLoading = false
    private(set) var hasError = false
    private(set) var nextCursor: String?
    private(set) var search = ""

    @ObservationIgnored private let provider: FormKitDynamicOptionsProvider
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var loadedCursors: Set<String> = []

    init(
        provider: @escaping FormKitDynamicOptionsProvider,
        labels: FormKitDynamicOptionsPickerLabels = FormKitDynamicOptionsPickerLabels()
    ) {
        self.provider = provider
        self.labels = labels
    }

    func startSearch(_ search: String) async {
        generation += 1
        self.search = search
        options = []
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
            labels.remember(page.options)
            var indices = Dictionary(uniqueKeysWithValues: options.enumerated().map { ($0.element.id, $0.offset) })
            for option in page.options {
                if let index = indices[option.id] {
                    options[index] = option
                } else {
                    indices[option.id] = options.count
                    options.append(option)
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
final class FormKitDynamicOptionsPickerLabels {
    private(set) var options: [String: FormKitDynamicOption] = [:]

    func remember(_ options: [FormKitDynamicOption]) {
        for option in options {
            self.options[option.id] = option
        }
    }

    func option(for id: String, savedOptions: [FormKitDynamicOption]) -> FormKitDynamicOption {
        savedOptions.first(where: { $0.id == id }) ?? options[id]
            ?? FormKitDynamicOption(id: id, label: id)
    }

    func isDuplicate(_ option: FormKitDynamicOption, savedOptions: [FormKitDynamicOption]) -> Bool {
        options.values.contains { $0.id != option.id && $0.label == option.label }
            || savedOptions.contains { $0.id != option.id && $0.label == option.label }
    }

    func secondaryLabel(for option: FormKitDynamicOption, savedOptions: [FormKitDynamicOption]) -> String? {
        if let detail = option.detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return detail
        }
        return isDuplicate(option, savedOptions: savedOptions) ? option.id : nil
    }

    func displayLabel(for option: FormKitDynamicOption, savedOptions: [FormKitDynamicOption]) -> String {
        guard let secondary = secondaryLabel(for: option, savedOptions: savedOptions) else {
            return option.label
        }
        return "\(option.label), \(secondary)"
    }
}
