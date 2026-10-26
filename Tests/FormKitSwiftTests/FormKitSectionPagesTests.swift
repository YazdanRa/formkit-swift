import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitSectionPagesTests: XCTestCase {
    func testLayoutReadsSectionPagesAndKeepsScrollForOtherValues() {
        XCTAssertEqual(FormKitFormLayout(schemaValue: "section-pages"), .sectionPages)
        XCTAssertEqual(FormKitFormLayout(schemaValue: " Section-Pages "), .sectionPages)
        XCTAssertEqual(FormKitFormLayout(schemaValue: "wizard"), .scroll)
        XCTAssertEqual(FormKitFormLayout(schemaValue: nil), .scroll)

        XCTAssertEqual(makeSession().renderPlan.layout, .sectionPages)
        XCTAssertEqual(makeSession(layout: nil).renderPlan.layout, .scroll)
    }

    func testPagesHoldOneTopLevelSectionEachWithLooseFieldsOnTheNextPage() {
        let session = makeSession()
        let pages = session.formPages

        XCTAssertEqual(pages.map(\.propertyKey), ["housekeeping", "electrical"])
        XCTAssertEqual(pages.map(\.title), ["Housekeeping", "Electrical"])
        XCTAssertEqual(pages.first?.fieldIDs.first, "#/roomNumber")
        XCTAssertEqual(session.pageIndex(containing: "#/roomNumber"), 0)
        XCTAssertEqual(session.pageIndex(containing: "#/electrical/lighting"), 1)
        XCTAssertFalse(pages[0].isSectionField("#/roomNumber"))
        XCTAssertTrue(pages[0].isSectionField("#/housekeeping/linens"))
    }

    func testTrailingLooseFieldsJoinTheLastPage() {
        let session = makeSession(trailingField: true)

        XCTAssertEqual(session.formPages.last?.fieldIDs.last, "#/inspectorNotes")
    }

    func testPagesAreEmptyForScrollLayoutOrASingleSection() {
        XCTAssertTrue(makeSession(layout: nil).formPages.isEmpty)
        XCTAssertTrue(makeSession(includesElectrical: false).formPages.isEmpty)
    }

    func testSummaryCountsQuestionsFlagsFailuresAndMissingFollowUps() throws {
        let session = makeSession(instance: [
            "roomNumber": 1204,
            "housekeeping": ["linens": "Failed", "bed": "Pass"],
        ])
        let summary = session.formSummary()

        let housekeeping = try XCTUnwrap(summary.pages.first)
        XCTAssertEqual(housekeeping.answered, 2)
        XCTAssertEqual(housekeeping.total, 2)
        XCTAssertEqual(housekeeping.status, .needsAttention)
        XCTAssertEqual(summary.pages.last?.status, .notStarted)
        XCTAssertEqual(summary.flagged.map(\.field.id), ["#/housekeeping/linens"])
        XCTAssertEqual(summary.flagged.first?.answer, "Failed")
        XCTAssertEqual(summary.flagged.first?.pageIndex, 0)
        XCTAssertEqual(summary.missingRequired.map(\.id), ["#/housekeeping/linens_observation"])
        XCTAssertEqual(summary.general.map(\.answer), ["1204"])
    }

    func testPageIsDoneOnceTheFollowUpIsFilled() throws {
        let session = makeSession(instance: [
            "roomNumber": 1204,
            "housekeeping": ["linens": "Failed", "linens_observation": "Torn sheet", "bed": "Pass"],
        ])
        let summary = session.formSummary()

        XCTAssertEqual(summary.pages.first?.status, .done)
        XCTAssertEqual(summary.flagged.first?.details.map(\.answer), ["Torn sheet"])
        XCTAssertEqual(summary.flagged.first?.qualifiedTitle, "Housekeeping › Linens")
        XCTAssertTrue(summary.missingRequired.isEmpty)
    }

    func testFreshFormIsNotFlaggedUntilValidationFails() {
        let session = makeSession()

        var summary = session.formSummary()
        XCTAssertEqual(summary.pages.first?.status, .notStarted)
        XCTAssertEqual(summary.missingRequired.map(\.id), ["#/roomNumber"])

        XCTAssertFalse(session.validate())
        summary = session.formSummary()
        XCTAssertEqual(summary.pages.first?.status, .needsAttention)
    }

    func testSectionsDeclaredThroughReferencesAreFlagged() {
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: """
            {
              "type": "object",
              "x-formkit-layout": "section-pages",
              "$defs": {
                "check": {
                  "type": "object",
                  "title": "Check",
                  "properties": {
                    "result": { "type": "string", "enum": ["Pass", "Failed"] },
                    "note": { "type": "string" }
                  },
                  "allOf": [
                    {
                      "if": { "properties": { "result": { "const": "Failed" } }, "required": ["result"] },
                      "then": { "required": ["note"] }
                    }
                  ]
                }
              },
              "properties": {
                "first": { "$ref": "#/$defs/check" },
                "second": { "$ref": "#/$defs/check" }
              }
            }
            """,
            instanceJSON: #"{"second": {"result": "Failed"}}"#
        )
        let summary = session.formSummary()

        XCTAssertEqual(summary.flagged.map(\.field.id), ["#/second/result"])
        XCTAssertEqual(summary.flagged.first?.pageIndex, 1)
        XCTAssertEqual(summary.pages.map(\.status), [.notStarted, .needsAttention])
    }

    func testHiddenSectionsAreNotPages() throws {
        let schema = """
        {
          "type": "object",
          "x-formkit-layout": "section-pages",
          "properties": {
            "requestType": { "type": "string", "enum": ["Bug", "Feature"], "x-formkit-order": 1 },
            "contact": { "type": "object", "title": "Contact", "x-formkit-order": 2,
                         "properties": { "name": { "type": "string" } } },
            "bugDetails": { "type": "object", "title": "Bug Details", "x-formkit-order": 3,
                            "properties": { "severity": { "type": "string" } } },
            "notes": { "type": "object", "title": "Notes", "x-formkit-order": 4,
                       "properties": { "text": { "type": "string" } } }
          },
          "if": { "properties": { "requestType": { "const": "Bug" } }, "required": ["requestType"] },
          "then": { "required": ["bugDetails"] }
        }
        """
        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: #"{"requestType": "Feature"}"#)

        XCTAssertEqual(session.formPages.map(\.title), ["Contact", "Notes"])
        XCTAssertEqual(session.formPages.first?.fieldIDs.first, "#/requestType")
        XCTAssertNil(session.pageIndex(containing: "#/bugDetails/severity"))

        let requestType = try XCTUnwrap(session.renderPlan.fields.first { $0.propertyKey == "requestType" })
        session.setSelectedEnumChoiceID("string:Bug", for: requestType)
        XCTAssertEqual(session.formPages.map(\.title), ["Contact", "Bug Details", "Notes"])
    }

    func testValidExplicitNullCountsAsAnAnswer() throws {
        let schema = """
        {
          "type": "object",
          "x-formkit-layout": "section-pages",
          "properties": {
            "first": { "type": "object", "title": "First", "required": ["reading"],
                       "properties": { "reading": { "type": ["string", "null"], "title": "Reading" } } },
            "second": { "type": "object", "title": "Second", "properties": { "note": { "type": "string" } } }
          }
        }
        """
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: schema,
            instanceJSON: #"{"first": {"reading": null}}"#
        )
        let summary = session.formSummary()

        XCTAssertTrue(session.validate())
        XCTAssertEqual(summary.pages.first?.status, .done)
        XCTAssertTrue(summary.missingRequired.isEmpty)
    }

    func testConditionsResolveReferencesToTheRootSchema() {
        let schema = """
        {
          "type": "object",
          "x-formkit-layout": "section-pages",
          "$defs": {
            "failed": { "properties": { "result": { "const": "Failed" } }, "required": ["result"] }
          },
          "properties": {
            "first": {
              "type": "object", "title": "First",
              "properties": {
                "result": { "type": "string", "enum": ["Pass", "Failed"] },
                "note": { "type": "string" }
              },
              "if": { "$ref": "#/$defs/failed" },
              "then": { "required": ["note"] }
            },
            "second": { "type": "object", "title": "Second", "properties": { "other": { "type": "string" } } }
          }
        }
        """
        let session = FormKitRenderer().makeFormSession(schemaJSON: schema, instanceJSON: #"{"first": {"result": "Failed"}}"#)
        let summary = session.formSummary()

        XCTAssertEqual(summary.flagged.map(\.field.id), ["#/first/result"])
        XCTAssertEqual(summary.pages.first?.status, .needsAttention)
        XCTAssertEqual(summary.missingRequired.map(\.id), ["#/first/note"])
    }

    func testArrayValidationErrorsFlagTheirPage() throws {
        let schema = """
        {
          "type": "object",
          "x-formkit-layout": "section-pages",
          "properties": {
            "first": {
              "type": "object", "title": "First",
              "properties": {
                "name": { "type": "string" },
                "photos": { "type": "array", "maxItems": 1, "items": { "type": "string" } }
              }
            },
            "second": { "type": "object", "title": "Second", "properties": { "other": { "type": "string" } } }
          }
        }
        """
        let session = FormKitRenderer().makeFormSession(
            schemaJSON: schema,
            instanceJSON: #"{"first": {"name": "Ada", "photos": ["a", "b"]}}"#
        )
        XCTAssertEqual(session.formSummary().pages.first?.status, .done)

        XCTAssertFalse(session.validate())
        XCTAssertFalse(session.arrayErrors.isEmpty)
        XCTAssertEqual(session.formSummary().pages.first?.status, .needsAttention)
        XCTAssertEqual(session.formSummary().pages.last?.status, .notStarted)
    }

    func testNavigatorMovesThroughPagesAndTheSummary() {
        let navigator = FormKitPageNavigator(session: makeSession())
        var userPositions: [FormKitPagePosition] = []
        navigator.onUserNavigation = { userPositions.append($0) }

        navigator.nextPage(origin: .user)
        XCTAssertEqual(navigator.position, .page(1))
        navigator.nextPage(origin: .user)
        XCTAssertEqual(navigator.position, .summary)
        XCTAssertEqual(navigator.currentPage, 1)
        navigator.nextPage(origin: .user)
        XCTAssertEqual(navigator.position, .summary)
        navigator.previousPage(origin: .user)
        XCTAssertEqual(navigator.position, .page(1))
        navigator.goToPage(9)
        XCTAssertEqual(navigator.position, .page(1))
        navigator.goToPage(-3)
        XCTAssertEqual(navigator.position, .page(0))
        navigator.previousPage(origin: .user)
        XCTAssertEqual(navigator.position, .page(0))

        XCTAssertEqual(userPositions, [.page(1), .summary, .page(1)])
    }

    func testRevealingAFieldTurnsThePageWithoutReportingAUserNavigation() {
        let navigator = FormKitPageNavigator(session: makeSession())
        var userPositions: [FormKitPagePosition] = []
        navigator.onUserNavigation = { userPositions.append($0) }
        navigator.openSummary()

        navigator.revealField("#/electrical/lighting")
        XCTAssertEqual(navigator.position, .page(1))
        XCTAssertEqual(navigator.scrollTargetFieldID, "#/electrical/lighting")

        navigator.revealField("#/unknown")
        XCTAssertEqual(navigator.position, .page(1))
        XCTAssertTrue(userPositions.isEmpty)
    }

    func testNavigatorDoesNothingWithoutPages() {
        let navigator = FormKitPageNavigator(session: makeSession(layout: nil))

        navigator.nextPage()
        navigator.openSummary()

        XCTAssertEqual(navigator.position, .page(0))
    }

    func testPageBlocksHoldThePageFieldsAndLeaveOutTheRepeatedSectionTitle() {
        let session = makeSession()
        let pages = session.formPages
        let renderIndex = FormKitRenderIndex(renderPlan: session.renderPlan)

        let firstPageFieldIDs = renderIndex.pageBlocks(for: pages[0]).flatMap(\.fieldIDs)
        XCTAssertEqual(firstPageFieldIDs, ["#/roomNumber", "#/housekeeping/linens", "#/housekeeping/bed"])
        XCTAssertFalse(renderIndex.pageBlocks(for: pages[0]).contains(where: \.showSectionHeader))
        XCTAssertEqual(renderIndex.pageBlocks(for: pages[1]).flatMap(\.fieldIDs), ["#/electrical/lighting"])
    }

    func testPageLabelsFormatPositionsProgressAndStatuses() throws {
        let labels = FormKitPageLabels(
            positionFormat: "%1$lld of %2$lld",
            continueToFormat: "Continue to %@",
            answeredFormat: "%1$lld of %2$lld answered",
            done: "Done",
            notAnswered: "Not answered",
            needsAttention: "Needs attention"
        )
        let summary = makeSession(instance: ["housekeeping": ["bed": "Pass"]]).formSummary()
        let housekeeping = try XCTUnwrap(summary.pages.first)

        XCTAssertEqual(labels.position(page: 2, of: 6), "2 of 6")
        XCTAssertEqual(labels.continueTo("Electrical"), "Continue to Electrical")
        XCTAssertEqual(labels.status(for: housekeeping), "1 of 2 answered")
        XCTAssertEqual(labels.status(for: try XCTUnwrap(summary.pages.last)), "Not answered")
        XCTAssertEqual(FormKitLabels().pages, FormKitPageLabels.localizedDefaults)
        XCTAssertFalse(FormKitPageLabels.localizedDefaults.done.hasPrefix("formkit."))
    }

    // MARK: - Fixtures

    private func makeSession(
        layout: String? = "section-pages",
        includesElectrical: Bool = true,
        trailingField: Bool = false,
        instance: [String: Any]? = nil
    ) -> FormKitSession {
        var properties: [String: Any] = [
            "roomNumber": ["type": "integer", "title": "Room number", "x-formkit-order": 1],
            "housekeeping": section(
                title: "Housekeeping",
                order: 2,
                checks: [("linens", "Linens"), ("bed", "Bed")]
            ),
        ]
        if includesElectrical {
            properties["electrical"] = section(title: "Electrical", order: 3, checks: [("lighting", "Lighting")])
        }
        if trailingField {
            properties["inspectorNotes"] = ["type": "string", "title": "Inspector notes", "x-formkit-order": 4]
        }
        var schema: [String: Any] = [
            "type": "object",
            "title": "Inspection",
            "required": ["roomNumber"],
            "properties": properties,
        ]
        schema["x-formkit-layout"] = layout

        return FormKitRenderer().makeFormSession(
            schemaJSON: json(schema),
            instanceJSON: instance.map(json)
        )
    }

    private func section(title: String, order: Int, checks: [(String, String)]) -> [String: Any] {
        var properties: [String: Any] = [:]
        var rules: [[String: Any]] = []
        for (index, (key, checkTitle)) in checks.enumerated() {
            properties[key] = [
                "type": "string",
                "title": checkTitle,
                "enum": ["Pass", "Failed", "N/A"],
                "x-formkit-order": index * 2,
            ]
            properties["\(key)_observation"] = [
                "type": "string",
                "title": "Observation",
                "x-formkit-order": index * 2 + 1,
            ]
            rules.append([
                "if": ["properties": [key: ["const": "Failed"]], "required": [key]],
                "then": ["required": ["\(key)_observation"]],
            ])
        }
        return [
            "type": "object",
            "title": title,
            "x-formkit-order": order,
            "properties": properties,
            "allOf": rules,
        ]
    }

    private func json(_ object: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

private extension FormKitRenderIndex.DisplayBlock {
    var fieldIDs: [String] {
        if case let .fieldGroup(_, fieldIDs) = kind {
            return fieldIDs
        }
        return []
    }
}
