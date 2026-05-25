import Foundation
import Observation
import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitRendererTests: XCTestCase {
    private let supportedSchema =
        """
        {
          "title": "Project Intake",
          "type": "object",
          "properties": {
            "contact": {
              "type": "object",
              "title": "Contact",
              "properties": {
                "fullName": {
                  "type": "string",
                  "title": "Full Name",
                  "minLength": 1
                },
                "email": {
                  "type": "string",
                  "format": "email",
                  "title": "Email"
                },
                "website": {
                  "type": ["string", "null"],
                  "format": "uri",
                  "title": "Website"
                },
                "sendUpdates": {
                  "type": "boolean",
                  "title": "Send Updates",
                  "default": true
                }
              },
              "required": ["fullName", "email"]
            },
            "visitDate": {
              "type": "string",
              "format": "date",
              "title": "Visit Date"
            },
            "priority": {
              "title": "Priority",
              "enum": ["Standard", "Expedited", "Critical"],
              "default": "Standard"
            }
          },
          "required": ["contact", "visitDate", "priority"]
        }
        """

    private let populatedInstance =
        """
        {
          "contact": {
            "fullName": "Taylor Jordan",
            "email": "taylor@example.com",
            "website": "https://example.com",
            "sendUpdates": false
          },
          "visitDate": "2026-03-12",
          "priority": "Expedited"
        }
        """

    private let unsupportedSchema =
        """
        {
          "title": "Unsupported",
          "type": "object",
          "properties": {
            "items": {
              "type": "array",
              "prefixItems": [
                {
                  "type": "string"
                }
              ]
            }
          }
        }
        """

    private let arraySchema =
        """
        {
          "title": "Work Crew",
          "type": "object",
          "properties": {
            "tags": {
              "type": "array",
              "title": "Tags",
              "items": {
                "type": "string",
                "title": "Tag"
              },
              "minItems": 1
            },
            "contacts": {
              "type": "array",
              "title": "Contacts",
              "items": {
                "type": "object",
                "title": "Contact",
                "properties": {
                  "name": {
                    "type": "string",
                    "title": "Name"
                  },
                  "email": {
                    "type": "string",
                    "format": "email",
                    "title": "Email"
                  },
                  "primary": {
                    "type": "boolean",
                    "title": "Primary Contact",
                    "default": false
                  }
                },
                "required": ["name", "email"]
              }
            }
          }
        }
        """

    private let conditionalSchema =
        """
        {
          "title": "Conditional",
          "type": "object",
          "properties": {
            "mode": {
              "title": "Mode",
              "enum": ["ABC", "XYZ"],
              "default": "ABC"
            }
          },
          "required": ["mode"],
          "if": {
            "properties": {
              "mode": { "const": "XYZ" }
            },
            "required": ["mode"]
          },
          "then": {
            "properties": {
              "anotherField": {
                "type": "string",
                "title": "Another Field"
              }
            },
            "required": ["anotherField"]
          },
          "else": {
            "properties": {
              "fallbackField": {
                "type": "string",
                "title": "Fallback Field"
              }
            }
          }
        }
        """

    func testSupportedSchemaProducesFieldPlan() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: supportedSchema, instanceJSON: nil)

        XCTAssertTrue(session.renderPlan.isSupported)
        XCTAssertEqual(session.renderPlan.title, "Project Intake")
        XCTAssertEqual(session.renderPlan.sections.map(\.title), ["Project Intake", "Contact"])
        XCTAssertEqual(
            session.renderPlan.sections.first(where: { $0.title == "Project Intake" })?.fieldIDs,
            ["#/visitDate", "#/priority"]
        )
        XCTAssertEqual(
            session.renderPlan.sections.first(where: { $0.title == "Contact" })?.fieldIDs,
            ["#/contact/fullName", "#/contact/email", "#/contact/website", "#/contact/sendUpdates"]
        )
        XCTAssertEqual(
            session.renderPlan.fields.map(\.propertyKey),
            ["fullName", "email", "website", "sendUpdates", "visitDate", "priority"]
        )
        XCTAssertEqual(field(named: "website", in: session)?.scalarType, .uri)
        XCTAssertEqual(field(named: "priority", in: session)?.enumOptions.map(\.title), ["Standard", "Expedited", "Critical"])
    }

    func testRendererPreservesDeclaredPropertyOrder() throws {
        let schema =
            """
            {
              "title": "Ordering",
              "type": "object",
              "properties": {
                "zeta": {
                  "type": "string",
                  "title": "Zeta"
                },
                "alpha": {
                  "type": "string",
                  "title": "Alpha"
                },
                "middle": {
                  "type": "string",
                  "title": "Middle"
                }
              },
              "required": ["alpha"]
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)

        XCTAssertEqual(
            session.renderPlan.sections.first(where: { $0.title == "Ordering" })?.fieldIDs,
            ["#/zeta", "#/alpha", "#/middle"]
        )
        XCTAssertEqual(session.renderPlan.fields.map(\.propertyKey), ["zeta", "alpha", "middle"])
    }

    func testRendererPreservesReferencedPropertyOrder() throws {
        let schema =
            """
            {
              "title": "Reference Ordering",
              "type": "object",
              "properties": {
                "contact": {
                  "$ref": "#/$defs/contact_details"
                }
              },
              "$defs": {
                "contact_details": {
                  "title": "Contact Details",
                  "type": "object",
                  "properties": {
                    "full_name": {
                      "title": "Full Name",
                      "type": "string"
                    },
                    "email": {
                      "title": "Email",
                      "type": "string",
                      "format": "email"
                    },
                    "phone": {
                      "title": "Phone",
                      "type": "string"
                    }
                  },
                  "required": ["email"]
                }
              }
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)

        XCTAssertEqual(
            session.renderPlan.sections.first(where: { $0.title == "Contact Details" })?.fieldIDs,
            ["#/contact/full_name", "#/contact/email", "#/contact/phone"]
        )
        XCTAssertEqual(session.renderPlan.fields.map(\.propertyKey), ["full_name", "email", "phone"])
    }

    func testDetailPageRenderIndexPreservesRootContentOrder() throws {
        let schema =
            """
            {
              "$schema": "https://json-schema.org/draft/2020-12/schema",
              "title": "Feedback Form",
              "type": "object",
              "properties": {
                "contact_details": {
                  "title": "Contact Details",
                  "type": "object",
                  "properties": {
                    "full_name": {
                      "title": "Full Name",
                      "type": "string"
                    },
                    "email": {
                      "title": "Email",
                      "type": "string",
                      "format": "email"
                    }
                  },
                  "required": ["full_name", "email"]
                },
                "request_type": {
                  "title": "Request Type",
                  "type": "string",
                  "enum": ["Bug", "Feature", "Support"]
                },
                "bug_details": {
                  "title": "Bug Details",
                  "type": "object",
                  "properties": {
                    "severity": {
                      "title": "Severity",
                      "type": "string",
                      "enum": ["Low", "Medium", "High"]
                    }
                  }
                },
                "links": {
                  "title": "Related Links",
                  "type": "array",
                  "items": {
                    "type": "string"
                  }
                },
                "team_members": {
                  "title": "Team Members",
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "name": {
                        "title": "Name",
                        "type": "string"
                      }
                    }
                  }
                }
              },
              "required": ["request_type"]
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)
        let renderIndex = FormKitRenderIndex(renderPlan: session.renderPlan)
        let blockLabels = renderIndex.visibleRootBlocks.compactMap { block -> String? in
            switch block.kind {
            case .section(let sectionID):
                return renderIndex.section(sectionID)?.title
            case .fieldGroup(_, let fieldIDs):
                return fieldIDs
                    .compactMap { renderIndex.field($0)?.propertyKey }
                    .joined(separator: ",")
            }
        }

        XCTAssertEqual(
            blockLabels,
            ["Contact Details", "request_type", "Bug Details", "Related Links", "Team Members"]
        )
    }

    func testUnsupportedSchemaReturnsFailClosedPlan() {
        let session = FormKitRenderer().makeFormSession(schemaJSON: unsupportedSchema, instanceJSON: nil)

        XCTAssertFalse(session.renderPlan.isSupported)
        XCTAssertTrue(session.renderPlan.sections.isEmpty, "Unexpected sections: \(session.renderPlan.sections)")
        XCTAssertTrue(session.renderPlan.fields.isEmpty, "Unexpected fields: \(session.renderPlan.fields)")
        XCTAssertTrue(session.renderPlan.unsupportedReasons.contains(where: {
            $0.message.localizedCaseInsensitiveContains("prefixItems")
        }))
    }

    func testInvalidSchemaFallbackUsesUntitledJSONFormTitle() {
        let invalidJSONSession = FormKitRenderer().makeFormSession(schemaJSON: "{", instanceJSON: nil)
        let nonObjectRootSession = FormKitRenderer().makeFormSession(schemaJSON: "[]", instanceJSON: nil)

        XCTAssertEqual(invalidJSONSession.renderPlan.title, FormKitDefaults.untitledTitle)
        XCTAssertEqual(nonObjectRootSession.renderPlan.title, FormKitDefaults.untitledTitle)
        XCTAssertFalse(invalidJSONSession.renderPlan.isSupported)
        XCTAssertFalse(nonObjectRootSession.renderPlan.isSupported)
    }

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

        let updatedContactsSection = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.id == contactsSection.id }))
        let updatedContactsDescriptor = try XCTUnwrap(updatedContactsSection.arrayDescriptor)
        XCTAssertEqual(updatedContactsDescriptor.rows.count, 1)

        let contactRowSectionID = try XCTUnwrap(updatedContactsDescriptor.rows.first?.sectionIDs.first)
        let contactRowSection = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.id == contactRowSectionID }))

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
        let field = FormKitFieldDescriptor(
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
            renderBehavior: .hide,
            conditionalState: .active,
            accessibilityIdentifier: "json_schema_field_name"
        )
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
            renderBehavior: .hide,
            conditionalState: .active,
            arrayDescriptor: nil
        )
        let plan = FormKitRenderPlan(
            title: "Test",
            description: nil,
            sections: [section],
            fields: [field],
            fieldOrder: [field.id],
            unsupportedReasons: []
        )
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

    func testValidationMapsInlineAndFormLevelErrors() throws {
        let schema =
            """
            {
              "title": "Validation",
              "type": "object",
              "minProperties": 4,
              "properties": {
                "contact": {
                  "type": "object",
                  "properties": {
                    "fullName": {
                      "type": "string",
                      "minLength": 1
                    },
                    "email": {
                      "type": "string",
                      "format": "email"
                    }
                  },
                  "required": ["fullName", "email"]
                }
              },
              "required": ["contact"]
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)

        XCTAssertFalse(session.validate())
        XCTAssertEqual(session.errorMessages(for: tryUnwrapField("fullName", in: session)), ["This field is required."])
        XCTAssertEqual(session.errorMessages(for: tryUnwrapField("email", in: session)), ["This field is required."])
        XCTAssertEqual(session.firstInvalidFieldID, tryUnwrapField("fullName", in: session).id)
        XCTAssertNotNil(session.formErrorMessage)
        XCTAssertTrue(session.formErrorMessage?.localizedCaseInsensitiveContains("minimum") == true)
    }

    func testIfThenElseUpdatesVisibleFieldsAndSerialization() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: conditionalSchema, instanceJSON: nil)

        XCTAssertEqual(field(named: "mode", in: session)?.enumOptions.map(\.title), ["ABC", "XYZ"])
        XCTAssertNil(field(named: "anotherField", in: session))
        XCTAssertNotNil(field(named: "fallbackField", in: session))

        session.setSelectedEnumChoiceID("string:XYZ", for: tryUnwrapField("mode", in: session))

        XCTAssertNotNil(field(named: "anotherField", in: session))
        XCTAssertNil(field(named: "fallbackField", in: session))

        session.setStringValue("Visible now", for: tryUnwrapField("anotherField", in: session))
        let jsonObject = try decodeJSONObject(session.currentInstanceJSON)

        XCTAssertEqual(jsonObject["mode"] as? String, "XYZ")
        XCTAssertEqual(jsonObject["anotherField"] as? String, "Visible now")
        XCTAssertNil(jsonObject["fallbackField"])
    }

    func testDependentRequiredOnlyAppliesWhenTriggerIsPresent() throws {
        let schema =
            """
            {
              "title": "Dependencies",
              "type": "object",
              "properties": {
                "email": {
                  "type": "string",
                  "format": "email"
                },
                "phone": {
                  "type": "string"
                }
              },
              "dependentRequired": {
                "email": ["phone"]
              }
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)

        XCTAssertTrue(session.validate())

        session.setStringValue("person@example.com", for: tryUnwrapField("email", in: session))

        XCTAssertFalse(session.validate())
        XCTAssertEqual(
            session.errorMessages(for: tryUnwrapField("phone", in: session)),
            ["This field is required."]
        )
    }

    func testDependentSchemasAddsConditionalFields() throws {
        let schema =
            """
            {
              "title": "Dependent Schema",
              "type": "object",
              "properties": {
                "billingMode": {
                  "title": "Billing Mode",
                  "enum": ["Email", "Paper"]
                }
              },
              "dependentSchemas": {
                "billingMode": {
                  "properties": {
                    "billingEmail": {
                      "type": "string",
                      "format": "email",
                      "title": "Billing Email"
                    }
                  },
                  "required": ["billingEmail"]
                }
              }
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)

        XCTAssertNil(field(named: "billingEmail", in: session))

        session.setSelectedEnumChoiceID("string:Email", for: tryUnwrapField("billingMode", in: session))

        XCTAssertNotNil(field(named: "billingEmail", in: session))
        XCTAssertFalse(session.validate())
        XCTAssertEqual(
            session.errorMessages(for: tryUnwrapField("billingEmail", in: session)),
            ["This field is required."]
        )
    }

    func testAllOfAndOneOfMaterializeMatchingBranch() throws {
        let schema =
            """
            {
              "title": "Applicant",
              "type": "object",
              "properties": {
                "kind": {
                  "enum": ["person", "company"]
                }
              },
              "allOf": [
                {
                  "properties": {
                    "sharedCode": {
                      "type": "string",
                      "title": "Shared Code"
                    }
                  }
                }
              ],
              "oneOf": [
                {
                  "properties": {
                    "kind": { "const": "person" },
                    "firstName": {
                      "type": "string",
                      "title": "First Name"
                    }
                  },
                  "required": ["kind", "firstName"]
                },
                {
                  "properties": {
                    "kind": { "const": "company" },
                    "companyName": {
                      "type": "string",
                      "title": "Company Name"
                    }
                  },
                  "required": ["kind", "companyName"]
                }
              ]
            }
            """
        let instance =
            """
            {
              "kind": "company"
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: instance)

        XCTAssertNotNil(field(named: "sharedCode", in: session))
        XCTAssertNotNil(field(named: "companyName", in: session))
        XCTAssertNil(field(named: "firstName", in: session))
        XCTAssertTrue(tryUnwrapField("companyName", in: session).isRequired)
    }

    func testIfThenElseUpdatesVisibleFieldsAndPreservesHiddenDrafts() throws {
        let schema =
            """
            {
              "title": "Transport",
              "type": "object",
              "properties": {
                "transport": {
                  "title": "Transport",
                  "enum": ["car", "bike"],
                  "default": "car"
                }
              },
              "required": ["transport"],
              "if": {
                "properties": {
                  "transport": {
                    "const": "car"
                  }
                },
                "required": ["transport"]
              },
              "then": {
                "properties": {
                  "licensePlate": {
                    "type": "string",
                    "title": "License Plate"
                  }
                },
                "required": ["licensePlate"]
              },
              "else": {
                "properties": {
                  "helmetColor": {
                    "type": "string",
                    "title": "Helmet Color"
                  }
                },
                "required": ["helmetColor"]
              }
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)
        let transportField = tryUnwrapField("transport", in: session)

        XCTAssertNotNil(field(named: "licensePlate", in: session))
        XCTAssertNil(field(named: "helmetColor", in: session))

        session.setSelectedEnumChoiceID("string:bike", for: transportField)

        XCTAssertNil(field(named: "licensePlate", in: session))
        let helmetColorField = tryUnwrapField("helmetColor", in: session)
        session.setStringValue("Matte Black", for: helmetColorField)

        session.setSelectedEnumChoiceID("string:car", for: transportField)
        XCTAssertNotNil(field(named: "licensePlate", in: session))
        XCTAssertNil(field(named: "helmetColor", in: session))

        session.setSelectedEnumChoiceID("string:bike", for: transportField)
        XCTAssertEqual(session.stringValue(for: tryUnwrapField("helmetColor", in: session)), "Matte Black")
    }

    func testDependentSchemasRevealAdditionalFieldsAndRequiredness() throws {
        let schema =
            """
            {
              "title": "Business Intake",
              "type": "object",
              "properties": {
                "businessName": {
                  "type": "string",
                  "title": "Business Name"
                }
              },
              "dependentSchemas": {
                "businessName": {
                  "properties": {
                    "vatNumber": {
                      "type": "string",
                      "title": "VAT Number"
                    }
                  },
                  "required": ["vatNumber"]
                }
              }
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)
        let businessNameField = tryUnwrapField("businessName", in: session)

        XCTAssertNil(field(named: "vatNumber", in: session))

        session.setStringValue("Acme Corp", for: businessNameField)

        let vatNumberField = tryUnwrapField("vatNumber", in: session)
        XCTAssertFalse(session.validate())
        XCTAssertEqual(session.errorMessages(for: vatNumberField), ["This field is required."])
    }

    func testOneOfSwitchesToMatchingBranch() throws {
        let schema =
            """
            {
              "title": "Notifications",
              "type": "object",
              "properties": {
                "channel": {
                  "title": "Channel",
                  "enum": ["email", "sms"]
                }
              },
              "required": ["channel"],
              "oneOf": [
                {
                  "properties": {
                    "channel": {
                      "const": "email"
                    },
                    "emailAddress": {
                      "type": "string",
                      "format": "email",
                      "title": "Email Address"
                    }
                  },
                  "required": ["channel"]
                },
                {
                  "properties": {
                    "channel": {
                      "const": "sms"
                    },
                    "phoneNumber": {
                      "type": "string",
                      "title": "Phone Number"
                    }
                  },
                  "required": ["channel"]
                }
              ]
            }
            """
        let instance =
            """
            {
              "channel": "sms"
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: instance)
        let channelField = tryUnwrapField("channel", in: session)

        XCTAssertNotNil(field(named: "phoneNumber", in: session))
        XCTAssertNil(field(named: "emailAddress", in: session))

        session.setSelectedEnumChoiceID("string:email", for: channelField)

        XCTAssertNil(field(named: "phoneNumber", in: session))
        XCTAssertNotNil(field(named: "emailAddress", in: session))
    }

    func testConditionalDisableBehaviorKeepsFieldVisibleButNonSerializableUntilApplicable() throws {
        let schema =
            """
            {
              "title": "Conditional Disable",
              "type": "object",
              "properties": {
                "mode": {
                  "title": "Mode",
                  "enum": ["basic", "advanced"],
                  "default": "basic"
                }
              },
              "required": ["mode"],
              "if": {
                "properties": {
                  "mode": { "const": "advanced" }
                },
                "required": ["mode"]
              },
              "then": {
                "properties": {
                  "advancedCode": {
                    "type": "string",
                    "title": "Advanced Code",
                    "x-render-behavior": "disable"
                  }
                },
                "required": ["advancedCode"]
              }
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)
        let modeField = tryUnwrapField("mode", in: session)
        let advancedCodeField = tryUnwrapField("advancedCode", in: session)

        XCTAssertTrue(advancedCodeField.isDisabled)
        session.setStringValue("SHOULD-NOT-STICK", for: advancedCodeField)
        XCTAssertEqual(session.stringValue(for: advancedCodeField), "")
        XCTAssertFalse(session.currentInstanceJSON.contains("advancedCode"))
        XCTAssertTrue(session.validate())

        session.setSelectedEnumChoiceID("string:advanced", for: modeField)

        let activeAdvancedCodeField = tryUnwrapField("advancedCode", in: session)
        XCTAssertFalse(activeAdvancedCodeField.isDisabled)
        session.setStringValue("LIVE-CODE", for: activeAdvancedCodeField)
        XCTAssertTrue(session.currentInstanceJSON.contains("\"advancedCode\" : \"LIVE-CODE\""))
    }

    func testConditionalIgnoreBehaviorKeepsFieldVisibleAndSerializableWhileInactive() throws {
        let schema =
            """
            {
              "title": "Conditional Ignore",
              "type": "object",
              "properties": {
                "mode": {
                  "title": "Mode",
                  "enum": ["basic", "advanced"],
                  "default": "basic"
                }
              },
              "required": ["mode"],
              "if": {
                "properties": {
                  "mode": { "const": "advanced" }
                },
                "required": ["mode"]
              },
              "then": {
                "properties": {
                  "advancedNotes": {
                    "type": "string",
                    "title": "Advanced Notes",
                    "x-render-behavior": "ignore"
                  }
                }
              }
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)
        let advancedNotesField = tryUnwrapField("advancedNotes", in: session)

        XCTAssertFalse(advancedNotesField.isDisabled)
        XCTAssertTrue(advancedNotesField.isConditionallyInactive)

        session.setStringValue("Carry across branches", for: advancedNotesField)
        XCTAssertTrue(session.currentInstanceJSON.contains("\"advancedNotes\" : \"Carry across branches\""))
        XCTAssertTrue(session.validate())
    }

    func testConditionalDisableBehaviorOnArraySectionBlocksEditsWhileInactive() throws {
        let schema =
            """
            {
              "title": "Conditional Array",
              "type": "object",
              "properties": {
                "mode": {
                  "title": "Mode",
                  "enum": ["basic", "advanced"],
                  "default": "basic"
                }
              },
              "required": ["mode"],
              "if": {
                "properties": {
                  "mode": { "const": "advanced" }
                },
                "required": ["mode"]
              },
              "then": {
                "properties": {
                  "crew": {
                    "type": "array",
                    "title": "Crew",
                    "x-render-behavior": "disable",
                    "items": {
                      "type": "string",
                      "title": "Crew Member"
                    }
                  }
                }
              }
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)
        let modeField = tryUnwrapField("mode", in: session)
        let disabledCrewSection = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.title == "Crew" }))

        XCTAssertTrue(disabledCrewSection.isDisabled)
        session.appendArrayRow(to: disabledCrewSection)
        XCTAssertNil(try decodeJSONObject(session.currentInstanceJSON)["crew"])

        session.setSelectedEnumChoiceID("string:advanced", for: modeField)

        let activeCrewSection = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.title == "Crew" }))
        XCTAssertFalse(activeCrewSection.isDisabled)
        session.appendArrayRow(to: activeCrewSection)

        let updatedCrewSection = try XCTUnwrap(session.renderPlan.sections.first(where: { $0.id == activeCrewSection.id }))
        let crewDescriptor = try XCTUnwrap(updatedCrewSection.arrayDescriptor)
        XCTAssertEqual(crewDescriptor.rows.count, 1)
    }

    func testXConditionsAreIgnoredAsNonNativeAnnotations() throws {
        let schema =
            """
            {
              "title": "Feedback Form",
              "type": "object",
              "properties": {
                "contact_details": {
                  "title": "Contact Details",
                  "type": "object",
                  "properties": {
                    "full_name": {
                      "title": "Full Name",
                      "type": "string"
                    },
                    "email": {
                      "title": "Email",
                      "type": "string",
                      "format": "email"
                    }
                  },
                  "required": ["full_name", "email"]
                },
                "request_type": {
                  "title": "Request Type",
                  "type": "string",
                  "enum": ["Bug", "Feature", "Support"]
                },
                "bug_details": {
                  "title": "Bug Details",
                  "description": "Shown only for bug reports",
                  "type": "object",
                  "properties": {
                    "severity": {
                      "title": "Severity",
                      "type": "string",
                      "enum": ["Low", "Medium", "High"]
                    },
                    "steps": {
                      "title": "Steps to Reproduce",
                      "type": "string"
                    }
                  },
                  "required": ["severity"],
                  "x-conditions": [
                    {
                      "dependsOn": "request_type",
                      "equals": "Bug"
                    }
                  ]
                },
                "links": {
                  "title": "Related Links",
                  "type": "array",
                  "items": {
                    "type": "string"
                  }
                },
                "team_members": {
                  "title": "Team Members",
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "name": {
                        "title": "Name",
                        "type": "string"
                      }
                    },
                    "required": ["name"]
                  }
                }
              },
              "required": ["request_type"]
            }
            """
        let featureInstance =
            """
            {
              "request_type": "Feature"
            }
            """

        let session = FormKitRenderer().makeFormSession(
            schemaJSON: schema,
            instanceJSON: featureInstance
        )

        XCTAssertNotNil(session.renderPlan.sections.first(where: { $0.title == "Bug Details" }))
        XCTAssertNotNil(field(named: "severity", in: session))
        XCTAssertNotNil(field(named: "steps", in: session))

        let renderIndex = FormKitRenderIndex(renderPlan: session.renderPlan)
        let blockLabels = renderIndex.visibleRootBlocks.compactMap { block -> String? in
            switch block.kind {
            case .section(let sectionID):
                return renderIndex.section(sectionID)?.title
            case .fieldGroup(_, let fieldIDs):
                return fieldIDs
                    .compactMap { renderIndex.field($0)?.propertyKey }
                    .joined(separator: ",")
            }
        }

        XCTAssertEqual(
            blockLabels,
            ["Contact Details", "request_type", "Bug Details", "Related Links", "Team Members"]
        )
    }

    func testArrayItemRootXConditionsAreIgnored() throws {
        let schema =
            """
            {
              "title": "Entries",
              "type": "object",
              "properties": {
                "entries": {
                  "title": "Entries",
                  "type": "array",
                  "items": {
                    "title": "Entry",
                    "type": "object",
                    "properties": {
                      "kind": {
                        "title": "Kind",
                        "type": "string",
                        "enum": ["Bug", "Feature"]
                      },
                      "details": {
                        "title": "Details",
                        "type": "string"
                      }
                    },
                    "x-conditions": [
                      {
                        "dependsOn": "kind",
                        "equals": "Bug"
                      }
                    ]
                  }
                }
              }
            }
            """
        let instance =
            """
            {
              "entries": [
                {
                  "kind": "Bug",
                  "details": "Keep"
                },
                {
                  "kind": "Feature",
                  "details": "Hide"
                }
              ]
            }
            """

        let session = FormKitRenderer().makeFormSession(
            schemaJSON: schema,
            instanceJSON: instance
        )

        let entriesSection = try XCTUnwrap(
            session.renderPlan.sections.first(where: {
                $0.pointer == "#/entries" && $0.arrayDescriptor != nil
            })
        )
        let descriptor = try XCTUnwrap(entriesSection.arrayDescriptor)

        XCTAssertEqual(descriptor.rows.map(\.pointer), ["#/entries/0", "#/entries/1"])
        XCTAssertEqual(descriptor.rows.count, 2)
    }

    func testRendererAcceptsEscapedNonBMPUnicodeInSchemaStrings() throws {
        let schema =
            """
            {
              "title": "Emoji \\uD83D\\uDE00 Form",
              "type": "object",
              "properties": {
                "name": {
                  "title": "Name",
                  "type": "string"
                }
              }
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)

        XCTAssertTrue(session.renderPlan.isSupported)
        XCTAssertEqual(session.renderPlan.title, "Emoji 😀 Form")
    }

    func testMalformedXConditionsAreIgnored() throws {
        let schema =
            """
            {
              "title": "Malformed Annotation",
              "type": "object",
              "properties": {
                "name": {
                  "title": "Name",
                  "type": "string",
                  "x-conditions": {
                    "dependsOn": "mode",
                    "equals": "advanced"
                  }
                }
              }
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)

        XCTAssertTrue(session.renderPlan.isSupported)
        XCTAssertNotNil(field(named: "name", in: session))
    }

    func testPureJSONSchemaConditionalObjectSectionsHideAndShowWithDiscriminator() throws {
        let schema =
            """
            {
              "$schema": "https://json-schema.org/draft/2020-12/schema",
              "title": "Feedback Form",
              "type": "object",
              "properties": {
                "request_type": {
                  "title": "Request Type",
                  "type": "string",
                  "enum": ["Bug", "Feature", "Support"]
                }
              },
              "required": ["request_type"],
              "allOf": [
                {
                  "if": {
                    "properties": {
                      "request_type": { "const": "Bug" }
                    },
                    "required": ["request_type"]
                  },
                  "then": {
                    "properties": {
                      "bug_details": {
                        "title": "Bug Details",
                        "type": "object",
                        "properties": {
                          "severity": {
                            "title": "Severity",
                            "type": "string",
                            "enum": ["Low", "Medium", "High"]
                          },
                          "steps": {
                            "title": "Steps to Reproduce",
                            "type": "string"
                          }
                        }
                      }
                    },
                    "required": ["bug_details"]
                  }
                },
                {
                  "if": {
                    "properties": {
                      "request_type": { "const": "Feature" }
                    },
                    "required": ["request_type"]
                  },
                  "then": {
                    "properties": {
                      "feature_details": {
                        "title": "Feature Details",
                        "type": "object",
                        "properties": {
                          "summary": {
                            "title": "Summary",
                            "type": "string"
                          }
                        }
                      }
                    },
                    "required": ["feature_details"]
                  }
                }
              ]
            }
            """

        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: nil)
        let requestTypeField = tryUnwrapField("request_type", in: session)

        XCTAssertNotNil(session.renderPlan.sections.first(where: { $0.title == "Bug Details" }))
        XCTAssertNil(session.renderPlan.sections.first(where: { $0.title == "Feature Details" }))
        XCTAssertNotNil(field(named: "severity", in: session))
        XCTAssertNil(field(named: "summary", in: session))

        session.setSelectedEnumChoiceID("string:Feature", for: requestTypeField)

        XCTAssertNil(session.renderPlan.sections.first(where: { $0.title == "Bug Details" }))
        XCTAssertNotNil(session.renderPlan.sections.first(where: { $0.title == "Feature Details" }))
        XCTAssertNil(field(named: "severity", in: session))
        XCTAssertNotNil(field(named: "summary", in: session))

        let renderIndex = FormKitRenderIndex(renderPlan: session.renderPlan)
        let blockLabels = renderIndex.visibleRootBlocks.compactMap { block -> String? in
            switch block.kind {
            case .section(let sectionID):
                return renderIndex.section(sectionID)?.title
            case .fieldGroup(_, let fieldIDs):
                return fieldIDs
                    .compactMap { renderIndex.field($0)?.propertyKey }
                    .joined(separator: ",")
            }
        }

        XCTAssertEqual(
            blockLabels,
            ["request_type", "Feature Details"]
        )
    }

    func testConditionalRequiredPredeclaredObjectSectionHidesWhenBranchInactive() throws {
        let schema =
            """
            {
              "$schema": "https://json-schema.org/draft/2020-12/schema",
              "title": "Project Intake Form",
              "description": "Collect a few basic details and export them as JSON Schema.",
              "type": "object",
              "properties": {
                "contact_details": {
                  "title": "Contact Details",
                  "description": "Basic information about the requester.",
                  "type": "object",
                  "properties": {
                    "full_name": {
                      "title": "Full Name",
                      "description": "Name of the requester",
                      "type": "string"
                    },
                    "email": {
                      "title": "Email",
                      "description": "Primary contact email",
                      "type": "string",
                      "format": "email"
                    }
                  },
                  "required": ["full_name", "email"]
                },
                "request_type": {
                  "title": "Request Type",
                  "description": "Select the kind of request",
                  "type": "string",
                  "enum": ["Bug", "Feature", "Support"]
                },
                "bug_details": {
                  "title": "Bug Details",
                  "description": "Optional details when the request is a bug.",
                  "type": "object",
                  "properties": {
                    "severity": {
                      "title": "Severity",
                      "type": "string",
                      "enum": ["Low", "Medium", "High"]
                    },
                    "steps": {
                      "title": "Steps to Reproduce",
                      "type": "string"
                    }
                  },
                  "required": ["severity"]
                },
                "links": {
                  "title": "Related Links",
                  "description": "A simple list of text items",
                  "type": "array",
                  "items": {
                    "type": "string"
                  }
                },
                "team_members": {
                  "title": "Team Members",
                  "description": "A list of nested object items",
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "name": {
                        "title": "Name",
                        "type": "string"
                      },
                      "role": {
                        "title": "Role",
                        "type": "string"
                      }
                    },
                    "required": ["name"]
                  }
                }
              },
              "required": ["request_type"],
              "allOf": [
                {
                  "if": {
                    "properties": {
                      "request_type": {
                        "const": "Bug"
                      }
                    },
                    "required": ["request_type"]
                  },
                  "then": {
                    "required": ["bug_details"]
                  }
                }
              ]
            }
            """
        let instance =
            """
            {
              "request_type": "Feature"
            }
            """

        let session = FormKitRenderer().makeFormSession(
            schemaJSON: schema,
            instanceJSON: instance
        )
        let requestTypeField = tryUnwrapField("request_type", in: session)

        let hiddenBugDetailsSection = try XCTUnwrap(
            session.renderPlan.sections.first(where: { $0.title == "Bug Details" })
        )
        XCTAssertFalse(hiddenBugDetailsSection.isVisible)
        XCTAssertFalse(tryUnwrapField("severity", in: session).isVisible)
        XCTAssertFalse(tryUnwrapField("steps", in: session).isVisible)

        let featureRenderIndex = FormKitRenderIndex(renderPlan: session.renderPlan)
        let featureBlockLabels = featureRenderIndex.visibleRootBlocks.compactMap { block -> String? in
            switch block.kind {
            case .section(let sectionID):
                return featureRenderIndex.section(sectionID)?.title
            case .fieldGroup(_, let fieldIDs):
                return fieldIDs
                    .compactMap { featureRenderIndex.field($0)?.propertyKey }
                    .joined(separator: ",")
            }
        }

        XCTAssertEqual(
            featureBlockLabels,
            ["Contact Details", "request_type", "Related Links", "Team Members"]
        )

        session.setSelectedEnumChoiceID("string:Bug", for: requestTypeField)

        XCTAssertTrue(
            try XCTUnwrap(
                session.renderPlan.sections.first(where: { $0.title == "Bug Details" })
            ).isVisible
        )
        XCTAssertTrue(tryUnwrapField("severity", in: session).isVisible)
    }

    func testConditionalRequiredPredeclaredScalarFieldHidesUntilBranchActivates() throws {
        let schema =
            """
            {
              "$schema": "https://json-schema.org/draft/2020-12/schema",
              "title": "Advanced Settings",
              "type": "object",
              "properties": {
                "mode": {
                  "title": "Mode",
                  "type": "string",
                  "enum": ["basic", "advanced"]
                },
                "advanced_code": {
                  "title": "Advanced Code",
                  "type": "string"
                }
              },
              "required": ["mode"],
              "allOf": [
                {
                  "if": {
                    "properties": {
                      "mode": { "const": "advanced" }
                    },
                    "required": ["mode"]
                  },
                  "then": {
                    "required": ["advanced_code"]
                  }
                }
              ]
            }
            """
        let instance =
            """
            {
              "mode": "basic"
            }
            """

        let session = FormKitRenderer().makeFormSession(
            schemaJSON: schema,
            instanceJSON: instance
        )
        let modeField = tryUnwrapField("mode", in: session)
        let inactiveAdvancedCodeField = tryUnwrapField("advanced_code", in: session)

        XCTAssertFalse(inactiveAdvancedCodeField.isVisible)
        XCTAssertFalse(inactiveAdvancedCodeField.isRequired)
        XCTAssertTrue(session.validate())

        let basicRenderIndex = FormKitRenderIndex(renderPlan: session.renderPlan)
        let basicBlockLabels = basicRenderIndex.visibleRootBlocks.compactMap { block -> String? in
            switch block.kind {
            case .section(let sectionID):
                return basicRenderIndex.section(sectionID)?.title
            case .fieldGroup(_, let fieldIDs):
                return fieldIDs
                    .compactMap { basicRenderIndex.field($0)?.propertyKey }
                    .joined(separator: ",")
            }
        }

        XCTAssertEqual(basicBlockLabels, ["mode"])

        session.setSelectedEnumChoiceID("string:advanced", for: modeField)

        let activeAdvancedCodeField = tryUnwrapField("advanced_code", in: session)
        XCTAssertTrue(activeAdvancedCodeField.isVisible)
        XCTAssertTrue(activeAdvancedCodeField.isRequired)
        XCTAssertFalse(session.validate())
        XCTAssertEqual(session.errorMessages(for: activeAdvancedCodeField), ["This field is required."])

        session.setStringValue("ALPHA-7", for: activeAdvancedCodeField)
        XCTAssertTrue(session.validate())
    }

    func testOnDemandValidationDoesNotRevalidateAfterFieldEdits() throws {
        let schema =
            """
            {
              "type": "object",
              "properties": {
                "name": {
                  "type": "string",
                  "title": "Name"
                }
              },
              "required": ["name"]
            }
            """

        let session = FormKitRenderer().makeFormSession(
            schemaJSON: schema,
            instanceJSON: "{}",
            validationBehavior: .onDemandOnly
        )
        let nameField = tryUnwrapField("name", in: session)

        XCTAssertFalse(session.validate())
        XCTAssertEqual(session.errorMessages(for: nameField), ["This field is required."])

        session.setStringValue("Taylor", for: nameField)

        XCTAssertTrue(session.errorMessages(for: nameField).isEmpty)
        XCTAssertNil(session.validationStatusMessage)
        XCTAssertTrue(session.validate())
    }

    func testToolContextExposesVisibleFieldsAndCurrentValues() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: supportedSchema,
            instanceJSON: populatedInstance
        )

        let context = session.makeToolContext(focusedPointers: ["/contact/email"])

        XCTAssertEqual(context.title, "Project Intake")
        XCTAssertEqual(context.revision, 0)
        XCTAssertEqual(context.fields.map(\.pointer), [
            "/contact/fullName",
            "/contact/email",
            "/contact/website",
            "/contact/sendUpdates",
            "/visitDate",
            "/priority"
        ])
        XCTAssertTrue(try XCTUnwrap(context.fields.first { $0.pointer == "/contact/email" }).isLocked)
        XCTAssertEqual(context.currentValues["/contact/fullName"], .string("Taylor Jordan"))
        XCTAssertEqual(context.currentValues["/contact/sendUpdates"], .boolean(false))
    }

    func testToolEditsApplySetClearAndRejectLockedPointers() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: supportedSchema,
            instanceJSON: populatedInstance
        )

        let result = session.applyToolEdits(
            [
                .init(pointer: "/contact/fullName", operation: .set, value: .string("Avery Stone")),
                .init(pointer: "/contact/website", operation: .clear),
                .init(pointer: "/contact/email", operation: .set, value: .string("locked@example.com"))
            ],
            baseRevision: 0,
            lockedPointers: ["/contact/email"]
        )

        XCTAssertEqual(result.revision, 2)
        XCTAssertEqual(result.appliedEdits.map(\.pointer), ["/contact/fullName", "/contact/website"])
        XCTAssertEqual(result.rejectedEdits.map(\.reason), ["field_locked"])
        XCTAssertEqual(session.stringValue(for: tryUnwrapField("fullName", in: session)), "Avery Stone")
        XCTAssertEqual(session.stringValue(for: tryUnwrapField("website", in: session)), "")
    }

    func testToolEditsRejectRevisionConflictWithoutChangingForm() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: supportedSchema,
            instanceJSON: populatedInstance
        )

        let result = session.applyToolEdits(
            [.init(pointer: "/contact/fullName", operation: .set, value: .string("Avery Stone"))],
            baseRevision: 9
        )

        XCTAssertEqual(result.revision, 0)
        XCTAssertTrue(result.appliedEdits.isEmpty)
        XCTAssertEqual(result.rejectedEdits.map(\.reason), ["revision_conflict"])
        XCTAssertEqual(session.stringValue(for: tryUnwrapField("fullName", in: session)), "Taylor Jordan")
    }

    private func field(
        named propertyKey: String,
        in session: FormKitSession
    ) -> FormKitFieldDescriptor? {
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
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}

private final class InvalidationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        storage += 1
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
