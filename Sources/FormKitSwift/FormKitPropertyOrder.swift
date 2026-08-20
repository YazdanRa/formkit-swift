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

private func formKitOrder(_ property: FormKitJSONValue?) -> Int? {
    property?.object?["x-formkit-order"]?.integer
}
