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
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
