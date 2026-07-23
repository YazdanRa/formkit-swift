import Foundation

public typealias FormKitUploadHandler = @MainActor (FormKitUploadRequest) async throws -> [FormKitUploadedAsset]

public struct FormKitUploadRequest: Sendable {
    public let component: FormKitUIComponent
    public let pointer: String
    public let title: String
    public let items: [FormKitUploadItem]

    public init(
        component: FormKitUIComponent,
        pointer: String,
        title: String,
        items: [FormKitUploadItem]
    ) {
        self.component = component
        self.pointer = pointer
        self.title = title
        self.items = items
    }
}

public struct FormKitUploadItem: Sendable {
    public enum Source: Sendable {
        case fileURL(URL)
        case data(Data)
    }

    public let source: Source
    public let name: String?
    public let mimeType: String?
    public let size: Int?

    public init(
        source: Source,
        name: String? = nil,
        mimeType: String? = nil,
        size: Int? = nil
    ) {
        self.source = source
        self.name = name
        self.mimeType = mimeType
        self.size = size
    }
}

public struct FormKitUploadedAsset: Sendable, Equatable {
    public let url: String
    public let name: String?
    public let mimeType: String?
    public let size: Int?
    public let id: String?

    public init(
        url: String,
        name: String? = nil,
        mimeType: String? = nil,
        size: Int? = nil,
        id: String? = nil
    ) {
        self.url = url
        self.name = name
        self.mimeType = mimeType
        self.size = size
        self.id = id
    }
}

extension FormKitUploadItem {
    init(fileURL: URL) {
        self.init(
            source: .fileURL(fileURL),
            name: fileURL.lastPathComponent
        )
    }
}

extension String {
    var formKitNonEmpty: String? {
        isEmpty ? nil : self
    }
}
