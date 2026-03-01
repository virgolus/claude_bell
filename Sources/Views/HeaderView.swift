import SwiftUI

struct HeaderView: View {
    @EnvironmentObject var store: RequestStore
    @Binding var showSetup: Bool

    var body: some View {
        HStack {
            Image(systemName: "bell.fill")
                .foregroundStyle(.orange)
            Text("Claude Bell")
                .font(.headline)

            Spacer()

            if store.badgeCount > 0 {
                Text("\(store.badgeCount) pending")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.2))
                    .clipShape(Capsule())
            }

            Button {
                showSetup.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                dismissPanel()
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func dismissPanel() {
        // Click the status bar button to properly toggle the MenuBarExtra panel
        // This deselects the icon correctly, unlike orderOut
        if let button = findStatusButton() {
            button.performClick(nil)
        } else {
            // Fallback
            NSApp.keyWindow?.orderOut(nil)
            NSApp.deactivate()
        }
    }

    private func findStatusButton() -> NSStatusBarButton? {
        for window in NSApp.windows {
            let name = String(describing: type(of: window))
            if name.contains("StatusBar") || name.contains("NSStatusBar") {
                if let contentView = window.contentView {
                    return findButtonIn(contentView)
                }
            }
        }
        return nil
    }

    private func findButtonIn(_ view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton {
            return button
        }
        for subview in view.subviews {
            if let found = findButtonIn(subview) {
                return found
            }
        }
        return nil
    }
}
