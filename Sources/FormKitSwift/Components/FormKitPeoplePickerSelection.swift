import SwiftUI

/// Bind a scalar identifier or an ordered array of identifiers to the picker.
@MainActor
public enum FormKitPeopleSelection {
    case single(Binding<String?>)
    case multiple(Binding<[String]>)

    var ids: [String] {
        switch self {
        case .single(let binding):
            return binding.wrappedValue.map { [$0] } ?? []
        case .multiple(let binding):
            return binding.wrappedValue
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
        case .multiple(let binding):
            return binding.wrappedValue.contains(id)
                || maximumSelectionCount.map { binding.wrappedValue.count < $0 } ?? true
        }
    }

    func choose(_ id: String, isRequired: Bool, maximumSelectionCount: Int? = nil) {
        guard canChoose(id, maximumSelectionCount: maximumSelectionCount) else { return }
        switch self {
        case .single(let binding):
            binding.wrappedValue = id
        case .multiple(let binding):
            let current = binding.wrappedValue
            if current.contains(id) {
                let remaining = current.filter { $0 != id }
                if !isRequired || !remaining.isEmpty {
                    binding.wrappedValue = remaining
                }
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
