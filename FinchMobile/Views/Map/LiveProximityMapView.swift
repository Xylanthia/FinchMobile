import SwiftUI
import MapKit
import CoreLocation

/// Live map centered on the phone operating Finch.
/// Device pins sit at **RSSI-estimated distance**; compass bearing is synthetic (BLE has no AoA).
struct LiveProximityMapView: View {
    @Environment(AppModel.self) private var app
    @State private var location = LocationProvider()
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedID: UUID?
    @State private var showRadar = true
    @State private var maxRingMeters: Double = 40

    private var devices: [BLEDevice] {
        app.bleScanner.sortedDevices
    }

    private var selectedDevice: BLEDevice? {
        guard let selectedID else { return nil }
        return app.bleScanner.devices[selectedID]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FinchTheme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    statusBar
                    if showRadar {
                        radarPane
                            .frame(height: 280)
                    }
                    mapPane
                    distanceStrip
                }
            }
            .navigationTitle("Live Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(showRadar ? "Hide radar" : "Radar") {
                        withAnimation { showRadar.toggle() }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        if !app.bleScanner.isScanning { app.bleScanner.start() }
                        location.requestAndStart()
                        if let c = location.coordinate {
                            camera = .region(MKCoordinateRegion(
                                center: c,
                                latitudinalMeters: max(maxRingMeters * 2.5, 60),
                                longitudinalMeters: max(maxRingMeters * 2.5, 60)
                            ))
                        } else {
                            camera = .userLocation(fallback: .automatic)
                        }
                    } label: {
                        Image(systemName: "location.circle.fill")
                    }
                    Text("\(devices.count)")
                        .font(FinchTheme.mono)
                        .foregroundStyle(FinchTheme.cyan)
                }
            }
            .sheet(isPresented: Binding(
                get: { selectedID != nil },
                set: { if !$0 { selectedID = nil } }
            )) {
                if let device = selectedDevice {
                    BLEDeviceDetailSheet(deviceID: device.identifier)
                        .environment(app)
                }
            }
            .onAppear {
                location.requestAndStart()
                if app.settings.continuousBLEDefault {
                    app.bleScanner.continuousMode = true
                    app.bleScanner.start()
                } else if !app.bleScanner.isScanning {
                    app.bleScanner.start()
                }
                refreshMaxRing()
            }
            .onDisappear {
                location.stop()
            }
            .onChange(of: devices.count) { _, _ in refreshMaxRing() }
        }
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(app.bleScanner.isScanning ? FinchTheme.cyan : FinchTheme.textSecondary)
                    .frame(width: 8, height: 8)
                Text(app.bleScanner.isScanning ? "BLE live" : "BLE stopped")
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.textSecondary)
                Spacer()
                if let acc = location.accuracyMeters, acc > 0, acc < 100 {
                    Text(String(format: "GPS ±%.0fm", acc))
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.cyan)
                } else if !location.isAuthorized {
                    Text("GPS off")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.warn)
                }
            }
            Text("Distances ≈ RSSI (walls skew). Map angles are visual only — BLE has no direction.")
                .font(FinchTheme.monoSmall)
                .foregroundStyle(FinchTheme.textSecondary)
            if let err = location.errorMessage {
                Text(err)
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.danger)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(FinchTheme.surface)
    }

    private var radarPane: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) - 16
            ZStack {
                FinchTheme.surface
                ProximityRadarCanvas(
                    devices: devices,
                    maxMeters: maxRingMeters,
                    phoneHeading: location.headingDegrees
                )
                .frame(width: size, height: size)
                .padding(8)
            }
        }
        .background(FinchTheme.surface)
    }

    private var mapPane: some View {
        Map(position: $camera) {
            UserAnnotation()

            if let origin = location.coordinate {
                ForEach(devices) { device in
                    if let dist = device.estimatedDistanceMeters {
                    let coord = ProximityGeo.coordinate(
                        from: origin,
                        distanceMeters: dist,
                        bearingDegrees: ProximityGeo.bearingDegrees(for: device.identifier)
                    )
                    Annotation(device.friendly.title, coordinate: coord) {
                        Button {
                            selectedID = device.identifier
                        } label: {
                            VStack(spacing: 2) {
                                Text(device.distanceShortLabel)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(FinchTheme.background)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(FinchTheme.cyan)
                                    .clipShape(Capsule())
                                Circle()
                                    .fill(pinColor(for: device))
                                    .frame(width: 12, height: 12)
                                    .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1))
                                Text(shortTitle(device.friendly.title))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .topLeading) {
            if location.coordinate == nil {
                Text(location.isAuthorized ? "Waiting for GPS fix…" : "Enable Location to place pins on the street map.")
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.warn)
                    .padding(8)
                    .background(FinchTheme.surface.opacity(0.9))
                    .padding(8)
            }
        }
    }

    private var distanceStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(devices.prefix(24)) { device in
                    Button {
                        selectedID = device.identifier
                        focus(on: device)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortTitle(device.friendly.title))
                                .font(FinchTheme.monoSmall)
                                .foregroundStyle(FinchTheme.textPrimary)
                                .lineLimit(1)
                            Text(device.distanceShortLabel)
                                .font(FinchTheme.mono)
                                .foregroundStyle(FinchTheme.cyan)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(FinchTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(FinchTheme.cyan.opacity(0.25), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(FinchTheme.background)
    }

    private func refreshMaxRing() {
        let farthest = devices.compactMap(\.estimatedDistanceMeters).max() ?? 15
        maxRingMeters = min(max(farthest * 1.15, 12), 80)
    }

    private func focus(on device: BLEDevice) {
        guard let origin = location.coordinate, let dist = device.estimatedDistanceMeters else { return }
        let coord = ProximityGeo.coordinate(
            from: origin,
            distanceMeters: dist,
            bearingDegrees: ProximityGeo.bearingDegrees(for: device.identifier)
        )
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: coord,
                latitudinalMeters: 40,
                longitudinalMeters: 40
            ))
        }
    }

    private func shortTitle(_ title: String) -> String {
        if title.count <= 16 { return title }
        return String(title.prefix(14)) + "…"
    }

    private func pinColor(for device: BLEDevice) -> Color {
        switch device.estimatedDistanceMeters {
        case .some(let m) where m < 2: return FinchTheme.cyan
        case .some(let m) where m < 8: return FinchTheme.warn
        case .some: return FinchTheme.danger
        case .none: return FinchTheme.textSecondary
        }
    }
}

// MARK: - Polar radar (phone at center)

private struct ProximityRadarCanvas: View {
    var devices: [BLEDevice]
    var maxMeters: Double
    var phoneHeading: CLLocationDirection?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 6
                let rings: [Double] = [0.25, 0.5, 0.75, 1.0]
                let sweep = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3

                // Rings
                for t in rings {
                    let r = radius * t
                    var path = Path()
                    path.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                    context.stroke(path, with: .color(FinchTheme.cyan.opacity(0.22)), lineWidth: 1)
                    let meters = Int((maxMeters * t).rounded())
                    context.draw(
                        Text("\(meters)m").font(FinchTheme.monoSmall).foregroundColor(FinchTheme.textSecondary),
                        at: CGPoint(x: center.x + 4, y: center.y - r + 2),
                        anchor: .topLeading
                    )
                }

                // Sweep
                var sweepPath = Path()
                sweepPath.move(to: center)
                sweepPath.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(sweep * 360 - 25),
                    endAngle: .degrees(sweep * 360),
                    clockwise: false
                )
                sweepPath.closeSubpath()
                context.fill(sweepPath, with: .color(FinchTheme.cyan.opacity(0.08)))

                // Phone
                let phone = Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))
                context.fill(phone, with: .color(FinchTheme.cyan))
                context.draw(
                    Text("YOU").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(FinchTheme.cyan),
                    at: CGPoint(x: center.x, y: center.y + 14),
                    anchor: .top
                )

                // Devices
                for device in devices {
                    guard let dist = device.estimatedDistanceMeters else { continue }
                    let t = min(dist / max(maxMeters, 1), 1.0)
                    var bearing = ProximityGeo.bearingDegrees(for: device.identifier)
                    if let heading = phoneHeading {
                        bearing -= heading // keep map-ish relative to phone heading when available
                    }
                    let rad = (bearing - 90) * .pi / 180
                    let r = radius * t
                    let pt = CGPoint(x: center.x + cos(rad) * r, y: center.y + sin(rad) * r)
                    let dot = Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8))
                    let color: Color = dist < 2 ? FinchTheme.cyan : (dist < 8 ? FinchTheme.warn : FinchTheme.danger)
                    context.fill(dot, with: .color(color))
                }
            }
        }
    }
}
