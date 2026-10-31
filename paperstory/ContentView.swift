import SwiftUI
import RealityKit

struct ContentView: View {
    @State private var controller = PaperSceneController()
    @State private var hasInteracted = false
    @State private var dragMode: DragMode = .idle
    @State private var lastTranslation: CGSize = .zero

    private enum DragMode { case idle, undecided, pulling, tearing, orbiting }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RealityView { content in
                    content.camera = .virtual
                    await controller.setup(content)
                }
                .gesture(dragGesture(size: geo.size))

                perforationOverlay
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    header
                    Spacer()
                    if !hasInteracted {
                        Text("手前にまわす")
                            .font(.custom("HiraMinProN-W3", size: 16))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 14)
                            .transition(.opacity)
                    }
                    ZStack {
                        cutButton
                        HStack {
                            Spacer()
                            resetViewButton
                        }
                    }
                    .padding(.bottom, 14)
                }
                .padding(.horizontal, 20)
            }
            .background(Color(red: 0.95, green: 0.92, blue: 0.86))
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ToireStory")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(Story.title)
                    .font(.custom("HiraMinProN-W6", size: 17))
                    .foregroundStyle(Color(white: 0.2))
            }
            Spacer()
            Image(systemName: "gearshape")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 64)
    }

    private var cutButton: some View {
        Button {
            hasInteracted = true
            controller.cutHere()
        } label: {
            Label("ここで切る", systemImage: "scissors")
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(Color(white: 0.25))
        }
        .padding(.bottom, 20)
    }

    private var resetViewButton: some View {
        Button {
            controller.resetView()
        } label: {
            Image(systemName: "circle")
                .font(.system(size: 22, weight: .light))
                .frame(width: 44, height: 44)
                .overlay(Circle().fill(Color(white: 0.3).opacity(0.5)).frame(width: 8, height: 8))
                .foregroundStyle(Color(white: 0.3))
        }
        .padding(.bottom, 20)
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
                            hasInteracted = true
                            controller.world.cut(atS: s, fromLeft: t.width > 0)
                        }
                    } else {
                        dragMode = .pulling
                        hasInteracted = true
                        controller.highlightS = nil
                        lastTranslation = .zero
                    }
                case .pulling:
                    let axis = controller.pullAxis(in: size)
                    let along = (delta.width * axis.dir.dx + delta.height * axis.dir.dy) / axis.pointsPerMeter
                    if along > 0 {
                        controller.world.feed(Float(along))
                    } else if along < 0 {
                        controller.world.nudgeBack(Float(-along))
                    }
                    lastTranslation = v.translation
                default:
                    break
                }
            }
            .onEnded { v in
                if dragMode == .undecided {
                    hasInteracted = true
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
}

#Preview {
    ContentView()
}
