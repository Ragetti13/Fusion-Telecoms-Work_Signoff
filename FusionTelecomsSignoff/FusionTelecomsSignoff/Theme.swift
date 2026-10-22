import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }

    // Fusion Telecoms brand
    static let brandPink = Color(hex: 0xED0F66)   // logo tile magenta
    static let brandInk  = Color(hex: 0x1E242F)   // dark charcoal text

    // Accent dots from the logo's atom mark — for small status touches.
    static let brandCyan   = Color(hex: 0x29B6D8)
    static let brandOrange = Color(hex: 0xF08A1E)
    static let brandYellow = Color(hex: 0xFFD21E)
    static let brandBlue   = Color(hex: 0x3A5CA8)
    static let brandPurple = Color(hex: 0x8C5BA6)
}

/// The Fusion Telecoms logo as a rounded, bordered badge. The logo art is
/// white-on-pink, so the pink tile reads as a brand mark on light surfaces.
struct LogoBadge: View {
    var size: CGFloat = 72
    var corner: CGFloat = 16

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.brandPink.opacity(0.28), radius: 10, x: 0, y: 5)
    }
}
