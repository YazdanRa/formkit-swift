import SwiftUI

extension FormKitContainerView {
    @ViewBuilder
    func renderDisplayBlock(
        _ block: FormKitRenderIndex.DisplayBlock,
        renderIndex: FormKitRenderIndex,
        components: FormKitResolvedComponents
    ) -> some View {
        switch block.kind {
        case let .section(sectionID):
            if let section = renderIndex.section(sectionID),
               let arrayDescriptor = section.arrayDescriptor
            {
                arraySection(
                    section,
                    descriptor: arrayDescriptor,
                    renderIndex: renderIndex,
                    components: components
                )
            }

        case let .fieldGroup(sectionID, fieldIDs):
            if let section = renderIndex.section(sectionID) {
                formSection(
                    section,
                    fieldIDs: fieldIDs,
                    block: block,
                    renderIndex: renderIndex,
                    components: components
                )
            }
        }
    }

    private func formSection(
        _ section: FormKitRenderPlan.SectionDescriptor,
        fieldIDs: [String],
        block: FormKitRenderIndex.DisplayBlock,
        renderIndex: FormKitRenderIndex,
        components: FormKitResolvedComponents
    ) -> some View {
        let visibleFields: [FormKitFieldDescriptor] = fieldIDs.compactMap { fieldID in
            guard let field = renderIndex.field(fieldID), field.isVisible else {
                return nil
            }
            return field
        }
        let accessibilityID = FormKitAccessibility.sectionIdentifier(
            section.id,
            fieldIDs: fieldIDs,
            showsHeader: block.showSectionHeader
        )

        return Section {
            ForEach(visibleFields, id: \.id) { field in
                fieldCard(field, renderIndex: renderIndex, components: components)
            }
        } header: {
            if block.showSectionHeader, let title = sectionHeaderTitle(for: section) {
                sectionHeader(section, title: title)
            }
        } footer: {
            if block.showSectionFooter, let description = section.description, !description.isEmpty {
                Text(description)
            }
        }
        .accessibilityIdentifier(accessibilityID)
    }

    @ViewBuilder
    private func arraySection(
        _ section: FormKitRenderPlan.SectionDescriptor,
        descriptor: FormKitArraySectionDescriptor,
        renderIndex: FormKitRenderIndex,
        components: FormKitResolvedComponents
    ) -> some View {
        if let customArraySection = components.arraySections[section.id] {
            customArraySection
        } else {
            stockArraySection(
                section,
                descriptor: descriptor,
                renderIndex: renderIndex,
                components: components
            )
        }
    }

    private func stockArraySection(
        _ section: FormKitRenderPlan.SectionDescriptor,
        descriptor: FormKitArraySectionDescriptor,
        renderIndex: FormKitRenderIndex,
        components: FormKitResolvedComponents
    ) -> some View {
        Section {
            arraySectionRows(
                section,
                descriptor: descriptor,
                renderIndex: renderIndex,
                components: components
            )
        } header: {
            if let title = sectionHeaderTitle(for: section) {
                sectionHeader(section, title: title)
            }
        } footer: {
            arraySectionFooter(section, descriptor: descriptor)
        }
        .accessibilityIdentifier(section.id)
    }

    @ViewBuilder
    private func arraySectionRows(
        _ section: FormKitRenderPlan.SectionDescriptor,
        descriptor: FormKitArraySectionDescriptor,
        renderIndex: FormKitRenderIndex,
        components: FormKitResolvedComponents
    ) -> some View {
        if descriptor.rows.isEmpty {
            Text(options.labels.noItems)
                .font(.caption)
                .foregroundStyle(options.style.secondaryText)
                .accessibilityIdentifier("\(section.id)_empty_state")
        }

        ForEach(descriptor.rows) { row in
            arrayRowView(
                row,
                in: section,
                descriptor: descriptor,
                renderIndex: renderIndex,
                components: components
            )
        }

        if options.mode == .editable {
            arrayAddButton(section, descriptor: descriptor)
        }

        let arrayErrors = session.errorMessages(for: section)
        if !arrayErrors.isEmpty {
            FormKitMessageRow(message: arrayErrors.joined(separator: "\n"), color: options.style.destructive)
                .accessibilityIdentifier("\(section.id)_error")
        }
    }

    private func arrayAddButton(
        _ section: FormKitRenderPlan.SectionDescriptor,
        descriptor: FormKitArraySectionDescriptor
    ) -> some View {
        let canAddMore = descriptor.maxItems.map { descriptor.rows.count < $0 } ?? true
        return Button {
            pendingArraySectionFocusID = section.id
            session.appendArrayRow(to: section)
        } label: {
            Label(
                "\(options.labels.addItemPrefix) \(descriptor.itemTitle)",
                systemImage: "plus.circle.fill"
            )
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .disabled(!canAddMore || section.isDisabled || isEditingLocked)
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("\(section.id)_add_button")
    }

    private func arraySectionFooter(
        _ section: FormKitRenderPlan.SectionDescriptor,
        descriptor: FormKitArraySectionDescriptor
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let description = section.description, !description.isEmpty {
                Text(description)
            }
            if descriptor.minItems > 0 {
                Text("\(options.labels.minimumItemsPrefix) \(descriptor.minItems)")
            }
            if let maxItems = descriptor.maxItems {
                Text("\(options.labels.maximumItemsPrefix) \(maxItems)")
            }
        }
    }

    @ViewBuilder
    func sectionHeader(
        _ section: FormKitRenderPlan.SectionDescriptor,
        title: String
    ) -> some View {
        if let customHeader = options.components.sectionHeader {
            customHeader(FormKitSectionComponentContext(section: section))
        } else {
            Text(title)
        }
    }

    func sectionHeaderTitle(for section: FormKitRenderPlan.SectionDescriptor) -> String? {
        if section.pointer == "#", section.title == session.renderPlan.title {
            return nil
        }
        return section.title
    }
}
