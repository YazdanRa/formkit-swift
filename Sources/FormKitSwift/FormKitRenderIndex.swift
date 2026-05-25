import Foundation

struct FormKitRenderIndex {
    private struct ParentSectionKey: Hashable {
        let pointer: String
        let ownerArrayRowID: String?
    }

    struct DisplayBlock: Identifiable, Equatable {
        enum Kind: Equatable {
            case section(String)
            case fieldGroup(sectionID: String, fieldIDs: [String])
        }

        let kind: Kind
        let showSectionHeader: Bool
        let showSectionFooter: Bool

        var id: String {
            switch kind {
            case let .section(sectionID):
                return "section:\(sectionID)"
            case let .fieldGroup(sectionID, fieldIDs):
                return "field_group:\(sectionID):\(fieldIDs.joined(separator: ","))"
            }
        }
    }

    let visibleRootBlocks: [DisplayBlock]
    private let fieldsByID: [String: FormKitFieldDescriptor]
    private let sectionsByID: [String: FormKitRenderPlan.SectionDescriptor]
    private let displayBlocksBySectionID: [String: [DisplayBlock]]
    private let visibleChildSectionsByParentKey: [ParentSectionKey: [FormKitRenderPlan.SectionDescriptor]]
    private let orderedFocusableFieldIDs: [String]

    init(renderPlan: FormKitRenderPlan) {
        let fieldsByID = Dictionary(uniqueKeysWithValues: renderPlan.fields.map { ($0.id, $0) })
        let sectionsByID = Dictionary(uniqueKeysWithValues: renderPlan.sections.map { ($0.id, $0) })
        let visibleChildSectionsByParentKey = Dictionary(
            grouping: renderPlan.sections.filter {
                $0.isVisible && $0.parentPointer != nil
            },
            by: {
                ParentSectionKey(
                    pointer: $0.parentPointer ?? "#",
                    ownerArrayRowID: $0.ownerArrayRowID
                )
            }
        ).mapValues { sections in
            sections.sorted { $0.order < $1.order }
        }

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
        orderedFocusableFieldIDs = renderPlan.fieldOrder.compactMap { fieldID in
            guard let field = fieldsByID[fieldID],
                  field.isVisible,
                  field.isInteractive
            else {
                return nil
            }

            switch field.scalarType {
            case .string, .email, .uri, .integer, .number:
                return field.id
            case .date, .dateTime, .boolean:
                return nil
            }
        }

        if let rootSection = renderPlan.sections.first(where: {
            $0.pointer == "#" && !$0.isOwnedByArrayRow
        }) {
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

    func nextFocusableFieldID(after fieldID: String) -> String? {
        guard let currentIndex = orderedFocusableFieldIDs.firstIndex(of: fieldID) else {
            return nil
        }

        return orderedFocusableFieldIDs.dropFirst(currentIndex + 1).first
    }

    private static func makeDisplayBlocks(
        for section: FormKitRenderPlan.SectionDescriptor,
        fieldsByID: [String: FormKitFieldDescriptor],
        visibleChildSectionsByParentKey: [ParentSectionKey: [FormKitRenderPlan.SectionDescriptor]]
    ) -> [DisplayBlock] {
        let visibleFields: [FormKitFieldDescriptor] = section.fieldIDs.compactMap { fieldID in
            guard let field = fieldsByID[fieldID], field.isVisible else {
                return nil
            }
            return field
        }

        let directChildSections = visibleChildSectionsByParentKey[
            ParentSectionKey(
                pointer: section.pointer,
                ownerArrayRowID: section.ownerArrayRowID
            )
        ] ?? []

        let fieldsByPropertyKey = visibleFields.reduce(into: [String: String]()) { result, field in
            result[field.propertyKey] = field.id
        }
        let childSectionsByPropertyKey = directChildSections.reduce(into: [String: String]()) { result, childSection in
            guard let propertyKey = childSection.propertyKey else {
                return
            }
            result[propertyKey] = childSection.id
        }

        var rawBlocks: [DisplayBlock.Kind] = []
        var pendingFieldIDs: [String] = []
        var consumedFieldIDs = Set<String>()
        var consumedSectionIDs = Set<String>()

        func flushPendingFields() {
            guard !pendingFieldIDs.isEmpty else {
                return
            }
            rawBlocks.append(.fieldGroup(sectionID: section.id, fieldIDs: pendingFieldIDs))
            pendingFieldIDs.removeAll()
        }

        for propertyKey in section.propertyOrder {
            if let fieldID = fieldsByPropertyKey[propertyKey] {
                pendingFieldIDs.append(fieldID)
                consumedFieldIDs.insert(fieldID)
            }

            if let childSectionID = childSectionsByPropertyKey[propertyKey] {
                flushPendingFields()
                rawBlocks.append(.section(childSectionID))
                consumedSectionIDs.insert(childSectionID)
            }
        }

        let remainingFieldIDs = visibleFields
            .map(\.id)
            .filter { !consumedFieldIDs.contains($0) }
        pendingFieldIDs.append(contentsOf: remainingFieldIDs)
        flushPendingFields()

        let remainingSectionIDs = directChildSections
            .map(\.id)
            .filter { !consumedSectionIDs.contains($0) }
        rawBlocks.append(contentsOf: remainingSectionIDs.map(DisplayBlock.Kind.section))

        let fieldGroupIndices = rawBlocks.indices.filter {
            if case .fieldGroup = rawBlocks[$0] {
                return true
            }
            return false
        }

        return rawBlocks.enumerated().map { index, kind in
            DisplayBlock(
                kind: kind,
                showSectionHeader: fieldGroupIndices.first == index,
                showSectionFooter: fieldGroupIndices.last == index
            )
        }
    }

}
