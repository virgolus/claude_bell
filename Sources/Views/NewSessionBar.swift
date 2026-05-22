import SwiftUI

/// Always-visible action bar shown just under the header. Opens the New Session flow.
struct NewSessionBar: View {
    var isActive: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.body)
                Text("New Session")
                    .font(.callout.weight(.medium))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isActive ? Color.white : Color.orange)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.orange : Color.orange.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.orange.opacity(isActive ? 0 : 0.35), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}
