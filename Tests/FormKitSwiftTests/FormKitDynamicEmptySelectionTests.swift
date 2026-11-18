import SwiftUI
import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitDynamicEmptySelectionTests: XCTestCase {
    func testRequiredZeroCapacityArrayStaysAbsentUntilExplicitEmptySelectionThenReopensValid() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: schema(minimum: 0))
        let context = try context(session)
        let revision = session.revision
        XCTAssertNil(try object(session)["equipment"])
        XCTAssertFalse(session.validate())
        let sheet = sheet(selection: context.selection(), isRequired: context.requiresSelection)
        XCTAssertTrue(sheet.showsClearSelection)
        XCTAssertTrue(context.selectedIDs.isEmpty)
        XCTAssertFalse(context.selection().canChoose("unavailable", maximumSelectionCount: 0))
        XCTAssertEqual(session.revision, revision)
        XCTAssertNil(try object(session)["equipment"])

        context.selection().clear(isRequired: context.requiresSelection)
        XCTAssertEqual(try object(session)["equipment"] as? [String], [])
        XCTAssertTrue(session.validate())
        let reopened = FormKitRenderer().makeFormSession(schemaJSON: schema(minimum: 0),
                                                        instanceJSON: session.currentInstanceJSON)
        XCTAssertEqual(try object(reopened)["equipment"] as? [String], [])
        XCTAssertTrue(reopened.validate())
    }

    func testPositiveMinimumDoesNotOfferEmptyActionOrWriteAbsentOrEmptyArray() throws {
        for instance in [nil, #"{"equipment":[]}"#] {
            let session = FormKitRenderer().makeFormSession(schemaJSON: schema(minimum: 1), instanceJSON: instance)
            let context = try context(session)
            let before = session.currentInstanceJSON
            let revision = session.revision
            let pickerSheet = sheet(selection: context.selection(), isRequired: context.requiresSelection)
            XCTAssertFalse(pickerSheet.showsClearSelection)
            context.selection().clear(isRequired: context.requiresSelection)
            XCTAssertEqual(session.currentInstanceJSON, before)
            XCTAssertEqual(session.revision, revision)
            XCTAssertFalse(session.validate())
        }
    }

    func testEmptyScalarStillHidesClearAndSelectedOptionalScalarCanClear() {
        var value: String?
        let selection = FormKitDynamicSelection.single(Binding(get: { value }, set: { value = $0 }))
        XCTAssertFalse(sheet(selection: selection, isRequired: false).showsClearSelection)
        XCTAssertNil(value)
        value = "saved-option"
        XCTAssertTrue(sheet(selection: selection, isRequired: false).showsClearSelection)
        XCTAssertFalse(sheet(selection: selection, isRequired: true).showsClearSelection)
    }

    private func sheet(selection: FormKitDynamicSelection, isRequired: Bool) -> FormKitDynamicOptionsPickerSheet {
        FormKitDynamicOptionsPickerSheet(
            title: "Equipment", selection: selection, savedOptions: [], labels: FormKitDynamicOptionsPickerLabels(),
            isRequired: isRequired, maximumSelectionCount: 0, isEditingLocked: false,
            provider: { _, _ in FormKitDynamicOptionsPage(options: []) }
        )
    }

    private func context(_ session: FormKitSession) throws -> FormKitDynamicOptionsContext {
        let section = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/equipment" })
        return .arraySection(FormKitArraySectionComponentContext(
            session: session, section: section, descriptor: try XCTUnwrap(section.arrayDescriptor), errors: [],
            isEditingLocked: false, style: .init(), labels: .init(), uploadHandler: nil
        ))
    }

    private func object(_ session: FormKitSession) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(session.currentInstanceJSON.utf8)) as? [String: Any])
    }

    private func schema(minimum: Int) -> String {
        """
        {"type":"object","required":["equipment"],"properties":{"equipment":{
          "type":"array","minItems":\(minimum),"maxItems":0,"items":{"type":"string"},
          "x-formkit-ui-component":"dynamic-options"
        }}}
        """
    }
}
