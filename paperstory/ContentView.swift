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
                    .allowsHitTesting(false)
                    #if os(macOS)
                    PaperInputSurface(
                        onChanged: { start, translation in
                            updateDrag(start: start, translation: translation, in: geo.size)
                        },
                        onEnded: { start, translation, velocity in
                            endDrag(start: start, translation: translation, velocity: velocity, in: geo.size)
                        },
                        onScroll: { distance in
                            guard dragMode == .idle else { return }
                            let axis = controller.pullAxis(in: geo.size)
                            pullPaper(by: CGSize(width: axis.dir.dx * distance, height: axis.dir.dy * distance), in: geo.size)
                        }
                    )
                    #else
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateDrag(start: value.startLocation, translation: value.translation, in: geo.size)
                            }
                            .onEnded { value in
                                endDrag(start: value.startLocation, translation: value.translation, velocity: value.velocity, in: geo.size)
                            })
                    #endif
                    perforationOverlay
                        .allowsHitTesting(false)
                    if controller.viewMode == .reading {
                        VStack {
                            LinearGradient(colors: [background, background.opacity(0)],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: 14)
                            Spacer(minLength: 0)
                        }
                        .allowsHitTesting(false)
                    }
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

    private var pullHint: String {
        #if os(macOS)
        "下へドラッグして読む"
        #else
        "下へ引いて読む"
        #endif
    }

    private var readingControls: some View {
        VStack(spacing: 12) {
            Text(pullHint)
                .font(.subheadline)
                .foregroundStyle(ink.opacity(0.75))
                .opacity(hasPulled ? 0 : 1)
                .accessibilityHidden(hasPulled)
                .accessibilityIdentifier("reading.hint")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    cutButton
                    Spacer(minLength: 0)
                    resetViewButton
                    viewModeButton
                }
                VStack(spacing: 12) {
                    cutButton
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        resetViewButton
                        viewModeButton
                    }
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
                .keyboardShortcut(.leftArrow, modifiers: .command)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("PaperStory")
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
        .keyboardShortcut("k", modifiers: .command)
        .accessibilityValue(controller.canCut ? "切断できます" : "切断できません")
        .accessibilityHint(controller.canCut ? "ミシン目で紙を切ります" : "切れるミシン目まで下へ引いてください")
    }

    private var resetViewButton: some View {
        Button {
            controller.resetView()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "viewfinder")
                    .font(.body)
                Text("視点")
                    .font(.caption)
            }
            .frame(minWidth: 52, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(ink)
        .accessibilityLabel("視点を戻す")
        .keyboardShortcut("0", modifiers: .command)
    }

    private var viewModeButton: some View {
        Button {
            controller.toggleViewMode()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: controller.viewMode == .roll ? "text.magnifyingglass" : "cylinder")
                    .font(.body)
                Text(controller.viewMode == .roll ? "本文" : "ロール")
                    .font(.caption)
            }
            .frame(minWidth: 64, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(ink)
        .disabled(!controller.isReady)
        .accessibilityLabel(controller.viewMode == .roll ? "本文表示に切り替える" : "ロール表示に切り替える")
        .accessibilityValue(controller.viewMode == .roll ? "ロール表示" : "本文表示")
        .accessibilityIdentifier("reading.viewMode")
        .keyboardShortcut("1", modifiers: .command)
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

    private func updateDrag(start: CGPoint, translation: CGSize, in size: CGSize) {
        if dragMode == .idle {
            lastTranslation = .zero
            if controller.isOnPaper(start, in: size) {
                dragMode = .undecided
                controller.world.feedVelocity = 0
                controller.highlightS = controller.perforation(near: start, in: size)
            } else {
                dragMode = .orbiting
            }
        }
        let delta = CGSize(width: translation.width - lastTranslation.width,
                           height: translation.height - lastTranslation.height)
        switch dragMode {
        case .orbiting:
            controller.orbit(dx: delta.width, dy: delta.height)
            lastTranslation = translation
        case .undecided:
            let t = translation
            guard hypot(t.width, t.height) > 12 else { return }
            if abs(t.width) > abs(t.height) * 1.4 {
                if let s = controller.highlightS, abs(t.width) > 20 {
                    dragMode = .tearing
                    controller.world.cut(atS: s, fromLeft: t.width > 0)
                }
            } else {
                dragMode = .pulling
                controller.highlightS = nil
                pullPaper(by: translation, in: size)
                lastTranslation = translation
            }
        case .pulling:
            pullPaper(by: delta, in: size)
            lastTranslation = translation
        default:
            break
        }
    }

    private func endDrag(start: CGPoint, translation: CGSize, velocity: CGSize, in size: CGSize) {
        if dragMode == .undecided, hypot(translation.width, translation.height) < 12 {
            controller.touchPaper(at: start, in: size)
        }
        if dragMode == .pulling {
            let axis = controller.pullAxis(in: size)
            let along = (velocity.width * axis.dir.dx + velocity.height * axis.dir.dy) / axis.pointsPerMeter
            controller.world.feedVelocity = max(0, Float(along)) * 0.5
        }
        controller.highlightS = nil
        dragMode = .idle
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
