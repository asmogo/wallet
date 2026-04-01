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
            case .error: return .red
            case .warning: return .orange
            case .info: return .secondary
            }
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Label(message, systemImage: type.icon)
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
        .accessibilityElement(children: .combine)
    }
}
