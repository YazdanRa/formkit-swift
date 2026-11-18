import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitExplicitEnumArrayTests: XCTestCase {
    func testGeneratedScalarEnumArrayPlaceholdersKeepTheirExistingContract() throws {
        for itemSchema in [
            #"{"type":"string","enum":["North","South"]}"#,
            #"{"type":["string","null"],"enum":["North",null]}"#,
            #"{"type":"string","const":"Fixed"}"#
        ] {
            let schema = """
            {"type":"object","properties":{
              "choices":{"type":"array","minItems":1,"items":\(itemSchema)}
            }}
            """
            let legacy = FormKitRenderer().makeFormSession(schemaJSON: schema)
            let explicit = FormKitRenderer(requiresExplicitEnumSelection: true).makeFormSession(schemaJSON: schema)
            let legacyField = try XCTUnwrap(legacy.renderPlan.fields.first { $0.pointer == "#/choices/0" })
            let explicitField = try XCTUnwrap(explicit.renderPlan.fields.first { $0.pointer == "#/choices/0" })
            XCTAssertEqual(explicit.currentInstanceJSON, legacy.currentInstanceJSON)
            XCTAssertEqual(explicit.selectedEnumChoiceID(for: explicitField),
                           legacy.selectedEnumChoiceID(for: legacyField))
            XCTAssertTrue(legacy.validate())
            XCTAssertTrue(explicit.validate())
            let array = try XCTUnwrap(explicit.renderPlan.sections.first { $0.pointer == "#/choices" })
            explicit.appendArrayRow(to: array)
            let legacyArray = try XCTUnwrap(legacy.renderPlan.sections.first { $0.pointer == "#/choices" })
            legacy.appendArrayRow(to: legacyArray)
            XCTAssertEqual(explicit.currentInstanceJSON, legacy.currentInstanceJSON)
            XCTAssertEqual(explicit.renderPlan.fields.count, 2)
        }
    }

    func testMissingEnumFieldsInsideObjectArrayRowsStillRequireSelection() throws {
        let session = FormKitRenderer(requiresExplicitEnumSelection: true).makeFormSession(schemaJSON: #"""
        {"type":"object","properties":{
          "rows":{"type":"array","minItems":1,"items":{
            "type":"object","required":["area"],"properties":{
              "area":{"type":"string","enum":["North","South"]}
            }
          }}
        }}
        """#)
        let area = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/rows/0/area" })
        XCTAssertNil(session.selectedEnumChoiceID(for: area))
        XCTAssertFalse(session.currentInstanceJSON.contains("North"))
        XCTAssertFalse(session.validate())
        session.setSelectedEnumChoiceID(try XCTUnwrap(area.enumOptions.first?.id), for: area)
        XCTAssertTrue(session.validate())
        XCTAssertTrue(session.currentInstanceJSON.contains("North"))
    }
}
