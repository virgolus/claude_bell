import SwiftUI
import AppKit

/// Manages user-configurable style settings for notification body text.
@MainActor
final class BodyStyleSettings: ObservableObject {
    static let shared = BodyStyleSettings()

    enum PanelPosition: String, CaseIterable {
        case menuBar = "menuBar"
        case left = "left"
        case right = "right"
        case fullscreen = "fullscreen"

        var label: String {
            switch self {
            case .menuBar: return "Menu Bar"
            case .left: return "Left"
            case .right: return "Right"
            case .fullscreen: return "Fullscreen"
            }
        }
    }

    enum Appearance: String, CaseIterable {
        case system = "system"
        case light = "light"
        case dark = "dark"

        var label: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }

        var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }
    }

    @Published var panelWidth: CGFloat {
        didSet {
            AppDefaults.shared.set(Double(panelWidth), forKey: "panelWidth")
        }
    }

    @Published var panelPosition: PanelPosition {
        didSet {
            AppDefaults.shared.set(panelPosition.rawValue, forKey: "panelPosition")
        }
    }

    @Published var appearance: Appearance {
        didSet {
            AppDefaults.shared.set(appearance.rawValue, forKey: "appAppearance")
            applyAppearance()
        }
    }

    /// Sentinel `fontName` meaning "the system monospaced font" (SF Mono).
    /// SF Mono is a reserved system font and cannot be loaded via
    /// `NSFont(name: "SFMono-Regular", …)` — that returns nil and SwiftUI
    /// silently falls back to the proportional system font. It must be reached
    /// through `Font.system(…, design: .monospaced)` instead.
    static let systemMonospacedFontName = "__system_monospaced__"

    static let availableFonts: [(label: String, name: String?)] = [
        ("System Default", nil),
        ("SF Mono", systemMonospacedFontName),
        ("Monaco", "Monaco"),
        ("Menlo", "Menlo"),
        ("Courier New", "Courier New"),
        ("Georgia", "Georgia"),
        ("Helvetica Neue", "HelveticaNeue"),
        ("Avenir", "Avenir"),
        ("Palatino", "Palatino"),
    ]

    /// Whether the user has set a custom background color (vs system default).
    @Published var hasCustomBackground: Bool
    /// Whether the user has set a custom font color (vs system default).
    @Published var hasCustomFontColor: Bool

    /// The custom background color (only used when `hasCustomBackground` is true).
    @Published var customBackgroundColor: Color {
        didSet {
            if hasCustomBackground { saveColor(customBackgroundColor, forKey: "bodyBackgroundColor") }
        }
    }
    /// The custom font color (only used when `hasCustomFontColor` is true).
    @Published var customFontColor: Color {
        didSet {
            if hasCustomFontColor { saveColor(customFontColor, forKey: "bodyFontColor") }
        }
    }

    @Published var fontName: String? {
        didSet { AppDefaults.shared.set(fontName, forKey: "bodyFontName") }
    }

    /// The body text point size for notification markdown. Other text styles
    /// (headings, tables, code) scale by the same delta relative to this.
    @Published var bodyFontSize: CGFloat {
        didSet { AppDefaults.shared.set(Double(bodyFontSize), forKey: "bodyFontSize") }
    }

    /// The system's default Dynamic Type body point size (typically 13 pt).
    /// Used as the baseline so a default `bodyFontSize` leaves the UI unchanged.
    static var systemBodyPointSize: CGFloat {
        NSFont.preferredFont(forTextStyle: .body).pointSize
    }

    /// The effective background color: custom or system default.
    /// Default is `controlBackgroundColor` — a solid, mode-aware card surface
    /// (white in light, near-black in dark) that gives the notification body
    /// strong contrast against the panel background.
    var backgroundColor: Color {
        hasCustomBackground ? customBackgroundColor : Color(nsColor: .controlBackgroundColor)
    }

    /// The effective font color: custom or nil (= use system .primary via foregroundStyle inheritance).
    var fontColor: Color? {
        hasCustomFontColor ? customFontColor : nil
    }

    private init() {
        let savedBg = Self.loadColor(forKey: "bodyBackgroundColor")
        self.hasCustomBackground = savedBg != nil
        self.customBackgroundColor = savedBg ?? Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 0.3)

        let savedFont = Self.loadColor(forKey: "bodyFontColor")
        self.hasCustomFontColor = savedFont != nil
        self.customFontColor = savedFont ?? .white

        var loadedFontName = AppDefaults.shared.string(forKey: "bodyFontName")
        // Migrate the old, non-loadable SF Mono PostScript name to the sentinel.
        if loadedFontName == "SFMono-Regular" {
            loadedFontName = Self.systemMonospacedFontName
            AppDefaults.shared.set(loadedFontName, forKey: "bodyFontName")
        }
        self.fontName = loadedFontName

        let savedFontSize = AppDefaults.shared.object(forKey: "bodyFontSize") as? Double
        self.bodyFontSize = savedFontSize.map { CGFloat($0) } ?? Self.systemBodyPointSize

        let savedWidth = AppDefaults.shared.object(forKey: "panelWidth") as? Double
        self.panelWidth = savedWidth.map { CGFloat($0) } ?? 900

        let savedPosition = AppDefaults.shared.string(forKey: "panelPosition") ?? "menuBar"
        self.panelPosition = PanelPosition(rawValue: savedPosition) ?? .menuBar

        let savedAppearance = AppDefaults.shared.string(forKey: "appAppearance") ?? "system"
        self.appearance = Appearance(rawValue: savedAppearance) ?? .system
        applyAppearance()
    }

    func applyAppearance() {
        NSApp.appearance = appearance.nsAppearance
    }

    /// Returns the body font at the given size style, using the user's chosen
    /// font family and shifting every text style by the user's body-size delta.
    func bodyFont(size style: Font.TextStyle = .body) -> Font {
        let base = NSFont.preferredFont(forTextStyle: nsFontStyle(style)).pointSize
        let delta = bodyFontSize - Self.systemBodyPointSize
        let pointSize = max(1, base + delta)
        if let name = fontName {
            if name == Self.systemMonospacedFontName {
                return Font.system(size: pointSize, design: .monospaced)
            }
            return Font.custom(name, size: pointSize)
        }
        return Font.system(size: pointSize)
    }

    func setCustomBackground(_ color: Color) {
        hasCustomBackground = true
        customBackgroundColor = color
        saveColor(color, forKey: "bodyBackgroundColor")
    }

    func setCustomFontColor(_ color: Color) {
        hasCustomFontColor = true
        customFontColor = color
        saveColor(color, forKey: "bodyFontColor")
    }

    func resetBackgroundColor() {
        AppDefaults.shared.removeObject(forKey: "bodyBackgroundColor")
        hasCustomBackground = false
    }

    func resetFontColor() {
        AppDefaults.shared.removeObject(forKey: "bodyFontColor")
        hasCustomFontColor = false
    }

    func resetFontName() {
        AppDefaults.shared.removeObject(forKey: "bodyFontName")
        fontName = nil
    }

    func resetFontSize() {
        AppDefaults.shared.removeObject(forKey: "bodyFontSize")
        bodyFontSize = Self.systemBodyPointSize
    }

    func resetPanelWidth() {
        AppDefaults.shared.removeObject(forKey: "panelWidth")
        panelWidth = 900
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
