import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitTextAreaTests: XCTestCase {
    func testTextAreaHintPreservesMultilineNarrativeAcrossEditsAndReopen() throws {
        let schema = #"""
        {
          "type":"object", "required":["description"],
          "properties":{
            "description":{"type":"string","x-formkit-ui-component":"text-area","maxLength":2000},
            "worker":{"type":"string"}
          }
        }
        """#
        let narrative = "First line: a detailed observation with punctuation, spaces and an unchanged native value.\n"
            + "Second line: " + String(repeating: "The access route requires review. ", count: 12)
        let session = FormKitRenderer().makeFormSession(schemaJSON: schema)
        let description = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "description" })
        XCTAssertEqual(description.uiComponent, .textArea)
        XCTAssertEqual(FormKitUIComponent.textArea.rawValue, "text-area")
        session.setStringValue(narrative, for: description)
        let worker = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "worker" })
        session.setStringValue("Synthetic worker", for: worker)
        XCTAssertTrue(session.validate())

        let reopened = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: session.currentInstanceJSON)
        let reopenedDescription = try XCTUnwrap(reopened.renderPlan.fields.first { $0.propertyKey == "description" })
        XCTAssertEqual(reopened.stringValue(for: reopenedDescription), narrative)
        XCTAssertTrue(reopened.validate())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(reopened.currentInstanceJSON.utf8))
            as? [String: Any])
        XCTAssertEqual(json["description"] as? String, narrative)
    }
}
