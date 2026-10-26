import SwiftUI

extension FormKitContainerView {
    /// The fields keyboard focus may move between: those on the page on screen, or `nil` when the
    /// form scrolls as one page.
    func focusScope(pages: [FormKitFormPage]) -> Set<String>? {
        guard let pageNavigator, !pages.isEmpty else {
            return nil
        }
        guard !pageNavigator.isSummaryOpen else {
            return []
        }
        return Set(pages[min(pageNavigator.currentPage, pages.count - 1)].fieldIDs)
    }

    func pagedForm(
        navigator: FormKitPageNavigator,
        pages: [FormKitFormPage],
        renderIndex: FormKitRenderIndex,
        components: FormKitResolvedComponents
    ) -> some View {
        let summary = session.formSummary(pages: pages)
        let currentPage = min(navigator.currentPage, pages.count - 1)
        let labels = options.labels.pages

        return VStack(spacing: 0) {
            FormKitPageHeader(
                progress: summary.pages,
                currentPage: currentPage,
                isSummaryOpen: navigator.isSummaryOpen,
                style: options.style,
                labels: labels,
                onPrevious: { navigator.previousPage(origin: .user) },
                onNext: { navigator.nextPage(origin: .user) },
                onOpenJump: { isPageJumpSheetPresented = true }
            )

            ScrollViewReader { proxy in
                Form {
                    statusSection
                    if navigator.isSummaryOpen {
                        FormKitPageSummarySections(
                            summary: summary,
                            missingTitles: summary.missingRequired.map(session.qualifiedTitle(for:)),
                            style: options.style,
                            labels: labels,
                            onPick: { navigator.goToPage($0, origin: .user) }
                        )
                    } else {
                        pageContent(
                            pages[currentPage],
                            nextTitle: pages.indices.contains(currentPage + 1) ? pages[currentPage + 1].title : nil,
                            navigator: navigator,
                            renderIndex: renderIndex,
                            components: components
                        )
                    }
                }
                // A new page starts at its top.
                .id(navigator.position)
                .task(id: navigator.scrollTargetFieldID) {
                    guard let fieldID = navigator.scrollTargetFieldID else {
                        return
                    }
                    await Task.yield()
                    withAnimation {
                        proxy.scrollTo(fieldID, anchor: .center)
                    }
                    navigator.scrollTargetFieldID = nil
                }
            }
        }
        .onAppear {
            navigator.session = session
        }
        .onChange(of: ObjectIdentifier(session)) {
            navigator.session = session
        }
        .onChange(of: navigator.position) { _, position in
            leavePageFocus(for: position, pages: pages)
        }
        .sheet(isPresented: $isPageJumpSheetPresented) {
            FormKitPageJumpSheet(
                progress: summary.pages,
                currentPage: currentPage,
                isSummaryOpen: navigator.isSummaryOpen,
                style: options.style,
                labels: labels,
                onPick: { index in
                    isPageJumpSheetPresented = false
                    navigator.goToPage(index, origin: .user)
                },
                onSummary: {
                    isPageJumpSheetPresented = false
                    navigator.openSummary(origin: .user)
                },
                onDismiss: { isPageJumpSheetPresented = false }
            )
        }
    }

    @ViewBuilder
    private func pageContent(
        _ page: FormKitFormPage,
        nextTitle: String?,
        navigator: FormKitPageNavigator,
        renderIndex: FormKitRenderIndex,
        components: FormKitResolvedComponents
    ) -> some View {
        if page.index == 0, let description = session.renderPlan.description, !description.isEmpty {
            Section {} footer: {
                Text(description)
            }
        }
        ForEach(renderIndex.pageBlocks(for: page)) { block in
            renderDisplayBlock(block, renderIndex: renderIndex, components: components)
        }
        FormKitPageFooter(
            nextTitle: nextTitle,
            style: options.style,
            labels: options.labels.pages,
            onContinue: { navigator.nextPage(origin: .user) }
        )
    }

    /// Keeps a half-typed answer and drops keyboard focus when the focused field is not on the new page.
    private func leavePageFocus(for position: FormKitPagePosition, pages: [FormKitFormPage]) {
        guard let focusedFieldID else {
            return
        }
        if case let .page(index) = position,
           pages.indices.contains(index),
           pages[index].fieldIDs.contains(focusedFieldID)
        {
            return
        }
        commitFocusedTextDraft()
        self.focusedFieldID = nil
    }
}
