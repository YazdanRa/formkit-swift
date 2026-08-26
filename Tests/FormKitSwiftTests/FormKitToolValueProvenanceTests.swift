import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitToolValueProvenanceTests: XCTestCase {
    func testScalarValuesExposeInitialDefaultAndSessionSources() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "initial": { "type": "boolean" },
                "requiredEnum": { "type": "string", "enum": ["Low", "High"] },
                "requiredBoolean": { "type": "boolean" },
                "requiredDate": { "type": "string", "format": "date" },
                "schemaDefault": { "type": "string", "default": "Standard" },
                "missing": { "type": "string" }
              },
              "required": ["initial", "requiredEnum", "requiredBoolean", "requiredDate"]
            }
            """,
            instanceJSON: #"{"initial":false}"#
        )
        let initialContext = session.makeToolContext()

        assertSource(.initialInstance, at: "/initial", in: initialContext)
        assertSource(.defaultValue, at: "/requiredEnum", in: initialContext)
        assertSource(.defaultValue, at: "/requiredBoolean", in: initialContext)
        assertSource(.defaultValue, at: "/requiredDate", in: initialContext)
        assertSource(.defaultValue, at: "/schemaDefault", in: initialContext)
        assertSource(nil, at: "/missing", in: initialContext)
        XCTAssertEqual(initialContext.currentValues["/requiredEnum"], .string("Low"))
        XCTAssertEqual(initialContext.currentValues["/requiredBoolean"], .boolean(false))
        XCTAssertFalse(try XCTUnwrap(initialContext.currentValues["/requiredDate"]?.string).isEmpty)

        let initialJSON = session.currentInstanceJSON
        _ = session.applyToolEdits([
            FormKitToolEdit(pointer: "/requiredEnum", operation: .set, value: .string("Low"))
        ])
        assertSource(.sessionEdit, at: "/requiredEnum", in: session.makeToolContext())
        XCTAssertEqual(session.currentInstanceJSON, initialJSON)
    }

    func testArrayAppendAndRemovalPreservePerValueSources() throws {
        let session = makeArraySession()
        let itemsSection = try section(in: session)
        let secondConfirmedField = try XCTUnwrap(
            session.renderPlan.fields.first { $0.pointer == "#/items/1/confirmed" }
        )

        session.setBooleanValue(false, for: secondConfirmedField)
        session.appendArrayRow(to: itemsSection)
        let appendedContext = session.makeToolContext()
        assertSource(.initialInstance, at: "/items/0/name", in: appendedContext)
        assertSource(.initialInstance, at: "/items/1/name", in: appendedContext)
        assertSource(.defaultValue, at: "/items/2/name", in: appendedContext)
        assertSource(.defaultValue, at: "/items/2/confirmed", in: appendedContext)

        let appendedSection = try section(in: session)
        session.removeArrayRow(
            try XCTUnwrap(appendedSection.arrayDescriptor?.rows.first),
            from: appendedSection
        )
        let removedContext = session.makeToolContext()
        assertSource(.initialInstance, at: "/items/0/name", in: removedContext)
        assertSource(.sessionEdit, at: "/items/0/confirmed", in: removedContext)
        assertSource(.defaultValue, at: "/items/1/name", in: removedContext)

        let removedSection = try section(in: session)
        session.removeArrayRow(
            try XCTUnwrap(removedSection.arrayDescriptor?.rows.last),
            from: removedSection
        )
        session.appendArrayRow(to: try section(in: session))
        assertSource(.defaultValue, at: "/items/1/name", in: session.makeToolContext())
    }

    func testArrayReplacementDistinguishesExplicitAndGeneratedValues() throws {
        let restoredSession = makeArraySession()
        restoredSession.setArrayValue([.object([:])], for: try section(in: restoredSession))
        let defaultedContext = restoredSession.makeToolContext()
        assertSource(.defaultValue, at: "/items/0/name", in: defaultedContext)
        XCTAssertEqual(defaultedContext.currentValues["/items/0/name"], .string("Generated"))

        restoredSession.setArrayValue([.object(["name": .null])], for: try section(in: restoredSession))
        let restoredContext = restoredSession.makeToolContext()
        assertSource(.initialInstance, at: "/items/0/name", in: restoredContext)
        XCTAssertEqual(restoredContext.currentValues["/items/0/name"], .string("First"))

        let session = makeArraySession(instanceJSON: nil)
        session.setArrayValue([.object([:])], for: try section(in: session))
        assertSource(.defaultValue, at: "/items/0/name", in: session.makeToolContext())
        assertSource(.defaultValue, at: "/items/0/confirmed", in: session.makeToolContext())

        session.setArrayValue([.object(["name": .null])], for: try section(in: session))
        assertSource(.defaultValue, at: "/items/0/name", in: session.makeToolContext())

        session.setArrayValue(
            [.object(["name": .string("Replacement")])],
            for: try section(in: session)
        )
        let context = session.makeToolContext()
        assertSource(.sessionEdit, at: "/items/0/name", in: context)
        assertSource(.defaultValue, at: "/items/0/confirmed", in: context)
    }

    func testRematerializingDefaultPreservesUnrelatedSessionAndHiddenValues() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: Self.conditionalSchema,
            instanceJSON: #"{"mode":"advanced","code":"Legacy","notes":"Original","fallback":"Keep"}"#
        )
        let notes = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/notes" })
        let code = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/code" })
        session.setStringValue("Edited", for: notes)

        XCTAssertTrue(session.rematerializeDefaultValue(for: code))
        var context = session.makeToolContext()
        XCTAssertEqual(context.currentValues["/code"], .string("Current"))
        assertSource(.defaultValue, at: "/code", in: context)
        assertSource(.sessionEdit, at: "/notes", in: context)

        let mode = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/mode" })
        session.setSelectedEnumChoiceID("string:basic", for: mode)
        context = session.makeToolContext()
        XCTAssertEqual(context.currentValues["/fallback"], .string("Keep"))
        assertSource(.initialInstance, at: "/fallback", in: context)

        let currentMode = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/mode" })
        session.setSelectedEnumChoiceID("string:advanced", for: currentMode)
        context = session.makeToolContext()
        XCTAssertEqual(context.currentValues["/code"], .string("Current"))
        assertSource(.defaultValue, at: "/code", in: context)
        XCTAssertEqual(context.currentValues["/notes"], .string("Edited"))
        assertSource(.sessionEdit, at: "/notes", in: context)
    }

    func testRematerializingDefaultRejectsEditedValue() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: Self.conditionalSchema,
            instanceJSON: #"{"mode":"advanced","code":"Legacy"}"#
        )
        let code = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/code" })
        session.setStringValue("Confirmed", for: code)

        XCTAssertFalse(session.rematerializeDefaultValue(for: code))
        XCTAssertEqual(session.makeToolContext().currentValues["/code"], .string("Confirmed"))
        assertSource(.sessionEdit, at: "/code", in: session.makeToolContext())
    }

    func testRematerializingDefaultRejectsStaleHiddenField() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: Self.conditionalSchema,
            instanceJSON: #"{"mode":"advanced","code":"Legacy"}"#
        )
        let code = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/code" })
        let mode = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/mode" })
        session.setSelectedEnumChoiceID("string:basic", for: mode)

        XCTAssertFalse(session.rematerializeDefaultValue(for: code))
        let currentMode = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/mode" })
        session.setSelectedEnumChoiceID("string:advanced", for: currentMode)
        XCTAssertEqual(session.makeToolContext().currentValues["/code"], .string("Legacy"))
    }

    private func makeArraySession() -> FormKitSession {
        makeArraySession(instanceJSON: Self.arrayInstance)
    }

    private func makeArraySession(instanceJSON: String?) -> FormKitSession {
        FormKitRenderer().makeFormSession(
            schemaJSON: Self.arraySchema,
            instanceJSON: instanceJSON
        )
    }

    private func section(in session: FormKitSession) throws -> FormKitRenderPlan.SectionDescriptor {
        try XCTUnwrap(session.renderPlan.sections.first { $0.propertyKey == "items" })
    }

    private func assertSource(
        _ expected: FormKitToolValueSource?,
        at pointer: String,
        in context: FormKitToolContext,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            context.fields.first { $0.pointer == pointer }?.valueSource,
            expected,
            file: file,
            line: line
        )
    }

    private static let arraySchema = """
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

    private static let arrayInstance = """
    {"items":[{"name":"First","confirmed":false},{"name":"Second","confirmed":false}]}
    """

    private static let conditionalSchema = """
    {
      "type": "object",
      "properties": {
        "mode": { "type": "string", "enum": ["basic", "advanced"] },
        "notes": { "type": "string" }
      },
      "required": ["mode"],
      "if": {
        "properties": { "mode": { "const": "advanced" } },
        "required": ["mode"]
      },
      "then": {
        "properties": { "code": { "type": "string", "enum": ["Current", "Legacy"] } },
        "required": ["code"]
      },
      "else": {
        "properties": { "fallback": { "type": "string" } }
      }
    }
    """
}
