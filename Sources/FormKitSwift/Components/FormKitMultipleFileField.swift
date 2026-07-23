import SwiftUI
import UniformTypeIdentifiers

struct FormKitMultipleFileField: View {
    @Bindable var session: FormKitSession
    let section: FormKitRenderPlan.SectionDescriptor
    let descriptor: FormKitArraySectionDescriptor
    let errors: [String]
    let isEditingLocked: Bool
    let style: FormKitStyle
    let uploadHandler: FormKitUploadHandler?
    @State private var isImporterPresented = false
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var isClearConfirmationPresented = false

    init(context: FormKitArraySectionComponentContext) {
        session = context.session
        section = context.section
        descriptor = context.descriptor
        errors = context.errors
        isEditingLocked = context.isEditingLocked
        style = context.style
        uploadHandler = context.uploadHandler
    }

    var body: some View {
        Section {
            if currentFiles.isEmpty {
                FormKitUploadEmptyState(
                    title: String(localized: "No files selected", bundle: #bundle),
                    subtitle: uploadHandler == nil
                        ? String(localized: "An upload handler is required.", bundle: #bundle)
                        : String(localized: "Choose files to upload.", bundle: #bundle),
                    systemImage: "doc.on.doc"
                )
            } else {
                ForEach(currentFiles, id: \.offset) { index, urlString in
                    fileRow(urlString: urlString, index: index)
                }
            }

            Button {
                uploadError = nil
                isImporterPresented = true
            } label: {
                FormKitUploadActionRow(
                    title: isUploading
                        ? String(localized: "Uploading", bundle: #bundle)
                        : String(localized: "Choose Files", bundle: #bundle),
                    systemImage: "doc.badge.plus",
                    tint: canUploadMore ? style.accent : style.secondaryText,
                    isBusy: isUploading
                )
            }
            .buttonStyle(.plain)
            .disabled(!canUploadMore)
            .accessibilityHint(uploadActionHint)

            if canClearAll {
                Button(role: .destructive) {
                    isClearConfirmationPresented = true
                } label: {
                    FormKitUploadActionRow(
                        title: String(localized: "Clear All", bundle: #bundle),
                        systemImage: "trash",
                        tint: style.destructive
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canClearAll)
            }

            if uploadHandler == nil {
                FormKitUploadStatusText(
                    message: String(localized: "Upload unavailable", bundle: #bundle),
                    color: style.secondaryText,
                    systemImage: "exclamationmark.circle"
                )
            }

            if let uploadError {
                FormKitUploadStatusText(
                    message: uploadError,
                    color: style.destructive,
                    systemImage: "exclamationmark.triangle"
                )
            }

            if !errors.isEmpty {
                FormKitUploadStatusText(
                    message: errors.joined(separator: "\n"),
                    color: style.destructive,
                    systemImage: "exclamationmark.triangle"
                )
            }
        } header: {
            Text(section.title)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let description = section.description, !description.isEmpty {
                    Text(description)
                }
                if descriptor.minItems > 0 {
                    Text("Minimum items: \(descriptor.minItems)", bundle: #bundle)
                }
                if let maxItems = descriptor.maxItems {
                    Text("Maximum items: \(maxItems)", bundle: #bundle)
                }
            }
        }
        .accessibilityIdentifier(section.id)
        .confirmationDialog(
            String(localized: "Clear all files?", bundle: #bundle),
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Clear All", bundle: #bundle), role: .destructive) {
                session.setArrayValue([], for: section)
            }
            Button(String(localized: "Cancel", bundle: #bundle), role: .cancel) {}
        } message: {
            Text("This removes all uploaded file URLs from this field.", bundle: #bundle)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: handleImportResult
        )
    }

    private var currentValues: [FormKitJSONValue] {
        session.arrayValue(for: section) ?? []
    }

    private var currentFiles: [(offset: Int, element: String)] {
        currentValues.enumerated().compactMap { index, value in
            value.string.map { (index, $0) }
        }
    }

    private var canUploadMore: Bool {
        guard uploadHandler != nil, !isUploading, !isEditingLocked, !section.isDisabled else {
            return false
        }
        if let maxItems = descriptor.maxItems {
            return currentValues.count < maxItems
        }
        return true
    }

    private var canClearAll: Bool {
        !isUploading
            && !isEditingLocked
            && !section.isDisabled
            && descriptor.minItems == 0
            && !currentValues.isEmpty
    }

    private var uploadActionHint: String {
        if isUploading {
            return String(localized: "Files are uploading.", bundle: #bundle)
        }
        if uploadHandler == nil {
            return String(localized: "Upload unavailable because no upload handler is configured.", bundle: #bundle)
        }
        if isEditingLocked || section.isDisabled {
            return String(localized: "This field is not editable.", bundle: #bundle)
        }
        if let maxItems = descriptor.maxItems, currentValues.count >= maxItems {
            return String(localized: "Maximum number of files reached.", bundle: #bundle)
        }
        return String(localized: "Opens the file picker.", bundle: #bundle)
    }

    private func fileRow(urlString: String, index: Int) -> some View {
        FormKitUploadRow(
            title: displayName(for: urlString),
            subtitle: urlString,
            systemImage: formKitUploadSymbolName(for: urlString),
            accent: style.accent,
            removeLabel: String(localized: "Remove file", bundle: #bundle),
            removeAction: canRemoveURL ? { removeURL(at: index) } : nil
        )
    }

    private var canRemoveURL: Bool {
        !isUploading
            && !isEditingLocked
            && !section.isDisabled
            && currentValues.count > descriptor.minItems
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        guard let uploadHandler else {
            uploadError = String(localized: "Upload unavailable.", bundle: #bundle)
            return
        }

        switch result {
        case .success(let urls):
            let remainingSlots = descriptor.maxItems.map { max(0, $0 - currentValues.count) } ?? urls.count
            let selectedURLs = Array(urls.prefix(remainingSlots))
            guard !selectedURLs.isEmpty else {
                return
            }
            Task {
                await upload(selectedURLs, using: uploadHandler)
            }
        case .failure(let error):
            uploadError = error.localizedDescription
        }
    }

    private func upload(_ urls: [URL], using uploadHandler: @escaping FormKitUploadHandler) async {
        isUploading = true
        defer { isUploading = false }
        let originalValue = session.arrayValue(for: section)
        let originalValues = originalValue ?? []

        let accessTokens = urls.map { url in
            (url, url.startAccessingSecurityScopedResource())
        }
        defer {
            for (url, didAccess) in accessTokens where didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let assets = try await uploadHandler(
                FormKitUploadRequest(
                    component: .multipleFileField,
                    pointer: section.pointer,
                    title: section.title,
                    items: urls.map(FormKitUploadItem.init(fileURL:))
                )
            )
            let remainingSlots = descriptor.maxItems.map { max(0, $0 - originalValues.count) }
                ?? assets.count
            let uploadedURLs = assets.lazy.map(\.url).filter { !$0.isEmpty }.prefix(remainingSlots)
            guard !uploadedURLs.isEmpty else {
                uploadError = String(localized: "Upload did not return any URLs.", bundle: #bundle)
                return
            }
            guard session.renderPlan.sections.contains(section),
                  session.arrayValue(for: section) == originalValue
            else {
                uploadError = String(
                    localized: "The form changed before the files finished uploading.",
                    bundle: #bundle
                )
                return
            }
            session.setArrayValue(
                originalValues + uploadedURLs.map(FormKitJSONValue.string),
                for: section
            )
            uploadError = nil
        } catch {
            uploadError = error.localizedDescription
        }
    }

    private func removeURL(at index: Int) {
        var values = currentValues
        guard values.indices.contains(index), values.count > descriptor.minItems else {
            return
        }
        values.remove(at: index)
        session.setArrayValue(values, for: section)
    }

    private func displayName(for urlString: String) -> String {
        URL(string: urlString)?.lastPathComponent.formKitNonEmpty ?? urlString
    }
}

#Preview("FormKit Multiple File Field") {
    let schema =
        """
        {
          "type": "object",
          "properties": {
            "attachments": {
              "type": "array",
              "title": "Attachments",
              "description": "Upload one or more files.",
              "x-formkit-ui-component": "multiple-file-field",
              "items": {
                "type": "string",
                "format": "uri"
              }
            }
          }
        }
        """
    let session = FormKitRenderer().makeFormSession(
        schemaJSON: schema,
        instanceJSON: #"{"attachments":["https://example.com/uploads/site-plan.pdf"]}"#
    )
    FormKitView(
        session: session,
        options: FormKitOptions(
            uploadHandler: { request in
                request.items.enumerated().map { index, item in
                    FormKitUploadedAsset(
                        url: "https://example.com/uploads/\(item.name ?? "file-\(index)")"
                    )
                }
            }
        )
    )
}
