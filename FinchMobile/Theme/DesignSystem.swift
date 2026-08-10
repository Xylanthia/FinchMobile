import SwiftUI
import UIKit

enum FinchTheme {
    static let background = Color(red: 13 / 255, green: 13 / 255, blue: 13 / 255)
    static let surface = Color(red: 22 / 255, green: 24 / 255, blue: 26 / 255)
    static let cyan = Color(red: 0, green: 1, blue: 209 / 255)
    static let cyanDim = Color(red: 0, green: 1, blue: 209 / 255).opacity(0.35)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.65)
    static let danger = Color(red: 1, green: 0.35, blue: 0.35)
    static let warn = Color(red: 1, green: 0.75, blue: 0.2)
    static let mono: Font = .system(.body, design: .monospaced)
    static let monoSmall: Font = .system(.caption, design: .monospaced)
    static let monoTitle: Font = .system(.title3, design: .monospaced).weight(.semibold)
}

enum FinchCopy {
    static func set(_ string: String) {
        guard !string.isEmpty else { return }
        UIPasteboard.general.string = string
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

struct GlowBorder: ViewModifier {
    var active: Bool
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(active ? FinchTheme.cyan : FinchTheme.cyanDim, lineWidth: active ? 1.5 : 1)
                    .shadow(color: active ? FinchTheme.cyan.opacity(0.55) : .clear, radius: active ? 8 : 0)
            )
    }
}

extension View {
    func glowBorder(active: Bool, cornerRadius: CGFloat = 10) -> some View {
        modifier(GlowBorder(active: active, cornerRadius: cornerRadius))
    }

    /// Selectable text + long-press Copy + double-tap Copy.
    func finchCopyable(_ text: String, label: String = "Copy") -> some View {
        self
            .textSelection(.enabled)
            .contextMenu {
                Button {
                    FinchCopy.set(text)
                } label: {
                    Label(label, systemImage: "doc.on.doc")
                }
            }
            .onTapGesture(count: 2) {
                FinchCopy.set(text)
            }
    }
}

struct FinchCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(FinchTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(FinchTheme.cyan.opacity(0.15), lineWidth: 1)
            )
    }
}
