import Combine
import SwiftUI
import UIKit

/// Anchors protection to this SwiftUI scene, including its presented controllers.
struct AppLockWindowBridge: UIViewRepresentable {
    let manager: AppLockManager

    func makeCoordinator() -> AppLockWindowController { AppLockWindowController(manager: manager) }
    func makeUIView(context: Context) -> AppLockSceneProbe {
        let view = AppLockSceneProbe()
        view.onWindow = { [weak coordinator = context.coordinator] in coordinator?.attach(to: $0) }
        return view
    }
    func updateUIView(_ uiView: AppLockSceneProbe, context: Context) {}
    static func dismantleUIView(_ uiView: AppLockSceneProbe, coordinator: AppLockWindowController) {
        coordinator.detach()
    }
}

final class AppLockSceneProbe: UIView {
    var onWindow: ((UIWindow) -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window { onWindow?(window) }
    }
}

@MainActor
final class AppLockWindowController {
    private let manager: AppLockManager
    private weak var sourceWindow: UIWindow?
    private weak var previousKeyWindow: UIWindow?
    private var previousAccessibilityHidden = false
    private var subscriptions = Set<AnyCancellable>()
    private(set) var protectionWindow: UIWindow?

    init(manager: AppLockManager) { self.manager = manager }

    func attach(to source: UIWindow) {
        guard sourceWindow !== source, let scene = source.windowScene else { return }
        detach()
        sourceWindow = source
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .systemBackground
        let host = UIHostingController(rootView: AppLockWindowContent(manager: manager))
        host.view.accessibilityViewIsModal = true
        window.rootViewController = host
        protectionWindow = window
        manager.$isLocked.combineLatest(manager.$isObscured)
            .sink { [weak self] locked, obscured in self?.setCovered(locked || obscured) }
            .store(in: &subscriptions)
        // UIKit posts these synchronously before scene snapshots. SwiftUI's
        // scenePhase remains responsible for service lifecycle, not privacy timing.
        NotificationCenter.default.publisher(for: UIScene.willDeactivateNotification, object: scene)
            .sink { [weak self] _ in self?.manager.appResignedActive() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIScene.didActivateNotification, object: scene)
            .sink { [weak self] _ in self?.manager.appBecameActive() }
            .store(in: &subscriptions)
    }

    private func setCovered(_ covered: Bool) {
        guard let window = protectionWindow, let source = sourceWindow else { return }
        if covered {
            if window.isHidden {
                previousKeyWindow = source.windowScene?.windows.first(where: \.isKeyWindow)
                previousAccessibilityHidden = source.accessibilityElementsHidden
                source.accessibilityElementsHidden = true
                window.makeKeyAndVisible()
                // No fade: the first inactive frame must already be opaque.
                window.layoutIfNeeded()
                UIAccessibility.post(notification: .screenChanged, argument: window.rootViewController?.view)
            }
        } else if !window.isHidden {
            window.isHidden = true
            source.accessibilityElementsHidden = previousAccessibilityHidden
            (previousKeyWindow ?? source).makeKey()
            previousKeyWindow = nil
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }

    func detach() {
        subscriptions.removeAll()
        setCovered(false)
        protectionWindow?.rootViewController = nil
        protectionWindow = nil
        sourceWindow = nil
    }
}

private struct AppLockWindowContent: View {
    @ObservedObject var manager: AppLockManager
    var body: some View {
        Group {
            if manager.isLocked { AppLockView().environmentObject(manager) }
            else { PrivacyCoverView() }
        }
        .transaction { $0.disablesAnimations = true }
    }
}
