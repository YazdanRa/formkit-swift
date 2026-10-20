import Foundation

/// An opaque sRGB color supplied by an enum's `x-formkit-option-color-map` annotation.
public struct FormKitOptionColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    let usesDarkForeground: Bool

    init?(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("#") else { return nil }
        let digits = value.dropFirst()
        guard [3, 6].contains(digits.count),
              digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
        else { return nil }
        let expanded = digits.count == 3 ? digits.map { "\($0)\($0)" }.joined() : String(digits)
        guard let rgb = UInt32(expanded, radix: 16) else { return nil }
        red = Double((rgb >> 16) & 0xFF) / 255
        green = Double((rgb >> 8) & 0xFF) / 255
        blue = Double(rgb & 0xFF) / 255
        let linear = [red, green, blue].map { channel in
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        usesDarkForeground = (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05)
    }
}
