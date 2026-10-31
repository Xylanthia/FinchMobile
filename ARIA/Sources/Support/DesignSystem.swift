import SwiftUI
import UIKit

enum FinchTheme {
    static let background = Color.black
    static let surface = Color(white: 10 / 255)
    static let cyan = Color(red: 191 / 255, green: 0, blue: 1)
    static let cyanDim = Color(red: 191 / 255, green: 0, blue: 1).opacity(0.35)
    static let secondaryAccent = Color(red: 224 / 255, green: 64 / 255, blue: 251 / 255)
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


/// The phone's real compass heading; this never supplies a target bearing.
struct PhoneHeadingReadout: View {
    let location: LocationProvider

    var body: some View {
        HStack(spacing: 8) {
            if let heading = location.headingDegrees {
                Image(systemName: "arrow.up")
                    .rotationEffect(.degrees(heading))
                    .foregroundStyle(FinchTheme.cyan)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text(String(format: "PHONE %03.0f° · %@", heading, location.headingReference))
                if let accuracy = location.headingAccuracyDegrees {
                    Text(String(format: "±%.0f°", accuracy)).foregroundStyle(FinchTheme.textSecondary)
                }
            } else {
                Image(systemName: "location.slash")
                Text("Compass unavailable")
            }
        }
        .font(FinchTheme.monoSmall)
        .accessibilityElement(children: .combine)
    }
}

struct FinchOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FinchTheme.mono)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(FinchTheme.cyan)
            .background(RoundedRectangle(cornerRadius: 10).stroke(FinchTheme.cyan, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
