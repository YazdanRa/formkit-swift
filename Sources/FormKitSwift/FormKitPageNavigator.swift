import Foundation
import Observation

/// Where a ``FormKitFormLayout/sectionPages`` form is: one of its pages or the summary page.
public enum FormKitPagePosition: Hashable, Sendable {
    case page(Int)
    case summary
}

/// Who asked for a page change.
public enum FormKitPageNavigationOrigin: Equatable, Sendable {
    /// The person using the form tapped a page control.
    case user
    /// The host app, such as a voice assistant moving to the question it asks next.
    case host
}

/// Page state for a ``FormKitFormLayout/sectionPages`` form.
///
/// ``FormKitView`` creates one when the host does not pass its own. Hosts that need to turn pages
/// themselves, or to react when the person pages by hand, keep a navigator and pass it to the view.
@MainActor
@Observable
public final class FormKitPageNavigator {
    /// The page shown, or the page the summary was opened from while ``isSummaryOpen`` is `true`.
    public private(set) var currentPage = 0
    public private(set) var isSummaryOpen = false
    /// The field to bring into view after a host page turn. The view clears it once it has scrolled.
    public internal(set) var scrollTargetFieldID: String?

    /// Called after a page change with ``FormKitPageNavigationOrigin/user`` origin.
    @ObservationIgnored
    public var onUserNavigation: (@MainActor (FormKitPagePosition) -> Void)?

    /// The session whose pages this navigator moves through. ``FormKitView`` attaches its session
    /// when it appears; hosts that rebuild sessions can reassign it.
    @ObservationIgnored
    public var session: FormKitSession?

    public init(session: FormKitSession? = nil) {
        self.session = session
    }

    public var position: FormKitPagePosition {
        isSummaryOpen ? .summary : .page(currentPage)
    }

    private var pageCount: Int {
        session?.formPages.count ?? 0
    }

    /// Shows page `index`, clamped to the form's pages.
    public func goToPage(_ index: Int, origin: FormKitPageNavigationOrigin = .host) {
        let count = pageCount
        guard count > 0 else {
            return
        }
        let target = min(max(index, 0), count - 1)
        guard target != currentPage || isSummaryOpen else {
            return
        }
        currentPage = target
        isSummaryOpen = false
        notify(origin)
    }

    /// Shows the next page, or the summary after the last page.
    public func nextPage(origin: FormKitPageNavigationOrigin = .host) {
        guard !isSummaryOpen else {
            return
        }
        if currentPage >= pageCount - 1 {
            openSummary(origin: origin)
        } else {
            goToPage(currentPage + 1, origin: origin)
        }
    }

    /// Shows the previous page. From the summary, returns to the page it was opened from.
    public func previousPage(origin: FormKitPageNavigationOrigin = .host) {
        if isSummaryOpen {
            goToPage(currentPage, origin: origin)
        } else if currentPage > 0 {
            goToPage(currentPage - 1, origin: origin)
        }
    }

    /// Opens the summary page.
    public func openSummary(origin: FormKitPageNavigationOrigin = .host) {
        guard pageCount > 0, !isSummaryOpen else {
            return
        }
        isSummaryOpen = true
        notify(origin)
    }

    /// Turns to the page holding the field without reporting a user navigation, closing the summary
    /// if it is open. Does nothing for fields that are on no page.
    public func revealField(_ fieldID: String, scrollsToField: Bool = true) {
        guard let index = session?.pageIndex(containing: fieldID) else {
            return
        }
        if index != currentPage || isSummaryOpen {
            currentPage = index
            isSummaryOpen = false
        }
        if scrollsToField {
            scrollTargetFieldID = fieldID
        }
    }

    private func notify(_ origin: FormKitPageNavigationOrigin) {
        if origin == .user {
            onUserNavigation?(position)
        }
    }
}
