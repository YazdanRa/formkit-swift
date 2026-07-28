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

        XCTAssertEqual(
            FormKitFocusSupport.normalizedFieldID(name.id, in: session.renderPlan, isEditingLocked: false),
            name.id
        )
        XCTAssertNil(FormKitFocusSupport.normalizedFieldID(choice.id, in: session.renderPlan, isEditingLocked: false))
        XCTAssertNil(FormKitFocusSupport.normalizedFieldID(enabled.id, in: session.renderPlan, isEditingLocked: false))
        XCTAssertNil(FormKitFocusSupport.normalizedFieldID(file.id, in: session.renderPlan, isEditingLocked: false))
        XCTAssertNil(FormKitFocusSupport.normalizedFieldID(name.id, in: session.renderPlan, isEditingLocked: true))
        XCTAssertNil(FormKitFocusSupport.normalizedFieldID("#/missing", in: session.renderPlan, isEditingLocked: false))
        XCTAssertNil(FormKitFocusSupport.normalizedFieldID(nil, in: session.renderPlan, isEditingLocked: false))
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
            FormKitFocusSupport.normalizedFieldID(note.id, in: session.renderPlan, isEditingLocked: false),
            note.id
        )

        session.removeArrayRow(row, from: section)

        XCTAssertNil(
            FormKitFocusSupport.normalizedFieldID(note.id, in: session.renderPlan, isEditingLocked: false)
        )
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
