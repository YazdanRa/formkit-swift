import XCTest

final class DynamicOptionsUITests: XCTestCase {
    @MainActor
    func testSingleSelectionUsesTypedIdentifierAndCanClear() {
        let app = launch()
        let picker = app.buttons["demo_contact_picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "Saved contact")
        picker.tap()

        let sameNameContact = app.buttons["formkit_dynamic_option_contact-102"]
        XCTAssertTrue(sameNameContact.waitForExistence(timeout: 5))
        let firstContact = app.buttons["formkit_dynamic_option_contact-101"]
        XCTAssertTrue(firstContact.exists)
        XCTAssertEqual(firstContact.label, "Alex Morgan, Northline Engineering")
        XCTAssertEqual(sameNameContact.label, "Alex Morgan, City Mechanical")
        XCTAssertTrue(firstContact.staticTexts["Northline Engineering"].exists)
        XCTAssertTrue(sameNameContact.staticTexts["City Mechanical"].exists)
        capture("dynamic-contact-companies", app: app)
        sameNameContact.tap()
        waitForValue("contact-102", id: "demo_contact_value", in: app)
        XCTAssertEqual(picker.value as? String, "Alex Morgan, City Mechanical")

        picker.tap()
        let clear = app.buttons["formkit_dynamic_clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        app.buttons["formkit_dynamic_done"].tap()
        waitForValue("none", id: "demo_contact_value", in: app)
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
        app.buttons["demo_contact_picker"].tap()
        XCTAssertTrue(app.staticTexts["Options could not be loaded."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["formkit_dynamic_option_contact-saved"].exists)
        capture("dynamic-saved-option", app: app)
        app.buttons["formkit_dynamic_done"].tap()
        waitForValue("contact-saved", id: "demo_contact_value", in: app)
        XCTAssertEqual(app.buttons["demo_contact_picker"].value as? String, "Saved contact")
    }

    @MainActor
    func testLockChangeDisablesSelectionWhileSheetIsOpen() {
        let app = launch(arguments: ["-DYNAMIC_LOCK_ON_LOAD"])
        app.buttons["demo_contact_picker"].tap()
        let contact = app.buttons["formkit_dynamic_option_contact-101"]
        XCTAssertTrue(contact.waitForExistence(timeout: 5))
        let disabled = NSPredicate(format: "isEnabled == false")
        expectation(for: disabled, evaluatedWith: contact)
        waitForExpectations(timeout: 5)
        app.buttons["formkit_dynamic_done"].tap()
        waitForValue("contact-saved", id: "demo_contact_value", in: app)
    }

    @MainActor
    func testRegistryBindsNestedContactAndEquipmentAnswers() {
        let app = launch(arguments: ["-DYNAMIC_REGISTRY"])
        let contact = app.buttons["Contact"]
        XCTAssertTrue(contact.waitForExistence(timeout: 5))
        contact.tap()
        let option = app.buttons["formkit_dynamic_option_contact-102"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        waitForJSON("\"contact\" : \"contact-102\"", in: app)
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
    func testRequiredZeroCapacityArrayWritesEmptyOnlyAfterExplicitClear() throws {
        let app = launch(arguments: ["-DYNAMIC_REGISTRY", "-DYNAMIC_EMPTY_REQUIRED"])
        let json = app.staticTexts["demo_dynamic_json"]
        XCTAssertTrue(json.waitForExistence(timeout: 5))
        let originalJSON = json.label
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(originalJSON.utf8)) as? [String: Any])
        XCTAssertNil(original["equipment"])
        let picker = app.buttons["Equipment"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        XCTAssertTrue(app.staticTexts["No options found"].waitForExistence(timeout: 5))
        app.buttons["formkit_dynamic_done"].tap()
        XCTAssertEqual(json.label, originalJSON)

        picker.tap()
        XCTAssertTrue(app.staticTexts["No options found"].waitForExistence(timeout: 5))
        let clear = app.buttons["formkit_dynamic_clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        capture("dynamic-required-empty-array", app: app)
        clear.tap()
        app.buttons["formkit_dynamic_done"].tap()
        waitForJSON("\"equipment\" : [", in: app)
        let savedJSON = json.label
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(savedJSON.utf8)) as? [String: Any])
        XCTAssertEqual(saved["equipment"] as? [String], [])

        picker.tap()
        XCTAssertTrue(app.staticTexts["No options found"].waitForExistence(timeout: 5))
        XCTAssertTrue(clear.exists)
        app.buttons["formkit_dynamic_done"].tap()
        XCTAssertEqual(json.label, savedJSON)
    }

    @MainActor
    func testHostScopeRemountDismissesSheetAndRejectsOldOptions() {
        let app = launch(arguments: ["-DYNAMIC_SCOPE_CHANGE"])
        let picker = app.buttons["demo_contact_picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        waitForValue("1:true", id: "demo_catalog_scope", in: app)
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.buttons["formkit_dynamic_done"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        waitForValue("contact-saved", id: "demo_contact_value", in: app)
        picker.tap()
        let current = app.buttons["formkit_dynamic_option_new-scope-option"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["formkit_dynamic_option_old-scope-option"].exists)
        XCTAssertFalse(app.staticTexts["Old scope option"].exists)
        current.tap()
        waitForValue("new-scope-option", id: "demo_contact_value", in: app)
    }

    @MainActor
    func testRegistryHydratesMountedSavedOptionWithoutChangingItsIdentifier() {
        let app = launch(arguments: ["-DYNAMIC_REGISTRY", "-DYNAMIC_HYDRATE_ON_LOAD"])
        let contact = app.buttons["Contact"]
        XCTAssertTrue(contact.waitForExistence(timeout: 5))
        XCTAssertEqual(contact.value as? String, "saved-opaque-contact")
        let json = app.staticTexts["demo_dynamic_json"]
        let originalJSON = json.label
        XCTAssertTrue(originalJSON.contains("\"contact\" : \"saved-opaque-contact\""))
        contact.tap()
        let savedRows = app.buttons.matching(identifier: "formkit_dynamic_option_saved-opaque-contact")
        let saved = savedRows.firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        let hydrated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Hydrated contact, New company"), object: saved
        )
        XCTAssertEqual(XCTWaiter.wait(for: [hydrated], timeout: 5), .completed)
        XCTAssertTrue(saved.isSelected)
        XCTAssertEqual(savedRows.count, 1)
        let browse = app.buttons["formkit_dynamic_option_contact-101"]
        XCTAssertTrue(browse.waitForExistence(timeout: 5))
        XCTAssertFalse(browse.isSelected)
        capture("dynamic-registry-hydrated-saved-option", app: app)
        app.buttons["formkit_dynamic_done"].tap()
        let summary = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Hydrated contact, New company"), object: contact
        )
        XCTAssertEqual(XCTWaiter.wait(for: [summary], timeout: 5), .completed)
        XCTAssertEqual(json.label, originalJSON)
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

@MainActor
extension DynamicOptionsUITests {
    func testRegistryPreservesBlankScalarAndArrayIdentifiers() throws {
        let app = launch(arguments: ["-DYNAMIC_REGISTRY", "-DYNAMIC_BLANK_IDS"])
        try selectAndClearEmptyScalarID(in: app)
        let equipment = app.buttons["Equipment"]
        XCTAssertTrue(equipment.waitForExistence(timeout: 5))
        equipment.tap()
        let first = app.buttons["formkit_dynamic_option_"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.label, "First option")
        first.tap()
        let second = app.buttons["formkit_dynamic_option_  "]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertEqual(second.label, "Second option")
        second.tap()
        let third = app.buttons["formkit_dynamic_option_ordinary"]
        XCTAssertTrue(third.waitForExistence(timeout: 5))
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"), object: third)
        XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: 5), .completed)
        app.buttons["formkit_dynamic_done"].tap()
        waitForJSON("\"equipment\" : [", in: app)
        let json = app.staticTexts["demo_dynamic_json"]
        let savedJSON = json.label
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(savedJSON.utf8)) as? [String: Any])
        XCTAssertEqual(saved["equipment"] as? [String], ["", "  "])
        equipment.tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.isSelected)
        XCTAssertTrue(second.isSelected)
        XCTAssertTrue(third.waitForExistence(timeout: 5))
        XCTAssertFalse(third.isEnabled)
        capture("dynamic-blank-identifiers", app: app)
        app.buttons["formkit_dynamic_done"].tap()
        XCTAssertEqual(json.label, savedJSON)
    }

