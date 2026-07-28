import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitSessionMutationTests: XCTestCase {
    func testSectionReplacementDiscardsTouchedDescendantValues() throws {
        let session = makeSession(instanceJSON: #"{"attachments":["first","second"]}"#)
        let section = try XCTUnwrap(session.renderPlan.sections.first { $0.propertyKey == "attachments" })
        let secondField = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/attachments/1" })
        session.setStringValue("edited", for: secondField)

        session.setArrayValue(
            [.string("replacement-1"), .string("replacement-2")],
            for: section
        )

        let currentSection = try XCTUnwrap(
            session.renderPlan.sections.first { $0.id == section.id }
        )
        XCTAssertEqual(
            session.arrayValue(for: currentSection),
            [.string("replacement-1"), .string("replacement-2")]
        )
    }

    func testStaleSectionCannotReplaceCurrentValue() throws {
        let session = makeSession(instanceJSON: nil)
        let staleSection = try XCTUnwrap(
            session.renderPlan.sections.first { $0.propertyKey == "attachments" }
        )
        session.setArrayValue([.string("current")], for: staleSection)

        session.setArrayValue([.string("stale")], for: staleSection)

        let currentSection = try XCTUnwrap(
            session.renderPlan.sections.first { $0.id == staleSection.id }
        )
        XCTAssertEqual(session.arrayValue(for: currentSection), [.string("current")])
    }

    func testClearingAbsentNestedArrayDoesNotMaterializeItsParent() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "profile": {
                  "type": "object",
                  "properties": {
                    "attachments": {
                      "type": "array",
                      "items": { "type": "string" }
                    }
                  }
                }
              }
            }
            """,
            instanceJSON: nil
        )
        let section = try XCTUnwrap(
            session.renderPlan.sections.first { $0.propertyKey == "attachments" }
        )

        session.setArrayValue(nil, for: section)

        let data = try XCTUnwrap(session.currentInstanceJSON.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["profile"])
    }

    func testSectionReplacementClearsDescendantValidationErrors() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "attachments": {
                  "type": "array",
                  "items": {
                    "type": "string",
                    "minLength": 3
                  }
                }
              }
            }
            """,
            instanceJSON: #"{"attachments":["x"]}"#,
            validationBehavior: .onDemandOnly
        )
        let section = try XCTUnwrap(
            session.renderPlan.sections.first { $0.propertyKey == "attachments" }
        )
        let fieldID = try XCTUnwrap(section.arrayDescriptor?.rows.first?.fieldIDs.first)
        XCTAssertFalse(session.validate())
        XCTAssertFalse(session.fieldErrors[fieldID, default: []].isEmpty)

        session.setArrayValue([.string("valid")], for: section)

        XCTAssertNil(session.fieldErrors[fieldID])
    }

    func testNullableNumbersPreserveAbsenceAndNull() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {"type":"object","properties":{
              "count":{"type":["integer","null"]},
              "amount":{"type":["number","null"]},
              "requiredCount":{"type":["integer","null"]},
              "requiredAmount":{"type":["number","null"]},
              "defaultedAmount":{"type":["number","null"],"default":2.5}
            },"required":["requiredCount","requiredAmount"]}
            """,
            instanceJSON: nil
        )
        let countField = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "count" })
        let amountField = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "amount" })
        let requiredCount = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "requiredCount" })
        let requiredAmount = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "requiredAmount" })
        let defaultedAmount = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "defaultedAmount" })

        typealias PrimitiveValue = FormKitFieldDescriptor.PrimitiveValue
        let optionalFields = [countField, amountField]
        let inputs = ["42", "3.5"]
        let parsedValues: [PrimitiveValue] = [.integer(42), .number(3.5)]
        let zeroValues: [PrimitiveValue] = [.integer(0), .number(0)]
        for index in optionalFields.indices {
            let field = optionalFields[index]
            XCTAssertNil(session.primitiveValue(for: field))
            session.setStringValue(inputs[index], for: field)
            XCTAssertEqual(session.primitiveValue(for: field), parsedValues[index])
            session.setStringValue(" \t", for: field)
            XCTAssertEqual(session.primitiveValue(for: field), .null)
            session.unsetValue(for: field)
            XCTAssertNil(session.primitiveValue(for: field))
            session.setNullSelection(false, for: field)
            XCTAssertEqual(session.primitiveValue(for: field), zeroValues[index])
        }

        let requiredFields = [requiredCount, requiredAmount]
        for index in requiredFields.indices {
            let field = requiredFields[index]
            XCTAssertEqual(session.primitiveValue(for: field), .null)
            session.unsetValue(for: field)
            XCTAssertEqual(session.primitiveValue(for: field), .null)
            session.setNullSelection(false, for: field)
            XCTAssertEqual(session.primitiveValue(for: field), zeroValues[index])
        }

        session.setNullSelection(true, for: defaultedAmount)
        session.setNullSelection(false, for: defaultedAmount)
        XCTAssertEqual(session.primitiveValue(for: defaultedAmount), .number(2.5))
    }

    func testEmptyTextNormalizesAcrossNullableScalarTypes() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "text": { "type": ["string", "null"] },
                "email": { "type": ["string", "null"], "format": "email" },
                "uri": { "type": ["string", "null"], "format": "uri" },
                "date": { "type": ["string", "null"], "format": "date" },
                "time": { "type": ["string", "null"], "format": "time" },
                "dateTime": { "type": ["string", "null"], "format": "date-time" },
                "integer": { "type": ["integer", "null"] },
                "number": { "type": ["number", "null"] }
              }
            }
            """,
            instanceJSON: nil
        )

        for propertyKey in ["text", "email", "uri", "date", "time", "dateTime", "integer", "number"] {
            let field = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == propertyKey })
            session.setStringValue(" \n\t", for: field)
            XCTAssertEqual(session.primitiveValue(for: field), .null)
        }
    }

    func testBooleanStringsRoundTripCanonically() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: #"{"type":"object","properties":{"enabled":{"type":"boolean"}}}"#,
            instanceJSON: #"{"enabled":true}"#
        )
        let field = try XCTUnwrap(
            session.renderPlan.fields.first { $0.propertyKey == "enabled" }
        )

        XCTAssertEqual(session.stringValue(for: field), "true")
        session.setStringValue("false", for: field)
        XCTAssertEqual(session.primitiveValue(for: field), .boolean(false))
        XCTAssertEqual(session.stringValue(for: field), "false")
    }

    func testToolEmptyValuesUseCanonicalRepresentation() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "nullable": { "type": ["string", "null"] },
                "blank": { "type": "string" }
              }
            }
            """,
            instanceJSON: #"{"nullable":"value","blank":"value"}"#
        )

        let result = session.applyToolEdits([
            FormKitToolEdit(pointer: "/nullable", operation: .set, value: .string("")),
            FormKitToolEdit(pointer: "/blank", operation: .clear)
        ])

        XCTAssertEqual(result.appliedEdits.map(\.value), [.null, nil])
        XCTAssertEqual(result.context.currentValues["/nullable"], .null)
        XCTAssertEqual(result.context.currentValues["/blank"], .string(""))

        let repeatedClear = session.applyToolEdits([
            FormKitToolEdit(pointer: "/blank", operation: .clear)
        ])
        XCTAssertEqual(repeatedClear.rejectedEdits.map(\.reason), ["no_change"])
    }
}

extension FormKitSessionMutationTests {
    func testToolClearHandlesSchemaAuthoredBlankEnumValues() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "blank": { "type": "string", "enum": ["", "value"] },
                "nullable": {
                  "type": ["string", "null"],
                  "enum": ["", "value", null],
                  "default": ""
                },
                "whitespace": {
                  "type": ["string", "null"],
                  "enum": [" ", "value", null]
                },
                "undeclaredBlank": {
                  "type": ["string", "null"],
                  "enum": ["value", null]
                }
              }
            }
            """,
            instanceJSON: #"{"blank":"","whitespace":" ","undeclaredBlank":""}"#
        )
        let blankField = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "blank" })
        let nullableField = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "nullable" })
        let whitespaceField = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "whitespace" })
        let undeclaredField = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "undeclaredBlank" })

        XCTAssertEqual(session.primitiveValue(for: blankField), .string(""))
        XCTAssertEqual(session.primitiveValue(for: nullableField), .string(""))
        XCTAssertEqual(session.primitiveValue(for: whitespaceField), .string(" "))
        XCTAssertEqual(session.primitiveValue(for: undeclaredField), .null)

        let edits = [
            FormKitToolEdit(pointer: "/blank", operation: .clear),
            FormKitToolEdit(pointer: "/nullable", operation: .clear),
            FormKitToolEdit(pointer: "/whitespace", operation: .clear)
        ]
        let result = session.applyToolEdits(edits)
        let object = try Self.decodeJSONObject(session.currentInstanceJSON)

        XCTAssertEqual(result.appliedEdits.map(\.pointer), ["/blank", "/nullable", "/whitespace"])
        XCTAssertNil(object["blank"])
        XCTAssertTrue(object["nullable"] is NSNull)
        XCTAssertTrue(object["whitespace"] is NSNull)
        XCTAssertEqual(
            session.applyToolEdits(edits).rejectedEdits.map(\.reason),
            ["no_change", "no_change", "no_change"]
        )
    }

    private func makeSession(instanceJSON: String?) -> FormKitSession {
        FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "attachments": {
                  "type": "array",
                  "items": {
                    "type": "string"
                  }
                }
              }
            }
            """,
            instanceJSON: instanceJSON
        )
    }

    private static func decodeJSONObject(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
