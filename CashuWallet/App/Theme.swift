import SwiftUI

// MARK: - Theme Colors
extension Color {
    /// Cashu neon green accent color (default, use cashuAccent for dynamic)
    @available(*, deprecated, message: "Use settings.accentColor or CashuPrimaryButtonStyle instead for dynamic theming")
    static let cashuGreen = Color(red: 0, green: 1, blue: 0) // #00FF00
    
    /// Background color - pure black
    static let cashuBackground = Color.black
    
    /// Card background - dark gray
    static let cashuCardBackground = Color(white: 0.08)
    
    /// Secondary background
    static let cashuSecondaryBackground = Color(white: 0.12)
    
    /// Border color
    static let cashuBorder = Color.white.opacity(0.15)
    
    /// Success green
    static let cashuSuccess = Color(red: 0.2, green: 0.8, blue: 0.2)
    
    /// Warning/pending color
    static let cashuWarning = Color.orange
    
    /// Error color
    static let cashuError = Color.red
    
    /// Muted text color
    static let cashuMutedText = Color.gray
}

// MARK: - Theme Fonts
// Using SF Pro (default system font) which closely matches Inter used by cashu.me
extension Font {
    /// Large balance display - matches cashu.me h3 bold style
    static let cashuBalance = Font.system(size: 56, weight: .bold, design: .default)
    
    /// Medium balance display
    static let cashuBalanceMedium = Font.system(size: 36, weight: .bold, design: .default)
    
    /// Small balance display
    static let cashuBalanceSmall = Font.system(size: 24, weight: .bold, design: .default)
    
    /// Section title - matches Inter semibold
    static let cashuTitle = Font.system(size: 20, weight: .semibold, design: .default)
    
    /// Dialog header title
    static let cashuDialogHeader = Font.system(size: 18, weight: .semibold, design: .default)
    
    /// Body text - regular weight
    static let cashuBody = Font.system(size: 16, weight: .regular, design: .default)
    
    /// Body text - medium weight
    static let cashuBodyMedium = Font.system(size: 16, weight: .medium, design: .default)
    
    /// Button text
    static let cashuButton = Font.system(size: 16, weight: .semibold, design: .default)
    
    /// Small text / caption
    static let cashuCaption = Font.system(size: 14, weight: .regular, design: .default)
    
    /// Numeric keypad
    static let cashuKeypad = Font.system(size: 32, weight: .medium, design: .default)
    
    /// Unit label (BTC/SAT badge)
    static let cashuUnitLabel = Font.system(size: 14, weight: .semibold, design: .default)
    
    /// Fiat price display
    static let cashuFiatPrice = Font.system(size: 18, weight: .semibold, design: .default)
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

