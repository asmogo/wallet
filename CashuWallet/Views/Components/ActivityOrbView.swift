import SwiftUI

// MARK: - Activity Orb View
/// Loading indicator matching cashu.me's ActivityOrb component
/// Shows a subtle pulsing indicator when operations are in progress

struct ActivityOrbView: View {
    @Binding var isActive: Bool
    var autoHideDelay: Double = 2.0
    
    @ObservedObject var settings = SettingsManager.shared
    @State private var isVisible: Bool = false
    @State private var rotation: Double = 0
    
    var body: some View {
        Group {
            if isVisible {
                Image(systemName: "circle.dotted")
                    .font(.system(size: 20))
                    .foregroundColor(settings.accentColor)
                    .rotationEffect(.degrees(rotation))
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isVisible)
        .onChange(of: isActive) { newValue in
            if newValue {
                showOrb()
            } else {
                hideOrbAfterDelay()
            }
        }
    }
    
    private func showOrb() {
        withAnimation(.easeIn(duration: 0.3)) {
            isVisible = true
        }
        // Start rotation animation
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
    
    private func hideOrbAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideDelay) {
            withAnimation(.easeOut(duration: 0.5)) {
                isVisible = false
                rotation = 0
            }
        }
    }
}

// MARK: - Loading Spinner View
/// Full-screen loading spinner for operations

struct LoadingSpinnerView: View {
    var message: String?
    
    @ObservedObject var settings = SettingsManager.shared
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Spinner
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(settings.accentColor, lineWidth: 3)
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
            
            // Message
            if let message = message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.cashuMutedText)
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Global Mutex Lock Overlay
/// Overlay shown when wallet is performing critical operations
/// Matches cashu.me's globalMutexLock behavior

struct MutexLockOverlay: View {
    @Binding var isLocked: Bool
    var message: String = "Processing..."
    
    var body: some View {
        Group {
            if isLocked {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        LoadingSpinnerView()
                        
                        Text(message)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    .padding(40)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.cashuCardBackground)
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLocked)
    }
}

// MARK: - Pulse Animation Modifier
/// Adds pulse animation to any view (like cashu.me's animated pulse class)

struct PulseAnimationModifier: ViewModifier {
    @State private var isPulsing = false
    var duration: Double = 0.5
    var minScale: CGFloat = 0.95
    var maxScale: CGFloat = 1.05
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? maxScale : minScale)
            .animation(
                .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

extension View {
    func pulseAnimation(duration: Double = 0.5) -> some View {
        modifier(PulseAnimationModifier(duration: duration))
    }
}

// MARK: - Fade In Animation Modifier
/// Adds fade-in animation matching cashu.me's animated fadeIn class

struct FadeInAnimationModifier: ViewModifier {
    @State private var opacity: Double = 0
    var duration: Double = 0.5
    var delay: Double = 0
    
    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeIn(duration: duration).delay(delay)) {
                    opacity = 1
                }
            }
    }
}

extension View {
    func fadeInAnimation(duration: Double = 0.5, delay: Double = 0) -> some View {
        modifier(FadeInAnimationModifier(duration: duration, delay: delay))
    }
}

// MARK: - Slide Up Animation Modifier
/// Adds slide-up animation for dialogs

struct SlideUpAnimationModifier: ViewModifier {
    @State private var offset: CGFloat = 100
    @State private var opacity: Double = 0
    var duration: Double = 0.3
    
    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: duration, dampingFraction: 0.8)) {
                    offset = 0
                    opacity = 1
                }
            }
    }
}

extension View {
    func slideUpAnimation(duration: Double = 0.3) -> some View {
        modifier(SlideUpAnimationModifier(duration: duration))
    }
}

// MARK: - Preview

#Preview("Activity Orb") {
    ZStack {
        Color.cashuBackground
            .ignoresSafeArea()
        
        VStack(spacing: 40) {
            ActivityOrbView(isActive: .constant(true))
            
            LoadingSpinnerView(message: "Loading wallet...")
        }
    }
}

#Preview("Mutex Lock Overlay") {
    ZStack {
        Color.cashuBackground
            .ignoresSafeArea()
        
        Text("Main Content")
            .foregroundStyle(.primary)
        
        MutexLockOverlay(isLocked: .constant(true), message: "Sending tokens...")
    }
}
