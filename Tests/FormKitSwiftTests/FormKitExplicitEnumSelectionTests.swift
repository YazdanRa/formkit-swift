import Foundation
import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitExplicitEnumSelectionTests: XCTestCase {
    func testRequiredZoneStaysAbsentAcrossUnrelatedEditAndReopen() throws {
        let renderer = FormKitRenderer(includesHiddenToolFields: true, requiresExplicitEnumSelection: true)
        let session = renderer.makeFormSession(
            schemaJSON: Self.workshopSchema,
            instanceJSON: #"{"checkout":{"operator_name":"Example operator"}}"#
        )
        let area = try field("#/checkout/zone", in: session)
        XCTAssertNil(session.selectedEnumChoiceID(for: area))
        XCTAssertFalse(session.validate())
        XCTAssertNil(try checkout(in: session)["zone"])

        session.setStringValue("Updated operator", for: try field("#/checkout/operator_name", in: session))
        XCTAssertNil(try checkout(in: session)["zone"])
        let reopened = renderer.makeFormSession(schemaJSON: Self.workshopSchema,
                                                instanceJSON: session.currentInstanceJSON)
        XCTAssertNil(reopened.selectedEnumChoiceID(for: try field(area.pointer, in: reopened)))
        XCTAssertFalse(reopened.validate())

        let currentArea = try field(area.pointer, in: reopened)
        let firstChoice = try XCTUnwrap(currentArea.enumOptions.first)
        reopened.setSelectedEnumChoiceID(firstChoice.id, for: currentArea)
        XCTAssertTrue(reopened.validate())
        XCTAssertEqual(try checkout(in: reopened)["zone"] as? String, "North")
        let cleared = reopened.applyToolEdits([.init(pointer: "/checkout/zone", operation: .clear)])
        XCTAssertEqual(cleared.appliedEdits.count, 1)
        XCTAssertNil(reopened.selectedEnumChoiceID(for: try field(area.pointer, in: reopened)))
        XCTAssertNil(try checkout(in: reopened)["zone"])
        XCTAssertFalse(reopened.validate())
    }

    func testDefaultRendererRetainsExistingRequiredChoiceFallback() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: Self.workshopSchema,
            instanceJSON: #"{"checkout":{"operator_name":"Example operator"}}"#
        )
        XCTAssertEqual(session.selectedEnumChoiceID(for: try field("#/checkout/zone", in: session)),
                       "string:North")
        XCTAssertTrue(session.validate())
    }

    func testExplicitDefaultsAndSuppliedValuesRemainSelected() throws {
        let renderer = FormKitRenderer(requiresExplicitEnumSelection: true)
        let schema = #"""
        {"type":"object","required":["area"],"properties":{
          "area":{"type":"string","enum":["North","South"],"default":"South"}
        }}
        """#
        let seeded = renderer.makeFormSession(schemaJSON: schema)
        XCTAssertEqual(seeded.selectedEnumChoiceID(for: try field("#/area", in: seeded)), "string:South")
        XCTAssertTrue(seeded.validate())

        let supplied = renderer.makeFormSession(schemaJSON: schema, instanceJSON: #"{"area":"North"}"#)
        XCTAssertEqual(supplied.selectedEnumChoiceID(for: try field("#/area", in: supplied)), "string:North")
        XCTAssertTrue(supplied.validate())
    }

    func testNullableEnumDoesNotAcquireAnImplicitNullSelection() throws {
        let renderer = FormKitRenderer(requiresExplicitEnumSelection: true)
        let schema = #"""
        {"type":"object","required":["area"],"properties":{
          "area":{"type":["string","null"],"enum":["North",null]}
        }}
        """#
        let session = renderer.makeFormSession(schemaJSON: schema)
        XCTAssertNil(session.selectedEnumChoiceID(for: try field("#/area", in: session)))
        XCTAssertFalse(session.validate())
        let supplied = renderer.makeFormSession(schemaJSON: schema, instanceJSON: #"{"area":null}"#)
        XCTAssertEqual(supplied.selectedEnumChoiceID(for: try field("#/area", in: supplied)), "null")
        XCTAssertTrue(supplied.validate())

        let defaultSchema = schema.replacingOccurrences(of: #""enum":["North",null]"#,
                                                        with: #""enum":["North",null],"default":null"#)
        let defaulted = renderer.makeFormSession(schemaJSON: defaultSchema)
        XCTAssertEqual(defaulted.primitiveValue(for: try field("#/area", in: defaulted)), .null)
        XCTAssertTrue(defaulted.validate())
    }

    func testConditionalRefreshAndSessionOverridesKeepExplicitSelectionPolicy() throws {
        let renderer = FormKitRenderer(includesHiddenToolFields: true, requiresExplicitEnumSelection: true)
        let schema = #"""
        {"type":"object","properties":{
          "enabled":{"type":"boolean"},
          "area":{"type":"string","enum":["North","South"]}
        },"allOf":[{
          "if":{"properties":{"enabled":{"const":true}},"required":["enabled"]},
          "then":{"required":["area"]}
        }]}
        """#
        let session = renderer.makeFormSession(schemaJSON: schema, instanceJSON: #"{"enabled":false}"#,
                                                defaultConditionalRenderBehavior: .disable)
        session.setBooleanValue(true, for: try field("#/enabled", in: session))
        let area = try field("#/area", in: session)
        XCTAssertTrue(area.isRequired)
        XCTAssertNil(session.selectedEnumChoiceID(for: area))
        XCTAssertFalse(session.validate())
        session.setSelectedEnumChoiceID(try XCTUnwrap(area.enumOptions.first?.id), for: area)
        XCTAssertTrue(session.validate())
        let reopened = renderer.makeFormSession(schemaJSON: schema, instanceJSON: session.currentInstanceJSON)
        XCTAssertEqual(reopened.selectedEnumChoiceID(for: try field("#/area", in: reopened)), "string:North")
    }

    func testNonEnumRequiredDefaultsRemainUnchanged() throws {
        let session = FormKitRenderer(requiresExplicitEnumSelection: true).makeFormSession(schemaJSON: #"""
        {"type":"object","required":["enabled","day"],"properties":{
          "enabled":{"type":"boolean"},"day":{"type":"string","format":"date"}
        }}
        """#)
        XCTAssertEqual(session.primitiveValue(for: try field("#/enabled", in: session)), .boolean(false))
        XCTAssertNotNil(session.primitiveValue(for: try field("#/day", in: session)))
        XCTAssertTrue(session.validate())
    }

    func testConstantValuesStayFixedWhileSingleChoiceEnumsRemainUnselected() throws {
        let session = FormKitRenderer(requiresExplicitEnumSelection: true).makeFormSession(schemaJSON: #"""
        {"type":"object","required":["constant","choice"],"properties":{
          "constant":{"type":"string","const":"Fixed"},
          "choice":{"type":"string","enum":["Only choice"]}
        }}
        """#)
        XCTAssertEqual(session.primitiveValue(for: try field("#/constant", in: session)), .string("Fixed"))
        XCTAssertNil(session.selectedEnumChoiceID(for: try field("#/choice", in: session)))
        XCTAssertFalse(session.validate())
    }

    private func field(_ pointer: String, in session: FormKitSession) throws -> FormKitFieldDescriptor {
        try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == pointer })
    }

    private func checkout(in session: FormKitSession) throws -> [String: Any] {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(session.currentInstanceJSON.utf8))
            as? [String: Any])
        return try XCTUnwrap(object["checkout"] as? [String: Any])
    }

    private static let workshopSchema = #"""
    {
      "type":"object", "required":["checkout"],
      "properties":{
        "checkout":{
          "type":"object", "title":"Equipment checkout", "required":["zone","operator_name"],
          "properties":{
            "zone":{"type":"string","title":"Workshop zone","enum":["North","South"],
              "x-formkit-ui-component":"line-options-choice"},
            "operator_name":{"type":"string","title":"Operator","minLength":1}
          }
        }
      }
    }
    """#
}
