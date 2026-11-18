import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitDynamicCanonicalValueTests: XCTestCase {
    func testNonnullableObjectRowClearChangesWireImmediatelyInNormalAndHiddenModes() throws {
        for hiddenTools in [false, true] {
            for component in ["dynamic-options", ""] {
                for key in ["choice", "slash/key", "tilde~key"] {
                    let encodedKey = try XCTUnwrap(String(data: JSONEncoder().encode(key), encoding: .utf8))
                    let definition = rowSchema.replacingOccurrences(of: "COMPONENT", with: component)
                        .replacingOccurrences(of: "\"choice\"", with: encodedKey)
                    let data = try JSONSerialization.data(withJSONObject: ["rows": [[key: "saved"]]])
                    let renderer = FormKitRenderer(includesHiddenToolFields: hiddenTools)
                    let session = renderer.makeFormSession(schemaJSON: definition,
                        instanceJSON: try XCTUnwrap(String(data: data, encoding: .utf8)))
                    let token = key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
                    let clear = session.applyToolEdits([.init(pointer: "/rows/0/\(token)", operation: .clear)])
                    XCTAssertTrue(clear.rejectedEdits.isEmpty)
                    XCTAssertEqual(try rowChoice(session, key: key) as? String, component.isEmpty ? "" : nil)
                    let note = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/note" })
                    session.setStringValue("Unrelated", for: note)
                    XCTAssertEqual(try rowChoice(session, key: key) as? String, component.isEmpty ? "" : nil)
                    let reopened = renderer.makeFormSession(schemaJSON: definition,
                        instanceJSON: session.currentInstanceJSON)
                    XCTAssertEqual(try rowChoice(reopened, key: key) as? String, component.isEmpty ? "" : nil)
                }
            }
        }
    }

    func testCompatibleStringArrayDefaultsWinItemDefaultsWithoutChangingDefaultMetadata() throws {
        for id in ["A", "", "  "] {
            for itemDefault in [nil, "B"] {
                let definition = try arraySchema(values: [.string(id)], itemDefault: itemDefault)
                let session = FormKitRenderer().makeFormSession(schemaJSON: definition)
                let field = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/equipment/0" })
                XCTAssertEqual(try object(session)["equipment"] as? [String], [id])
                XCTAssertEqual(session.primitiveValue(for: field), .string(id))
                XCTAssertEqual(field.defaultValue, itemDefault.map(FormKitFieldDescriptor.PrimitiveValue.string))
                XCTAssertEqual(session.makeToolContext().currentValues["/equipment/0"], .string(id))
                XCTAssertEqual(session.toolValueSource(for: field), .defaultValue)
                XCTAssertFalse(session.hasAnswer(for: field))
                let other = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/other" })
                session.setArrayValue([.string("unrelated")], for: other)
                XCTAssertEqual(try object(session)["equipment"] as? [String], [id])
                let reopened = FormKitRenderer().makeFormSession(schemaJSON: definition,
                                                                instanceJSON: session.currentInstanceJSON)
                XCTAssertEqual(reopened.makeToolContext().currentValues["/equipment/0"], .string(id))
                XCTAssertTrue(reopened.validate())
            }
        }
        let ordinary = FormKitRenderer().makeFormSession(
            schemaJSON: try arraySchema(values: [.string("A")], itemDefault: "B", component: "")
        )
        XCTAssertEqual(try object(ordinary)["equipment"] as? [String], ["B"])
    }

    func testObjectArrayDefaultFieldsWinItemDefaultsOnlyForCompatibleScalarMarkers() throws {
        for value in [FormKitJSONValue.string("A"), .string(""), .string("  "), .null] {
            let raw = try XCTUnwrap(String(data: JSONEncoder().encode(value), encoding: .utf8))
            let definition = #"""
            {"type":"object","properties":{"rows":{"type":"array","default":[{"choice":VALUE}],
              "items":{"type":"object","properties":{"choice":{"type":["string","null"],"default":"B",
              "x-formkit-ui-component":"dynamic-options"}}}}}}
            """#.replacingOccurrences(of: "VALUE", with: raw)
            let session = FormKitRenderer().makeFormSession(schemaJSON: definition)
            XCTAssertEqual(session.makeToolContext().currentValues["/rows/0/choice"], value)
            let field = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/rows/0/choice" })
            XCTAssertEqual(field.defaultValue, .string("B"))
            XCTAssertEqual(session.toolValueSource(for: field), .defaultValue)
            let reopened = FormKitRenderer().makeFormSession(schemaJSON: definition,
                                                            instanceJSON: session.currentInstanceJSON)
            XCTAssertEqual(reopened.makeToolContext().currentValues["/rows/0/choice"], value)
        }
    }

    func testInvalidRawArrayDefaultDoesNotFallThroughToAValidItemDefault() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: try arraySchema(values: [.integer(7)], itemDefault: "B")
        )
        XCTAssertEqual(try object(session)["equipment"] as? [Int], [7])
        XCTAssertNil(session.makeToolContext().currentValues["/equipment/0"])
        XCTAssertFalse(session.validate())
    }

    func testOwnMarkedScalarArrayItemToolClearKeepsTheExistingPositionalStringContract() throws {
        let definition = #"""
        {"type":"object","properties":{"items":{"type":"array","items":{"type":"string",
          "x-formkit-ui-component":"dynamic-options"}}}}
        """#
        let session = FormKitRenderer().makeFormSession(schemaJSON: definition, instanceJSON: #"{"items":["saved"]}"#)
        let result = session.applyToolEdits([.init(pointer: "/items/0", operation: .clear)])
        XCTAssertTrue(result.rejectedEdits.isEmpty)
        XCTAssertEqual(try object(session)["items"] as? [String], [""])
        let unchanged = session.applyToolEdits([.init(pointer: "/items/0", operation: .clear)])
        XCTAssertEqual(unchanged.rejectedEdits.first?.reason, "no_change")
    }

    private func object(_ session: FormKitSession) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(session.currentInstanceJSON.utf8)) as? [String: Any])
    }

    private func rowChoice(_ session: FormKitSession, key: String = "choice") throws -> Any? {
        let rows = try XCTUnwrap(try object(session)["rows"] as? [[String: Any]])
        return rows.first?[key]
    }

    private func arraySchema(values: [FormKitJSONValue], itemDefault: String?,
                             component: String = "dynamic-options") throws -> String
    {
        let raw = try XCTUnwrap(String(data: JSONEncoder().encode(FormKitJSONValue.array(values)), encoding: .utf8))
        let item = try itemDefault.map { value in
            let data = try JSONEncoder().encode(FormKitJSONValue.string(value))
            return ",\"default\":" + (try XCTUnwrap(String(data: data, encoding: .utf8)))
        } ?? ""
        return """
        {"type":"object","properties":{
          "equipment":{"type":"array","minItems":1,"default":\(raw),"x-formkit-ui-component":"\(component)",
            "items":{"type":"string"\(item)}},"other":{"type":"array","items":{"type":"string"}}
        }}
        """
    }

    private var rowSchema: String {
        #"""
        {"type":"object","properties":{"note":{"type":"string"},"rows":{"type":"array","items":{
          "type":"object","properties":{"choice":{"type":"string","x-formkit-ui-component":"COMPONENT"}}}}}}
        """#
    }
}
