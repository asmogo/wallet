import Foundation

struct OnchainPaymentObservation: Equatable {
    let txid: String
    let amount: UInt64
    let confirmed: Bool
    let confirmations: Int?

    var statusText: String {
        if let confirmations, confirmations > 0 {
            let suffix = confirmations == 1 ? "" : "s"
            return "Payment confirmed on-chain (\(confirmations) confirmation\(suffix))"
        }

        return confirmed ? "Payment detected on-chain" : "Payment seen in mempool"
    }

}

enum OnchainExplorer {
    private struct ExplorerDescriptor {
        let webBaseURL: String
        let apiBaseURL: String
    }

    private struct ExplorerTransaction: Decodable {
        let txid: String
        let status: ExplorerTransactionStatus
        let vout: [ExplorerTransactionOutput]
    }

    private struct ExplorerBlock: Decodable {
        let height: Int
    }

    private struct ExplorerTransactionStatus: Decodable {
        let confirmed: Bool
        let blockHeight: Int?
        let blockTime: Int?

        private enum CodingKeys: String, CodingKey {
            case confirmed
            case blockHeight = "block_height"
            case blockTime = "block_time"
        }
    }

    private struct ExplorerTransactionOutput: Decodable {
        let scriptpubkeyAddress: String?
        let value: UInt64

        private enum CodingKeys: String, CodingKey {
            case scriptpubkeyAddress = "scriptpubkey_address"
            case value
        }
    }

    static func addressWebURL(for address: String, mintURL: String?) -> URL? {
        guard let descriptor = descriptor(for: address, mintURL: mintURL) else {
            return nil
        }

        let normalizedAddress = PaymentRequestParser.normalizeBitcoinRequest(address)
        return URL(string: "\(descriptor.webBaseURL)/address/\(normalizedAddress)")
    }

    static func transactionWebURL(for txid: String, address: String? = nil, mintURL: String?) -> URL? {
        guard let descriptor = descriptor(for: address, mintURL: mintURL) else {
            return nil
        }

        return URL(string: "\(descriptor.webBaseURL)/tx/\(txid)")
    }

    static func observePayment(
        for address: String,
        mintURL: String?,
        expectedAmount: UInt64,
        createdAfter: Date
    ) async -> OnchainPaymentObservation? {
        guard let descriptor = descriptor(for: address, mintURL: mintURL) else {
            return nil
        }

        let normalizedAddress = PaymentRequestParser.normalizeBitcoinRequest(address)
        guard let url = URL(string: "\(descriptor.apiBaseURL)/address/\(normalizedAddress)/txs") else {
            return nil
        }

        do {
            let request = explorerAPIRequest(url: url)

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                AppLogger.wallet.error("Failed to inspect on-chain address activity: HTTP \(httpResponse.statusCode)")
                return nil
            }

            let transactions = try JSONDecoder().decode([ExplorerTransaction].self, from: data)
            let earliestBlockTime = Int(createdAfter.timeIntervalSince1970)
            let normalizedAddressLowercased = normalizedAddress.lowercased()
            let tipHeight = await currentTipHeight(using: descriptor)

            for transaction in transactions {
                let matchingAmount = transaction.vout
                    .filter { $0.scriptpubkeyAddress?.lowercased() == normalizedAddressLowercased }
                    .map(\.value)
                    .max() ?? 0

                guard matchingAmount >= expectedAmount else {
                    continue
                }

                let status = await freshStatusIfNeeded(for: transaction, using: descriptor)

                if let blockTime = status.blockTime, blockTime < earliestBlockTime {
                    continue
                }

                return OnchainPaymentObservation(
                    txid: transaction.txid,
                    amount: matchingAmount,
                    confirmed: status.confirmed,
                    confirmations: confirmations(
                        for: status,
                        tipHeight: tipHeight
                    )
                )
            }
        } catch {
            AppLogger.wallet.error("Failed to inspect on-chain address activity: \(error)")
        }

        return nil
    }

    private static func descriptor(for address: String?, mintURL: String?) -> ExplorerDescriptor? {
        let mintHost = mintURL.flatMap { URL(string: $0)?.host?.lowercased() }
        if mintHost == "onchain.cashudevkit.org" {
            return ExplorerDescriptor(
                webBaseURL: "https://mutinynet.com",
                apiBaseURL: "https://mutinynet.com/api"
            )
        }

        let normalizedAddress = address.map(PaymentRequestParser.normalizeBitcoinRequest)?.lowercased() ?? ""

        if normalizedAddress.hasPrefix("bc1")
            || normalizedAddress.hasPrefix("1")
            || normalizedAddress.hasPrefix("3") {
            return ExplorerDescriptor(
                webBaseURL: "https://mempool.space",
                apiBaseURL: "https://mempool.space/api"
            )
        }

        if normalizedAddress.hasPrefix("tb1")
            || normalizedAddress.hasPrefix("m")
            || normalizedAddress.hasPrefix("n")
            || normalizedAddress.hasPrefix("2") {
            return ExplorerDescriptor(
                webBaseURL: "https://mempool.space/signet",
                apiBaseURL: "https://mempool.space/signet/api"
            )
        }

        guard mintHost != nil else {
            return nil
        }

        return ExplorerDescriptor(
            webBaseURL: "https://mempool.space/signet",
            apiBaseURL: "https://mempool.space/signet/api"
        )
    }

    private static func currentTipHeight(using descriptor: ExplorerDescriptor) async -> Int? {
        if let url = URL(string: "\(descriptor.apiBaseURL)/blocks/tip/height"),
           let tipHeight = await tipHeight(from: url) {
            return tipHeight
        }

        guard let url = URL(string: "\(descriptor.apiBaseURL)/blocks") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: explorerAPIRequest(url: url))
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                return nil
            }

            let blocks = try JSONDecoder().decode([ExplorerBlock].self, from: data)
            return blocks.map(\.height).max()
        } catch {
            AppLogger.wallet.error("Failed to inspect on-chain tip height: \(error)")
            return nil
        }
    }

    private static func tipHeight(from url: URL) async -> Int? {
        do {
            let (data, response) = try await URLSession.shared.data(for: explorerAPIRequest(url: url))
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                return nil
            }

            return String(data: data, encoding: .utf8)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap(Int.init)
        } catch {
            return nil
        }
    }

    private static func freshStatusIfNeeded(
        for transaction: ExplorerTransaction,
        using descriptor: ExplorerDescriptor
    ) async -> ExplorerTransactionStatus {
        guard transaction.status.confirmed,
              transaction.status.blockHeight == nil,
              let url = URL(string: "\(descriptor.apiBaseURL)/tx/\(transaction.txid)/status") else {
            return transaction.status
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: explorerAPIRequest(url: url))
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                return transaction.status
            }

            return try JSONDecoder().decode(ExplorerTransactionStatus.self, from: data)
        } catch {
            return transaction.status
        }
    }

    private static func explorerAPIRequest(url: URL) -> URLRequest {
        var request = URLRequest(
            url: cacheBustedURL(url),
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 10
        )
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        return request
    }

    private static func cacheBustedURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(
            URLQueryItem(
                name: "_",
                value: String(Int(Date().timeIntervalSince1970 * 1_000))
            )
        )
        components.queryItems = queryItems

        return components.url ?? url
    }

    private static func confirmations(
        for status: ExplorerTransactionStatus,
        tipHeight: Int?
    ) -> Int? {
        guard status.confirmed else {
            return nil
        }

        guard let blockHeight = status.blockHeight,
              let tipHeight,
              tipHeight >= blockHeight else {
            return 1
        }

        return tipHeight - blockHeight + 1
    }
}

/// Mint information
