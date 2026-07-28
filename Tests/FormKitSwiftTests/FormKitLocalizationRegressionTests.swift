import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitLocalizationRegressionTests: XCTestCase {
    func testBooleanStringValuesRemainCanonical() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: #"{"type":"object","properties":{"enabled":{"type":"boolean"}}}"#,
            instanceJSON: #"{"enabled":true}"#
        )
        let field = try XCTUnwrap(
            session.renderPlan.fields.first { $0.propertyKey == "enabled" }
        )

        if ProcessInfo.processInfo.environment["FORMKIT_ASSERT_FRENCH"] == "1" {
            XCTAssertEqual(String(localized: "true", bundle: .module), "vrai")
        }
        XCTAssertEqual(session.stringValue(for: field), "true")
        session.setStringValue(session.stringValue(for: field), for: field)
        XCTAssertTrue(session.booleanValue(for: field))

        session.setStringValue("false", for: field)
        XCTAssertEqual(session.stringValue(for: field), "false")
        session.setStringValue(session.stringValue(for: field), for: field)
        XCTAssertFalse(session.booleanValue(for: field))
    }
}
