import SwiftUI

/// Ecash icon using SF Symbols
struct EcashIcon: View {
    var color: Color = .accentColor

    var body: some View {
        Image(systemName: "bitcoinsign.circle")
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// Lightning bolt icon using SF Symbols
struct LightningIcon: View {
    var color: Color = .accentColor

    var body: some View {
        Image(systemName: "bolt.fill")
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 20) {
        Label { Text("Ecash") } icon: { EcashIcon() }
        Label { Text("Lightning") } icon: { LightningIcon() }
    }
    .padding()
}
