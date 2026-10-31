import SwiftUI

struct CoinIcon: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "FFE66D"), Color(hex: "FFB703"), Color(hex: "FF5DA2")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(Color.white.opacity(0.55), lineWidth: max(size * 0.08, 1))
                .padding(size * 0.14)

            Text("C")
                .font(.system(size: size * 0.46, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "4A1259").opacity(0.85))
        }
        .frame(width: size, height: size)
        .shadow(color: AppTheme.pink.opacity(0.22), radius: size * 0.18, x: 0, y: size * 0.06)
        .accessibilityLabel("Coins")
    }
}
