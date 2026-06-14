import SwiftUI

enum C {
    static let bg      = Color(hex: "#111111")
    static let bg2     = Color(hex: "#1a1a1a")
    static let bg3     = Color(hex: "#2a2a2a")
    static let text    = Color(hex: "#d8d8d8")
    static let dim     = Color(hex: "#666666")
    static let green   = Color(hex: "#4ec94e")
    static let red     = Color(hex: "#c04040")
    static let orange  = Color(hex: "#e09030")
    static let groove  = Color(hex: "#333333")

    static let track: [Int: Color] = [
        1: Color(hex: "#4477bb"),
        2: Color(hex: "#bb9933"),
        3: Color(hex: "#848c94"),
        4: Color(hex: "#ff6a00"),
    ]

    static func track(_ n: Int) -> Color { track[n] ?? .gray }

    // Transport button base size
    static let transportW: CGFloat = 48
    static let transportH: CGFloat = 32
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(
            red:   Double((v >> 16) & 0xFF) / 255,
            green: Double((v >>  8) & 0xFF) / 255,
            blue:  Double( v        & 0xFF) / 255
        )
    }
}

// A simple dark rounded button style used throughout the app
struct DarkButton: ButtonStyle {
    var color: Color = C.bg3
    var pressed: Color = Color(hex: "#3a3a3a")

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(configuration.isPressed ? pressed : color)
            .cornerRadius(4)
    }
}

// Section divider with uppercase label (matches desktop panel separators)
struct SectionDivider: View {
    let label: String
    var body: some View {
        HStack(spacing: 6) {
            Rectangle().frame(height: 1).foregroundColor(C.bg3)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(C.dim)
                .fixedSize()
            Rectangle().frame(height: 1).foregroundColor(C.bg3)
        }
        .padding(.horizontal, 4)
    }
}
