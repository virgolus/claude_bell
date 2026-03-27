import SwiftUI

/// Prominent button style with orange background that darkens on press
/// instead of the system default which lightens orange to yellow.
struct OrangeProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.orange.opacity(0.7) : .orange)
            )
            .opacity(isEnabled ? 1 : 0.5)
    }
}

extension ButtonStyle where Self == OrangeProminentButtonStyle {
    static var orangeProminent: OrangeProminentButtonStyle { .init() }
}
