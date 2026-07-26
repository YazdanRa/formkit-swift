import SwiftUI

struct FormKitUploadRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let subtitle: String?
    let systemImage: String
    let accent: Color
    let removeLabel: String
    let removeAction: (() -> Void)?

    var body: some View {
        HStack(
            alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center,
            spacing: FormKitUploadMetrics.rowSpacing
        ) {
            FormKitUploadIcon(systemImage: systemImage, tint: accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if let removeAction {
                Button(role: .destructive, action: removeAction) {
                    Image(systemName: "minus.circle.fill")
                        .font(.body)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.red)
                        .accessibilityLabel(removeLabel)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .padding(.top, dynamicTypeSize.isAccessibilitySize ? -6 : -5)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: removeAction == nil ? .combine : .contain)
    }
}

struct FormKitUploadEmptyState: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(
            alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center,
            spacing: FormKitUploadMetrics.rowSpacing
        ) {
            FormKitUploadIcon(systemImage: systemImage, tint: .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct FormKitUploadActionRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    var isBusy = false

    var body: some View {
        HStack(spacing: FormKitUploadMetrics.rowSpacing) {
            ZStack {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.body)
                        .imageScale(.medium)
                }
            }
            .foregroundStyle(tint)
            .frame(width: FormKitUploadMetrics.iconSize, height: FormKitUploadMetrics.iconSize)

            Text(title)
                .font(.body)
                .foregroundStyle(tint)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct FormKitUploadStatusText: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let message: String
    let color: Color
    let systemImage: String

    var body: some View {
        HStack(
            alignment: dynamicTypeSize.isAccessibilitySize ? .top : .firstTextBaseline,
            spacing: FormKitUploadMetrics.rowSpacing
        ) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.medium))
                .imageScale(.medium)
                .foregroundStyle(color)
                .frame(width: FormKitUploadMetrics.iconSize)

            Text(message)
                .font(.footnote)
                .foregroundStyle(color)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

enum FormKitUploadMetrics {
    static let iconSize: CGFloat = 34
    static let rowSpacing: CGFloat = 12
}

struct FormKitUploadIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.callout.weight(.semibold))
            .imageScale(.medium)
            .foregroundStyle(tint)
            .frame(width: FormKitUploadMetrics.iconSize, height: FormKitUploadMetrics.iconSize)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

func formKitUploadSymbolName(for urlString: String) -> String {
    let pathExtension = URL(string: urlString)?.pathExtension.lowercased()
        ?? URL(fileURLWithPath: urlString).pathExtension.lowercased()

    switch pathExtension {
    case "pdf":
        return "doc.richtext.fill"
    case "png", "jpg", "jpeg", "heic", "gif", "tiff", "webp":
        return "photo.fill"
    case "zip", "gz", "tar", "rar", "7z":
        return "archivebox.fill"
    case "txt", "md", "rtf":
        return "doc.text.fill"
    case "csv", "xls", "xlsx", "numbers":
        return "tablecells.fill"
    default:
        return "doc.fill"
    }
}
