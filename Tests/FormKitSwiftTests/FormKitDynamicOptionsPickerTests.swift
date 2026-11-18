import SwiftUI
import XCTest
@testable import FormKitSwift

@MainActor
final class FormKitDynamicOptionsPickerTests: XCTestCase {
    func testProviderIsLazyAndPagesDeduplicateWithoutLosingKnownLabels() async {
        var calls: [(String, String?)] = []
        let model = FormKitDynamicOptionsPickerModel { search, cursor in
            calls.append((search, cursor))
            if cursor == nil {
                return FormKitDynamicOptionsPage(options: [self.option("1"), self.option("1")], nextCursor: "next")
            }
            return FormKitDynamicOptionsPage(options: [self.option("1"), self.option("2")], nextCursor: "next")
        }
        XCTAssertTrue(calls.isEmpty)
        await model.startSearch("")
        XCTAssertEqual(model.options.map(\.id), ["1"])
        await model.loadMore()
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[1].1, "next")
        XCTAssertEqual(model.options.map(\.id), ["1", "2"])
        XCTAssertNil(model.nextCursor)
        await model.startSearch("another")
        XCTAssertEqual(model.knownOptions["2"]?.label, "Option 2")
    }

    func testDelayedSearchCannotReplaceNewerResults() async {
        let requests = PendingDynamicOptionsRequests()
        let model = FormKitDynamicOptionsPickerModel(provider: requests.load)
        let oldSearch = Task { await model.startSearch("old") }
        await requests.waitForCount(1)
        let newSearch = Task { await model.startSearch("new") }
        await requests.waitForCount(2)
        requests.finish(1, page: FormKitDynamicOptionsPage(options: [option("new")]))
        await newSearch.value
        requests.finish(0, page: FormKitDynamicOptionsPage(options: [option("old")], nextCursor: "stale"))
        await oldSearch.value
        XCTAssertEqual(model.options.map(\.id), ["new"])
        XCTAssertNil(model.knownOptions["old"])
        XCTAssertNil(model.nextCursor)
        XCTAssertFalse(model.isLoading)
    }

    func testOldPageAndCancellationCannotAppendToNewSearch() async {
        let requests = PendingDynamicOptionsRequests()
        let model = FormKitDynamicOptionsPickerModel(provider: requests.load)
        let initial = Task { await model.startSearch("first") }
        await requests.waitForCount(1)
        requests.finish(0, page: FormKitDynamicOptionsPage(options: [option("1")], nextCursor: "p2"))
        await initial.value
        let pagination = Task { await model.loadMore() }
        await requests.waitForCount(2)
        let replacement = Task { await model.startSearch("second") }
        await requests.waitForCount(3)
        requests.finish(1, page: FormKitDynamicOptionsPage(options: [option("stale")]))
        await pagination.value
        XCTAssertTrue(model.isLoading)
        replacement.cancel()
        requests.finish(2, page: FormKitDynamicOptionsPage(options: [option("cancelled")]))
        await replacement.value
        XCTAssertTrue(model.options.isEmpty)
        XCTAssertNil(model.knownOptions["stale"])
        XCTAssertNil(model.knownOptions["cancelled"])
        XCTAssertFalse(model.hasError)
        XCTAssertFalse(model.isLoading)
    }

    func testRetryUsesFailedPageCursorAndCancelRejectsLateError() async {
        let requests = PendingDynamicOptionsRequests()
        let model = FormKitDynamicOptionsPickerModel(provider: requests.load)
        let initial = Task { await model.startSearch("query") }
        await requests.waitForCount(1)
        requests.finish(0, page: FormKitDynamicOptionsPage(options: [option("1")], nextCursor: "p2"))
        await initial.value
        let pagination = Task { await model.loadMore() }
        await requests.waitForCount(2)
        requests.fail(1)
        await pagination.value
        XCTAssertTrue(model.hasError)
        XCTAssertEqual(model.options.map(\.id), ["1"])
        let retry = Task { await model.retry() }
        await requests.waitForCount(3)
        XCTAssertEqual(requests.items[2].search, "query")
        XCTAssertEqual(requests.items[2].cursor, "p2")
        requests.finish(2, page: FormKitDynamicOptionsPage(options: [option("2")]))
        await retry.value
        XCTAssertEqual(model.options.map(\.id), ["1", "2"])
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
        let selection = FormKitDynamicSelection.single(Binding(get: { value }, set: { value = $0 }))
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
        let selection = FormKitDynamicSelection.multiple(Binding(get: { value }, set: { value = $0 }))
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
        let model = FormKitDynamicOptionsPickerModel { _, cursor in
            if cursor == nil {
                return FormKitDynamicOptionsPage(options: [self.option("1"), self.option("2")], nextCursor: "more")
            }
            return FormKitDynamicOptionsPage(options: [FormKitDynamicOption(id: "1", label: "Updated name")])
        }
        await model.startSearch("")
        await model.loadMore()
        XCTAssertEqual(model.options.map(\.id), ["1", "2"])
        XCTAssertEqual(model.options[0].label, "Updated name")
        XCTAssertEqual(model.knownOptions["1"]?.label, "Updated name")
    }

    func testLearnedHistoricalLabelSurvivesSheetModelReplacementAndProviderFailure() async {
        let labels = FormKitDynamicOptionsPickerLabels()
        let option = FormKitDynamicOption(id: "historical-id", label: "Known option")
        let firstPresentation = FormKitDynamicOptionsPickerModel(provider: { _, _ in
            FormKitDynamicOptionsPage(options: [option])
        }, labels: labels)
        XCTAssertEqual(labels.option(for: option.id, savedOptions: []).label, option.id)
        await firstPresentation.startSearch("")
        firstPresentation.cancel()
        XCTAssertEqual(labels.option(for: option.id, savedOptions: []).label, "Known option")
        let reopened = FormKitDynamicOptionsPickerModel(provider: { _, _ in
            throw CancellationError()
        }, labels: labels)
        await reopened.startSearch("")
        XCTAssertEqual(labels.option(for: option.id, savedOptions: []).label, "Known option")
        let saved = FormKitDynamicOption(id: option.id, label: "Host refreshed name")
        XCTAssertEqual(
            labels.option(for: option.id, savedOptions: [saved]).label,
            "Host refreshed name"
        )
    }

    func testDuplicateNamesUseTypedIDsAcrossPagesAndSavedSelections() async {
        let first = FormKitDynamicOption(id: "company-contact:101", label: "Alex Example")
        let second = FormKitDynamicOption(id: "company-contact:102", label: "Alex Example")
        let model = FormKitDynamicOptionsPickerModel { _, cursor in
            FormKitDynamicOptionsPage(
                options: cursor == nil ? [first] : [second],
                nextCursor: cursor == nil ? "more" : nil
            )
        }
        await model.startSearch("")
        XCTAssertEqual(model.labels.displayLabel(for: first, savedOptions: []), "Alex Example")
        XCTAssertTrue(model.labels.isDuplicate(first, savedOptions: [second]))
        await model.loadMore()
        XCTAssertEqual(model.labels.displayLabel(for: first, savedOptions: []), "Alex Example, company-contact:101")
        XCTAssertEqual(model.labels.displayLabel(for: second, savedOptions: []), "Alex Example, company-contact:102")
        XCTAssertEqual(model.options.map(\.label), ["Alex Example", "Alex Example"])
        await model.startSearch("another search")
        XCTAssertTrue(model.labels.isDuplicate(first, savedOptions: []))
    }

    func testEmptyInitialAndIntermediatePagesRemainPageable() async {
        var cursors: [String?] = []
        let model = FormKitDynamicOptionsPickerModel { _, cursor in
            cursors.append(cursor)
            switch cursor {
            case nil:
                return FormKitDynamicOptionsPage(options: [], nextCursor: "empty-page")
            case "empty-page":
                return FormKitDynamicOptionsPage(options: [], nextCursor: "final-page")
            default:
                return FormKitDynamicOptionsPage(options: [self.option("last")])
            }
        }
        await model.startSearch("")
        XCTAssertTrue(model.options.isEmpty)
        XCTAssertEqual(model.nextCursor, "empty-page")
        await model.loadMore()
        XCTAssertTrue(model.options.isEmpty)
        XCTAssertEqual(model.nextCursor, "final-page")
        await model.loadMore()
        XCTAssertEqual(cursors, [nil, "empty-page", "final-page"])
        XCTAssertEqual(model.options.map(\.id), ["last"])
        XCTAssertNil(model.nextCursor)
    }

    func testStaleSavedLabelDoesNotMaskDuplicateProviderNames() {
        let labels = FormKitDynamicOptionsPickerLabels()
        let first = FormKitDynamicOption(id: "company-contact:101", label: "Alex")
        let second = FormKitDynamicOption(id: "company-contact:102", label: "Alex")
        let saved = [FormKitDynamicOption(id: first.id, label: "Old name")]
        labels.remember([first, second])
        XCTAssertEqual(labels.displayLabel(for: first, savedOptions: saved), "Alex, company-contact:101")
        XCTAssertEqual(labels.displayLabel(for: second, savedOptions: saved), "Alex, company-contact:102")
        XCTAssertEqual(labels.option(for: first.id, savedOptions: saved).label, "Old name")
    }

    func testLoadingAndUnavailableOptionsNeverWriteSelectionBindings() async {
        var singleValue: String? = "offline-id"
        var multipleValue = ["offline-id", "historical-id"]
        var writes = 0
        let single = FormKitDynamicSelection.single(Binding(get: { singleValue }, set: {
            writes += 1
            singleValue = $0
        }))
        let multiple = FormKitDynamicSelection.multiple(Binding(get: { multipleValue }, set: {
            writes += 1
            multipleValue = $0
        }))
        let model = FormKitDynamicOptionsPickerModel { search, _ in
            if search == "unavailable" {
                throw CancellationError()
            }
            return FormKitDynamicOptionsPage(options: [self.option("different-id")])
        }
        await model.startSearch("")
        await model.startSearch("unavailable")
        model.cancel()
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(single.ids, ["offline-id"])
        XCTAssertEqual(multiple.ids, ["offline-id", "historical-id"])
    }

    private func option(_ id: String) -> FormKitDynamicOption {
        FormKitDynamicOption(id: id, label: "Option \(id)")
    }
}

