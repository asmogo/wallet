import XCTest
@testable import CashuWallet

@MainActor
final class LightningAddressResolverTests: XCTestCase {
    private let amount: UInt64 = 250_000_000
    private let invoice = "lnbc2500u1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4jsxqzpu9qrsgquk0rl77nj30yxdy8j9vdx85fkpmdla2087ne0xh8nhedh8w27kyke0lp53ut353s06fv3qfegext0eh0ymjpf39tuven09sam30g4vgpfna3rh"

    func testSameHostAndDelegatedCallbacksPreserveQueryAndReplaceAmounts() async throws {
        for host in ["example.com", "pay.example.net"] {
            var urls: [URL] = []
            let resolved = try await resolve(callback: "https://\(host)/invoice?amount=1&Amount=2&memo=coffee") {
                urls.append($0)
            }
            XCTAssertEqual(resolved, invoice)
            let callback = try XCTUnwrap(URLComponents(url: XCTUnwrap(urls.last), resolvingAgainstBaseURL: false))
            XCTAssertEqual(callback.host, host)
            XCTAssertEqual(callback.queryItems?.filter { $0.name.lowercased() == "amount" }, [URLQueryItem(name: "amount", value: String(amount))])
            XCTAssertTrue(callback.queryItems?.contains(URLQueryItem(name: "memo", value: "coffee")) == true)
        }
    }

    func testUnsafeCallbacksAreRejectedBeforeRequestingInvoice() async {
        for callback in ["http://pay.example.net/invoice", "https://@pay.example.net/invoice", "https:///invoice", "https://bad host/invoice", "https://user:pass@pay.example.net/invoice", "https://pay.example.net/invoice#fragment", "not a URL"] {
            var requests = 0
            do {
                _ = try await resolve(callback: callback) { _ in requests += 1 }
                XCTFail("Unsafe callback accepted")
            } catch {
                XCTAssertEqual(requests, 1)
                XCTAssertFalse((error as? LightningAddressResolverError)?.indicatesNoLnurlPayEndpoint ?? true)
            }
        }
    }

    func testInvalidOrAmountMismatchedInvoiceCannotTriggerFallback() async {
        for (response, requested) in [("invalid", amount), (invoice, amount - 1)] {
            do {
                _ = try await resolve(callback: "https://pay.example.net/invoice", responseInvoice: response, requested: requested)
                XCTFail("Invalid invoice accepted")
            } catch {
                XCTAssertFalse((error as? LightningAddressResolverError)?.indicatesNoLnurlPayEndpoint ?? true)
            }
        }
    }

    func testMissingEndpointStillAllowsBip353Fallback() async {
        do {
            _ = try await LightningAddressResolver.resolveBolt11Invoice(address: "alice@example.com", amountMsat: amount) { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            }
            XCTFail("Missing endpoint accepted")
        } catch {
            XCTAssertTrue((error as? LightningAddressResolverError)?.indicatesNoLnurlPayEndpoint == true)
        }
    }

    private func resolve(
        callback: String, responseInvoice: String? = nil, requested: UInt64? = nil,
        observe: (URL) -> Void = { _ in }
    ) async throws -> String {
        var calls = 0
        return try await LightningAddressResolver.resolveBolt11Invoice(address: "alice@example.com", amountMsat: requested ?? amount) { request in
            let url = try XCTUnwrap(request.url)
            observe(url)
            calls += 1
            let body: [String: Any] = calls == 1
                ? ["tag": "payRequest", "callback": callback, "minSendable": 1, "maxSendable": 1_000_000_000]
                : ["pr": responseInvoice ?? self.invoice]
            return (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
}
