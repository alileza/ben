import SwiftUI
import AppKit

/// Custom About window. Replaces the system-default About panel via a
/// `CommandGroup(replacing: .appInfo)` in `App.swift`. Single-instance
/// `Window` scene; opens via `openWindow(id: "about")`.
struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 16) {
            icon
            VStack(spacing: 4) {
                Text("Ben")
                    .font(.system(size: 28, weight: .bold))
                Text("Version \(version) (build \(build))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text("Real-time English ⇄ German speech translation, fully on-device. Built on Apple's SFSpeechRecognizer and Translation framework.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .frame(maxWidth: 240)
                .padding(.vertical, 4)

            VStack(spacing: 8) {
                Text("Made by Ali Reza Yahya")
                    .font(.callout)
                HStack(spacing: 14) {
                    Link("github.com/alileza/ben",
                         destination: URL(string: "https://github.com/alileza/ben")!)
                        .font(.caption.monospaced())
                    Link("landing page",
                         destination: URL(string: "https://alileza.github.io/ben/")!)
                        .font(.caption.monospaced())
                }
            }

            BuyMeACoffeeButton()
                .padding(.top, 6)

            Text("© 2026 Ali Reza Yahya · MIT License")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .frame(width: 380)
        .background(.background)
    }

    private var icon: some View {
        let image = NSImage(named: NSImage.applicationIconName)
                 ?? NSApplication.shared.applicationIconImage
                 ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)!
        return Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: 96, height: 96)
            .accessibilityHidden(true)
    }
}

/// Discreet "support the maintainer" button. Styled to look like a
/// recognizable BMaC chip without screaming for attention.
private struct BuyMeACoffeeButton: View {
    @State private var hovered = false

    var body: some View {
        Link(destination: URL(string: "https://buymeacoffee.com/alileza")!) {
            HStack(spacing: 8) {
                Text("☕")
                    .font(.callout)
                Text("Buy me a coffee")
                    .font(.callout.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(red: 1.0, green: 0.51, blue: 0.25))
                    .shadow(color: .black.opacity(hovered ? 0.18 : 0.08),
                            radius: hovered ? 6 : 3, y: hovered ? 3 : 1.5)
            )
            .foregroundStyle(.black)
            .scaleEffect(hovered ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .help("If you find Ben useful")
        .accessibilityLabel("Buy me a coffee")
        .accessibilityHint("Opens buymeacoffee.com in your browser")
    }
}
