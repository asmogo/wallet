import XCTest

/// Integration tests for wallet operations against real Cashu mints
/// These tests require live mints running (see CI/setup-mints.sh)
class WalletIntegrationTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        app = XCUIApplication()
        
        // Setup launch environment
        app.launchEnvironment = [
            "CI_INTEGRATION_TEST": "1",
            "RESET_WALLET": "1",
            "NUTSHELL_MINT_URL": "http://localhost:3338",
            "CDK_MINT_URL": "http://localhost:3339"
        ]
        
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Onboarding Tests
    
    func testOnboardingCreatesWalletWithMints() throws {
        // Complete onboarding
        let createButton = app.buttons["Create New Wallet"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()
        
        // Wait for onboarding to complete
        let walletView = app.navigationBars["Wallet"]
        XCTAssertTrue(walletView.waitForExistence(timeout: 10))
        
        // Navigate to Mints tab
        let mintsTab = app.tabBars.buttons["Mints"]
        XCTAssertTrue(mintsTab.waitForExistence(timeout: 5))
        mintsTab.tap()
        
        // Add Nutshell mint
        let addMintButton = app.buttons["Add Mint"]
        addMintButton.tap()
        
        let mintUrlField = app.textFields["Mint URL"]
        mintUrlField.tap()
        mintUrlField.typeText("http://localhost:3338")
        
        app.buttons["Add"].tap()
        
        // Wait for mint to be added
        let nutshellMintCell = app.staticTexts["Nutshell Mint"]
        XCTAssertTrue(nutshellMintCell.waitForExistence(timeout: 10))
        
        // Add CDK mint
        addMintButton.tap()
        mintUrlField.tap()
        mintUrlField.typeText("http://localhost:3339")
        app.buttons["Add"].tap()
        
        // Wait for second mint
        let cdkMintCell = app.staticTexts["CDK Mint"]
        XCTAssertTrue(cdkMintCell.waitForExistence(timeout: 10))
    }
    
    // MARK: - Mint Operations Tests
    
    func testMintAndReceiveLightning() throws {
        // Setup: Complete onboarding and add mints (reuse from above)
        try testOnboardingCreatesWalletWithMints()
        
        // Go to Receive tab
        let receiveTab = app.tabBars.buttons["Receive"]
        receiveTab.tap()
        
        // Request Lightning payment
        let lightningButton = app.buttons["Lightning"]
        lightningButton.tap()
        
        let amountField = app.textFields["Amount"]
        amountField.tap()
        amountField.typeText("21")
        
        let requestButton = app.buttons["Request Payment"]
        requestButton.tap()
        
        // Wait for QR code
        let qrCode = app.images["QR Code"]
        XCTAssertTrue(qrCode.waitForExistence(timeout: 5))
        
        // The invoice should be paid by the fake mint
        // Wait for success
        let successMessage = app.staticTexts["Payment Received"]
        XCTAssertTrue(successMessage.waitForExistence(timeout: 15))
        
        // Check balance updated
        let balanceText = app.staticTexts["21 sats"]
        XCTAssertTrue(balanceText.exists)
    }
    
    // MARK: - Token Operations Tests
    
    func testCreateAndRedeemToken() throws {
        // Setup: Complete onboarding and add mint
        try testMintAndReceiveLightning()
        
        // Go to Send tab
        let sendTab = app.tabBars.buttons["Send"]
        sendTab.tap()
        
        // Create token
        let tokenButton = app.buttons["Create Token"]
        tokenButton.tap()
        
        let amountField = app.textFields["Amount"]
        amountField.tap()
        amountField.typeText("10")
        
        let createButton = app.buttons["Create"]
        createButton.tap()
        
        // Wait for token to be displayed
        let tokenField = app.textFields["Token"]
        XCTAssertTrue(tokenField.waitForExistence(timeout: 5))
        
        // Copy token
        let copyButton = app.buttons["Copy"]
        copyButton.tap()
        
        // Go to Receive tab and redeem token
        let receiveTab = app.tabBars.buttons["Receive"]
        receiveTab.tap()
        
        let tokenReceiveButton = app.buttons["Cashu Token"]
        tokenReceiveButton.tap()
        
        let tokenInputField = app.textFields["Paste Token"]
        tokenInputField.tap()
        
        // Paste from clipboard
        app.typeText(tokenField.value as? String ?? "")
        
        let redeemButton = app.buttons["Redeem"]
        redeemButton.tap()
        
        // Wait for success
        let successMessage = app.staticTexts["Token Redeemed"]
        XCTAssertTrue(successMessage.waitForExistence(timeout: 10))
    }
}
