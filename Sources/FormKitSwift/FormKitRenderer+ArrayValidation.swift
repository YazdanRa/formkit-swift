import Foundation
import JSONSchema

extension FormKitRenderer {
    func supportsArraySchema(
        _ schemaObject: [String: FormKitJSONValue],
        pointerTokens: [String],
        reasons: inout [FormKitUnsupportedReason]
    ) -> Bool {
        let pointer = JSONPointer.pointerString(from: pointerTokens)
        guard case .array = schemaType(
            for: schemaObject,
            pointerTokens: pointerTokens,
            reasons: &reasons
        ) else {
            reasons.append(
                .unsupportedSchemaShape(
                    location: pointer,
                    message: String(localized: "Only array schemas can create repeatable groups.", bundle: .module)
                )
            )
            return false
        }

        let blocked = Self.blockedArrayKeywords.filter { schemaObject[$0] != nil }
        for keyword in blocked {
            reasons.append(
                .unsupportedKeyword(
                    keyword: keyword,
                    location: pointer,
                    message: String(
                        localized: "This array shape is not supported in the native renderer yet.",
                        bundle: .module
                    )
                )
            )
        }
        guard blocked.isEmpty else {
            return false
        }
        guard schemaObject["items"] != nil else {
            reasons.append(
                .unsupportedKeyword(
                    keyword: "items",
                    location: pointer,
                    message: String(localized: "Array schemas must declare a single items schema.", bundle: .module)
                )
            )
            return false
        }
        return true
    }
}
