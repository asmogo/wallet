import SwiftUI

// MARK: - Currency Flag

enum CurrencyFlag {
    /// ISO-4217 currency code → regional-indicator flag emoji. The first two
    /// letters of every supported code are a valid ISO-3166 country (USD→US,
    /// GBP→GB, …); EUR→EU yields the 🇪🇺 flag.
    static func emoji(for code: String) -> String {
        let base: UInt32 = 0x1F1E6      // regional indicator "A"
        let letterA: UInt32 = 0x41      // ASCII "A"
        var result = ""
        for scalar in code.prefix(2).uppercased().unicodeScalars {
            guard scalar.value >= letterA, scalar.value <= letterA + 25,
                  let flagScalar = Unicode.Scalar(base + scalar.value - letterA) else { continue }
            result.unicodeScalars.append(flagScalar)
        }
        return result
    }
}

// MARK: - Currency Avatar

/// Circular avatar for a currency row — a flag emoji clipped into the same circle
/// the app uses for mint avatars (`MintAvatarView`). DESIGN.md carve-out: emoji is
/// permitted *only* here, contained inside this avatar. The "Off · sats only" row
/// passes a monochrome SF Symbol instead of a flag.
private struct CurrencyAvatar: View {
    enum Glyph {
        case flag(String)     // emoji
        case symbol(String)   // SF Symbol name
    }

    let glyph: Glyph
    var size: CGFloat = 36

    var body: some View {
        avatar
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var avatar: some View {
        switch glyph {
        case .flag(let emoji):
            // Oversize the emoji so the flag rectangle fills the circle
            // edge-to-edge (Family idiom); the sides spill out and get clipped.
            Text(emoji)
                .font(.system(size: size * 1.85))
                .fixedSize()
        case .symbol(let name):
            Circle()
                .fill(.quaternary)
                .overlay(
                    Image(systemName: name)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.secondary)
                )
        }
    }
}

// MARK: - Currency Picker Sheet

/// Bottom-sheet currency selector. Owns fiat display end-to-end: picking a
/// currency turns fiat on (`showFiatBalance = true`) and starts the Coinbase
/// price fetch; "Off · sats only" turns it off. Mirrors the row + sheet idiom of
/// `CashuRequestMintPickerSheet`.
struct CurrencyPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var priceService = PriceService.shared

    var body: some View {
        NavigationStack {
            List {
                Button(action: selectOff) {
                    HStack(spacing: 12) {
                        CurrencyAvatar(glyph: .symbol("bitcoinsign"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Off")
                                .font(.body.weight(.medium))
                            Text("Sats only")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !settings.showFiatBalance {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .listRowSeparator(.hidden)
                .buttonStyle(.plain)
                .accessibilityLabel("Off, sats only")
                .accessibilityAddTraits(settings.showFiatBalance ? [] : [.isSelected])

                ForEach(SettingsManager.supportedFiatCurrencies, id: \.self) { code in
                    Button { select(code) } label: {
                        HStack(spacing: 12) {
                            CurrencyAvatar(glyph: .flag(CurrencyFlag.emoji(for: code)))
                            Text(code)
                                .font(.body.weight(.medium))
                            Spacer()
                            if isSelected(code) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .listRowSeparator(.hidden)
                    .buttonStyle(.plain)
                    .accessibilityLabel(code)
                    .accessibilityAddTraits(isSelected(code) ? [.isSelected] : [])
                }
            }
            .listStyle(.plain)
            .navigationTitle("Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if settings.showFiatBalance {
                    priceFooter
                }
            }
        }
    }

    // MARK: - Price footer

    private var priceFooter: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BTC Price")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if priceService.btcPriceUSD > 0 {
                    Text(formattedPrice)
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                } else {
                    Text("Loading…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let lastUpdated = priceService.lastUpdated, priceService.btcPriceUSD > 0 {
                Text("Updated \(relativeTime(lastUpdated))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button(action: { Task { await priceService.fetchPrice() } }) {
                if priceService.isFetching {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .disabled(priceService.isFetching)
            .accessibilityLabel("Refresh price")
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Selection

    private func isSelected(_ code: String) -> Bool {
        settings.showFiatBalance && settings.bitcoinPriceCurrency == code
    }

    /// Set the code *before* enabling so the fetch that enabling triggers uses
    /// the right currency (and the `didSet` guards avoid a double fetch).
    private func select(_ code: String) {
        HapticFeedback.selection()
        settings.bitcoinPriceCurrency = code
        settings.showFiatBalance = true
        dismiss()
    }

    private func selectOff() {
        HapticFeedback.selection()
        settings.showFiatBalance = false
        dismiss()
    }

    private var formattedPrice: String {
        // `.presentation(.narrow)` yields the bare symbol ("$", not "US$").
        priceService.btcPriceUSD.formatted(
            .currency(code: settings.bitcoinPriceCurrency).presentation(.narrow).precision(.fractionLength(0))
        )
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
