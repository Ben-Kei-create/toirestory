import SwiftUI
import RealityKit

struct ContentView: View {
    var onClose: (() -> Void)? = nil
    @State private var controller = PaperSceneController()
    @State private var hasPulled = false
    @State private var finished = false
    @State private var confirmRestart = false
    @State private var dragMode: DragMode = .idle
    @State private var lastTranslation: CGSize = .zero

    private enum DragMode { case idle, undecided, pulling, tearing, orbiting }

    private let ink = AppPalette.ink
    private let background = AppPalette.background

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geo in
                ZStack {
                    RealityView { content in
                        content.camera = .virtual
                        await controller.setup(content)
                    }
                    .gesture(dragGesture(size: geo.size))
                    perforationOverlay
                        .allowsHitTesting(false)
                    VStack {
                        Spacer(minLength: 0)
                        LinearGradient(colors: [background.opacity(0), background],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 14)
                    }
                    .allowsHitTesting(false)
                    if finished { finishedOverlay }
                }
                .clipped()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    controller.updateViewport(size)
                }
            }
            readingControls
        }
        .background(background.ignoresSafeArea())
        .tint(ink)
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.25), value: hasPulled)
        .animation(.easeInOut(duration: 0.4), value: finished)
        .confirmationDialog("最初から読み直しますか?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("最初から読む", role: .destructive) { restartReading() }
            Button("キャンセル", role: .cancel) {}
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(300)) }
                catch { return }
                let done = controller.world.isExhausted && controller.world.feedVelocity == 0
                if done != finished { finished = done }
            }
        }
    }

    private func restartReading() {
        controller.resetReading()
        finished = false
        hasPulled = false
    }

    private var readingControls: some View {
        VStack(spacing: 12) {
            Text("下へ引いて読む")
                .font(.subheadline)
                .foregroundStyle(ink.opacity(0.75))
                .opacity(hasPulled ? 0 : 1)
                .accessibilityHidden(hasPulled)
                .accessibilityIdentifier("reading.hint")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    cutButton
                    resetViewButton
                }
                VStack(spacing: 12) {
                    cutButton
                    resetViewButton
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(background)
    }

    private var finishedOverlay: some View {
        VStack(spacing: 14) {
            Text("読了")
                .font(.custom("HiraMinProN-W6", size: 26))
            Text("紙を最後まで引き出しました")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button("最初から読む") {
                restartReading()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(white: 0.3))
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .transition(.opacity)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("作品選択に戻る")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("paperstory")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ink.opacity(0.7))
                Text(Story.title)
                    .font(.headline)
            }
            Spacer(minLength: 8)
            Menu {
                Button("最初から読み直す", systemImage: "arrow.counterclockwise", role: .destructive) {
                    confirmRestart = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("読書メニュー")
        }
        .foregroundStyle(ink)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(background)
    }

    private var cutButton: some View {
        Button {
            controller.cutHere()
        } label: {
            Label("ここで切る", systemImage: "scissors")
                .font(.body.weight(.medium))
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(controller.canCut ? AppPalette.accent.opacity(0.18) : Color.clear, in: Capsule())
                .foregroundStyle(controller.canCut ? ink : Color(white: 0.60))
        }
        .buttonStyle(.plain)
        .disabled(!controller.canCut)
        .accessibilityIdentifier("reading.cut")
        .accessibilityValue(controller.canCut ? "切断できます" : "切断できません")
        .accessibilityHint(controller.canCut ? "ミシン目で紙を切ります" : "切れるミシン目まで下へ引いてください")
    }

    private var resetViewButton: some View {
        Button {
            controller.resetView()
        } label: {
            Label("視点を戻す", systemImage: "viewfinder")
                .font(.subheadline)
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(ink)
    }

    private var perforationOverlay: some View {
        TimelineView(.animation) { _ in
            Canvas { ctx, size in
                guard let pts = controller.highlightPoints(in: size), pts.count > 1 else { return }
                var path = Path()
                path.move(to: pts[0])
                for p in pts.dropFirst() { path.addLine(to: p) }
                ctx.stroke(path, with: .color(Color(red: 0.45, green: 0.4, blue: 0.35).opacity(0.55)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
            }
        }
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if dragMode == .idle {
                    lastTranslation = .zero
                    if controller.isOnPaper(v.startLocation, in: size) {
                        dragMode = .undecided
                        controller.world.feedVelocity = 0
                        controller.highlightS = controller.perforation(near: v.startLocation, in: size)
                    } else {
                        dragMode = .orbiting
                    }
                }
                let delta = CGSize(width: v.translation.width - lastTranslation.width,
                                   height: v.translation.height - lastTranslation.height)
                switch dragMode {
                case .orbiting:
                    controller.orbit(dx: delta.width, dy: delta.height)
                    lastTranslation = v.translation
                case .undecided:
                    let t = v.translation
                    guard hypot(t.width, t.height) > 12 else { return }
                    if abs(t.width) > abs(t.height) * 1.4 {
                        if let s = controller.highlightS, abs(t.width) > 20 {
                            dragMode = .tearing
                            controller.world.cut(atS: s, fromLeft: t.width > 0)
                        }
                    } else {
                        dragMode = .pulling
                        controller.highlightS = nil
                        pullPaper(by: v.translation, in: size)
                        lastTranslation = v.translation
                    }
                case .pulling:
                    pullPaper(by: delta, in: size)
                    lastTranslation = v.translation
                default:
                    break
                }
            }
            .onEnded { v in
                if dragMode == .undecided, hypot(v.translation.width, v.translation.height) < 12 {
                    controller.touchPaper(at: v.startLocation, in: size)
                }
                if dragMode == .pulling {
                    let axis = controller.pullAxis(in: size)
                    let along = (v.velocity.width * axis.dir.dx + v.velocity.height * axis.dir.dy) / axis.pointsPerMeter
                    controller.world.feedVelocity = max(0, Float(along)) * 0.5
                }
                controller.highlightS = nil
                dragMode = .idle
            }
    }

    private func pullPaper(by delta: CGSize, in size: CGSize) {
        let axis = controller.pullAxis(in: size)
        let along = (delta.width * axis.dir.dx + delta.height * axis.dir.dy) / axis.pointsPerMeter
        if along > 0 {
            let previousExit = controller.world.sExit
            controller.world.feed(Float(along))
            if controller.world.sExit > previousExit { hasPulled = true }
        } else if along < 0 {
            controller.world.nudgeBack(Float(-along))
        }
    }
}

#Preview {
    ContentView()
}
