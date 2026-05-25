import SwiftUI

struct FormKitOwnedSessionConfiguration: Equatable {
    let schemaJSON: String
    let instanceJSON: String?
    let defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior
    let validationBehavior: FormKitValidationBehavior

    @MainActor
    func makeSession() -> FormKitSession {
        FormKitRenderer(
            defaultConditionalRenderBehavior: defaultConditionalRenderBehavior
        ).makeFormSession(
            schemaJSON: schemaJSON,
            instanceJSON: instanceJSON,
            defaultConditionalRenderBehavior: nil,
            validationBehavior: validationBehavior
        )
    }
}

public struct FormKitView: View {
    private let injectedSession: FormKitSession?
    private let ownedSessionConfiguration: FormKitOwnedSessionConfiguration?
    private let options: FormKitOptions
    @State private var ownedSession: FormKitSession?
    @State private var activeOwnedSessionConfiguration: FormKitOwnedSessionConfiguration?

    public init(session: FormKitSession, options: FormKitOptions = .init()) {
        injectedSession = session
        ownedSessionConfiguration = nil
        self.options = options
        _ownedSession = State(initialValue: nil)
        _activeOwnedSessionConfiguration = State(initialValue: nil)
    }

    @MainActor
    public init(schemaJSON: String, instanceJSON: String? = nil, options: FormKitOptions = .init()) {
        let configuration = FormKitOwnedSessionConfiguration(
            schemaJSON: schemaJSON,
            instanceJSON: instanceJSON,
            defaultConditionalRenderBehavior: options.defaultConditionalRenderBehavior,
            validationBehavior: options.validationBehavior
        )

        injectedSession = nil
        ownedSessionConfiguration = configuration
        self.options = options
        _ownedSession = State(initialValue: configuration.makeSession())
        _activeOwnedSessionConfiguration = State(initialValue: configuration)
    }

    public var body: some View {
        if let session = injectedSession {
            FormKitContainerView(session: session, options: options)
        } else if let session = ownedSession {
            FormKitContainerView(session: session, options: options)
                .onChange(of: ownedSessionConfiguration) { _, newConfiguration in
                    guard let newConfiguration,
                          activeOwnedSessionConfiguration != newConfiguration
                    else {
                        return
                    }

                    ownedSession = newConfiguration.makeSession()
                    activeOwnedSessionConfiguration = newConfiguration
                }
        }
    }
}

private struct FormKitContainerView: View {
    @Bindable var session: FormKitSession
    let options: FormKitOptions
    @FocusState private var focusedFieldID: String?

    private var isEditingLocked: Bool {
        options.mode == .readOnly
    }

