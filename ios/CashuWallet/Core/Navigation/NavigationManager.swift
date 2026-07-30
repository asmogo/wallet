import SwiftUI

// MARK: - Navigation Manager

/// Manages navigation state and sheet presentations across the app.
/// Handles deep link processing for cashu: URL scheme.
class NavigationManager: ObservableObject {
    
    // MARK: - Sheet State
    
    @Published var showReceiveSheet = false
    @Published var showSendSheet = false
    @Published var showAddMintSheet = false
    @Published var showBackupSheet = false
    @Published var showScannerSheet = false
    
    /// Token received from deep link (cashu: URL)
    @Published var pendingDeepLinkToken: String?
    @Published var pendingMeltInvoice: String?
    @Published var showReceiveTokenSheet = false
    
    // MARK: - Public Methods
    
    /// Dismiss all sheets
    func dismissAll() {
        showReceiveSheet = false
        showSendSheet = false
        showAddMintSheet = false
        showBackupSheet = false
        showScannerSheet = false
        showReceiveTokenSheet = false
        pendingMeltInvoice = nil
    }
    
    /// Handle incoming cashu: URL
    func handleDeepLink(url: URL) {
        // Parse cashu: URL scheme
        // Format: cashu:cashuA... or cashu://cashuA...
        guard url.scheme == "cashu" else { return }
        
        var token: String
        
        if let host = url.host {
            // Format: cashu://token
            token = host + url.path
        } else {
            // Format: cashu:token
            token = url.absoluteString.replacingOccurrences(of: "cashu:", with: "")
        }
        
        // Clean up any URL encoding
        token = token.removingPercentEncoding ?? token
        
        // Validate it looks like a cashu token
        guard TokenParser.isCashuDeepLinkToken(token) else {
            print("Invalid cashu token in deep link: \(token.prefix(20))...")
            return
        }
        
        // Store the token before presentation. ContentView waits for the wallet
        // runtime before presenting this payment surface.
        pendingDeepLinkToken = token
        
        // Dismiss any open sheets first
        dismissAll()
        
    }

    /// Presents a queued Cashu token only after the encrypted wallet runtime is
    /// available. Re-check the token after the presentation delay so a newer
    /// deep link cannot present stale content.
    func presentPendingReceiveTokenIfReady(isRuntimeReady: Bool) {
        guard isRuntimeReady,
              !showReceiveTokenSheet,
              let token = pendingDeepLinkToken else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self,
                  self.pendingDeepLinkToken == token,
                  !self.showReceiveTokenSheet else { return }
            self.showReceiveTokenSheet = true
        }
    }
}
