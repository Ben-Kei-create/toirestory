import SwiftUI

private enum AppPalette {
    static let background = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let ink = Color(red: 0.13, green: 0.20, blue: 0.27)
    static let blue = Color(red: 0.16, green: 0.40, blue: 0.83)
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
                Text("ToireStory")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppPalette.blue)
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
                    storyButton(title: "おすすめの名作", subtitle: "準備中", available: false) {}
                }
            }
            .frame(maxWidth: 480, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 68)
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
                    .foregroundStyle(available ? AppPalette.blue : Color(white: 0.59))
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
                        .foregroundStyle(AppPalette.blue)
                }
            }
            .foregroundStyle(available ? AppPalette.ink : Color(white: 0.55))
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .background(available ? Color.white : Color(white: 0.91),
                        in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(available ? AppPalette.blue.opacity(0.22) : Color(white: 0.85), lineWidth: 1)
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
    @State private var startedAt = Date()

    var body: some View {
        VStack(spacing: 24) {
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
                let progress = reduceMotion ? 0 : min(elapsed / 2.8, 1)
                Canvas { context, size in
                    drawRoll(context: &context, size: size, progress: progress)
                }
            }
            .frame(width: 280, height: 300)
            .clipped()
            .accessibilityHidden(true)

            Text("ToireStory")
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

    private func drawRoll(context: inout GraphicsContext, size: CGSize, progress: Double) {
        let unwinding = min(progress / 0.84, 1)
        let disappearance = max(0, (progress - 0.84) / 0.16)
        let radius = CGFloat(54 - 40 * unwinding)
        let center = CGPoint(x: size.width / 2, y: 88)
        let left = center.x - 72
        let right = center.x + 72
        let outline = AppPalette.ink.opacity(0.65)
        context.opacity = 1 - disappearance

        // The moving sheet extends out of view as the remaining roll shrinks.
        let sheetTop = center.y + radius * 0.25
        let sheetBottom = sheetTop + 100 + CGFloat(unwinding) * size.height
        let sheetRect = CGRect(x: left + 22, y: sheetTop, width: 122, height: sheetBottom - sheetTop)
        context.fill(Path(sheetRect), with: .color(.white))
        var edges = Path()
        edges.move(to: CGPoint(x: sheetRect.minX, y: sheetTop))
        edges.addLine(to: CGPoint(x: sheetRect.minX, y: sheetBottom))
        edges.move(to: CGPoint(x: sheetRect.maxX, y: sheetTop))
        edges.addLine(to: CGPoint(x: sheetRect.maxX, y: sheetBottom))
        context.stroke(edges, with: .color(outline), lineWidth: 1.5)
        let movement = CGFloat(unwinding * 650)
        for row in -8..<8 {
            let y = sheetTop + CGFloat(row) * 68 + movement
            guard y > sheetTop + 12, y < sheetBottom - 8 else { continue }
            var perforation = Path()
            perforation.move(to: CGPoint(x: sheetRect.minX + 6, y: y))
            perforation.addLine(to: CGPoint(x: sheetRect.maxX - 6, y: y))
            context.stroke(perforation, with: .color(outline.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
        }

        // End caps and a narrowing body make the paper visibly run out.
        let body = CGRect(x: left, y: center.y - radius, width: 144, height: radius * 2)
        context.fill(Path(roundedRect: body, cornerRadius: radius * 0.35), with: .color(.white))
        context.stroke(Path(roundedRect: body, cornerRadius: radius * 0.35), with: .color(outline), lineWidth: 1.5)
        let end = CGRect(x: right - radius * 0.38, y: center.y - radius,
                         width: radius * 0.76, height: radius * 2)
        context.fill(Path(ellipseIn: end), with: .color(Color(red: 0.89, green: 0.86, blue: 0.79)))
        context.stroke(Path(ellipseIn: end), with: .color(outline), lineWidth: 1.5)
        let coreRadius = CGFloat(10) * (1 - disappearance)
        let core = CGRect(x: right - coreRadius * 0.38, y: center.y - coreRadius,
                          width: coreRadius * 0.76, height: coreRadius * 2)
        context.fill(Path(ellipseIn: core), with: .color(AppPalette.ink))
    }
}

#Preview {
    AppRootView()
}
