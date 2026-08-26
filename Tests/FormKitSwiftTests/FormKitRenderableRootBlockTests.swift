import XCTest
@testable import FormKitSwift

extension FormKitViewTests {
    func testRenderableRootBlocksIncludeNestedObjectFields() {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: FormKitRenderableRootBlockFixtures.nestedObjectFields
        )
        let renderIndex = FormKitRenderIndex(renderPlan: session.renderPlan)
        let blocks = renderIndex.renderableRootBlocks

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(
            blocks.compactMap { block in
                guard case .fieldGroup(let sectionID, _) = block.kind else {
                    return nil
                }
                return renderIndex.section(sectionID)?.title
            },
            ["General Information", "Inspection Checks", "Weld Inspection"]
        )
        XCTAssertEqual(
            blocks.flatMap { block -> [String] in
                guard case .fieldGroup(_, let fieldIDs) = block.kind else {
                    return []
                }
                return fieldIDs.compactMap { renderIndex.field($0)?.propertyKey }
            },
            ["inspectorName", "noCracks", "disposition"]
        )
        guard let rootBlock = blocks.last,
              case .fieldGroup(let rootSectionID, let rootFieldIDs) = rootBlock.kind
        else {
            return XCTFail("Expected the root scalar field group last")
        }
        XCTAssertTrue(rootBlock.showSectionHeader)
        XCTAssertTrue(rootBlock.showSectionFooter)
        XCTAssertEqual(
            FormKitAccessibility.sectionIdentifier(
                rootSectionID,
                fieldIDs: rootFieldIDs,
                showsHeader: rootBlock.showSectionHeader
            ),
            rootSectionID
        )
    }

    func testRenderableRootBlocksPreserveContainerOnlyObjectSection() {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: FormKitRenderableRootBlockFixtures.containerOnlyObject
        )
        let renderIndex = FormKitRenderIndex(renderPlan: session.renderPlan)
        let blocks = renderIndex.renderableRootBlocks
        let rootID = session.renderPlan.sections.first { $0.pointer == "#" }?.id
        let containerID = session.renderPlan.sections.first { $0.propertyKey == "container" }?.id

        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(
            blocks.first?.kind,
            containerID.map { .fieldGroup(sectionID: $0, fieldIDs: []) }
        )
        XCTAssertEqual(blocks.first?.showSectionHeader, true)
        XCTAssertEqual(
            blocks[2].kind,
            containerID.map { .fieldGroup(sectionID: $0, fieldIDs: []) }
        )
        XCTAssertEqual(blocks[2].showSectionHeader, false)
        XCTAssertEqual(blocks[2].showSectionFooter, true)
        XCTAssertEqual(
            blocks.last?.kind,
            rootID.map { .fieldGroup(sectionID: $0, fieldIDs: []) }
        )
        XCTAssertEqual(blocks.last?.showSectionHeader, true)
        XCTAssertEqual(blocks.last?.showSectionFooter, true)
        XCTAssertNotEqual(blocks[0].id, blocks[2].id)
        guard case .fieldGroup(_, let fieldIDs) = blocks[1].kind else {
            return XCTFail("Expected the nested object's fields between the container boundaries")
        }
        XCTAssertEqual(fieldIDs.compactMap { renderIndex.field($0)?.propertyKey }, ["name"])
    }

    func testRenderableRootBlocksBoundMixedObjectContent() {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: FormKitRenderableRootBlockFixtures.mixedObjectContent
        )
        let renderIndex = FormKitRenderIndex(renderPlan: session.renderPlan)
        let blocks = renderIndex.renderableRootBlocks
        let containerID = session.renderPlan.sections.first { $0.propertyKey == "container" }?.id

        XCTAssertEqual(blocks.count, 6)
        XCTAssertEqual(blocks[0].id, containerID.map { "field_group:\($0):header" })
        XCTAssertEqual(blocks[4].id, containerID.map { "field_group:\($0):footer" })
        XCTAssertEqual(
            blocks.flatMap { block -> [String] in
                guard case .fieldGroup(_, let fieldIDs) = block.kind else {
                    return []
                }
                return fieldIDs.compactMap { renderIndex.field($0)?.propertyKey }
            },
            ["first", "middle", "last"]
        )
        let accessibilityIDs = blocks.compactMap { block -> String? in
            guard case .fieldGroup(let sectionID, let fieldIDs) = block.kind else {
                return nil
            }
            return FormKitAccessibility.sectionIdentifier(
                sectionID,
                fieldIDs: fieldIDs,
                showsHeader: block.showSectionHeader
            )
        }
        XCTAssertEqual(accessibilityIDs.first, containerID)
        XCTAssertEqual(Set(accessibilityIDs).count, accessibilityIDs.count)
        guard case .fieldGroup(_, let fieldIDs) = blocks[2].kind else {
            return XCTFail("Expected the container's scalar field between its child objects")
        }
        XCTAssertEqual(fieldIDs.compactMap { renderIndex.field($0)?.propertyKey }, ["middle"])
        XCTAssertFalse(blocks[2].showSectionHeader)
        XCTAssertFalse(blocks[2].showSectionFooter)
    }

    func testRenderableRootBlocksPlaceRootFooterAfterTrailingObject() {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: FormKitRenderableRootBlockFixtures.trailingObject
        )
        let renderIndex = FormKitRenderIndex(renderPlan: session.renderPlan)
        let blocks = renderIndex.renderableRootBlocks
        let rootID = session.renderPlan.sections.first { $0.pointer == "#" }?.id

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(
            blocks.flatMap { block -> [String] in
                guard case .fieldGroup(_, let fieldIDs) = block.kind else {
                    return []
                }
                return fieldIDs.compactMap { renderIndex.field($0)?.propertyKey }
            },
            ["first", "last"]
        )
        XCTAssertEqual(blocks.first?.showSectionHeader, true)
        XCTAssertEqual(blocks.first?.showSectionFooter, false)
        XCTAssertEqual(
            blocks.last?.kind,
            rootID.map { .fieldGroup(sectionID: $0, fieldIDs: []) }
        )
        XCTAssertEqual(blocks.last?.showSectionHeader, false)
        XCTAssertEqual(blocks.last?.showSectionFooter, true)
    }
}

