import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitDynamicArrayToolContextTests: XCTestCase {
    func testParentFieldsFollowAuthoredOrderAndEscapedPointersWithOrWithoutRows() throws {
        let schema = #"""
        {"type":"object","properties":{
          "before":{"type":"string","x-formkit-order":0},
          "group":{"type":"object","x-formkit-order":1,"properties":{
            "first":{"type":"string","x-formkit-order":0},
            "equipment/~":{"type":"array","x-formkit-order":1,"items":{"type":"string"},
              "x-formkit-ui-component":"dynamic-options"},
            "last":{"type":"string","x-formkit-order":2}}},
          "after":{"type":"string","x-formkit-order":2}}}
        """#
        for ids in [[], ["saved"]] {
            let data = try JSONSerialization.data(withJSONObject: [
                "group": ["equipment/~": ids]
            ])
            let initial = try XCTUnwrap(String(data: data, encoding: .utf8))
            let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: initial)
            let before = session.currentInstanceJSON
            let pointer = "/group/equipment~1~0"
            XCTAssertEqual(session.makeToolContext().fields.map(\.pointer),
                           ["/before", "/group/first", pointer]
                               + ids.indices.map { pointer + "/\($0)" } + ["/group/last", "/after"])
            XCTAssertEqual(session.currentInstanceJSON, before)
            XCTAssertEqual(session.revision, 0)
            let result = session.applyToolEdits([.init(pointer: pointer, operation: .set,
                                                       value: .array([.string("asset/~:1")]))])
            XCTAssertTrue(result.rejectedEdits.isEmpty)
            let value = try JSONDecoder().decode(FormKitJSONValue.self, from: Data(session.currentInstanceJSON.utf8))
            XCTAssertEqual(value.object?["group"]?.object?["equipment/~"], .array([.string("asset/~:1")]))
        }
    }

    func testUnrelatedArrayReplacementPreservesDefaultAndConfirmedCollectionSources() throws {
        for defaults in [[], ["schema"]] {
            let schema: [String: Any] = ["type": "object", "properties": [
                "equipment": ["type": "array", "default": defaults, "items": ["type": "string"],
                              "x-formkit-ui-component": "dynamic-options"],
                "other": ["type": "array", "items": ["type": "string"]]
            ]]
            let data = try JSONSerialization.data(withJSONObject: schema)
            let schemaJSON = try XCTUnwrap(String(data: data, encoding: .utf8))
            let session = FormKitRenderer().makeFormSession(schemaJSON: schemaJSON)
            for confirmed in [false, true] {
                if confirmed {
                    _ = session.applyToolEdits([.init(pointer: "/equipment", operation: .set,
                                                       value: .array(defaults.map(FormKitJSONValue.string)))])
                }
                let other = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/other" })
                session.setArrayValue([.string("unrelated")], for: other)
                let context = session.makeToolContext()
                XCTAssertEqual(context.fields.first { $0.pointer == "/equipment" }?.valueSource,
                               confirmed ? .sessionEdit : .defaultValue)
                XCTAssertEqual(context.currentValues["/equipment"], .array(defaults.map(FormKitJSONValue.string)))
            }
        }
    }

    func testRequiredParentAndIndexedEntriesDoNotDuplicateCollectionSummary() {
        let schema = #"""
        {"type":"object","required":["equipment"],"properties":{
          "equipment":{"type":"array","title":"Equipment","minItems":1,"items":{"type":"string"},
            "x-formkit-ui-component":"dynamic-options"}}}
        """#
        for instance in [nil, #"{"equipment":[]}"#] as [String?] {
            let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: instance)
            XCTAssertEqual(session.makeToolContext().summary, "Missing required fields: Equipment.")
        }
    }
}
