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
