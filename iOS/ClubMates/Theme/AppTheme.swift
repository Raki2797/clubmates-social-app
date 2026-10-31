import SwiftUI

struct AppTheme {
    // MARK: - Colors
    static let background = Color(hex: "0D0D0F")
    static let cardBackground = Color(hex: "1A1A1F")
    static let surface = Color(hex: "232328")
    static let surfaceElevated = Color(hex: "2C2C33")

    static let primaryGradient = LinearGradient(
        colors: [Color(hex: "FF6B9D"), Color(hex: "C44EFF")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let likeGradient = LinearGradient(
        colors: [Color(hex: "00E5A0"), Color(hex: "00B4D8")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let nopeGradient = LinearGradient(
        colors: [Color(hex: "FF6B6B"), Color(hex: "FF4757")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let superLikeGradient = LinearGradient(
        colors: [Color(hex: "FFD93D"), Color(hex: "FF9A3C")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "9999AA")
    static let textTertiary = Color(hex: "555566")

    static let pink = Color(hex: "FF6B9D")
    static let purple = Color(hex: "C44EFF")
    static let green = Color(hex: "00E5A0")
    static let red = Color(hex: "FF4757")
    static let gold = Color(hex: "FFD93D")

    // MARK: - Typography
    static let titleFont = Font.system(size: 28, weight: .bold, design: .rounded)
    static let headlineFont = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let bodyFont = Font.system(size: 16, weight: .regular, design: .rounded)
    static let captionFont = Font.system(size: 13, weight: .medium, design: .rounded)

    // MARK: - Spacing
    static let cornerRadius: CGFloat = 24
    static let cardCornerRadius: CGFloat = 28
    static let buttonCornerRadius: CGFloat = 50
    
    // MARK: - Photo Dimensions (Premium)
    static let photoGridSpacing: CGFloat = 12
    static let photoGridCornerRadius: CGFloat = 24
    static let photoTileCornerRadius: CGFloat = 24
    static let heroPhotoHeight: CGFloat = 520
    static let publicStoryPhotoHeightLeft: CGFloat = 380
    static let publicStoryPhotoHeightRight: CGFloat = 340
    static let manageGridPhotoLeft: CGFloat = 260
    static let manageGridPhotoRight: CGFloat = 210
    static let manageGridPhotoSpacing: CGFloat = 12
    static let manageGridPhotoCornerRadius: CGFloat = 24
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
