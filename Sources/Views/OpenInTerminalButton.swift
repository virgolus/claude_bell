import SwiftUI

/// Compact ghost-style action button used inside notification/request headers
/// to focus the originating terminal tab. Borderless by default; gains a soft
/// orange tint on hover. Lives inline next to the title text so it reads as a
/// contextual action of that title rather than a separate footer command.
struct OpenInTerminalButton: View {
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressing = false

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: "terminal.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(backgroundFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
                .scaleEffect(isPressing ? 0.92 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressing {
                        withAnimation(.easeOut(duration: 0.08)) { isPressing = true }
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.12)) { isPressing = false }
                }
        )
        .help("Open in Terminal")
        .accessibilityLabel("Open in Terminal")
    }

    private var foregroundColor: Color {
        isHovering ? Color.orange : Color.secondary
    }

    private var backgroundFill: Color {
        isHovering ? Color.orange.opacity(0.14) : Color.clear
    }

    private var borderColor: Color {
        isHovering ? Color.orange.opacity(0.35) : Color.secondary.opacity(0.18)
    }
}
