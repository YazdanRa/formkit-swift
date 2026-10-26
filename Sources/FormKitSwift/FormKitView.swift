import SwiftUI

struct FormKitOwnedSessionConfiguration: Equatable {
    let schemaJSON: String
    let instanceJSON: String?
    let defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior
    let conditionalRenderBehaviorOverrides: [String: FormKitConditionalRenderBehavior]
    let validationBehavior: FormKitValidationBehavior

    init(
        schemaJSON: String,
        instanceJSON: String?,
        defaultConditionalRenderBehavior: FormKitConditionalRenderBehavior,
        conditionalRenderBehaviorOverrides: [String: FormKitConditionalRenderBehavior] = [:],
        validationBehavior: FormKitValidationBehavior
    ) {
        self.schemaJSON = schemaJSON
        self.instanceJSON = instanceJSON
        self.defaultConditionalRenderBehavior = defaultConditionalRenderBehavior
        self.conditionalRenderBehaviorOverrides = conditionalRenderBehaviorOverrides
        self.validationBehavior = validationBehavior
    }

    @MainActor
    func makeSession() -> FormKitSession {
        FormKitRenderer(
            defaultConditionalRenderBehavior: defaultConditionalRenderBehavior,
            conditionalRenderBehaviorOverrides: conditionalRenderBehaviorOverrides
        ).makeFormSession(
            schemaJSON: schemaJSON,
            instanceJSON: instanceJSON,
            defaultConditionalRenderBehavior: nil,
            validationBehavior: validationBehavior
        )
    }
}

public struct FormKitView: View {
    private let injectedSession: FormKitSession?
    private let externalFocusedFieldID: Binding<String?>?
    private let ownedSessionConfiguration: FormKitOwnedSessionConfiguration?
    private let options: FormKitOptions
    private let injectedPageNavigator: FormKitPageNavigator?
    @State private var ownedSession: FormKitSession?
    @State private var ownedPageNavigator = FormKitPageNavigator()
    @State private var activeOwnedSessionConfiguration: FormKitOwnedSessionConfiguration?

    /// Pass a `pageNavigator` to turn the pages of a ``FormKitFormLayout/sectionPages`` form from the
    /// host or to observe page changes; the view keeps its own otherwise.
    public init(
        session: FormKitSession,
        pageNavigator: FormKitPageNavigator? = nil,
        options: FormKitOptions = .init()
    ) {
        injectedSession = session
        externalFocusedFieldID = nil
        ownedSessionConfiguration = nil
        injectedPageNavigator = pageNavigator
        self.options = options
        _ownedSession = State(initialValue: nil)
        _activeOwnedSessionConfiguration = State(initialValue: nil)
    }

    /// Pass a `pageNavigator` to turn the pages of a ``FormKitFormLayout/sectionPages`` form from the
    /// host or to observe page changes; the view keeps its own otherwise.
    public init(
        session: FormKitSession,
        focusedFieldID: Binding<String?>,
        pageNavigator: FormKitPageNavigator? = nil,
        options: FormKitOptions = .init()
    ) {
        injectedSession = session
        externalFocusedFieldID = focusedFieldID
        ownedSessionConfiguration = nil
        injectedPageNavigator = pageNavigator
        self.options = options
        _ownedSession = State(initialValue: nil)
        _activeOwnedSessionConfiguration = State(initialValue: nil)
    }

    @MainActor
    public init(schemaJSON: String, instanceJSON: String? = nil, options: FormKitOptions = .init()) {
        let configuration = FormKitOwnedSessionConfiguration(
            schemaJSON: schemaJSON,
            instanceJSON: instanceJSON,
            defaultConditionalRenderBehavior: options.defaultConditionalRenderBehavior,
            conditionalRenderBehaviorOverrides: options.conditionalRenderBehaviorOverrides,
            validationBehavior: options.validationBehavior
        )

        injectedSession = nil
        externalFocusedFieldID = nil
        ownedSessionConfiguration = configuration
        injectedPageNavigator = nil
        self.options = options
        _ownedSession = State(initialValue: configuration.makeSession())
        _activeOwnedSessionConfiguration = State(initialValue: configuration)
    }

    public var body: some View {
        if let session = injectedSession {
            FormKitContainerView(
                session: session,
                externalFocusedFieldID: externalFocusedFieldID,
                options: options,
                pageNavigator: injectedPageNavigator ?? ownedPageNavigator
            )
        } else if let session = ownedSession {
            FormKitContainerView(
                session: session,
                externalFocusedFieldID: nil,
                options: options,
                pageNavigator: ownedPageNavigator
            )
                .onChange(of: ownedSessionConfiguration) { _, newConfiguration in
                    guard let newConfiguration,
                          activeOwnedSessionConfiguration != newConfiguration
                    else {
                        return
                    }

                    ownedSession = newConfiguration.makeSession()
                    activeOwnedSessionConfiguration = newConfiguration
                }
        }
    }
}