private enum FormKitRenderableRootBlockFixtures {
    static let nestedObjectFields =
        """
        {
          "title": "Weld Inspection",
          "type": "object",
          "properties": {
            "generalInformation": {
              "title": "General Information",
              "type": "object",
              "properties": { "inspectorName": { "title": "Inspector Name", "type": "string" } }
            },
            "inspectionChecks": {
              "title": "Inspection Checks",
              "type": "object",
              "properties": {
                "noCracks": { "title": "No Cracks", "type": "string", "enum": ["Pass", "Fail", "N/A"] }
              }
            },
            "disposition": { "title": "Disposition", "type": "string", "enum": ["Accept", "Reject"] }
          }
        }
        """

    static let containerOnlyObject =
        """
        {
          "title": "Root",
          "description": "Root description",
          "type": "object",
          "properties": {
            "container": {
              "title": "Container",
              "description": "Container description",
              "type": "object",
              "properties": {
                "nested": {
                  "title": "Nested",
                  "type": "object",
                  "properties": { "name": { "title": "Name", "type": "string" } }
                }
              }
            }
          }
        }
        """

    static let mixedObjectContent =
        """
        {
          "type": "object",
          "properties": {
            "container": {
              "title": "Container",
              "description": "Container description",
              "type": "object",
              "properties": {
                "leading": {
                  "title": "Leading",
                  "type": "object",
                  "properties": { "first": { "type": "string" } }
                },
                "middle": { "type": "string" },
                "trailing": {
                  "title": "Trailing",
                  "type": "object",
                  "properties": { "last": { "type": "string" } }
                }
              }
            }
          }
        }
        """

    static let trailingObject =
        """
        {
          "title": "Root",
          "description": "Root description",
          "type": "object",
          "properties": {
            "first": { "type": "string" },
            "trailing": {
              "type": "object",
              "properties": { "last": { "type": "string" } }
            }
          }
        }
        """
}
