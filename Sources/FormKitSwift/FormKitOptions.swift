import SwiftUI

public struct FormKitOptions {
    public var mode: FormKitMode
    public var validationBehavior: FormKitValidationBehavior
    public var defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior
    public var style: FormKitStyle
    public var labels: FormKitLabels
    public var fieldState: @MainActor (FormKitFieldDescriptor) -> FormKitFieldVisualState
    public var components: FormKitComponents

    public init(
        mode: FormKitMode = .editable,
        validationBehavior: FormKitValidationBehavior = .revalidateAfterFirstAttempt,
        defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior = .hide,
        style: FormKitStyle = .init(),
        labels: FormKitLabels = .init(),
        fieldState: @escaping @MainActor (FormKitFieldDescriptor) -> FormKitFieldVisualState = { _ in .normal },
        components: FormKitComponents = .init()
    ) {
        self.mode = mode
        self.validationBehavior = validationBehavior
        self.defaultConditionalRenderBehavior = defaultConditionalRenderBehavior
        self.style = style
        self.labels = labels
        self.fieldState = fieldState
        self.components = components
    }
}

public enum FormKitMode: Equatable, Sendable {
    case editable
    case readOnly
}

public enum FormKitFieldVisualState: Equatable, Sendable {
    case normal
    case changed
    case locked
}

public struct FormKitStyle: Equatable, Sendable {
    public var accent: Color
    public var destructive: Color
    public var success: Color
    public var secondaryText: Color
    public var fieldBackground: Color
    public var cornerRadius: CGFloat
    public var fieldSpacing: CGFloat

    public init(
        accent: Color = .accentColor,
        destructive: Color = .red,
        success: Color = .green,
        secondaryText: Color = .secondary,
        fieldBackground: Color = Color.gray.opacity(0.12),
        cornerRadius: CGFloat = 8,
        fieldSpacing: CGFloat = 8
    ) {
        self.accent = accent
        self.destructive = destructive
        self.success = success
        self.secondaryText = secondaryText
        self.fieldBackground = fieldBackground
        self.cornerRadius = cornerRadius
        self.fieldSpacing = fieldSpacing
    }
}

public struct FormKitLabels: Equatable, Sendable {
    public var valueState: String
    public var value: String
    public var noValue: String
    public var notSet: String
    public var noItems: String
    public var addItemPrefix: String
    public var remove: String
    public var minimumItemsPrefix: String
    public var maximumItemsPrefix: String

    public init(
        valueState: String = "Value State",
        value: String = "Value",
        noValue: String = "No Value",
        notSet: String = "Not Set",
        noItems: String = "No items added yet.",
        addItemPrefix: String = "Add",
        remove: String = "Remove",
        minimumItemsPrefix: String = "Minimum items:",
        maximumItemsPrefix: String = "Maximum items:"
    ) {
        self.valueState = valueState
        self.value = value
        self.noValue = noValue
        self.notSet = notSet
        self.noItems = noItems
        self.addItemPrefix = addItemPrefix
        self.remove = remove
        self.minimumItemsPrefix = minimumItemsPrefix
        self.maximumItemsPrefix = maximumItemsPrefix
    }
}

public struct FormKitComponents {
    public var field: (@MainActor (FormKitFieldComponentContext) -> AnyView)?
    public var sectionHeader: (@MainActor (FormKitSectionComponentContext) -> AnyView)?

    public init(
        field: (@MainActor (FormKitFieldComponentContext) -> AnyView)? = nil,
        sectionHeader: (@MainActor (FormKitSectionComponentContext) -> AnyView)? = nil
    ) {
        self.field = field
        self.sectionHeader = sectionHeader
    }
}

public struct FormKitFieldComponentContext {
    public let session: FormKitSession
    public let field: FormKitFieldDescriptor
    public let errors: [String]
    public let state: FormKitFieldVisualState
    public let isEditingLocked: Bool
}

public struct FormKitSectionComponentContext {
    public let section: FormKitRenderPlan.SectionDescriptor
}
