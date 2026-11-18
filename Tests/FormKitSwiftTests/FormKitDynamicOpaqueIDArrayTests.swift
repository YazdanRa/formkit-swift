import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitDynamicOpaqueIDArrayTests: XCTestCase {
    func testBlankArrayIDsCountForCapacityAndSurviveUntilDeliberateRemoval() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: schema, instanceJSON: #"{"equipment":["","  ","saved","" ]}"#
        )
        let context = try context(session)
        let revision = session.revision
        XCTAssertEqual(context.selectedIDs, ["", "  ", "saved"])
        XCTAssertEqual(try array(session), ["", "  ", "saved", ""])
        XCTAssertEqual(session.revision, revision)
        XCTAssertFalse(context.selection().canChoose("new", maximumSelectionCount: 3))
        context.selection().choose("new", isRequired: true, maximumSelectionCount: 3)
        XCTAssertEqual(try array(session), ["", "  ", "saved", ""])
        context.selection().choose("", isRequired: true, maximumSelectionCount: 3)
        XCTAssertEqual(try array(session), ["  ", "saved"])
        context.selection().choose("new", isRequired: true, maximumSelectionCount: 3)
        context.selection().choose("saved", isRequired: true, maximumSelectionCount: 3)
        context.selection().choose("", isRequired: true, maximumSelectionCount: 3)
        XCTAssertEqual(try array(session), ["  ", "new", ""])
        XCTAssertTrue(session.validate())
        let note = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/note" })
        session.setStringValue("Unrelated", for: note)
        let reopened = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: session.currentInstanceJSON)
        XCTAssertEqual(try self.context(reopened).selectedIDs, ["  ", "new", ""])
        XCTAssertTrue(reopened.validate())
    }

    func testRequiredSingleCapacityArrayRetainsAndReplacesAnEmptyIdentifier() throws {
        let definition = schema.replacingOccurrences(of: "\"maxItems\":3", with: "\"maxItems\":1")
        let session = FormKitRenderer().makeFormSession(schemaJSON: definition, instanceJSON: #"{"equipment":[""]}"#)
        let context = try context(session)
        XCTAssertEqual(context.selectedIDs, [""])
        XCTAssertTrue(session.validate())
        context.selection().choose("", isRequired: true, maximumSelectionCount: 1)
        XCTAssertEqual(try array(session), [""])
        context.selection().choose("replacement", isRequired: true, maximumSelectionCount: 1)
        XCTAssertEqual(try array(session), ["replacement"])
        context.selection().choose("", isRequired: true, maximumSelectionCount: 1)
        XCTAssertEqual(try array(session), [""])
        XCTAssertTrue(session.validate())
    }

    func testArrayItemPresenceAndToolSnapshotKeepBlankIDsWithoutWeakeningItemConstraints() throws {
        for id in ["", "  "] {
            let data = try JSONSerialization.data(withJSONObject: ["equipment": [id]])
            let instance = try XCTUnwrap(String(data: data, encoding: .utf8))
            let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: instance)
            let field = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/equipment/0" })
            XCTAssertTrue(session.hasAnswer(for: field))
            XCTAssertNotNil(session.displayValue(for: field))
            XCTAssertTrue(session.formSummary().missingRequired.isEmpty)
            XCTAssertEqual(session.makeToolContext().currentValues["/equipment/0"], .string(id))
            XCTAssertFalse(session.makeToolContext().summary.contains("Missing required"))
            XCTAssertTrue(session.validate())
            let constrained = schema.replacingOccurrences(of: "\"items\":{\"type\":\"string\"}",
                                                          with: "\"items\":{\"type\":\"string\",\"pattern\":\"\\\\S\"}")
            let invalid = FormKitRenderer().makeFormSession(schemaJSON: constrained, instanceJSON: instance)
            XCTAssertEqual(try array(invalid), [id])
            XCTAssertFalse(invalid.validate())
        }
    }

    func testAuthoredArrayDefaultsRetainLiteralBlankIDsThroughUnrelatedEditAndReopen() throws {
        for id in ["", "  "] {
            let data = try JSONSerialization.data(withJSONObject: [id])
            let value = try XCTUnwrap(String(data: data, encoding: .utf8))
            let definition = schema.replacingOccurrences(of: "\"minItems\":1",
                                                         with: "\"default\":\(value),\"minItems\":1")
            let session = FormKitRenderer().makeFormSession(schemaJSON: definition)
            XCTAssertEqual(try context(session).selectedIDs, [id])
            XCTAssertEqual(try array(session), [id])
            XCTAssertTrue(session.validate())
            let note = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/note" })
            session.setStringValue("Unrelated", for: note)
            let reopened = FormKitRenderer().makeFormSession(schemaJSON: definition,
                                                            instanceJSON: session.currentInstanceJSON)
            XCTAssertEqual(try context(reopened).selectedIDs, [id])
            XCTAssertTrue(reopened.validate())
        }
    }

    private func context(_ session: FormKitSession) throws -> FormKitDynamicOptionsContext {
        let section = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/equipment" })
        return .arraySection(FormKitArraySectionComponentContext(
            session: session, section: section, descriptor: try XCTUnwrap(section.arrayDescriptor), errors: [],
            isEditingLocked: false, style: .init(), labels: .init(), uploadHandler: nil
        ))
    }

    private func array(_ session: FormKitSession) throws -> [String] {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(session.currentInstanceJSON.utf8))
            as? [String: Any])
        return try XCTUnwrap(object["equipment"] as? [String])
    }

    private var schema: String {
        #"""
        {"type":"object","required":["equipment"],"properties":{
          "note":{"type":"string"},"equipment":{"type":"array","minItems":1,"maxItems":3,
          "items":{"type":"string"},"x-formkit-ui-component":"dynamic-options"}
        }}
        """#
    }
}
