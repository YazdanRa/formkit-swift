import Foundation

public extension FormKitSession {
    /// The pages to show when the schema requests ``FormKitFormLayout/sectionPages``, or an empty
    /// array when the form scrolls as one page.
    var formPages: [FormKitFormPage] {
        FormKitFormPageBuilder.pages(for: renderPlan)
    }

    /// The index of the page that shows the field, or `nil` when no page does.
    func pageIndex(containing fieldID: String) -> Int? {
        formPages.first { $0.fieldIDs.contains(fieldID) }?.index
    }

    /// Progress per page, the answers that opened follow-ups, and required fields that are still empty.
    ///
    /// Only visible fields count. A field is required when the schema says so or when an answer has
    /// opened it as a follow-up.
    func formSummary() -> FormKitFormSummary {
        formSummary(pages: formPages)
    }

    /// Whether the field holds an answer someone gave, as opposed to a renderer default.
    func hasAnswer(for field: FormKitFieldDescriptor) -> Bool {
        hasValue(for: field) && toolValueSource(for: field) != .defaultValue
    }

    /// The field's current value formatted for display, or `nil` when it is empty.
    func displayValue(for field: FormKitFieldDescriptor) -> String? {
        guard hasValue(for: field), let value = primitiveValue(for: field) else {
            return nil
        }
        return field.enumOptions.first(where: { $0.value == value })?.title ?? value.title
    }

    /// The field's title prefixed with the titles of the sections it sits in, such as
    /// "Housekeeping › Observation".
    func qualifiedTitle(for field: FormKitFieldDescriptor) -> String {
        let sectionsByPointer = Dictionary(
            renderPlan.sections.filter { !$0.isOwnedByArrayRow }.map { ($0.pointer, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var titles = [field.title]
        var pointer: String? = field.parentPointer
        while let current = pointer, current != "#", let section = sectionsByPointer[current] {
            titles.insert(section.title, at: 0)
            pointer = section.parentPointer
        }
        return titles.joined(separator: " › ")
    }
}

extension FormKitSession {
    func formSummary(pages: [FormKitFormPage]) -> FormKitFormSummary {
        let rules = conditionalRules.filter { rule in
            rule.triggerFieldIDs.contains { fieldsByID[$0] != nil }
        }
        let instance = makeInstanceJSONValue()
        let activeRules = rules.filter { rule in
            rule.triggerFieldIDs.allSatisfy { fieldID in
                fieldsByID[fieldID].map { hasValue(for: $0) } ?? true
            } && rule.matches(instance)
        }
        let dependentIDs = Set(rules.flatMap(\.dependentFieldIDs))
        let openedRequiredIDs = Set(activeRules.flatMap(\.dependentFieldIDs))

        let visibleFields = orderedFields.filter { $0.isVisible && $0.shouldSerialize }
        let visibleIDs = Set(visibleFields.map(\.id))
        let missingRequired = visibleFields.filter { field in
            (field.isRequired || openedRequiredIDs.contains(field.id)) && !hasValue(for: field)
        }
        let attentionIDs = Set(missingRequired.map(\.id).filter(openedRequiredIDs.contains))
            .union(fieldErrors.filter { !$0.value.isEmpty }.keys)

        let progress = pages.map { page in
            let questions = page.fieldIDs.filter { fieldID in
                visibleIDs.contains(fieldID) && !dependentIDs.contains(fieldID) && page.isSectionField(fieldID)
            }
            return FormKitPageProgress(
                page: page,
                answered: questions.count { fieldID in fieldsByID[fieldID].map(hasAnswer(for:)) ?? false },
                total: questions.count,
                needsAttention: page.fieldIDs.contains(where: attentionIDs.contains)
            )
        }

        return FormKitFormSummary(
            pages: progress,
            general: generalAnswers(outside: pages, visibleFields: visibleFields),
            flagged: flaggedAnswers(for: activeRules, pages: pages),
            missingRequired: missingRequired
        )
    }

    func hasValue(for field: FormKitFieldDescriptor) -> Bool {
        switch primitiveValue(for: field) {
        case .none, .null:
            return false
        case .string(let value):
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .integer, .number, .boolean:
            return true
        }
    }

    private func generalAnswers(
        outside pages: [FormKitFormPage],
        visibleFields: [FormKitFieldDescriptor]
    ) -> [FormKitSummaryAnswer] {
        visibleFields.compactMap { field in
            guard !pages.contains(where: { $0.isSectionField(field.id) }),
                  let answer = displayValue(for: field)
            else {
                return nil
            }
            return FormKitSummaryAnswer(fieldID: field.id, title: qualifiedTitle(for: field), answer: answer)
        }
    }

    private func flaggedAnswers(
        for activeRules: [FormKitConditionalRule],
        pages: [FormKitFormPage]
    ) -> [FormKitFlaggedAnswer] {
        let fieldOrder = Dictionary(
            orderedFields.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        var seenFieldIDs = Set<String>()
        var flagged: [FormKitFlaggedAnswer] = []
        for rule in activeRules {
            guard let field = rule.triggerFieldIDs.lazy.compactMap({ self.fieldsByID[$0] }).first,
                  seenFieldIDs.insert(field.id).inserted,
                  let answer = displayValue(for: field)
            else {
                continue
            }
            flagged.append(
                FormKitFlaggedAnswer(
                    pageIndex: pages.first { $0.fieldIDs.contains(field.id) }?.index,
                    field: field,
                    qualifiedTitle: qualifiedTitle(for: field),
                    answer: answer,
                    details: rule.dependentFieldIDs.compactMap { fieldID in
                        fieldsByID[fieldID].map {
                            FormKitSummaryAnswer(fieldID: $0.id, title: $0.title, answer: displayValue(for: $0) ?? "")
                        }
                    }
                )
            )
        }
        return flagged.sorted { (fieldOrder[$0.field.id] ?? .max) < (fieldOrder[$1.field.id] ?? .max) }
    }
}
