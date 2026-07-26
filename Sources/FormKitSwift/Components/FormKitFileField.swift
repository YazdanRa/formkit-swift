import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct FormKitFileField: View {
    @Bindable var session: FormKitSession
    let field: FormKitFieldDescriptor
    let isEditingLocked: Bool
    let style: FormKitStyle
    let uploadHandler: FormKitUploadHandler?
    @State private var isImporterPresented = false
    @State private var isUploading = false
    @State private var uploadError: String?

    init(context: FormKitFieldComponentContext) {
        session = context.session
        field = context.field
        isEditingLocked = context.isEditingLocked
        style = context.style
        uploadHandler = context.uploadHandler
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if currentURL.isEmpty {
                FormKitUploadEmptyState(
                    title: String(localized: "No file selected", bundle: .module),
                    subtitle: uploadHandler == nil
                        ? String(localized: "An upload handler is required.", bundle: .module)
                        : String(localized: "Choose a file to upload.", bundle: .module),
                    systemImage: "doc"
                )
            } else {
                fileRow(urlString: currentURL)
            }

            Button {
                uploadError = nil
                isImporterPresented = true
            } label: {
                FormKitUploadActionRow(
                    title: uploadActionTitle,
                    systemImage: currentURL.isEmpty ? "doc.badge.plus" : "arrow.triangle.2.circlepath",
                    tint: canChooseFile ? style.accent : style.secondaryText,
                    isBusy: isUploading
                )
            }
            .buttonStyle(.plain)
            .disabled(!canChooseFile)
            .accessibilityHint(uploadActionHint)

            if uploadHandler == nil {
                FormKitUploadStatusText(
                    message: String(localized: "Upload unavailable", bundle: .module),
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
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false,
            onCompletion: handleImportResult
        )
    }

    private var currentURL: String {
        session.stringValue(for: field).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canChooseFile: Bool {
        uploadHandler != nil && !isUploading && !isEditingLocked && !field.isDisabled
    }

    private var uploadActionTitle: String {
        if isUploading {
            return String(localized: "Uploading", bundle: .module)
        }
        return currentURL.isEmpty
            ? String(localized: "Choose File", bundle: .module)
            : String(localized: "Replace File", bundle: .module)
    }

    private var uploadActionHint: String {
        if isUploading {
            return String(localized: "The file is uploading.", bundle: .module)
        }
        if uploadHandler == nil {
            return String(
                localized: "Upload unavailable because no upload handler is configured.",
                bundle: .module
            )
        }
        if isEditingLocked || field.isDisabled {
            return String(localized: "This field is not editable.", bundle: .module)
        }
        return String(localized: "Opens the file picker.", bundle: .module)
    }

    private func fileRow(urlString: String) -> some View {
        FormKitUploadRow(
            title: displayName(for: urlString),
            subtitle: urlString,
            systemImage: formKitUploadSymbolName(for: urlString),
            accent: style.accent,
            removeLabel: String(localized: "Remove file", bundle: .module),
            removeAction: canRemoveValue ? { session.clearValue(for: field) } : nil
        )
    }

    private var canRemoveValue: Bool {
        !isEditingLocked && !field.isDisabled
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        guard let uploadHandler else {
            uploadError = String(localized: "Upload unavailable.", bundle: .module)
            return
        }

        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                return
            }
            Task {
                await upload(url, using: uploadHandler)
            }
        case .failure(let error):
            uploadError = error.localizedDescription
        }
    }

    private func upload(_ url: URL, using uploadHandler: @escaping FormKitUploadHandler) async {
        isUploading = true
        defer { isUploading = false }
        let originalValue = session.primitiveValue(for: field)

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let assets = try await uploadHandler(
                FormKitUploadRequest(
                    component: .fileField,
                    pointer: field.pointer,
                    title: field.title,
                    items: [FormKitUploadItem(fileURL: url)]
                )
            )
            guard let uploadedURL = assets.first?.url.formKitNonEmpty else {
                uploadError = String(localized: "Upload did not return a URL.", bundle: .module)
                return
            }
            guard session.renderPlan.fields.contains(field),
                  session.primitiveValue(for: field) == originalValue
            else {
                uploadError = String(
                    localized: "The form changed before the file finished uploading.",
                    bundle: .module
                )
                return
            }
            session.setStringValue(uploadedURL, for: field)
            uploadError = nil
        } catch {
            uploadError = error.localizedDescription
        }
    }

    private func displayName(for urlString: String) -> String {
        URL(string: urlString)?.lastPathComponent.formKitNonEmpty ?? urlString
    }
}

#Preview("FormKit File Field") {
    let schema =
        """
        {
          "type": "object",
          "properties": {
            "license": {
              "type": "string",
              "format": "uri",
              "title": "License",
              "description": "Upload a single document.",
              "x-formkit-ui-component": "file-field"
            }
          }
        }
        """
    let session = FormKitRenderer().makeFormSession(
        schemaJSON: schema,
        instanceJSON: #"{"license":"https://example.com/license.pdf"}"#
    )
    FormKitView(
        session: session,
        options: FormKitOptions(
            uploadHandler: { request in
                [
                    FormKitUploadedAsset(
                        url: "https://example.com/uploads/\(request.items.first?.name ?? "file")"
                    )
                ]
            }
        )
    )
}
