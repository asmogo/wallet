import SwiftUI
import UIKit
import XCTest
@testable import CashuWallet

@MainActor
final class AppLockPresentationTests: XCTestCase {
    func testLockProtectsPaymentAndNestedSettingsPresentationsWithoutLosingDraft() async throws {
        try await exercisePresentation(style: .pageSheet, nested: true)
    }

    func testLockProtectsFullScreenPaymentAndShowsItsSettledStateOnResume() async throws {
        try await exercisePresentation(style: .fullScreen, nested: false)
    }

    private func exercisePresentation(style: UIModalPresentationStyle, nested: Bool) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let originalKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        var enabled = false
        var time = Date(timeIntervalSince1970: 100)
        var authSucceeds = false
        let manager = AppLockManager(enabled: { enabled }, available: { true }, now: { time }, evaluation: { _ in authSucceeds })
        let protector = AppLockWindowController(manager: manager)
        protector.attach(to: window)
        defer {
            protector.detach()
            window.isHidden = true
            originalKeyWindow?.makeKey()
        }
        let payment = UIViewController()
        payment.modalPresentationStyle = style
        let draft = UITextField(frame: CGRect(x: 20, y: 80, width: 220, height: 44))
        draft.text = "Draft payment 21"
        payment.view.addSubview(draft)
        await present(payment, from: root)
        if nested {
            let settings = UIViewController()
            settings.modalPresentationStyle = .pageSheet
            await present(settings, from: payment)
        }
        enabled = true
        // UIKit's synchronous notification must cover the app-switcher frame.
        NotificationCenter.default.post(name: UIScene.willDeactivateNotification, object: scene)
        let protection = try XCTUnwrap(protector.protectionWindow)
        XCTAssertFalse(protection.isHidden)
        XCTAssertTrue(protection.windowLevel > window.windowLevel)
        XCTAssertTrue(window.accessibilityElementsHidden)
        XCTAssertFalse(manager.isLocked, "Short switches retain the existing grace period")
        time += 31
        manager.appBecameActive()
        XCTAssertTrue(manager.isLocked)
        // Let the initial automatic attempt finish, then explicitly retry/cancel.
        try await Task.sleep(for: .milliseconds(100))
        let cancelled = await manager.authenticate()
        XCTAssertFalse(cancelled)
        XCTAssertFalse(protection.isHidden)
        manager.appResignedActive()
        time += 31
        manager.appBecameActive()
        XCTAssertTrue(protector.protectionWindow === protection)
        XCTAssertTrue(root.presentedViewController === payment)
        XCTAssertEqual(draft.text, "Draft payment 21")
        if nested { XCTAssertNotNil(payment.presentedViewController) }
        // Wallet work can settle under the gate without replacing the screen.
        draft.text = "Payment complete"
        authSucceeds = true
        let unlocked = await manager.authenticate()
        XCTAssertTrue(unlocked)
        XCTAssertTrue(protection.isHidden)
        XCTAssertFalse(window.accessibilityElementsHidden)
        XCTAssertTrue(root.presentedViewController === payment)
        XCTAssertEqual(draft.text, "Payment complete")
    }

    func testRepeatedBackgroundNotificationsDoNotExtendTheGracePeriod() {
        var time = Date(timeIntervalSince1970: 100)
        var enabled = false
        let manager = AppLockManager(enabled: { enabled }, available: { true }, now: { time }, evaluation: { _ in false })
        enabled = true
        manager.appResignedActive()
        time += 20
        manager.appResignedActive()
        time += 11
        manager.appBecameActive()
        XCTAssertTrue(manager.isLocked)
    }

    private func present(_ controller: UIViewController, from presenter: UIViewController) async {
        await withCheckedContinuation { continuation in
            presenter.present(controller, animated: false) { continuation.resume() }
        }
    }
}
