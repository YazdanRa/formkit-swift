import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct FormKitSignaturePad: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Bindable var session: FormKitSession
    let field: FormKitFieldDescriptor
    let isEditingLocked: Bool
    let style: FormKitStyle
    let uploadHandler: FormKitUploadHandler?
    @State private var strokes: [FormKitSignatureStroke] = []
    @State private var activeStroke = FormKitSignatureStroke(points: [])
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
        VStack(alignment: .leading, spacing: 12) {
            if !currentURL.isEmpty {
                existingSignatureRow
            }

            signatureCanvas

            VStack(spacing: 2) {
                Button {
                    clearDraft()
                } label: {
                    FormKitUploadActionRow(
                        title: String(localized: "Clear Draft", bundle: .module),
                        systemImage: "eraser",
                        tint: canClearDraft ? style.destructive : style.secondaryText
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canClearDraft)

                Button {
                    Task {
                        await uploadSignature()
                    }
                } label: {
                    FormKitUploadActionRow(
                        title: isUploading
                            ? String(localized: "Saving", bundle: .module)
                            : String(localized: "Save Signature", bundle: .module),
                        systemImage: "signature",
                        tint: canUploadSignature ? style.accent : style.secondaryText,
                        isBusy: isUploading
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canUploadSignature)
                .accessibilityHint(saveSignatureHint)
            }

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
    }

    private var currentURL: String {
        session.stringValue(for: field).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canUploadSignature: Bool {
        uploadHandler != nil
            && !strokes.isEmpty
            && !isUploading
            && !isEditingLocked
            && !field.isDisabled
    }

    private var canClearDraft: Bool {
        !strokes.isEmpty && !isUploading && !isEditingLocked && !field.isDisabled
    }

    private var saveSignatureHint: String {
        if uploadHandler == nil {
            return String(localized: "Upload unavailable because no upload handler is configured.", bundle: .module)
        }
        if strokes.isEmpty {
            return String(localized: "Draw a signature before saving.", bundle: .module)
        }
        if isUploading {
            return String(localized: "Signature is saving.", bundle: .module)
        }
        if isEditingLocked || field.isDisabled {
            return String(localized: "This field is not editable.", bundle: .module)
        }
        return String(localized: "Uploads the drawn signature and stores the returned URL.", bundle: .module)
    }

    private var signatureAccessibilityValue: String {
        if !strokes.isEmpty {
            return String(localized: "Unsaved signature drawing", bundle: .module)
        }
        if !currentURL.isEmpty {
            return String(localized: "Saved signature", bundle: .module)
        }
        return String(localized: "Empty", bundle: .module)
    }

    private var existingSignatureRow: some View {
        FormKitUploadRow(
            title: String(localized: "Saved signature", bundle: .module),
            subtitle: currentURL,
            systemImage: "signature",
            accent: style.accent,
            removeLabel: String(localized: "Remove signature", bundle: .module),
            removeAction: canRemoveValue ? { session.clearValue(for: field) } : nil
        )
    }

    private var signatureCanvas: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.background)
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(.separator.opacity(0.55))
                        .frame(height: 1)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 34)
                }
                if strokes.isEmpty && activeStroke.points.isEmpty {
                    Text("Sign here", bundle: .module)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                FormKitSignatureCanvas(strokes: strokes + [activeStroke])
                    .padding(12)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard uploadHandler != nil, !isUploading, !isEditingLocked, !field.isDisabled else {
                            return
                        }
                        activeStroke.points.append(normalizedPoint(value.location, in: geometry.size))
                    }
                    .onEnded { _ in
                        guard activeStroke.points.count > 1 else {
                            activeStroke = FormKitSignatureStroke(points: [])
                            return
                        }
                        strokes.append(activeStroke)
                        activeStroke = FormKitSignatureStroke(points: [])
                    }
            )
        }
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 230 : 190)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.separator.opacity(0.7), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Signature drawing area", bundle: .module))
        .accessibilityValue(signatureAccessibilityValue)
        .accessibilityHint(String(localized: "Draw a signature, then save it.", bundle: .module))
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    private func normalizedPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let drawableSize = CGSize(width: max(size.width - 24, 1), height: max(size.height - 24, 1))
        return CGPoint(
            x: min(max((point.x - 12) / drawableSize.width, 0), 1),
            y: min(max((point.y - 12) / drawableSize.height, 0), 1)
        )
    }

    private var canRemoveValue: Bool {
        !isEditingLocked && !field.isDisabled
    }

    private func clearDraft() {
        strokes = []
        activeStroke = FormKitSignatureStroke(points: [])
        uploadError = nil
    }

    private func uploadSignature() async {
        guard let uploadHandler else {
            uploadError = String(localized: "Upload unavailable.", bundle: .module)
            return
        }

        isUploading = true
        defer { isUploading = false }
        let originalValue = session.primitiveValue(for: field)

        guard let pngData = pngData() else {
            uploadError = String(localized: "Signature image could not be created.", bundle: .module)
            return
        }

        do {
            let assets = try await uploadHandler(
                FormKitUploadRequest(
                    component: .signaturePad,
                    pointer: field.pointer,
                    title: field.title,
                    items: [
                        FormKitUploadItem(
                            source: .data(pngData),
                            name: "\(field.propertyKey)-signature.png",
                            mimeType: "image/png",
                            size: pngData.count
                        )
                    ]
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
                    localized: "The form changed before the signature finished saving.",
                    bundle: .module
                )
                return
            }
            session.setStringValue(uploadedURL, for: field)
            clearDraft()
        } catch {
            uploadError = error.localizedDescription
        }
    }

    private func pngData() -> Data? {
        let renderer = ImageRenderer(
            content: FormKitSignatureCanvas(strokes: strokes)
                .frame(width: 640, height: 240)
                .background(Color.white)
        )
        renderer.scale = 2

        #if canImport(UIKit)
        return renderer.uiImage?.pngData()
        #elseif canImport(AppKit)
        guard let tiffData = renderer.nsImage?.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
        #else
        return nil
        #endif
    }
}

private struct FormKitSignatureStroke: Equatable {
    var points: [CGPoint]
}

private struct FormKitSignatureCanvas: View {
    let strokes: [FormKitSignatureStroke]

    var body: some View {
        Canvas { context, size in
            for stroke in strokes where stroke.points.count > 1 {
                var path = Path()
                path.move(to: scaledPoint(stroke.points[0], in: size))
                for point in stroke.points.dropFirst() {
                    path.addLine(to: scaledPoint(point, in: size))
                }
                context.stroke(path, with: .color(.primary), lineWidth: 3)
            }
        }
    }

    private func scaledPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
}

#Preview("FormKit Signature Pad") {
    let schema =
        """
        {
          "type": "object",
          "properties": {
            "signature": {
              "type": "string",
              "format": "uri",
              "title": "Signature",
              "description": "Draw and save a signature.",
              "x-formkit-ui-component": "signature-pad"
            }
          }
        }
        """
    let session = FormKitRenderer().makeFormSession(
        schemaJSON: schema,
        instanceJSON: #"{"signature":"https://example.com/signatures/current.png"}"#
    )
    FormKitView(
        session: session,
        options: FormKitOptions(
            uploadHandler: { _ in
                [FormKitUploadedAsset(url: "https://example.com/signatures/generated.png")]
            }
        )
    )
}
