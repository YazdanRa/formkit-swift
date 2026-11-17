import SwiftUI
import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitPeoplePickerTests: XCTestCase {
    func testProviderIsLazyAndPagesDeduplicateWithoutLosingKnownLabels() async {
        var calls: [(String, String?)] = []
        let model = FormKitPeoplePickerModel { search, cursor in
            calls.append((search, cursor))
            if cursor == nil {
                return FormKitPeoplePage(people: [self.person("1"), self.person("1")], nextCursor: "next")
            }
            return FormKitPeoplePage(people: [self.person("1"), self.person("2")], nextCursor: "next")
        }
        XCTAssertTrue(calls.isEmpty)
        await model.startSearch("")
        XCTAssertEqual(model.people.map(\.id), ["1"])
        await model.loadMore()
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[1].1, "next")
        XCTAssertEqual(model.people.map(\.id), ["1", "2"])
        XCTAssertNil(model.nextCursor)
        await model.startSearch("another")
        XCTAssertEqual(model.knownPeople["2"]?.displayName, "Person 2")
    }

    func testDelayedSearchCannotReplaceNewerResults() async {
        let requests = PendingPeopleRequests()
        let model = FormKitPeoplePickerModel(provider: requests.load)
        let oldSearch = Task { await model.startSearch("old") }
        await requests.waitForCount(1)
        let newSearch = Task { await model.startSearch("new") }
        await requests.waitForCount(2)
        requests.finish(1, page: FormKitPeoplePage(people: [person("new")]))
        await newSearch.value
        requests.finish(0, page: FormKitPeoplePage(people: [person("old")], nextCursor: "stale"))
        await oldSearch.value
        XCTAssertEqual(model.people.map(\.id), ["new"])
        XCTAssertNil(model.knownPeople["old"])
        XCTAssertNil(model.nextCursor)
        XCTAssertFalse(model.isLoading)
    }

    func testOldPageAndCancellationCannotAppendToNewSearch() async {
        let requests = PendingPeopleRequests()
        let model = FormKitPeoplePickerModel(provider: requests.load)
        let initial = Task { await model.startSearch("first") }
        await requests.waitForCount(1)
        requests.finish(0, page: FormKitPeoplePage(people: [person("1")], nextCursor: "p2"))
        await initial.value
        let pagination = Task { await model.loadMore() }
        await requests.waitForCount(2)
        let replacement = Task { await model.startSearch("second") }
        await requests.waitForCount(3)
        requests.finish(1, page: FormKitPeoplePage(people: [person("stale")]))
        await pagination.value
        XCTAssertTrue(model.isLoading)
        replacement.cancel()
        requests.finish(2, page: FormKitPeoplePage(people: [person("cancelled")]))
        await replacement.value
        XCTAssertTrue(model.people.isEmpty)
        XCTAssertNil(model.knownPeople["stale"])
        XCTAssertNil(model.knownPeople["cancelled"])
        XCTAssertFalse(model.hasError)
        XCTAssertFalse(model.isLoading)
    }

    func testRetryUsesFailedPageCursorAndCancelRejectsLateError() async {
        let requests = PendingPeopleRequests()
        let model = FormKitPeoplePickerModel(provider: requests.load)
        let initial = Task { await model.startSearch("query") }
        await requests.waitForCount(1)
        requests.finish(0, page: FormKitPeoplePage(people: [person("1")], nextCursor: "p2"))
        await initial.value
        let pagination = Task { await model.loadMore() }
        await requests.waitForCount(2)
        requests.fail(1)
        await pagination.value
        XCTAssertTrue(model.hasError)
        XCTAssertEqual(model.people.map(\.id), ["1"])
        let retry = Task { await model.retry() }
        await requests.waitForCount(3)
        XCTAssertEqual(requests.items[2].search, "query")
        XCTAssertEqual(requests.items[2].cursor, "p2")
        requests.finish(2, page: FormKitPeoplePage(people: [person("2")]))
        await retry.value
        XCTAssertEqual(model.people.map(\.id), ["1", "2"])
        XCTAssertFalse(model.hasError)
        let late = Task { await model.startSearch("late") }
        await requests.waitForCount(4)
        model.cancel()
        requests.fail(3)
        await late.value
        XCTAssertFalse(model.hasError)
    }

    func testSingleSelectionPreservesHistoricalIDAndRequiredClearIsNoOp() {
        var value: String? = "offline-id"
        let selection = FormKitPeopleSelection.single(Binding(get: { value }, set: { value = $0 }))
        XCTAssertEqual(selection.ids, ["offline-id"])
        selection.clear(isRequired: true)
        XCTAssertEqual(value, "offline-id")
        selection.choose("live-id", isRequired: true)
        XCTAssertEqual(value, "live-id")
        selection.clear(isRequired: false)
        XCTAssertNil(value)
    }

    func testMultipleSelectionKeepsOffPageIDsAndRequiredLastItem() {
        var value = ["offline-id", "live-id"]
        let selection = FormKitPeopleSelection.multiple(Binding(get: { value }, set: { value = $0 }))
        selection.choose("other-page-id", isRequired: false)
        XCTAssertEqual(value, ["offline-id", "live-id", "other-page-id"])
        selection.choose("live-id", isRequired: false)
        XCTAssertEqual(value, ["offline-id", "other-page-id"])
        selection.choose("offline-id", isRequired: true)
        selection.choose("other-page-id", isRequired: true)
        XCTAssertEqual(value, ["other-page-id"])
        selection.clear(isRequired: true)
        XCTAssertEqual(value, ["other-page-id"])
        selection.clear(isRequired: false)
        XCTAssertTrue(value.isEmpty)
    }

    func testLaterPageRefreshesExistingLabelWithoutReorderingIDs() async {
        let model = FormKitPeoplePickerModel { _, cursor in
            if cursor == nil {
                return FormKitPeoplePage(people: [self.person("1"), self.person("2")], nextCursor: "more")
            }
            return FormKitPeoplePage(people: [FormKitPersonOption(id: "1", displayName: "Updated name")])
        }
        await model.startSearch("")
        await model.loadMore()
        XCTAssertEqual(model.people.map(\.id), ["1", "2"])
        XCTAssertEqual(model.people[0].displayName, "Updated name")
        XCTAssertEqual(model.knownPeople["1"]?.displayName, "Updated name")
    }

    func testLearnedHistoricalLabelSurvivesSheetModelReplacementAndProviderFailure() async {
        let labels = FormKitPeoplePickerLabels()
        let person = FormKitPersonOption(id: "historical-id", displayName: "Known person")
        let firstPresentation = FormKitPeoplePickerModel(provider: { _, _ in
            FormKitPeoplePage(people: [person])
        }, labels: labels)
        XCTAssertEqual(labels.person(for: person.id, savedPeople: []).displayName, person.id)
        await firstPresentation.startSearch("")
        firstPresentation.cancel()
        XCTAssertEqual(labels.person(for: person.id, savedPeople: []).displayName, "Known person")
        let reopened = FormKitPeoplePickerModel(provider: { _, _ in
            throw CancellationError()
        }, labels: labels)
        await reopened.startSearch("")
        XCTAssertEqual(labels.person(for: person.id, savedPeople: []).displayName, "Known person")
        let saved = FormKitPersonOption(id: person.id, displayName: "Host refreshed name")
        XCTAssertEqual(labels.person(for: person.id, savedPeople: [saved]).displayName, "Host refreshed name")
    }

    func testDuplicateNamesUseTypedIDsAcrossPagesAndSavedSelections() async {
        let first = FormKitPersonOption(id: "company-contact:101", displayName: "Alex Example")
        let second = FormKitPersonOption(id: "company-contact:102", displayName: "Alex Example")
        let model = FormKitPeoplePickerModel { _, cursor in
            FormKitPeoplePage(people: cursor == nil ? [first] : [second], nextCursor: cursor == nil ? "more" : nil)
        }
        await model.startSearch("")
        XCTAssertEqual(model.labels.displayLabel(for: first, savedPeople: []), "Alex Example")
        XCTAssertTrue(model.labels.isDuplicate(first, savedPeople: [second]))
        await model.loadMore()
        XCTAssertEqual(model.labels.displayLabel(for: first, savedPeople: []), "Alex Example, company-contact:101")
        XCTAssertEqual(model.labels.displayLabel(for: second, savedPeople: []), "Alex Example, company-contact:102")
        XCTAssertEqual(model.people.map(\.displayName), ["Alex Example", "Alex Example"])
        await model.startSearch("another search")
        XCTAssertTrue(model.labels.isDuplicate(first, savedPeople: []))
    }

    func testEmptyInitialAndIntermediatePagesRemainPageable() async {
        var cursors: [String?] = []
        let model = FormKitPeoplePickerModel { _, cursor in
            cursors.append(cursor)
            switch cursor {
            case nil:
                return FormKitPeoplePage(people: [], nextCursor: "empty-page")
            case "empty-page":
                return FormKitPeoplePage(people: [], nextCursor: "final-page")
            default:
                return FormKitPeoplePage(people: [self.person("last")])
            }
        }
        await model.startSearch("")
        XCTAssertTrue(model.people.isEmpty)
        XCTAssertEqual(model.nextCursor, "empty-page")
        await model.loadMore()
        XCTAssertTrue(model.people.isEmpty)
        XCTAssertEqual(model.nextCursor, "final-page")
        await model.loadMore()
        XCTAssertEqual(cursors, [nil, "empty-page", "final-page"])
        XCTAssertEqual(model.people.map(\.id), ["last"])
        XCTAssertNil(model.nextCursor)
    }

    func testStaleSavedLabelDoesNotMaskDuplicateProviderNames() {
        let labels = FormKitPeoplePickerLabels()
        let first = FormKitPersonOption(id: "company-contact:101", displayName: "Alex")
        let second = FormKitPersonOption(id: "company-contact:102", displayName: "Alex")
        let saved = [FormKitPersonOption(id: first.id, displayName: "Old name")]
        labels.remember([first, second])
        XCTAssertEqual(labels.displayLabel(for: first, savedPeople: saved), "Alex, company-contact:101")
        XCTAssertEqual(labels.displayLabel(for: second, savedPeople: saved), "Alex, company-contact:102")
        XCTAssertEqual(labels.person(for: first.id, savedPeople: saved).displayName, "Old name")
    }

    func testLoadingAndUnavailablePeopleNeverWriteSelectionBindings() async {
        var singleValue: String? = "offline-id"
        var multipleValue = ["offline-id", "historical-id"]
        var writes = 0
        let single = FormKitPeopleSelection.single(Binding(get: { singleValue }, set: {
            writes += 1
            singleValue = $0
        }))
        let multiple = FormKitPeopleSelection.multiple(Binding(get: { multipleValue }, set: {
            writes += 1
            multipleValue = $0
        }))
        let model = FormKitPeoplePickerModel { search, _ in
            if search == "unavailable" {
                throw CancellationError()
            }
            return FormKitPeoplePage(people: [self.person("different-id")])
        }
        await model.startSearch("")
        await model.startSearch("unavailable")
        model.cancel()
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(single.ids, ["offline-id"])
        XCTAssertEqual(multiple.ids, ["offline-id", "historical-id"])
    }

    private func person(_ id: String) -> FormKitPersonOption {
        FormKitPersonOption(id: id, displayName: "Person \(id)")
    }
}

@MainActor
private final class PendingPeopleRequests {
    struct Request {
        let search: String
        let cursor: String?
        let continuation: CheckedContinuation<FormKitPeoplePage, Error>
    }

    private struct Failure: Error {}
    private(set) var items: [Request] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func load(search: String, cursor: String?) async throws -> FormKitPeoplePage {
        try await withCheckedThrowingContinuation { continuation in
            items.append(Request(search: search, cursor: cursor, continuation: continuation))
            let ready = waiters.filter { items.count >= $0.count }
            waiters.removeAll { items.count >= $0.count }
            ready.forEach { $0.continuation.resume() }
        }
    }

    func waitForCount(_ count: Int) async {
        if items.count >= count {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }

    func finish(_ index: Int, page: FormKitPeoplePage) {
        items[index].continuation.resume(returning: page)
    }

    func fail(_ index: Int) {
        items[index].continuation.resume(throwing: Failure())
    }
}
