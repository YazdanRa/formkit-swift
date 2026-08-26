import SwiftUI

extension FormKitContainerView {
    func arrayRowView(
        _ row: FormKitArrayRowDescriptor,
        in section: FormKitRenderPlan.SectionDescriptor,
        descriptor: FormKitArraySectionDescriptor,
        renderIndex: FormKitRenderIndex,
        components: FormKitResolvedComponents
    ) -> some View {
        arrayRowContent(
            row,
            descriptor: descriptor,
            renderIndex: renderIndex,
            components: components
        )
        .padding(12)
        .background(
            .background,
            in: RoundedRectangle(cornerRadius: options.style.cornerRadius + 4, style: .continuous)
        )
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canRemoveRow(from: section, descriptor: descriptor) {
                Button(role: .destructive) {
                    removeArrayRow(row, from: section)
                } label: {
                    Label(options.labels.remove, systemImage: "trash")
                }
            }
        }
        .accessibilityIdentifier("\(section.id)_row_\(row.index)")
    }

    private func arrayRowContent(
        _ row: FormKitArrayRowDescriptor,
        descriptor: FormKitArraySectionDescriptor,
        renderIndex: FormKitRenderIndex,
        components: FormKitResolvedComponents
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if descriptor.itemKind == .object {
                Text(row.title)
                    .font(.headline)
            }

            if let field = renderIndex.firstVisibleField(in: row) {
                fieldCard(field, renderIndex: renderIndex, components: components)
            }

            ForEach(renderIndex.visibleSections(in: row), id: \.id) { nestedSection in
                nestedArraySection(
                    nestedSection,
                    row: row,
                    renderIndex: renderIndex,
                    components: components
                )
            }
        }
    }

    private func nestedArraySection(
        _ section: FormKitRenderPlan.SectionDescriptor,
        row: FormKitArrayRowDescriptor,
        renderIndex: FormKitRenderIndex,
        components: FormKitResolvedComponents
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if section.pointer != row.pointer {
                Text(section.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(options.style.secondaryText)
            }
            if let description = section.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(options.style.secondaryText)
            }
            ForEach(renderIndex.visibleFields(in: section), id: \.id) { field in
                fieldCard(field, renderIndex: renderIndex, components: components)
            }
        }
    }

    private func canRemoveRow(
        from section: FormKitRenderPlan.SectionDescriptor,
        descriptor: FormKitArraySectionDescriptor
    ) -> Bool {
        options.mode == .editable
            && descriptor.rows.count > descriptor.minItems
            && !section.isDisabled
            && !isEditingLocked
    }

    private func removeArrayRow(
        _ row: FormKitArrayRowDescriptor,
        from section: FormKitRenderPlan.SectionDescriptor
    ) {
        commitFocusedTextDraft()
        focusedFieldID = nil
        DispatchQueue.main.async {
            guard let currentSection = session.renderPlan.sections.first(where: { $0.id == section.id }) else {
                return
            }
            session.removeArrayRow(row, from: currentSection)
        }
    }
}
