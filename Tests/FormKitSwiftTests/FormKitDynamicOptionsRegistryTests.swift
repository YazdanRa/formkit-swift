import SwiftUI
import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitDynamicOptionsRegistryTests: XCTestCase {
    func testRegistryRequiresSourceAndCompatibleStringShape() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: compatibilitySchema)
        var factoryCalls: [String] = []
        var providerCalls = 0
        let options = FormKitOptions(dynamicOptions: { context in
            factoryCalls.append(context.pointer)
            return FormKitDynamicOptionsSource { _, _ in
                providerCalls += 1
                return FormKitDynamicOptionsPage(options: [])
            }
        })
        for field in session.renderPlan.fields.filter({ !$0.pointer.contains("/0") }) {
            let context = fieldContext(field, session: session)
            XCTAssertNil(FormKitComponentRegistry.fieldInput(for: context))
            let resolved = FormKitComponentRegistry.fieldInput(for: context, dynamicOptions: options.dynamicOptions)
            XCTAssertEqual(resolved != nil, field.propertyKey == "contact", field.pointer)
        }
        for section in session.renderPlan.sections where section.isArraySection {
            let context = try arrayContext(section, session: session)
            XCTAssertNil(FormKitComponentRegistry.arraySection(for: context))
            let resolved = FormKitComponentRegistry.arraySection(for: context, dynamicOptions: options.dynamicOptions)
            XCTAssertEqual(resolved != nil, section.propertyKey == "equipment", section.pointer)
        }
        XCTAssertEqual(Set(factoryCalls), ["#/contact", "#/equipment"])
        XCTAssertEqual(providerCalls, 0)
    }

    func testFactoryReceivesActualNestedPointerAndUnmodifiedSavedIDs() {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: nestedSchema,
            instanceJSON: #"{"team":{"contact":null,"members":["unknown-user"]}}"#
        )
        var contexts: [FormKitDynamicOptionsContext] = []
        let revision = session.revision
        let resolved = FormKitFocusSupport.resolvedComponents(session: session, options: FormKitOptions(
            dynamicOptions: { context in
                contexts.append(context)
                return FormKitDynamicOptionsSource(savedOptions: context.selectedIDs.map {
                    FormKitDynamicOption(id: $0, label: "Saved option")
                }) { _, _ in FormKitDynamicOptionsPage(options: []) }
            }
        ))
        XCTAssertEqual(Set(contexts.map(\.pointer)), ["#/team/contact", "#/team/members", "#/equipment"])
        XCTAssertEqual(contexts.first { $0.pointer == "#/team/members" }?.selectedIDs, ["unknown-user"])
        XCTAssertEqual(contexts.first { $0.pointer == "#/team/contact" }?.selectedIDs, [])
        XCTAssertEqual(resolved.arraySections.count, 1)
        XCTAssertEqual(session.revision, revision)
        XCTAssertTrue(session.currentInstanceJSON.contains("unknown-user"))
    }

    func testScalarBindingClearsNullableToNullAndOptionalStringToOmission() throws {
        let session = FormKitRenderer().makeFormSession(schemaJSON: nestedSchema)
        let nullable = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/team/contact" })
        let selection = FormKitDynamicOptionsContext.field(fieldContext(nullable, session: session)).selection()
        selection.choose("company-contact:7", isRequired: false)
        XCTAssertEqual(selection.ids, ["company-contact:7"])
        selection.clear(isRequired: false)
        let current = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == nullable.pointer })
        XCTAssertEqual(session.primitiveValue(for: current), .null)
        let equipment = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/equipment" })
        let equipmentContext = FormKitDynamicOptionsContext.field(fieldContext(equipment, session: session))
        let equipmentSelection = equipmentContext.selection()
        equipmentSelection.choose("tool:42", isRequired: false)
        equipmentSelection.clear(isRequired: false)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(session.currentInstanceJSON.utf8))
            as? [String: Any])
        XCTAssertNil(object["equipment"])
    }

    func testArrayBindingResolvesFreshDescriptorAcrossRepeatedMutationsAndKeepsOversizedIDs() throws {
        let ids = (1...52).map { "equipment:\($0)" }
        let data = try JSONSerialization.data(withJSONObject: ["team": ["members": ids]])
        let session = FormKitRenderer().makeFormSession(schemaJSON: nestedSchema,
                                                       instanceJSON: try XCTUnwrap(String(data: data, encoding: .utf8)))
        let section = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/team/members" })
        let context = FormKitDynamicOptionsContext.arraySection(try arrayContext(section, session: session))
        let selection = context.selection()
        let revision = session.revision
        XCTAssertEqual(context.selectedIDs, ids)
        XCTAssertEqual(session.revision, revision)
        selection.choose(try XCTUnwrap(ids.last), isRequired: false, maximumSelectionCount: 50)
        XCTAssertEqual(context.selectedIDs, Array(ids.dropLast()))
        selection.choose(try XCTUnwrap(ids.first), isRequired: false, maximumSelectionCount: 50)
        XCTAssertEqual(context.selectedIDs.count, 50)
        selection.clear(isRequired: false)
        XCTAssertTrue(context.selectedIDs.isEmpty)
        let current = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == section.pointer })
        XCTAssertEqual(session.arrayValue(for: current), [])
    }

    func testHostOverridesWinWithoutInvokingDynamicFactory() {
        let session = FormKitRenderer().makeFormSession(schemaJSON: compatibilitySchema)
        var calls = 0
        let resolved = FormKitFocusSupport.resolvedComponents(session: session, options: FormKitOptions(
            components: FormKitComponents(fieldInput: { _ in AnyView(Text("Host field")) },
                                          arraySection: { _ in AnyView(Text("Host array")) }),
            dynamicOptions: { _ in
                calls += 1
                return nil
            }
        ))
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(resolved.fieldInputs.isEmpty)
        XCTAssertFalse(resolved.arraySections.isEmpty)
    }

    private func fieldContext(
        _ field: FormKitFieldDescriptor,
        session: FormKitSession
    ) -> FormKitFieldComponentContext {
        FormKitFieldComponentContext(session: session, field: field, errors: [], state: .normal,
                                     isEditingLocked: false, style: .init(), uploadHandler: nil)
    }

    private func arrayContext(_ section: FormKitRenderPlan.SectionDescriptor,
                              session: FormKitSession) throws -> FormKitArraySectionComponentContext
    {
        FormKitArraySectionComponentContext(session: session, section: section,
                                            descriptor: try XCTUnwrap(section.arrayDescriptor), errors: [],
                                            isEditingLocked: false, style: .init(), labels: .init(), uploadHandler: nil)
    }

    private var compatibilitySchema: String {
        #"""
        {
          "type": "object",
          "properties": {
            "contact": {
              "type": [
                "string",
                "null"
              ],
              "x-formkit-ui-component": "dynamic-options"
            },
            "date": {
              "type": "string",
              "format": "date",
              "x-formkit-ui-component": "dynamic-options"
            },
            "number": {
              "type": "number",
              "x-formkit-ui-component": "dynamic-options"
            },
            "enum": {
              "type": "string",
              "enum": [
                "a",
                "b"
              ],
              "x-formkit-ui-component": "dynamic-options"
            },
            "equipment": {
              "type": "array",
              "items": {
                "type": "string"
              },
              "x-formkit-ui-component": "dynamic-options"
            },
            "fixedArray": {
              "type": "array",
              "items": {
                "type": "string",
                "enum": [
                  "a"
                ]
              },
              "x-formkit-ui-component": "dynamic-options"
            },
            "numericArray": {
              "type": "array",
              "items": {
                "type": "number"
              },
              "x-formkit-ui-component": "dynamic-options"
            },
            "objects": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "x": {
                    "type": "string"
                  }
                }
              },
              "x-formkit-ui-component": "dynamic-options"
            }
          }
        }
        """#
    }

    private var nestedSchema: String {
        #"""
        {
          "type": "object",
          "properties": {
            "team": {
              "type": "object",
              "properties": {
                "contact": {
                  "type": [
                    "string",
                    "null"
                  ],
                  "x-formkit-ui-component": "dynamic-options"
                },
                "members": {
                  "type": "array",
                  "minItems": 0,
                  "maxItems": 50,
                  "items": {
                    "type": "string"
                  },
                  "x-formkit-ui-component": "dynamic-options"
                }
              }
            },
            "equipment": {
              "type": "string",
              "x-formkit-ui-component": "dynamic-options"
            }
          }
        }
        """#
    }
}

extension FormKitDynamicOptionsRegistryTests {
    func testNullableArrayItemsKeepNullEntriesAndUseStockFallback() throws {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: #"""
            {"type":"object","properties":{
              "equipment":{"type":"array","items":{"type":["string","null"]},
                           "x-formkit-ui-component":"dynamic-options"}
            }}
            """#,
            instanceJSON: #"{"equipment":[null,"equipment:1"]}"#
        )
        XCTAssertTrue(session.renderPlan.isSupported)
        let section = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/equipment" })
        let context = try arrayContext(section, session: session)
        XCTAssertTrue(context.descriptor.itemAllowsNull)
        let before = session.currentInstanceJSON
        let revision = session.revision
        var factoryCalls = 0
        let component = FormKitComponentRegistry.arraySection(for: context, dynamicOptions: { _ in
            factoryCalls += 1
            return FormKitDynamicOptionsSource { _, _ in FormKitDynamicOptionsPage(options: []) }
        })
        XCTAssertNil(component)
        XCTAssertEqual(factoryCalls, 0)
        XCTAssertEqual(session.arrayValue(for: section), [.null, .string("equipment:1")])
        XCTAssertEqual(session.currentInstanceJSON, before)
        XCTAssertEqual(session.revision, revision)
    }

    func testScalarEligibilityRechecksAtWriteAndStillAllowsRetentionAndClear() throws {
        let eligibility = DynamicOptionEligibility()
        let source = FormKitDynamicOptionsSource(canSelect: eligibility.canSelect, provider: { _, _ in
            FormKitDynamicOptionsPage(options: [FormKitDynamicOption(id: "new-id", label: "Option")])
        })
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: nestedSchema,
            instanceJSON: #"{"team":{"contact":"legacy-id"}}"#
        )
        let field = try XCTUnwrap(session.renderPlan.fields.first { $0.pointer == "#/team/contact" })
        let context = FormKitDynamicOptionsContext.field(fieldContext(field, session: session))
        let selection = context.selection(canSelect: source.canSelect)
        let revision = session.revision
        XCTAssertEqual(selection.ids, ["legacy-id"])
        XCTAssertEqual(session.revision, revision)
        selection.choose("new-id", isRequired: false)
        XCTAssertEqual(context.selectedIDs, ["new-id"])
        eligibility.allowed = false
        selection.choose("denied-id", isRequired: false)
        XCTAssertEqual(context.selectedIDs, ["new-id"])
        selection.choose("new-id", isRequired: false)
        XCTAssertEqual(context.selectedIDs, ["new-id"])
        selection.clear(isRequired: false)
        XCTAssertTrue(context.selectedIDs.isEmpty)
    }

    func testArrayEligibilityDeniesOnlyNewIDsAfterPermissionChange() throws {
        let eligibility = DynamicOptionEligibility()
        let source = FormKitDynamicOptionsSource(canSelect: eligibility.canSelect,
                                                 provider: { _, _ in FormKitDynamicOptionsPage(options: []) })
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: nestedSchema,
            instanceJSON: #"{"team":{"members":["unavailable-legacy"]}}"#
        )
        let section = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/team/members" })
        let context = FormKitDynamicOptionsContext.arraySection(try arrayContext(section, session: session))
        let selection = context.selection(canSelect: source.canSelect)
        let revision = session.revision
        XCTAssertEqual(context.selectedIDs, ["unavailable-legacy"])
        XCTAssertEqual(session.revision, revision)
        XCTAssertTrue(eligibility.checkedIDs.isEmpty)
        selection.choose("allowed-id", isRequired: false)
        XCTAssertEqual(context.selectedIDs, ["unavailable-legacy", "allowed-id"])
        eligibility.allowed = false
        selection.choose("new-denied-id", isRequired: false)
        XCTAssertEqual(context.selectedIDs, ["unavailable-legacy", "allowed-id"])
        selection.choose("allowed-id", isRequired: false)
        XCTAssertEqual(context.selectedIDs, ["unavailable-legacy"])
        selection.choose("unavailable-legacy", isRequired: false)
        XCTAssertTrue(context.selectedIDs.isEmpty)
        XCTAssertEqual(eligibility.checkedIDs, ["allowed-id", "new-denied-id"])
    }

}

@MainActor
private final class DynamicOptionEligibility {
    var allowed = true
    var checkedIDs: [String] = []

    func canSelect(_ id: String) -> Bool {
        checkedIDs.append(id)
        return allowed
    }
}
