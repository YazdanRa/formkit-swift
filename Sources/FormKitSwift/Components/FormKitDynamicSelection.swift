import SwiftUI

/// Bind a scalar identifier or an ordered array of identifiers to the picker.
@MainActor
public enum FormKitDynamicSelection {
    case single(Binding<String?>)
    case multiple(Binding<[String]>)

    var ids: [String] {
        switch self {
        case .single(let binding):
            return binding.wrappedValue.map { [$0] } ?? []
        case .multiple(let binding):
            var seen: Set<String> = []
            return binding.wrappedValue.filter { seen.insert($0).inserted }
        }
    }

    var isSingle: Bool {
        if case .single = self {
            return true
        }
        return false
    }

    func canChoose(_ id: String, maximumSelectionCount: Int?) -> Bool {
        switch self {
        case .single:
            return true
        case .multiple:
            let current = ids
            return current.contains(id)
                || (maximumSelectionCount == 1 && current.count == 1)
                || maximumSelectionCount.map { current.count < $0 } ?? true
        }
    }

    func choose(_ id: String, isRequired: Bool, maximumSelectionCount: Int? = nil) {
        guard canChoose(id, maximumSelectionCount: maximumSelectionCount) else { return }
        switch self {
        case .single(let binding):
            binding.wrappedValue = id
        case .multiple(let binding):
            let current = ids
            if current.contains(id) {
                let remaining = current.filter { $0 != id }
                if !isRequired || !remaining.isEmpty {
                    binding.wrappedValue = remaining
                }
            } else if maximumSelectionCount == 1, current.count == 1 {
                binding.wrappedValue = [id]
            } else {
                binding.wrappedValue = current + [id]
            }
        }
    }

    func clear(isRequired: Bool) {
        guard !isRequired else { return }
        switch self {
        case .single(let binding):
            binding.wrappedValue = nil
        case .multiple(let binding):
            binding.wrappedValue = []
        }
    }
}
