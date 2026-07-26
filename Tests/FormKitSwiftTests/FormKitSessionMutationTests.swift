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
            session.setStringValue("", for: field)
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
}
