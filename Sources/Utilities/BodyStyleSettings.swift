import SwiftUI
import AppKit

/// Manages user-configurable style settings for notification body text.
@MainActor
final class BodyStyleSettings: ObservableObject {
    static let shared = BodyStyleSettings()

    static let availableFonts: [(label: String, name: String?)] = [
        ("System Default", nil),
        ("SF Mono", "SFMono-Regular"),
        ("Menlo", "Menlo"),
        ("Courier New", "Courier New"),
        ("Georgia", "Georgia"),
        ("Helvetica Neue", "HelveticaNeue"),
        ("Avenir", "Avenir"),
        ("Palatino", "Palatino"),
    ]

    @Published var backgroundColor: Color {
        didSet { saveColor(backgroundColor, forKey: "bodyBackgroundColor") }
    }
    @Published var fontColor: Color {
        didSet { saveColor(fontColor, forKey: "bodyFontColor") }
    }
    @Published var fontName: String? {
        didSet { AppDefaults.shared.set(fontName, forKey: "bodyFontName") }
    }

    /// Concrete default that round-trips through hex (matches the look of Color.secondary.opacity(0.06))
    static let defaultBackgroundColor = Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 0.06)
    static let defaultFontColor = Color(.sRGB, red: 0.0, green: 0.0, blue: 0.0, opacity: 1.0)

    private init() {
        self.backgroundColor = Self.loadColor(forKey: "bodyBackgroundColor") ?? Self.defaultBackgroundColor
        self.fontColor = Self.loadColor(forKey: "bodyFontColor") ?? Self.defaultFontColor
        self.fontName = AppDefaults.shared.string(forKey: "bodyFontName")
    }

    /// Returns the body font at the given size style, using the user's chosen font family.
    func bodyFont(size: Font.TextStyle = .title3) -> Font {
        guard let name = fontName else { return Font.system(size) }
        return Font.custom(name, size: NSFont.preferredFont(forTextStyle: nsFontStyle(size)).pointSize)
    }

    func resetBackgroundColor() {
        AppDefaults.shared.removeObject(forKey: "bodyBackgroundColor")
        backgroundColor = Self.defaultBackgroundColor
    }

    func resetFontColor() {
        AppDefaults.shared.removeObject(forKey: "bodyFontColor")
        fontColor = Self.defaultFontColor
    }

    func resetFontName() {
        AppDefaults.shared.removeObject(forKey: "bodyFontName")
        fontName = nil
    }

    // MARK: - Color persistence via hex

    private func saveColor(_ color: Color, forKey key: String) {
        guard let hex = color.toHex() else { return }
        AppDefaults.shared.set(hex, forKey: key)
    }

    private static func loadColor(forKey key: String) -> Color? {
        guard let hex = AppDefaults.shared.string(forKey: key) else { return nil }
        return Color(hex: hex)
    }

    private func nsFontStyle(_ style: Font.TextStyle) -> NSFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .body: return .body
        case .callout: return .callout
        case .caption: return .caption1
        case .caption2: return .caption2
        case .footnote: return .footnote
        default: return .body
        }
    }
}

// MARK: - Color ↔ Hex

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6 || h.count == 8 else { return nil }
        var num: UInt64 = 0
        guard Scanner(string: h).scanHexInt64(&num) else { return nil }
        if h.count == 8 {
            let r = Double((num >> 24) & 0xFF) / 255
            let g = Double((num >> 16) & 0xFF) / 255
            let b = Double((num >> 8) & 0xFF) / 255
            let a = Double(num & 0xFF) / 255
            self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
        } else {
            let r = Double((num >> 16) & 0xFF) / 255
            let g = Double((num >> 8) & 0xFF) / 255
            let b = Double(num & 0xFF) / 255
            self.init(.sRGB, red: r, green: g, blue: b)
        }
    }

    func toHex() -> String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int(c.redComponent * 255)
        let g = Int(c.greenComponent * 255)
        let b = Int(c.blueComponent * 255)
        let a = Int(c.alphaComponent * 255)
        if a < 255 {
            return String(format: "%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
