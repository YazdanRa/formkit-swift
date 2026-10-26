import SwiftUI

/// Page navigation for a section-pages form, built from the same Liquid Glass parts as the system
/// bars: a round previous button, a capsule showing "1 of 6 · Housekeeping" with the section's progress
/// bars that opens a menu of every section and the summary, and a round next button. It floats above
/// the page so the host keeps its own navigation bar and bottom accessories.
struct FormKitPageNavigationBar: View {
    let progress: [FormKitPageProgress]
    let currentPage: Int
    let isSummaryOpen: Bool
    let style: FormKitStyle
    let labels: FormKitPageLabels
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onPick: (Int) -> Void
    let onSummary: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            stepButton("chevron.backward", label: labels.previousSection, action: onPrevious)
                .disabled(!isSummaryOpen && currentPage == 0)
                .accessibilityIdentifier("formkit_page_previous")

            Menu {
                sectionMenu
            } label: {
                VStack(spacing: 5) {
                    HStack(spacing: 4) {
                        Text(positionTitle)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    progressBars
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Capsule())
                .modifier(FormKitGlassBackground(shape: Capsule()))
            }
            // Primary text, like the titles in the system bars, rather than the menu's tint.
            .tint(.primary)
            .accessibilityLabel(positionTitle)
            .accessibilityHint(labels.goToSection)
            .accessibilityIdentifier("formkit_page_jump")

            stepButton("chevron.forward", label: labels.nextSection, action: onNext)
                .disabled(isSummaryOpen)
                .accessibilityIdentifier("formkit_page_next")
        }
        // Keeps the control compact and centered on wide layouts such as iPad.
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("formkit_page_header")
    }

    @ViewBuilder
    private var sectionMenu: some View {
        Section(labels.goToSection) {
            ForEach(progress) { page in
                Button {
                    onPick(page.page.index)
                } label: {
                    if !isSummaryOpen, page.page.index == currentPage {
                        Label(page.page.title, systemImage: "checkmark")
                    } else {
                        Text(page.page.title)
                    }
                    Text(labels.status(for: page))
                }
            }
        }
        Section {
            Button(action: onSummary) {
                Label(labels.summary, systemImage: isSummaryOpen ? "checkmark" : "list.bullet.clipboard")
            }
        }
    }

    private var progressBars: some View {
        HStack(spacing: 3) {
            ForEach(progress) { page in
                let isCurrent = !isSummaryOpen && page.page.index == currentPage
                Capsule()
                    .fill(barColor(for: page, isCurrent: isCurrent))
                    .frame(height: 3)
            }
        }
        .frame(maxWidth: 220)
        .accessibilityHidden(true)
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

    private func stepButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                .modifier(FormKitGlassBackground(shape: Circle()))
        }
        .buttonStyle(.plain)
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

/// Liquid Glass where the system has it, and a material on earlier systems.
private struct FormKitGlassBackground<GlassShape: Shape>: ViewModifier {
    let shape: GlassShape
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        let content = content.opacity(isEnabled ? 1 : 0.35)
        #if os(visionOS)
        content.background(.regularMaterial, in: shape)
        #else
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular.interactive(isEnabled), in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
        #endif
    }
}

/// One section on the summary page: number, title, and how far it has got.
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

/// "Continue to Equipment" at the foot of a page, or "Review summary" on the last one, as a standard-size
/// Liquid Glass button on the trailing edge, where the next step reads.
struct FormKitPageContinueButton: View {
    let nextTitle: String?
    let labels: FormKitPageLabels
    let onContinue: () -> Void

    var body: some View {
        Section {
            Button(action: onContinue) {
                HStack(spacing: 6) {
                    Text(nextTitle.map(labels.continueTo) ?? labels.reviewSummary)
                        .multilineTextAlignment(.center)
                    Image(systemName: "arrow.forward")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
            }
            .modifier(FormKitGlassButtonStyle())
            .controlSize(.regular)
            .tint(.primary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("formkit_page_continue")
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}

/// The system glass button style where the system has it, and a bordered button on earlier systems.
private struct FormKitGlassButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(visionOS)
        content.buttonStyle(.bordered)
        #else
        if #available(iOS 26.0, macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
        #endif
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
