import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitComponentTests: XCTestCase {
    func testUIComponentAnnotationsPropagateToFieldsAndSections() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: FormKitComponentTestFixtures.componentSchema,
            instanceJSON: nil
        )

        XCTAssertEqual(field(named: "license", in: session)?.uiComponent, .fileField)
        XCTAssertEqual(field(named: "signature", in: session)?.uiComponent, .signaturePad)
        XCTAssertEqual(
            session.renderPlan.sections.first(where: { $0.title == "Attachments" })?.uiComponent,
            .multipleFileField
        )

        let itemAnnotatedSection = try XCTUnwrap(
            session.renderPlan.sections.first(where: { $0.title == "Item Annotated Attachments" })
        )
        let descriptor = try XCTUnwrap(itemAnnotatedSection.arrayDescriptor)
        let rowFieldID = try XCTUnwrap(descriptor.rows.first?.fieldIDs.first)
        let rowField = try XCTUnwrap(session.renderPlan.fields.first(where: { $0.id == rowFieldID }))
        XCTAssertEqual(rowField.uiComponent, .signaturePad)
    }

    func testComponentRegistryResolvesOnlyCompatibleFieldComponents() throws {
        let schema =
            """
            {
              "type": "object",
              "properties": {
                "file": {
                  "type": "string",
                  "format": "uri",
                  "x-formkit-ui-component": "file-field"
                },
                "signature": {
                  "type": "string",
                  "x-formkit-ui-component": "signature-pad"
                },
                "numberFile": {
                  "type": "number",
                  "x-formkit-ui-component": "file-field"
                },
                "enumFile": {
                  "type": "string",
                  "enum": ["A", "B"],
                  "x-formkit-ui-component": "file-field"
                }
              }
            }
            """
        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)

        XCTAssertNotNil(fieldComponent(for: tryUnwrapField("file", in: session), session: session))
        XCTAssertNotNil(fieldComponent(for: tryUnwrapField("signature", in: session), session: session))
        XCTAssertNil(fieldComponent(for: tryUnwrapField("numberFile", in: session), session: session))
        XCTAssertNil(fieldComponent(for: tryUnwrapField("enumFile", in: session), session: session))
    }

    func testComponentRegistryResolvesOnlyCompatibleArrayComponents() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: FormKitComponentTestFixtures.arrayCompatibilitySchema,
            instanceJSON: nil
        )
        let filesSection = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.propertyKey == "files" }))
        let numbersSection = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.propertyKey == "numbers" }))
        let enumSection = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.propertyKey == "enumFiles" }))
        let constSection = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.propertyKey == "constFiles" }))
        let genericSection = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.propertyKey == "generic" }))

        XCTAssertNotNil(arrayComponent(for: filesSection, session: session))
        XCTAssertNil(arrayComponent(for: numbersSection, session: session))
        XCTAssertNil(arrayComponent(for: enumSection, session: session))
        XCTAssertNil(arrayComponent(for: constSection, session: session))
        XCTAssertNil(arrayComponent(for: genericSection, session: session))
    }

    func testSectionArrayValueSetterReplacesAndClearsArrayValues() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: FormKitComponentTestFixtures.multipleFileSchema,
            instanceJSON: nil
        )
        let section = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.title == "Attachments" }))
        let startingRevision = session.revision

        session.setArrayValue(
            [
                .string("https://example.com/a.pdf"),
                .string("https://example.com/b.pdf")
            ],
            for: section
        )

        XCTAssertGreaterThan(session.revision, startingRevision)
        XCTAssertEqual(
            session.arrayValue(for: section),
            [
                .string("https://example.com/a.pdf"),
                .string("https://example.com/b.pdf")
            ]
        )
        var jsonObject = try decodeJSONObject(session.currentInstanceJSON)
        XCTAssertEqual(
            jsonObject["attachments"] as? [String],
            ["https://example.com/a.pdf", "https://example.com/b.pdf"]
        )

        let updatedSection = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.id == section.id }))
        session.setArrayValue(nil, for: updatedSection)

        jsonObject = try decodeJSONObject(session.currentInstanceJSON)
        XCTAssertNil(jsonObject["attachments"])
        XCTAssertNil(session.arrayValue(for: section))
    }

    func testMultipleFileUploadsReplaceMinimumItemPlaceholdersAtMaximumCapacity() throws {
        let schema =
            """
            {
              "type": "object",
              "properties": {
                "attachments": {
                  "type": "array",
                  "minItems": 2,
                  "maxItems": 2,
                  "x-formkit-ui-component": "multiple-file-field",
                  "items": {
                    "type": "string",
                    "format": "uri"
                  }
                }
              }
            }
            """
        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)
        let section = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.propertyKey == "attachments" }))
        let placeholders = try XCTUnwrap(session.arrayValue(for: section))

        XCTAssertEqual(placeholders, [.string(""), .string("")])
        XCTAssertEqual(FormKitMultipleFileField.occupiedValueCount(in: placeholders), 0)

        let uploadedValues = FormKitMultipleFileField.replacingVacancies(
            in: placeholders,
            with: [
                .string("https://example.com/a.pdf"),
                .string("https://example.com/b.pdf")
            ],
            maxItems: 2
        )
        session.setArrayValue(uploadedValues, for: section)

        let jsonObject = try decodeJSONObject(session.currentInstanceJSON)
        XCTAssertEqual(
            jsonObject["attachments"] as? [String],
            ["https://example.com/a.pdf", "https://example.com/b.pdf"]
        )
        XCTAssertEqual(
            FormKitMultipleFileField.replacingVacancies(
                in: [.string(""), .string("https://example.com/existing.pdf")],
                with: [.string("https://example.com/new.pdf")],
                maxItems: 2
            ),
            [
                .string("https://example.com/existing.pdf"),
                .string("https://example.com/new.pdf")
            ]
        )
    }

    func testClearingNonnullableFileComponentsKeepsBlankValues() throws {
        let schema =
            """
            {
              "type": "object",
              "properties": {
                "file": {
                  "type": "string",
                  "format": "uri",
                  "x-formkit-ui-component": "file-field"
                },
                "signature": {
                  "type": "string",
                  "format": "uri",
                  "x-formkit-ui-component": "signature-pad"
                }
              }
            }
            """
        let instance =
            """
            {
              "file": "https://example.com/file.pdf",
              "signature": "https://example.com/signature.png"
            }
            """
        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: instance)

        session.clearValue(for: tryUnwrapField("file", in: session))
        session.clearValue(for: tryUnwrapField("signature", in: session))

        let jsonObject = try decodeJSONObject(session.currentInstanceJSON)
        XCTAssertEqual(jsonObject["file"] as? String, "")
        XCTAssertEqual(jsonObject["signature"] as? String, "")
    }

    func testUploadURLsAreTrimmedAndBlankURLsAreRejected() {
        XCTAssertEqual("  https://example.com/file.pdf \n".formKitNonEmpty, "https://example.com/file.pdf")
        XCTAssertNil(" \n\t".formKitNonEmpty)
    }

    private func fieldComponent(
        for field: FormKitFieldDescriptor,
        session: FormKitSession
    ) -> Any? {
        FormKitComponentRegistry.fieldInput(for: componentContext(for: field, session: session))
    }

    private func arrayComponent(
        for section: FormKitRenderPlan.SectionDescriptor,
        session: FormKitSession
    ) -> Any? {
        FormKitComponentRegistry.arraySection(for: arrayComponentContext(for: section, session: session))
    }

    private func componentContext(
        for field: FormKitFieldDescriptor,
        session: FormKitSession
    ) -> FormKitFieldComponentContext {
        FormKitFieldComponentContext(
            session: session,
            field: field,
            errors: [],
            state: .normal,
            isEditingLocked: false,
            style: .init(),
            uploadHandler: nil
        )
    }

    private func arrayComponentContext(
        for section: FormKitRenderPlan.SectionDescriptor,
        session: FormKitSession,
        labels: FormKitLabels = .init()
    ) -> FormKitArraySectionComponentContext {
        FormKitArraySectionComponentContext(
            session: session,
            section: section,
            descriptor: section.arrayDescriptor!,
            errors: [],
            isEditingLocked: false,
            style: .init(),
            labels: labels,
            uploadHandler: nil
        )
    }

    private func field(named propertyKey: String, in session: FormKitSession) -> FormKitFieldDescriptor? {
        session.renderPlan.fields.first(where: { $0.propertyKey == propertyKey })
    }

    private func tryUnwrapField(
        _ propertyKey: String,
        in session: FormKitSession,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> FormKitFieldDescriptor {
        guard let field = field(named: propertyKey, in: session) else {
            XCTFail("Missing field \(propertyKey)", file: file, line: line)
            fatalError("Missing field \(propertyKey)")
        }
        return field
    }

    private func decodeJSONObject(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

}

extension FormKitComponentTests {
    func testMultipleFileComponentReceivesConfiguredLabels() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: FormKitComponentTestFixtures.multipleFileSchema,
            instanceJSON: nil
        )
        let section = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.title == "Attachments" }))
        let labels = FormKitLabels(minimumItemsPrefix: "At least", maximumItemsPrefix: "At most")
        let component = FormKitMultipleFileField(
            context: arrayComponentContext(for: section, session: session, labels: labels)
        )

        XCTAssertEqual(component.labels, labels)
    }
}
