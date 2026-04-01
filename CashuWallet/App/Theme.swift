import SwiftUI

// MARK: - Theme Colors
extension Color {
    /// Cashu neon green accent color (default, use cashuAccent for dynamic)
    @available(*, deprecated, message: "Use settings.accentColor or CashuPrimaryButtonStyle instead for dynamic theming")
    static let cashuGreen = Color(red: 0, green: 1, blue: 0) // #00FF00

    /// Background color — adapts to system appearance
    static let cashuBackground = Color(uiColor: .systemBackground)

    /// Card background — adapts to system appearance
    static let cashuCardBackground = Color(uiColor: .secondarySystemBackground)

    /// Secondary background — adapts to system appearance
    static let cashuSecondaryBackground = Color(uiColor: .tertiarySystemBackground)

    /// Border color — adapts to system appearance
    static let cashuBorder = Color(uiColor: .separator)

    /// Success green
    static let cashuSuccess = Color(red: 0.2, green: 0.8, blue: 0.2)

    /// Warning/pending color
    static let cashuWarning = Color.orange

    /// Error color
    static let cashuError = Color.red

    /// Muted text color — adapts to system appearance
    static let cashuMutedText = Color.secondary
}

// MARK: - Theme Fonts
// Using semantic font styles that scale with Dynamic Type
extension Font {
    /// Large balance display — scales with accessibility settings
    static let cashuBalance = Font.largeTitle.weight(.bold)

    /// Medium balance display
    static let cashuBalanceMedium = Font.title.weight(.bold)

    /// Small balance display
    static let cashuBalanceSmall = Font.title2.weight(.bold)

    /// Section title
    static let cashuTitle = Font.title3.weight(.semibold)

    /// Dialog header title
    static let cashuDialogHeader = Font.headline

    /// Body text - regular weight
    static let cashuBody = Font.body

    /// Body text - medium weight
    static let cashuBodyMedium = Font.body.weight(.medium)

    /// Button text
    static let cashuButton = Font.callout.weight(.semibold)

    /// Small text / caption
    static let cashuCaption = Font.footnote

    /// Numeric keypad — uses fixed size intentionally for layout stability
    static let cashuKeypad = Font.system(size: 32, weight: .medium, design: .default)

    /// Unit label (BTC/SAT badge)
    static let cashuUnitLabel = Font.caption.weight(.semibold)

    /// Fiat price display
    static let cashuFiatPrice = Font.headline
}

// MARK: - Dynamic Button Styles

struct CashuPrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false
    @ObservedObject var settings = SettingsManager.shared
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.cashuButton)
            .foregroundColor(isDisabled ? .gray : .black)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(isDisabled ? Color.gray.opacity(0.3) : settings.accentColor)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct CashuSecondaryButtonStyle: ButtonStyle {
    @ObservedObject var settings = SettingsManager.shared
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.cashuButton)
            .foregroundColor(settings.accentColor)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(settings.accentColor, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct CashuOutlineButtonStyle: ButtonStyle {
    @ObservedObject var settings = SettingsManager.shared
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.cashuButton)
            .foregroundColor(settings.accentColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(settings.accentColor, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - View Modifiers
struct CashuCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.cashuCardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.cashuBorder, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func cashuCard() -> some View {
        modifier(CashuCardModifier())
    }
}

// MARK: - Themed Text Helper

struct ThemedText: View {
    let text: String
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        Text(text)
            .foregroundColor(settings.accentColor)
    }
}

