import Foundation

/// Text for the page header, jump sheet, footer, and summary of a ``FormKitFormLayout/sectionPages`` form.
///
/// Format strings take positional arguments, so translations can reorder them.
public struct FormKitPageLabels: Equatable, Sendable {
    public static let localizedDefaults = FormKitPageLabels(
        positionFormat: String(localized: "%1$lld of %2$lld", bundle: .module),
        previousSection: String(localized: "Previous section", bundle: .module),
        nextSection: String(localized: "Next section", bundle: .module),
        goToSection: String(localized: "Go to section", bundle: .module),
        continueToFormat: String(localized: "Continue to %@", bundle: .module),
        reviewSummary: String(localized: "Review summary", bundle: .module),
        summary: String(localized: "Summary", bundle: .module),
        answeredFormat: String(localized: "%1$lld of %2$lld answered", bundle: .module),
        done: String(
            localized: "formkit.page.status.done",
            defaultValue: "Done",
            bundle: .module,
            comment: "Status of a form section whose questions are all answered."
        ),
        notAnswered: String(localized: "Not answered", bundle: .module),
        needsAttention: String(localized: "Needs attention", bundle: .module),
        flaggedAnswers: String(localized: "Flagged answers", bundle: .module),
        stillRequired: String(localized: "Still required", bundle: .module),
        close: String(localized: "Done", bundle: .module)
    )

    /// The page position, such as "2 of 6". Takes the page number and the page count.
    public var positionFormat: String
    public var previousSection: String
    public var nextSection: String
    public var goToSection: String
    /// The footer button, such as "Continue to Equipment". Takes the next page's title.
    public var continueToFormat: String
    public var reviewSummary: String
    public var summary: String
    /// A section's progress, such as "3 of 8 answered". Takes the answered and total counts.
    public var answeredFormat: String
    public var done: String
    public var notAnswered: String
    public var needsAttention: String
    public var flaggedAnswers: String
    public var stillRequired: String
    /// Dismisses the jump sheet.
    public var close: String

    public init(
        positionFormat: String = FormKitPageLabels.localizedDefaults.positionFormat,
        previousSection: String = FormKitPageLabels.localizedDefaults.previousSection,
        nextSection: String = FormKitPageLabels.localizedDefaults.nextSection,
        goToSection: String = FormKitPageLabels.localizedDefaults.goToSection,
        continueToFormat: String = FormKitPageLabels.localizedDefaults.continueToFormat,
        reviewSummary: String = FormKitPageLabels.localizedDefaults.reviewSummary,
        summary: String = FormKitPageLabels.localizedDefaults.summary,
        answeredFormat: String = FormKitPageLabels.localizedDefaults.answeredFormat,
        done: String = FormKitPageLabels.localizedDefaults.done,
        notAnswered: String = FormKitPageLabels.localizedDefaults.notAnswered,
        needsAttention: String = FormKitPageLabels.localizedDefaults.needsAttention,
        flaggedAnswers: String = FormKitPageLabels.localizedDefaults.flaggedAnswers,
        stillRequired: String = FormKitPageLabels.localizedDefaults.stillRequired,
        close: String = FormKitPageLabels.localizedDefaults.close
    ) {
        self.positionFormat = positionFormat
        self.previousSection = previousSection
        self.nextSection = nextSection
        self.goToSection = goToSection
        self.continueToFormat = continueToFormat
        self.reviewSummary = reviewSummary
        self.summary = summary
        self.answeredFormat = answeredFormat
        self.done = done
        self.notAnswered = notAnswered
        self.needsAttention = needsAttention
        self.flaggedAnswers = flaggedAnswers
        self.stillRequired = stillRequired
        self.close = close
    }

    func position(page: Int, of count: Int) -> String {
        String(format: positionFormat, locale: .current, page, count)
    }

    func continueTo(_ title: String) -> String {
        String(format: continueToFormat, locale: .current, title)
    }

    func answered(_ answered: Int, of total: Int) -> String {
        String(format: answeredFormat, locale: .current, answered, total)
    }

    func status(for progress: FormKitPageProgress) -> String {
        switch progress.status {
        case .done:
            return done
        case .needsAttention:
            return needsAttention
        case .notStarted:
            return notAnswered
        case .partial:
            return answered(progress.answered, of: progress.total)
        }
    }
}