    var body: some View {
        let renderIndex = FormKitRenderIndex(renderPlan: session.renderPlan)

        Form {
            statusSection
            ForEach(renderIndex.visibleRootBlocks) { block in
                renderDisplayBlock(block, renderIndex: renderIndex)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .accessibilityIdentifier("formkit_form")
    }

    @ViewBuilder
    private var statusSection: some View {
        if session.formErrorMessage != nil || session.validationStatusMessage != nil || !session.renderPlan.isSupported {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if let validationStatus = session.validationStatusMessage {
                        Text(validationStatus)
                            .font(.caption)
                            .foregroundStyle(
                                session.formErrorMessage == nil
                                    && session.fieldErrors.isEmpty
                                    && session.arrayErrors.isEmpty
                                    ? options.style.success
                                    : options.style.destructive
                            )
                    }

                    if let formErrorMessage = session.formErrorMessage {
                        FormKitMessageRow(message: formErrorMessage, color: options.style.destructive)
                    }

                    ForEach(session.renderPlan.unsupportedReasons, id: \.message) { reason in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reason.title)
                                .font(.caption.weight(.semibold))
                            Text(reason.message)
                                .font(.caption)
                        }
                        .foregroundStyle(options.style.destructive)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func renderDisplayBlock(
        _ block: FormKitRenderIndex.DisplayBlock,
        renderIndex: FormKitRenderIndex
    ) -> some View {
        switch block.kind {
        case let .section(sectionID):
            if let section = renderIndex.section(sectionID),
               let arrayDescriptor = section.arrayDescriptor
            {
                arraySection(section, descriptor: arrayDescriptor, renderIndex: renderIndex)
            }

        case let .fieldGroup(sectionID, fieldIDs):
            if let section = renderIndex.section(sectionID) {
                formSection(
                    section,
                    fieldIDs: fieldIDs,
                    showHeader: block.showSectionHeader,
                    showFooter: block.showSectionFooter,
                    renderIndex: renderIndex
                )
            }
        }
    }

    private func formSection(
        _ section: FormKitRenderPlan.SectionDescriptor,
        fieldIDs: [String],
        showHeader: Bool,
        showFooter: Bool,
        renderIndex: FormKitRenderIndex
    ) -> some View {
        let visibleFields: [FormKitFieldDescriptor] = fieldIDs.compactMap { fieldID in
            guard let field = renderIndex.field(fieldID), field.isVisible else {
                return nil
            }
            return field
        }

        return Section {
            ForEach(visibleFields, id: \.id) { field in
                fieldCard(field, renderIndex: renderIndex)
            }
        } header: {
            if showHeader, let title = sectionHeaderTitle(for: section) {
                sectionHeader(section, title: title)
            }
        } footer: {
            if showFooter, let description = section.description, !description.isEmpty {
                Text(description)
            }
        }
        .accessibilityIdentifier(section.id)
    }

    @ViewBuilder
    private func arraySection(
        _ section: FormKitRenderPlan.SectionDescriptor,
        descriptor: FormKitArraySectionDescriptor,
        renderIndex: FormKitRenderIndex
    ) -> some View {
        let canAddMore = descriptor.maxItems.map { descriptor.rows.count < $0 } ?? true
        let arrayErrors = session.errorMessages(for: section)

        Section {
            if descriptor.rows.isEmpty {
                Text(options.labels.noItems)
                    .font(.caption)
                    .foregroundStyle(options.style.secondaryText)
                    .accessibilityIdentifier("\(section.id)_empty_state")
            }

            ForEach(descriptor.rows) { row in
                arrayRowView(row, in: section, descriptor: descriptor, renderIndex: renderIndex)
            }

            if options.mode == .editable {
                Button {
                    session.appendArrayRow(to: section)
                    focusFirstField(in: section)
                } label: {
                    Label("\(options.labels.addItemPrefix) \(descriptor.itemTitle)", systemImage: "plus.circle.fill")
                }
                .disabled(!canAddMore || section.isDisabled || isEditingLocked)
                .accessibilityIdentifier("\(section.id)_add_button")
            }

            if !arrayErrors.isEmpty {
                FormKitMessageRow(message: arrayErrors.joined(separator: "\n"), color: options.style.destructive)
                    .accessibilityIdentifier("\(section.id)_error")
            }
        } header: {
            if let title = sectionHeaderTitle(for: section) {
                sectionHeader(section, title: title)
            }
        } footer: {
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
        .accessibilityIdentifier(section.id)
    }

    @ViewBuilder
    private func sectionHeader(
        _ section: FormKitRenderPlan.SectionDescriptor,
        title: String
    ) -> some View {
        if let customHeader = options.components.sectionHeader {
            customHeader(FormKitSectionComponentContext(section: section))
        } else {
            Text(title)
        }
    }

    @ViewBuilder
    private func fieldCard(
        _ field: FormKitFieldDescriptor,
        renderIndex: FormKitRenderIndex
    ) -> some View {
        let errors = session.errorMessages(for: field)
        let state = options.fieldState(field)
        let locked = isEditingLocked || state == .locked

        if let customField = options.components.field {
            customField(
                FormKitFieldComponentContext(
                    session: session,
                    field: field,
                    errors: errors,
                    state: state,
                    isEditingLocked: locked
                )
            )
        } else {
            VStack(alignment: .leading, spacing: options.style.fieldSpacing) {
                if let description = field.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(options.style.secondaryText)
                }

                if field.allowsNull {
                    Picker(
                        options.labels.valueState,
                        selection: Binding(
                            get: { session.isNullSelected(for: field) ? 1 : 0 },
                            set: { session.setNullSelection($0 == 1, for: field) }
                        )
                    ) {
                        Text(options.labels.value).tag(0)
                        Text(options.labels.noValue).tag(1)
                    }
                    .pickerStyle(.segmented)
                    .disabled(locked || field.isDisabled)
                    .accessibilityIdentifier("\(fieldIdentifier(for: field))_null_picker")
                }

                if !session.isNullSelected(for: field) {
                    fieldInput(field, renderIndex: renderIndex, locked: locked)
                }

                if !errors.isEmpty {
                    FormKitMessageRow(message: errors.joined(separator: "\n"), color: options.style.destructive)
                        .padding(.top, 4)
                        .accessibilityIdentifier("\(fieldIdentifier(for: field))_error")
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: options.style.cornerRadius, style: .continuous)
                    .fill(options.style.fieldBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: options.style.cornerRadius, style: .continuous)
                    .stroke(borderColor(for: state, hasErrors: !errors.isEmpty), lineWidth: 1.5)
            )
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            .id(field.id)
            .disabled(field.isDisabled || locked)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(fieldIdentifier(for: field))
        }
    }

    @ViewBuilder
    private func fieldInput(
        _ field: FormKitFieldDescriptor,
        renderIndex: FormKitRenderIndex,
        locked: Bool
    ) -> some View {
        if field.isEnum {
            Picker(
                field.title,
                selection: Binding(
                    get: { session.selectedEnumChoiceID(for: field) },
                    set: { session.setSelectedEnumChoiceID($0, for: field) }
                )
            ) {
                if !field.isRequired {
                    Text(options.labels.notSet).tag(String?.none)
                }
                ForEach(field.enumOptions) { choice in
                    Text(choice.title).tag(Optional(choice.id))
                }
            }
            .disabled(locked)
            .accessibilityIdentifier("\(fieldIdentifier(for: field))_picker")
        } else {
            switch field.scalarType {
            case .boolean:
                Toggle(
                    field.title,
                    isOn: Binding(
                        get: { session.booleanValue(for: field) },
                        set: { session.setBooleanValue($0, for: field) }
                    )
                )
                .toggleStyle(.switch)
                .disabled(locked)
                .accessibilityIdentifier("\(fieldIdentifier(for: field))_toggle")

            case .date:
                DatePicker(
                    field.title,
                    selection: Binding(
                        get: { session.dateValue(for: field) },
                        set: { session.setDateValue($0, for: field) }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .disabled(locked)
                .accessibilityIdentifier("\(fieldIdentifier(for: field))_date_picker")

            case .dateTime:
                DatePicker(
                    field.title,
                    selection: Binding(
                        get: { session.dateValue(for: field) },
                        set: { session.setDateValue($0, for: field) }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .disabled(locked)
                .accessibilityIdentifier("\(fieldIdentifier(for: field))_date_picker")

            default:
                FormKitDebouncedTextInputField(
                    fieldID: field.id,
                    accessibilityIdentifier: "\(fieldIdentifier(for: field))_input",
                    accessibilityLabel: field.title,
                    prompt: fieldPrompt(for: field),
                    canonicalText: session.stringValue(for: field),
                    submitLabel: renderIndex.nextFocusableFieldID(after: field.id) == nil ? .done : .next,
                    nextFocusableFieldID: renderIndex.nextFocusableFieldID(after: field.id),
                    focusedFieldID: $focusedFieldID,
                    isEditingLocked: locked
                ) { updatedText in
                    session.setStringValue(updatedText, for: field)
                }
            }
        }
    }

    private func arrayRowView(
        _ row: FormKitArrayRowDescriptor,
        in section: FormKitRenderPlan.SectionDescriptor,
        descriptor: FormKitArraySectionDescriptor,
        renderIndex: FormKitRenderIndex
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if descriptor.itemKind == .object {
                Text(row.title)
                    .font(.headline)
            }

            if let field = renderIndex.firstVisibleField(in: row) {
                fieldCard(field, renderIndex: renderIndex)
            }

            ForEach(renderIndex.visibleSections(in: row), id: \.id) { nestedSection in
                VStack(alignment: .leading, spacing: 4) {
                    if nestedSection.pointer != row.pointer {
                        Text(nestedSection.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(options.style.secondaryText)
                    }
                    if let description = nestedSection.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(options.style.secondaryText)
                    }
                    ForEach(renderIndex.visibleFields(in: nestedSection), id: \.id) { field in
                        fieldCard(field, renderIndex: renderIndex)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if options.mode == .editable,
               descriptor.rows.count > descriptor.minItems,
               !section.isDisabled,
               !isEditingLocked
            {
                Button(role: .destructive) {
                    session.removeArrayRow(row, from: section)
                    focusedFieldID = nil
                } label: {
                    Label(options.labels.remove, systemImage: "trash")
                }
            }
        }
        .accessibilityIdentifier("\(section.id)_row_\(row.index)")
    }

    private func focusFirstField(in section: FormKitRenderPlan.SectionDescriptor) {
        let renderIndex = FormKitRenderIndex(renderPlan: session.renderPlan)
        guard let arrayDescriptor = renderIndex.section(section.id)?.arrayDescriptor,
              let row = arrayDescriptor.rows.last
        else {
            return
        }

        if let field = renderIndex.firstVisibleField(in: row) {
            focusedFieldID = field.id
        }
    }

    private func sectionHeaderTitle(for section: FormKitRenderPlan.SectionDescriptor) -> String? {
        if section.pointer == "#", section.title == session.renderPlan.title {
            return nil
        }
        return section.title
    }

    private func borderColor(for state: FormKitFieldVisualState, hasErrors: Bool) -> Color {
        if hasErrors {
            return options.style.destructive
        }
        switch state {
        case .changed:
            return options.style.accent
        case .locked:
            return options.style.secondaryText
        case .normal:
            return .clear
        }
    }

    private func fieldPrompt(for field: FormKitFieldDescriptor) -> String {
        switch field.scalarType {
        case .email:
            return "name@example.com"
        case .uri:
            return "https://example.com"
        case .integer:
            return "0"
        case .number:
            return "0.0"
        default:
            return field.title
        }
    }

    private func fieldIdentifier(for field: FormKitFieldDescriptor) -> String {
        FormKitAccessibility.fieldIdentifier(for: field)
    }
}

private struct FormKitMessageRow: View {
    let message: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .foregroundStyle(color)
                .multilineTextAlignment(.leading)
        }
    }
}

private struct FormKitDebouncedTextInputField: View {
    let fieldID: String
    let accessibilityIdentifier: String
    let accessibilityLabel: String
    let prompt: String
    let canonicalText: String
    let submitLabel: SubmitLabel
    let nextFocusableFieldID: String?
    let focusedFieldID: FocusState<String?>.Binding
    let isEditingLocked: Bool
    let onCommit: (String) -> Void

    @State private var draftText: String

    init(
        fieldID: String,
        accessibilityIdentifier: String,
        accessibilityLabel: String,
        prompt: String,
        canonicalText: String,
        submitLabel: SubmitLabel,
        nextFocusableFieldID: String?,
        focusedFieldID: FocusState<String?>.Binding,
        isEditingLocked: Bool,
        onCommit: @escaping (String) -> Void
    ) {
        self.fieldID = fieldID
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityLabel = accessibilityLabel
        self.prompt = prompt
        self.canonicalText = canonicalText
        self.submitLabel = submitLabel
        self.nextFocusableFieldID = nextFocusableFieldID
        self.focusedFieldID = focusedFieldID
        self.isEditingLocked = isEditingLocked
        self.onCommit = onCommit
        _draftText = State(initialValue: canonicalText)
    }

    var body: some View {
        TextField(prompt, text: $draftText, axis: .vertical)
            .lineLimit(1...)
            .submitLabel(submitLabel)
            .focused(focusedFieldID, equals: fieldID)
            .disabled(isEditingLocked)
            .onChange(of: canonicalText) { _, newValue in
                guard draftText != newValue else {
                    return
                }
                draftText = newValue
            }
            .onChange(of: focusedFieldID.wrappedValue) { _, newValue in
                if newValue != fieldID {
                    commitIfNeeded()
                }
            }
            .onSubmit {
                commitIfNeeded()
                focusedFieldID.wrappedValue = nextFocusableFieldID
            }
            .onDisappear {
                commitIfNeeded()
            }
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityLabel(accessibilityLabel)
    }

    private func commitIfNeeded() {
        guard draftText != canonicalText else {
            return
        }
        onCommit(draftText)
    }
}
