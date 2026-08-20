func applyFormKitOrder(
    _ sourceOrder: [String],
    properties: [String: FormKitJSONValue]
) -> [String] {
    sourceOrder.enumerated().sorted { lhs, rhs in
        let lhsOrder = formKitOrder(properties[lhs.element])
        let rhsOrder = formKitOrder(properties[rhs.element])

        switch (lhsOrder, rhsOrder) {
        case let (lhsOrder?, rhsOrder?) where lhsOrder != rhsOrder:
            return lhsOrder < rhsOrder
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.offset < rhs.offset
        }
    }.map(\.element)
}

private func formKitOrder(_ property: FormKitJSONValue?) -> Double? {
    guard let value = property?.object?["x-formkit-order"] else {
        return nil
    }

    switch value {
    case .integer(let value):
        return Double(value)
    case .number(let value) where value.isFinite && value.rounded(.towardZero) == value:
        return value
    default:
        return nil
    }
}
