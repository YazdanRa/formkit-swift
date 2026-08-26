extension FormKitRenderIndex {
    static func visibleChildSectionsByParentKey(
        in sections: [FormKitRenderPlan.SectionDescriptor]
    ) -> [ParentSectionKey: [FormKitRenderPlan.SectionDescriptor]] {
        Dictionary(
            grouping: sections.filter {
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
    }

    static func makeDisplayBlocks(
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
        let rawBlocks = makeRawDisplayBlocks(
            for: section,
            visibleFields: visibleFields,
            directChildSections: directChildSections
        )
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

    private static func makeRawDisplayBlocks(
        for section: FormKitRenderPlan.SectionDescriptor,
        visibleFields: [FormKitFieldDescriptor],
        directChildSections: [FormKitRenderPlan.SectionDescriptor]
    ) -> [FormKitDisplayBlockKind] {
        let fieldsByPropertyKey = visibleFields.reduce(into: [String: String]()) { result, field in
            result[field.propertyKey] = field.id
        }
        let childSectionsByPropertyKey = directChildSections.reduce(into: [String: String]()) { result, childSection in
            guard let propertyKey = childSection.propertyKey else {
                return
            }
            result[propertyKey] = childSection.id
        }

        var blocks: [FormKitDisplayBlockKind] = []
        var pendingFieldIDs: [String] = []
        var consumedFieldIDs = Set<String>()
        var consumedSectionIDs = Set<String>()

        func flushPendingFields() {
            guard !pendingFieldIDs.isEmpty else {
                return
            }
            blocks.append(.fieldGroup(sectionID: section.id, fieldIDs: pendingFieldIDs))
            pendingFieldIDs.removeAll()
        }

        for propertyKey in section.propertyOrder {
            if let fieldID = fieldsByPropertyKey[propertyKey] {
                pendingFieldIDs.append(fieldID)
                consumedFieldIDs.insert(fieldID)
            }

            if let childSectionID = childSectionsByPropertyKey[propertyKey] {
                flushPendingFields()
                blocks.append(.section(childSectionID))
                consumedSectionIDs.insert(childSectionID)
            }
        }

        pendingFieldIDs.append(contentsOf: visibleFields
            .map(\.id)
            .filter { !consumedFieldIDs.contains($0) })
        flushPendingFields()

        let remainingSectionIDs = directChildSections
            .map(\.id)
            .filter { !consumedSectionIDs.contains($0) }
        blocks.append(contentsOf: remainingSectionIDs.map(FormKitDisplayBlockKind.section))
        return blocks
    }

    static func expandingObjectSections(
        in blocks: [DisplayBlock],
        sectionsByID: [String: FormKitRenderPlan.SectionDescriptor],
        displayBlocksBySectionID: [String: [DisplayBlock]]
    ) -> [DisplayBlock] {
        blocks.flatMap { block in
            guard case .section(let sectionID) = block.kind,
                  let section = sectionsByID[sectionID],
                  section.arrayDescriptor == nil
            else {
                return [block]
            }

            let childBlocks = displayBlocksBySectionID[sectionID] ?? []
            let showsHeaderInContent = childBlocks.first?.showSectionHeader == true
            let showsFooterInContent = childBlocks.last?.showSectionFooter == true
            let contentBlocks = childBlocks.map { childBlock in
                DisplayBlock(
                    kind: childBlock.kind,
                    showSectionHeader: childBlock.showSectionHeader && showsHeaderInContent,
                    showSectionFooter: childBlock.showSectionFooter && showsFooterInContent
                )
            }
            let expandedChildBlocks = expandingObjectSections(
                in: contentBlocks,
                sectionsByID: sectionsByID,
                displayBlocksBySectionID: displayBlocksBySectionID
            )

            let headerBlocks = showsHeaderInContent ? [] : [
                DisplayBlock(
                    kind: .fieldGroup(sectionID: sectionID, fieldIDs: []),
                    showSectionHeader: true,
                    showSectionFooter: false
                ),
            ]
            let footerBlocks = showsFooterInContent ? [] : [
                DisplayBlock(
                    kind: .fieldGroup(sectionID: sectionID, fieldIDs: []),
                    showSectionHeader: false,
                    showSectionFooter: true
                ),
            ]

            return headerBlocks + expandedChildBlocks + footerBlocks
        }
    }

    static func expandingRootObjectSection(
        _ sectionID: String,
        blocks: [DisplayBlock],
        sectionsByID: [String: FormKitRenderPlan.SectionDescriptor],
        displayBlocksBySectionID: [String: [DisplayBlock]]
    ) -> [DisplayBlock] {
        let hasFieldGroup = blocks.contains { block in
            if case .fieldGroup = block.kind {
                return true
            }
            return false
        }
        let showsFooterInContent = blocks.last?.showSectionFooter == true
        let contentBlocks = blocks.map { block in
            DisplayBlock(
                kind: block.kind,
                showSectionHeader: block.showSectionHeader,
                showSectionFooter: block.showSectionFooter && showsFooterInContent
            )
        }
        let expandedChildBlocks = expandingObjectSections(
            in: contentBlocks,
            sectionsByID: sectionsByID,
            displayBlocksBySectionID: displayBlocksBySectionID
        )

        guard !showsFooterInContent else {
            return expandedChildBlocks
        }

        return expandedChildBlocks + [
            DisplayBlock(
                kind: .fieldGroup(sectionID: sectionID, fieldIDs: []),
                showSectionHeader: !hasFieldGroup,
                showSectionFooter: true
            ),
        ]
    }
}
