import Foundation

extension String {
    func trimmedForJSONSchemaForm() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
