import SwiftUI

struct FormKitOwnedSessionConfiguration: Equatable {
    let schemaJSON: String
    let instanceJSON: String?
    let defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior
    let conditionalRenderBehaviorOverrides: [String: FormKitConditionalRenderBehavior]
    let validationBehavior: FormKitValidationBehavior

    init(
        schemaJSON: String,
        instanceJSON: String?,
        defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior,
        conditionalRenderBehaviorOverrides: [String: FormKitConditionalRenderBehavior] = [:],
        validationBehavior: FormKitValidationBehavior
    ) {
        self.schemaJSON = schemaJSON
        self.instanceJSON = instanceJSON
        self.defaultConditionalRenderBehavior = defaultConditionalRenderBehavior
        self.conditionalRenderBehaviorOverrides = conditionalRenderBehaviorOverrides
        self.validationBehavior = validationBehavior
    }

    @MainActor
    func makeSession() -> FormKitSession {
        FormKitRenderer(
            defaultConditionalRenderBehavior: defaultConditionalRenderBehavior,
            conditionalRenderBehaviorOverrides: conditionalRenderBehaviorOverrides
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
    private let externalFocusedFieldID: Binding<String?>?
    private let ownedSessionConfiguration: FormKitOwnedSessionConfiguration?
    private let options: FormKitOptions
    @State private var ownedSession: FormKitSession?
    @State private var activeOwnedSessionConfiguration: FormKitOwnedSessionConfiguration?

    public init(session: FormKitSession, options: FormKitOptions = .init()) {
        injectedSession = session
        externalFocusedFieldID = nil
        ownedSessionConfiguration = nil
        self.options = options
        _ownedSession = State(initialValue: nil)
        _activeOwnedSessionConfiguration = State(initialValue: nil)
    }

    public init(
        session: FormKitSession,
        focusedFieldID: Binding<String?>,
        options: FormKitOptions = .init()
    ) {
        injectedSession = session
        externalFocusedFieldID = focusedFieldID
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
            conditionalRenderBehaviorOverrides: options.conditionalRenderBehaviorOverrides,
            validationBehavior: options.validationBehavior
        )

        injectedSession = nil
        externalFocusedFieldID = nil
        ownedSessionConfiguration = configuration
        self.options = options
        _ownedSession = State(initialValue: configuration.makeSession())
        _activeOwnedSessionConfiguration = State(initialValue: configuration)
    }

    public var body: some View {
        if let session = injectedSession {
            FormKitContainerView(
                session: session,
                externalFocusedFieldID: externalFocusedFieldID,
                options: options
            )
        } else if let session = ownedSession {
            FormKitContainerView(session: session, externalFocusedFieldID: nil, options: options)
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
    let externalFocusedFieldID: Binding<String?>?
    let options: FormKitOptions
    @FocusState private var focusedFieldID: String?
    @State private var pendingTextDrafts: [String: String] = [:]
    @State private var pendingArraySectionFocusID: String?

    private var isEditingLocked: Bool { options.mode == .readOnly }

    var body: some View {
        let components = FormKitFocusSupport.resolvedComponents(session: session, options: options)
        let renderIndex = FormKitRenderIndex(renderPlan: session.renderPlan,
                                             focusableFieldIDs: components.focusableFieldIDs)

        Form {
            statusSection
            ForEach(renderIndex.renderableRootBlocks) { block in
                renderDisplayBlock(block, renderIndex: renderIndex, components: components)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        #if os(iOS) || os(visionOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if let focusedFieldID,
                   let field = renderIndex.field(focusedFieldID),
                   FormKitTextInputTraits(scalarType: field.scalarType).supportsVerticalExpansion
                {
                    Spacer()
                    Button {
                        advanceFocus(after: focusedFieldID)
                    } label: {
                        Text(
                            renderIndex.nextFocusableFieldID(after: focusedFieldID) == nil
                                ? String(localized: "Done", bundle: .module)
                                : String(localized: "Next", bundle: .module)
                        )
                    }
                    .accessibilityIdentifier("formkit_keyboard_submit")
                }
            }
        }
        #endif
        .onAppear {
            synchronizeFocusFromHost(
                externalFocusedFieldID?.wrappedValue,
                focusableFieldIDs: components.focusableFieldIDs
            )
        }
        .onChange(of: externalFocusedFieldID?.wrappedValue) { _, newValue in
            synchronizeFocusFromHost(newValue, focusableFieldIDs: components.focusableFieldIDs)
        }
        .onChange(of: focusedFieldID) { _, newValue in
            let normalizedFieldID = FormKitFocusSupport.normalizedFieldID(
                newValue,
                focusableFieldIDs: components.focusableFieldIDs
            )
            guard normalizedFieldID == newValue else {
                focusedFieldID = normalizedFieldID
                return
            }
            guard let externalFocusedFieldID,
                  externalFocusedFieldID.wrappedValue != normalizedFieldID
            else {
                return
            }
            externalFocusedFieldID.wrappedValue = normalizedFieldID
        }
        .onChange(of: components.focusableFieldIDs) { _, focusableFieldIDs in
            if let externalFocusedFieldID {
                synchronizeFocusFromHost(
                    externalFocusedFieldID.wrappedValue,
                    focusableFieldIDs: focusableFieldIDs
                )
            } else if FormKitFocusSupport.normalizedFieldID(
                focusedFieldID,
                focusableFieldIDs: focusableFieldIDs
            ) != focusedFieldID {
                commitFocusedTextDraft()
                focusedFieldID = nil
            }
        }
        .task(id: session.revision) {
            guard let sectionID = pendingArraySectionFocusID else {
                return
            }
            pendingArraySectionFocusID = nil
            focusFirstField(in: sectionID, renderIndex: renderIndex)
        }
        .onChange(of: isEditingLocked) { _, isEditingLocked in
            if isEditingLocked {
                commitFocusedTextDraft()
                focusedFieldID = nil
            }
        }
        .accessibilityIdentifier("formkit_form")
    }

    private func synchronizeFocusFromHost(
        _ requestedFieldID: String?,
        focusableFieldIDs: Set<String>
    ) {
        guard let externalFocusedFieldID else {
            return
        }

        var currentFocusableFieldIDs = focusableFieldIDs
        if requestedFieldID != nil,
           focusedFieldID != requestedFieldID,
           commitFocusedTextDraft()
        {
            currentFocusableFieldIDs = FormKitFocusSupport.resolvedComponents(
                session: session,
                options: options
            ).focusableFieldIDs
        }
        let normalizedFieldID = FormKitFocusSupport.normalizedFieldID(
            requestedFieldID,
            focusableFieldIDs: currentFocusableFieldIDs
        )

        if focusedFieldID != normalizedFieldID {
            commitFocusedTextDraft()
            focusedFieldID = normalizedFieldID
        }
        if externalFocusedFieldID.wrappedValue != normalizedFieldID {
            externalFocusedFieldID.wrappedValue = normalizedFieldID
        }
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
                    showHeader: block.showSectionHeader,
                    showFooter: block.showSectionFooter,
                    renderIndex: renderIndex,
                    components: components
                )
            }
        }
    }

