import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitDynamicArrayToolTests: XCTestCase {
    func testParentContextRepresentsMissingEmptyAndPopulatedCollectionsWithoutWriting() throws {
        for ids in [nil, [], ["", "  ", "saved"]] as [[String]?] {
            let form = FormKitRenderer().makeFormSession(
                schemaJSON: try schema(), instanceJSON: try ids.map { try instanceJSON($0) }
            )
            let before = form.currentInstanceJSON
            let revision = form.revision
            let context = form.makeToolContext()
            let parents = context.fields.filter { $0.pointer == "/equipment" }
            XCTAssertEqual(parents.count, 1)
            XCTAssertEqual(parents.first?.type, "array")
            let indexed = context.fields.filter { $0.pointer.hasPrefix("/equipment/") }.map(\.pointer)
            XCTAssertEqual(indexed, ids?.indices.map { "/equipment/\($0)" } ?? [])
            for (index, id) in (ids ?? []).enumerated() {
                XCTAssertEqual(context.currentValues["/equipment/\(index)"], .string(id))
            }
            XCTAssertEqual(context.currentValues["/equipment"], ids.map(array))
            XCTAssertEqual(parents.first?.valueSource, ids == nil ? nil : .initialInstance)
            XCTAssertEqual(form.makeToolContext(), context)
            XCTAssertEqual(form.currentInstanceJSON, before)
            XCTAssertEqual(form.revision, revision)
            XCTAssertFalse(form.hasAttemptedValidation)
        }
    }

    func testWholeArraySetPreservesLiteralIdentifiersAndReturnsRefreshedContext() throws {
        let form = FormKitRenderer().makeFormSession(
            schemaJSON: try schema(), instanceJSON: try instanceJSON(["original"])
        )
        let ids = ["", "  ", "0", "01", "later-page:opaque"]
        let revision = form.revision
        let edit = FormKitToolEdit(pointer: "/equipment", operation: .set, value: array(ids))
        let result = form.applyToolEdits([edit], baseRevision: revision)
        XCTAssertTrue(result.rejectedEdits.isEmpty)
        XCTAssertEqual(result.appliedEdits, [edit])
        XCTAssertGreaterThan(result.revision, revision)
        XCTAssertEqual(try equipmentValue(form), array(ids))
        XCTAssertEqual(result.context.currentValues["/equipment"], array(ids))
        XCTAssertEqual(parent(in: result.context)?.valueSource, .sessionEdit)
        XCTAssertEqual(result.context, form.makeToolContext())
    }

    func testClearRecordsExplicitEmptyAndOnlyAlreadyConfirmedEmptyIsNoChange() throws {
        for (initial, defaults) in [(nil, nil), (["saved"], nil), (nil, [])] as [([String]?, [String]?)] {
            let form = FormKitRenderer().makeFormSession(
                schemaJSON: try schema(defaultIDs: defaults), instanceJSON: try initial.map { try instanceJSON($0) }
            )
            let revision = form.revision
            let result = form.applyToolEdits([.init(pointer: "/equipment", operation: .clear)])
            XCTAssertTrue(result.rejectedEdits.isEmpty)
            XCTAssertEqual(result.appliedEdits.count, 1)
            XCTAssertGreaterThan(result.revision, revision)
            XCTAssertEqual(try equipmentValue(form), .array([]))
            XCTAssertEqual(result.context.currentValues["/equipment"], .array([]))
            XCTAssertEqual(parent(in: result.context)?.valueSource, .sessionEdit)
            let after = form.revision
            let unchanged = form.applyToolEdits([.init(pointer: "/equipment", operation: .clear)])
            XCTAssertTrue(unchanged.appliedEdits.isEmpty)
            XCTAssertEqual(unchanged.rejectedEdits.first?.reason, "no_change")
            XCTAssertEqual(form.revision, after)
        }
        let suppliedEmpty = FormKitRenderer().makeFormSession(
            schemaJSON: try schema(), instanceJSON: try instanceJSON([])
        )
        let revision = suppliedEmpty.revision
        let result = suppliedEmpty.applyToolEdits([.init(pointer: "/equipment", operation: .clear)])
        XCTAssertTrue(result.appliedEdits.isEmpty)
        XCTAssertEqual(result.rejectedEdits.first?.reason, "no_change")
        XCTAssertEqual(suppliedEmpty.revision, revision)
        XCTAssertEqual(parent(in: result.context)?.valueSource, .initialInstance)
    }

    func testSameValueSetConfirmsEmptyAndNonemptySchemaDefaults() throws {
        for ids in [[], ["", "  ", "default:opaque"]] {
            let form = FormKitRenderer().makeFormSession(schemaJSON: try schema(defaultIDs: ids))
            let before = form.currentInstanceJSON
            let revision = form.revision
            XCTAssertEqual(parent(in: form.makeToolContext())?.valueSource, .defaultValue)
            let edit = FormKitToolEdit(pointer: "/equipment", operation: .set, value: array(ids))
            let result = form.applyToolEdits([edit])
            XCTAssertTrue(result.rejectedEdits.isEmpty)
            XCTAssertEqual(result.appliedEdits, [edit])
            XCTAssertGreaterThan(form.revision, revision)
            XCTAssertEqual(parent(in: result.context)?.valueSource, .sessionEdit)
            XCTAssertEqual(result.context.currentValues["/equipment"], array(ids))
            XCTAssertEqual(form.currentInstanceJSON, before)
        }
    }

    func parent(in context: FormKitToolContext) -> FormKitToolField? {
        context.fields.first { $0.pointer == "/equipment" }
    }

    func equipmentValue(_ form: FormKitSession) throws -> FormKitJSONValue? {
        try JSONDecoder().decode(FormKitJSONValue.self, from: Data(form.currentInstanceJSON.utf8))
            .value(atPointer: "#/equipment")
    }

    func array(_ ids: [String]) -> FormKitJSONValue {
        .array(ids.map(FormKitJSONValue.string))
    }

    func instanceJSON(_ ids: [String], note: String? = nil) throws -> String {
        var value: [String: Any] = ["equipment": ids]
        if let note {
            value["note"] = note
        }
        return try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: value), encoding: .utf8))
    }

    func schema(defaultIDs: [String]? = nil, minimum: Int = 0, maximum: Int? = nil,
                component: String = "dynamic-options", items: [String: Any] = ["type": "string"],
                containerType: Any = "array") throws -> String
    {
        var equipment: [String: Any] = [
            "type": containerType, "title": "Equipment", "minItems": minimum,
            "items": items, "x-formkit-ui-component": component
        ]
        if let defaultIDs {
            equipment["default"] = defaultIDs
        }
        if let maximum {
            equipment["maxItems"] = maximum
        }
        let definition: [String: Any] = [
            "type": "object", "required": ["equipment"],
            "properties": ["equipment": equipment, "note": ["type": "string", "default": "Untouched"],
                           "otherDefault": ["type": "string", "default": "Keep"]]
        ]
        return try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: definition), encoding: .utf8))
    }

    func assertRejected(_ form: FormKitSession, _ edit: FormKitToolEdit,
                        locks: Set<String> = [], reason: String? = nil,
                        file: StaticString = #filePath, line: UInt = #line)
    {
        let before = form.currentInstanceJSON
        let revision = form.revision
        let context = form.makeToolContext()
        let result = form.applyToolEdits([edit], lockedPointers: locks)
        XCTAssertTrue(result.appliedEdits.isEmpty, file: file, line: line)
        XCTAssertEqual(result.rejectedEdits.count, 1, file: file, line: line)
        if let reason {
            XCTAssertEqual(result.rejectedEdits.first?.reason, reason, file: file, line: line)
        }
        XCTAssertEqual(form.currentInstanceJSON, before, file: file, line: line)
        XCTAssertEqual(form.revision, revision, file: file, line: line)
        XCTAssertEqual(result.context, context, file: file, line: line)
    }
}
