import SwiftUI

/// The top of a section-pages form: one bar per section showing how far it has got, and a row with
/// previous, "2 of 6 · Equipment", and next. The middle button opens the jump sheet. It stays above the
/// scrolling page so it never scrolls away.
struct FormKitPageHeader: View {
    let progress: [FormKitPageProgress]
    let currentPage: Int
    let isSummaryOpen: Bool
    let style: FormKitStyle
    let labels: FormKitPageLabels
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onOpenJump: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(progress) { page in
                    let isCurrent = !isSummaryOpen && page.page.index == currentPage
                    Capsule()
                        .fill(barColor(for: page, isCurrent: isCurrent))
                        .frame(height: isCurrent ? 6 : 4)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 12)
            .accessibilityHidden(true)

            HStack(spacing: 4) {
                chevronButton("chevron.left", label: labels.previousSection, action: onPrevious)
                    .disabled(!isSummaryOpen && currentPage == 0)
                    .accessibilityIdentifier("formkit_page_previous")
                Button(action: onOpenJump) {
                    HStack(spacing: 4) {
                        Text(positionTitle)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.down")
                            .imageScale(.small)
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .overlay(Capsule().stroke(style.secondaryText.opacity(0.35)))
                .accessibilityHint(labels.goToSection)
                .accessibilityIdentifier("formkit_page_jump")
                chevronButton("chevron.right", label: labels.nextSection, action: onNext)
                    .disabled(isSummaryOpen)
                    .accessibilityIdentifier("formkit_page_next")
            }
        }
        .padding(.top, 12)
        .padding([.horizontal, .bottom], 6)
        .background(style.fieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Self.groupedBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("formkit_page_header")
    }

    /// Matches the grouped form below, so the header reads as a card on the same surface.
    private static var groupedBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    private var positionTitle: String {
        guard !isSummaryOpen else {
            return labels.summary
        }
        let position = labels.position(page: currentPage + 1, of: progress.count)
        guard let title = progress.first(where: { $0.page.index == currentPage })?.page.title else {
            return position
        }
        return "\(position) · \(title)"
    }

    private func chevronButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    private func barColor(for page: FormKitPageProgress, isCurrent: Bool) -> Color {
        // The page on screen is darker while it has nothing answered yet.
        if isCurrent, page.status == .notStarted {
            return style.secondaryText
        }
        return FormKitPageStatusView.color(for: page.status, style: style)
    }
}

/// Every section with its progress, plus the summary. Tapping one goes there.
struct FormKitPageJumpSheet: View {
    let progress: [FormKitPageProgress]
    let currentPage: Int
    let isSummaryOpen: Bool
    let style: FormKitStyle
    let labels: FormKitPageLabels
    let onPick: (Int) -> Void
    let onSummary: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(progress) { page in
                        FormKitPageRow(
                            progress: page,
                            isSelected: !isSummaryOpen && page.page.index == currentPage,
                            style: style,
                            labels: labels
                        ) {
                            onPick(page.page.index)
                        }
                    }
                }
                Section {
                    Button(action: onSummary) {
                        Label(labels.summary, systemImage: "list.bullet.clipboard")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(isSummaryOpen ? style.accent.opacity(0.12) : nil)
                    .accessibilityAddTraits(isSummaryOpen ? .isSelected : [])
                    .accessibilityIdentifier("formkit_page_jump_summary")
                }
            }
            .navigationTitle(labels.goToSection)
            #if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(labels.close, action: onDismiss)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("formkit_page_jump_sheet")
    }
}

/// One section in the jump sheet or on the summary page: number, title, and how far it has got.
struct FormKitPageRow: View {
    let progress: FormKitPageProgress
    let isSelected: Bool
    let style: FormKitStyle
    let labels: FormKitPageLabels
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(progress.page.index + 1, format: .number)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(style.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(style.secondaryText.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                Text(progress.page.title)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                FormKitPageStatusView(progress: progress, style: style, labels: labels)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? style.accent.opacity(0.12) : nil)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("formkit_page_row_\(progress.page.index)")
    }
}

struct FormKitPageStatusView: View {
    let progress: FormKitPageProgress
    let style: FormKitStyle
    let labels: FormKitPageLabels

    var body: some View {
        switch progress.status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(style.success)
                .imageScale(.large)
                .accessibilityLabel(labels.done)
        case .needsAttention:
            Text(labels.needsAttention)
                .font(.footnote)
                .foregroundStyle(style.destructive)
        case .notStarted, .partial:
            Text(labels.status(for: progress))
                .font(.footnote)
                .foregroundStyle(style.secondaryText)
        }
    }

    static func color(for status: FormKitPageProgress.Status, style: FormKitStyle) -> Color {
        switch status {
        case .done:
            return style.success
        case .partial:
            return style.success.opacity(0.45)
        case .needsAttention:
            return style.destructive
        case .notStarted:
            return style.secondaryText.opacity(0.25)
        }
    }
}

/// "Continue to Equipment" at the foot of a page, or "Review summary" on the last one.
struct FormKitPageFooter: View {
    let nextTitle: String?
    let style: FormKitStyle
    let labels: FormKitPageLabels
    let onContinue: () -> Void

    var body: some View {
        Section {
            Button(action: onContinue) {
                HStack(spacing: 8) {
                    Text(nextTitle.map(labels.continueTo) ?? labels.reviewSummary)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .accessibilityHidden(true)
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(style.accent)
            .accessibilityIdentifier("formkit_page_continue")
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}

/// The summary page: each section's progress (tap one to go back to it), the answers that opened
/// follow-ups with what was entered for them, and anything required that is still empty.
struct FormKitPageSummarySections: View {
    let summary: FormKitFormSummary
    let missingTitles: [String]
    let style: FormKitStyle
    let labels: FormKitPageLabels
    let onPick: (Int) -> Void

    var body: some View {
        Section {
            ForEach(summary.pages) { page in
                FormKitPageRow(progress: page, isSelected: false, style: style, labels: labels) {
                    onPick(page.page.index)
                }
            }
        }

        if !summary.flagged.isEmpty {
            Section(labels.flaggedAnswers) {
                ForEach(summary.flagged) { flagged in
                    Button {
                        if let pageIndex = flagged.pageIndex {
                            onPick(pageIndex)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(flagged.qualifiedTitle)
                            Text(flaggedDescription(flagged))
                                .font(.subheadline)
                                .foregroundStyle(style.destructive)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            }

        if !missingTitles.isEmpty {
            Section(labels.stillRequired) {
                Text(missingTitles.joined(separator: ", "))
                    .foregroundStyle(style.destructive)
            }
            }
    }

    private func flaggedDescription(_ flagged: FormKitFlaggedAnswer) -> String {
        let details = flagged.details.map(\.answer).filter { !$0.isEmpty }.joined(separator: " · ")
        return details.isEmpty ? flagged.answer : "\(flagged.answer) — \(details)"
    }
}
