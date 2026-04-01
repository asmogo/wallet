import SwiftUI

/// Standardized error/info banner for consistent error display across the app
struct ErrorBannerView: View {
    let message: String
    var type: BannerType = .error
    var onDismiss: (() -> Void)?

    enum BannerType {
        case error, warning, info

        var icon: String {
            switch self {
            case .error: return "exclamationmark.triangle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .error: return .cashuError
            case .warning: return .cashuWarning
            case .info: return .cashuMutedText
            }
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: type.icon)
                .foregroundColor(type.color)
                .accessibilityHidden(true)

            Text(message)
                .font(.footnote)
                .foregroundStyle(type.color)
                .multilineTextAlignment(.leading)

            Spacer()

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(type.color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(type.color.opacity(0.3), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }
}