extension FormKitDynamicOptionsPickerTests {
    func testDetailIsDisplayOnlyAndDuplicateIDsRemainDistinct() {
        let first = FormKitDynamicOption(id: "opaque-first", label: "Alex", detail: "Example Construction")
        let second = FormKitDynamicOption(id: "opaque-second", label: "Alex", detail: "Example Mechanical")
        let labels = FormKitDynamicOptionsPickerLabels()
        labels.remember([first, second])
        XCTAssertEqual(labels.secondaryLabel(for: first, savedOptions: []), "Example Construction")
        XCTAssertEqual(labels.displayLabel(for: first, savedOptions: []), "Alex, Example Construction")
        XCTAssertEqual(labels.displayLabel(for: second, savedOptions: []), "Alex, Example Mechanical")
        var value: String?
        let selection = FormKitDynamicSelection.single(Binding(get: { value }, set: { value = $0 }))
        selection.choose(second.id, isRequired: false)
        XCTAssertEqual(value, "opaque-second")
        XCTAssertEqual(second.label, "Alex")
        let saved = FormKitDynamicOption(id: second.id, label: "Saved Alex", detail: "Saved company")
        XCTAssertEqual(labels.displayLabel(for: labels.option(for: second.id, savedOptions: [saved]),
                                          savedOptions: [saved]), "Saved Alex, Saved company")
        let withoutDetail = FormKitDynamicOption(id: first.id, label: "Alex", detail: "  ")
        XCTAssertEqual(labels.displayLabel(for: withoutDetail, savedOptions: []), "Alex, opaque-first")
    }

