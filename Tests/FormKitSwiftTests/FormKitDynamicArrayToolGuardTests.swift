import XCTest
@testable import FormKitSwift

extension FormKitDynamicArrayToolTests {
    func testMetadataAndFocusedLocksAreAdditiveAndPointersStayNormalized() throws {
        let form = FormKitRenderer().makeFormSession(
            schemaJSON: try schema(minimum: 1, maximum: 2), instanceJSON: try instanceJSON(["saved"])
        )
        let context = form.makeToolContext()
        XCTAssertEqual(parent(in: context)?.minItems, 1)
        XCTAssertEqual(parent(in: context)?.maxItems, 2)
        XCTAssertNil(context.fields.first { $0.pointer == "/equipment/0" }?.minItems)
        let legacy = FormKitToolField(pointer: "/legacy", title: "Legacy", type: "string", isRequired: false)
        XCTAssertNil(legacy.minItems)
        XCTAssertNil(legacy.maxItems)
        for pointer in ["/equipment", "#/equipment/0"] {
            XCTAssertEqual(parent(in: form.makeToolContext(focusedPointers: [pointer]))?.isLocked, true)
        }
        XCTAssertEqual(parent(in: form.makeToolContext(focusedPointers: ["/equipmentExtra"]))?.isLocked, false)
        let result = form.applyToolEdits([.init(pointer: "#/equipment", operation: .set, value: array(["new"]))])
        XCTAssertEqual(result.appliedEdits.first?.pointer, "/equipment")
        XCTAssertTrue(result.rejectedEdits.isEmpty)
    }

    func testWholeArrayRejectsEveryInactiveBehaviorEvenWithHiddenContextOptIn() throws {
        for hidden in [false, true] {
            for behavior in [FormKitConditionalRenderBehavior.hide, .disable, .ignore] {
                let form = FormKitRenderer(defaultConditionalRenderBehavior: behavior,
                                               includesHiddenToolFields: hidden).makeFormSession(
                    schemaJSON: conditionalSchema,
                    instanceJSON: #"{"enabled":true,"equipment":["saved"],"hiddenScalar":"Original"}"#
                )
                let enabled = try XCTUnwrap(form.renderPlan.fields.first { $0.pointer == "#/enabled" })
                form.setBooleanValue(false, for: enabled)
                assertRejected(form, .init(pointer: "/equipment", operation: .set, value: array(["new"])))
                assertRejected(form, .init(pointer: "/equipment", operation: .clear))
                assertRejected(form, .init(pointer: "/equipment/0", operation: .set, value: .string("denied")))
                assertRejected(form, .init(pointer: "/equipment/0", operation: .clear))
                if let child = form.makeToolContext().fields.first(where: { $0.pointer == "/equipment/0" }) {
                    XCTAssertTrue(child.isLocked)
                }
                if hidden && behavior == .hide {
                    let result = form.applyToolEdits([
                        .init(pointer: "/hiddenScalar", operation: .set, value: .string("Still allowed"))
                    ])
                    XCTAssertTrue(result.rejectedEdits.isEmpty)
                    XCTAssertEqual(result.context.currentValues["/hiddenScalar"], .string("Still allowed"))
                }
                form.setBooleanValue(true, for: enabled)
                if hidden && behavior != .disable {
                    XCTAssertEqual(try equipmentValue(form), array(["saved"]), "hidden=\(hidden), behavior=\(behavior)")
                }
                let active = form.applyToolEdits([.init(pointer: "/equipment", operation: .set, value: array(["new"]))])
                XCTAssertTrue(active.rejectedEdits.isEmpty)
                let slot = form.applyToolEdits([.init(pointer: "/equipment/0", operation: .set, value: .string("ok"))])
                XCTAssertTrue(slot.rejectedEdits.isEmpty)
                XCTAssertEqual(try equipmentValue(form), array(["ok"]))
                let cleared = form.applyToolEdits([.init(pointer: "/equipment/0", operation: .clear)])
                XCTAssertTrue(cleared.rejectedEdits.isEmpty)
                XCTAssertEqual(try equipmentValue(form), array([""]))
            }
        }
    }

