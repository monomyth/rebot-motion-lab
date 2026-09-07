import SwiftUI
import AppKit

@MainActor final class Typography: ObservableObject {
    static let shared = Typography()
    @Published private(set) var scale: Double
    private var monitor: Any?
    init() {
        let saved = UserDefaults.standard.double(forKey: "interfaceFontScale")
        scale = saved.isFinite && (0.8...1.6).contains(saved) ? saved : 1
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) == true }
            return handled ? nil : event
        }
    }
    func setScale(_ value: Double) {
        guard value.isFinite else { return }
        scale = min(1.6, max(0.8, (value * 10).rounded() / 10))
        UserDefaults.standard.set(scale, forKey: "interfaceFontScale")
    }
    func increase() { setScale(scale + 0.1) }
    func decrease() { setScale(scale - 0.1) }
    func reset() { setScale(1) }
    @discardableResult func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.type == .keyDown, modifiers.contains(.command), !modifiers.contains(.option), !modifiers.contains(.control) else { return false }
        switch event.charactersIgnoringModifiers {
        case "+", "=": increase()
        case "-": decrease()
        case "0": reset()
        default: return false
        }
        return true
    }
}

private struct FontScaleKey: EnvironmentKey { static let defaultValue = 1.0 }
extension EnvironmentValues {
    var fontScale: Double { get { self[FontScaleKey.self] } set { self[FontScaleKey.self] = newValue } }
}

struct LabFont {
    var size: CGFloat
    var weight: Font.Weight = .regular
    var design: Font.Design = .default
    static let largeTitle = LabFont(size: 34)
    static let title = LabFont(size: 28)
    static let title2 = LabFont(size: 22)
    static let title3 = LabFont(size: 20)
    static let headline = LabFont(size: 13, weight: .semibold)
    static let body = LabFont(size: 13)
    static let callout = LabFont(size: 12)
    static let caption = LabFont(size: 11)
    static let caption2 = LabFont(size: 10)
    func weight(_ value: Font.Weight) -> LabFont { var copy = self; copy.weight = value; return copy }
    static func system(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> LabFont { LabFont(size: size, weight: weight, design: design) }
    static func system(_ style: LabFont, design: Font.Design) -> LabFont { var copy = style; copy.design = design; return copy }
}
private struct ScaledFont: ViewModifier {
    @Environment(\.fontScale) private var scale
    let specification: LabFont
    func body(content: Content) -> some View {
        content.font(.system(size: specification.size * scale, weight: specification.weight, design: specification.design))
    }
}
extension View {
    func labFont(_ specification: LabFont) -> some View { modifier(ScaledFont(specification: specification)) }
}