    func testMaximumSelectionCountBlocksAddsButAllowsDeselection() {
        var value = ["one"]
        let selection = FormKitDynamicSelection.multiple(Binding(get: { value }, set: { value = $0 }))
        XCTAssertTrue(selection.canChoose("two", maximumSelectionCount: 2))
        selection.choose("two", isRequired: false, maximumSelectionCount: 2)
        XCTAssertEqual(value, ["one", "two"])
        XCTAssertFalse(selection.canChoose("three", maximumSelectionCount: 2))
        selection.choose("three", isRequired: false, maximumSelectionCount: 2)
        XCTAssertEqual(value, ["one", "two"])
        XCTAssertTrue(selection.canChoose("one", maximumSelectionCount: 2))
        selection.choose("one", isRequired: false, maximumSelectionCount: 2)
        selection.choose("three", isRequired: false, maximumSelectionCount: 2)
        XCTAssertEqual(value, ["two", "three"])
    }

    func testPublishedFiftyOptionBoundaryAndOversizedHydrationPreserveAllIDs() {
        var value = (1...49).map { "company-user:\($0)" }
        var writes = 0
        let selection = FormKitDynamicSelection.multiple(Binding(get: { value }, set: {
            writes += 1
            value = $0
        }))
        selection.choose("company-user:50", isRequired: false, maximumSelectionCount: 50)
        XCTAssertEqual(value.count, 50)
        XCTAssertEqual(writes, 1)
        selection.choose("company-user:51", isRequired: false, maximumSelectionCount: 50)
        XCTAssertEqual(value.count, 50)
        XCTAssertEqual(writes, 1)
        value = (1...52).map { "company-user:\($0)" }
        let hydrated = selection.ids
        XCTAssertEqual(hydrated.count, 52)
        XCTAssertEqual(writes, 1)
        XCTAssertFalse(selection.canChoose("new-id", maximumSelectionCount: 50))
        selection.choose("company-user:52", isRequired: true, maximumSelectionCount: 50)
        XCTAssertEqual(value, Array(hydrated.dropLast()))
        XCTAssertEqual(writes, 2)
        XCTAssertFalse(selection.canChoose("new-id", maximumSelectionCount: 50))
    }

