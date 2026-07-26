import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitReviewRegressionTests: XCTestCase {
    func testUploadURLsAreTrimmedAndBlankURLsAreRejected() {
        XCTAssertEqual("  https://example.com/file.pdf \n".formKitNonEmpty, "https://example.com/file.pdf")
        XCTAssertNil(" \n\t".formKitNonEmpty)
    }

    func testLegacyRendererConformanceUsesNewOverrideOverload() {
        let renderer: any FormKitRendering = LegacyFormKitRenderer()

        let session = renderer.makeFormSession(
            schemaJSON: #"{"type":"object"}"#,
            instanceJSON: nil,
            defaultConditionalRenderBehavior: nil,
            conditionalRenderBehaviorOverrides: [:],
            validationBehavior: .revalidateAfterFirstAttempt
        )

        XCTAssertTrue(session.renderPlan.isSupported)
    }

    func testOwnedSessionConfigurationRebuildsWhenSchemaChanges() {
        let firstConfiguration = FormKitOwnedSessionConfiguration(
            schemaJSON: Self.schema(title: "First", fieldName: "first"),
            instanceJSON: nil,
            defaultConditionalRenderBehavior: .hide,
            validationBehavior: .revalidateAfterFirstAttempt
        )
        let secondConfiguration = FormKitOwnedSessionConfiguration(
            schemaJSON: Self.schema(title: "Second", fieldName: "second"),
            instanceJSON: nil,
            defaultConditionalRenderBehavior: .hide,
            validationBehavior: .revalidateAfterFirstAttempt
        )

        XCTAssertNotEqual(firstConfiguration, secondConfiguration)
        XCTAssertEqual(firstConfiguration.makeSession().renderPlan.title, "First")
        XCTAssertEqual(secondConfiguration.makeSession().renderPlan.title, "Second")
    }

    func testOwnedSessionConfigurationRebuildsWhenRenderBehaviorOverridesChange() throws {
        let baseConfiguration = FormKitOwnedSessionConfiguration(
            schemaJSON: Self.conditionalSchema,
            instanceJSON: nil,
            defaultConditionalRenderBehavior: .hide,
            validationBehavior: .revalidateAfterFirstAttempt
        )
        let overrideConfiguration = FormKitOwnedSessionConfiguration(
            schemaJSON: Self.conditionalSchema,
            instanceJSON: nil,
            defaultConditionalRenderBehavior: .hide,
            conditionalRenderBehaviorOverrides: ["#/advancedNotes": .ignore],
            validationBehavior: .revalidateAfterFirstAttempt
        )

        XCTAssertNotEqual(baseConfiguration, overrideConfiguration)
        XCTAssertNil(field(named: "advancedNotes", in: baseConfiguration.makeSession()))

        let advancedNotesField = try XCTUnwrap(
            field(named: "advancedNotes", in: overrideConfiguration.makeSession())
        )
        XCTAssertTrue(advancedNotesField.isConditionallyInactive)
        XCTAssertTrue(advancedNotesField.shouldSerialize)
    }

    func testToolClearRemovesBooleanValues() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "enabled": {
                  "type": "boolean",
                  "title": "Enabled"
                }
              }
            }
            """,
            instanceJSON: #"{"enabled":true}"#
        )

        let result = session.applyToolEdits([
            FormKitToolEdit(pointer: "/enabled", operation: .clear)
        ])

        XCTAssertEqual(result.appliedEdits.map(\.pointer), ["/enabled"])
        let object = try Self.decodeJSONObject(session.currentInstanceJSON)
        XCTAssertNil(object["enabled"])
    }

    func testToolClearIsIdempotentForNullableFields() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "note": {
                  "type": ["string", "null"]
                },
                "priority": {
                  "type": ["string", "null"],
                  "enum": ["low", "high", null]
                }
              }
            }
            """,
            instanceJSON: #"{"note":"Review","priority":"high"}"#
        )
        let edits = [
            FormKitToolEdit(pointer: "/note", operation: .clear),
            FormKitToolEdit(pointer: "/priority", operation: .clear)
        ]

        let firstResult = session.applyToolEdits(edits)
        let secondResult = session.applyToolEdits(edits)

        XCTAssertEqual(firstResult.revision, 2)
        XCTAssertEqual(firstResult.appliedEdits.map(\.pointer), ["/note", "/priority"])
        XCTAssertEqual(secondResult.revision, 2)
        XCTAssertTrue(secondResult.appliedEdits.isEmpty)
        XCTAssertEqual(secondResult.rejectedEdits.map(\.reason), ["no_change", "no_change"])
    }

    func testRenderedFieldIdentifiersUseFullPointer() {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "name": {
                  "type": "string",
                  "title": "Name"
                },
                "contact": {
                  "type": "object",
                  "title": "Contact",
                  "properties": {
                    "name": {
                      "type": "string",
                      "title": "Name"
                    }
                  }
                }
              }
            }
            """,
            instanceJSON: nil
        )

        let identifiers = session.renderPlan.fields.map(FormKitAccessibility.fieldIdentifier)

        XCTAssertEqual(identifiers.count, 2)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertTrue(identifiers.contains("json_form_field_name"))
        XCTAssertTrue(identifiers.contains("json_form_field_contact_name"))
    }

    private static func schema(title: String, fieldName: String) -> String {
        """
        {
          "title": "\(title)",
          "type": "object",
          "properties": {
            "\(fieldName)": {
              "type": "string",
              "title": "\(fieldName)"
            }
          }
        }
        """
    }

    private static let conditionalSchema =
        """
        {
          "title": "Conditional Notes",
          "type": "object",
          "properties": {
            "mode": {
              "title": "Mode",
              "enum": ["basic", "advanced"],
              "default": "basic"
            }
          },
          "required": ["mode"],
          "if": {
            "properties": {
              "mode": { "const": "advanced" }
            },
            "required": ["mode"]
          },
          "then": {
            "properties": {
              "advancedNotes": {
                "type": "string",
                "title": "Advanced Notes"
              }
            }
          }
        }
        """

    private func field(
        named propertyKey: String,
        in session: FormKitSession
    ) -> FormKitFieldDescriptor? {
        session.renderPlan.fields.first(where: { $0.propertyKey == propertyKey })
    }

    private static func decodeJSONObject(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}

@MainActor
private struct LegacyFormKitRenderer: FormKitRendering {
    func makeFormSession(
        schemaJSON: String,
        instanceJSON: String?,
        defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior?,
        validationBehavior: FormKitValidationBehavior
    ) -> FormKitSession {
        FormKitRenderer().makeFormSession(
            schemaJSON: schemaJSON,
            instanceJSON: instanceJSON,
            defaultConditionalRenderBehavior: defaultConditionalRenderBehavior,
            validationBehavior: validationBehavior
        )
    }
}
