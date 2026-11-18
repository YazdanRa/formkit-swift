import XCTest

final class DynamicOptionsUITests: XCTestCase {
    @MainActor
    func testSingleSelectionUsesTypedIdentifierAndCanClear() {
        let app = launch()
        let picker = app.buttons["demo_issued_to_picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "Saved contact")
        picker.tap()

        let sameNameContact = app.buttons["formkit_dynamic_option_company-contact:102"]
        XCTAssertTrue(sameNameContact.waitForExistence(timeout: 5))
        let firstContact = app.buttons["formkit_dynamic_option_company-contact:101"]
        XCTAssertTrue(firstContact.exists)
        XCTAssertEqual(firstContact.label, "Alex Morgan, Northline Engineering")
        XCTAssertEqual(sameNameContact.label, "Alex Morgan, City Mechanical")
        XCTAssertTrue(firstContact.staticTexts["Northline Engineering"].exists)
        XCTAssertTrue(sameNameContact.staticTexts["City Mechanical"].exists)
        capture("dynamic-contact-companies", app: app)
        sameNameContact.tap()
        waitForValue("company-contact:102", id: "demo_issued_to_value", in: app)
        XCTAssertEqual(picker.value as? String, "Alex Morgan, City Mechanical")

        picker.tap()
        let clear = app.buttons["formkit_dynamic_clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        app.buttons["formkit_dynamic_done"].tap()
        waitForValue("none", id: "demo_issued_to_value", in: app)
    }

    @MainActor
    func testMultipleSelectionKeepsEarlierPageIdentifiers() {
        let app = launch()
        app.buttons["demo_equipment_picker"].tap()
        let first = app.buttons["formkit_dynamic_option_equipment:excavator"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        let loadMore = app.buttons["formkit_dynamic_load_more"]
        XCTAssertTrue(loadMore.waitForExistence(timeout: 5))
        loadMore.tap()

        let later = app.buttons["formkit_dynamic_option_equipment:crane"]
        XCTAssertTrue(later.waitForExistence(timeout: 5))
        later.tap()
        capture("dynamic-equipment-pages", app: app)
        app.buttons["formkit_dynamic_done"].tap()
        waitForValue("equipment:excavator,equipment:crane", id: "demo_equipment_value", in: app)
    }

    @MainActor
    func testRequiredMultipleSelectionKeepsItsLastOption() {
        let app = launch(arguments: ["-DYNAMIC_REQUIRED"])
        app.buttons["demo_equipment_picker"].tap()
        let first = app.buttons["formkit_dynamic_option_equipment:excavator"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: first)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        first.tap()
        XCTAssertTrue(first.isSelected)
        XCTAssertFalse(app.buttons["formkit_dynamic_clear"].exists)
        app.buttons["formkit_dynamic_done"].tap()
        waitForValue("equipment:excavator", id: "demo_equipment_value", in: app)
    }

    @MainActor
    func testMaximumSelectionDisablesNewOptionsUntilOneIsRemoved() {
        let app = launch(arguments: ["-DYNAMIC_LIMIT_TWO"])
        app.buttons["demo_equipment_picker"].tap()
        let first = app.buttons["formkit_dynamic_option_equipment:excavator"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        app.buttons["formkit_dynamic_option_equipment:loader"].tap()
        let loadMore = app.buttons["formkit_dynamic_load_more"]
        XCTAssertTrue(loadMore.waitForExistence(timeout: 5))
        loadMore.tap()

        let later = app.buttons["formkit_dynamic_option_equipment:crane"]
        XCTAssertTrue(later.waitForExistence(timeout: 5))
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"), object: later)
        XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: 5), .completed)
        XCTAssertTrue(first.isEnabled)
        first.tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: later)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        later.tap()
        app.buttons["formkit_dynamic_done"].tap()
        waitForValue("equipment:loader,equipment:crane", id: "demo_equipment_value", in: app)
    }

    @MainActor
    func testSavedSelectionSurvivesLookupFailure() {
        let app = launch(arguments: ["-DYNAMIC_LOOKUP_FAILS"])
        app.buttons["demo_issued_to_picker"].tap()
        XCTAssertTrue(app.staticTexts["Options could not be loaded."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["formkit_dynamic_option_company-contact:saved"].exists)
        capture("dynamic-saved-option", app: app)
        app.buttons["formkit_dynamic_done"].tap()
        waitForValue("company-contact:saved", id: "demo_issued_to_value", in: app)
        XCTAssertEqual(app.buttons["demo_issued_to_picker"].value as? String, "Saved contact")
    }

    @MainActor
    func testLockChangeDisablesSelectionWhileSheetIsOpen() {
        let app = launch(arguments: ["-DYNAMIC_LOCK_ON_LOAD"])
        app.buttons["demo_issued_to_picker"].tap()
        let contact = app.buttons["formkit_dynamic_option_company-contact:101"]
        XCTAssertTrue(contact.waitForExistence(timeout: 5))
        let disabled = NSPredicate(format: "isEnabled == false")
        expectation(for: disabled, evaluatedWith: contact)
        waitForExpectations(timeout: 5)
        app.buttons["formkit_dynamic_done"].tap()
        waitForValue("company-contact:saved", id: "demo_issued_to_value", in: app)
    }

    @MainActor
    func testRegistryBindsNestedContactAndEquipmentAnswers() {
        let app = launch(arguments: ["-DYNAMIC_REGISTRY"])
        let contact = app.buttons["Contact"]
        XCTAssertTrue(contact.waitForExistence(timeout: 5))
        contact.tap()
        let option = app.buttons["formkit_dynamic_option_company-contact:102"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        waitForJSON("\"contact\" : \"company-contact:102\"", in: app)
        waitForJSON("\"request\" : {", in: app)
        app.buttons["formkit_page_next"].tap()
        let equipment = app.buttons["Equipment"]
        XCTAssertTrue(equipment.waitForExistence(timeout: 5))
        equipment.tap()
        let first = app.buttons["formkit_dynamic_option_equipment:excavator"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        let loadMore = app.buttons["formkit_dynamic_load_more"]
        XCTAssertTrue(loadMore.waitForExistence(timeout: 5))
        loadMore.tap()
        let later = app.buttons["formkit_dynamic_option_equipment:crane"]
        XCTAssertTrue(later.waitForExistence(timeout: 5))
        later.tap()
        app.buttons["formkit_dynamic_done"].tap()
        waitForJSON("\"assets\" : {", in: app)
        waitForJSON("equipment:excavator", in: app)
        waitForJSON("equipment:crane", in: app)
        app.buttons["formkit_page_previous"].tap()
        contact.tap()
        app.buttons["formkit_dynamic_clear"].tap()
        app.buttons["formkit_dynamic_done"].tap()
        waitForJSON("\"contact\" : null", in: app)
        capture("dynamic-registry-nested-answers", app: app)
    }

    @MainActor
    func testHostScopeRemountDismissesSheetAndRejectsOldOptions() {
        let app = launch(arguments: ["-DYNAMIC_SCOPE_CHANGE"])
        let picker = app.buttons["demo_issued_to_picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        waitForValue("1:true", id: "demo_catalog_scope", in: app)
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.buttons["formkit_dynamic_done"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        waitForValue("company-contact:saved", id: "demo_issued_to_value", in: app)
        picker.tap()
        let current = app.buttons["formkit_dynamic_option_new-scope-option"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["formkit_dynamic_option_old-scope-option"].exists)
        XCTAssertFalse(app.staticTexts["Old scope option"].exists)
        current.tap()
        waitForValue("new-scope-option", id: "demo_issued_to_value", in: app)
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func waitForValue(_ value: String, id: String, in app: XCUIApplication) {
        let element = app.staticTexts[id]
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, element.debugDescription)
    }

    @MainActor
    private func waitForJSON(_ fragment: String, in app: XCUIApplication) {
        let json = app.staticTexts["demo_dynamic_json"]
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", fragment), object: json
        )
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, json.debugDescription)
    }

    @MainActor
    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITEST_DYNAMIC_OPTIONS", "-AppleLanguages", "(en)"] + arguments
        app.launch()
        return app
    }
}
