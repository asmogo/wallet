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
                .foregroundColor(.white)
                .font(.system(size: 24))
            
            // Text Content
            VStack(alignment: .leading, spacing: 2) {
                if let amount = amount {
                    Text("Received \(amount) sat")
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                    
                    if let fee = fee, fee > 0 {
                        Text("(fee: \(fee) sat)")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.caption)
                    }
                } else {
                    Text(message)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                }
            }
            
            Spacer()
            
            // Close Button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .bold))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.green) // Cashu green
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        .transition(.move(edge: .top).combined(with: .opacity))
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
