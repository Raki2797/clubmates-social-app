import SwiftUI

struct TreatIcon: View {
    let treat: TreatInvite
    var size: CGFloat
    var isEnabled: Bool = true

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 0.58, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .opacity(isEnabled ? 1 : 0.45)
            .accessibilityLabel(treat.title)
    }

    private var foreground: some ShapeStyle {
        switch treat {
        case .drink:
            return AnyShapeStyle(LinearGradient(colors: [Color(hex: "7DD3FC"), Color(hex: "C084FC")], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .dessert:
            return AnyShapeStyle(LinearGradient(colors: [Color(hex: "F9A8D4"), Color(hex: "FDE68A")], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .coffee:
            return AnyShapeStyle(LinearGradient(colors: [Color(hex: "FDBA74"), Color(hex: "A16207")], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .starter:
            return AnyShapeStyle(LinearGradient(colors: [Color(hex: "86EFAC"), Color(hex: "F97316")], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    private var symbolName: String {
        switch treat {
        case .drink: return "wineglass.fill"
        case .dessert: return "birthday.cake.fill"
        case .coffee: return "cup.and.saucer.fill"
        case .starter: return "fork.knife"
        }
    }
}
