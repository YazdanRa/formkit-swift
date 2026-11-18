import XCTest

final class PeoplePickerUITests: XCTestCase {
    @MainActor
    func testSingleSelectionUsesTypedIdentifierAndCanClear() {
        let app = launch()
        let picker = app.buttons["demo_issued_to_picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "Saved contact")
        picker.tap()

        let sameNameContact = app.buttons["formkit_person_company-contact:102"]
        XCTAssertTrue(sameNameContact.waitForExistence(timeout: 5))
        let firstContact = app.buttons["formkit_person_company-contact:101"]
        XCTAssertTrue(firstContact.exists)
        XCTAssertEqual(firstContact.label, "Alex Morgan, Northline Engineering")
        XCTAssertEqual(sameNameContact.label, "Alex Morgan, City Mechanical")
        XCTAssertTrue(firstContact.staticTexts["Northline Engineering"].exists)
        XCTAssertTrue(sameNameContact.staticTexts["City Mechanical"].exists)
        capture("people-duplicate-names", app: app)
        sameNameContact.tap()
        waitForValue("company-contact:102", id: "demo_issued_to_value", in: app)
        XCTAssertEqual(picker.value as? String, "Alex Morgan, City Mechanical")

        picker.tap()
        let clear = app.buttons["formkit_people_clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        app.buttons["formkit_people_done"].tap()
        waitForValue("none", id: "demo_issued_to_value", in: app)
    }

    @MainActor
    func testMultipleSelectionKeepsEarlierPageIdentifiers() {
        let app = launch()
        app.buttons["demo_assigned_to_picker"].tap()
        let first = app.buttons["formkit_person_company-user:101"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        let loadMore = app.buttons["formkit_people_load_more"]
        XCTAssertTrue(loadMore.waitForExistence(timeout: 5))
        loadMore.tap()

        let later = app.buttons["formkit_person_company-user:103"]
        XCTAssertTrue(later.waitForExistence(timeout: 5))
        later.tap()
        capture("people-multiple-pages", app: app)
        app.buttons["formkit_people_done"].tap()
        waitForValue("company-user:101,company-user:103", id: "demo_assigned_to_value", in: app)
    }

    @MainActor
    func testRequiredMultipleSelectionKeepsItsLastPerson() {
        let app = launch(arguments: ["-PEOPLE_REQUIRED"])
        app.buttons["demo_assigned_to_picker"].tap()
        let first = app.buttons["formkit_person_company-user:101"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: first)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        first.tap()
        XCTAssertTrue(first.isSelected)
        XCTAssertFalse(app.buttons["formkit_people_clear"].exists)
        app.buttons["formkit_people_done"].tap()
        waitForValue("company-user:101", id: "demo_assigned_to_value", in: app)
    }

    @MainActor
    func testMaximumSelectionDisablesNewPeopleUntilOneIsRemoved() {
        let app = launch(arguments: ["-PEOPLE_LIMIT_TWO"])
        app.buttons["demo_assigned_to_picker"].tap()
        let first = app.buttons["formkit_person_company-user:101"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        app.buttons["formkit_person_company-user:102"].tap()
        let loadMore = app.buttons["formkit_people_load_more"]
        XCTAssertTrue(loadMore.waitForExistence(timeout: 5))
        loadMore.tap()

        let later = app.buttons["formkit_person_company-user:103"]
        XCTAssertTrue(later.waitForExistence(timeout: 5))
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"), object: later)
        XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: 5), .completed)
        XCTAssertTrue(first.isEnabled)
        first.tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: later)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        later.tap()
        app.buttons["formkit_people_done"].tap()
        waitForValue("company-user:102,company-user:103", id: "demo_assigned_to_value", in: app)
    }

    @MainActor
    func testSavedSelectionSurvivesLookupFailure() {
        let app = launch(arguments: ["-PEOPLE_LOOKUP_FAILS"])
        app.buttons["demo_issued_to_picker"].tap()
        XCTAssertTrue(app.staticTexts["People could not be loaded."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["formkit_person_company-contact:saved"].exists)
        capture("people-saved-offline", app: app)
        app.buttons["formkit_people_done"].tap()
        waitForValue("company-contact:saved", id: "demo_issued_to_value", in: app)
        XCTAssertEqual(app.buttons["demo_issued_to_picker"].value as? String, "Saved contact")
    }

    @MainActor
    func testLockChangeDisablesSelectionWhileSheetIsOpen() {
        let app = launch(arguments: ["-PEOPLE_LOCK_ON_LOAD"])
        app.buttons["demo_issued_to_picker"].tap()
        let contact = app.buttons["formkit_person_company-contact:101"]
        XCTAssertTrue(contact.waitForExistence(timeout: 5))
        let disabled = NSPredicate(format: "isEnabled == false")
        expectation(for: disabled, evaluatedWith: contact)
        waitForExpectations(timeout: 5)
        app.buttons["formkit_people_done"].tap()
        waitForValue("company-contact:saved", id: "demo_issued_to_value", in: app)
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
    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITEST_PEOPLE_PICKER", "-AppleLanguages", "(en)"] + arguments
        app.launch()
        return app
    }
}