    func testParentReplacementProtectsLockedDescendantsWithoutPrefixCollisions() throws {
        for lock in ["/equipment", "#/equipment", "/equipment/0", "#/equipment/0"] {
            let form = FormKitRenderer().makeFormSession(
                schemaJSON: try schema(), instanceJSON: try instanceJSON(["saved"])
            )
            assertRejected(form, .init(pointer: "/equipment", operation: .set, value: array(["new"])),
                                    locks: [lock], reason: "field_locked")
            assertRejected(form, .init(pointer: "/equipment", operation: .clear),
                                    locks: [lock], reason: "field_locked")
        }
        let form = FormKitRenderer().makeFormSession(schemaJSON: try schema())
        let result = form.applyToolEdits([.init(pointer: "/equipment", operation: .set, value: array(["new"]))],
                                            lockedPointers: ["/equipmentExtra", "/equipmentToo/0"])
        XCTAssertTrue(result.rejectedEdits.isEmpty)
        XCTAssertEqual(try equipmentValue(form), array(["new"]))
    }

    func testTypeAndCardinalityRejectionsDoNotMutateAndDuplicatesUseRawCount() throws {
        let form = FormKitRenderer().makeFormSession(
            schemaJSON: try schema(minimum: 1, maximum: 2), instanceJSON: try instanceJSON(["keep"])
        )
        let invalid: [FormKitJSONValue?] = [nil, .null, .string("wrong"), .integer(1),
            .array([.null]), .array([.integer(1)]), .array([.string("valid"), .boolean(true)]),
            .array([]), array(["one", "two", "three"])]
        for value in invalid {
            assertRejected(form, .init(pointer: "/equipment", operation: .set, value: value))
        }
        assertRejected(form, .init(pointer: "/equipment", operation: .clear))
        let duplicate = array(["", ""])
        let result = form.applyToolEdits([.init(pointer: "/equipment", operation: .set, value: duplicate)])
        XCTAssertTrue(result.rejectedEdits.isEmpty)
        XCTAssertEqual(try equipmentValue(form), duplicate)
        let section = try XCTUnwrap(form.renderPlan.sections.first { $0.pointer == "#/equipment" })
        form.setArrayValue([], for: section)
        XCTAssertEqual(try equipmentValue(form), .array([]))
        XCTAssertFalse(form.validate())
    }

