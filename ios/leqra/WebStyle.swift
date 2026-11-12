import SwiftUI
import leqraCore

enum WebStyle {
    static let page = Color(hex: "#111619"), surface = Color(hex: "#192127")
    static let sunken = Color(hex: "#111a1f"), raised = Color(hex: "#232e33"), hover = Color(hex: "#324249")
    static let border = Color(hex: "#34434a"), edge = Color(hex: "#506d80")
    static let text = Color(hex: "#f1f7fc"), soft = Color(hex: "#c6d5df"), muted = Color(hex: "#9babbb")
    static let accent = Color(hex: "#40d5ff"), accentWash = Color(hex: "#102e3d"), green = Color(hex: "#39ff88")
    static let danger = Color(hex: "#ff4f5f")
    static func mono(_ size: CGFloat = 10, weight: Font.Weight = .regular) -> Font { .system(size: max(10, size), weight: weight, design: .monospaced) }
    static func paint(_ index: Int) -> Color { Color(hex: GamePalette.displayColors[GamePalette.index(index)]) }
    static func mapped(_ canonical: String) -> Color {
        let index = GamePalette.colors.firstIndex(of: canonical.lowercased())
        return index.map(paint) ?? Color(hex: canonical)
    }
}

enum BattleMode: String, CaseIterable, Identifiable {
    case infinity, elimination, ctf, koth, survival
    var id: String { rawValue }
    var title: String {
        switch self { case .infinity: return "Infinity"; case .elimination: return "Elimination"; case .ctf: return "Capture the flag"; case .koth: return "King of the hill"; case .survival: return "Survival" }
    }
    var short: String {
        switch self { case .ctf: return "Capture\nthe flag"; case .koth: return "King of\nthe hill"; default: return title }
    }
    var symbol: String {
        switch self { case .infinity: return "infinity"; case .elimination: return "scope"; case .ctf: return "flag"; case .koth: return "crown"; case .survival: return "shield.lefthalf.filled" }
    }
    var help: String {
        switch self {
        case .infinity: return "An endless tank arena. +1 per kill, -1 per death."
        case .elimination: return "Last side standing wins a round. A fresh maze every round."
        case .ctf: return "Carry the enemy flag home while the home flag is safe."
        case .koth: return "Hold the hill for points. Contested hills score nothing."
        case .survival: return "One squad against waves of enemy tanks. Survive together."
        }
    }
}

struct LocalBot: Identifiable, Codable, Equatable {
    var id: Int
    var name: String
    var colorIndex: Int
    var difficulty = "normal"
    var team = 0
}

struct LocalPreset: Identifiable, Codable {
    var id: String
    var rules: RoomRules
    var bots: [LocalBot]
    var team: Int
    var roster: [NativeSeatSpec]? = nil
}

struct WebButtonStyle: ButtonStyle {
    enum Kind { case primary, play, secondary, share, text, danger }
    var kind: Kind = .secondary
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(kind == .share || kind == .text ? WebStyle.mono() : .system(size: compact ? 10 : 12, weight: .bold))
            .foregroundStyle(ink)
            .frame(maxWidth: kind == .text ? nil : .infinity)
            .frame(minHeight: compact ? 36 : 44)
            .padding(.horizontal, kind == .text ? 0 : 12)
            .background(fill.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(edge, lineWidth: kind == .text ? 0 : 1).allowsHitTesting(false))
            .contentShape(Rectangle())
            .shadow(color: kind == .play ? WebStyle.green.opacity(0.2) : .clear, radius: 10)
            .shadow(color: kind == .play ? Color(hex: "#15994d") : kind == .primary ? Color(hex: "#087693") : .clear, radius: 0, x: 0, y: configuration.isPressed ? 1 : 3)
            .offset(y: configuration.isPressed ? 1 : 0)
    }
    private var fill: Color {
        switch kind { case .primary: return WebStyle.accent; case .play: return WebStyle.green; case .secondary: return WebStyle.raised; case .share: return WebStyle.accentWash.opacity(0.4); case .danger: return WebStyle.danger.opacity(0.1); case .text: return .clear }
    }
    private var edge: Color {
        switch kind { case .primary: return Color(hex: "#95eaff"); case .play: return Color(hex: "#72ffaa"); case .share: return WebStyle.accent.opacity(0.4); case .danger: return WebStyle.danger; default: return WebStyle.edge }
    }
    private var ink: Color {
        switch kind { case .primary: return Color(hex: "#002536"); case .play: return Color(hex: "#06160d"); case .share: return WebStyle.accent; case .text: return WebStyle.muted; case .danger: return WebStyle.danger; default: return WebStyle.text }
    }
}

