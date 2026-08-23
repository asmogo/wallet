import SwiftUI

/// A full-width destination row used by the Send and Receive entry sheets.
///
/// The solid neutral surface, inset icon tile, two-line label, and trailing
/// affordance mirror the same component on Android while remaining native to
/// SwiftUI. Disabled destinations stay visible and replace the chevron with a
/// short explanation, so the layout does not jump when capability changes.
struct MethodActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let accessibilityLabel: String
    let action: () -> Void
    var enabled = true
    var status: String?

    @Environment(\.bottomSheetSurfaceStyle) private var bottomSheetSurfaceStyle
    @Environment(\.colorScheme) private var colorScheme

    init(
        icon: String,
        title: String,
        subtitle: String,
        accessibilityLabel: String,
        enabled: Bool = true,
        status: String? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.accessibilityLabel = accessibilityLabel
        self.enabled = enabled
        self.status = status
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .opacity(enabled ? 1 : 0.38)
                    .frame(width: 48, height: 48)
                    .background(
                        iconInsetColor,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
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
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.04), in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(.quaternary, lineWidth: 1)
                                .opacity(enabled ? 1 : 0.38)
                        }
                } else {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .opacity(enabled ? 1 : 0.38)
                        .accessibilityHidden(true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .background(
                rowColor,
                in: RoundedRectangle(cornerRadius: 24)
            )
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(MethodActionRowButtonStyle())
        .disabled(!enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(status ?? "")
    }

    private var rowColor: Color {
        bottomSheetSurfaceStyle == .compact
            ? CompactSheetPalette.control(for: colorScheme)
            : Color.primary.opacity(0.08)
    }

    private var iconInsetColor: Color {
        bottomSheetSurfaceStyle == .compact
            ? CompactSheetPalette.iconInset(for: colorScheme)
            : Color.primary.opacity(0.08)
    }
}
