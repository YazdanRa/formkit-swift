import Foundation
import XCTest
@testable import FormKitSwift

private let validationSchema =
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

private let dependentRequiredSchema =
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

private let dependentSchema =
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

private let dependentRequirednessSchema =
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

private let allOfAndOneOfSchema =
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

private let companyInstance =
    """
    {
      "kind": "company"
    }
    """

private let switchingOneOfSchema =
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

private let smsInstance =
    """
    {
      "channel": "sms"
    }
    """

extension FormKitRendererTests {
    func testValidationMapsInlineAndFormLevelErrors() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: validationSchema, instanceJSON: nil)

        XCTAssertFalse(session.validate())
        XCTAssertEqual(session.errorMessages(for: tryUnwrapField("fullName", in: session)), ["This field is required."])
        XCTAssertEqual(session.errorMessages(for: tryUnwrapField("email", in: session)), ["This field is required."])
        XCTAssertEqual(session.firstInvalidFieldID, tryUnwrapField("fullName", in: session).id)
        XCTAssertNotNil(session.formErrorMessage)
        XCTAssertTrue(session.formErrorMessage?.localizedCaseInsensitiveContains("minimum") == true)
    }

    func testDependentRequiredOnlyAppliesWhenTriggerIsPresent() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: dependentRequiredSchema, instanceJSON: nil)

        XCTAssertTrue(session.validate())

        session.setStringValue("person@example.com", for: tryUnwrapField("email", in: session))

        XCTAssertFalse(session.validate())
        XCTAssertEqual(
            session.errorMessages(for: tryUnwrapField("phone", in: session)),
            ["This field is required."]
        )
    }

    func testDependentSchemasAddsConditionalFields() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: dependentSchema, instanceJSON: nil)

        XCTAssertNil(field(named: "billingEmail", in: session))

        session.setSelectedEnumChoiceID("string:Email", for: tryUnwrapField("billingMode", in: session))

        XCTAssertNotNil(field(named: "billingEmail", in: session))
        XCTAssertFalse(session.validate())
        XCTAssertEqual(
            session.errorMessages(for: tryUnwrapField("billingEmail", in: session)),
            ["This field is required."]
        )
    }

    func testDependentSchemasRevealAdditionalFieldsAndRequiredness() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: dependentRequirednessSchema, instanceJSON: nil)
        let businessNameField = tryUnwrapField("businessName", in: session)

        XCTAssertNil(field(named: "vatNumber", in: session))

        session.setStringValue("Acme Corp", for: businessNameField)

        let vatNumberField = tryUnwrapField("vatNumber", in: session)
        XCTAssertFalse(session.validate())
        XCTAssertEqual(session.errorMessages(for: vatNumberField), ["This field is required."])
    }
}

extension FormKitRendererTests {
    func testAllOfAndOneOfMaterializeMatchingBranch() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: allOfAndOneOfSchema, instanceJSON: companyInstance)

        XCTAssertNotNil(field(named: "sharedCode", in: session))
        XCTAssertNotNil(field(named: "companyName", in: session))
        XCTAssertNil(field(named: "firstName", in: session))
        XCTAssertTrue(tryUnwrapField("companyName", in: session).isRequired)
    }

    func testOneOfSwitchesToMatchingBranch() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: switchingOneOfSchema, instanceJSON: smsInstance)
        let channelField = tryUnwrapField("channel", in: session)

        XCTAssertNotNil(field(named: "phoneNumber", in: session))
        XCTAssertNil(field(named: "emailAddress", in: session))

        session.setSelectedEnumChoiceID("string:email", for: channelField)

        XCTAssertNil(field(named: "phoneNumber", in: session))
        XCTAssertNotNil(field(named: "emailAddress", in: session))
    }
}
