import SwiftUI

// MARK: - Activity Orb View
/// Loading indicator showing a subtle pulsing indicator when operations are in progress

struct ActivityOrbView: View {
    @Binding var isActive: Bool
    var autoHideDelay: Double = 2.0

    @State private var isVisible: Bool = false
    @State private var rotation: Double = 0

    var body: some View {
        Group {
            if isVisible {
                Image(systemName: "circle.dotted")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
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
/// Full-screen loading spinner for operations — uses standard ProgressView

struct LoadingSpinnerView: View {
    var message: String?

    var body: some View {
        if let message = message {
            ProgressView(message)
        } else {
            ProgressView()
        }
    }
}

// MARK: - Global Mutex Lock Overlay
/// Overlay shown when wallet is performing critical operations

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
                        ProgressView()
                            .controlSize(.large)

                        Text(message)
                            .font(.headline)
                    }
                    .padding(40)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLocked)
    }
}

// MARK: - Preview

#Preview("Activity Orb") {
    VStack(spacing: 40) {
        ActivityOrbView(isActive: .constant(true))

        LoadingSpinnerView(message: "Loading wallet...")
    }
}

#Preview("Mutex Lock Overlay") {
    ZStack {
        Text("Main Content")

        MutexLockOverlay(isLocked: .constant(true), message: "Sending tokens...")
    }
}
