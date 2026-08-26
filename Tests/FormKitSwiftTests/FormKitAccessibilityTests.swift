import XCTest
@testable import FormKitSwift

extension FormKitReviewRegressionTests {
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
}
