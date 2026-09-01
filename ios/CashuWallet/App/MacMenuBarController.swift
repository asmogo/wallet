#if os(macOS)
import AppKit
import SwiftUI

extension Notification.Name {
    static let cashuMenuBarPanelDidOpen = Notification.Name("cashu.menuBar.panelDidOpen")
    static let cashuMenuBarPanelDidClose = Notification.Name("cashu.menuBar.panelDidClose")
    static let cashuMenuBarDidReceiveURL = Notification.Name("cashu.menuBar.didReceiveURL")
}

// MARK: - Panel
//
// Why an NSPanel and not `MenuBarExtra(.window)`.
//
// MenuBarExtra is five lines and would have been the obvious choice, but its
// window-style content is hosted in a popover, and a popover is not a window
// that can present a sheet. This app presents 51 sheets across 17 files — the
// entire send, receive, mint and settings surface. Hosting the root in a real
// panel keeps every one of them working, which makes the "manual" route the
// smaller change by a wide margin.

/// A borderless panel that can still take key focus.
///
/// Both overrides are load-bearing. A borderless window refuses key status by
/// default, and without it every text field in the wallet — amounts, mint URLs,
/// the twelve-word restore — would silently swallow keystrokes.
private final class MenuBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Controller

@MainActor
final class MacMenuBarController: NSObject {
    /// Phone-shaped, because the UI inside it is. Tall enough for the wallet
    /// home without scrolling, short enough to fit a laptop screen under the
    /// menu bar.
    private static let panelSize = NSSize(width: 400, height: 700)

    private var statusItem: NSStatusItem?
    private var panel: MenuBarPanel?
    private var outsideClickMonitor: Any?

    var isPanelVisible: Bool { panel?.isVisible == true }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "bitcoinsign.circle",
            accessibilityDescription: "Cashu Wallet"
        )
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        // Ask for both edges so a right-click can open the quit menu without
        // stealing the plain left-click that toggles the wallet.
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    // MARK: Click handling

    @objc private func statusItemClicked() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true

        if isRightClick {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func showContextMenu() {
        guard let button = statusItem?.button else { return }

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Quit Cashu",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        // Popped up directly rather than assigned to `statusItem.menu`. Assigning
        // it would make the menu own *every* click, including the left click that
        // is supposed to open the wallet, and the assign/click/unassign dance
        // that avoids that is re-entrant enough to drop clicks.
        hidePanel()
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.minY - 6),
            in: button
        )
    }

    func togglePanel() {
        if isPanelVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    // MARK: Show / hide

    private func showPanel() {
        let panel = panel ?? makePanel()
        self.panel = panel

        positionUnderStatusItem(panel)
        // An accessory app is not frontmost by default, so the panel would open
        // behind whatever the user was in and never take focus.
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.makeKeyAndOrderFront(nil)
        startWatchingForOutsideClicks()
        NotificationCenter.default.post(name: .cashuMenuBarPanelDidOpen, object: nil)
    }

    func hidePanel() {
        guard let panel, panel.isVisible else { return }
        stopWatchingForOutsideClicks()
        panel.orderOut(nil)
        NotificationCenter.default.post(name: .cashuMenuBarPanelDidClose, object: nil)
    }

    private func makePanel() -> MenuBarPanel {
        let panel = MenuBarPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Chromeless, but still a titled window underneath — that is what keeps
        // it sheet-capable while looking like a popover.
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovable = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // The frame is on the SwiftUI root, not just the window.
        //
        // NSHostingView negotiates its size with the window, and this UI was
        // written for a phone: give it no width constraint and it reports a
        // small ideal width, the window shrinks to that, and the wallet renders
        // as a sliver. Pinning the root fixes the negotiation at the size the
        // layout was designed for.
        let host = NSHostingView(
            rootView: AppRootView()
                .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        )
        host.frame = NSRect(origin: .zero, size: Self.panelSize)
        panel.contentView = host
        panel.setContentSize(Self.panelSize)
        panel.contentMinSize = Self.panelSize
        panel.contentMaxSize = Self.panelSize

        return panel
    }

    private func positionUnderStatusItem(_ panel: NSPanel) {
        guard
            let button = statusItem?.button,
            let buttonWindow = button.window
        else { return }

        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let size = panel.frame.size

        var x = buttonRect.midX - size.width / 2
        let y = buttonRect.minY - size.height - 6

        // Keep it on screen when the status item sits near the right edge.
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: Dismissal

    /// Closes the panel on a click anywhere else, the way a menu behaves.
    ///
    /// A global monitor only sees events destined for *other* applications, so
    /// clicks inside the wallet never reach it and cannot dismiss it by
    /// accident. Sheets belong to the panel, so they are safe too.
    private func startWatchingForOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.hidePanel() }
        }
    }

    private func stopWatchingForOutsideClicks() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }
}

// MARK: - Delegate

@MainActor
final class MacMenuBarAppDelegate: NSObject, NSApplicationDelegate {
    private let controller = MacMenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt and braces with LSUIElement in Info.plist: if the app is ever
        // launched in a context where the plist key is not honoured, this still
        // keeps it out of the Dock and the app switcher.
        NSApp.setActivationPolicy(.accessory)
        controller.install()
    }

    /// `cashu:` links. Routed through a notification because the wallet's
    /// NavigationManager lives inside the SwiftUI tree, not out here.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        controller.togglePanelIfNeeded()
        NotificationCenter.default.post(
            name: .cashuMenuBarDidReceiveURL,
            object: url
        )
    }
}

private extension MacMenuBarController {
    /// Opens the panel for an incoming link without closing it if it is already
    /// up — a deep link should never toggle the wallet shut.
    func togglePanelIfNeeded() {
        guard !isPanelVisible else { return }
        togglePanel()
    }
}
#endif
