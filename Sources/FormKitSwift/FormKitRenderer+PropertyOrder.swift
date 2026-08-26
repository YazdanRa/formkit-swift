import Foundation
import JSONSchema

extension FormKitRenderer {
    struct MaterializedJSONSchemaObject {
        var object: [String: FormKitJSONValue]
        var propertyOrder: [String]
    }

    struct ResolvedSchemaObject {
        let object: [String: FormKitJSONValue]
        let propertyOrderPathTokens: [[String]]
    }

    struct JSONSchemaPropertyOrderIndex {
        private let propertyNamesBySchemaPointer: [String: [String]]

        init(schemaJSON: String) throws {
            var propertyNamesBySchemaPointer: [String: [String]] = [:]
            var scanner = JSONSchemaPropertyOrderScanner(source: schemaJSON)
            try scanner.collectPropertyOrder(into: &propertyNamesBySchemaPointer)
            self.propertyNamesBySchemaPointer = propertyNamesBySchemaPointer
        }

        func propertyNames(at schemaPathTokens: [String]) -> [String] {
            propertyNamesBySchemaPointer[JSONPointer.pointerString(from: schemaPathTokens)] ?? []
        }

        func dependentSchemaNames(at schemaPathTokens: [String]) -> [String] {
            propertyNamesBySchemaPointer[
                JSONPointer.pointerString(from: schemaPathTokens + ["dependentSchemas"])
            ] ?? []
        }
    }

    struct JSONSchemaPropertyOrderScanner {
        private let characters: [Character]
        private var index: Int = 0

        init(source: String) {
            self.characters = Array(source)
        }
    }
}

extension FormKitRenderer.JSONSchemaPropertyOrderScanner {
        mutating func collectPropertyOrder(
            into propertyNamesBySchemaPointer: inout [String: [String]]
        ) throws {
            try parseValue(
                at: [],
                propertyNamesBySchemaPointer: &propertyNamesBySchemaPointer
            )
            skipWhitespace()
            guard isAtEnd else {
                throw error("Unexpected trailing content.")
            }
        }

        private var isAtEnd: Bool {
            index >= characters.count
        }

        private mutating func parseValue(
            at schemaPathTokens: [String],
            propertyNamesBySchemaPointer: inout [String: [String]]
        ) throws {
            skipWhitespace()
            guard let character = currentCharacter else {
                throw error("Unexpected end of JSON input.")
            }

            switch character {
            case "{":
                try parseObject(
                    at: schemaPathTokens,
                    propertyNamesBySchemaPointer: &propertyNamesBySchemaPointer
                )
            case "[":
                try parseArray(
                    at: schemaPathTokens,
                    propertyNamesBySchemaPointer: &propertyNamesBySchemaPointer
                )
            case "\"":
                _ = try parseString()
            case "t":
                try consumeLiteral("true")
            case "f":
                try consumeLiteral("false")
            case "n":
                try consumeLiteral("null")
            case "-", "0"..."9":
                try parseNumber()
            default:
                throw error("Unexpected character \(character).")
            }
        }

        private mutating func parseObject(
            at schemaPathTokens: [String],
            propertyNamesBySchemaPointer: inout [String: [String]]
        ) throws {
            try consume("{")
            skipWhitespace()
            guard currentCharacter != "}" else {
                index += 1
                return
            }

            while true {
                let key = try parseString()
                skipWhitespace()
                try consume(":")
                skipWhitespace()

                if key == "properties" || key == "dependentSchemas",
                   currentCharacter == "{"
                {
                    let memberNames = try parseSchemaMap(
                        named: key,
                        at: schemaPathTokens,
                        propertyNamesBySchemaPointer: &propertyNamesBySchemaPointer
                    )
                    let orderPathTokens = key == "properties"
                        ? schemaPathTokens
                        : schemaPathTokens + [key]
                    propertyNamesBySchemaPointer[
                        JSONPointer.pointerString(from: orderPathTokens)
                    ] = memberNames
                } else {
                    try parseValue(
                        at: schemaPathTokens + [key],
                        propertyNamesBySchemaPointer: &propertyNamesBySchemaPointer
                    )
                }

                skipWhitespace()
                if currentCharacter == "," {
                    index += 1
                    skipWhitespace()
                    continue
                }

                try consume("}")
                return
            }
        }

        private mutating func parseSchemaMap(
            named memberName: String,
            at schemaPathTokens: [String],
            propertyNamesBySchemaPointer: inout [String: [String]]
        ) throws -> [String] {
            try consume("{")
            skipWhitespace()
            guard currentCharacter != "}" else {
                index += 1
                return []
            }

            var propertyNames: [String] = []
            while true {
                let key = try parseString()
                propertyNames.append(key)
                skipWhitespace()
                try consume(":")
                try parseValue(
                    at: schemaPathTokens + [memberName, key],
                    propertyNamesBySchemaPointer: &propertyNamesBySchemaPointer
                )

                skipWhitespace()
                if currentCharacter == "," {
                    index += 1
                    skipWhitespace()
                    continue
                }

                try consume("}")
                return propertyNames
            }
        }

