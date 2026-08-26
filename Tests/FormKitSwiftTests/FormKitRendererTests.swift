import Foundation
import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitRendererTests: XCTestCase {
    let supportedSchema =
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

    let populatedInstance =
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

    let unsupportedSchema =
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

    let arraySchema =
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

    let conditionalSchema =
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

    func field(
        named propertyKey: String,
        in session: FormKitSession
    ) -> FormKitFieldDescriptor? {
        session.renderPlan.fields.first(where: { $0.propertyKey == propertyKey })
    }

    func tryUnwrapField(
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

    func decodeJSONObject(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}

final class InvalidationCounter: @unchecked Sendable {
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
