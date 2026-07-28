import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitArrayMutationTests: XCTestCase {
    func testRemovingEditedRowDoesNotReuseItsValue() throws {
        let schema =
            """
            {
              "type": "object",
              "properties": {
                "tags": {
                  "type": "array",
                  "title": "Tags",
                  "items": { "type": "string" }
                }
              }
            }
            """
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: schema,
            instanceJSON: #"{"tags":["Electrical","Weekend"]}"#
        )
        let section = try XCTUnwrap(session.renderPlan.sections.first { $0.title == "Tags" })
        let firstRow = try XCTUnwrap(section.arrayDescriptor?.rows.first)
        let firstFieldID = try XCTUnwrap(firstRow.fieldIDs.first)
        let firstField = try XCTUnwrap(session.renderPlan.fields.first { $0.id == firstFieldID })

        session.setStringValue("Updated", for: firstField)
        session.removeArrayRow(firstRow, from: section)

        let updatedSection = try XCTUnwrap(session.renderPlan.sections.first { $0.id == section.id })
        let remainingFieldID = try XCTUnwrap(updatedSection.arrayDescriptor?.rows.first?.fieldIDs.first)
        let remainingField = try XCTUnwrap(session.renderPlan.fields.first { $0.id == remainingFieldID })
        XCTAssertEqual(session.stringValue(for: remainingField), "Weekend")
    }
}
