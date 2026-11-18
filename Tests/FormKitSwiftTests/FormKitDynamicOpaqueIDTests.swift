import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitDynamicOpaqueIDTests: XCTestCase {
    func testSavedScalarIDsRemainLiteralAcrossReadUnrelatedEditAndReopen() throws {
        for hiddenTools in [false, true] {
            let renderer = FormKitRenderer(includesHiddenToolFields: hiddenTools)
            for nullable in [false, true]
        {
                for required in [false, true] {
                    for id in ["", " \t\n", "0", "01", "saved:1"] {
                        let definition = try schema(nullable: nullable, required: required)
                        let data = try JSONSerialization.data(withJSONObject: ["choice": id])
                        let session = renderer.makeFormSession(
                            schemaJSON: definition, instanceJSON: try XCTUnwrap(String(data: data, encoding: .utf8))
                        )
                        let field = try field(session)
                        let revision = session.revision
                        XCTAssertEqual(session.primitiveValue(for: field), .string(id))
                        XCTAssertEqual(try context(session).selectedIDs, [id])
                        XCTAssertTrue(session.hasAnswer(for: field))
                        XCTAssertEqual(session.toolValueSource(for: field), .initialInstance)
                        XCTAssertEqual(session.makeToolContext().currentValues["/choice"], .string(id))
                        XCTAssertFalse(session.makeToolContext().summary.contains("Missing required"))
                        XCTAssertEqual(session.revision, revision)
                        XCTAssertTrue(session.validate())
                        XCTAssertTrue(session.formSummary().missingRequired.isEmpty)
                        try editUnrelatedField(session)
                        XCTAssertEqual(try object(session)["choice"] as? String, id)
                        let reopened = renderer.makeFormSession(schemaJSON: definition,
                                                                        instanceJSON: session.currentInstanceJSON)
                        XCTAssertEqual(try context(reopened).selectedIDs, [id])
                        XCTAssertTrue(reopened.validate())
                    }
                }
        }
        }
    }

    func testChosenScalarIDsUseEditLifecycleAndClearRemainsNullOrAbsence() throws {
        for hiddenTools in [false, true] {
            let renderer = FormKitRenderer(includesHiddenToolFields: hiddenTools)
            for nullable in [false, true]
        {
                for required in [false, true] {
                    for id in ["", " \t", "chosen:1"] {
                        let definition = try schema(nullable: nullable, required: required)
                        let session = renderer.makeFormSession(schemaJSON: definition)
                        let context = try context(session)
                        let revision = session.revision
                        context.selection().choose(id, isRequired: context.requiresSelection)
                        XCTAssertGreaterThan(session.revision, revision)
                        XCTAssertEqual(try object(session)["choice"] as? String, id)
                        XCTAssertEqual(session.toolValueSource(for: try field(session)), .sessionEdit)
                        XCTAssertTrue(session.hasAnswer(for: try field(session)))
                        XCTAssertTrue(session.validate())
                        try editUnrelatedField(session)
                        let reopened = renderer.makeFormSession(schemaJSON: definition,
                                                                        instanceJSON: session.currentInstanceJSON)
                        let restored = try self.context(reopened)
                        XCTAssertEqual(restored.selectedIDs, [id])
                        restored.selection().clear(isRequired: restored.requiresSelection)
                        let value = try object(reopened)["choice"]
                        if nullable {
                            XCTAssertTrue(value is NSNull)
                        } else if required {
                            XCTAssertEqual(value as? String, id)
                        } else {
                            XCTAssertNil(value)
                        }
                    }
                }
        }
        }
    }

    func testAuthoredBlankDefaultsRetainProvenanceAndRestoreFromNull() throws {
        for id in ["", " \n"] {
            let definition = try schema(nullable: true, required: true, defaultID: id)
            let session = FormKitRenderer().makeFormSession(schemaJSON: definition)
            let field = try field(session)
            XCTAssertEqual(session.primitiveValue(for: field), .string(id))
            XCTAssertEqual(field.defaultValue, .string(id))
            XCTAssertEqual(session.toolValueSource(for: field), .defaultValue)
            XCTAssertFalse(session.hasAnswer(for: field))
            XCTAssertTrue(session.validate())
            session.setNullSelection(true, for: field)
            XCTAssertTrue(try object(session)["choice"] is NSNull)
            session.setNullSelection(false, for: field)
            XCTAssertEqual(try object(session)["choice"] as? String, id)
            let reopened = FormKitRenderer().makeFormSession(schemaJSON: definition,
                                                            instanceJSON: session.currentInstanceJSON)
            XCTAssertEqual(try context(reopened).selectedIDs, [id])
            XCTAssertTrue(reopened.validate())
        }
    }

    func testSchemaLengthAndPatternStillRejectInvalidOpaqueIDsWithoutRewritingThem() throws {
        for (id, constraint) in [("", ["minLength": 1] as [String: Any]), ("  ", ["pattern": "\\S"])] {
            let session = FormKitRenderer().makeFormSession(
                schemaJSON: try schema(nullable: true, required: true, constraints: constraint)
            )
            try context(session).selection().choose(id, isRequired: false)
            XCTAssertEqual(try object(session)["choice"] as? String, id)
            XCTAssertFalse(session.validate())
            XCTAssertFalse(session.errorMessages(for: try field(session)).isEmpty)
        }
    }

    func testOrdinaryAndFormattedNullableTextKeepBlankNormalization() throws {
        for (annotation, constraints) in [("", [:] as [String: Any]), ("dynamic-options", ["format": "email"])] {
            let definition = try schema(nullable: true, required: false, annotation: annotation,
                                        constraints: constraints)
            let session = FormKitRenderer().makeFormSession(schemaJSON: definition, instanceJSON: #"{"choice":"  "}"#)
            let field = try field(session)
            XCTAssertFalse(field.usesDynamicOptions)
            XCTAssertTrue(try object(session)["choice"] is NSNull)
            session.setStringValue("", for: field)
            XCTAssertTrue(try object(session)["choice"] is NSNull)
        }
    }

    func testExplicitClearSurvivesLiveArrayReplacementAndAuthoredDefaultsKeepReopenSemantics() throws {
        for nullable in [false, true] {
            let definition = try schema(nullable: nullable, required: false,
                                        defaultID: "default:1", includesArray: true)
            let session = FormKitRenderer().makeFormSession(schemaJSON: definition)
            let selection = try context(session).selection()
            selection.clear(isRequired: false)
            let array = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/assets" })
            session.setArrayValue([.string("asset:1")], for: array)
            if nullable {
                XCTAssertTrue(try object(session)["choice"] is NSNull)
            } else {
                XCTAssertNil(try object(session)["choice"])
            }
            let reopened = FormKitRenderer().makeFormSession(schemaJSON: definition,
                                                            instanceJSON: session.currentInstanceJSON)
            if nullable {
                XCTAssertTrue(try object(reopened)["choice"] is NSNull)
            } else {
                XCTAssertEqual(try object(reopened)["choice"] as? String, "default:1")
            }
        }
    }

    private func editUnrelatedField(_ session: FormKitSession) throws {
        let note = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/note" })
        session.setStringValue("Unrelated edit", for: note)
    }

    private func field(_ session: FormKitSession) throws -> FormKitFieldDescriptor {
        try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/choice" })
    }

    private func context(_ session: FormKitSession) throws -> FormKitDynamicOptionsContext {
        .field(FormKitFieldComponentContext(
            session: session, field: try field(session), errors: [], state: .normal,
            isEditingLocked: false, style: .init(), uploadHandler: nil
        ))
    }

    private func object(_ session: FormKitSession) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(session.currentInstanceJSON.utf8)) as? [String: Any])
    }

    private func schema(nullable: Bool, required: Bool, defaultID: String? = nil,
                        annotation: String = "dynamic-options", constraints: [String: Any] = [:],
                        includesArray: Bool = false) throws -> String
    {
        var choice = constraints
        choice["type"] = nullable ? ["string", "null"] : "string"
        choice["x-formkit-ui-component"] = annotation
        if let defaultID {
            choice["default"] = defaultID
        }
        var properties: [String: Any] = ["choice": choice, "note": ["type": "string"]]
        if includesArray {
            properties["assets"] = ["type": "array", "items": ["type": "string"]]
        }
        let definition: [String: Any] = [
            "type": "object", "required": required ? ["choice"] : [],
            "properties": properties
        ]
        return try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: definition), encoding: .utf8))
    }
}