    private func selectAndClearEmptyScalarID(in app: XCUIApplication) throws {
        let category = app.buttons["Category"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        category.tap()
        let first = app.buttons["formkit_dynamic_option_"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.label, "First option")
        first.tap()
        waitForJSON("\"choice\" : \"\"", in: app)
        let json = app.staticTexts["demo_dynamic_json"]
        let selected = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.label.utf8)) as? [String: Any])
        XCTAssertEqual(selected["choice"] as? String, "")
        XCTAssertFalse(selected["choice"] is NSNull)
        XCTAssertEqual(category.value as? String, "First option")
        category.tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.isSelected)
        app.buttons["formkit_dynamic_clear"].tap()
        app.buttons["formkit_dynamic_done"].tap()
        waitForJSON("\"choice\" : null", in: app)
        let cleared = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.label.utf8)) as? [String: Any])
        XCTAssertTrue(cleared["choice"] is NSNull)
    }

    func testRequiredZeroCapacityArrayCanExplicitlyClearWithoutDynamicSource() throws {
        let app = launch(arguments: ["-DYNAMIC_REGISTRY", "-DYNAMIC_EMPTY_REQUIRED", "-DYNAMIC_NO_SOURCE"])
        let json = app.staticTexts["demo_dynamic_json"]
        XCTAssertTrue(json.waitForExistence(timeout: 5))
        let originalJSON = json.label
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(originalJSON.utf8)) as? [String: Any])
        XCTAssertNil(original["equipment"])
        XCTAssertTrue(app.staticTexts["No items added yet."].waitForExistence(timeout: 5))
        let stockButtons = app.buttons.matching(identifier: "json_form_section_equipment")
        let add = stockButtons.matching(NSPredicate(format: "label == %@", "Add Equipment")).firstMatch
        XCTAssertTrue(add.exists)
        XCTAssertFalse(add.isEnabled)
        XCTAssertFalse(app.buttons["Equipment"].exists)
        XCTAssertFalse(app.buttons["formkit_dynamic_done"].exists)
        let clear = stockButtons.matching(NSPredicate(format: "label == %@", "Clear selection")).firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(clear.frame.height, 44)
        XCTAssertEqual(json.label, originalJSON)
        capture("dynamic-empty-array-stock-fallback", app: app)
        clear.tap()
        waitForJSON("\"equipment\" : [", in: app)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.label.utf8)) as? [String: Any])
        XCTAssertEqual(saved["equipment"] as? [String], [])
        XCTAssertFalse(add.isEnabled)
    }
}
