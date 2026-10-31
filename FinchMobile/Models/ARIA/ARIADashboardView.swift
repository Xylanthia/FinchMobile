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
            NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Settings")
        }
        .padding(.horizontal).padding(.vertical, 8)
        .sheet(isPresented: $showJoin) {
            NavigationStack {
                VStack(spacing: 22) {
                    Image(systemName: "wifi").font(.largeTitle).foregroundStyle(FinchTheme.cyan)
                    Text("Join ARIA-Setup Wi-Fi").font(.title2.bold())
                    Text("In Settings → Wi-Fi, join ARIA-Setup. Allow Finch access under Privacy & Security → Local Network. Return here to reconnect automatically.")
                        .multilineTextAlignment(.center)
                    Button("Open Finch Settings") {
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
    private let bands = ["Overview", "Wi-Fi", "Sub-GHz", "BLE", "UAS", "RFID"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
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
                ScrollView {
                    VStack(spacing: 16) {
                        ARIARadarPanel()
                        if !app.aria.connection.state.isConnected {
                            Text("Join ARIA-Setup Wi-Fi to view live devices.")
                                .font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary)
                        } else if let error = app.aria.lastError {
                            Text("Last snapshot · \(error)").font(FinchTheme.monoSmall)
                        }
                    }.padding()
                }
                .refreshable { await app.aria.refresh() }
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
        case "UAS": ARIAUASView()
        default: ARIARFIDView()
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
    private var location: LocationProvider { BLESurveyFix.location }
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
        VStack(spacing: 16) {
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
            PhoneHeadingReadout(location: location)
            HStack {
                Text("RSSI estimate · illustrative bearings")
                Spacer()
                Text("~100 m")
            }.font(.system(size: 9, design: .monospaced)).foregroundStyle(FinchTheme.textSecondary)
            VStack(alignment: .leading, spacing: 10) {
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
                count("Computers", "laptopcomputer", live: classified(app.aria.session.wifi, "computer", "laptop"),
                      total: classified(app.aria.history.wifi, "computer", "laptop").map(String.init) ?? "—")
                count("Phones", "iphone", live: classified(app.aria.session.wifi, "phone"),
                      total: classified(app.aria.history.wifi, "phone").map(String.init) ?? "—")
                count(.wifi, "Wi-Fi devices", "wifi")
                count(.ble, "BLE devices", "bolt.fill")
                count(.subghz, "Sub-GHz captures", "chart.bar.fill")
                count(.uas, "UAS / Remote ID", "airplane")
                count(.rfid, "RFID tags", "wave.3.right")
                Text("Live now: heard in the last 60 s (Sub-GHz: still in handheld RAM). Total seen: everything in the stored history, including devices no longer in range. Counts the ARIA handheld's radios, not the phone's own BLE scanner.")
                    .font(.system(size: 9)).foregroundStyle(FinchTheme.textSecondary)
            }
        }.padding(16).background(FinchCardBackground()).glowBorder(active: true, cornerRadius: 12)
        .onAppear { location.requestAndStart() }
    }

    private func classified(_ devices: [ARIAWiFiDevice], _ kinds: String...) -> Int? {
        let classes = devices.compactMap { $0.decode?.bestFingerprint?.deviceClass?.lowercased() }
        guard !classes.isEmpty else { return nil }
        return classes.filter { value in kinds.contains { value.contains($0) } }.count
    }

    private func count(_ source: ARIALogSource, _ label: String, _ icon: String) -> some View {
        let history = app.aria.history
        return count(label, icon, live: source == .rfid ? nil : history.liveCount(source), total: history.totalText(source))
    }

    private func count(_ label: String, _ icon: String, live: Int?, total: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(FinchTheme.cyan).frame(width: 22)
            Text(app.aria.connection.state.isConnected ? live.map(String.init) ?? "—" : "—")
                .font(FinchTheme.monoTitle).frame(minWidth: 32, alignment: .trailing)
            Text(label).font(.subheadline)
            Spacer()
            Text(total).font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textPrimary)
        }
    }
}

// MARK: - Mode → action list (second level, §1.5.2)

struct ARIAModeActionsView: View {
    @Environment(AppModel.self) private var app
    let mode: ARIAMode

    @State private var pendingConfirm: ARIAAction?
    @State private var outcome: String?

    var body: some View {
        List {
            if mode.actions.isEmpty {
                Text("No actions reported for this mode.")
                    .font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary)
            }
            ForEach(mode.actions) { action in
                Button {
                    if action.requiresConfirmation == true {
                        pendingConfirm = action
                    } else {
                        fire(action)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        // Unmapped action → render raw name + description generically (§1.5.5).
                        Text(action.displayLabel).font(FinchTheme.mono).foregroundStyle(FinchTheme.textPrimary)
                        if let d = action.description, !d.isEmpty {
                            Text(d).font(.caption2).foregroundStyle(FinchTheme.textSecondary)
                        }
                        if let page = action.page {
                            Text(page).font(.caption2).foregroundStyle(FinchTheme.cyanDim)
                        }
                    }
                }
                .disabled(!app.aria.connection.state.isConnected)   // connection-gated (§1.6)
                .listRowBackground(FinchTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(FinchTheme.background)
        .navigationTitle(mode.name)
        .confirmationDialog(
            "Fire \(pendingConfirm?.displayLabel ?? "")?",
            isPresented: Binding(get: { pendingConfirm != nil }, set: { if !$0 { pendingConfirm = nil } }),
            titleVisibility: .visible
        ) {
            Button("Fire", role: .destructive) {
                if let a = pendingConfirm { fire(a) }
                pendingConfirm = nil
            }
            Button("Cancel", role: .cancel) { pendingConfirm = nil }
        }
        .overlay(alignment: .bottom) {
            if let outcome {
                Text(outcome)
                    .font(FinchTheme.monoSmall).padding(10)
                    .background(FinchCardBackground()).padding()
            }
        }
    }

    private func fire(_ action: ARIAAction) {
        Task {
            let result = await app.aria.fire(action)
            switch result {
            case .success: outcome = "\(action.displayLabel): OK"
            case .unknown(let m): outcome = "\(action.displayLabel): UNKNOWN — \(m)"
            case .failed(let m): outcome = "\(action.displayLabel): FAILED — \(m)"
            }
        }
    }
}
