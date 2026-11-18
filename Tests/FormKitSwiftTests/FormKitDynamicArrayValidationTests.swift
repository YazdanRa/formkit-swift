import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitDynamicArrayValidationTests: XCTestCase {
    func testArrayWrapperShowsItemAndArrayErrorsThenClearsAfterCorrection() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: #"""
            {"type":"object","properties":{"equipment":{
              "type":"array","maxItems":1,"x-formkit-ui-component":"dynamic-options",
              "items":{"type":"string","minLength":4,"pattern":"^equipment:[0-9]+$"}
            }}}
            """#,
            instanceJSON: #"{"equipment":["x","x"]}"#
        )
        XCTAssertTrue(session.renderPlan.isSupported)
        let wrapper = try component(in: session)
        XCTAssertFalse(session.validate())
        let section = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/equipment" })
        let first = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/equipment/0" })
        let second = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/equipment/1" })
        let arrayErrors = session.errorMessages(for: section)
        let itemErrors = session.errorMessages(for: first)
        XCTAssertFalse(arrayErrors.isEmpty)
        XCTAssertEqual(itemErrors.count, 2)
        XCTAssertEqual(session.errorMessages(for: second), itemErrors)
        XCTAssertEqual(wrapper.validationMessages, arrayErrors + itemErrors)
        XCTAssertEqual(wrapper.validationMessages.count, Set(wrapper.validationMessages).count)

        session.setArrayValue([.string("equipment:1")], for: section)
        XCTAssertTrue(session.validate())
        XCTAssertTrue(wrapper.validationMessages.isEmpty)
    }

    func testArrayWrapperReadsCurrentArrayMessagesAndOmitsUnrelatedItemErrors() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: #"""
            {"type":"object","properties":{
              "equipment":{"type":"array","items":{"type":"string"},
                "x-formkit-ui-component":"dynamic-options"},
              "equipmentOther":{"type":"array","items":{"type":"string"}}
            }}
            """#,
            instanceJSON: #"{"equipment":["equipment:1"],"equipmentOther":["other"]}"#
        )
        let wrapper = try component(in: session)
        let section = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/equipment" })
        session.arrayErrors[section.id] = ["Minimum count", "Maximum count", "Minimum count"]
        session.fieldErrors["#/equipment/0"] = ["Item error", "Item error"]
        session.fieldErrors["#/equipmentOther/0"] = ["Unrelated error"]
        XCTAssertEqual(wrapper.validationMessages, ["Minimum count", "Maximum count", "Item error"])
    }

    private func component(in session: FormKitSession) throws -> FormKitDynamicOptionsArraySection {
        let section = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/equipment" })
        let descriptor = try XCTUnwrap(section.arrayDescriptor)
        return FormKitDynamicOptionsArraySection(
            context: FormKitArraySectionComponentContext(
                session: session, section: section, descriptor: descriptor,
                errors: session.errorMessages(for: section), isEditingLocked: false,
                style: .init(), labels: .init(), uploadHandler: nil
            ),
            source: FormKitDynamicOptionsSource { _, _ in FormKitDynamicOptionsPage(options: []) }
        )
    }
}
