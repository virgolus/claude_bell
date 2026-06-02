import SwiftUI

/// Shows that a live Stop-hook hold exists for the session: replies go
/// straight through the hook (no keystroke injection) until it expires.
struct DirectReplyBadge: View {
    let expiresAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(expiresAt.timeIntervalSince(context.date)))
            if remaining > 0 {
                Label("Direct reply · \(Self.format(remaining))", systemImage: "bolt.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
    }

    static func format(_ seconds: Int) -> String {
        if seconds >= 3600 { return "\(seconds / 3600)h \((seconds % 3600) / 60)m" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
