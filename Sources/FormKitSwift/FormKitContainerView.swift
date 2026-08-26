import SwiftUI

struct FormKitContainerView: View {
    @Bindable var session: FormKitSession
    let externalFocusedFieldID: Binding<String?>?
    let options: FormKitOptions
    @FocusState var focusedFieldID: String?
    @State var pendingTextDrafts: [String: String] = [:]
    @State var pendingArraySectionFocusID: String?

    var isEditingLocked: Bool { options.mode == .readOnly }

    var body: some View {
        let components = FormKitFocusSupport.resolvedComponents(session: session, options: options)
        let renderIndex = FormKitRenderIndex(
            renderPlan: session.renderPlan,
            focusableFieldIDs: components.focusableFieldIDs
        )

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
                keyboardSubmitButton(renderIndex: renderIndex)
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
            handleFocusedFieldChange(newValue, focusableFieldIDs: components.focusableFieldIDs)
        }
        .onChange(of: components.focusableFieldIDs) { _, focusableFieldIDs in
            handleFocusableFieldIDsChange(focusableFieldIDs)
        }
        .task(id: session.revision) {
            focusPendingArrayRow(renderIndex: renderIndex)
        }
        .onChange(of: isEditingLocked) { _, isEditingLocked in
            if isEditingLocked {
                commitFocusedTextDraft()
                focusedFieldID = nil
            }
        }
        .accessibilityIdentifier("formkit_form")
    }

    #if os(iOS) || os(visionOS)
    @ViewBuilder
    private func keyboardSubmitButton(renderIndex: FormKitRenderIndex) -> some View {
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
    #endif

    private func handleFocusedFieldChange(
        _ newValue: String?,
        focusableFieldIDs: Set<String>
    ) {
        let normalizedFieldID = FormKitFocusSupport.normalizedFieldID(
            newValue,
            focusableFieldIDs: focusableFieldIDs
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

    private func handleFocusableFieldIDsChange(_ focusableFieldIDs: Set<String>) {
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

    private func focusPendingArrayRow(renderIndex: FormKitRenderIndex) {
        guard let sectionID = pendingArraySectionFocusID else {
            return
        }
        pendingArraySectionFocusID = nil
        focusFirstField(in: sectionID, renderIndex: renderIndex)
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
        if session.formErrorMessage != nil
            || session.validationStatusMessage != nil
            || !session.renderPlan.isSupported
        {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if let validationStatus = session.validationStatusMessage {
                        Text(validationStatus)
                            .font(.caption)
                            .foregroundStyle(validationStatusColor)
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

    private var validationStatusColor: Color {
        session.formErrorMessage == nil
            && session.fieldErrors.isEmpty
            && session.arrayErrors.isEmpty
            ? options.style.success
            : options.style.destructive
    }
}
