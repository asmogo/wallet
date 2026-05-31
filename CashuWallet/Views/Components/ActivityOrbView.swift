import SwiftUI

// MARK: - Activity Orb View
/// Loading indicator showing a subtle pulsing indicator when operations are in progress

struct ActivityOrbView: View {
    @Binding var isActive: Bool
    var autoHideDelay: Double = 2.0

    @State private var isVisible: Bool = false
    @State private var rotation: Double = 0

    var body: some View {
        Group {
            if isVisible {
                Image(systemName: "circle.dotted")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .rotationEffect(.degrees(rotation))
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.3), value: isVisible)
        .onChange(of: isActive) { _, newValue in
            if newValue {
                showOrb()
            } else {
                hideOrbAfterDelay()
            }
        }
    }

    private func showOrb() {
        withAnimation(.easeIn(duration: 0.3)) {
            isVisible = true
        }
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }

    private func hideOrbAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideDelay) {
            withAnimation(.easeOut(duration: 0.5)) {
                isVisible = false
                rotation = 0
            }
        }
    }
}

// MARK: - Loading Spinner View
/// Full-screen loading spinner for operations — uses standard ProgressView

struct LoadingSpinnerView: View {
    var message: String?

    var body: some View {
        if let message = message {
            ProgressView(message)
        } else {
            ProgressView()
        }
    }
}

// MARK: - Native Empty State

struct NativeEmptyState: View {
    enum Style {
        case fullScreen
        case section
        case compact

        var iconSize: CGFloat {
            switch self {
            case .fullScreen: return 56
            case .section: return 42
            case .compact: return 30
            }
        }

        var titleFont: Font {
            switch self {
            case .fullScreen: return .title2.weight(.semibold)
            case .section: return .headline.weight(.semibold)
            case .compact: return .subheadline.weight(.semibold)
            }
        }

        var descriptionFont: Font {
            switch self {
            case .fullScreen: return .body
            case .section, .compact: return .subheadline
            }
        }

        var spacing: CGFloat {
            switch self {
            case .fullScreen: return 12
            case .section: return 10
            case .compact: return 8
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .fullScreen: return 0
            case .section: return 32
            case .compact: return 24
            }
        }

        var maxHeight: CGFloat? {
            switch self {
            case .fullScreen: return .infinity
            case .section, .compact: return nil
            }
        }
    }

    let title: String
    let systemImage: String
    var description: String?
    var style: Style = .fullScreen

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false
    @State private var symbolTrigger = false

    var body: some View {
        VStack(spacing: style.spacing) {
            animatedIcon

            VStack(spacing: 4) {
                Text(title)
                    .font(style.titleFont)
                    .multilineTextAlignment(.center)

                if let description {
                    Text(description)
                        .font(style.descriptionFont)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: style.maxHeight)
        .padding(.horizontal, 32)
        .padding(.vertical, style.verticalPadding)
        .opacity(isPresented ? 1 : 0)
        .scaleEffect(reduceMotion ? 1 : (isPresented ? 1 : 0.96))
        .offset(y: reduceMotion ? 0 : (isPresented ? 0 : 8))
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: isPresented)
        .task {
            isPresented = true
            guard !reduceMotion else { return }
            symbolTrigger.toggle()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var animatedIcon: some View {
        let icon = Image(systemName: systemImage)
            .font(.system(size: style.iconSize, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
            .opacity(0.62)

        if #available(iOS 17.0, macOS 14.0, *) {
            icon.symbolEffect(.bounce, value: symbolTrigger)
        } else {
            icon
        }
    }
}

// MARK: - Global Mutex Lock Overlay
/// Overlay shown when wallet is performing critical operations

struct MutexLockOverlay: View {
    @Binding var isLocked: Bool
    var message: String = "Processing..."

    var body: some View {
        Group {
            if isLocked {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()

                    VStack(spacing: 20) {
                        ProgressView()
                            .controlSize(.large)

                        Text(message)
                            .font(.headline)
                    }
                    .padding(40)
                    .liquidGlassMaterial(in: RoundedRectangle(cornerRadius: 20), material: .regularMaterial)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLocked)
    }
}

// MARK: - Suggested Mints (restore recognition aid)

/// A known public mint surfaced as a one-tap quick-add during onboarding and
/// seed-restore.
struct RecommendedMint: Identifiable {
    let name: String
    let url: String
    var id: String { url }

    /// The curated shortlist offered when a user has no mints to type from memory.
    static let suggested: [RecommendedMint] = [
        RecommendedMint(name: "Minibits", url: "https://mint.minibits.cash/Bitcoin"),
        RecommendedMint(name: "Coinos", url: "https://mint.coinos.io"),
        RecommendedMint(name: "Macadamia", url: "https://mint.macadamia.cash")
    ]
}

/// Quick-add suggestion rows shown in the restore-mints empty state. Converts
/// the "type a mint URL from memory" recall task into recognition: tap a known
/// mint to stage it for restore. Rows sit on the bare canvas with hairline
/// dividers — the same shape as the staged-mint list, no card.
struct SuggestedMintsSection: View {
    /// URLs already staged or restored — filtered out of the suggestions.
    let existingURLs: Set<String>
    let onAdd: (String) -> Void

    private var available: [RecommendedMint] {
        RecommendedMint.suggested.filter { !existingURLs.contains($0.url) }
    }

    var body: some View {
        if !available.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Suggested mints")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)

                ForEach(Array(available.enumerated()), id: \.element.id) { index, mint in
                    Button {
                        onAdd(mint.url)
                        HapticFeedback.selection()
                    } label: {
                        row(for: mint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(mint.name)")
                    .accessibilityHint("Stages \(displayHost(mint.url)) for recovery")

                    if index < available.count - 1 {
                        CanvasDivider()
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func row(for mint: RecommendedMint) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bitcoinsign.bank.building")
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(mint.name)
                    .font(.subheadline.weight(.medium))
                Text(displayHost(mint.url))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func displayHost(_ url: String) -> String {
        var host = url
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        if host.hasSuffix("/") { host = String(host.dropLast()) }
        return host
    }
}

// MARK: - Preview

#Preview("Activity Orb") {
    VStack(spacing: 40) {
        ActivityOrbView(isActive: .constant(true))

        LoadingSpinnerView(message: "Loading wallet...")
    }
}

#Preview("Mutex Lock Overlay") {
    ZStack {
        Text("Main Content")

        MutexLockOverlay(isLocked: .constant(true), message: "Sending tokens...")
    }
}
