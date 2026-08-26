import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitInstanceProjectionTests: XCTestCase {
    func testPrunesGeneratedEmptyObjectsAndPreservesInitialEmptyObjects() throws {
        let schema = """
        {
          "type": "object",
          "properties": {
            "settings": {
              "type": "object",
              "properties": {
                "theme": { "type": "string", "default": "system" }
              }
            }
          }
        }
        """
        let generatedSession = FormKitRenderer().makeFormSession(
            schemaJSON: schema,
            instanceJSON: nil
        )
        XCTAssertEqual(
            try decodeJSONObject(generatedSession.instanceJSONOmittingNonArrayDefaults).count,
            0
        )

        let initialSession = FormKitRenderer().makeFormSession(
            schemaJSON: schema,
            instanceJSON: #"{"settings":{}}"#
        )
        let initialObject = try decodeJSONObject(
            initialSession.instanceJSONOmittingNonArrayDefaults
        )
        XCTAssertNotNil(initialObject["settings"] as? [String: Any])
    }

    func testPreservesRequiredEmptyObjectsWithAndWithoutOmittedDefaults() throws {
        for properties in [
            "{}",
            #"{"theme":{"type":"string","default":"system"}}"#
        ] {
            let session = FormKitRenderer().makeFormSession(
                schemaJSON: """
                {
                  "type": "object",
                  "properties": {
                    "settings": { "type": "object", "properties": \(properties) }
                  },
                  "required": ["settings"]
                }
                """,
                instanceJSON: nil
            )

            let object = try decodeJSONObject(session.instanceJSONOmittingNonArrayDefaults)
            let settings = try XCTUnwrap(object["settings"] as? [String: Any])
            XCTAssertTrue(settings.isEmpty)
        }
    }

    func testPreservesObjectArrayDefaults() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: Self.objectArraySchema,
            instanceJSON: nil
        )
        let section = try XCTUnwrap(
            session.renderPlan.sections.first { $0.propertyKey == "items" }
        )
        session.appendArrayRow(to: section)

        let object = try decodeJSONObject(session.instanceJSONOmittingNonArrayDefaults)
        let items = try XCTUnwrap(object["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0]["name"] as? String, "Generated")
        XCTAssertEqual(items[0]["confirmed"] as? Bool, false)
    }

    func testPreservesDefaultedScalarArrayItems() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "tags": {
                  "type": "array",
                  "minItems": 1,
                  "items": { "type": "string", "default": "Generated" }
                }
              }
            }
            """,
            instanceJSON: nil
        )

        let object = try decodeJSONObject(session.instanceJSONOmittingNonArrayDefaults)
        XCTAssertEqual(object["tags"] as? [String], ["Generated"])
    }

    private func decodeJSONObject(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static let objectArraySchema = """
    {
      "type": "object",
      "properties": {
        "items": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "name": { "type": "string", "default": "Generated" },
              "confirmed": { "type": "boolean", "default": false }
            }
          }
        }
      }
    }
    """
}
