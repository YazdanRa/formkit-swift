import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitDynamicOpaqueIDToolTests: XCTestCase {
    func testToolSetAndClearPreserveLiteralIDUntilExplicitClear() throws {
        for nullable in [false, true] {
            for required in [false, true] {
                for id in ["", "  ", "normal"] {
                    let definition = schema(nullable: nullable, required: required)
                    let session = FormKitRenderer().makeFormSession(schemaJSON: definition)
                    let set = session.applyToolEdits([.init(pointer: "/choice", operation: .set, value: .string(id))])
                    XCTAssertTrue(set.rejectedEdits.isEmpty)
                    XCTAssertEqual(set.appliedEdits.first?.value, .string(id))
                    XCTAssertEqual(session.makeToolContext().currentValues["/choice"], .string(id))
                    XCTAssertEqual(try object(session)["choice"] as? String, id)
                    XCTAssertTrue(session.validate())
                    let cleared = session.applyToolEdits([.init(pointer: "/choice", operation: .clear)])
                    XCTAssertTrue(cleared.rejectedEdits.isEmpty)
                    if nullable {
                        XCTAssertTrue(try object(session)["choice"] is NSNull)
                        XCTAssertTrue(session.validate())
                    } else {
                        XCTAssertNil(try object(session)["choice"])
                        XCTAssertEqual(session.validate(), !required)
                    }
                    let reopened = FormKitRenderer().makeFormSession(schemaJSON: definition,
                                                                    instanceJSON: session.currentInstanceJSON)
                    XCTAssertEqual(reopened.validate(), nullable || !required)
                }
            }
        }
    }

    func testClearingActuallyAbsentOptionalScalarKeepsExistingNoChangeOutcome() {
        let session = FormKitRenderer().makeFormSession(schemaJSON: schema(nullable: false, required: false))
        let revision = session.revision
        let result = session.applyToolEdits([.init(pointer: "/choice", operation: .clear)])
        XCTAssertTrue(result.appliedEdits.isEmpty)
        XCTAssertEqual(result.rejectedEdits.first?.reason, "no_change")
        XCTAssertEqual(session.revision, revision)
    }

    func testOrdinaryRequiredTextStillTreatsBlankAsMissingAndUsesExistingClearBehavior() throws {
        let definition = schema(nullable: false, required: true)
            .replacingOccurrences(of: "dynamic-options", with: "")
        let session = FormKitRenderer().makeFormSession(schemaJSON: definition, instanceJSON: #"{"choice":""}"#)
        XCTAssertFalse(session.validate())
        XCTAssertTrue(session.makeToolContext().summary.contains("Missing required"))
        _ = session.applyToolEdits([.init(pointer: "/choice", operation: .set, value: .string("normal"))])
        let clear = session.applyToolEdits([.init(pointer: "/choice", operation: .clear)])
        XCTAssertTrue(clear.rejectedEdits.isEmpty)
        XCTAssertEqual(try object(session)["choice"] as? String, "")
        XCTAssertFalse(session.validate())
    }

    func testBlankDynamicScalarDefaultsAndInitialProvenanceSurviveObjectArrayEdits() throws {
        let definition = #"""
        {"type":"object","properties":{"rows":{"type":"array","minItems":1,"items":{
          "type":"object","properties":{"choice":{"type":["string","null"],"default":"",
          "x-formkit-ui-component":"dynamic-options"}}}}}}
        """#
        let defaulted = FormKitRenderer().makeFormSession(schemaJSON: definition)
        XCTAssertEqual(defaulted.makeToolContext().currentValues["/rows/0/choice"], .string(""))
        let section = try XCTUnwrap(defaulted.renderPlan.sections.first { $0.pointer == "#/rows" })
        defaulted.appendArrayRow(to: section)
        XCTAssertEqual(defaulted.makeToolContext().currentValues["/rows/1/choice"], .string(""))
        XCTAssertEqual(defaulted.makeToolContext().fields.first { $0.pointer == "/rows/1/choice" }?.valueSource,
                       .defaultValue)

        let initial = FormKitRenderer().makeFormSession(
            schemaJSON: definition, instanceJSON: #"{"rows":[{"choice":"first"},{"choice":"  "}]}"#
        )
        let original = try XCTUnwrap(initial.renderPlan.sections.first { $0.pointer == "#/rows" })
        let first = try XCTUnwrap(original.arrayDescriptor?.rows.first)
        initial.removeArrayRow(first, from: original)
        XCTAssertEqual(initial.makeToolContext().currentValues["/rows/0/choice"], .string("  "))
        XCTAssertEqual(initial.makeToolContext().fields.first { $0.pointer == "/rows/0/choice" }?.valueSource,
                       .initialInstance)
    }

    func testPresentSavedAndChosenBlankIDsAndNullSurviveOtherObjectRowRemoval() throws {
        let definition = #"""
        {"type":"object","properties":{"rows":{"type":"array","minItems":1,"items":{
          "type":"object","properties":{"choice":{"type":["string","null"],"default":"fallback",
          "x-formkit-ui-component":"dynamic-options"}}}}}}
        """#
        for value in [FormKitJSONValue.string(""), .string("  "), .null] {
            for chosen in [false, true] {
                for removedIndex in [0, 1] {
                    let keptIndex = 1 - removedIndex
                    var rows = Array(repeating: FormKitJSONValue.object(["choice": .string("other")]), count: 2)
                    if !chosen {
                        rows[keptIndex] = .object(["choice": value])
                    }
                    let data = try JSONEncoder().encode(FormKitJSONValue.object(["rows": .array(rows)]))
                    let renderer = FormKitRenderer(includesHiddenToolFields: true)
                    let session = renderer.makeFormSession(
                        schemaJSON: definition, instanceJSON: try XCTUnwrap(String(data: data, encoding: .utf8))
                    )
                    if chosen {
                        let field = try XCTUnwrap(session.renderPlan.fields.first {
                            $0.pointer == "#/rows/\(keptIndex)/choice"
                        })
                        if case .string(let id) = value {
                            session.setStringValue(id, for: field)
                        } else {
                            session.setNullSelection(true, for: field)
                        }
                    }
                    let section = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/rows" })
                    let row = try XCTUnwrap(section.arrayDescriptor?.rows[removedIndex])
                    session.removeArrayRow(row, from: section)
                    XCTAssertEqual(session.makeToolContext().currentValues["/rows/0/choice"], value)
                    let reopened = renderer.makeFormSession(schemaJSON: definition,
                                                           instanceJSON: session.currentInstanceJSON)
                    XCTAssertEqual(reopened.makeToolContext().currentValues["/rows/0/choice"], value)
                    XCTAssertTrue(reopened.validate())
                }
            }
        }
    }

    private func object(_ session: FormKitSession) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(session.currentInstanceJSON.utf8)) as? [String: Any])
    }

    private func schema(nullable: Bool, required: Bool) -> String {
        """
        {"type":"object","required":\(required ? "[\"choice\"]" : "[]"),"properties":{
          "choice":{"type":\(nullable ? "[\"string\",\"null\"]" : "\"string\""),
            "x-formkit-ui-component":"dynamic-options"}
        }}
        """
    }
}
