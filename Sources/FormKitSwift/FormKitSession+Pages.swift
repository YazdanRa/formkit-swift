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
    /// Only visible fields count. Required fields follow the active schema, including conditional requirements.
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
        qualifiedTitle(field.title, parentPointer: field.parentPointer)
    }

    internal func qualifiedTitle(for section: FormKitRenderPlan.SectionDescriptor) -> String {
        qualifiedTitle(section.title, parentPointer: section.parentPointer)
    }

    private func qualifiedTitle(_ title: String, parentPointer: String?) -> String {
        let sectionsByPointer = Dictionary(
            renderPlan.sections.filter { !$0.isOwnedByArrayRow }.map { ($0.pointer, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var titles = [title]
        var pointer = parentPointer
        while let current = pointer, current != "#", let section = sectionsByPointer[current] {
            titles.insert(section.title, at: 0)
            pointer = section.parentPointer
        }
        return titles.joined(separator: " › ")
    }
}

extension FormKitSession {
    func formSummary(pages: [FormKitFormPage]) -> FormKitFormSummary {
        let visibleFields = orderedFields.filter { $0.isVisible && $0.shouldSerialize }
        let visibleIDs = Set(visibleFields.map(\.id))
        let rules = conditionalRules.flatMap { rule in
            guard let arrayPointer = rule.arrayPointer else { return [rule] }
            return (arraySectionsByPointer[arrayPointer]?.arrayDescriptor?.rows ?? []).map(rule.bound(to:))
        }.filter { rule in
            rule.triggerFieldIDs.contains(where: visibleIDs.contains)
        }
        let instance = makeInstanceJSONValue()
        let activeRules = rules.filter { rule in
            rule.triggerFieldIDs.allSatisfy { fieldID in
                fieldsByID[fieldID].map { hasValue(for: $0) } ?? true
            } && rule.matches(instance)
        }
        let missingRequired = visibleFields.filter { field in
            field.isRequired && !isDynamicOptionsArrayItem(field) && !hasValue(for: field)
        }

        return FormKitFormSummary(
            pages: pageProgress(pages, visibleFields: visibleFields, rules: rules,
                                activeRules: activeRules, instance: instance),
            general: generalAnswers(outside: pages, visibleFields: visibleFields),
            flagged: flaggedAnswers(for: activeRules, pages: pages, visibleFields: visibleFields),
            missingRequired: missingRequired,
            missingRequiredArraySections: missingDynamicOptionsArrays(in: instance)
        )
    }

    private func pageProgress(
        _ pages: [FormKitFormPage],
        visibleFields: [FormKitFieldDescriptor],
        rules: [FormKitConditionalRule],
        activeRules: [FormKitConditionalRule],
        instance: FormKitJSONValue
    ) -> [FormKitPageProgress] {
        let visibleIDs = Set(visibleFields.map(\.id))
        let dependentIDs = Set(rules.flatMap(\.dependentFieldIDs))
        let openedRequiredIDs = Set(activeRules.flatMap(\.dependentFieldIDs))
        let missingRequired = visibleFields.filter {
            $0.isRequired && !isDynamicOptionsArrayItem($0) && !hasValue(for: $0)
        }
        let attentionIDs = Set(missingRequired.map(\.id).filter(openedRequiredIDs.contains))
            .union(fieldErrors.filter { !$0.value.isEmpty }.keys)
        let invalidArrayPointers = renderPlan.sections
            .filter { $0.isArraySection && !(arrayErrors[$0.id] ?? []).isEmpty }
            .map(\.pointer)
            + missingDynamicOptionsArrays(in: instance).map(\.pointer).filter(openedRequiredIDs.contains)
        let dynamicArrays = visibleDynamicOptionsArrays

        return pages.map { page in
            let questions = page.fieldIDs.filter { fieldID in
                visibleIDs.contains(fieldID) && !dependentIDs.contains(fieldID) && page.isSectionField(fieldID)
                    && fieldsByID[fieldID].map { !isDynamicOptionsArrayItem($0) } == true
            }
            let arrays = dynamicArrays.filter { section in
                page.isSectionField(section.pointer) && !dependentIDs.contains(section.pointer)
            }
            return FormKitPageProgress(
                page: page,
                answered: questions.count { fieldID in fieldsByID[fieldID].map(hasAnswer(for:)) ?? false }
                    + arrays.count { hasAnswer(for: $0, in: instance) },
                total: questions.count + arrays.count,
                needsAttention: page.fieldIDs.contains(where: attentionIDs.contains)
                    || invalidArrayPointers.contains { page.holds(pointer: $0) }
            )
        }
    }

    /// Whether the field holds a value validation accepts as present. An explicit null counts on a
    /// nullable field; ``hasAnswer(for:)`` then uses provenance to leave out renderer defaults.
    func hasValue(for field: FormKitFieldDescriptor) -> Bool {
        switch primitiveValue(for: field) {
        case .none:
            return false
        case .null:
            return field.allowsNull
        case .string(let value):
            if preservesDynamicOptionID(for: field) {
                return true
            }
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
        pages: [FormKitFormPage],
        visibleFields: [FormKitFieldDescriptor]
    ) -> [FormKitFlaggedAnswer] {
        let visibleIDs = Set(visibleFields.map(\.id))
        var dependentsByTrigger: [String: Set<String>] = [:]
        for rule in activeRules {
            guard let triggerID = rule.triggerFieldIDs.first(where: visibleIDs.contains) else { continue }
            dependentsByTrigger[triggerID, default: []].formUnion(rule.dependentFieldIDs)
        }
        return visibleFields.compactMap { field in
            guard let dependentIDs = dependentsByTrigger[field.id],
                  let answer = displayValue(for: field)
            else {
                return nil
            }
            return FormKitFlaggedAnswer(
                pageIndex: pages.first { $0.fieldIDs.contains(field.id) }?.index,
                field: field,
                qualifiedTitle: qualifiedTitle(for: field),
                answer: answer,
                details: visibleFields.filter { dependentIDs.contains($0.id) }.map {
                    FormKitSummaryAnswer(fieldID: $0.id, title: $0.title, answer: displayValue(for: $0) ?? "")
                }
            )
        }
    }
}
