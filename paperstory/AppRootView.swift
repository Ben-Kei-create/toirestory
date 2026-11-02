import SwiftUI

enum AppPalette {
    static let background = Color(red: 0.95, green: 0.92, blue: 0.86)
    static let ink = Color(red: 0.25, green: 0.23, blue: 0.20)
    static let accent = Color(red: 0.36, green: 0.29, blue: 0.20)
}

struct AppRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingIntro = true
    @State private var reading = false

    var body: some View {
        ZStack {
            if showingIntro {
                RollIntroView(reduceMotion: reduceMotion)
                    .transition(.opacity)
            } else if reading {
                ContentView(onClose: { reading = false })
                    .transition(.opacity)
            } else {
                storySelection
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.3), value: showingIntro)
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.25), value: reading)
        .preferredColorScheme(.light)
        .task {
            guard showingIntro else { return }
            do {
                try await Task.sleep(for: .seconds(reduceMotion ? 0.2 : 3.2))
                showingIntro = false
            } catch {
                // A disappearing window cancels its introduction.
            }
        }
    }

    private var storySelection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("PaperStory")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppPalette.accent)
                    .padding(.bottom, 18)
                Text("ひと巻きの、物語。")
                    .font(.system(size: 30, weight: .medium, design: .serif))
                    .foregroundStyle(AppPalette.ink)
                    .padding(.bottom, 12)
                Text("読む作品を選んでください")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 36)

                VStack(spacing: 14) {
                    storyButton(title: "走れメロス", subtitle: "太宰 治", available: true) {
                        reading = true
                    }
                    storyButton(title: "おすすめの名作", subtitle: "準備中", available: false) {}
                }
                Text("本文は青空文庫の「走れメロス」(太宰治)を使用しています。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 44)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .background(AppPalette.background.ignoresSafeArea())
    }

    private func storyButton(title: String, subtitle: String, available: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: "book.closed")
                    .font(.system(size: 23, weight: .regular))
                    .foregroundStyle(available ? AppPalette.accent : Color(white: 0.59))
                    .frame(width: 44, height: 48)
                VStack(alignment: .leading, spacing: 7) {
                    Text(title)
                        .font(.system(size: 19, weight: .medium, design: .serif))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if available {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(AppPalette.accent)
                }
            }
            .foregroundStyle(available ? AppPalette.ink : Color(white: 0.55))
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .background(available ? Color.white : Color(white: 0.91),
                        in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(available ? AppPalette.accent.opacity(0.22) : Color(white: 0.85), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .accessibilityIdentifier(available ? "story.melos" : "story.comingSoon")
    }
}

private struct RollIntroView: View {
    let reduceMotion: Bool
    private static let frameCount = 10
    private static let frameDuration = 0.28
    @State private var startedAt = Date()

    var body: some View {
        VStack(spacing: 24) {
            TimelineView(.periodic(from: startedAt, by: Self.frameDuration)) { timeline in
                let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
                let index = reduceMotion ? 6 : min(Int(elapsed / Self.frameDuration), Self.frameCount - 1)
                Image("roll-\(String(format: "%02d", index + 1))")
                    .resizable()
                    .scaledToFit()
            }
            .frame(width: 280, height: 300)
            .accessibilityHidden(true)

            Text("PaperStory")
                .font(.system(size: 25, weight: .medium, design: .rounded))
                .foregroundStyle(AppPalette.ink)
            Text("ひと巻きの、物語。")
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppPalette.background.ignoresSafeArea())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    AppRootView()
}
