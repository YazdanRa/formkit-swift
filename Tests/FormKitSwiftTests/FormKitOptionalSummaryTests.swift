import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitOptionalSummaryTests: XCTestCase {
    func testOptionalConditionalFollowUpDoesNotBecomeRequiredInSummary() throws {
        let session = FormKitRenderer(includesHiddenToolFields: true).makeFormSession(
            schemaJSON: #"""
            {
              "type": "object", "x-formkit-layout": "section-pages",
              "properties": {
                "first": {
                  "type": "object",
                  "properties": {
                    "enabled": {"type": "boolean"},
                    "optionalNote": {"type": "string"},
                    "requiredNote": {"type": "string"}
                  },
                  "allOf": [{
                    "if": {"properties": {"enabled": {"const": true}}, "required": ["enabled"]},
                    "then": {
                      "properties": {"optionalNote": {"type": "string"}},
                      "required": ["requiredNote"]
                    }
                  }]
                },
                "second": {"type": "object", "properties": {"other": {"type": "string"}}}
              }
            }
            """#,
            instanceJSON: #"{"first":{"enabled":true}}"#
        )
        XCTAssertTrue(session.renderPlan.isSupported)
        XCTAssertFalse(try field("#/first/optionalNote", in: session).isRequired)
        XCTAssertEqual(session.formSummary().missingRequired.map(\.id), ["#/first/requiredNote"])

        session.setStringValue("Required response", for: try field("#/first/requiredNote", in: session))

        XCTAssertTrue(session.validate())
        XCTAssertTrue(session.formSummary().missingRequired.isEmpty)
        XCTAssertEqual(session.formSummary().pages.first?.status, .done)
    }

    private func field(_ id: String, in session: FormKitSession) throws -> FormKitFieldDescriptor {
        try XCTUnwrap(session.renderPlan.fields.first { $0.id == id })
    }
}
