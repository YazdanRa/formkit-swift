import Foundation

public extension FormKitSession {
    /// The current serializable instance without untouched defaults outside arrays.
    ///
    /// Unlike ``currentInstanceJSON``, this projection omits non-array values whose source is
    /// ``FormKitToolValueSource/defaultValue``. Initial values and values set during the session
    /// remain explicit. Arrays and all their descendants are preserved because FormKit does not
    /// track enough container provenance to omit their defaults without changing authored data.
    var instanceJSONOmittingNonArrayDefaults: String {
        let currentInstance = makeInstanceJSONValue()
        let omittedDefaultPaths = orderedFields.compactMap { field -> [String]? in
            guard field.shouldSerialize,
                  toolValueSource(for: field) == .defaultValue,
                  !hasArrayAncestor(in: currentInstance, path: Self.tokens(from: field.pointer))
            else {
                return nil
            }
            return Self.tokens(from: field.pointer)
        }
        let projectedInstance = omittedDefaultPaths.reduce(currentInstance) { instance, path in
            removingValue(from: instance, path: path)
        }
        let prunableObjectPaths = Set(omittedDefaultPaths.flatMap { path in
            path.indices.dropFirst().map { Array(path.prefix($0)) }
        })
        let requiredObjectPaths = Set(
            renderPlan.sections
                .filter(\.isRequired)
                .filter(\.shouldSerialize)
                .filter { !$0.isOwnedByArrayRow && $0.pointer != "#" }
                .map { Self.tokens(from: $0.pointer) }
        )
        return Self.prettyJSONString(
            from: pruningGeneratedEmptyObjects(
                projectedInstance,
                initialValue: initialInstance,
                path: [],
                prunableObjectPaths: prunableObjectPaths,
                requiredObjectPaths: requiredObjectPaths
            )
        )
    }

    private func hasArrayAncestor(
        in rootValue: FormKitJSONValue,
        path: [String]
    ) -> Bool {
        var currentValue = rootValue
        for token in path.dropLast() {
            switch currentValue {
            case .array:
                return true
            case .object(let object):
                guard let child = object[token] else { return false }
                currentValue = child
            default:
                return false
            }
        }
        return currentValue.array != nil
    }

    private func pruningGeneratedEmptyObjects(
        _ currentValue: FormKitJSONValue,
        initialValue: FormKitJSONValue?,
        path: [String],
        prunableObjectPaths: Set<[String]>,
        requiredObjectPaths: Set<[String]>
    ) -> FormKitJSONValue {
        guard case .object(let object) = currentValue else {
            return currentValue
        }

        let initialObject = initialValue?.object
        let prunedObject = object.reduce(into: [String: FormKitJSONValue]()) { result, element in
            let (key, value) = element
            let childPath = path + [key]
            let prunedValue = pruningGeneratedEmptyObjects(
                value,
                initialValue: initialObject?[key],
                path: childPath,
                prunableObjectPaths: prunableObjectPaths,
                requiredObjectPaths: requiredObjectPaths
            )
            if case .object(let childObject) = prunedValue,
               childObject.isEmpty,
               initialObject?[key]?.object == nil,
               prunableObjectPaths.contains(childPath),
               !requiredObjectPaths.contains(childPath)
            {
                return
            }
            result[key] = prunedValue
        }
        return .object(prunedObject)
    }
}
