import SwiftUI
import DataTrackerCore

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x888888
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    static let wifiColor = Color(hex: "0090FF")
    static let cellularColor = Color(hex: "30A46C")
}

/// Rounded square icon for an app entry.
struct EntryIcon: View {
    let info: EntryInfo
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: info.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: info.colorHex), in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension Int64 {
    var bytesText: String { ByteFormatter.string(self) }
}
