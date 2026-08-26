import Foundation
import Observation
import XCTest
@testable import FormKitSwift

extension FormKitRendererTests {
    func testProvidedInstancePopulatesFields() {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: supportedSchema,
            instanceJSON: populatedInstance
        )

        XCTAssertEqual(session.stringValue(for: tryUnwrapField("fullName", in: session)), "Taylor Jordan")
        XCTAssertEqual(session.stringValue(for: tryUnwrapField("email", in: session)), "taylor@example.com")
        XCTAssertEqual(session.stringValue(for: tryUnwrapField("website", in: session)), "https://example.com")
        XCTAssertFalse(session.booleanValue(for: tryUnwrapField("sendUpdates", in: session)))
        XCTAssertEqual(session.selectedEnumChoiceID(for: tryUnwrapField("priority", in: session)), "string:Expedited")
    }

    func testSchemaDefaultsPopulateMissingValues() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: supportedSchema, instanceJSON: nil)

        XCTAssertTrue(session.booleanValue(for: tryUnwrapField("sendUpdates", in: session)))
        XCTAssertEqual(session.selectedEnumChoiceID(for: tryUnwrapField("priority", in: session)), "string:Standard")
        XCTAssertTrue(session.currentInstanceJSON.contains("\"priority\" : \"Standard\""))
    }

    func testEditedValuesSerializeBackIntoJSON() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: supportedSchema, instanceJSON: nil)

        let nameField = tryUnwrapField("fullName", in: session)
        let emailField = tryUnwrapField("email", in: session)
        let websiteField = tryUnwrapField("website", in: session)

        session.setStringValue("Ada Lovelace", for: nameField)
        session.setStringValue("ada@example.com", for: emailField)
        session.setStringValue("https://lovelace.example", for: websiteField)
        session.setBooleanValue(false, for: tryUnwrapField("sendUpdates", in: session))

        let jsonObject = try decodeJSONObject(session.currentInstanceJSON)
        let contact = try XCTUnwrap(jsonObject["contact"] as? [String: Any])

        XCTAssertEqual(contact["fullName"] as? String, "Ada Lovelace")
        XCTAssertEqual(contact["email"] as? String, "ada@example.com")
        XCTAssertEqual(contact["website"] as? String, "https://lovelace.example")
        XCTAssertEqual(contact["sendUpdates"] as? Bool, false)
        XCTAssertEqual(jsonObject["priority"] as? String, "Standard")
    }

    func testEmptyTextUsesNullOrBlankByNullability() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "nullable": { "type": ["string", "null"] },
                "defaulted": { "type": ["string", "null"], "default": "" },
                "optional": { "type": "string" },
                "required": { "type": "string" }
              },
              "required": ["required"]
            }
            """,
            instanceJSON: #"{"nullable":" \t","required":"value"}"#,
            validationBehavior: .onDemandOnly
        )
        let nullableField = tryUnwrapField("nullable", in: session)
        let optionalField = tryUnwrapField("optional", in: session)
        let requiredField = tryUnwrapField("required", in: session)

        var object = try decodeJSONObject(session.currentInstanceJSON)
        XCTAssertTrue(object["nullable"] is NSNull)
        XCTAssertTrue(object["defaulted"] is NSNull)

        session.setStringValue("", for: optionalField)
        session.setStringValue(" \t", for: requiredField)
        session.setStringValue("", for: nullableField)

        object = try decodeJSONObject(session.currentInstanceJSON)
        XCTAssertEqual(object["optional"] as? String, "")
        XCTAssertEqual(object["required"] as? String, " \t")
        XCTAssertTrue(object["nullable"] is NSNull)
        XCTAssertFalse(session.validate())
        XCTAssertEqual(session.errorMessages(for: requiredField), ["This field is required."])

        session.setNullSelection(true, for: requiredField)
        object = try decodeJSONObject(session.currentInstanceJSON)
        XCTAssertEqual(object["required"] as? String, " \t")

        session.setStringValue("value", for: nullableField)
        session.setStringValue(" \n", for: nullableField)
        XCTAssertTrue(try decodeJSONObject(session.currentInstanceJSON)["nullable"] is NSNull)
    }

    func testEnumConstraintDeterminesEffectiveNullability() throws {
        let schema =
            """
            {
              "type": "object",
              "properties": {
                "concrete": {
                  "type": ["string", "null"],
                  "enum": ["A"]
                },
                "nullable": {
                  "type": ["string", "null"],
                  "enum": ["A", null]
                }
              }
            }
            """
        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)
        let concreteField = tryUnwrapField("concrete", in: session)
        let nullableField = tryUnwrapField("nullable", in: session)

        XCTAssertFalse(concreteField.allowsNull)
        XCTAssertTrue(nullableField.allowsNull)
        XCTAssertEqual(nullableField.enumOptions.map(\.value), [.string("A"), .null])
    }
}

extension FormKitRendererTests {
    func testArrayItemsRenderRowsAndSerializeBack() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: arraySchema, instanceJSON: nil)

        let tagsSection = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.title == "Tags" }))
        let contactsSection = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.title == "Contacts" }))
        let tagsDescriptor = try XCTUnwrap(tagsSection.arrayDescriptor)
        let contactsDescriptor = try XCTUnwrap(contactsSection.arrayDescriptor)

        XCTAssertEqual(tagsDescriptor.rows.count, 1)
        XCTAssertEqual(contactsDescriptor.rows.count, 0)

        let firstTagFieldID = try XCTUnwrap(tagsDescriptor.rows.first?.fieldIDs.first)
        let firstTagField = try XCTUnwrap(session.renderPlan.fields.first(where: { $0.id == firstTagFieldID }))
        session.setStringValue("Electrical", for: firstTagField)
        session.appendArrayRow(to: contactsSection)

        let updatedContactsSection = try XCTUnwrap(
            session.renderPlan.sections.first(where: { $0.id == contactsSection.id })
        )
        let updatedContactsDescriptor = try XCTUnwrap(updatedContactsSection.arrayDescriptor)
        XCTAssertEqual(updatedContactsDescriptor.rows.count, 1)

        let contactRowSectionID = try XCTUnwrap(updatedContactsDescriptor.rows.first?.sectionIDs.first)
        let contactRowSection = try XCTUnwrap(
            session.renderPlan.sections.first(where: { $0.id == contactRowSectionID })
        )

        let contactNameFieldID = try XCTUnwrap(contactRowSection.fieldIDs.first(where: { $0.hasSuffix("/name") }))
        let contactEmailFieldID = try XCTUnwrap(contactRowSection.fieldIDs.first(where: { $0.hasSuffix("/email") }))
        let contactNameField = try XCTUnwrap(session.renderPlan.fields.first(where: { $0.id == contactNameFieldID }))
        let contactEmailField = try XCTUnwrap(session.renderPlan.fields.first(where: { $0.id == contactEmailFieldID }))

        session.setStringValue("Taylor Jordan", for: contactNameField)
        session.setStringValue("taylor@example.com", for: contactEmailField)

        let jsonObject = try decodeJSONObject(session.currentInstanceJSON)
        XCTAssertEqual(jsonObject["tags"] as? [String], ["Electrical"])

        let contacts = try XCTUnwrap(jsonObject["contacts"] as? [[String: Any]])
        XCTAssertEqual(contacts.count, 1)
        XCTAssertEqual(contacts[0]["name"] as? String, "Taylor Jordan")
        XCTAssertEqual(contacts[0]["email"] as? String, "taylor@example.com")
        XCTAssertEqual(contacts[0]["primary"] as? Bool, false)
    }

    func testRemovingArrayRowReindexesFollowingFields() throws {
        let instance =
            """
            {
              "tags": ["Electrical", "Weekend"]
            }
            """
        let session = FormKitRenderer().makeFormSession(schemaJSON: arraySchema, instanceJSON: instance)
        let tagsSection = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.title == "Tags" }))
        let tagsDescriptor = try XCTUnwrap(tagsSection.arrayDescriptor)

        XCTAssertEqual(tagsDescriptor.rows.count, 2)

        session.removeArrayRow(try XCTUnwrap(tagsDescriptor.rows.first), from: tagsSection)

        let updatedTagsSection = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.id == tagsSection.id }))
        let updatedTagsDescriptor = try XCTUnwrap(updatedTagsSection.arrayDescriptor)
        XCTAssertEqual(updatedTagsDescriptor.rows.count, 1)

        let remainingFieldID = try XCTUnwrap(updatedTagsDescriptor.rows.first?.fieldIDs.first)
        let remainingField = try XCTUnwrap(session.renderPlan.fields.first(where: { $0.id == remainingFieldID }))
        XCTAssertEqual(session.stringValue(for: remainingField), "Weekend")
    }

}

private func makeStaticRenderPlanField() -> FormKitFieldDescriptor {
    FormKitFieldDescriptor(
        id: "name",
        pointer: "/name",
        parentPointer: "",
        propertyKey: "name",
        title: "Name",
        description: nil,
        scalarType: .string,
        enumOptions: [],
        isRequired: false,
        allowsNull: false,
        defaultValue: nil,
        uiComponent: nil,
        renderBehavior: .hide,
        conditionalState: .active,
        accessibilityIdentifier: "json_schema_field_name"
    )
}

private func makeStaticRenderPlan(field: FormKitFieldDescriptor) -> FormKitRenderPlan {
    let section = FormKitRenderPlan.SectionDescriptor(
        id: "root",
        pointer: "",
        parentPointer: nil,
        propertyKey: nil,
        title: "Test",
        description: nil,
        depth: 0,
        isRequired: true,
        order: 0,
        fieldIDs: [field.id],
        propertyOrder: [field.propertyKey],
        ownerArrayRowID: nil,
        uiComponent: nil,
        renderBehavior: .hide,
        conditionalState: .active,
        arrayDescriptor: nil
    )
    return FormKitRenderPlan(
        title: "Test",
        description: nil,
        sections: [section],
        fields: [field],
        fieldOrder: [field.id],
        unsupportedReasons: []
    )
}

extension FormKitRendererTests {
    func testStaticFieldEditDoesNotPublishRenderPlanWhenPlanIsUnchanged() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: supportedSchema, instanceJSON: nil)
        let nameField = tryUnwrapField("fullName", in: session)
        let invalidationCount = InvalidationCounter()

        withObservationTracking {
            _ = session.renderPlan
        } onChange: {
            invalidationCount.increment()
        }

        session.setStringValue("Ada", for: nameField)

        XCTAssertEqual(invalidationCount.value, 0)
    }

    func testStaticFieldEditDoesNotRefreshRenderPlan() throws {
        let field = makeStaticRenderPlanField()
        let plan = makeStaticRenderPlan(field: field)
        var renderPlanProviderCallCount = 0
        let session = FormKitSession(
            renderPlan: plan,
            validator: nil,
            initialInstance: nil,
            initialFieldValues: [field.id: Optional<FormKitFieldDescriptor.PrimitiveValue>.none],
            validationBehavior: .onDemandOnly,
            refreshesRenderPlanOnFieldEdit: false,
            renderPlanProvider: { _ in
                renderPlanProviderCallCount += 1
                return plan
            },
            fieldValueSeedProvider: { _, _ in
                [field.id: Optional<FormKitFieldDescriptor.PrimitiveValue>.none]
            }
        )

        XCTAssertEqual(renderPlanProviderCallCount, 1)

        session.setStringValue("Ada", for: field)

        XCTAssertEqual(renderPlanProviderCallCount, 1)
    }
}

extension FormKitRendererTests {
    func testArrayValidationMapsItemAndArrayLevelErrors() throws {
        let schema =
            """
            {
              "title": "Checklist",
              "type": "object",
              "properties": {
                "items": {
                  "type": "array",
                  "title": "Items",
                  "uniqueItems": true,
                  "items": {
                    "type": "string",
                    "title": "Item",
                    "minLength": 1
                  }
                }
              }
            }
            """
        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)
        let itemsSection = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.title == "Items" }))
        session.appendArrayRow(to: itemsSection)
        session.appendArrayRow(to: itemsSection)

        let descriptor = try XCTUnwrap(
            session.renderPlan.sections.first(where: { $0.id == itemsSection.id })?.arrayDescriptor
        )
        XCTAssertEqual(descriptor.rows.count, 2)
        let firstFieldID = try XCTUnwrap(descriptor.rows[0].fieldIDs.first)
        let secondFieldID = try XCTUnwrap(descriptor.rows[1].fieldIDs.first)
        let firstField = try XCTUnwrap(session.renderPlan.fields.first(where: { $0.id == firstFieldID }))
        let secondField = try XCTUnwrap(session.renderPlan.fields.first(where: { $0.id == secondFieldID }))

        session.setStringValue("Alpha", for: firstField)
        session.setStringValue("Alpha", for: secondField)

        XCTAssertFalse(session.validate())
        XCTAssertFalse(session.errorMessages(for: itemsSection).isEmpty)
    }
}
