import SwiftUI

// MARK: - Context

/// Where the connect-a-mint surface was opened from. Only the header differs:
/// from Send the sheet is still titled "Send" and needs an in-body headline
/// explaining why the flow stalled, while the wallet-home CTA already said
/// "Add mint" — repeating it as a headline stacks a third level of title before
/// the user reaches anything tappable.
enum ConnectMintContext {
    case send
    case addMint

    var navigationTitle: String {
        switch self {
        case .send: "Send"
        case .addMint: "Add mint"
        }
    }

    var showsHeadline: Bool { self == .send }

    // The app says "add" everywhere else — CTAs, row a11y labels, the submit
    // button — so the headline says it too rather than introducing "connect" as
    // a second verb for the same act.
    static let headline = "Add a mint first"
    static let subtitle = "Mints issue the ecash you send and receive. Add one to get started."
}

/// The in-sheet steps pushed from the picker.
enum ConnectMintRoute: Hashable {
    case addCustom
    case discover
}

// MARK: - Layout constants

private enum ConnectMintMetrics {
    /// One gutter for every element on the picker — headline, section header,
    /// rows and footer links share a left edge.
    static let gutter: CGFloat = 20
    static let avatar: CGFloat = 36
    static let avatarGap: CGFloat = 12
    static let headlineToSubtitle: CGFloat = 6
    /// Opens a new group; at the old 12 the header glued to the paragraph.
    static let subtitleToSection: CGFloat = 24
    static let sectionToRows: CGFloat = 8
    static let rowVertical: CGFloat = 12
    static let rowsToFooter: CGFloat = 20
    static let footerSpacing: CGFloat = 12
}

// MARK: - Picker

/// Recognition over recall: a curated shortlist to tap instead of a URL to
/// remember. Body only — the host owns the `NavigationStack`, the title and the
/// presentation detents.
struct ConnectMintPicker: View {
    let context: ConnectMintContext
    @Binding var route: ConnectMintRoute?
    let onAdd: (String) -> Void
    /// URLs the wallet already has — filtered out of the shortlist.
    var existingURLs: Set<String> = []
    /// Whether Nostr discovery can run at all (WebSockets setting).
    var discoveryAvailable: Bool = false
    var errorMessage: String?
    var onHeightChange: (CGFloat) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if context.showsHeadline {
                Text(ConnectMintContext.headline)
                    .font(.title3.weight(.medium))
                    .padding(.bottom, ConnectMintMetrics.headlineToSubtitle)
            }

            Text(ConnectMintContext.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SuggestedMintsSection(existingURLs: existingURLs, onAdd: onAdd)

            if let errorMessage {
                InlineNotice(message: errorMessage, severity: .error)
                    .padding(.top, ConnectMintMetrics.footerSpacing)
            }

            // Spacing lives in each label's vertical padding so the links keep
            // 44pt hit targets; stacking them with plain spacing would leave
            // ~20pt-tall taps.
            VStack(spacing: 0) {
                // Verb + object, matching "Discover mints" below it. "Custom" is
                // an implementation label, and "URL" is already said by the step
                // it opens.
                footerLink(
                    title: "Add by URL",
                    systemImage: "plus",
                    route: .addCustom
                )
                // Discovery rides Nostr relays over WebSockets. With the
                // setting off it can only show a "turn this on" dead end, so
                // it isn't offered at all.
                if discoveryAvailable {
                    footerLink(
                        title: "Discover mints",
                        systemImage: "magnifyingglass",
                        route: .discover
                    )
                }
            }
            // The first link carries 12pt of its own padding; net gap is the
            // designed 20pt.
            .padding(.top, ConnectMintMetrics.rowsToFooter - ConnectMintMetrics.footerSpacing)
        }
        .padding(.horizontal, ConnectMintMetrics.gutter)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .contentFitMeasured { onHeightChange($0) }
    }

    @ViewBuilder
    private func footerLink(
        title: String,
        systemImage: String,
        route target: ConnectMintRoute
    ) -> some View {
        Button {
            route = target
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .padding(.vertical, ConnectMintMetrics.footerSpacing)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .textLinkButton()
    }
}

// MARK: - Known mints

/// Quick-add rows for known public mints, filtered against what the wallet
/// already has. Rows sit on the bare canvas.
struct SuggestedMintsSection: View {
    /// URLs already added — filtered out of the suggestions.
    let existingURLs: Set<String>
    let onAdd: (String) -> Void

    private var available: [RecommendedMint] {
        RecommendedMint.suggested.filter { !existingURLs.contains($0.url) }
    }

