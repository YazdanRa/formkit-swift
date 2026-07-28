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
        XCTAssertNil(FormKitFocusSupport.normalizedFieldID("#/missing", focusableFieldIDs: focusableFieldIDs))
        XCTAssertNil(FormKitFocusSupport.normalizedFieldID(nil, focusableFieldIDs: focusableFieldIDs))

        let readOnlyFieldIDs = FormKitFocusSupport.resolvedComponents(
            session: session,
            options: .init(mode: .readOnly)
        ).focusableFieldIDs
        XCTAssertTrue(readOnlyFieldIDs.isEmpty)
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
        let renderIndex = FormKitRenderIndex(renderPlan: session.renderPlan)
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
    }

    func testChangedFieldStateHasNonvisualAccessibilityValue() {
        XCTAssertEqual(FormKitFieldVisualState.changed.formKitAccessibilityValue, "Changed")
        XCTAssertEqual(FormKitFieldVisualState.normal.formKitAccessibilityValue, "")
        XCTAssertEqual(FormKitFieldVisualState.locked.formKitAccessibilityValue, "")
    }
}
