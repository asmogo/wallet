import SwiftUI

/// Custom numeric keyboard matching cashu.me design
struct NumericKeyboard: View {
    @Binding var text: String
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            ForEach(0..<3) { row in
                HStack(spacing: 40) {
                    ForEach(1...3, id: \.self) { col in
                        let number = row * 3 + col
                        keyButton(String(number))
                    }
                }
            }
            
            // Bottom row: empty, 0, backspace
            HStack(spacing: 40) {
                // Empty space
                Color.clear
                    .frame(width: 70, height: 60)
                
                // Zero
                keyButton("0")
                
                // Backspace
                Button(action: backspace) {
                    Image(systemName: "delete.left")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 70, height: 60)
                }
            }
        }
    }
    
    private func keyButton(_ value: String) -> some View {
        Button(action: { appendDigit(value) }) {
            Text(value)
                .font(.system(size: 32, weight: .regular))
                .foregroundColor(.white)
                .frame(width: 70, height: 60)
        }
    }
    
    private func appendDigit(_ digit: String) {
        // Prevent leading zeros
        if text == "0" && digit == "0" { return }
        if text == "0" && digit != "0" {
            text = digit
            return
        }
        
        // Limit to reasonable amount
        if text.count < 12 {
            text += digit
        }
    }
    
    private func backspace() {
        if !text.isEmpty {
            text.removeLast()
        }
    }
}

#Preview {
    ZStack {
        Color.cashuBackground
            .ignoresSafeArea()
        
        VStack {
            Text("1234 sat")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
            
            Spacer()
            
            NumericKeyboard(text: .constant("1234"))
        }
        .padding()
    }
}