    var body: some View {
        if !available.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Not "Suggested": the disclaimer on the pushed step says this
                // wallet isn't affiliated with any mint, and suggesting implies
                // it is.
                Text("Known mints")
                    .cashuText(.overline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, ConnectMintMetrics.sectionToRows)

                ForEach(Array(available.enumerated()), id: \.element.id) { index, mint in
                    mintButton(mint)
                }
            }
            .padding(.top, ConnectMintMetrics.subtitleToSection)
        }
    }

    @ViewBuilder
    private func mintButton(_ mint: RecommendedMint) -> some View {
        Button {
            onAdd(mint.url)
            HapticFeedback.selection()
        } label: {
            row(for: mint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(mint.name)")
        .accessibilityHint("Connects \(displayHost(mint.url)) to your wallet")
    }

    private func row(for mint: RecommendedMint) -> some View {
        HStack(spacing: ConnectMintMetrics.avatarGap) {
            MintAvatarView(iconUrl: mint.iconUrl, name: mint.name, size: ConnectMintMetrics.avatar)

            // Title and the subtitle above it share a size and separate by weight
            // and colour — that is what keeps this sheet to four type sizes.
            VStack(alignment: .leading, spacing: 2) {
                Text(mint.name)
                    .font(.subheadline.weight(.semibold))
                Text(displayHost(mint.url))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // The whole row is the target; the glyph is an indicator, not a
            // nested control, and must not compete with the headline's weight.
            Image(systemName: "plus.circle.fill")
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, ConnectMintMetrics.rowVertical)
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

// MARK: - Pushed steps

/// Shared destination builder so the Send sheet and the standalone sheet push
/// identical steps.
@ViewBuilder
func connectMintDestination(
    _ route: ConnectMintRoute,
    onAdded: @escaping () -> Void,
    onHeightChange: @escaping (CGFloat) -> Void = { _ in }
) -> some View {
    switch route {
    case .addCustom:
        // Titled after the link that pushed it. The standalone Mints-tab sheet
        // isn't reached through that link, so it keeps the form's default.
        AddMintFormView(
            navigationTitle: "Add by URL",
            onAdded: onAdded,
            onHeightChange: onHeightChange
        )
    case .discover:
        MintDiscoveryList(onMintAdded: onAdded)
            .navigationTitle("Discover mints")
            .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Standalone sheet

/// The wallet-home "Add mint" entry point. The Send flow renders
/// `ConnectMintPicker` inside its own sheet instead of presenting this.
struct ConnectMintSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared

    @State private var route: ConnectMintRoute?
    @State private var contentHeight: CGFloat = 0
    @State private var addMintError: String?

    var body: some View {
        NavigationStack {
            ConnectMintPicker(
                context: .addMint,
                route: $route,
                onAdd: addMint,
                existingURLs: Set(walletManager.mints.map(\.url)),
                discoveryAvailable: settings.useWebsockets,
                errorMessage: addMintError,
                onHeightChange: { newHeight in
                    // Ignore re-measures from the off-screen picker while a step
                    // is pushed — the pushed view reports its own height.
                    guard route == nil else { return }
                    contentHeight = newHeight
                }
            )
            .navigationTitle(ConnectMintContext.addMint.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $route) { route in
                connectMintDestination(
                    route,
                    onAdded: { dismiss() },
                    onHeightChange: { contentHeight = $0 }
                )
            }
        }
        // Both the shortlist and the pushed URL step hug their content, matching
        // Android. Only discovery fills the sheet — it hosts a scrolling list and
        // needs bounded height.
        .contentFitDetent(contentHeight, enabled: route != .discover)
        .presentationDragIndicator(.visible)
        // Hugging the shortlist, this floats over the canvas and keeps the
        // system's elevated background; only the pushed full-height steps adopt
        // the flat canvas. Every other partial-height sheet in the app does the
        // same — see `MintsListView`'s Add Mint and the Send sheet's compact face.
        .canvasSheetBackground(whenFillingScreen: route == .discover)
    }

    private func addMint(_ url: String) {
        addMintError = nil
        Task { @MainActor in
            do {
                try await walletManager.addMint(url: url)
                dismiss()
            } catch {
                // Same mapper Android's quick-add uses. The old string blamed
                // this wallet's own shortlist for what is usually the network.
                addMintError = error.userFacingWalletMessage
            }
        }
    }
}

#Preview("Connect a mint — from Send") {
    ConnectMintPicker(context: .send, route: .constant(nil), onAdd: { _ in }, discoveryAvailable: true)
        .environmentObject(WalletManager())
}

#Preview("Connect a mint — from Add mint") {
    ConnectMintPicker(context: .addMint, route: .constant(nil), onAdd: { _ in }, discoveryAvailable: true)
        .environmentObject(WalletManager())
}
