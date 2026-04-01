import SwiftUI

struct NotificationBadgeView: View {
    let message: String
    let amount: UInt64?
    let fee: UInt64?
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.primary)
                .font(.system(size: 24))
                .accessibilityHidden(true)

            // Text Content
            VStack(alignment: .leading, spacing: 2) {
                if let amount = amount {
                    Text("Received \(amount) sat")
                        .foregroundStyle(.primary)
                        .font(.system(size: 16, weight: .medium))

                    if let fee = fee, fee > 0 {
                        Text("(fee: \(fee) sat)")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.caption)
                    }
                } else {
                    Text(message)
                        .foregroundStyle(.primary)
                        .font(.system(size: 16, weight: .medium))
                }
            }

            Spacer()

            // Close Button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(.primary)
                    .font(.system(size: 16, weight: .bold))
            }
            .accessibilityLabel("Dismiss notification")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.green) // Cashu green
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(notificationAccessibilityLabel)
        .accessibilityAddTraits(.isStaticText)
    }

    private var notificationAccessibilityLabel: String {
        if let amount = amount {
            if let fee = fee, fee > 0 {
                return "Received \(amount) sats, fee: \(fee) sats"
            }
            return "Received \(amount) sats"
        }
        return message
    }
}

#Preview {
    ZStack {
        Color.black
        NotificationBadgeView(
            message: "Success",
            amount: 21,
            fee: 1,
            onDismiss: {}
        )
        .padding()
    }
}
