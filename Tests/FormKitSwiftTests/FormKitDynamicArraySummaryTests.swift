import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitDynamicArraySummaryTests: XCTestCase {
    func testRequiredMissingArrayAppearsInNormalAndToolSummariesWithoutReadWrites() throws {
        for minimum in [0, 1] {
            let session = FormKitRenderer().makeFormSession(schemaJSON: try schema(minimum: minimum))
            let before = session.currentInstanceJSON
            let revision = session.revision
            let summary = session.formSummary()
            XCTAssertTrue(summary.missingRequired.isEmpty)
            XCTAssertEqual(summary.missingRequiredArraySections.map(\.pointer), ["#/selection/equipment"])
            XCTAssertEqual(summary.pages.first?.total, 1)
            XCTAssertEqual(summary.pages.first?.answered, 0)
            XCTAssertEqual(summary.pages.first?.status, .notStarted)
            XCTAssertTrue(session.makeToolContext().summary.contains("Selection › Equipment"))
            XCTAssertFalse(session.makeToolContext().fields.contains { $0.pointer == "/selection/equipment" })
            XCTAssertFalse(session.hasAttemptedValidation)
            XCTAssertEqual(session.currentInstanceJSON, before)
            XCTAssertEqual(session.revision, revision)
            XCTAssertFalse(session.validate())
            let section = try section(session)
            let messages = session.errorMessages(for: section)
            XCTAssertFalse(messages.isEmpty)
            XCTAssertTrue(messages.allSatisfy(session.toolValidationMessages().contains))
            XCTAssertEqual(session.formSummary().pages.first?.status, .needsAttention)
        }
    }

    func testExplicitEmptyAndLiteralIdentifiersAnswerOneCollectionQuestion() throws {
        let zero = FormKitRenderer().makeFormSession(schemaJSON: try schema(minimum: 0),
                                                     instanceJSON: #"{"selection":{"equipment":[]}}"#)
        XCTAssertTrue(zero.formSummary().missingRequiredArraySections.isEmpty)
        XCTAssertEqual(zero.formSummary().pages.first?.answered, 1)
        XCTAssertEqual(zero.formSummary().pages.first?.total, 1)
        XCTAssertTrue(zero.validate())

        let session = FormKitRenderer().makeFormSession(schemaJSON: try schema(minimum: 1),
                                                        instanceJSON: #"{"selection":{"equipment":[]}}"#)
        XCTAssertEqual(session.formSummary().missingRequiredArraySections.count, 1)
        let context = try context(session)
        context.selection().choose("", isRequired: true)
        XCTAssertTrue(session.formSummary().missingRequiredArraySections.isEmpty)
        XCTAssertTrue(session.formSummary().missingRequired.isEmpty)
        XCTAssertEqual(session.formSummary().pages.first?.answered, 1)
        XCTAssertEqual(session.formSummary().pages.first?.total, 1)
        XCTAssertTrue(session.validate())
        context.selection().choose("second", isRequired: true)
        XCTAssertEqual(session.formSummary().pages.first?.total, 1)
        XCTAssertEqual(session.formSummary().pages.first?.status, .done)
        XCTAssertFalse(session.makeToolContext().summary.contains("Missing required"))
    }

    func testArrayDefaultsAreNotUserAnswersAndDoNotCreateMissingItemFields() throws {
        for (minimum, values) in [(0, []), (1, ["default"]), (1, []), (2, ["default"])] {
            let session = FormKitRenderer().makeFormSession(
                schemaJSON: try schema(minimum: minimum, defaultValue: values)
            )
            XCTAssertEqual(session.formSummary().pages.first?.total, 1)
            XCTAssertEqual(session.formSummary().pages.first?.answered, 0)
            XCTAssertTrue(session.formSummary().missingRequired.isEmpty)
            XCTAssertEqual(session.formSummary().missingRequiredArraySections.isEmpty, values.count >= minimum)
            if values.count >= minimum {
                session.setArrayValue(values.map(FormKitJSONValue.string), for: try section(session))
                XCTAssertEqual(session.formSummary().pages.first?.answered, 1)
            }
        }
        let fallback = FormKitRenderer().makeFormSession(schemaJSON: try schema(minimum: 0))
        fallback.appendArrayRow(to: try section(fallback))
        XCTAssertEqual(fallback.formSummary().pages.first?.answered, 0)
        let item = try XCTUnwrap(fallback.renderPlan.fields.first { $0.parentPointer == "#/selection/equipment" })
        fallback.setStringValue("", for: item)
        XCTAssertEqual(fallback.formSummary().pages.first?.answered, 1)
    }

    func testOptionalAbsenceAndInactiveParentAreNotMissingButPresentBelowMinimumIs() throws {
        let optionalArray = FormKitRenderer().makeFormSession(
            schemaJSON: try schema(minimum: 1, arrayRequired: false)
        )
        XCTAssertTrue(optionalArray.formSummary().missingRequiredArraySections.isEmpty)
        XCTAssertTrue(optionalArray.validate())
        let optionalParent = FormKitRenderer().makeFormSession(
            schemaJSON: try schema(minimum: 1, parentRequired: false)
        )
        XCTAssertTrue(optionalParent.formSummary().missingRequiredArraySections.isEmpty)
        XCTAssertTrue(optionalParent.validate())
        XCTAssertEqual(optionalParent.formSummary().pages.first?.total, 1)
        for (arrayRequired, minimum, instance) in [
            (true, 1, #"{"selection":{}}"#),
            (false, 1, #"{"selection":{"equipment":[]}}"#),
            (false, 2, #"{"selection":{"equipment":["one"]}}"#)
        ] {
            let present = FormKitRenderer().makeFormSession(
                schemaJSON: try schema(minimum: minimum, arrayRequired: arrayRequired, parentRequired: false),
                instanceJSON: instance
            )
            XCTAssertEqual(present.formSummary().missingRequiredArraySections.count, 1)
            XCTAssertFalse(present.validate())
        }
    }

    func testRawItemCountAndValidationDiagnosticsRemainSeparateFromQuestionPresence() throws {
        let duplicate = FormKitRenderer().makeFormSession(schemaJSON: try schema(minimum: 2),
                                                          instanceJSON: #"{"selection":{"equipment":["",""]}}"#)
        let before = duplicate.currentInstanceJSON
        XCTAssertTrue(duplicate.formSummary().missingRequiredArraySections.isEmpty)
        XCTAssertEqual(duplicate.formSummary().pages.first?.answered, 1)
        XCTAssertEqual(duplicate.currentInstanceJSON, before)
        XCTAssertTrue(duplicate.validate())

        let constrained = FormKitRenderer().makeFormSession(
            schemaJSON: try schema(minimum: 1, itemConstraints: ["minLength": 1]),
            instanceJSON: #"{"selection":{"equipment":[""]}}"#
        )
        XCTAssertTrue(constrained.formSummary().missingRequiredArraySections.isEmpty)
        XCTAssertFalse(constrained.validate())
        XCTAssertEqual(constrained.formSummary().pages.first?.status, .needsAttention)
        let array = try section(constrained)
        constrained.arrayErrors[array.id] = ["Array issue", "Array issue"]
        XCTAssertEqual(constrained.toolValidationMessages().count { $0 == "Array issue" }, 1)
    }

    private func section(_ session: FormKitSession) throws -> FormKitRenderPlan.SectionDescriptor {
        try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/selection/equipment" })
    }

    private func context(_ session: FormKitSession) throws -> FormKitDynamicOptionsContext {
        let section = try section(session)
        return .arraySection(FormKitArraySectionComponentContext(
            session: session, section: section, descriptor: try XCTUnwrap(section.arrayDescriptor), errors: [],
            isEditingLocked: false, style: .init(), labels: .init(), uploadHandler: nil
        ))
    }

    private func schema(minimum: Int, arrayRequired: Bool = true, parentRequired: Bool = true,
                        defaultValue: [String]? = nil, itemConstraints: [String: Any] = [:]) throws -> String
    {
        var item = itemConstraints
        item["type"] = "string"
        var array: [String: Any] = ["type": "array", "title": "Equipment", "minItems": minimum,
                                    "items": item, "x-formkit-ui-component": "dynamic-options"]
        if let defaultValue {
            array["default"] = defaultValue
        }
        let definition: [String: Any] = [
            "type": "object", "x-formkit-layout": "section-pages", "required": parentRequired ? ["selection"] : [],
            "properties": [
                "selection": ["type": "object", "title": "Selection", "x-formkit-order": 0,
                               "required": arrayRequired ? ["equipment"] : [], "properties": ["equipment": array]],
                "details": ["type": "object", "title": "Details", "x-formkit-order": 1,
                             "properties": ["note": ["type": "string"]]]
            ]
        ]
        return try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: definition), encoding: .utf8))
    }
}
