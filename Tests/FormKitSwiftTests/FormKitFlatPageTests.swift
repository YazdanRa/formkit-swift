import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitFlatPageTests: XCTestCase {
    func testPresentationPagesKeepFlatAnswersAndCountTheirOwnQuestions() throws {
        let session = try makeSession(
            groups: [
                ["id": "request", "title": "Request", "fields": ["question", "title"]],
                ["id": "impact", "title": "Impact", "fields": ["priority", "reason"]]
            ],
            instance: ["title": "Example", "question": "Please confirm", "priority": "High", "reason": "Urgent"]
        )
        let pages = session.formPages
        XCTAssertEqual(pages.map(\.id), ["page:request", "page:impact"])
        guard pages.count == 2 else { return }
        XCTAssertEqual(pages.map(\.sectionID), ["#", "#"])
        XCTAssertEqual(pages[0].fieldIDs, ["#/title", "#/question"])
        XCTAssertEqual(pages[1].fieldIDs, ["#/priority", "#/reason", "#/other"])
        XCTAssertTrue(pages[0].isSectionField("#/title"))
        XCTAssertEqual(session.formSummary().pages.map(\.total), [2, 2])
        XCTAssertEqual(session.formSummary().pages.map(\.answered), [2, 1])
        XCTAssertTrue(session.validate())
        let object = try JSONSerialization.jsonObject(with: Data(session.currentInstanceJSON.utf8)) as? [String: String]
        XCTAssertEqual(object, [
            "title": "Example", "question": "Please confirm", "priority": "High", "reason": "Urgent"
        ])
        let reopened = try makeSession(groups: standardGroups, instance: object ?? [:])
        XCTAssertEqual(reopened.currentInstanceJSON, session.currentInstanceJSON)

        let index = FormKitRenderIndex(renderPlan: session.renderPlan)
        let rendered = pages.flatMap { index.pageBlocks(for: $0).flatMap(blockFieldIDs) }
        XCTAssertEqual(rendered, session.renderPlan.fieldOrder)
        XCTAssertEqual(Set(rendered).count, rendered.count)
        let navigator = FormKitPageNavigator(session: session)
        navigator.revealField("#/reason")
        XCTAssertEqual(navigator.position, .page(1))
        XCTAssertEqual(navigator.scrollTargetFieldID, "#/reason")
        XCTAssertEqual(session.pageIndex(containing: "#/title"), 0)
        let view = FormKitContainerView(
            session: session, externalFocusedFieldID: nil, options: .init(), pageNavigator: navigator
        )
        XCTAssertEqual(view.focusScope(pages: pages), Set(pages[1].fieldIDs))
        let pageIndex = FormKitRenderIndex(renderPlan: session.renderPlan, focusableFieldIDs: Set(pages[0].fieldIDs))
        XCTAssertEqual(pageIndex.nextFocusableFieldID(after: "#/title"), "#/question")
        XCTAssertNil(pageIndex.nextFocusableFieldID(after: "#/question"))
    }

    func testHiddenGroupsDisappearAndReappearWithCommittedAnswers() throws {
        let session = try makeSession(groups: [
            ["id": "request", "title": "Request", "fields": ["title", "question", "priority"]],
            ["id": "reason", "title": "Explanation", "fields": ["reason"]],
            ["id": "other", "title": "Other", "fields": ["other"]]
        ])
        XCTAssertEqual(session.formPages.map(\.id), ["page:request", "page:other"])
        let priority = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "priority" })
        session.setSelectedEnumChoiceID("string:High", for: priority)
        XCTAssertEqual(session.formPages.map(\.id), ["page:request", "page:reason", "page:other"])
        let reason = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "reason" })
        session.setStringValue("Keep draft", for: reason)
        session.unsetValue(for: priority)
        XCTAssertEqual(session.formPages.map(\.id), ["page:request", "page:other"])
        XCTAssertNil(session.pageIndex(containing: reason.id))
        session.setSelectedEnumChoiceID("string:High", for: priority)
        XCTAssertEqual(session.stringValue(for: reason), "Keep draft")
        XCTAssertEqual(session.formPages.flatMap(\.fieldIDs), session.renderPlan.fieldOrder)
    }

    func testUnknownOrganizationFieldsAreIgnoredAndUnassignedFieldsJoinLastPage() throws {
        let session = try makeSession(groups: [
            ["id": "unused", "title": "Unused", "fields": ["missing"]],
            ["id": "request", "title": "Request", "fields": ["title", "unknown"]],
            ["id": "details", "title": "Details", "fields": ["question"]]
        ])
        XCTAssertEqual(session.formPages.map(\.title), ["Request", "Details"])
        guard session.formPages.count == 2 else { return }
        XCTAssertEqual(session.formPages[1].fieldIDs, ["#/question", "#/priority", "#/other"])
        XCTAssertEqual(
            Set(session.formPages.flatMap(\.fieldIDs)), Set(session.renderPlan.fields.filter(\.isVisible).map(\.id))
        )
    }

    func testMalformedOrDuplicateMetadataFallsBackToScroll() throws {
        let invalid: [Any] = [
            "request",
            [["id": "first", "title": "First", "fields": "title"]],
            [["id": "", "title": "First", "fields": ["title"]]],
            [["id": "first", "title": " ", "fields": ["title"]]],
            [["id": "first", "title": "First", "fields": ["title", 3]]],
            [["id": "first", "title": "First", "fields": ["title", "title"]]],
            [["id": "first", "title": "First", "fields": ["title"]],
             ["id": "first", "title": "Second", "fields": ["question"]]],
            [["id": "first", "title": "First", "fields": ["title"]],
             ["id": "second", "title": "Second", "fields": ["title", "question"]]]
        ]
        for groups in invalid {
            let session = try makeSession(groups: groups)
            XCTAssertTrue(session.renderPlan.isSupported)
            XCTAssertTrue(session.formPages.isEmpty, "Invalid metadata must retain a scrolling form: \(groups)")
            XCTAssertFalse(FormKitRenderIndex(renderPlan: session.renderPlan).visibleRootBlocks.isEmpty)
        }
        XCTAssertTrue(try makeSession(groups: [["id": "only", "title": "Only", "fields": ["title"]]]).formPages.isEmpty)
    }

    func testWholeObjectsAndEmptyArraysUseExistingDisplayBlocks() throws {
        let schema = #"""
        {
          "type":"object", "x-formkit-layout":"section-pages",
          "x-formkit-pages":[
            {"id":"person","title":"Person","fields":["person"]},
            {"id":"items","title":"Items","fields":["items"]}
          ],
          "properties":{
            "person":{"type":"object","x-formkit-order":0,"properties":{"name":{"type":"string"}}},
            "items":{"type":"array","x-formkit-order":1,"items":{"type":"string"}},
            "a/b~c":{"type":"string","x-formkit-order":2}
          }
        }
        """#
        let session = FormKitRenderer().makeFormSession(schemaJSON: schema)
        let pages = session.formPages
        XCTAssertEqual(pages.count, 2)
        guard pages.count == 2 else { return }
        XCTAssertEqual(pages[0].fieldIDs, ["#/person/name"])
        XCTAssertEqual(pages[1].fieldIDs, ["#/a~1b~0c"])
        XCTAssertEqual(pages[1].loosePointers, ["#/items", "#/a~1b~0c"])
        let index = FormKitRenderIndex(renderPlan: session.renderPlan)
        XCTAssertEqual(index.pageBlocks(for: pages[0]).flatMap(blockFieldIDs), ["#/person/name"])
        let arraySectionID = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/items" }?.id)
        XCTAssertTrue(index.pageBlocks(for: pages[1]).contains { $0.kind == .section(arraySectionID) })
        XCTAssertTrue(pages[1].holds(pointer: "#/items"))
        let arraySection = try XCTUnwrap(session.renderPlan.sections.first { $0.pointer == "#/items" })
        session.appendArrayRow(to: arraySection)
        XCTAssertEqual(session.formPages[1].fieldIDs, ["#/items/0", "#/a~1b~0c"])
        XCTAssertEqual(session.pageIndex(containing: "#/items/0"), 1)
    }

    func testInvalidExplicitGroupsKeepFullScrollEvenWhenObjectSectionsExist() throws {
        let schema = #"""
        {"type":"object","x-formkit-layout":"section-pages","properties":{
          "first":{"type":"object","properties":{"name":{"type":"string"}}},
          "second":{"type":"object","properties":{"note":{"type":"string"}}}
        }}
        """#
        XCTAssertEqual(FormKitRenderer().makeFormSession(schemaJSON: schema).formPages.count, 2)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(schema.utf8)) as? [String: Any])
        for invalid in [NSNull(), "bad", []] as [Any] {
            object["x-formkit-pages"] = invalid
            let json = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: object), encoding: .utf8))
            let session = FormKitRenderer().makeFormSession(schemaJSON: json)
            XCTAssertTrue(session.formPages.isEmpty)
            XCTAssertEqual(session.renderPlan.fields.count, 2)
        }
    }

    func testEmptyObjectGroupsAreSkippedButNestedEmptyArraysStayActionable() {
        let session = FormKitRenderer(includesHiddenToolFields: true).makeFormSession(schemaJSON: #"""
        {
          "type":"object", "x-formkit-layout":"section-pages",
          "x-formkit-pages":[
            {"id":"empty","title":"Empty","fields":["empty","conditional"]},
            {"id":"request","title":"Request","fields":["title"]},
            {"id":"items","title":"Items","fields":["container"]}
          ],
          "properties":{
            "empty":{"type":"object","properties":{}},
            "conditional":{
              "type":"object",
              "if":{"properties":{"show":{"const":true}},"required":["show"]},
              "then":{"properties":{"note":{"type":"string"}}}
            },
            "title":{"type":"string"},
            "container":{"type":"object","properties":{"items":{"type":"array","items":{"type":"string"}}}}
          }
        }
        """#)
        XCTAssertTrue(session.renderPlan.isSupported)
        XCTAssertEqual(session.formPages.map(\.id), ["page:request", "page:items"])
        XCTAssertEqual(session.formPages.last?.loosePointers, ["#/container"])
        let array = session.renderPlan.sections.first { $0.pointer == "#/container/items" }
        XCTAssertNotNil(array)
        let index = FormKitRenderIndex(renderPlan: session.renderPlan)
        if let page = session.formPages.last, let array {
            XCTAssertTrue(index.pageBlocks(for: page).contains { $0.kind == .section(array.id) })
        }
    }

    private func blockFieldIDs(_ block: FormKitRenderIndex.DisplayBlock) -> [String] {
        if case let .fieldGroup(_, fieldIDs) = block.kind {
            return fieldIDs
        }
        return []
    }

    private var standardGroups: [[String: Any]] {
        [
            ["id": "request", "title": "Request", "fields": ["title", "question"]],
            ["id": "impact", "title": "Impact", "fields": ["priority", "reason"]]
        ]
    }

    private func makeSession(groups: Any, instance: [String: String] = [:]) throws -> FormKitSession {
        var schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Self.schema.utf8)) as? [String: Any])
        schema["x-formkit-pages"] = groups
        let schemaJSON = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: schema), encoding: .utf8))
        let instanceJSON = try XCTUnwrap(
            String(data: JSONSerialization.data(withJSONObject: instance), encoding: .utf8)
        )
        return FormKitRenderer(includesHiddenToolFields: true).makeFormSession(
            schemaJSON: schemaJSON, instanceJSON: instanceJSON
        )
    }

    private static let schema = #"""
    {
      "type":"object", "additionalProperties":false, "x-formkit-layout":"section-pages",
      "properties":{
        "title":{"type":"string","x-formkit-order":0},
        "question":{"type":"string","x-formkit-order":1},
        "priority":{"type":"string","enum":["High","Low"],"x-formkit-order":2},
        "reason":{"type":"string","x-formkit-order":3},
        "other":{"type":"string","x-formkit-order":4}
      },
      "allOf":[{
        "if":{"properties":{"priority":{"const":"High"}},"required":["priority"]},
        "then":{"properties":{"reason":{"type":"string","x-formkit-order":3}}}
      }]
    }
    """#
}
