#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

public struct FormKitOptions {
    public var mode: FormKitMode
    public var validationBehavior: FormKitValidationBehavior
    public var defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior
    public var conditionalRenderBehaviorOverrides: [String: FormKitConditionalRenderBehavior]
    public var style: FormKitStyle
    public var labels: FormKitLabels
    public var fieldState: @MainActor (FormKitFieldDescriptor) -> FormKitFieldVisualState
    public var components: FormKitComponents
    public var uploadHandler: FormKitUploadHandler?

    public init(
        mode: FormKitMode = .editable,
        validationBehavior: FormKitValidationBehavior = .revalidateAfterFirstAttempt,
        defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior = .hide,
        conditionalRenderBehaviorOverrides: [String: FormKitConditionalRenderBehavior] = [:],
        style: FormKitStyle = .init(),
        labels: FormKitLabels = .init(),
        fieldState: @escaping @MainActor (FormKitFieldDescriptor) -> FormKitFieldVisualState = { _ in .normal },
        components: FormKitComponents = .init(),
        uploadHandler: FormKitUploadHandler? = nil
    ) {
        self.mode = mode
        self.validationBehavior = validationBehavior
        self.defaultConditionalRenderBehavior = defaultConditionalRenderBehavior
        self.conditionalRenderBehaviorOverrides = conditionalRenderBehaviorOverrides
        self.style = style
        self.labels = labels
        self.fieldState = fieldState
        self.components = components
        self.uploadHandler = uploadHandler
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
    public static var defaultFieldBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    public var accent: Color
    public var destructive: Color
    public var success: Color
    public var secondaryText: Color
    public var fieldBackground: Color
    public var disabledFieldBackground: Color
    public var cornerRadius: CGFloat
    public var fieldSpacing: CGFloat

    public init(
        accent: Color = .accentColor,
        destructive: Color = .red,
        success: Color = .green,
        secondaryText: Color = .secondary,
        fieldBackground: Color = FormKitStyle.defaultFieldBackground,
        disabledFieldBackground: Color = Color.gray.opacity(0.1),
        cornerRadius: CGFloat = 8,
        fieldSpacing: CGFloat = 8
    ) {
        self.accent = accent
        self.destructive = destructive
        self.success = success
        self.secondaryText = secondaryText
        self.fieldBackground = fieldBackground
        self.disabledFieldBackground = disabledFieldBackground
        self.cornerRadius = cornerRadius
        self.fieldSpacing = fieldSpacing
    }
}

public struct FormKitLabels: Equatable, Sendable {
    public static let localizedDefaults = FormKitLabels(
        valueState: String(localized: "Value State", bundle: .module),
        value: String(localized: "Value", bundle: .module),
        noValue: String(localized: "No Value", bundle: .module),
        notSet: String(localized: "Not Set", bundle: .module),
        noItems: String(localized: "No items added yet.", bundle: .module),
        addItemPrefix: String(localized: "Add", bundle: .module),
        remove: String(localized: "Remove", bundle: .module),
        minimumItemsPrefix: String(localized: "Minimum items:", bundle: .module),
        maximumItemsPrefix: String(localized: "Maximum items:", bundle: .module)
    )

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
        valueState: String = FormKitLabels.localizedDefaults.valueState,
        value: String = FormKitLabels.localizedDefaults.value,
        noValue: String = FormKitLabels.localizedDefaults.noValue,
        notSet: String = FormKitLabels.localizedDefaults.notSet,
        noItems: String = FormKitLabels.localizedDefaults.noItems,
        addItemPrefix: String = FormKitLabels.localizedDefaults.addItemPrefix,
        remove: String = FormKitLabels.localizedDefaults.remove,
        minimumItemsPrefix: String = FormKitLabels.localizedDefaults.minimumItemsPrefix,
        maximumItemsPrefix: String = FormKitLabels.localizedDefaults.maximumItemsPrefix
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
    public var fieldInput: (@MainActor (FormKitFieldComponentContext) -> AnyView?)?
    public var arraySection: (@MainActor (FormKitArraySectionComponentContext) -> AnyView?)?
    public var sectionHeader: (@MainActor (FormKitSectionComponentContext) -> AnyView)?

    public init(
        field: (@MainActor (FormKitFieldComponentContext) -> AnyView)? = nil,
        fieldInput: (@MainActor (FormKitFieldComponentContext) -> AnyView?)? = nil,
        arraySection: (@MainActor (FormKitArraySectionComponentContext) -> AnyView?)? = nil,
        sectionHeader: (@MainActor (FormKitSectionComponentContext) -> AnyView)? = nil
    ) {
        self.field = field
        self.fieldInput = fieldInput
        self.arraySection = arraySection
        self.sectionHeader = sectionHeader
    }
}

public struct FormKitFieldComponentContext {
    public let session: FormKitSession
    public let field: FormKitFieldDescriptor
    public let errors: [String]
    public let state: FormKitFieldVisualState
    public let isEditingLocked: Bool
    public let style: FormKitStyle
    public let uploadHandler: FormKitUploadHandler?
}

public struct FormKitArraySectionComponentContext {
    public let session: FormKitSession
    public let section: FormKitRenderPlan.SectionDescriptor
    public let descriptor: FormKitArraySectionDescriptor
    public let errors: [String]
    public let isEditingLocked: Bool
    public let style: FormKitStyle
    public let labels: FormKitLabels
    public let uploadHandler: FormKitUploadHandler?
}

public struct FormKitSectionComponentContext {
    public let section: FormKitRenderPlan.SectionDescriptor
}