    func testSingleIgnoresArrayLimitAndRequiredEmptySelectionNeverAutofills() {
        var value: String?
        let single = FormKitDynamicSelection.single(Binding(get: { value }, set: { value = $0 }))
        XCTAssertTrue(single.canChoose("one", maximumSelectionCount: 0))
        XCTAssertNil(value)
        single.choose("one", isRequired: true, maximumSelectionCount: 0)
        XCTAssertEqual(value, "one")
        var empty: [String] = []
        var writes = 0
        let multiple = FormKitDynamicSelection.multiple(Binding(get: { empty }, set: {
            writes += 1
            empty = $0
        }))
        XCTAssertTrue(multiple.ids.isEmpty)
        XCTAssertEqual(writes, 0)
        multiple.choose("one", isRequired: true, maximumSelectionCount: 0)
        XCTAssertTrue(multiple.ids.isEmpty)
        XCTAssertEqual(writes, 0)
        multiple.choose("one", isRequired: true, maximumSelectionCount: 1)
        multiple.choose("one", isRequired: true, maximumSelectionCount: 1)
        XCTAssertEqual(empty, ["one"])
        XCTAssertEqual(writes, 1)
    }

}

@MainActor
private final class PendingDynamicOptionsRequests {
    struct Request {
        let search: String
        let cursor: String?
        let continuation: CheckedContinuation<FormKitDynamicOptionsPage, Error>
    }

    private struct Failure: Error {}
    private(set) var items: [Request] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func load(search: String, cursor: String?) async throws -> FormKitDynamicOptionsPage {
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

    func finish(_ index: Int, page: FormKitDynamicOptionsPage) {
        items[index].continuation.resume(returning: page)
    }

    func fail(_ index: Int) {
        items[index].continuation.resume(throwing: Failure())
    }
}