    private func formSection(
        _ section: FormKitRenderPlan.SectionDescriptor,
        fieldIDs: [String],
        showHeader: Bool,
        showFooter: Bool,
        renderIndex: FormKitRenderIndex,
        components: FormKitResolvedComponents
    ) -> some View {
        let visibleFields: [FormKitFieldDescriptor] = fieldIDs.compactMap { fieldID in
            guard let field = renderIndex.field(fieldID), field.isVisible else {
                return nil
            }
            return field
        }
        let accessibilityID = fieldIDs.isEmpty && showFooter ? "\(section.id)_footer" : section.id

        return Section {
            ForEach(visibleFields, id: \.id) { field in
                fieldCard(field, renderIndex: renderIndex, components: components)
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
        .accessibilityIdentifier(accessibilityID)
    }

    @ViewBuilder
    private func arraySection(
        _ section: FormKitRenderPlan.SectionDescriptor,
        descriptor: FormKitArraySectionDescriptor,
        renderIndex: FormKitRenderIndex,
        components: FormKitResolvedComponents
    ) -> some View {
        let canAddMore = descriptor.maxItems.map { descriptor.rows.count < $0 } ?? true
        let arrayErrors = session.errorMessages(for: section)

        if let customArraySection = components.arraySections[section.id] {
            customArraySection
        } else {
            Section {
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
                    Button {
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
    }
}

private extension FormKitContainerView {
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

    @ViewBuilder
    func fieldCard(
        _ field: FormKitFieldDescriptor,
        renderIndex: FormKitRenderIndex,
        components: FormKitResolvedComponents
    ) -> some View {
        let errors = session.errorMessages(for: field)
        let state = components.fieldStates[field.id] ?? options.fieldState(field)
        let locked = isEditingLocked || state == .locked
        let componentContext = FormKitFieldComponentContext(
            session: session,
            field: field,
            errors: errors,
            state: state,
            isEditingLocked: locked,
            style: options.style,
            uploadHandler: options.uploadHandler
        )

        if let customField = options.components.field {
            customField(componentContext)
        } else {
            let componentInput = components.fieldInputs[field.id]
                ?? FormKitComponentRegistry.fieldInput(for: componentContext)
            let usesStackedLabel = componentInput != nil
                || (!field.isEnum && ![.boolean, .date, .time, .dateTime].contains(field.scalarType))
            VStack(alignment: .leading, spacing: options.style.fieldSpacing) {
                if usesStackedLabel {
                    Text(field.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(options.style.secondaryText)
                        .accessibilityHidden(componentInput == nil)
                }

                if let description = field.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(options.style.secondaryText)
                }

                if usesStackedLabel {
                    resolvedFieldInput(
                        componentInput,
                        field: field,
                        renderIndex: renderIndex,
                        locked: locked
                    )
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: options.style.cornerRadius, style: .continuous)
                            .fill(
                                locked || field.isDisabled
                                    ? options.style.disabledFieldBackground
                                    : options.style.fieldBackground
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: options.style.cornerRadius, style: .continuous)
                            .stroke(
                                borderColor(for: field, state: state, hasErrors: !errors.isEmpty),
                                lineWidth: 1.5
                            )
                    )
                } else {
                    resolvedFieldInput(
                        componentInput,
                        field: field,
                        renderIndex: renderIndex,
                        locked: locked
                    )
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }

                if !errors.isEmpty {
                    FormKitMessageRow(message: errors.joined(separator: "\n"), color: options.style.destructive)
                        .padding(.top, 4)
                        .accessibilityIdentifier("\(fieldIdentifier(for: field))_error")
                }
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            .id(field.id)
            .disabled(field.isDisabled || locked)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(fieldIdentifier(for: field))
            .accessibilityValue(state.formKitAccessibilityValue)
        }
    }

    @ViewBuilder
    func resolvedFieldInput(
        _ componentInput: AnyView?,
        field: FormKitFieldDescriptor,
        renderIndex: FormKitRenderIndex,
        locked: Bool
    ) -> some View {
        if let componentInput {
            componentInput
        } else {
            fieldInput(field, renderIndex: renderIndex, locked: locked)
        }
    }

    @ViewBuilder
    func fieldInput(
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
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("\(fieldIdentifier(for: field))_picker")
        } else {
            switch field.scalarType {
            case .boolean:
                if field.allowsNull {
                    Picker(
                        field.title,
                        selection: Binding(
                            get: { nullableBooleanSelection(for: field) },
                            set: { selection in
                                switch selection {
                                case .absent:
                                    session.unsetValue(for: field)
                                case .null:
                                    session.setNullSelection(true, for: field)
                                case .boolean(let value):
                                    session.setBooleanValue(value, for: field)
                                }
                            }
                        )
                    ) {
                        if !field.isRequired {
                            Text(options.labels.notSet).tag(NullableBooleanSelection.absent)
                        }
                        Text(options.labels.noValue).tag(NullableBooleanSelection.null)
                        Text("Off", bundle: .module).tag(NullableBooleanSelection.boolean(false))
                        Text("On", bundle: .module).tag(NullableBooleanSelection.boolean(true))
                    }
                    .pickerStyle(.menu)
                    .disabled(locked)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityIdentifier("\(fieldIdentifier(for: field))_picker")
                } else {
                    Toggle(
                        field.title,
                        isOn: Binding(
                            get: { session.booleanValue(for: field) },
                            set: { session.setBooleanValue($0, for: field) }
                        )
                    )
                    .toggleStyle(.switch)
                    .disabled(locked)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityIdentifier("\(fieldIdentifier(for: field))_toggle")
                }

            case .date, .time, .dateTime:
                if let displayedComponents = field.scalarType.datePickerComponents {
                    dateInput(field, displayedComponents: displayedComponents, locked: locked)
                }

            default:
                FormKitDebouncedTextInputField(
                    fieldID: field.id,
                    accessibilityIdentifier: "\(fieldIdentifier(for: field))_input",
                    accessibilityLabel: field.title,
                    prompt: fieldPrompt(for: field),
                    canonicalText: session.stringValue(for: field),
                    submitLabel: renderIndex.nextFocusableFieldID(after: field.id) == nil ? .done : .next,
                    focusedFieldID: $focusedFieldID,
                    inputTraits: FormKitTextInputTraits(scalarType: field.scalarType),
                    isEditingLocked: locked,
                    onDraftChange: { draft in
                        pendingTextDrafts[field.id] = draft
                    },
                    onSubmit: {
                        advanceFocus(after: field.id)
                    }
                ) { updatedText in
                    guard pendingTextDrafts.removeValue(forKey: field.id) != nil else {
                        return
                    }
                    session.setStringValue(updatedText, for: field)
                }
            }
        }
    }

    @ViewBuilder
    func dateInput(
        _ field: FormKitFieldDescriptor,
        displayedComponents: DatePickerComponents,
        locked: Bool
    ) -> some View {
        if field.allowsNull {
            VStack(alignment: .trailing, spacing: 8) {
                Picker(
                    field.title,
                    selection: Binding(
                        get: { nullableValueSelection(for: field) },
                        set: { selection in
                            switch selection {
                            case .absent:
                                session.unsetValue(for: field)
                            case .null:
                                session.setNullSelection(true, for: field)
                            case .value:
                                session.setDateValue(session.dateValue(for: field), for: field)
                            }
                        }
                    )
                ) {
                    if !field.isRequired {
                        Text(options.labels.notSet).tag(NullableValueSelection.absent)
                    }
                    Text(options.labels.noValue).tag(NullableValueSelection.null)
                    Text(options.labels.value).tag(NullableValueSelection.value)
                }
                .pickerStyle(.menu)
                .disabled(locked)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("\(fieldIdentifier(for: field))_date_state_picker")

                if nullableValueSelection(for: field) == .value {
                    datePicker(field, displayedComponents: displayedComponents, locked: locked)
                        .labelsHidden()
                }
            }
        } else {
            datePicker(field, displayedComponents: displayedComponents, locked: locked)
        }
    }

    func datePicker(
        _ field: FormKitFieldDescriptor,
        displayedComponents: DatePickerComponents,
        locked: Bool
    ) -> some View {
        DatePicker(
            field.title,
            selection: Binding(
                get: { session.dateValue(for: field) },
                set: { session.setDateValue($0, for: field) }
            ),
            displayedComponents: displayedComponents
        )
        .datePickerStyle(.compact)
        .disabled(locked)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityIdentifier("\(fieldIdentifier(for: field))_date_picker")
    }
}

private extension FormKitContainerView {
    func arrayRowView(
        _ row: FormKitArrayRowDescriptor,
        in section: FormKitRenderPlan.SectionDescriptor,
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
                        fieldCard(field, renderIndex: renderIndex, components: components)
                    }
                }
            }
        }
        .padding(12)
        .background(
            .background,
            in: RoundedRectangle(cornerRadius: options.style.cornerRadius + 4, style: .continuous)
        )
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if options.mode == .editable,
               descriptor.rows.count > descriptor.minItems,
               !section.isDisabled,
                !isEditingLocked
            {
                Button(role: .destructive) {
                    commitFocusedTextDraft()
                    focusedFieldID = nil
                    DispatchQueue.main.async {
                        guard let currentSection = session.renderPlan.sections.first(where: { $0.id == section.id }) else {
                            return
                        }
                        session.removeArrayRow(row, from: currentSection)
                    }
                } label: {
                    Label(options.labels.remove, systemImage: "trash")
                }
            }
        }
        .accessibilityIdentifier("\(section.id)_row_\(row.index)")
    }

    func focusFirstField(in sectionID: String, renderIndex: FormKitRenderIndex) {
        guard let arrayDescriptor = renderIndex.section(sectionID)?.arrayDescriptor,
              let row = arrayDescriptor.rows.last
        else {
            return
        }

        if let field = renderIndex.firstFocusableField(in: row) {
            focusedFieldID = field.id
        }
    }

    @discardableResult
    func commitFocusedTextDraft() -> Bool {
        guard let focusedFieldID,
              let draft = pendingTextDrafts.removeValue(forKey: focusedFieldID),
              let field = session.renderPlan.fields.first(where: { $0.id == focusedFieldID })
        else {
            return false
        }

        session.setStringValue(draft, for: field)
        return true
    }

    func advanceFocus(after fieldID: String) {
        commitFocusedTextDraft()
        let focusableIDs = FormKitFocusSupport.resolvedComponents(session: session, options: options).focusableFieldIDs
        let renderIndex = FormKitRenderIndex(renderPlan: session.renderPlan, focusableFieldIDs: focusableIDs)
        focusedFieldID = renderIndex.nextFocusableFieldID(after: fieldID)
    }

    func sectionHeaderTitle(for section: FormKitRenderPlan.SectionDescriptor) -> String? {
        if section.pointer == "#", section.title == session.renderPlan.title {
            return nil
        }
        return section.title
    }

    func borderColor(
        for field: FormKitFieldDescriptor,
        state: FormKitFieldVisualState,
        hasErrors: Bool
    ) -> Color {
        if hasErrors {
            return options.style.destructive
        }
        if focusedFieldID == field.id {
            return options.style.accent
        }
        switch state {
        case .changed:
            return options.style.accent
        case .locked:
            return options.style.secondaryText
        case .normal:
            return options.style.secondaryText.opacity(0.25)
        }
    }

    func fieldPrompt(for field: FormKitFieldDescriptor) -> String {
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
            return ""
        }
    }

    func nullableBooleanSelection(for field: FormKitFieldDescriptor) -> NullableBooleanSelection {
        switch session.primitiveValue(for: field) {
        case .boolean(let value):
            return .boolean(value)
        case .null:
            return .null
        case nil:
            return .absent
        default:
            return field.isRequired ? .null : .absent
        }
    }

    func nullableValueSelection(for field: FormKitFieldDescriptor) -> NullableValueSelection {
        if session.isConcreteValuePending(for: field) {
            return .value
        }

        switch session.primitiveValue(for: field) {
        case .string, .integer, .number:
            return .value
        case .null:
            return .null
        case nil:
            return .absent
        default:
            return field.isRequired ? .null : .absent
        }
    }

    func fieldIdentifier(for field: FormKitFieldDescriptor) -> String {
        FormKitAccessibility.fieldIdentifier(for: field)
    }
}

