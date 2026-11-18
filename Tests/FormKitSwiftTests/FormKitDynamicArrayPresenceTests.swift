import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitDynamicArrayPresenceTests: XCTestCase {
    func testAbsentRequiredArrayStaysAbsentThroughUnrelatedEditAndReopenAndShowsError() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: schema)
        XCTAssertNil(try object(session)["equipment"])
        let section = try arraySection(session)
        XCTAssertTrue(try XCTUnwrap(section.arrayDescriptor).rows.isEmpty)
        XCTAssertFalse(try XCTUnwrap(section.arrayDescriptor).materializeWhenEmpty)
        XCTAssertFalse(session.validate())
        XCTAssertFalse(session.errorMessages(for: section).isEmpty)
        let wrapper = FormKitDynamicOptionsArraySection(
            context: try arrayContext(session),
            source: FormKitDynamicOptionsSource { _, _ in FormKitDynamicOptionsPage(options: []) }
        )
        XCTAssertFalse(wrapper.validationMessages.isEmpty)

        let note = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/note" })
        session.setStringValue("Unrelated edit", for: note)
        XCTAssertNil(try object(session)["equipment"])
        let reopened = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: session.currentInstanceJSON)
        XCTAssertNil(try object(reopened)["equipment"])
        XCTAssertFalse(reopened.validate())
        XCTAssertFalse(reopened.errorMessages(for: try arraySection(reopened)).isEmpty)
    }

    func testExplicitEmptyArrayRemainsEmptyAndInvalidUntilFirstChoiceThenReopensValid() throws {
        for definition in [schema, optionalSchema] {
            let session = FormKitRenderer().makeFormSession(schemaJSON: definition, instanceJSON: #"{"equipment":[]}"#)
            XCTAssertEqual(try object(session)["equipment"] as? [String], [])
            XCTAssertTrue(try XCTUnwrap(arraySection(session).arrayDescriptor).rows.isEmpty)
            XCTAssertTrue(try XCTUnwrap(arraySection(session).arrayDescriptor).materializeWhenEmpty)
            XCTAssertFalse(session.validate())
            XCTAssertFalse(session.errorMessages(for: try arraySection(session)).isEmpty)
            let note = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/note" })
            session.setStringValue("Unrelated edit", for: note)
            let emptyReopened = FormKitRenderer().makeFormSession(schemaJSON: definition,
                                                                 instanceJSON: session.currentInstanceJSON)
            XCTAssertEqual(try object(emptyReopened)["equipment"] as? [String], [])
            XCTAssertFalse(emptyReopened.validate())

            let context = FormKitDynamicOptionsContext.arraySection(try arrayContext(emptyReopened))
            context.selection().choose("equipment:1", isRequired: context.requiresSelection, maximumSelectionCount: 1)
            XCTAssertTrue(emptyReopened.validate())
            let selectedReopened = FormKitRenderer().makeFormSession(schemaJSON: definition,
                                                                    instanceJSON: emptyReopened.currentInstanceJSON)
            let restored = FormKitDynamicOptionsContext.arraySection(try arrayContext(selectedReopened))
            restored.selection().choose("equipment:2", isRequired: restored.requiresSelection, maximumSelectionCount: 1)
            XCTAssertEqual(try object(selectedReopened)["equipment"] as? [String], ["equipment:2"])
            XCTAssertTrue(selectedReopened.validate())
            let reopened = FormKitRenderer().makeFormSession(schemaJSON: definition,
                                                            instanceJSON: selectedReopened.currentInstanceJSON)
            XCTAssertEqual(try object(reopened)["equipment"] as? [String], ["equipment:2"])
            XCTAssertTrue(reopened.validate())
        }
    }

    func testDeclaredDefaultsAndProvidedArraysArePreservedWithoutMinimumPlaceholders() throws {
        for values in [[], ["default:1"], ["first", "  ", "", "first"]] {
            let data = try JSONSerialization.data(withJSONObject: values)
            let defaultJSON = try XCTUnwrap(String(data: data, encoding: .utf8))
            let declared = schema.replacingOccurrences(of: "\"minItems\":1",
                                                       with: "\"default\":\(defaultJSON),\"minItems\":5")
            let session = FormKitRenderer().makeFormSession(schemaJSON: declared)
            XCTAssertEqual(try object(session)["equipment"] as? [String], values)
            XCTAssertEqual(try XCTUnwrap(arraySection(session).arrayDescriptor).rows.count, values.count)
            let reopened = FormKitRenderer().makeFormSession(schemaJSON: declared,
                                                            instanceJSON: session.currentInstanceJSON)
            XCTAssertEqual(try object(reopened)["equipment"] as? [String], values)
            let supplied = FormKitRenderer().makeFormSession(schemaJSON: declared,
                                                             instanceJSON: "{\"equipment\":\(defaultJSON)}")
            XCTAssertEqual(try object(supplied)["equipment"] as? [String], values)
            let explicit = FormKitRenderer().makeFormSession(schemaJSON: declared, instanceJSON: #"{"equipment":[]}"#)
            XCTAssertEqual(try object(explicit)["equipment"] as? [String], [])
        }
    }

    func testOptionalAbsentParentDoesNotAcquireRequiredArrayOrError() throws {
        let nested = #"""
        {"type":"object","properties":{"optional":{"type":"object","required":["equipment"],
          "properties":{"note":{"type":"string"},"equipment":{"type":"array","minItems":1,"items":{"type":"string"},
          "x-formkit-ui-component":"dynamic-options"}}}}}
        """#
        let session = FormKitRenderer().makeFormSession(schemaJSON: nested)
        XCTAssertNil(try object(session)["optional"])
        XCTAssertTrue(session.validate())
        let section = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/optional/equipment" })
        XCTAssertTrue(session.errorMessages(for: section).isEmpty)
        for hiddenTools in [false, true] {
            let renderer = FormKitRenderer(includesHiddenToolFields: hiddenTools)
            let present = renderer.makeFormSession(schemaJSON: nested, instanceJSON: #"{"optional":{}}"#)
            XCTAssertEqual((try object(present)["optional"] as? [String: Any])?.count, 0)
            XCTAssertFalse(present.validate())
            let current = try XCTUnwrap(present.renderPlan.sections.first { $0.pointer == section.pointer })
            XCTAssertFalse(present.errorMessages(for: current).isEmpty)
            let note = try XCTUnwrap(present.renderPlan.fields.first { $0.pointer == "#/optional/note" })
            present.setStringValue("Unrelated edit", for: note)
            XCTAssertNil((try object(present)["optional"] as? [String: Any])?["equipment"])
            let reopened = renderer.makeFormSession(schemaJSON: nested, instanceJSON: present.currentInstanceJSON)
            XCTAssertFalse(reopened.validate())
        }
    }

    func testOptionalArrayMinimumDoesNotRequireAnAbsentArray() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: optionalSchema)
        XCTAssertNil(try object(session)["equipment"])
        XCTAssertTrue(session.validate())
        let note = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/note" })
        session.setStringValue("Unrelated edit", for: note)
        let reopened = FormKitRenderer().makeFormSession(schemaJSON: optionalSchema,
                                                        instanceJSON: session.currentInstanceJSON)
        XCTAssertNil(try object(reopened)["equipment"])
        XCTAssertTrue(reopened.validate())
    }

    func testEffectiveReferenceAndCompositionUseDynamicCompatibility() throws {
        let composed = #"""
        {"type":"object","required":["equipment"],"$defs":{"identifier":{"type":"string","minLength":1}},
          "properties":{"equipment":{"type":"array","minItems":1,"items":{"$ref":"#/$defs/identifier"}}},
          "allOf":[{"properties":{"equipment":{"x-formkit-ui-component":"dynamic-options"}}}]}
        """#
        let session = FormKitRenderer().makeFormSession(schemaJSON: composed)
        XCTAssertTrue(session.renderPlan.isSupported, "\(session.renderPlan.unsupportedReasons)")
        let section = try arraySection(session)
        XCTAssertTrue(section.usesDynamicOptions)
        XCTAssertTrue(try XCTUnwrap(section.arrayDescriptor).rows.isEmpty)
        XCTAssertNil(try object(session)["equipment"])
        XCTAssertFalse(session.validate())
        var factoryCalled = false
        XCTAssertNotNil(FormKitComponentRegistry.arraySection(for: try arrayContext(session), dynamicOptions: { _ in
            factoryCalled = true
            return FormKitDynamicOptionsSource { _, _ in FormKitDynamicOptionsPage(options: []) }
        }))
        XCTAssertTrue(factoryCalled)
    }

    func testOrdinaryAndIncompatibleArraysKeepMinimumPlaceholderBehavior() throws {
        for (component, items) in [
            ("", #"{"type":"string"}"#),
            ("dynamic-options", #"{"type":["string","null"]}"#),
            ("dynamic-options", #"{"type":"string","enum":["one","two"]}"#),
            ("dynamic-options", #"{"type":"string","const":"one"}"#),
            ("dynamic-options", #"{"type":"string","format":"date"}"#)
        ] {
            let ordinary = #"""
            {"type":"object","required":["equipment"],"properties":{"equipment":{
              "type":"array","minItems":1,"items":ITEMS,"x-formkit-ui-component":"COMPONENT"
            }}}
            """#
                .replacingOccurrences(of: "ITEMS", with: items)
                .replacingOccurrences(of: "COMPONENT", with: component)
            let session = FormKitRenderer().makeFormSession(schemaJSON: ordinary)
            XCTAssertTrue(session.renderPlan.isSupported)
            XCTAssertEqual(try XCTUnwrap(arraySection(session).arrayDescriptor).rows.count, 1)
            XCTAssertEqual((try object(session)["equipment"] as? [Any])?.count, 1)
        }
    }

    private func arraySection(_ session: FormKitSession) throws -> FormKitRenderPlan.SectionDescriptor {
        try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/equipment" })
    }

    private func arrayContext(_ session: FormKitSession) throws -> FormKitArraySectionComponentContext {
        let section = try arraySection(session)
        return FormKitArraySectionComponentContext(
            session: session, section: section, descriptor: try XCTUnwrap(section.arrayDescriptor), errors: [],
            isEditingLocked: false, style: .init(), labels: .init(), uploadHandler: nil
        )
    }

    private func object(_ session: FormKitSession) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(session.currentInstanceJSON.utf8)) as? [String: Any])
    }

    private var schema: String {
        #"""
        {"type":"object","required":["equipment"],"properties":{
          "note":{"type":"string"},"equipment":{"type":"array","minItems":1,"maxItems":1,
          "items":{"type":"string","minLength":1},"x-formkit-ui-component":"dynamic-options"}
        }}
        """#
    }

    private var optionalSchema: String {
        schema.replacingOccurrences(of: "\"required\":[\"equipment\"],", with: "")
    }
}
