import SwiftUI

enum Theme {
    static let green = Color.accentColor
    static let mint = Color("BrandMint")
    static let ink = Color("BrandInk")
    static let warm = Color("BrandWarm")
}

extension View {
    func cardStyle() -> some View {
        padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.primary.opacity(0.055), lineWidth: 0.75) }
            .shadow(color: Color.black.opacity(0.045), radius: 10, y: 5)
    }

    func premiumScreenBackground() -> some View { background(Color(.systemGroupedBackground).ignoresSafeArea()) }
}

struct ServiceIcon: View {
    let symbol: String
    let colorName: String
    var size: CGFloat = 44
    private var color: Color {
        switch colorName { case "blue": .blue; case "green": Theme.green; case "orange": .orange; case "purple": .purple; case "pink": .pink; case "indigo": .indigo; default: .teal }
    }
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(color)
            .frame(width: size, height: size).background(color.opacity(0.12), in: Circle()).accessibilityHidden(true)
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var role: ButtonRole? = nil
    let action: () -> Void
    var body: some View {
        Button(role: role, action: action) {
            HStack { Text(title); if let systemImage { Image(systemName: systemImage) } }.font(.headline).frame(maxWidth: .infinity, minHeight: 48)
        }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 14))
    }
}

struct MetricCard: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) { Text(value).font(.title2.bold()).contentTransition(.numericText()); Text(label).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, alignment: .leading).cardStyle().accessibilityElement(children: .combine)
    }
}
