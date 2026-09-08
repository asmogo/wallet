import SwiftUI
import UIKit

extension EnvironmentValues {
    @Entry var activitySheetSizing: ((CGFloat?) -> Void)? = nil
    @Entry var dismissActivitySheet: (() -> Void)? = nil
}

extension View {
    /// History alone uses an edge-attached phone presentation. iPad keeps the
    /// system's floating sheet, including its native sizing and corner treatment.
    @ViewBuilder
    func activitySheet<Item: Identifiable, Sheet: View>(
        item: Binding<Item?>,
        onDismissalStateChanged: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder content: @escaping (Item) -> Sheet
    ) -> some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            background {
                ActivitySheetPresenter(item: item, onDismissalStateChanged: onDismissalStateChanged,
                                       sheetContent: content)
            }
        } else {
            sheet(item: item) { value in
                content(value).observeBottomSheetDismissal(onDismissalStateChanged)
            }
        }
    }
}

/// Owns the presentation geometry through public UIKit APIs. No changes to
/// UIKit's private sheet subviews, global appearance, or unrelated presentations.
private struct ActivitySheetPresenter<Item: Identifiable, Sheet: View>: UIViewControllerRepresentable {
    @Binding var item: Item?
    let onDismissalStateChanged: (Bool) -> Void
    let sheetContent: (Item) -> Sheet

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.onAppear = { [weak coordinator = context.coordinator, weak anchor] in
            if let anchor { coordinator?.synchronize(from: anchor) }
        }
        return anchor
    }

    func updateUIViewController(_ anchor: Anchor, context: Context) {
        let coordinator = context.coordinator
        coordinator.selection = $item
        coordinator.currentItem = item
        coordinator.onDismissalStateChanged = onDismissalStateChanged
        coordinator.makeContent = { value in
            AnyView(sheetContent(value)
                .environment(\.activitySheetSizing, { [weak coordinator] height in
                    coordinator?.host?.preferredContentSize.height = height ?? 0
                })
                .environment(\.dismissActivitySheet, { [weak coordinator] in
                    coordinator?.dismissPresentation(animated: true)
                }))
        }
        coordinator.synchronize(from: anchor)
    }

    static func dismantleUIViewController(_ anchor: Anchor, coordinator: Coordinator) {
        anchor.onAppear = nil
        coordinator.dismissPresentation(animated: false)
    }

    final class Anchor: UIViewController {
        var onAppear: (() -> Void)?
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onAppear?()
        }
    }

    final class Host: UIViewController {
        private let content: UIHostingController<AnyView>
        var rootView: AnyView {
            get { content.rootView }
            set { content.rootView = newValue }
        }
        init(rootView: AnyView) {
            content = UIHostingController(rootView: rootView)
            super.init(nibName: nil, bundle: nil)
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func viewDidLoad() {
            super.viewDidLoad()
            // UIKit owns the modal lifecycle; SwiftUI owns only its child content.
            // This also keeps SwiftUI geometry stable when dismissal is cancelled.
            addChild(content)
            content.view.backgroundColor = .clear
            content.view.frame = view.bounds
            content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(content.view)
            content.didMove(toParent: self)
        }
        var onDismissalBegan: (() -> Void)?
        var onDismissed: (() -> Void)?
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if isBeingDismissed { onDismissalBegan?() }
        }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if isBeingDismissed || presentingViewController == nil { onDismissed?() }
        }
    }

    final class Coordinator: NSObject, UIViewControllerTransitioningDelegate {
        var selection: Binding<Item?>?
        var currentItem: Item?
        var onDismissalStateChanged: (Bool) -> Void = { _ in }
        var makeContent: ((Item) -> AnyView)?
        var host: Host?
        var presentedID: Item.ID?
        private var dismissalReported = false

        func synchronize(from anchor: Anchor) {
            guard anchor.viewIfLoaded?.window != nil else { return }
            guard let value = currentItem else {
                if let host, !host.isBeingDismissed { dismissPresentation(animated: true) }
                return
            }
            if let host {
                if presentedID != value.id {
                    if !host.isBeingDismissed { dismissPresentation(animated: true) }
                    return
                }
                if !host.isBeingDismissed, let content = makeContent?(value) { host.rootView = content }
                return
            }
            guard anchor.presentedViewController == nil, let content = makeContent?(value) else { return }
            let controller = Host(rootView: content)
            controller.view.backgroundColor = .clear
            controller.modalPresentationStyle = .custom
            controller.transitioningDelegate = self
            controller.onDismissalBegan = { [weak self] in self?.reportDismissal() }
            controller.onDismissed = { [weak self, weak anchor] in
                guard let self else { return }
                if self.selection?.wrappedValue?.id == self.presentedID {
                    self.selection?.wrappedValue = nil
                    self.currentItem = nil
                }
                self.host = nil
                self.presentedID = nil
                self.dismissalReported = false
                self.onDismissalStateChanged(false)
                if let anchor { self.synchronize(from: anchor) }
            }
            host = controller
            presentedID = value.id
            anchor.present(controller, animated: true)
        }

        func reportDismissal() {
            guard !dismissalReported else { return }
            dismissalReported = true
            onDismissalStateChanged(true)
        }

        func dismissPresentation(animated: Bool) {
            // Dismiss the receipt and any child flow together, including the
            // receive-token cover that can still be closing after a claim.
            host?.presentingViewController?.dismiss(animated: animated)
        }

        func cancelDismissal() {
            dismissalReported = false
            onDismissalStateChanged(false)
        }

        func presentationController(forPresented presented: UIViewController,
                                    presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
            let controller = Presentation(presentedViewController: presented, presenting: presenting)
            controller.owner = self
            return controller
        }

        func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                                 source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
            Transition(presenting: true)
        }

        func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
            Transition(presenting: false)
        }
    }

    final class Presentation: UIPresentationController, UIGestureRecognizerDelegate {
        weak var owner: Coordinator?
        private let dimmer = UIView()
        private weak var scrollingView: UIScrollView?
        private var scrollWasEnabled = true
        private var dragOrigin: CGFloat = 0
        private var settlingAnimator: UIViewPropertyAnimator?

        override var shouldRemovePresentersView: Bool { false }
        override var frameOfPresentedViewInContainerView: CGRect {
            guard let container = containerView else { return .zero }
            let maximum = container.bounds.height - container.safeAreaInsets.top - 8
            let preferred = presentedViewController.preferredContentSize.height
            let height = preferred > 0
                ? min(preferred + container.safeAreaInsets.bottom, maximum)
                : maximum
            return CGRect(x: 0, y: container.bounds.maxY - height, width: container.bounds.width, height: height)
        }

        override func presentationTransitionWillBegin() {
            guard let container = containerView, let surface = presentedView else { return }
            dimmer.frame = container.bounds
            dimmer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.32)
            dimmer.alpha = 0
            dimmer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissSheet)))
            dimmer.isAccessibilityElement = false
            container.insertSubview(dimmer, at: 0)
            surface.layer.cornerRadius = 32
            surface.layer.cornerCurve = .continuous
            surface.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            surface.clipsToBounds = true
            surface.accessibilityViewIsModal = true
            let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
            pan.delegate = self
            surface.addGestureRecognizer(pan)
            presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in self.dimmer.alpha = 1 })
        }

        override func dismissalTransitionWillBegin() {
            presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in self.dimmer.alpha = 0 })
        }

        override func presentationTransitionDidEnd(_ completed: Bool) {
            if !completed { dimmer.removeFromSuperview() }
        }

        override func dismissalTransitionDidEnd(_ completed: Bool) {
            if completed { dimmer.removeFromSuperview() }
            else { dimmer.alpha = 1 }
        }

        override func containerViewWillLayoutSubviews() {
            super.containerViewWillLayoutSubviews()
            // Bounds/center remain valid while an interactive transform is active.
            let frame = frameOfPresentedViewInContainerView
            presentedView?.bounds.size = frame.size
            presentedView?.center = CGPoint(x: frame.midX, y: frame.midY)
        }

        override func preferredContentSizeDidChange(forChildContentContainer container: UIContentContainer) {
            super.preferredContentSizeDidChange(forChildContentContainer: container)
            containerView?.setNeedsLayout()
        }

        @objc private func dismissSheet() { presentedViewController.dismiss(animated: true) }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let surface = presentedView,
                  !presentedViewController.isBeingDismissed, presentedViewController.presentedViewController == nil else { return false }
            let velocity = pan.velocity(in: surface)
            guard velocity.y > abs(velocity.x) else { return false }
            var touched = surface.hitTest(pan.location(in: surface), with: nil)
            scrollingView = nil
            while let view = touched, view !== surface {
                if let scroll = view as? UIScrollView {
                    guard scroll.contentOffset.y <= -scroll.adjustedContentInset.top + 1 else { return false }
                    scrollingView = scroll
                    break
                }
                touched = view.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            otherGestureRecognizer === scrollingView?.panGestureRecognizer
        }

        @objc private func drag(_ pan: UIPanGestureRecognizer) {
            guard let owner, let surface = presentedView else { return }
            let distance = max(surface.bounds.height, 1)
            let translation = max(0, dragOrigin + pan.translation(in: surface).y)
            let progress = min(1, translation / distance)
            switch pan.state {
            case .began:
                settlingAnimator?.stopAnimation(false)
                settlingAnimator?.finishAnimation(at: .current)
                settlingAnimator = nil
                dragOrigin = surface.transform.ty
                scrollWasEnabled = scrollingView?.isScrollEnabled ?? true
                scrollingView?.isScrollEnabled = false
                owner.reportDismissal()
            case .changed:
                surface.transform = CGAffineTransform(translationX: 0, y: translation)
                dimmer.alpha = 1 - progress
            case .ended, .cancelled, .failed:
                scrollingView?.isScrollEnabled = scrollWasEnabled
                scrollingView = nil
                if pan.state == .ended && (progress > 0.3 || pan.velocity(in: surface).y > 900) {
                    // Commit the modal dismissal only after release. A short
                    // drag never sends SwiftUI through a cancelled disappearance.
                    dismissSheet()
                } else {
                    owner.cancelDismissal()
                    let animator = UIViewPropertyAnimator(duration: 0.25, dampingRatio: 1) {
                        surface.transform = .identity
                        self.dimmer.alpha = 1
                    }
                    animator.addCompletion { [weak self] _ in self?.settlingAnimator = nil }
                    settlingAnimator = animator
                    animator.startAnimation()
                }
            default: break
            }
        }
    }

    final class Transition: NSObject, UIViewControllerAnimatedTransitioning {
        let presenting: Bool
        private var animator: UIViewPropertyAnimator?
        init(presenting: Bool) { self.presenting = presenting }
        func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval {
            UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.35
        }
        func animateTransition(using context: UIViewControllerContextTransitioning) {
            interruptibleAnimator(using: context).startAnimation()
        }
        func interruptibleAnimator(using context: UIViewControllerContextTransitioning) -> UIViewImplicitlyAnimating {
            if let animator { return animator }
            let key: UITransitionContextViewControllerKey = presenting ? .to : .from
            let controller = context.viewController(forKey: key)!
            let surface = context.view(forKey: presenting ? .to : .from)!
            if presenting {
                context.containerView.addSubview(surface)
                surface.frame = controller.presentationController?.frameOfPresentedViewInContainerView ?? context.finalFrame(for: controller)
            }
            let reduceMotion = UIAccessibility.isReduceMotionEnabled
            let offscreen = CGAffineTransform(translationX: 0, y: surface.bounds.height)
            if presenting {
                surface.transform = reduceMotion ? .identity : offscreen
                surface.alpha = reduceMotion ? 0 : 1
            }
            let animator = UIViewPropertyAnimator(duration: transitionDuration(using: context), dampingRatio: 1) {
                surface.transform = self.presenting || reduceMotion ? .identity : offscreen
                surface.alpha = self.presenting || !reduceMotion ? 1 : 0
            }
            animator.addCompletion { _ in
                let completed = !context.transitionWasCancelled
                if !completed { surface.transform = .identity; surface.alpha = 1 }
                context.completeTransition(completed)
                self.animator = nil
            }
            self.animator = animator
            return animator
        }
    }
}
