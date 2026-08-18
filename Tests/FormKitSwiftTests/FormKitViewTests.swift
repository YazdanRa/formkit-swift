import SwiftUI
import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitViewTests: XCTestCase {
    func testControlledViewInitializersRemainSourceCompatible() {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: #"{"type":"object"}"#,
            instanceJSON: nil
        )
        var focusedFieldID: String?
        let focus = Binding(
            get: { focusedFieldID },
            set: { focusedFieldID = $0 }
        )

        _ = FormKitView(session: session)
        _ = FormKitView(session: session, focusedFieldID: focus)
    }

    func testControlledFocusAcceptsOnlyInteractiveStockTextFields() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "name": { "type": "string" },
                "choice": { "type": "string", "enum": ["A", "B"] },
                "enabled": { "type": "boolean" },
                "file": {
                  "type": "string",
                  "format": "uri",
                  "x-formkit-ui-component": "file-field"
                },
                "fallback": {
                  "type": "string",
                  "x-formkit-ui-component": "rating"
                }
              }
            }
            """,
            instanceJSON: nil
        )
        let field = { name in
            session.renderPlan.fields.first(where: { $0.propertyKey == name })
        }
        let name = try XCTUnwrap(field("name"))
        let choice = try XCTUnwrap(field("choice"))
        let enabled = try XCTUnwrap(field("enabled"))
        let file = try XCTUnwrap(field("file"))
        let fallback = try XCTUnwrap(field("fallback"))
        let focusableFieldIDs = FormKitFocusSupport.resolvedComponents(
            session: session,
            options: .init()
        ).focusableFieldIDs

        XCTAssertEqual(
            FormKitFocusSupport.normalizedFieldID(name.id, focusableFieldIDs: focusableFieldIDs),
            name.id
        )
        XCTAssertNil(FormKitFocusSupport.normalizedFieldID(choice.id, focusableFieldIDs: focusableFieldIDs))
        XCTAssertNil(FormKitFocusSupport.normalizedFieldID(enabled.id, focusableFieldIDs: focusableFieldIDs))
        XCTAssertNil(FormKitFocusSupport.normalizedFieldID(file.id, focusableFieldIDs: focusableFieldIDs))
        XCTAssertEqual(
            FormKitFocusSupport.normalizedFieldID(fallback.id, focusableFieldIDs: focusableFieldIDs),
            fallback.id
        )
        XCTAssertNil(FormKitFocusSupport.normalizedFieldID("#/missing", focusableFieldIDs: focusableFieldIDs))
        XCTAssertNil(FormKitFocusSupport.normalizedFieldID(nil, focusableFieldIDs: focusableFieldIDs))

        let readOnlyFieldIDs = FormKitFocusSupport.resolvedComponents(
            session: session,
            options: .init(mode: .readOnly)
        ).focusableFieldIDs
        XCTAssertTrue(readOnlyFieldIDs.isEmpty)
    }

    func testTemporalFormatsUseNativePickerRenderingPath() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "date": { "type": "string", "format": "date" },
                "time": { "type": "string", "format": "time" },
                "dateTime": { "type": "string", "format": "date-time" }
              }
            }
            """,
            instanceJSON: nil
        )
        let fields = Dictionary(
            uniqueKeysWithValues: session.renderPlan.fields.map { ($0.propertyKey, $0) }
        )
        let focusableFieldIDs = FormKitFocusSupport.resolvedComponents(
            session: session,
            options: .init()
        ).focusableFieldIDs

        XCTAssertEqual(fields["date"]?.scalarType, .date)
        XCTAssertEqual(fields["time"]?.scalarType, .time)
        XCTAssertEqual(fields["dateTime"]?.scalarType, .dateTime)
        XCTAssertEqual(fields["date"]?.scalarType.datePickerComponents, .date)
        XCTAssertEqual(fields["time"]?.scalarType.datePickerComponents, .hourAndMinute)
        XCTAssertEqual(fields["dateTime"]?.scalarType.datePickerComponents, [.date, .hourAndMinute])
        XCTAssertTrue(fields.values.allSatisfy { !focusableFieldIDs.contains($0.id) })
    }

    func testFocusTraversalSkipsEnumsAndCustomComponents() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "name": { "type": "string" },
                "choice": { "type": "string", "enum": ["A", "B"] },
                "file": {
                  "type": "string",
                  "format": "uri",
                  "x-formkit-ui-component": "file-field"
                },
                "count": { "type": "integer" }
              }
            }
            """,
            instanceJSON: nil
        )
        let renderIndex = FormKitRenderIndex(
            renderPlan: session.renderPlan,
            focusableFieldIDs: FormKitFocusSupport.resolvedComponents(
                session: session,
                options: .init()
            ).focusableFieldIDs
        )
        let name = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "name" })
        let count = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "count" })

        XCTAssertEqual(renderIndex.nextFocusableFieldID(after: name.id), count.id)
        XCTAssertNil(renderIndex.nextFocusableFieldID(after: count.id))
    }

    func testRemovedArrayFieldCannotRemainFocused() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "items": {
                  "type": "array",
                  "items": { "type": "string" }
                }
              }
            }
            """,
            instanceJSON: #"{"items":["Draft"]}"#
        )
        let renderIndex = FormKitRenderIndex(renderPlan: session.renderPlan)
        let section = try XCTUnwrap(session.renderPlan.sections.first { $0.propertyKey == "items" })
        let row = try XCTUnwrap(section.arrayDescriptor?.rows.first)
        let note = try XCTUnwrap(renderIndex.firstFocusableField(in: row))

        XCTAssertEqual(
            FormKitFocusSupport.normalizedFieldID(
                note.id,
                focusableFieldIDs: FormKitFocusSupport.resolvedComponents(
                    session: session,
                    options: .init()
                ).focusableFieldIDs
            ),
            note.id
        )

        session.removeArrayRow(row, from: section)

        XCTAssertNil(
            FormKitFocusSupport.normalizedFieldID(
                note.id,
                focusableFieldIDs: FormKitFocusSupport.resolvedComponents(
                    session: session,
                    options: .init()
                ).focusableFieldIDs
            )
        )
    }

    func testHostFieldOverridesAreExcludedFromControlledFocus() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: #"{"type":"object","properties":{"name":{"type":"string"},"city":{"type":"string"}}}"#,
            instanceJSON: nil
        )
        let name = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "name" })
        let city = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "city" })
        var invocationCount = 0
        let options = FormKitOptions(
            components: FormKitComponents(
                fieldInput: { context in
                    invocationCount += 1
                    return context.field.id == name.id ? AnyView(Text("Custom")) : nil
                }
            )
        )
        let components = FormKitFocusSupport.resolvedComponents(session: session, options: options)
        let focusableFieldIDs = components.focusableFieldIDs

        XCTAssertEqual(invocationCount, 2)
        XCTAssertFalse(focusableFieldIDs.contains(name.id))
        XCTAssertTrue(focusableFieldIDs.contains(city.id))
        XCTAssertNotNil(components.fieldInputs[name.id])
        let renderIndex = FormKitRenderIndex(
            renderPlan: session.renderPlan,
            focusableFieldIDs: focusableFieldIDs
        )
        XCTAssertEqual(renderIndex.firstFocusableField(in: .init(
            id: "row",
            pointer: "#",
            index: 0,
            title: "Row",
            placeholderValue: .null,
            fieldIDs: [name.id, city.id],
            sectionIDs: []
        ))?.id, city.id)
        XCTAssertNil(renderIndex.nextFocusableFieldID(after: city.id))
    }

    func testFocusEligibilityTracksDynamicStateAndOverrides() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: #"{"type":"object","properties":{"name":{"type":"string"}}}"#,
            instanceJSON: nil
        )
        let name = try XCTUnwrap(session.renderPlan.fields.first)

        XCTAssertTrue(
            FormKitFocusSupport.resolvedComponents(session: session, options: .init())
                .focusableFieldIDs.contains(name.id)
        )

        XCTAssertFalse(
            FormKitFocusSupport.resolvedComponents(
                session: session,
                options: .init(fieldState: { _ in .locked })
            )
                .focusableFieldIDs.contains(name.id)
        )

        XCTAssertFalse(
            FormKitFocusSupport.resolvedComponents(
                session: session,
                options: .init(
                    components: FormKitComponents(
                        fieldInput: { _ in AnyView(Text("Custom")) }
                    )
                )
            )
                .focusableFieldIDs.contains(name.id)
        )
    }

    func testArraySectionOverridesExcludeUnmountedDescendantsFromFocusResolution() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "notes": { "type": "array", "items": { "type": "string" } },
                "city": { "type": "string" }
              }
            }
            """,
            instanceJSON: #"{"notes":["First"]}"#
        )
        let section = try XCTUnwrap(session.renderPlan.sections.first { $0.propertyKey == "notes" })
        let noteID = try XCTUnwrap(section.arrayDescriptor?.rows.first?.fieldIDs.first)
        let city = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "city" })
        var resolvedInputIDs: [String] = []
        let options = FormKitOptions(
            components: FormKitComponents(
                fieldInput: { context in
                    resolvedInputIDs.append(context.field.id)
                    return nil
                },
                arraySection: { _ in AnyView(Text("Custom array")) }
            )
        )

        let components = FormKitFocusSupport.resolvedComponents(session: session, options: options)

        XCTAssertNotNil(components.arraySections[section.id])
        XCTAssertFalse(components.focusableFieldIDs.contains(noteID))
        XCTAssertTrue(components.focusableFieldIDs.contains(city.id))
        XCTAssertFalse(resolvedInputIDs.contains(noteID))
    }

    func testStockTextInputTraitsFollowScalarType() {
        XCTAssertEqual(FormKitTextInputTraits(scalarType: .string), .standard)
        XCTAssertEqual(FormKitTextInputTraits(scalarType: .email), .email)
        XCTAssertEqual(FormKitTextInputTraits(scalarType: .uri), .url)
        XCTAssertEqual(FormKitTextInputTraits(scalarType: .integer), .integer)
        XCTAssertEqual(FormKitTextInputTraits(scalarType: .number), .decimal)
        XCTAssertTrue(FormKitTextInputTraits.standard.supportsVerticalExpansion)
        XCTAssertTrue(FormKitTextInputTraits.email.supportsVerticalExpansion)
        XCTAssertTrue(FormKitTextInputTraits.url.supportsVerticalExpansion)
        XCTAssertFalse(FormKitTextInputTraits.integer.supportsVerticalExpansion)
        XCTAssertFalse(FormKitTextInputTraits.decimal.supportsVerticalExpansion)
    }

    func testChangedFieldStateHasNonvisualAccessibilityValue() {
        XCTAssertEqual(FormKitFieldVisualState.changed.formKitAccessibilityValue, "Changed")
        XCTAssertEqual(FormKitFieldVisualState.normal.formKitAccessibilityValue, "")
        XCTAssertEqual(FormKitFieldVisualState.locked.formKitAccessibilityValue, "")
    }
}

extension FormKitViewTests {
    func testRenderableRootBlocksIncludeNestedObjectFields() {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
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
            schemaJSON: """
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
            schemaJSON: """
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
            schemaJSON: """
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
