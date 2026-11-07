import SwiftUI
import UIKit

struct ARIAHeader: View {
    @Environment(AppModel.self) private var app
    @State private var showJoin = false

    var body: some View {
        HStack(spacing: 12) {
            Text("ARIA").font(.title2.bold()).tracking(3)
            Spacer(minLength: 0)
            Button { showJoin = true } label: {
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(app.aria.connection.state.isConnected ? FinchTheme.cyan : FinchTheme.danger)
                            .frame(width: 7, height: 7)
                        Text(app.aria.connection.state.isConnected ? "CONNECTED" : "NOT CONNECTED")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    if !app.aria.connection.state.isConnected {
                        Text("Join ARIA-Setup Wi-Fi").font(.system(size: 10))
                    }
                }
                .padding(8).background(Capsule().stroke(FinchTheme.cyanDim))
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
            NavigationLink { ARIASessionExportView() } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Export")
        }
        .padding(.horizontal).padding(.vertical, 8)
        .sheet(isPresented: $showJoin) {
            NavigationStack {
                VStack(spacing: 22) {
                    Image(systemName: "wifi").font(.largeTitle).foregroundStyle(FinchTheme.cyan)
                    Text("Join ARIA-Setup Wi-Fi").font(.title2.bold())
                    Text("In Settings → Wi-Fi, join ARIA-Setup. Allow ARIA access under Privacy & Security → Local Network. Return here to reconnect automatically.")
                        .multilineTextAlignment(.center)
                    Button("Open ARIA Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.buttonStyle(FinchOutlineButtonStyle())
                    Button("Check Connection") { Task { await app.aria.refresh() } }
                    if app.aria.connection.state.isConnected { Text("CONNECTED").foregroundStyle(FinchTheme.cyan) }
                }
                .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(FinchTheme.background)
                .toolbar { Button("Done") { showJoin = false } }
            }
            .presentationDetents([.medium, .large])
            .onAppear { app.aria.connection.start() }
        }
        .task {
            if !app.aria.connection.localNetworkReady { showJoin = true }
            app.aria.start()
        }
    }
}

struct ARIADashboardView: View {
    @Environment(AppModel.self) private var app
    private let bands = ["Overview", "Wi-Fi", "Sub-GHz", "BLE", "UAS", "Frames"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                ARIAHeader()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(bands, id: \.self) { band in
                            if band == "Overview" {
                                Text(band).padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(Capsule().stroke(FinchTheme.cyan, lineWidth: 1.5))
                                    .shadow(color: FinchTheme.cyan.opacity(0.5), radius: 5)
                            } else {
                                NavigationLink { destination(band) } label: {
                                    Text(band).padding(.horizontal, 14).padding(.vertical, 8)
                                }
                            }
                        }
                    }.font(.subheadline).padding(.horizontal)
                }
                // Overview fits one screen: the page is pinned to the visible height and the
                // radar shrinks to whatever space the counts leave. The ScrollView stays only
                // for pull-to-refresh.
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 6) {
                            ARIARadarPanel()
                            if !app.aria.connection.state.isConnected {
                                Text("Join ARIA-Setup Wi-Fi to view live devices.")
                                    .font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary)
                            } else if let error = app.aria.lastError {
                                Text("Last snapshot · \(error)").font(FinchTheme.monoSmall).lineLimit(2)
                            }
                        }
                        .padding(.horizontal).padding(.bottom, 8)
                        .frame(height: proxy.size.height)
                    }
                    .refreshable { await app.aria.refresh() }
                }
            }
            .background(FinchTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder private func destination(_ band: String) -> some View {
        switch band {
        case "Wi-Fi": ARIAWiFiView()
        case "Sub-GHz": ARIASubGHzView()
        case "BLE": ARIABLEView()
        case "Frames": ARIAFramesView()
        default: ARIAUASView()
        }
    }
}

private struct RadarObservation: Identifiable {
    let id: String
    let icon: String
    let rssi: Int?
    var fraction: Double {
        guard let rssi else { return 0.9 }
        return min(0.9, max(0.08, pow(10, Double(-45 - rssi) / 25) / 100))
    }
    // Stable illustrative bearings: RSSI cannot determine direction.
    var bearing: Double { Double(id.utf8.reduce(0) { ($0 * 31 + Int($1)) % 360 }) * .pi / 180 }
}

