import SwiftUI
import ARKit
import RealityKit

/// AR overlay: places floating labels for fused tracks using distance estimates (bearing when available).
struct AROverlayView: View {
    @Environment(AppModel.self) private var app
    @State private var supported = ARWorldTrackingConfiguration.isSupported

    var body: some View {
        NavigationStack {
            ZStack {
                FinchTheme.background.ignoresSafeArea()
                if supported {
                    ARTrackRepresentable(tracks: app.fusion.sortedTracks)
                        .ignoresSafeArea()
                    VStack {
                        Spacer()
                        Text("\(app.fusion.sortedTracks.count) tracks · AR reticles by range")
                            .font(FinchTheme.monoSmall)
                            .padding(10)
                            .background(.black.opacity(0.55))
                            .foregroundStyle(FinchTheme.cyan)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding()
                    }
                } else {
                    ContentUnavailableView(
                        "ARKit unavailable",
                        systemImage: "camera.metering.unknown",
                        description: Text("This device does not support world tracking. Use Map + Tracks instead.")
                    )
                }
            }
            .navigationTitle("AR · RF OVERLAY")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { app.refreshFusion() }
        }
    }
}

struct ARTrackRepresentable: UIViewRepresentable {
    var tracks: [RFTrack]

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravityAndHeading
        view.session.run(config)
        context.coordinator.arView = view
        context.coordinator.rebuild(tracks: tracks)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.rebuild(tracks: tracks)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var arView: ARView?
        private var anchored: [UUID: AnchorEntity] = [:]

        func rebuild(tracks: [RFTrack]) {
            guard let arView else { return }
            let keep = Set(tracks.prefix(12).map(\.id))
            for (id, anchor) in anchored where !keep.contains(id) {
                arView.scene.removeAnchor(anchor)
                anchored.removeValue(forKey: id)
            }
            for track in tracks.prefix(12) {
                let distance = Float(min(max(track.estimatedDistanceM ?? 3.0, 1.0), 20.0))
                let bearing = Float((track.bearingDeg ?? Double(track.id.hashValue % 360)) * .pi / 180)
                let x = sin(bearing) * distance
                let z = -cos(bearing) * distance

                let mesh = MeshResource.generateSphere(radius: 0.06)
                var material = SimpleMaterial()
                material.color = .init(tint: threatUIColor(track.threatScore))
                let entity = ModelEntity(mesh: mesh, materials: [material])

                let label = ModelEntity(
                    mesh: .generateText(
                        "\(track.displayName.prefix(16))\n\(track.threatScore)/10",
                        extrusionDepth: 0.002,
                        font: .monospacedSystemFont(ofSize: 0.08, weight: .medium),
                        containerFrame: .zero,
                        alignment: .center,
                        lineBreakMode: .byTruncatingTail
                    ),
                    materials: [SimpleMaterial(color: .white, isMetallic: false)]
                )
                label.position = SIMD3(0, 0.12, 0)

                if let existing = anchored[track.id] {
                    existing.position = SIMD3(x, 0, z)
                    existing.children.forEach { $0.removeFromParent() }
                    existing.addChild(entity)
                    existing.addChild(label)
                } else {
                    let anchor = AnchorEntity(world: SIMD3(x, 0, z))
                    anchor.addChild(entity)
                    anchor.addChild(label)
                    arView.scene.addAnchor(anchor)
                    anchored[track.id] = anchor
                }
            }
        }

        private func threatUIColor(_ score: Int) -> UIColor {
            switch score {
            case 8...10: return .systemRed
            case 5...7: return .systemOrange
            case 3...4: return .systemYellow
            default: return UIColor(red: 0, green: 1, blue: 0.82, alpha: 1)
            }
        }
    }
}