    func testParentLocksProtectIndexedChildrenWithoutLockingTheirSiblings() throws {
        let form = FormKitRenderer().makeFormSession(schemaJSON: try schema(),
                                                        instanceJSON: try instanceJSON(["first", "second"]))
        let context = form.makeToolContext(focusedPointers: ["/equipment"])
        XCTAssertEqual(context.fields.first { $0.pointer == "/equipment/0" }?.isLocked, true)
        assertRejected(form, .init(pointer: "/equipment/0", operation: .set, value: .string("denied")),
                                locks: ["/equipment"], reason: "field_locked")
        let sibling = form.applyToolEdits([.init(pointer: "/equipment/1", operation: .set, value: .string("allowed"))],
                                             lockedPointers: ["/equipment/0"])
        XCTAssertTrue(sibling.rejectedEdits.isEmpty)
        XCTAssertEqual(try equipmentValue(form), array(["first", "allowed"]))
        let nested = FormKitRenderer().makeFormSession(schemaJSON: pagedSchema,
                                                        instanceJSON: #"{"second":{"equipment":["saved"]}}"#)
        assertRejected(nested, .init(pointer: "/second/equipment/0", operation: .clear),
                                locks: ["/second"], reason: "field_locked")
    }

    func testStaleBatchesAndCurrentConditionalStateUseExistingTransactionRules() throws {
        let form = FormKitRenderer().makeFormSession(schemaJSON: try schema())
        let oldRevision = form.revision
        _ = form.applyToolEdits([.init(pointer: "/equipment", operation: .set, value: array(["first"]))])
        let before = form.currentInstanceJSON
        let revision = form.revision
        let result = form.applyToolEdits([
            .init(pointer: "/equipment", operation: .clear),
            .init(pointer: "/note", operation: .set, value: .string("No"))
        ], baseRevision: oldRevision)
        XCTAssertTrue(result.appliedEdits.isEmpty)
        XCTAssertEqual(result.rejectedEdits.map(\.reason), ["revision_conflict", "revision_conflict"])
        XCTAssertEqual(form.currentInstanceJSON, before)
        XCTAssertEqual(form.revision, revision)
        let conditional = FormKitRenderer(defaultConditionalRenderBehavior: .ignore, includesHiddenToolFields: true)
            .makeFormSession(schemaJSON: conditionalSchema, instanceJSON: #"{"enabled":true,"equipment":["saved"]}"#)
        let changed = conditional.applyToolEdits([
            .init(pointer: "/enabled", operation: .set, value: .boolean(false)),
            .init(pointer: "/equipment", operation: .set, value: array(["denied"]))
        ])
        XCTAssertEqual(changed.appliedEdits.map(\.pointer), ["/enabled"])
        XCTAssertEqual(changed.rejectedEdits.map(\.pointer), ["/equipment"])
        XCTAssertEqual(try equipmentValue(conditional), array(["saved"]))
        let bounded = FormKitRenderer().makeFormSession(schemaJSON: currentBoundsSchema,
                                                        instanceJSON: #"{"enabled":false,"equipment":["keep"]}"#)
        XCTAssertTrue(bounded.renderPlan.isSupported)
        let restricted = bounded.applyToolEdits([
            .init(pointer: "/enabled", operation: .set, value: .boolean(true)),
            .init(pointer: "/equipment", operation: .set, value: array(["one", "two"]))
        ])
        XCTAssertEqual(restricted.appliedEdits.map(\.pointer), ["/enabled"])
        XCTAssertEqual(restricted.rejectedEdits.map(\.pointer), ["/equipment"])
        XCTAssertEqual(try equipmentValue(bounded), array(["keep"]))
    }

    func testLaterPageArrayIsEligibleAndItemConstraintsKeepNormalValidation() throws {
        let form = FormKitRenderer().makeFormSession(schemaJSON: pagedSchema)
        let navigator = FormKitPageNavigator(session: form)
        XCTAssertEqual(form.formPages.count, 2)
        XCTAssertFalse(form.validate())
        let result = form.applyToolEdits([
            .init(pointer: "/second/equipment", operation: .set, value: array([""]))
        ])
        XCTAssertTrue(result.rejectedEdits.isEmpty)
        XCTAssertEqual(result.appliedEdits.count, 1)
        XCTAssertEqual(result.context.currentValues["/second/equipment"], array([""]))
        let item = try XCTUnwrap(form.renderPlan.fields.first { $0.pointer == "#/second/equipment/0" })
        let errors = form.errorMessages(for: item)
        XCTAssertFalse(errors.isEmpty)
        XCTAssertTrue(errors.allSatisfy(result.validationMessages.contains))
        XCTAssertFalse(form.validate())
        XCTAssertEqual(navigator.currentPage, 0)
    }

    func testOrdinaryAndIncompatibleCollectionsRetainIndexedToolsOnly() throws {
        for (component, items) in [("", ["type": "string"] as [String: Any]),
            ("dynamic-options", ["type": ["string", "null"]]),
            ("dynamic-options", ["type": "string", "enum": ["keep", "other"]]),
            ("dynamic-options", ["type": "string", "const": "keep"]),
            ("dynamic-options", ["type": "string", "format": "email"])]
        {
            let form = FormKitRenderer().makeFormSession(schemaJSON: try schema(component: component, items: items),
                                                            instanceJSON: try instanceJSON(["keep"]))
            XCTAssertNil(parent(in: form.makeToolContext()))
            XCTAssertNotNil(form.makeToolContext().fields.first { $0.pointer == "/equipment/0" })
            assertRejected(form, .init(pointer: "/equipment", operation: .set, value: array(["new"])))
            let legacy = form.applyToolEdits([.init(pointer: "/equipment/0", operation: .set, value: .string("keep"))])
            XCTAssertTrue(legacy.rejectedEdits.isEmpty)
        }
        let nullable = FormKitRenderer().makeFormSession(schemaJSON: try schema(containerType: ["array", "null"]))
        XCTAssertFalse(nullable.renderPlan.isSupported)
        XCTAssertNil(parent(in: nullable.makeToolContext()))
        assertRejected(nullable, .init(pointer: "/equipment", operation: .set, value: array(["new"])))
    }

    func testUnrelatedInitialEditedAndDefaultValuesKeepTheirSources() throws {
        for edited in [false, true] {
            let form = FormKitRenderer().makeFormSession(schemaJSON: try schema(),
                                                            instanceJSON: try instanceJSON(["saved"], note: "Supplied"))
            if edited {
                _ = form.applyToolEdits([.init(pointer: "/note", operation: .set, value: .string("Edited"))])
            }
            let result = form.applyToolEdits([.init(pointer: "/equipment", operation: .set, value: array(["new"]))])
            XCTAssertTrue(result.rejectedEdits.isEmpty)
            XCTAssertEqual(result.context.currentValues["/note"], .string(edited ? "Edited" : "Supplied"))
            XCTAssertEqual(result.context.fields.first { $0.pointer == "/note" }?.valueSource,
                           edited ? .sessionEdit : .initialInstance)
            XCTAssertEqual(result.context.currentValues["/otherDefault"], .string("Keep"))
            XCTAssertEqual(result.context.fields.first { $0.pointer == "/otherDefault" }?.valueSource, .defaultValue)
            XCTAssertEqual(result.context.fields.first { $0.pointer == "/equipment/0" }?.valueSource, .sessionEdit)
        }
    }

    func testGeneratedRowsRemainDefaultSourcedUntilWholeCollectionConfirmation() throws {
        let form = FormKitRenderer().makeFormSession(schemaJSON: try schema(defaultIDs: ["default"]))
        let section = try XCTUnwrap(form.renderPlan.sections.first { $0.pointer == "#/equipment" })
        form.appendArrayRow(to: section)
        XCTAssertEqual(parent(in: form.makeToolContext())?.valueSource, .defaultValue)
        _ = form.applyToolEdits([.init(pointer: "/equipment/1", operation: .set, value: .string("confirmed"))])
        XCTAssertEqual(parent(in: form.makeToolContext())?.valueSource, .defaultValue)
        let value = try XCTUnwrap(try equipmentValue(form))
        let before = form.currentInstanceJSON
        let result = form.applyToolEdits([.init(pointer: "/equipment", operation: .set, value: value)])
        XCTAssertTrue(result.rejectedEdits.isEmpty)
        XCTAssertEqual(parent(in: result.context)?.valueSource, .sessionEdit)
        XCTAssertEqual(form.currentInstanceJSON, before)
    }

    private var conditionalSchema: String {
        #"""
        {"type":"object","properties":{"enabled":{"type":"boolean"}},
          "if":{"properties":{"enabled":{"const":true}},"required":["enabled"]},
          "then":{"properties":{"hiddenScalar":{"type":"string"},"equipment":{"type":"array",
            "minItems":0,"items":{"type":"string"},"x-formkit-ui-component":"dynamic-options"}}}}
        """#
    }

    private var currentBoundsSchema: String {
        #"""
        {"type":"object","properties":{"enabled":{"type":"boolean"},"equipment":{"type":"array",
          "maxItems":2,"items":{"type":"string"},"x-formkit-ui-component":"dynamic-options"}},
          "if":{"properties":{"enabled":{"const":true}},"required":["enabled"]},
          "then":{"properties":{"equipment":{"maxItems":1}}}}
        """#
    }

    private var pagedSchema: String {
        #"""
        {"type":"object","x-formkit-layout":"section-pages","required":["second"],"properties":{
          "first":{"type":"object","x-formkit-order":0,"properties":{"note":{"type":"string"}}},
          "second":{"type":"object","x-formkit-order":1,"required":["equipment"],"properties":{
            "equipment":{"type":"array","minItems":1,"items":{"type":"string","minLength":1},
              "x-formkit-ui-component":"dynamic-options"}}}}}
        """#
    }
}
