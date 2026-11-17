import Foundation

/// Presentation groups reference whole root properties without changing their answer pointers.
struct FormKitPageGroup: Sendable, Equatable {
    let id: String
    let title: String
    let fields: [String]

    /// Missing metadata keeps section paging; invalid metadata keeps the full scrolling form.
    static func parse(_ value: FormKitJSONValue?) -> [Self]? {
        guard let value else { return nil }
        guard let entries = value.array else { return [] }
        var groups: [Self] = []
        var ids: Set<String> = []
        var fields: Set<String> = []
        for entry in entries {
            guard let object = entry.object,
                  let id = object["id"]?.string, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let title = object["title"]?.string, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let rawFields = object["fields"]?.array,
                  ids.insert(id).inserted
            else { return [] }
            var groupFields: [String] = []
            for rawField in rawFields {
                guard let field = rawField.string,
                      !field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      fields.insert(field).inserted
                else { return [] }
                groupFields.append(field)
            }
            groups.append(Self(id: id, title: title, fields: groupFields))
        }
        return groups
    }
}
