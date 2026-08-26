import Foundation

public struct FormKitRenderPlan: Sendable, Equatable {
    public struct SectionDescriptor: Identifiable, Sendable, Equatable {
        public let id: String
        public let pointer: String
        public let parentPointer: String?
        public let propertyKey: String?
        public let title: String
        public let description: String?
        public let depth: Int
        public let isRequired: Bool
        public let order: Int
        public let fieldIDs: [String]
        public let propertyOrder: [String]
        public let ownerArrayRowID: String?
        public let uiComponent: FormKitUIComponent?
        public let renderBehavior: FormKitConditionalRenderBehavior
        public let conditionalState: FormKitConditionalRenderState
        public let arrayDescriptor: FormKitArraySectionDescriptor?

        public var isOwnedByArrayRow: Bool {
            ownerArrayRowID != nil
        }

        public var isArraySection: Bool {
            arrayDescriptor != nil
        }

        public var isConditionallyInactive: Bool {
            conditionalState == .inactive
        }

        public var isDisabled: Bool {
            isConditionallyInactive && renderBehavior == .disable
        }

        public var isVisible: Bool {
            conditionalState == .active || renderBehavior != .hide
        }

        public var shouldSerialize: Bool {
            conditionalState == .active || renderBehavior == .ignore
        }
    }

    public let title: String
    public let description: String?
    public let sections: [SectionDescriptor]
    public let fields: [FormKitFieldDescriptor]
    public let fieldOrder: [String]
    public let unsupportedReasons: [FormKitUnsupportedReason]

    public var isSupported: Bool {
        unsupportedReasons.isEmpty
    }
}

public enum FormKitConditionalRenderBehavior: String, Sendable, Equatable, Codable {
    case hide
    case disable
    case ignore
}

public enum FormKitConditionalRenderState: String, Sendable, Equatable {
    case active
    case inactive
}

public struct FormKitArraySectionDescriptor: Sendable, Equatable {
    public enum ItemKind: String, Sendable, Equatable {
        case scalar
        case object
    }

    public let pointer: String
    public let propertyKey: String?
    public let itemKind: ItemKind
    public let itemScalarType: FormKitFieldDescriptor.ScalarType?
    public let itemHasValueConstraint: Bool
    public let itemTitle: String
    public let minItems: Int
    public let maxItems: Int?
    public let materializeWhenEmpty: Bool
    public let newItemPlaceholder: FormKitJSONValue
    public let rows: [FormKitArrayRowDescriptor]
}

public struct FormKitArrayRowDescriptor: Identifiable, Sendable, Equatable {
    public let id: String
    public let pointer: String
    public let index: Int
    public let title: String
    public let placeholderValue: FormKitJSONValue
    public let fieldIDs: [String]
    public let sectionIDs: [String]
}

public struct FormKitFieldDescriptor: Identifiable, Sendable, Equatable {
    public enum ScalarType: String, Sendable, Equatable {
        case string
        case email
        case uri
        case date
        case time
        case dateTime
        case integer
        case number
        case boolean
    }

    public enum PrimitiveValue: Sendable, Equatable {
        case string(String)
        case integer(Int)
        case number(Double)
        case boolean(Bool)
        case null

        var title: String {
            switch self {
            case .string(let value):
                return value
            case .integer(let value):
                return String(value)
            case .number(let value):
                return String(value)
            case .boolean(let value):
                return value ? String(localized: "On", bundle: .module) : String(localized: "Off", bundle: .module)
            case .null:
                return String(localized: "No Value", bundle: .module)
            }
        }

        var storageKey: String {
            switch self {
            case .string(let value):
                return "string:\(value)"
            case .integer(let value):
                return "integer:\(value)"
            case .number(let value):
                return "number:\(value)"
            case .boolean(let value):
                return "boolean:\(value)"
            case .null:
                return "null"
            }
        }
    }

    public struct Choice: Identifiable, Sendable, Equatable {
        public let id: String
        public let title: String
        public let value: PrimitiveValue
    }

    public let id: String
    public let pointer: String
    public let parentPointer: String
    public let propertyKey: String
    public let title: String
    public let description: String?
    public let scalarType: ScalarType
    public let enumOptions: [Choice]
    public let isRequired: Bool
    public let allowsNull: Bool
    public let defaultValue: PrimitiveValue?
    public let uiComponent: FormKitUIComponent?
    public let renderBehavior: FormKitConditionalRenderBehavior
    public let conditionalState: FormKitConditionalRenderState
    public let accessibilityIdentifier: String

    public var isEnum: Bool {
        !enumOptions.isEmpty
    }

    public var isConditionallyInactive: Bool {
        conditionalState == .inactive
    }

    public var isDisabled: Bool {
        isConditionallyInactive && renderBehavior == .disable
    }

    public var isVisible: Bool {
        conditionalState == .active || renderBehavior != .hide
    }

    public var shouldSerialize: Bool {
        conditionalState == .active || renderBehavior == .ignore
    }

    public var isInteractive: Bool {
        !isDisabled
    }
}

public enum FormKitUnsupportedReason: Sendable, Equatable {
    case invalidSchemaJSON(String)
    case invalidSchema(String)
    case unsupportedKeyword(keyword: String, location: String, message: String)
    case unsupportedType(typeDescription: String, location: String)
    case unsupportedSchemaShape(location: String, message: String)
    case unresolvedReference(String, location: String)
    case remoteReference(String, location: String)

    public var title: String {
        switch self {
        case .invalidSchemaJSON:
            return String(localized: "Invalid Schema JSON", bundle: .module)
        case .invalidSchema:
            return String(localized: "Invalid Schema", bundle: .module)
        case .unsupportedKeyword:
            return String(localized: "Unsupported Keyword", bundle: .module)
        case .unsupportedType:
            return String(localized: "Unsupported Type", bundle: .module)
        case .unsupportedSchemaShape:
            return String(localized: "Unsupported Schema Shape", bundle: .module)
        case .unresolvedReference:
            return String(localized: "Unresolved Reference", bundle: .module)
        case .remoteReference:
            return String(localized: "Remote Reference", bundle: .module)
        }
    }

    public var message: String {
        switch self {
        case .invalidSchemaJSON(let message):
            return message
        case .invalidSchema(let message):
            return message
        case .unsupportedKeyword(let keyword, let location, let message):
            return String(format: String(localized: "%@ at %@: %@", bundle: .module), keyword, location, message)
        case .unsupportedType(let typeDescription, let location):
            return String(
                format: String(localized: "Type '%@' at %@ is not supported in this renderer.", bundle: .module),
                typeDescription,
                location
            )
        case .unsupportedSchemaShape(let location, let message):
            return "\(location): \(message)"
        case .unresolvedReference(let reference, let location):
            return String(
                format: String(localized: "The local reference %@ could not be resolved from %@.", bundle: .module),
                reference,
                location
            )
        case .remoteReference(let reference, let location):
            return String(
                format: String(
                    localized: "Remote reference %@ at %@ is not supported in this renderer.",
                    bundle: .module
                ),
                reference,
                location
            )
        }
    }
}
