import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitToolClearContractTests: XCTestCase {
    func testClearConfirmsDefaultNullWithoutChangingTheValue() throws {
        let definitions: [[String: Any]] = [
            ["type": ["string", "null"]],
            ["type": ["string", "null"], "x-formkit-ui-component": "dynamic-options"],
            ["type": ["boolean", "null"]], ["type": ["integer", "null"]], ["type": ["number", "null"]],
            ["type": ["string", "null"], "format": "date"],
            ["type": ["string", "null"], "format": "time"],
            ["type": ["string", "null"], "format": "date-time"],
            ["type": ["string", "null"], "enum": ["Option", NSNull()]]
        ]
        for var definition in definitions {
            definition["default"] = NSNull()
            let session = try makeSession(definition)
            let before = session.currentInstanceJSON
            XCTAssertEqual(source(session), .defaultValue)
            let edit = FormKitToolEdit(pointer: "/value", operation: .clear)
            let result = session.applyToolEdits([edit], baseRevision: session.revision)
            XCTAssertEqual(result.appliedEdits, [edit])
            XCTAssertTrue(result.rejectedEdits.isEmpty)
            XCTAssertEqual(result.context.currentValues["/value"], .null)
            XCTAssertEqual(source(session), .sessionEdit)
            XCTAssertEqual(session.currentInstanceJSON, before)
            XCTAssertEqual(session.revision, 1)
            XCTAssertTrue(session.validate())
            let repeated = session.applyToolEdits([edit])
            XCTAssertEqual(repeated.rejectedEdits.first?.reason, "no_change")
            XCTAssertEqual(session.revision, 1)
        }
    }

    func testOptionalDynamicScalarClearStoresNullOrOmitsTheProperty() throws {
        for nullable in [false, true] {
            for initial in [nil, #"{"value":"Original"}"#, #"{"value":""}"#] as [String?] {
                let type: Any = nullable ? ["string", "null"] : "string"
                let session = try makeSession(["type": type, "x-formkit-ui-component": "dynamic-options"],
                                              instance: initial)
                let edit = FormKitToolEdit(pointer: "/value", operation: .clear)
                let result = session.applyToolEdits([edit])
                XCTAssertEqual(result.appliedEdits, nullable || initial != nil ? [edit] : [])
                let instance = try JSONDecoder().decode(
                    FormKitJSONValue.self, from: Data(session.currentInstanceJSON.utf8)
                )
                XCTAssertEqual(instance.object?["value"], nullable ? .null : nil)
                XCTAssertEqual(result.context.currentValues["/value"], nullable ? .null : nil)
                XCTAssertEqual(source(session), nullable ? .sessionEdit : nil)
                XCTAssertTrue(session.validate())
            }
        }
    }

    func testExplicitNullRemainsNoChangeAndDefaultConfirmationHonorsExistingGuards() throws {
        let definition: [String: Any] = ["type": ["string", "null"], "default": NSNull()]
        let initial = try makeSession(definition, instance: #"{"value":null}"#)
        let edit = FormKitToolEdit(pointer: "/value", operation: .clear)
        XCTAssertEqual(initial.applyToolEdits([edit]).rejectedEdits.first?.reason, "no_change")
        XCTAssertEqual(initial.revision, 0)
        XCTAssertEqual(source(initial), .initialInstance)

        let session = try makeSession(definition)
        let before = session.currentInstanceJSON
        let locked = session.applyToolEdits([edit], lockedPointers: ["#/value"])
        XCTAssertEqual(locked.rejectedEdits.first?.reason, "field_locked")
        let stale = session.applyToolEdits([edit], baseRevision: session.revision + 1)
        XCTAssertEqual(stale.rejectedEdits.first?.reason, "revision_conflict")
        XCTAssertEqual(session.currentInstanceJSON, before)
        XCTAssertEqual(session.revision, 0)
        XCTAssertEqual(source(session), .defaultValue)
        let nullSet = session.applyToolEdits([.init(pointer: "/value", operation: .set, value: .null)])
        XCTAssertEqual(nullSet.rejectedEdits.first?.reason, "type_mismatch")
        XCTAssertEqual(source(session), .defaultValue)
        XCTAssertEqual(session.revision, 0)
    }

    func testDefaultNullConfirmationDoesNotIntroduceInactiveWrites() throws {
        let schema = #"""
        {"type":"object","properties":{"enabled":{"type":"boolean"}},
          "if":{"properties":{"enabled":{"const":true}},"required":["enabled"]},
          "then":{"properties":{"value":{"type":["string","null"],"default":null,
            "x-formkit-ui-component":"dynamic-options"}}}}
        """#
        for behavior in [FormKitConditionalRenderBehavior.hide, .disable, .ignore] {
            let session = FormKitRenderer(defaultConditionalRenderBehavior: behavior, includesHiddenToolFields: true)
                .makeFormSession(schemaJSON: schema, instanceJSON: #"{"enabled":false}"#)
            let before = session.currentInstanceJSON
            let revision = session.revision
            let edit = FormKitToolEdit(pointer: "/value", operation: .clear)
            let result = session.applyToolEdits([edit])
            XCTAssertTrue(result.appliedEdits.isEmpty)
            XCTAssertEqual(session.revision, revision)
            XCTAssertEqual(session.currentInstanceJSON, before)
            let enabled = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/enabled" })
            session.setBooleanValue(true, for: enabled)
            XCTAssertEqual(session.applyToolEdits([edit]).appliedEdits, [edit])
            XCTAssertEqual(source(session), .sessionEdit)
            XCTAssertTrue(session.validate())
        }
    }

    private func makeSession(_ definition: [String: Any], instance: String? = nil) throws -> FormKitSession {
        let data = try JSONSerialization.data(withJSONObject: ["type": "object", "properties": ["value": definition]])
        return FormKitRenderer().makeFormSession(schemaJSON: try XCTUnwrap(String(data: data, encoding: .utf8)),
                                                instanceJSON: instance)
    }

    private func source(_ session: FormKitSession) -> FormKitToolValueSource? {
        session.makeToolContext().fields.first { $0.pointer == "/value" }?.valueSource
    }
}
