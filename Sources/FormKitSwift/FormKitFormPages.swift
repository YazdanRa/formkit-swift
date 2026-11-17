import Foundation
import JSONSchema

/// One page of a ``FormKitFormLayout/sectionPages`` form: a top-level object section, or a schema's
/// presentation group of whole root properties.
///
/// Top-level fields outside any section join the page of the section after them, or the last page
/// when no section follows, so a leading "Room number" opens page one.
public struct FormKitFormPage: Identifiable, Sendable, Equatable {
    public let index: Int
    /// The section's JSON Pointer, such as `#/housekeeping`, or `page:` followed by a presentation group ID.
    public let id: String
    /// The render plan identifier of the page's section, or `#` for a root presentation group.
    public let sectionID: String
    /// The top-level property key, such as `housekeeping`.
    public let propertyKey: String
    public let title: String
    /// Every field on the page in form order, including top-level fields placed on it.
    public let fieldIDs: [String]
    /// Pointers of the top-level properties outside any section that sit on this page.
    public let loosePointers: [String]

    /// Whether the field belongs to the page's own section rather than sitting on it from the top level.
    public func isSectionField(_ fieldID: String) -> Bool {
        sectionID == "#" ? fieldIDs.contains(fieldID) : fieldID.hasPrefix(id + "/")
    }

    /// Whether a field or section pointer is shown on this page, inside its section or under a top-level
    /// property placed on it.
    func holds(pointer: String) -> Bool {
        pointer.hasPrefix(id + "/")
            || loosePointers.contains { pointer == $0 || pointer.hasPrefix($0 + "/") }
    }
}

/// How far one page has got, for the progress bars, the section menu, and the summary page.
public struct FormKitPageProgress: Identifiable, Sendable, Equatable {
    public enum Status: String, Sendable, Equatable {
        case notStarted = "not_started"
        case partial
        case done
        case needsAttention = "needs_attention"
    }

    public let page: FormKitFormPage
    /// The section's questions with an answer. Follow-ups opened by an answer and top-level fields
    /// placed on the page are not counted as its questions.
    public let answered: Int
    public let total: Int
    /// A required follow-up an answer opened is still empty, or a field on the page failed validation. A required
    /// field nobody has reached yet is not flagged, so a fresh form does not open in an error state.
    public let needsAttention: Bool

    public var id: String {
        page.id
    }

    public var status: Status {
        if needsAttention {
            return .needsAttention
        }
        if total > 0, answered >= total {
            return .done
        }
        return answered > 0 ? .partial : .notStarted
    }
}

/// A field and its current answer, formatted for display or speech.
public struct FormKitSummaryAnswer: Identifiable, Sendable, Equatable {
    public let fieldID: String
    public let title: String
    /// The answer's display text, or an empty string when the field has no answer.
    public let answer: String

    public var id: String {
        fieldID
    }
}

/// An answer that opened follow-up fields, such as "Failed" opening its observation.
public struct FormKitFlaggedAnswer: Identifiable, Sendable, Equatable {
    public let pageIndex: Int?
    public let field: FormKitFieldDescriptor
    public let qualifiedTitle: String
    public let answer: String
    /// The follow-ups it opened, with whatever was entered for them.
    public let details: [FormKitSummaryAnswer]

    public var id: String {
        field.id
    }
}

/// Everything the summary page says about a paged form.
public struct FormKitFormSummary: Sendable, Equatable {
    public let pages: [FormKitPageProgress]
    /// Answered fields that sit outside every section.
    public let general: [FormKitSummaryAnswer]
    public let flagged: [FormKitFlaggedAnswer]
    /// Required fields that are still empty, in form order.
    public let missingRequired: [FormKitFieldDescriptor]
}

enum FormKitFormPageBuilder {
    /// Splits the plan into one page per visible top-level object section. Returns no pages unless the
    /// plan asks for ``FormKitFormLayout/sectionPages`` and has at least two such sections.
    static func pages(for plan: FormKitRenderPlan) -> [FormKitFormPage] {
        guard plan.layout == .sectionPages,
              let root = plan.sections.first(where: { $0.pointer == "#" && !$0.isOwnedByArrayRow })
        else {
            return []
        }

        if let groups = plan.pageGroups {
            return presentationPages(groups, root: root, plan: plan)
        }
        return sectionPages(root: root, plan: plan)
    }

