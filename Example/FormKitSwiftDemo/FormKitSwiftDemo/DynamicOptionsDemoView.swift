import FormKitSwift
import SwiftUI

struct DynamicOptionsDemoView: View {
    @State private var contactSelection: String? = "contact-saved"
    @State private var equipment: [String] = []
    @State private var isLocked = false
    @State private var catalogScope = 0
    @State private var oldScopeReturned = false
    @State private var cachedContactOptions: [FormKitDynamicOption] = []
    @State private var registrySession: FormKitSession

    private let contacts = [
        FormKitDynamicOption(id: "contact-101", label: "Alex Morgan", detail: "Northline Engineering"),
        FormKitDynamicOption(id: "contact-102", label: "Alex Morgan", detail: "City Mechanical"),
        FormKitDynamicOption(id: "contact-103", label: "Jamie Patel", detail: "Contact #103")
    ]
    private let equipmentOptions = [
        FormKitDynamicOption(id: "equipment:excavator", label: "Excavator"),
        FormKitDynamicOption(id: "equipment:loader", label: "Loader"),
        FormKitDynamicOption(id: "equipment:crane", label: "Crane")
    ]

    init() {
        let instance = ProcessInfo.processInfo.arguments.contains("-DYNAMIC_HYDRATE_ON_LOAD")
            ? #"{"request":{"contact":"saved-opaque-contact"}}"# : nil
        _registrySession = State(initialValue: FormKitRenderer().makeFormSession(
            schemaJSON: Self.registrySchema, instanceJSON: instance
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if ProcessInfo.processInfo.arguments.contains("-DYNAMIC_REGISTRY") {
                    registryForm
                } else {
                    standaloneForm
                }
            }
            .navigationTitle("Dynamic options")
        }
    }

    private var standaloneForm: some View {
        Form {
            Section("Contact") {
                FormKitDynamicOptionsPicker(
                    title: "Contact",
                    selection: .single($contactSelection),
                    savedOptions: [.init(id: "contact-saved", label: "Saved contact")],
                    isEditingLocked: isLocked,
                    provider: { [scope = catalogScope] search, cursor in
                        try await contactPage(scope: scope, search: search, cursor: cursor)
                    }
                )
                .id(catalogScope)
                .accessibilityIdentifier("demo_contact_picker")
            }
            Section("Equipment") {
                FormKitDynamicOptionsPicker(
                    title: "Equipment",
                    selection: .multiple($equipment),
                    isRequired: ProcessInfo.processInfo.arguments.contains("-DYNAMIC_REQUIRED"),
                    maximumSelectionCount: ProcessInfo.processInfo.arguments.contains("-DYNAMIC_LIMIT_TWO")
                        ? 2 : nil,
                    isEditingLocked: isLocked,
                    provider: { search, cursor in try await page(equipmentOptions, search: search, cursor: cursor) }
                )
                .accessibilityIdentifier("demo_equipment_picker")
            }
            Section("Saved identifiers") {
                if ProcessInfo.processInfo.arguments.contains("-DYNAMIC_SCOPE_CHANGE") {
                    Text(verbatim: "\(catalogScope):\(oldScopeReturned)")
                        .accessibilityIdentifier("demo_catalog_scope")
                }
                Text(contactSelection ?? "none").accessibilityIdentifier("demo_contact_value")
                Text(equipment.joined(separator: ",")).accessibilityIdentifier("demo_equipment_value")
            }
        }
    }

    private var registryForm: some View {
        VStack {
            FormKitView(
                session: registrySession,
                options: FormKitOptions(dynamicOptions: { [saved = cachedContactOptions] context in
                    registrySource(context, savedOptions: saved)
                })
            )
            Text(registrySession.currentInstanceJSON)
                .font(.caption.monospaced())
                .accessibilityIdentifier("demo_dynamic_json")
                .padding()
        }
    }

    private func registrySource(
        _ context: FormKitDynamicOptionsContext,
        savedOptions: [FormKitDynamicOption]
    ) -> FormKitDynamicOptionsSource? {
        switch context.pointer {
        case "#/request/contact":
            FormKitDynamicOptionsSource(savedOptions: savedOptions, provider: { search, cursor in
                try await registryContactPage(search: search, cursor: cursor)
            })
        case "#/assets/equipment":
            FormKitDynamicOptionsSource(provider: { search, cursor in
                try await page(equipmentOptions, search: search, cursor: cursor)
            })
        default: nil
        }
    }

    private func registryContactPage(search: String, cursor: String?) async throws -> FormKitDynamicOptionsPage {
        if ProcessInfo.processInfo.arguments.contains("-DYNAMIC_HYDRATE_ON_LOAD"), cachedContactOptions.isEmpty {
            await Task.yield()
            cachedContactOptions = [.init(id: "saved-opaque-contact", label: "Hydrated contact", detail: "New company")]
        }
        return try await page(contacts, search: search, cursor: cursor)
    }

    private func contactPage(scope: Int, search: String, cursor: String?) async throws -> FormKitDynamicOptionsPage {
        guard ProcessInfo.processInfo.arguments.contains("-DYNAMIC_SCOPE_CHANGE") else {
            return try await page(contacts, search: search, cursor: cursor)
        }
        if scope == 0 {
            catalogScope = 1
            // Model an old provider that completes even after the host remount cancels its task.
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { continuation.resume() }
            }
            oldScopeReturned = true
            return .init(options: [.init(id: "old-scope-option", label: "Old scope option")])
        }
        return .init(options: [.init(id: "new-scope-option", label: "New scope option")])
    }

    private func page(
        _ options: [FormKitDynamicOption],
        search: String,
        cursor: String?
    ) async throws -> FormKitDynamicOptionsPage {
        await Task.yield()
        if ProcessInfo.processInfo.arguments.contains("-DYNAMIC_LOCK_ON_LOAD") {
            isLocked = true
        }
        if ProcessInfo.processInfo.arguments.contains("-DYNAMIC_LOOKUP_FAILS") {
            throw DemoLookupError.unavailable
        }
        let matches = options.filter { search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) }
        let offset = Int(cursor ?? "") ?? 0
        let end = min(offset + 2, matches.count)
        return FormKitDynamicOptionsPage(
            options: Array(matches.dropFirst(offset).prefix(2)),
            nextCursor: end < matches.count ? String(end) : nil
        )
    }

    private enum DemoLookupError: Error {
        case unavailable
    }

    private static let registrySchema = #"""
    {
      "type":"object", "x-formkit-layout":"section-pages",
      "properties":{
        "request":{"type":"object","title":"Request","x-formkit-order":0,"properties":{
          "contact":{"type":["string","null"],"title":"Contact","x-formkit-ui-component":"dynamic-options"}
        }},
        "assets":{"type":"object","title":"Assets","x-formkit-order":1,"properties":{
          "equipment":{"type":"array","title":"Equipment","maxItems":2,"uniqueItems":true,
            "items":{"type":"string"},"x-formkit-ui-component":"dynamic-options"}
        }}
      }
    }
    """#
}
