import SwiftUI

/// A full-width destination row used by the Send and Receive entry sheets.
///
/// The resting state stays deliberately background-free, so the icon and
/// two-line label carry the hierarchy. Disabled destinations remain visible
/// and replace the chevron with a short explanation, so the layout does not
/// jump when capability changes.
struct MethodActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String?
    let action: () -> Void
    var enabled = true
    var status: String?

    @ScaledMetric(relativeTo: .body) private var iconSize = 24

    init(
        icon: String,
        title: String,
        subtitle: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String? = nil,
        enabled: Bool = true,
        status: String? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.enabled = enabled
        self.status = status
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundStyle(.primary)
                    .opacity(enabled ? 1 : 0.38)
                    .frame(width: iconSize, height: iconSize)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(enabled ? 1 : 0.38)

                Spacer(minLength: 8)

                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .opacity(enabled ? 1 : 0.38)
                        .lineLimit(1)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .opacity(enabled ? 1 : 0.38)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(MethodActionRowButtonStyle())
        .disabled(!enabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
        .accessibilityValue(status ?? "")
    }
}
