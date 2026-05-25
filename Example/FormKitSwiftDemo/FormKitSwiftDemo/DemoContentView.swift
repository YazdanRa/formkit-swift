import FormKitSwift
import SwiftUI

struct DemoContentView: View {
    private enum DemoTab: String, CaseIterable, Identifiable {
        case editable = "Editable"
        case readOnly = "Read Only"
        case styled = "Styled"
        case json = "JSON"

        var id: String { rawValue }
    }

    @State private var editableSession: FormKitSession
    @State private var readOnlySession: FormKitSession
    @State private var selectedTab: DemoTab = .editable
    @State private var changedPointers: Set<String> = []
    @State private var lockedPointers: Set<String> = ["/inspector"]
    @State private var toolMessage = "No tool edits applied."

    init() {
        let renderer = FormKitRenderer()
        _editableSession = State(
            initialValue: renderer.makeFormSession(
                schemaJSON: DemoSchemas.inspectionSchema,
                instanceJSON: DemoSchemas.inspectionInstance
            )
        )
        _readOnlySession = State(
            initialValue: renderer.makeFormSession(
                schemaJSON: DemoSchemas.inspectionSchema,
                instanceJSON: DemoSchemas.inspectionInstance
            )
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $selectedTab) {
                    ForEach(DemoTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                Group {
                    switch selectedTab {
                    case .editable:
                        editableForm
                    case .readOnly:
                        FormKitView(
                            session: readOnlySession,
                            options: FormKitOptions(mode: .readOnly)
                        )
                    case .styled:
                        styledForm
                    case .json:
                        jsonPreview
                    }
                }
            }
            .navigationTitle("FormKitSwift")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Validate") {
                        _ = editableSession.validate()
                    }

                    Button("Tool Edit") {
                        applyToolEdit()
                    }
                }
            }
        }
    }

    private var editableForm: some View {
        FormKitView(
            session: editableSession,
            options: FormKitOptions(
                fieldState: fieldState
            )
        )
    }

    private var styledForm: some View {
        VStack(spacing: 0) {
            Text(toolMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.teal.opacity(0.08))

            FormKitView(
                session: editableSession,
                options: FormKitOptions(
                    style: FormKitStyle(
                        accent: .teal,
                        destructive: .pink,
                        success: .mint,
                        fieldBackground: Color.teal.opacity(0.08),
                        cornerRadius: 8,
                        fieldSpacing: 10
                    ),
                    fieldState: fieldState,
                    components: FormKitComponents(
                        sectionHeader: { context in
                            AnyView(
                                Text(context.section.title.uppercased())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.teal)
                            )
                        }
                    )
                )
            )
        }
    }

    private var jsonPreview: some View {
        ScrollView {
            Text(editableSession.currentInstanceJSON)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func applyToolEdit() {
        let result = editableSession.applyToolEdits(
            [
                FormKitToolEdit(
                    pointer: "/status",
                    operation: .set,
                    value: .string("Needs Review")
                ),
                FormKitToolEdit(
                    pointer: "/follow_up_notes",
                    operation: .set,
                    value: .string("Generated from the generic tool API.")
                ),
                FormKitToolEdit(
                    pointer: "/inspector",
                    operation: .set,
                    value: .string("Locked")
                )
            ],
            baseRevision: editableSession.revision,
            lockedPointers: lockedPointers
        )

        changedPointers = Set(result.appliedEdits.map(\.pointer))
        toolMessage = "Applied \(result.appliedEdits.count), rejected \(result.rejectedEdits.count)."
    }

    private func fieldState(for field: FormKitFieldDescriptor) -> FormKitFieldVisualState {
        let pointer = publicPointer(field.pointer)
        if lockedPointers.contains(pointer) {
            return .locked
        }
        if changedPointers.contains(pointer) {
            return .changed
        }
        return .normal
    }

    private func publicPointer(_ pointer: String) -> String {
        pointer.hasPrefix("#") ? String(pointer.dropFirst()) : pointer
    }
}
