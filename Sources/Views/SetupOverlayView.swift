import SwiftUI

struct SetupOverlayView: View {
    var onDismiss: () -> Void

    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                Text("Welcome to Claude Bell")
                    .font(.title.bold())
                Text("Menu bar companion for Claude Code")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // Explanation
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("Claude Bell uses **Claude Code hooks** to intercept permission requests and notifications.")
                } icon: {
                    Image(systemName: "link.circle.fill")
                        .foregroundStyle(.orange)
                }

                Label {
                    Text("Without hooks installed, the app won't receive any events and won't be able to function.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }

                Label {
                    Text("Hooks are written to **~/.claude/settings.json** and apply to new Claude Code sessions.")
                } icon: {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .padding(20)

            if let error = errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            Divider()

            // Actions
            VStack(spacing: 10) {
                Button {
                    do {
                        try HookInstaller.install()
                        AppDefaults.shared.set(true, forKey: "hasCompletedSetup")
                        onDismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } label: {
                    Text("Install Hooks")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.orangeProminent)

                Button {
                    AppDefaults.shared.set(true, forKey: "hasCompletedSetup")
                    onDismiss()
                } label: {
                    Text("Skip — I'll set up later in Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .frame(width: 420, height: 420)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }
}