struct ARIARadarPanel: View {
    private var location: LocationProvider { PhoneLocation.location }
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var observations: [RadarObservation] {
        guard app.aria.connection.state.isConnected else { return [] }
        let s = app.aria.session
        return s.wifi.map { RadarObservation(id: "wifi:" + $0.id, icon: wifiIcon($0), rssi: $0.rssi) }
            + s.ble.map { RadarObservation(id: "ble:" + $0.id, icon: "bolt.fill", rssi: $0.rssi) }
            + s.subghz.map { RadarObservation(id: "rf:" + $0.id, icon: "chart.bar.fill", rssi: $0.rssi) }
            + s.uas.map { RadarObservation(id: "uas:" + $0.id, icon: "airplane", rssi: nil) }
    }

    private func wifiIcon(_ device: ARIAWiFiDevice) -> String {
        let kind = device.decode?.bestFingerprint?.deviceClass?.lowercased() ?? ""
        if kind.contains("phone") { return "iphone" }
        if kind.contains("computer") || kind.contains("laptop") { return "laptopcomputer" }
        return "wifi"
    }

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion || scenePhase != .active)) { timeline in
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    ZStack {
                        ForEach(1..<5) { ring in
                            Circle().stroke(FinchTheme.cyan.opacity(0.22), lineWidth: 1)
                                .frame(width: side * CGFloat(ring) / 4, height: side * CGFloat(ring) / 4)
                                .position(center)
                        }
                        Path { p in
                            p.move(to: CGPoint(x: center.x, y: 0)); p.addLine(to: CGPoint(x: center.x, y: side))
                            p.move(to: CGPoint(x: center.x - side / 2, y: center.y)); p.addLine(to: CGPoint(x: center.x + side / 2, y: center.y))
                        }.stroke(FinchTheme.cyan.opacity(0.2))
                        if !reduceMotion {
                            Rectangle().fill(LinearGradient(colors: [.clear, FinchTheme.cyan], startPoint: .leading, endPoint: .trailing))
                                .frame(width: side / 2, height: 2).offset(x: side / 4)
                                .rotationEffect(.degrees(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) * 60))
                                .position(center).shadow(color: FinchTheme.cyan, radius: 7)
                        }
                        Text("N").position(x: center.x, y: 9)
                        Text("S").position(x: center.x, y: side - 9)
                        Text("W").position(x: center.x - side / 2 + 9, y: center.y)
                        Text("E").position(x: center.x + side / 2 - 9, y: center.y)
                        if let heading = location.headingDegrees {
                            Image(systemName: "location.north.fill")
                                .font(.title2).foregroundStyle(FinchTheme.secondaryAccent)
                                .rotationEffect(.degrees(heading)).position(center)
                                .accessibilityLabel("Phone pointing \(Int(heading)) degrees")
                        } else {
                            Image(systemName: "iphone").position(center)
                        }
                        ForEach(Array(observations.prefix(100))) { item in
                            Image(systemName: item.icon)
                                .foregroundStyle(item.icon == "bolt.fill" ? FinchTheme.secondaryAccent : FinchTheme.cyan)
                                .position(x: center.x + cos(item.bearing) * item.fraction * side / 2,
                                          y: center.y + sin(item.bearing) * item.fraction * side / 2)
                        }
                    }.font(FinchTheme.monoSmall)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(-1)   // takes only the height left after the counts
            HStack {
                PhoneHeadingReadout(location: location).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text("RSSI est. · ~100 m")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(FinchTheme.textSecondary)
                    .lineLimit(1).fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("ARIA HANDHELD").font(FinchTheme.monoTitle)
                    Spacer()
                    Text("LIVE NOW · TOTAL SEEN").font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(FinchTheme.textSecondary)
                }
                if let progress = app.aria.history.progressText {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(progress).font(FinchTheme.monoSmall)
                    }
                }
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let rows = app.aria.overview.rows(now: timeline.date, connected: app.aria.connection.state.isConnected)
                    ScrollView {
                        VStack(spacing: 4) {
                            // Radio totals must not depend on optional firmware fingerprints.
                            // Keep the original device rows visible even on older captures.
                            categoryCount(rows.first { $0.id == "computer" } ?? .init(id: "computer", records: [], live: 0))
                            categoryCount(rows.first { $0.id == "phone" } ?? .init(id: "phone", records: [], live: 0))
                            radioCount(.wifi, "Wi-Fi devices", "wifi")
                            radioCount(.ble, "BLE devices", "bolt.fill")
                            categoryCount(rows.first { $0.id == "subghz_decoded" } ?? .init(id: "subghz_decoded", records: [], live: 0))
                            radioCount(.uas, "UAS / Remote ID", "airplane")
                            ForEach(rows.filter { !["computer", "phone", "subghz_decoded"].contains($0.id) }) { row in
                                if row.priority {
                                    NavigationLink {
                                        ARIAWiFiDetail(overviewRecords: row.records, categoryTitle: row.title)
                                    } label: { categoryCount(row) }
                                    .buttonStyle(.plain)
                                } else {
                                    categoryCount(row)
                                }
                            }
                        }
                    }
                    .frame(height: 6 * 28)
                }
                if let error = app.aria.overviewError {
                    Text(error).font(.system(size: 9)).foregroundStyle(FinchTheme.textSecondary)
                }
                Text("Live: last 60 s · Total: all stored history · ARIA handheld radios only · Wi-Fi/BLE include all devices; device types require fingerprints; Sub-GHz includes decoded captures")
                    .font(.system(size: 9)).foregroundStyle(FinchTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(12).background(FinchCardBackground()).glowBorder(active: true, cornerRadius: 12)
        .onAppear { location.requestAndStart() }
    }

    private func radioCount(_ source: ARIALogSource, _ title: String, _ icon: String) -> some View {
        let history = app.aria.history
        let live = app.aria.connection.state.isConnected ? history.liveCount(source) : 0
        return HStack {
            Image(systemName: icon).foregroundStyle(FinchTheme.cyan).frame(width: 22)
            Text(title).font(.subheadline)
            Spacer()
            Text(String(live)).font(FinchTheme.monoSmall).frame(width: 48, alignment: .trailing)
            Text(history.totalText(source)).font(FinchTheme.monoSmall).frame(width: 64, alignment: .trailing)
        }
        .foregroundStyle(FinchTheme.textPrimary)
        .frame(height: 24)
        .accessibilityElement(children: .combine)
    }

    private func categoryCount(_ row: ARIAOverviewCatalog.Row) -> some View {
        let accent = row.priority ? FinchTheme.secondaryAccent : FinchTheme.cyan
        return HStack {
            Image(systemName: row.icon).foregroundStyle(accent).frame(width: 22)
            Text(row.title).font(.subheadline).foregroundStyle(row.priority ? accent : FinchTheme.textPrimary)
            Spacer()
            Text(String(row.live)).font(FinchTheme.monoSmall).frame(width: 48, alignment: .trailing)
            Text(String(row.total)).font(FinchTheme.monoSmall).frame(width: 64, alignment: .trailing)
        }
        .foregroundStyle(row.priority ? accent : FinchTheme.textPrimary)
        .frame(height: 24)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title), live now \(row.live), total seen \(row.total)")
    }
}

// MARK: - Mode → action list (second level, §1.5.2)

struct ARIAModeActionsView: View {
    @Environment(AppModel.self) private var app
    let mode: ARIAMode

    var body: some View {
        List {
            if mode.command == "uas" || mode.name.localizedCaseInsensitiveContains("UAS") {
                NavigationLink { ARIAUASView() } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remote ID list").font(FinchTheme.mono).foregroundStyle(FinchTheme.textPrimary)
                        Text("Validated Remote ID records, flight and operator fields")
                            .font(.caption2).foregroundStyle(FinchTheme.textSecondary)
                    }
                }
                .listRowBackground(FinchTheme.surface)
            }
            if mode.actions.isEmpty {
                Text("No actions reported for this mode.")
                    .font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary)
            }
            ForEach(mode.actions) { action in
                NavigationLink {
                    ARIAActionDestination(action: action)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(action.displayLabel).font(FinchTheme.mono)
                        if let detail = action.description {
                            Text(detail).font(.caption2).foregroundStyle(FinchTheme.textSecondary)
                        }
                    }
                }
                .listRowBackground(FinchTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(FinchTheme.background)
        .navigationTitle(mode.name)
    }
}
