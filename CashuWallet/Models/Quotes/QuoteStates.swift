import Cdk

// MARK: - Quote States

enum MintQuoteState {
    case pending
    case paid
    case issued
}

enum MeltQuoteState {
    case unpaid
    case pending
    case paid
}

extension MintQuoteState {
    init(_ quoteState: Cdk.QuoteState) {
        switch quoteState {
        case .paid:
            self = .paid
        case .issued:
            self = .issued
        case .unpaid, .pending:
            self = .pending
        }
    }
}

extension MeltQuoteState {
    init(_ quoteState: Cdk.QuoteState) {
        switch quoteState {
        case .unpaid:
            self = .unpaid
        case .pending:
            self = .pending
        case .paid, .issued:
            self = .paid
        }
    }
}
