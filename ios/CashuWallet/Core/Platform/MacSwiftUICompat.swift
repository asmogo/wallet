#if os(macOS)
import SwiftUI

// MARK: - iOS-only SwiftUI surface
//
// Reproduces the handful of SwiftUI modifiers that iOS has and macOS does not,
// as no-ops or as the nearest honest equivalent. That is what lets ~26 view
// files compile untouched instead of being rewritten around platform branches.
//
// Scope note, verified against the macOS 26.1 SDK rather than assumed:
// `PresentationDetent`, `presentationDetents` and `presentationDragIndicator`
// are all *available* on macOS and are deliberately NOT shimmed here — adding
// them made every `.medium` and `.large` ambiguous. Only genuinely absent or
// `@available(macOS, unavailable)` API belongs in this file.

// MARK: - Navigation bar

/// Mirrors `SwiftUI.NavigationBarItem`, which exists on macOS but is marked
/// unavailable. macOS titles a window, not a bar, and has no large/inline split.
enum NavigationBarItem {
    enum TitleDisplayMode {
        case automatic, inline, large
    }
}

extension View {
    func navigationBarTitleDisplayMode(_ mode: NavigationBarItem.TitleDisplayMode) -> some View {
        self
    }
}

// MARK: - Toolbar placement
//
// The bar-relative placements are iOS-only. Mapping leading onto `.navigation`
// and trailing onto `.primaryAction` preserves the intent — first item on the
// left, action on the right — using the placements macOS actually has.

extension ToolbarItemPlacement {
    static var topBarLeading: ToolbarItemPlacement { .navigation }
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
    static var navigationBarLeading: ToolbarItemPlacement { .navigation }
    static var navigationBarTrailing: ToolbarItemPlacement { .primaryAction }
}

extension ToolbarPlacement {
    /// macOS has one toolbar per window; the navigation bar is that toolbar.
    static var navigationBar: ToolbarPlacement { .windowToolbar }

    /// There is no tab bar to hide on macOS. Resolving to the window toolbar
    /// keeps `.toolbar(.hidden, for: .tabBar)` meaning "hide the chrome", which
    /// is what the call sites are asking for — and the menu bar panel has no
    /// visible titlebar anyway.
    static var tabBar: ToolbarPlacement { .windowToolbar }
}

// MARK: - Search

extension SearchFieldPlacement {
    enum CashuNavigationBarDrawerDisplayMode {
        case automatic, always
    }

    /// iOS can park the search field in a drawer under the navigation bar.
    /// macOS puts it in the toolbar and offers no equivalent, so this resolves
    /// to the platform default.
    static func navigationBarDrawer(
        displayMode: CashuNavigationBarDrawerDisplayMode
    ) -> SearchFieldPlacement {
        .automatic
    }
}

// MARK: - List metrics

extension View {
    /// iOS-only spacing control for grouped list sections.
    func listSectionSpacing(_ spacing: CGFloat) -> some View {
        self
    }
}

// MARK: - Full-screen presentation

/// macOS has no full-screen cover. A sheet is the honest equivalent: modal,
/// dismissible, owns the interaction. The menu bar panel presents it as a real
/// window sheet, so the flow reads the same even though the chrome differs.
extension View {
    func fullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss, content: content)
    }

    func fullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
    }
}

// MARK: - Text input

/// Mirrors `UIKit.UIKeyboardType`. There is no software keyboard to configure
/// on macOS, so the hint is dropped.
enum UIKeyboardType {
    case `default`, asciiCapable, numbersAndPunctuation, URL, numberPad
    case phonePad, namePhonePad, emailAddress, decimalPad, twitter, webSearch
    case asciiCapableNumberPad
}

/// Mirrors `SwiftUI.TextInputAutocapitalization`. Hardware keyboards do not
/// autocapitalise, so there is nothing to suppress.
struct TextInputAutocapitalization {
    static let never = TextInputAutocapitalization()
    static let words = TextInputAutocapitalization()
    static let sentences = TextInputAutocapitalization()
    static let characters = TextInputAutocapitalization()
}

extension View {
    func keyboardType(_ type: UIKeyboardType) -> some View {
        self
    }

    func textInputAutocapitalization(_ style: TextInputAutocapitalization?) -> some View {
        self
    }
}
#endif
