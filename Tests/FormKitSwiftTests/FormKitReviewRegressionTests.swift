import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitReviewRegressionTests: XCTestCase {
    func testNullableSeedingPreservesOptionalAbsence() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "optional": { "type": ["string", "null"] },
                "required": { "type": ["string", "null"] },
                "defaulted": {
                  "type": ["string", "null"],
                  "default": "fallback"
                },
                "explicit": { "type": ["string", "null"] }
              },
              "required": ["required"]
            }
            """,
            instanceJSON: #"{"explicit":null}"#
        )

        var object = try Self.decodeJSONObject(session.currentInstanceJSON)
        XCTAssertNil(object["optional"])
        XCTAssertTrue(object["required"] is NSNull)
        XCTAssertEqual(object["defaulted"] as? String, "fallback")
        XCTAssertTrue(object["explicit"] is NSNull)

        let optionalField = try XCTUnwrap(field(named: "optional", in: session))
        session.setStringValue("", for: optionalField)
        XCTAssertTrue(try Self.decodeJSONObject(session.currentInstanceJSON)["optional"] is NSNull)
        session.setNullSelection(true, for: optionalField)
        XCTAssertTrue(try Self.decodeJSONObject(session.currentInstanceJSON)["optional"] is NSNull)
        session.unsetValue(for: optionalField)
        XCTAssertNil(try Self.decodeJSONObject(session.currentInstanceJSON)["optional"])

        let requiredField = try XCTUnwrap(field(named: "required", in: session))
        session.setNullSelection(false, for: requiredField)
        XCTAssertTrue(session.isConcreteValuePending(for: requiredField))
        object = try Self.decodeJSONObject(session.currentInstanceJSON)
        XCTAssertTrue(object["required"] is NSNull)
        session.setStringValue("entered", for: requiredField)
        XCTAssertFalse(session.isConcreteValuePending(for: requiredField))
        XCTAssertEqual(try Self.decodeJSONObject(session.currentInstanceJSON)["required"] as? String, "entered")
    }

    func testOptionalNullableEnumKeepsAbsenceDistinctFromNull() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "choice": {
                  "type": ["string", "null"],
                  "enum": ["A", null]
                }
              }
            }
            """,
            instanceJSON: nil
        )
        let field = try XCTUnwrap(field(named: "choice", in: session))
        let nullChoice = try XCTUnwrap(field.enumOptions.first { $0.value == .null })

        XCTAssertNil(session.selectedEnumChoiceID(for: field))
        XCTAssertNil(try Self.decodeJSONObject(session.currentInstanceJSON)["choice"])

        session.setSelectedEnumChoiceID(nullChoice.id, for: field)
        XCTAssertTrue(try Self.decodeJSONObject(session.currentInstanceJSON)["choice"] is NSNull)

        session.setSelectedEnumChoiceID(nil, for: field)
        XCTAssertNil(try Self.decodeJSONObject(session.currentInstanceJSON)["choice"])
    }

    func testOptionalNullableBooleanCanReturnToAbsence() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "optional": { "type": ["boolean", "null"] },
                "required": { "type": ["boolean", "null"] }
              },
              "required": ["required"]
            }
            """,
            instanceJSON: nil
        )
        let optionalField = try XCTUnwrap(field(named: "optional", in: session))
        let requiredField = try XCTUnwrap(field(named: "required", in: session))

        var object = try Self.decodeJSONObject(session.currentInstanceJSON)
        XCTAssertNil(object["optional"])
        XCTAssertTrue(object["required"] is NSNull)

        session.setBooleanValue(true, for: optionalField)
        XCTAssertEqual(try Self.decodeJSONObject(session.currentInstanceJSON)["optional"] as? Bool, true)

        session.setNullSelection(true, for: optionalField)
        XCTAssertTrue(try Self.decodeJSONObject(session.currentInstanceJSON)["optional"] is NSNull)

        session.setBooleanValue(false, for: optionalField)
        session.unsetValue(for: optionalField)
        XCTAssertNil(try Self.decodeJSONObject(session.currentInstanceJSON)["optional"])

        session.setBooleanValue(false, for: requiredField)
        session.unsetValue(for: requiredField)
        object = try Self.decodeJSONObject(session.currentInstanceJSON)
        XCTAssertEqual(object["required"] as? Bool, false)

        session.setNullSelection(true, for: requiredField)
        XCTAssertTrue(try Self.decodeJSONObject(session.currentInstanceJSON)["required"] is NSNull)
    }

    func testOptionalNullableDatesCanReturnToAbsence() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "birthday": { "type": ["string", "null"], "format": "date" },
                "appointment": { "type": ["string", "null"], "format": "date-time" },
                "requiredDate": { "type": ["string", "null"], "format": "date" }
              },
              "required": ["requiredDate"]
            }
            """,
            instanceJSON: nil
        )
        let fields = try ["birthday", "appointment"].map {
            try XCTUnwrap(field(named: $0, in: session))
        }

        for field in fields {
            XCTAssertNil(try Self.decodeJSONObject(session.currentInstanceJSON)[field.propertyKey])

            session.setDateValue(Date(timeIntervalSince1970: 0), for: field)
            XCTAssertNotNil(try Self.decodeJSONObject(session.currentInstanceJSON)[field.propertyKey] as? String)

            session.setNullSelection(true, for: field)
            XCTAssertTrue(try Self.decodeJSONObject(session.currentInstanceJSON)[field.propertyKey] is NSNull)

            session.unsetValue(for: field)
            XCTAssertNil(try Self.decodeJSONObject(session.currentInstanceJSON)[field.propertyKey])
        }

        let requiredField = try XCTUnwrap(field(named: "requiredDate", in: session))
        XCTAssertTrue(try Self.decodeJSONObject(session.currentInstanceJSON)["requiredDate"] is NSNull)

        session.setDateValue(Date(timeIntervalSince1970: 0), for: requiredField)
        session.unsetValue(for: requiredField)
        XCTAssertNotNil(try Self.decodeJSONObject(session.currentInstanceJSON)["requiredDate"] as? String)

        session.setNullSelection(true, for: requiredField)
        XCTAssertTrue(try Self.decodeJSONObject(session.currentInstanceJSON)["requiredDate"] is NSNull)
    }

    func testMultipleFileUploadsReplaceVacantNullAndInvalidValues() {
        for invalidValue in [FormKitJSONValue.null, .number(42)] {
            XCTAssertEqual(FormKitMultipleFileField.occupiedValueCount(in: [invalidValue]), 0)
            XCTAssertEqual(
                FormKitMultipleFileField.replacingVacancies(
                    in: [invalidValue],
                    with: [.string("https://example.com/replacement.pdf")],
                    maxItems: 1
                ),
                [.string("https://example.com/replacement.pdf")]
            )
        }
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