        private mutating func parseArray(
            at schemaPathTokens: [String],
            propertyNamesBySchemaPointer: inout [String: [String]]
        ) throws {
            try consume("[")
            skipWhitespace()
            guard currentCharacter != "]" else {
                index += 1
                return
            }

            var itemIndex = 0
            while true {
                try parseValue(
                    at: schemaPathTokens + [String(itemIndex)],
                    propertyNamesBySchemaPointer: &propertyNamesBySchemaPointer
                )
                itemIndex += 1

                skipWhitespace()
                if currentCharacter == "," {
                    index += 1
                    skipWhitespace()
                    continue
                }

                try consume("]")
                return
            }
        }

        private mutating func parseString() throws -> String {
            try consume("\"")
            var result = ""

            while let character = currentCharacter {
                index += 1
                switch character {
                case "\"":
                    return result
                case "\\":
                    result.append(contentsOf: try parseEscapedCharacter())
                default:
                    result.append(character)
                }
            }

            throw error("Unterminated string literal.")
        }

        private mutating func parseEscapedCharacter() throws -> String {
            guard let escaped = currentCharacter else {
                throw error("Unterminated escape sequence.")
            }
            index += 1
            switch escaped {
            case "\"", "\\", "/":
                return String(escaped)
            case "b":
                return "\u{08}"
            case "f":
                return "\u{0C}"
            case "n":
                return "\n"
            case "r":
                return "\r"
            case "t":
                return "\t"
            case "u":
                return try parseUnicodeEscape()
            default:
                throw error("Invalid escape sequence.")
            }
        }

        private mutating func parseUnicodeEscape() throws -> String {
            let firstScalarValue = try parseUnicodeEscapeScalarValue()
            if (0xD800...0xDBFF).contains(firstScalarValue) {
                try consume("\\")
                try consume("u")
                let secondScalarValue = try parseUnicodeEscapeScalarValue()
                guard (0xDC00...0xDFFF).contains(secondScalarValue) else {
                    throw error("Invalid unicode escape.")
                }

                let combinedScalarValue = 0x10000
                    + ((firstScalarValue - 0xD800) << 10)
                    + (secondScalarValue - 0xDC00)
                guard let scalar = UnicodeScalar(combinedScalarValue) else {
                    throw error("Invalid unicode escape.")
                }
                return String(scalar)
            }

            guard !(0xDC00...0xDFFF).contains(firstScalarValue),
                  let scalar = UnicodeScalar(firstScalarValue)
            else {
                throw error("Invalid unicode escape.")
            }
            return String(scalar)
        }

        private mutating func parseUnicodeEscapeScalarValue() throws -> UInt32 {
            let hex = try consumeHexDigits(count: 4)
            guard let scalarValue = UInt32(hex, radix: 16) else {
                throw error("Invalid unicode escape.")
            }
            return scalarValue
        }

        private mutating func parseNumber() throws {
            guard currentCharacter != nil else {
                throw error("Unexpected end of number.")
            }

            if currentCharacter == "-" {
                index += 1
            }

            try consumeDigits(minimumCount: 1)

            if currentCharacter == "." {
                index += 1
                try consumeDigits(minimumCount: 1)
            }

            if currentCharacter == "e" || currentCharacter == "E" {
                index += 1
                if currentCharacter == "+" || currentCharacter == "-" {
                    index += 1
                }
                try consumeDigits(minimumCount: 1)
            }
        }

        private mutating func consumeLiteral(_ literal: String) throws {
            for character in literal {
                try consume(character)
            }
        }

        private mutating func consumeDigits(minimumCount: Int) throws {
            var count = 0
            while let character = currentCharacter, character.isNumber {
                index += 1
                count += 1
            }

            guard count >= minimumCount else {
                throw error("Expected digit.")
            }
        }

        private mutating func consumeHexDigits(count: Int) throws -> String {
            var hex = ""
            for _ in 0..<count {
                guard let character = currentCharacter,
                      character.isHexDigit
                else {
                    throw error("Expected hex digit.")
                }
                hex.append(character)
                index += 1
            }
            return hex
        }

        private mutating func consume(_ expected: Character) throws {
            skipWhitespace()
            guard currentCharacter == expected else {
                throw error("Expected \(expected).")
            }
            index += 1
        }

        private mutating func skipWhitespace() {
            while let character = currentCharacter, character.isWhitespace {
                index += 1
            }
        }

        private var currentCharacter: Character? {
            guard index < characters.count else {
                return nil
            }
            return characters[index]
        }

        private func error(_ message: String) -> NSError {
            NSError(
                domain: "JSONSchemaPropertyOrderScanner",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
}