struct WebPanel<Content: View>: View {
    var accent = false
    var paddingAmount: CGFloat = 22
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(paddingAmount)
            .background(LinearGradient(colors: [WebStyle.raised, WebStyle.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(WebStyle.edge, lineWidth: 1).allowsHitTesting(false))
            .overlay(alignment: .topLeading) {
                if accent { RoundedRectangle(cornerRadius: 2).fill(WebStyle.accent).frame(width: 42, height: 3).padding(.leading, 24).allowsHitTesting(false) }
            }
    }
}

struct WebField: ViewModifier {
    var font: Font = .system(size: 13)
    var color: Color = WebStyle.text
    func body(content: Content) -> some View {
        content.font(font).foregroundStyle(color).padding(.horizontal, 11).frame(minHeight: 40)
            .background(WebStyle.sunken, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(WebStyle.edge, lineWidth: 1).allowsHitTesting(false))
    }
}

struct WebDisclosure<Content: View>: View {
    @Binding var isExpanded: Bool
    var title: String
    var detail = ""
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            Button { isExpanded.toggle() } label: {
                HStack(spacing: 9) {
                    Text(title).font(.system(size: 14, weight: .bold))
                    Spacer()
                    if !detail.isEmpty { Text(detail).font(WebStyle.mono()).foregroundStyle(WebStyle.accent) }
                    Image(systemName: "chevron.right").font(.system(size: 17, weight: .semibold)).foregroundStyle(WebStyle.accent).rotationEffect(.degrees(isExpanded ? 90 : 0))
                }.foregroundStyle(WebStyle.text).padding(.horizontal, 14).frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier(title).accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            if isExpanded { content().padding(12).frame(maxWidth: .infinity, alignment: .leading) }
        }.background(WebStyle.surface, in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(WebStyle.edge, lineWidth: 1).allowsHitTesting(false))
    }
}

struct WebSwitch: UIViewRepresentable {
    @Binding var isOn: Bool
    func makeCoordinator() -> Coordinator { Coordinator(isOn: $isOn) }
    func makeUIView(context: Context) -> UISwitch {
        let view = UISwitch()
        view.onTintColor = UIColor(red: 0, green: 200 / 255, blue: 1, alpha: 1)
        view.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        view.accessibilityLabel = "Public Infinity"
        return view
    }
    func updateUIView(_ view: UISwitch, context: Context) {
        context.coordinator.isOn = $isOn
        view.setOn(isOn, animated: true)
        view.thumbTintColor = isOn ? UIColor(red: 0, green: 37 / 255, blue: 54 / 255, alpha: 1) : UIColor(red: 155 / 255, green: 171 / 255, blue: 187 / 255, alpha: 1)
    }
    final class Coordinator: NSObject {
        var isOn: Binding<Bool>
        init(isOn: Binding<Bool>) { self.isOn = isOn }
        @objc func changed(_ sender: UISwitch) { isOn.wrappedValue = sender.isOn }
    }
}

struct TankMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 32
            context.scaleBy(x: scale, y: scale)
            var tracks = Path(); tracks.move(to: .init(x: 6, y: 10)); tracks.addLine(to: .init(x: 6, y: 25)); tracks.move(to: .init(x: 26, y: 10)); tracks.addLine(to: .init(x: 26, y: 25))
            context.stroke(tracks, with: .color(WebStyle.accent), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            context.fill(Path(roundedRect: CGRect(x: 10, y: 10, width: 12, height: 15), cornerRadius: 3), with: .color(WebStyle.accent))
            var barrel = Path(); barrel.move(to: .init(x: 16, y: 5)); barrel.addLine(to: .init(x: 16, y: 17))
            context.stroke(barrel, with: .color(WebStyle.accent), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: 13, y: 15, width: 6, height: 6)), with: .color(WebStyle.sunken))
        }.frame(width: 24, height: 24)
    }
}

struct WebIconButton: View {
    let symbol: String, label: String
    var active = false
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 15, weight: .regular)).frame(width: 36, height: 36) }
            .foregroundStyle(active ? WebStyle.accent : WebStyle.soft)
            .background(WebStyle.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? WebStyle.accent.opacity(0.4) : WebStyle.border, lineWidth: 1).allowsHitTesting(false))
            .accessibilityLabel(label)
    }
}

