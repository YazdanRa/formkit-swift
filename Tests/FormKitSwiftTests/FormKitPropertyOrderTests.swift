import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitPropertyOrderTests: XCTestCase {
    func testFormKitOrderOverridesSourceOrderAndUsesItForFallbacks() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "title": "Ordering",
              "type": "object",
              "properties": {
                "unannotated": { "type": "string" },
                "third": { "type": "string", "x-formkit-order": 3 },
                "first": { "type": "string", "x-formkit-order": 1 },
                "alsoThird": { "type": "string", "x-formkit-order": 3 },
                "largerExact": { "type": "string", "x-formkit-order": 9007199254740993 },
                "smallerExact": { "type": "string", "x-formkit-order": 9007199254740992 },
                "huge": { "type": "string", "x-formkit-order": 1e100 },
                "fractional": { "type": "string", "x-formkit-order": 1.5 },
                "invalid": { "type": "string", "x-formkit-order": "last" }
              }
            }
            """,
            instanceJSON: nil
        )

        let expectedOrder = [
            "first", "third", "alsoThird", "smallerExact", "largerExact",
            "unannotated", "huge", "fractional", "invalid"
        ]
        XCTAssertEqual(session.renderPlan.fields.map(\.propertyKey), expectedOrder)
        XCTAssertEqual(session.renderPlan.fieldOrder, expectedOrder.map { "#/\($0)" })
        XCTAssertEqual(
            session.renderPlan.sections.first(where: { $0.title == "Ordering" })?.propertyOrder,
            expectedOrder
        )
    }
}
