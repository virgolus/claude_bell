import SwiftUI

struct SetupView: View {
    @State private var installed = HookInstaller.isInstalled
    @State private var errorMessage: String?
    @State private var showSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: installed ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(installed ? .green : .secondary)
                Text(installed ? "Hooks installed" : "Hooks not installed")
                    .font(.body.weight(.medium))
            }

            Text("Claude Bell hooks intercept permission requests and notifications from Claude Code.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                if installed {
                    Button("Remove Hooks") {
                        do {
                            try HookInstaller.uninstall()
                            installed = false
                            showSuccess = true
                            errorMessage = nil
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                } else {
                    Button("Install Hooks") {
                        do {
                            try HookInstaller.install()
                            installed = true
                            showSuccess = true
                            errorMessage = nil
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if showSuccess {
                Text("Done! Changes apply to new Claude Code sessions.")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            showSuccess = false
                        }
                    }
            }
        }
        .padding()
    }
}
