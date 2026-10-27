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
    static let brandPink = Color(hex: 0xFB0065)   // Fusion Telecoms brand pink
    static let brandInk  = Color(hex: 0x1E242F)   // dark charcoal text

    // Accent dots from the logo's atom mark — for small status touches.
    static let brandCyan   = Color(hex: 0x29B6D8)
    static let brandOrange = Color(hex: 0xF08A1E)
    static let brandYellow = Color(hex: 0xFFD21E)
    static let brandBlue   = Color(hex: 0x3A5CA8)
    static let brandPurple = Color(hex: 0x8C5BA6)
}

extension View {
    /// The branded pink navigation bar used on every screen, so the identity
    /// carries through from the tabs into pushed/presented screens too.
    func brandNavigationBar() -> some View {
        self
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.brandPink, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }

    /// The single primary-action button look used across the app's forms and
    /// screens, so the main call-to-action reads the same everywhere.
    func brandPrimaryButton() -> some View {
        self
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.brandPink)
    }
}

/// The leading landscape logo shown in the navigation bar of the main tabs.
/// `.original` keeps the white wordmark + coloured atom dots readable on pink.
struct BrandLogoLeading: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Image("LogoLandscape")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(height: 26)
                .accessibilityLabel("Fusion Telecoms")
        }
    }
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
