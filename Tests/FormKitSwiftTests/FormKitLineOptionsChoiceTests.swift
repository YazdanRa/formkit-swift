import SwiftUI
import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitLineOptionsChoiceTests: XCTestCase {
    func testResolvedInputsDistinguishNativeAndCustomComponentsWithoutRepeatingHostClosure() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {"type":"object","properties":{"result":{
              "enum":["Pass","Failed"],"x-formkit-ui-component":"line-options-choice"
            }}}
            """,
            instanceJSON: nil
        )
        let field = try XCTUnwrap(session.renderPlan.fields.first)
        let native = FormKitFocusSupport.resolvedComponents(session: session, options: .init())
        XCTAssertEqual(native.fieldInputs[field.id]?.isCustom, false)

        var invocationCount = 0
        let replaced = FormKitFocusSupport.resolvedComponents(
            session: session,
            options: .init(components: .init(fieldInput: { _ in
                invocationCount += 1
                return AnyView(Text("Custom"))
            }))
        )
        XCTAssertEqual(replaced.fieldInputs[field.id]?.isCustom, true)
        XCTAssertEqual(invocationCount, 1)

        invocationCount = 0
        let delegated = FormKitFocusSupport.resolvedComponents(
            session: session,
            options: .init(components: .init(fieldInput: { _ in
                invocationCount += 1
                return nil
            }))
        )
        XCTAssertEqual(delegated.fieldInputs[field.id]?.isCustom, false)
        XCTAssertEqual(invocationCount, 1)
    }

    func testRegistryAcceptsOnlyAnnotatedEnumsWithTwoToThreeChoices() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "properties": {
                "two": {"enum": ["A", "B"], "x-formkit-ui-component": " LINE-OPTIONS-CHOICE "},
                "three": {"enum": [1, 2, 3], "x-formkit-ui-component": "line-options-choice"},
                "four": {"enum": [1, 2, 3, 4], "x-formkit-ui-component": "line-options-choice"},
                "five": {"enum": [1, 2, 3, 4, 5], "x-formkit-ui-component": "line-options-choice"},
                "one": {"enum": ["A"], "x-formkit-ui-component": "line-options-choice"},
                "six": {"enum": [1, 2, 3, 4, 5, 6], "x-formkit-ui-component": "line-options-choice"},
                "text": {"type": "string", "x-formkit-ui-component": "line-options-choice"},
                "unannotated": {"enum": ["A", "B"]}
              }
            }
            """,
            instanceJSON: nil
        )

        for field in session.renderPlan.fields {
            let resolved = FormKitComponentRegistry.fieldInput(for: context(field, in: session))
            if ["two", "three"].contains(field.propertyKey) {
                XCTAssertEqual(field.uiComponent, .lineOptionsChoice)
                XCTAssertNotNil(resolved, field.propertyKey)
            } else {
                XCTAssertNil(resolved, field.propertyKey)
            }
        }
        XCTAssertEqual(session.renderPlan.fields.count, 8)
    }

    func testOptionalSelectionCanBeChangedAndCleared() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {"type":"object","properties":{"result":{
              "enum":["Pass","Failed","N/A"],"x-formkit-ui-component":"line-options-choice"
            }}}
            """,
            instanceJSON: nil
        )
        let field = try XCTUnwrap(session.renderPlan.fields.first)
        let component = FormKitLineOptionsChoice(context: context(field, in: session))

        component.select(field.enumOptions[0])
        XCTAssertEqual(session.primitiveValue(for: field), .string("Pass"))
        component.select(field.enumOptions[1])
        XCTAssertEqual(session.primitiveValue(for: field), .string("Failed"))
        component.select(field.enumOptions[1])
        XCTAssertNil(session.selectedEnumChoiceID(for: field))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(session.currentInstanceJSON.utf8)) as? [String: Any]
        )
        XCTAssertNil(object["result"])
        XCTAssertTrue(session.validate())
    }

    func testRequiredSelectionValidatesAndCannotBeToggledOff() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {"type":"object","required":["result"],"properties":{"result":{
              "enum":["Pass","Failed","N/A"],"x-formkit-ui-component":"line-options-choice"
            }}}
            """,
            instanceJSON: nil,
            validationBehavior: .onDemandOnly
        )
        let field = try XCTUnwrap(session.renderPlan.fields.first)
        let component = FormKitLineOptionsChoice(context: context(field, in: session))

        session.setSelectedEnumChoiceID(nil, for: field)
        XCTAssertNil(session.selectedEnumChoiceID(for: field))
        XCTAssertFalse(session.validate())
        component.select(field.enumOptions[0])
        XCTAssertTrue(session.validate())
        let revision = session.revision
        component.select(field.enumOptions[0])
        XCTAssertEqual(session.revision, revision)
        XCTAssertEqual(session.primitiveValue(for: field), .string("Pass"))
    }

    func testSelectionPreservesScalarTypesAndExplicitNull() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {"type":"object","properties":{
              "integer":{"type":"integer","enum":[1,2],"x-formkit-ui-component":"line-options-choice"},
              "number":{"type":"number","enum":[1.5,2.5],"x-formkit-ui-component":"line-options-choice"},
              "boolean":{"type":"boolean","enum":[false,true],"x-formkit-ui-component":"line-options-choice"},
              "nullable":{"type":["string","null"],"enum":["Pass",null],"x-formkit-ui-component":"line-options-choice"}
            }}
            """,
            instanceJSON: nil
        )

        for field in session.renderPlan.fields {
            let choice = try XCTUnwrap(field.enumOptions.last)
            FormKitLineOptionsChoice(context: context(field, in: session)).select(choice)
            XCTAssertEqual(session.primitiveValue(for: field), choice.value, field.propertyKey)
            XCTAssertEqual(session.selectedEnumChoiceID(for: field), choice.id, field.propertyKey)
        }
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(session.currentInstanceJSON.utf8)) as? [String: Any]
        )
        XCTAssertEqual(object["integer"] as? Int, 2)
        XCTAssertEqual(object["number"] as? Double, 2.5)
        XCTAssertEqual(object["boolean"] as? Bool, true)
        XCTAssertTrue(object["nullable"] is NSNull)
        XCTAssertTrue(session.validate())
    }

    func testLockedAndConditionallyDisabledSelectionsDoNotMutateValues() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type":"object",
              "properties":{"enabled":{"type":"boolean","default":false}},
              "if":{"properties":{"enabled":{"const":true}},"required":["enabled"]},
              "then":{"properties":{"result":{
                "enum":["Pass","Failed"],"x-formkit-ui-component":"line-options-choice"
              }}}
            }
            """,
            instanceJSON: nil,
            conditionalRenderBehaviorOverrides: ["#/result": .disable]
        )
        let disabled = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "result" })
        XCTAssertTrue(disabled.isDisabled)
        let disabledRevision = session.revision
        FormKitLineOptionsChoice(context: context(disabled, in: session)).select(disabled.enumOptions[0])
        XCTAssertEqual(session.revision, disabledRevision)
        XCTAssertNil(session.selectedEnumChoiceID(for: disabled))

        let enabled = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "enabled" })
        session.setBooleanValue(true, for: enabled)
        let active = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "result" })
        XCTAssertFalse(active.isDisabled)
        let lockedRevision = session.revision
        FormKitLineOptionsChoice(context: context(active, in: session, locked: true)).select(active.enumOptions[0])
        XCTAssertEqual(session.revision, lockedRevision)
        XCTAssertNil(session.selectedEnumChoiceID(for: active))
    }

    private func context(
        _ field: FormKitFieldDescriptor,
        in session: FormKitSession,
        locked: Bool = false
    ) -> FormKitFieldComponentContext {
        FormKitFieldComponentContext(
            session: session,
            field: field,
            errors: [],
            state: .normal,
            isEditingLocked: locked,
            style: .init(),
            uploadHandler: nil
        )
    }
}
