public struct FormKitToolContext: Equatable, Sendable {
    public let revision: Int
    public let title: String
    public let summary: String
    public let fields: [FormKitToolField]
    public let currentValues: [String: FormKitJSONValue]

    public init(
        revision: Int,
        title: String,
        summary: String,
        fields: [FormKitToolField],
        currentValues: [String: FormKitJSONValue]
    ) {
        self.revision = revision
        self.title = title
        self.summary = summary
        self.fields = fields
        self.currentValues = currentValues
    }
}

public enum FormKitToolValueSource: Equatable, Sendable {
    /// The value was present in the instance used to create the session.
    case initialInstance

    /// The renderer supplied the value from the schema or a required-control fallback.
    case defaultValue

    /// The value was set or confirmed after the session was created.
    case sessionEdit
}

public struct FormKitToolField: Equatable, Sendable {
    public let pointer: String
    public let title: String
    public let type: String
    public let isRequired: Bool
    public let valueSource: FormKitToolValueSource?
    public let description: String?
    public let enumOptions: [String]
    public let isLocked: Bool
    public let validationMessages: [String]

    public init(
        pointer: String,
        title: String,
        type: String,
        isRequired: Bool,
        valueSource: FormKitToolValueSource? = nil,
        description: String? = nil,
        enumOptions: [String] = [],
        isLocked: Bool = false,
        validationMessages: [String] = []
    ) {
        self.pointer = pointer
        self.title = title
        self.type = type
        self.isRequired = isRequired
        self.valueSource = valueSource
        self.description = description
        self.enumOptions = enumOptions
        self.isLocked = isLocked
        self.validationMessages = validationMessages
    }
}

public struct FormKitToolEdit: Equatable, Sendable {
    public enum Operation: String, Equatable, Sendable {
        case set
        case clear
    }

    public let pointer: String
    public let operation: Operation
    public let value: FormKitJSONValue?

    public init(pointer: String, operation: Operation, value: FormKitJSONValue? = nil) {
        self.pointer = pointer
        self.operation = operation
        self.value = value
    }
}

public struct FormKitToolEditResult: Equatable, Sendable {
    public let revision: Int
    public let summary: String?
    public let appliedEdits: [FormKitToolEdit]
    public let rejectedEdits: [FormKitRejectedEdit]
    public let validationMessages: [String]
    public let context: FormKitToolContext

    public init(
        revision: Int,
        summary: String? = nil,
        appliedEdits: [FormKitToolEdit],
        rejectedEdits: [FormKitRejectedEdit] = [],
        validationMessages: [String] = [],
        context: FormKitToolContext
    ) {
        self.revision = revision
        self.summary = summary
        self.appliedEdits = appliedEdits
        self.rejectedEdits = rejectedEdits
        self.validationMessages = validationMessages
        self.context = context
    }
}

public struct FormKitRejectedEdit: Equatable, Sendable {
    public let pointer: String
    public let reason: String
    public let message: String

    public init(pointer: String, reason: String, message: String) {
        self.pointer = pointer
        self.reason = reason
        self.message = message
    }
}
