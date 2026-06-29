import Cdk

enum PaymentMethodKind: String, CaseIterable, Codable, Hashable {
    case bolt11
    case bolt12
    case onchain

    static func from(_ cdkMethod: Cdk.PaymentMethod) -> PaymentMethodKind? {
        switch cdkMethod {
        case .bolt11:
            return .bolt11
        case .bolt12:
            return .bolt12
        case .onchain:
            return .onchain
        case .custom(let method):
            return method.lowercased() == PaymentMethodKind.onchain.rawValue ? .onchain : nil
        }
    }

    var cdkMethod: Cdk.PaymentMethod {
        switch self {
        case .bolt11:
            return .bolt11
        case .bolt12:
            return .bolt12
        case .onchain:
            return .onchain
        }
    }

    var displayName: String {
        switch self {
        case .bolt11:
            return "BOLT11"
        case .bolt12:
            return "BOLT12"
        case .onchain:
            return "On-chain"
        }
    }

    var symbol: String {
        switch self {
        case .bolt11:
            return "\u{26A1}"
        case .bolt12:
            return "\u{1F517}"
        case .onchain:
            return "\u{20BF}"
        }
    }

    var requestDisplayName: String {
        switch self {
        case .bolt11:
            return "Invoice"
        case .bolt12:
            return "Invoice"
        case .onchain:
            return "Address"
        }
    }

    /// Plain-language title for the receive method picker, in place of the
    /// protocol jargon (`displayName`). Used by the method chip + picker sheet.
    var friendlyTitle: String {
        switch self {
        case .bolt11:
            return "Lightning invoice"
        case .bolt12:
            return "Reusable invoice"
        case .onchain:
            return "On-chain address"
        }
    }

    /// One-line descriptor shown beneath `friendlyTitle` in the picker sheet.
    var friendlyDescriptor: String {
        switch self {
        case .bolt11:
            return "One-time, instant"
        case .bolt12:
            return "Share once, paid many times"
        case .onchain:
            return "Slower, for larger amounts"
        }
    }

    /// Verb-phrase for the create CTA, matching `friendlyTitle`'s language.
    var createActionTitle: String {
        switch self {
        case .bolt11:
            return "Create invoice"
        case .bolt12:
            return "Create invoice"
        case .onchain:
            return "Create address"
        }
    }

    /// Monochrome SF Symbol for the nav-bar method switcher. Distinct from
    /// `symbol` (emoji), which the design system forbids in chrome.
    var navSymbol: String {
        switch self {
        case .bolt11:
            return "bolt.fill"
        case .bolt12:
            return "arrow.2.squarepath"
        case .onchain:
            return "bitcoinsign"
        }
    }

    var sortOrder: Int {
        switch self {
        case .bolt11:
            return 0
        case .bolt12:
            return 1
        case .onchain:
            return 2
        }
    }

    var requiresMintAmount: Bool {
        self != .bolt12 && self != .onchain
    }

    var supportsOptionalMintAmount: Bool {
        self == .bolt12
    }

}

/// Presentation-layer expansion of `PaymentMethodKind` for the *receive* method
/// picker. BOLT12 surfaces a single amountless "Reusable invoice" row — picking
/// it skips the keypad and creates the offer immediately. The `reusableFixed`
/// case is retained (dormant) for the resolved/current mappings but is no longer
/// offered in the picker. Every other rail maps to a single row. UI-only: the
/// service layer still sees a `PaymentMethodKind` plus a nil/non-nil amount.
enum ReceiveMethodOption: Hashable, Identifiable, CaseIterable {
    case lightning        // bolt11
    case reusableFixed    // bolt12, amount entered on the amount screen
    case reusableAny      // bolt12, amountless (sender decides)
    case onchain          // onchain

    var id: Self { self }

    /// Underlying service rail + whether the offer carries no amount.
    var resolved: (method: PaymentMethodKind, isAmountless: Bool) {
        switch self {
        case .lightning:     return (.bolt11, false)
        case .reusableFixed: return (.bolt12, false)
        case .reusableAny:   return (.bolt12, true)
        case .onchain:       return (.onchain, false)
        }
    }

    var method: PaymentMethodKind { resolved.method }
    var isAmountless: Bool { resolved.isAmountless }

    /// True when picking this row should skip the amount screen and create the
    /// request immediately. Only the amountless reusable offer needs no input.
    var autoCreates: Bool { isAmountless }

    /// Plain-language title, mirroring `PaymentMethodKind.friendlyTitle`. Both
    /// reusable rows use distinct titles; `friendlyDescriptor` adds detail.
    var friendlyTitle: String {
        switch self {
        case .lightning:                   return "Lightning invoice"
        case .reusableFixed: return "Reusable invoice"
        case .reusableAny:   return "Reusable invoice"
        case .onchain:                     return "On-chain address"
        }
    }

    /// One-line descriptor beneath the title in the picker.
    var friendlyDescriptor: String {
        switch self {
        case .lightning:     return "One-time, instant"
        case .reusableFixed: return "Fixed amount, paid many times"
        case .reusableAny:   return "Any amount, paid many times"
        case .onchain:       return "Slower, for larger amounts"
        }
    }

    /// Monochrome SF Symbol for the trailing glyph / nav-bar switcher. Both
    /// reusable rows share BOLT12's `arrow.2.squarepath`.
    var navSymbol: String { method.navSymbol }

    /// Verb-phrase CTA, reused on the amount screen for the fixed path.
    var createActionTitle: String { method.createActionTitle }

    /// Ordered picker rows for a set of supported rails. BOLT12 surfaces a single
    /// amountless "Reusable invoice" row (the fixed-amount row was retired); every
    /// other rail contributes one row. Input order is preserved so it tracks
    /// `availableMintMethods`.
    static func options(for methods: [PaymentMethodKind]) -> [ReceiveMethodOption] {
        methods.flatMap { method -> [ReceiveMethodOption] in
            switch method {
            case .bolt11:  return [.lightning]
            case .bolt12:  return [.reusableAny]
            case .onchain: return [.onchain]
            }
        }
    }

    /// The row representing a live (method, isAmountless) pair — used to reflect
    /// the parent's state back into the picker's highlight and to label the
    /// nav-bar switcher.
    static func current(method: PaymentMethodKind, isAmountless: Bool) -> ReceiveMethodOption {
        switch method {
        case .bolt11:  return .lightning
        case .bolt12:  return isAmountless ? .reusableAny : .reusableFixed
        case .onchain: return .onchain
        }
    }
}