extension Color {
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x32c5ff
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

// GitHub Invertocat geometry from the existing web header.
struct GitHubMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 41.4395, y: 69.3848))
        path.addCurve(to: CGPoint(x: 19.9062, y: 46.9902), control1: CGPoint(x: 28.8066, y: 67.8535), control2: CGPoint(x: 19.9062, y: 58.7617))
        path.addCurve(to: CGPoint(x: 24.5, y: 33.5918), control1: CGPoint(x: 19.9062, y: 42.2051), control2: CGPoint(x: 21.6289, y: 37.0371))
        path.addCurve(to: CGPoint(x: 24.8828, y: 20.959), control1: CGPoint(x: 23.2559, y: 30.4336), control2: CGPoint(x: 23.4473, y: 23.7344))
        path.addCurve(to: CGPoint(x: 36.9414, y: 25.2656), control1: CGPoint(x: 28.7109, y: 20.4805), control2: CGPoint(x: 33.8789, y: 22.4902))
        path.addCurve(to: CGPoint(x: 49.0957, y: 23.543), control1: CGPoint(x: 40.5781, y: 24.1172), control2: CGPoint(x: 44.4062, y: 23.543))
        path.addCurve(to: CGPoint(x: 61.0586, y: 25.1699), control1: CGPoint(x: 53.7852, y: 23.543), control2: CGPoint(x: 57.6133, y: 24.1172))
        path.addCurve(to: CGPoint(x: 73.1172, y: 20.959), control1: CGPoint(x: 64.0254, y: 22.4902), control2: CGPoint(x: 69.2891, y: 20.4805))
        path.addCurve(to: CGPoint(x: 73.4043, y: 33.4961), control1: CGPoint(x: 74.457, y: 23.543), control2: CGPoint(x: 74.6484, y: 30.2422))
        path.addCurve(to: CGPoint(x: 78.0937, y: 46.9902), control1: CGPoint(x: 76.4668, y: 37.1328), control2: CGPoint(x: 78.0937, y: 42.0137))
        path.addCurve(to: CGPoint(x: 56.3691, y: 69.2891), control1: CGPoint(x: 78.0937, y: 58.7617), control2: CGPoint(x: 69.1934, y: 67.6621))
        path.addCurve(to: CGPoint(x: 61.8242, y: 81.252), control1: CGPoint(x: 59.623, y: 71.3945), control2: CGPoint(x: 61.8242, y: 75.9883))
        path.addLine(to: CGPoint(x: 61.8242, y: 91.2051))
        path.addCurve(to: CGPoint(x: 67.0879, y: 94.5547), control1: CGPoint(x: 61.8242, y: 94.0762), control2: CGPoint(x: 64.2168, y: 95.7031))
        path.addCurve(to: CGPoint(x: 98, y: 49.1914), control1: CGPoint(x: 84.4102, y: 87.9512), control2: CGPoint(x: 98, y: 70.6289))
        path.addCurve(to: CGPoint(x: 48.9043, y: 4.309e-07), control1: CGPoint(x: 98, y: 22.1074), control2: CGPoint(x: 75.9883, y: 6.69539e-07))
        path.addCurve(to: CGPoint(x: -4.3343e-07, y: 49.1914), control1: CGPoint(x: 21.8203, y: 1.92261e-07), control2: CGPoint(x: -1.9479e-07, y: 22.1074))
        path.addCurve(to: CGPoint(x: 31.6777, y: 94.6504), control1: CGPoint(x: -6.20631e-07, y: 70.4375), control2: CGPoint(x: 13.4941, y: 88.0469))
        path.addCurve(to: CGPoint(x: 36.75, y: 91.3008), control1: CGPoint(x: 34.2617, y: 95.6074), control2: CGPoint(x: 36.75, y: 93.8848))
        path.addLine(to: CGPoint(x: 36.75, y: 83.6445))
        path.addCurve(to: CGPoint(x: 32.1562, y: 84.6016), control1: CGPoint(x: 35.4102, y: 84.2188), control2: CGPoint(x: 33.6875, y: 84.6016))
        path.addCurve(to: CGPoint(x: 19.4277, y: 74.7441), control1: CGPoint(x: 25.8398, y: 84.6016), control2: CGPoint(x: 22.1074, y: 81.1563))
        path.addCurve(to: CGPoint(x: 15.0254, y: 70.3418), control1: CGPoint(x: 18.375, y: 72.1602), control2: CGPoint(x: 17.2266, y: 70.6289))
        path.addCurve(to: CGPoint(x: 13.4941, y: 69.1934), control1: CGPoint(x: 13.877, y: 70.2461), control2: CGPoint(x: 13.4941, y: 69.7676))
        path.addCurve(to: CGPoint(x: 17.3223, y: 67.1836), control1: CGPoint(x: 13.4941, y: 68.0449), control2: CGPoint(x: 15.4082, y: 67.1836))
        path.addCurve(to: CGPoint(x: 24.9785, y: 72.4473), control1: CGPoint(x: 20.0977, y: 67.1836), control2: CGPoint(x: 22.4902, y: 68.9063))
        path.addCurve(to: CGPoint(x: 31.2949, y: 76.4668), control1: CGPoint(x: 26.8926, y: 75.2227), control2: CGPoint(x: 28.9023, y: 76.4668))
        path.addCurve(to: CGPoint(x: 37.4199, y: 73.4043), control1: CGPoint(x: 33.6875, y: 76.4668), control2: CGPoint(x: 35.2187, y: 75.6055))
        path.addCurve(to: CGPoint(x: 41.4395, y: 69.3848), control1: CGPoint(x: 39.0469, y: 71.7773), control2: CGPoint(x: 40.291, y: 70.3418))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 98, y: rect.height / 96))
    }
}
