import SwiftUI

/// Custom Ecash icon - two overlapping coins like cashu.me CoinsIcon (lucide)
/// The design shows two circular coins slightly offset, representing ecash tokens
struct EcashIcon: View {
    var size: CGFloat = 24
    var color: Color = .green
    
    var body: some View {
        Canvas { context, canvasSize in
            let strokeWidth = size * 0.085
            let coinRadius = size * 0.32
            let overlap = size * 0.22  // How much the coins overlap
            
            let centerY = canvasSize.height / 2
            let centerX = canvasSize.width / 2
            
            // Back coin (slightly to the right and up)
            let backCoinCenter = CGPoint(x: centerX + overlap * 0.4, y: centerY - overlap * 0.3)
            
            // Front coin (slightly to the left and down)  
            let frontCoinCenter = CGPoint(x: centerX - overlap * 0.4, y: centerY + overlap * 0.3)
            
            // Draw back coin first
            let backCoinPath = Path(ellipseIn: CGRect(
                x: backCoinCenter.x - coinRadius,
                y: backCoinCenter.y - coinRadius,
                width: coinRadius * 2,
                height: coinRadius * 2
            ))
            context.stroke(backCoinPath, with: .color(color), lineWidth: strokeWidth)
            
            // Draw front coin on top
            let frontCoinPath = Path(ellipseIn: CGRect(
                x: frontCoinCenter.x - coinRadius,
                y: frontCoinCenter.y - coinRadius,
                width: coinRadius * 2,
                height: coinRadius * 2
            ))
            context.stroke(frontCoinPath, with: .color(color), lineWidth: strokeWidth)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Lightning bolt icon matching cashu.me style - uses a custom drawn bolt
struct LightningIcon: View {
    var size: CGFloat = 24
    var color: Color = .green
    
    var body: some View {
        Canvas { context, canvasSize in
            let width = canvasSize.width
            let height = canvasSize.height
            
            // Lightning bolt path - classic zigzag shape
            var path = Path()
            
            // Scale factors for the bolt
            let padX = width * 0.25
            let padY = height * 0.1
            
            // Draw lightning bolt
            path.move(to: CGPoint(x: width * 0.55, y: padY))
            path.addLine(to: CGPoint(x: padX, y: height * 0.5))
            path.addLine(to: CGPoint(x: width * 0.45, y: height * 0.5))
            path.addLine(to: CGPoint(x: width * 0.4, y: height - padY))
            path.addLine(to: CGPoint(x: width - padX, y: height * 0.45))
            path.addLine(to: CGPoint(x: width * 0.52, y: height * 0.45))
            path.closeSubpath()
            
            context.fill(path, with: .color(color))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            EcashIcon(size: 32, color: .green)
            Text("Ecash 32pt")
                .foregroundColor(.white)
        }
        HStack(spacing: 20) {
            EcashIcon(size: 40, color: .green)
            Text("Ecash 40pt")
                .foregroundColor(.white)
        }
        HStack(spacing: 20) {
            LightningIcon(size: 32, color: .green)
            Text("Lightning 32pt")
                .foregroundColor(.white)
        }
        HStack(spacing: 20) {
            LightningIcon(size: 40, color: .green)
            Text("Lightning 40pt")
                .foregroundColor(.white)
        }
    }
    .padding()
    .background(Color.black)
}
