import SwiftUI

enum Theme {
    static let green = Color.accentColor
    static let mint = Color("BrandMint")
    static let ink = Color("BrandInk")
    static let warm = Color("BrandWarm")
    static let sky = Color("BrandSky")
}

extension View {
    func cardStyle() -> some View {
        padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.primary.opacity(0.055), lineWidth: 0.75) }
            .shadow(color: Color.black.opacity(0.045), radius: 10, y: 5)
    }

    func premiumScreenBackground() -> some View { background(Color(.systemGroupedBackground).ignoresSafeArea()) }

    func analyticsScreenBackground() -> some View {
        background {
            LinearGradient(
                colors: [Theme.sky.opacity(0.22), Color(.systemGroupedBackground), Color(.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }
}

struct ServiceIcon: View {
    let symbol: String
    let colorName: String
    var serviceName: String? = nil
    var size: CGFloat = 44
    private var color: Color {
        switch colorName { case "blue": .blue; case "green": Theme.green; case "orange": .orange; case "purple": .purple; case "pink": .pink; case "indigo": .indigo; default: .teal }
    }
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.12))
            if let logoURL = ServiceBrand.logoURL(for: serviceName) {
                AsyncImage(url: logoURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFit().padding(size * 0.2)
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Image(systemName: symbol).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(color)
    }
}

enum ServiceBrand {
    private static let domains: [(matches: [String], domain: String)] = [
        (["spotify"], "spotify.com"),
        (["netflix"], "netflix.com"),
        (["youtube"], "youtube.com"),
        (["apple music", "itunes"], "music.apple.com"),
        (["icloud"], "icloud.com"),
        (["amazon", "prime video"], "amazon.com"),
        (["microsoft", "office 365", "microsoft 365"], "microsoft.com"),
        (["adobe"], "adobe.com"),
        (["canva"], "canva.com"),
        (["disney"], "disneyplus.com"),
        (["hulu"], "hulu.com"),
        (["paramount"], "paramountplus.com"),
        (["peacock"], "peacocktv.com"),
        (["max", "hbo"], "max.com"),
        (["audible"], "audible.com"),
        (["headspace"], "headspace.com"),
        (["duolingo"], "duolingo.com"),
        (["grammarly"], "grammarly.com"),
        (["chatgpt", "openai"], "openai.com")
    ]

    static func logoURL(for name: String?) -> URL? {
        guard let name else { return nil }
        let normalized = name.lowercased()
        guard let domain = domains.first(where: { $0.matches.contains { normalized.contains($0) } })?.domain else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=128")
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