private enum NullableBooleanSelection: Hashable {
    case absent
    case null
    case boolean(Bool)
}

private enum NullableValueSelection: Hashable {
    case absent
    case null
    case value
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
    let focusedFieldID: FocusState<String?>.Binding
    let inputTraits: FormKitTextInputTraits
    let isEditingLocked: Bool
    let onDraftChange: (String?) -> Void
    let onSubmit: () -> Void
    let onCommit: (String) -> Void

    @State private var draftText: String

    init(
        fieldID: String,
        accessibilityIdentifier: String,
        accessibilityLabel: String,
        prompt: String,
        canonicalText: String,
        submitLabel: SubmitLabel,
        focusedFieldID: FocusState<String?>.Binding,
        inputTraits: FormKitTextInputTraits,
        isEditingLocked: Bool,
        onDraftChange: @escaping (String?) -> Void,
        onSubmit: @escaping () -> Void,
        onCommit: @escaping (String) -> Void
    ) {
        self.fieldID = fieldID
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityLabel = accessibilityLabel
        self.prompt = prompt
        self.canonicalText = canonicalText
        self.submitLabel = submitLabel
        self.focusedFieldID = focusedFieldID
        self.inputTraits = inputTraits
        self.isEditingLocked = isEditingLocked
        self.onDraftChange = onDraftChange
        self.onSubmit = onSubmit
        self.onCommit = onCommit
        _draftText = State(initialValue: canonicalText)
    }

    var body: some View {
        textField
            .formKitTextInputTraits(inputTraits)
    }

    private var textField: some View {
        TextField(
            prompt,
            text: Binding(
                get: { draftText },
                set: { newValue in
                    draftText = newValue
                    onDraftChange(newValue == canonicalText ? nil : newValue)
                }
            ),
            axis: inputTraits.supportsVerticalExpansion ? .vertical : .horizontal
        )
            .lineLimit(1...)
            .submitLabel(inputTraits.supportsVerticalExpansion ? .return : submitLabel)
            .focused(focusedFieldID, equals: fieldID)
            .disabled(isEditingLocked)
            .onChange(of: canonicalText) { _, newValue in
                guard draftText != newValue else {
                    return
                }
                draftText = newValue
                onDraftChange(nil)
            }
            .onChange(of: focusedFieldID.wrappedValue) { _, newValue in
                if newValue != fieldID {
                    commitIfNeeded()
                }
            }
            .onSubmit {
                commitIfNeeded()
                onSubmit()
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
