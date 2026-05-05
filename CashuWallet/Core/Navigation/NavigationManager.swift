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
        
        // Store the token and trigger the receive sheet
        pendingDeepLinkToken = token
        
        // Dismiss any open sheets first
        dismissAll()
        
        // Show the receive token sheet
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.showReceiveTokenSheet = true
        }
    }
}
