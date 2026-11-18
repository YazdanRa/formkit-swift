import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitDynamicVacancyTests: XCTestCase {
    func testAbsentRequiredArrayVacancyDoesNotOccupySelectionOrCapacity() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: arraySchema)
        let context = try arrayContext(session)
        let before = session.currentInstanceJSON
        let revision = session.revision
        let section = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/equipment" })
        XCTAssertNil(session.arrayValue(for: section))
        XCTAssertTrue(context.selectedIDs.isEmpty)
        var factoryIDs: [String]?
        let components = FormKitFocusSupport.resolvedComponents(session: session, options: FormKitOptions(
            dynamicOptions: { context in
                factoryIDs = context.selectedIDs
                return FormKitDynamicOptionsSource { _, _ in FormKitDynamicOptionsPage(options: []) }
            }
        ))
        XCTAssertEqual(components.arraySections.count, 1)
        XCTAssertEqual(factoryIDs, [])
        XCTAssertEqual(session.revision, revision)
        XCTAssertEqual(session.currentInstanceJSON, before)

        XCTAssertTrue(context.selection().canChoose("equipment:1", maximumSelectionCount: 1))
        context.selection().choose("equipment:1", isRequired: context.requiresSelection, maximumSelectionCount: 1)
        XCTAssertEqual(context.selectedIDs, ["equipment:1"])
        let current = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/equipment" })
        XCTAssertEqual(session.arrayValue(for: current), [.string("equipment:1")])
        XCTAssertTrue(session.validate())

        let guarded = context.selection(canSelect: { $0 != "equipment:2" })
        let beforeDeniedReplacement = session.revision
        guarded.choose("equipment:2", isRequired: context.requiresSelection, maximumSelectionCount: 1)
        XCTAssertEqual(context.selectedIDs, ["equipment:1"])
        XCTAssertEqual(session.revision, beforeDeniedReplacement)
        XCTAssertTrue(context.selection().canChoose("equipment:2", maximumSelectionCount: 1))
        context.selection().choose("equipment:2", isRequired: context.requiresSelection, maximumSelectionCount: 1)
        XCTAssertEqual(context.selectedIDs, ["equipment:2"])
        XCTAssertTrue(session.validate())
        context.selection().choose("equipment:2", isRequired: context.requiresSelection, maximumSelectionCount: 1)
        XCTAssertEqual(context.selectedIDs, ["equipment:2"])
    }

    func testArrayDefaultsAndNonemptyOpaqueIDsArePreservedOnRead() throws {
        let defaultSchema = arraySchema.replacingOccurrences(of: "\"maxItems\":1,", with:
            "\"maxItems\":1,\"default\":[\"default:1\"],")
        for (schema, instance, ids) in [
            (defaultSchema, nil, ["default:1"]),
            (arraySchema, #"{"equipment":["  ","equipment:old"]}"#, ["  ", "equipment:old"])
        ] {
            let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: instance)
            let context = try arrayContext(session)
            let before = session.currentInstanceJSON
            let revision = session.revision
            XCTAssertEqual(context.selectedIDs, ids)
            XCTAssertEqual(session.currentInstanceJSON, before)
            XCTAssertEqual(session.revision, revision)
        }
    }

    func testRequiredNullableScalarCanClearToNullWhileNonnullSelectionIsRetained() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: #"""
            {"type":"object","required":["nullable","fixed"],"properties":{
              "nullable":{"type":["string","null"],"x-formkit-ui-component":"dynamic-options"},
              "fixed":{"type":"string","minLength":1,"x-formkit-ui-component":"dynamic-options"}
            }}
            """#,
            instanceJSON: #"{"nullable":"option:old","fixed":"option:fixed"}"#
        )
        let nullable = try fieldContext("#/nullable", session: session)
        XCTAssertFalse(nullable.requiresSelection)
        nullable.selection().choose("option:new", isRequired: nullable.requiresSelection)
        XCTAssertEqual(nullable.selectedIDs, ["option:new"])
        nullable.selection().clear(isRequired: nullable.requiresSelection)
        let field = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/nullable" })
        XCTAssertEqual(session.primitiveValue(for: field), .null)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(session.currentInstanceJSON.utf8))
            as? [String: Any])
        XCTAssertTrue(object["nullable"] is NSNull)
        XCTAssertTrue(session.validate())

        let fixed = try fieldContext("#/fixed", session: session)
        XCTAssertTrue(fixed.requiresSelection)
        fixed.selection().clear(isRequired: fixed.requiresSelection)
        XCTAssertEqual(fixed.selectedIDs, ["option:fixed"])
        XCTAssertTrue(session.validate())
    }

    private func arrayContext(_ session: FormKitSession) throws -> FormKitDynamicOptionsContext {
        let section = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/equipment" })
        return .arraySection(FormKitArraySectionComponentContext(
            session: session, section: section, descriptor: try XCTUnwrap(section.arrayDescriptor), errors: [],
            isEditingLocked: false, style: .init(), labels: .init(), uploadHandler: nil
        ))
    }

    private func fieldContext(_ pointer: String, session: FormKitSession) throws -> FormKitDynamicOptionsContext {
        let field = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == pointer })
        return .field(FormKitFieldComponentContext(
            session: session, field: field, errors: [], state: .normal,
            isEditingLocked: false, style: .init(), uploadHandler: nil
        ))
    }

    private var arraySchema: String {
        #"""
        {"type":"object","required":["equipment"],"properties":{"equipment":{
          "type":"array","minItems":1,"maxItems":1,"x-formkit-ui-component":"dynamic-options",
          "items":{"type":"string","minLength":1}
        }}}
        """#
    }
}
