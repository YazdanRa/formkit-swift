import Foundation

enum FormKitDisplayBlockKind: Equatable {
    case section(String)
    case fieldGroup(sectionID: String, fieldIDs: [String])
}

struct FormKitRenderIndex {
    struct ParentSectionKey: Hashable {
        let pointer: String
        let ownerArrayRowID: String?
    }

    struct DisplayBlock: Identifiable, Equatable {
        let kind: FormKitDisplayBlockKind
        let showSectionHeader: Bool
        let showSectionFooter: Bool

        var id: String {
            switch kind {
            case let .section(sectionID):
                return "section:\(sectionID)"
            case let .fieldGroup(sectionID, fieldIDs):
                if fieldIDs.isEmpty {
                    return "field_group:\(sectionID):\(showSectionHeader ? "header" : "footer")"
                }
                return "field_group:\(sectionID):\(fieldIDs.joined(separator: ","))"
            }
        }
    }

    let visibleRootBlocks: [DisplayBlock]
    private let fieldsByID: [String: FormKitFieldDescriptor]
    private let sectionsByID: [String: FormKitRenderPlan.SectionDescriptor]
    private let displayBlocksBySectionID: [String: [DisplayBlock]]
    private let visibleChildSectionsByParentKey: [ParentSectionKey: [FormKitRenderPlan.SectionDescriptor]]
    private let rootSectionID: String?
    private let focusableFieldIDs: Set<String>
    private let orderedFocusableFieldIDs: [String]

    init(renderPlan: FormKitRenderPlan, focusableFieldIDs: Set<String>? = nil) {
        let fieldsByID = Dictionary(uniqueKeysWithValues: renderPlan.fields.map { ($0.id, $0) })
        let sectionsByID = Dictionary(uniqueKeysWithValues: renderPlan.sections.map { ($0.id, $0) })
        let visibleChildSectionsByParentKey = Self.visibleChildSectionsByParentKey(
            in: renderPlan.sections
        )

        let displayBlocksBySectionID = renderPlan.sections.reduce(into: [String: [DisplayBlock]]()) { result, section in
            guard section.isVisible else {
                return
            }

            result[section.id] = Self.makeDisplayBlocks(
                for: section,
                fieldsByID: fieldsByID,
                visibleChildSectionsByParentKey: visibleChildSectionsByParentKey
            )
        }

        self.fieldsByID = fieldsByID
        self.sectionsByID = sectionsByID
        self.displayBlocksBySectionID = displayBlocksBySectionID
        self.visibleChildSectionsByParentKey = visibleChildSectionsByParentKey
        let focusableFieldIDs = focusableFieldIDs ?? Set(
            renderPlan.fields.lazy.filter(\.supportsStockTextInputFocus).map(\.id)
        )
        self.focusableFieldIDs = focusableFieldIDs
        orderedFocusableFieldIDs = renderPlan.fieldOrder.compactMap { fieldID in
            focusableFieldIDs.contains(fieldID) ? fieldID : nil
        }

        let rootSection = renderPlan.sections.first(where: {
            $0.pointer == "#" && !$0.isOwnedByArrayRow
        })
        rootSectionID = rootSection?.id
        if let rootSection {
            visibleRootBlocks = displayBlocksBySectionID[rootSection.id] ?? []
        } else {
            visibleRootBlocks = renderPlan.sections
                .filter { !$0.isOwnedByArrayRow && $0.isVisible }
                .map {
                    DisplayBlock(
                        kind: .section($0.id),
                        showSectionHeader: false,
                        showSectionFooter: false
                    )
                }
        }
    }

    var renderableRootBlocks: [DisplayBlock] {
        guard let rootSectionID,
              sectionsByID[rootSectionID]?.arrayDescriptor == nil
        else {
            return Self.expandingObjectSections(
                in: visibleRootBlocks,
                sectionsByID: sectionsByID,
                displayBlocksBySectionID: displayBlocksBySectionID
            )
        }

        return Self.expandingRootObjectSection(
            rootSectionID,
            blocks: visibleRootBlocks,
            sectionsByID: sectionsByID,
            displayBlocksBySectionID: displayBlocksBySectionID
        )
    }

    func field(_ fieldID: String) -> FormKitFieldDescriptor? {
        fieldsByID[fieldID]
    }

    func section(_ sectionID: String) -> FormKitRenderPlan.SectionDescriptor? {
        sectionsByID[sectionID]
    }

    func displayBlocks(for section: FormKitRenderPlan.SectionDescriptor) -> [DisplayBlock] {
        displayBlocksBySectionID[section.id] ?? []
    }

    func visibleFields(in section: FormKitRenderPlan.SectionDescriptor) -> [FormKitFieldDescriptor] {
        section.fieldIDs.compactMap { fieldID in
            guard let field = fieldsByID[fieldID], field.isVisible else {
                return nil
            }
            return field
        }
    }

    func visibleSections(in row: FormKitArrayRowDescriptor) -> [FormKitRenderPlan.SectionDescriptor] {
        row.sectionIDs.compactMap { sectionID in
            guard let section = sectionsByID[sectionID], section.isVisible else {
                return nil
            }
            return section
        }
    }

    func firstVisibleField(in row: FormKitArrayRowDescriptor) -> FormKitFieldDescriptor? {
        row.fieldIDs.compactMap { field($0) }.first(where: \.isVisible)
    }

    func firstFocusableField(in row: FormKitArrayRowDescriptor) -> FormKitFieldDescriptor? {
        row.fieldIDs.lazy
            .filter { focusableFieldIDs.contains($0) }
            .compactMap { field($0) }
            .first
    }

    func nextFocusableFieldID(after fieldID: String) -> String? {
        guard let currentIndex = orderedFocusableFieldIDs.firstIndex(of: fieldID) else {
            return nil
        }

        return orderedFocusableFieldIDs.dropFirst(currentIndex + 1).first
    }
}