    private static func sectionPages(
        root: FormKitRenderPlan.SectionDescriptor,
        plan: FormKitRenderPlan
    ) -> [FormKitFormPage] {
        typealias Section = FormKitRenderPlan.SectionDescriptor
        let topSections = plan.sections.reduce(into: [String: Section]()) { result, section in
            guard section.parentPointer == root.pointer,
                  !section.isOwnedByArrayRow,
                  !section.isArraySection,
                  let propertyKey = section.propertyKey
            else {
                return
            }
            result[propertyKey] = section
        }

        var drafts: [PageDraft] = []
        var loose = PageDraft(section: nil)
        for propertyKey in root.propertyOrder {
            if let section = topSections[propertyKey] {
                // A section its conditionals hide is neither a page nor loose fields on another one.
                guard section.isVisible else {
                    continue
                }
                var draft = loose
                draft.section = section
                draft.fieldIDs += fieldIDs(under: section.pointer, in: plan)
                drafts.append(draft)
                loose = PageDraft(section: nil)
            } else {
                let pointer = JSONPointer.pointerString(from: [propertyKey])
                loose.fieldIDs += fieldIDs(atOrUnder: pointer, in: plan)
                loose.loosePointers.append(pointer)
            }
        }
        guard drafts.count >= 2 else {
            return []
        }
        drafts[drafts.count - 1].fieldIDs += loose.fieldIDs
        drafts[drafts.count - 1].loosePointers += loose.loosePointers

        return drafts.enumerated().compactMap { index, draft in
            draft.section.map { section in
                FormKitFormPage(
                    index: index,
                    id: section.pointer,
                    sectionID: section.id,
                    propertyKey: section.propertyKey ?? "",
                    title: section.title,
                    fieldIDs: draft.fieldIDs,
                    loosePointers: draft.loosePointers
                )
            }
        }
    }

    private struct PageDraft {
        var section: FormKitRenderPlan.SectionDescriptor?
        var fieldIDs: [String] = []
        var loosePointers: [String] = []
    }

    private static func presentationPages(
        _ groups: [FormKitPageGroup],
        root: FormKitRenderPlan.SectionDescriptor,
        plan: FormKitRenderPlan
    ) -> [FormKitFormPage] {
        let visibleFields = plan.fields.filter(\.isVisible)
        let visibleFieldIDs = Set(visibleFields.map(\.id))
        let visibleArrays = plan.sections.filter { $0.isArraySection && $0.isVisible && !$0.isOwnedByArrayRow }
        let availableProperties = root.propertyOrder.filter { key in
            let pointer = JSONPointer.pointerString(from: [key])
            return visibleFields.contains { $0.pointer == pointer || $0.pointer.hasPrefix(pointer + "/") }
                || visibleArrays.contains { $0.pointer == pointer || $0.pointer.hasPrefix(pointer + "/") }
        }
        let available = Set(availableProperties)
        var assigned: Set<String> = []
        var drafts: [(group: FormKitPageGroup, keys: [String])] = []
        for group in groups {
            let keys = group.fields.filter(available.contains)
            guard !keys.isEmpty else { continue }
            assigned.formUnion(keys)
            drafts.append((group, keys))
        }
        guard drafts.count >= 2 else { return [] }
        drafts[drafts.count - 1].keys += availableProperties.filter { !assigned.contains($0) }

        return drafts.enumerated().map { index, draft in
            let pointers = draft.keys.map { JSONPointer.pointerString(from: [$0]) }
            let fieldIDs = plan.fieldOrder.filter { fieldID in
                visibleFieldIDs.contains(fieldID)
                    && pointers.contains { fieldID == $0 || fieldID.hasPrefix($0 + "/") }
            }
            return FormKitFormPage(
                index: index,
                id: "page:" + draft.group.id,
                sectionID: "#",
                propertyKey: draft.group.id,
                title: draft.group.title,
                fieldIDs: fieldIDs,
                loosePointers: pointers
            )
        }
    }

    private static func fieldIDs(under pointer: String, in plan: FormKitRenderPlan) -> [String] {
        plan.fieldOrder.filter { $0.hasPrefix(pointer + "/") }
    }

    private static func fieldIDs(atOrUnder pointer: String, in plan: FormKitRenderPlan) -> [String] {
        plan.fieldOrder.filter { $0 == pointer || $0.hasPrefix(pointer + "/") }
    }
}
