import SwiftUI

struct DronePanelView: View {
    @Environment(AppModel.self) private var app
    @State private var flash: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                FinchTheme.background.ignoresSafeArea()
                List {
                    Section("Status") {
                        Text(app.drone.statusText)
                            .font(FinchTheme.monoSmall)
                            .foregroundStyle(FinchTheme.cyan)
                        Text(app.consent.statusSummary)
                            .font(FinchTheme.monoSmall)
                        if let last = app.drone.lastActiveResult {
                            Text(last)
                                .font(FinchTheme.monoSmall)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Detections (passive)") {
                        if app.drone.detections.isEmpty {
                            Text("No drone-class tracks yet. Scan BLE / Glass, or inject in Research Mode.")
                                .font(FinchTheme.monoSmall)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(app.drone.detections) { track in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(track.displayName)
                                        .font(FinchTheme.mono)
                                    Spacer()
                                    Text("\(track.threatScore)/10")
                                        .font(FinchTheme.mono)
                                        .foregroundStyle(FinchTheme.cyan)
                                }
                                Text(track.droneMeta?.linkType ?? track.deviceClass.rawValue)
                                    .font(FinchTheme.monoSmall)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Button("Observe") {
                                        app.drone.observeMAVLink(trackId: track.id)
                                        flash = app.drone.lastActiveResult ?? ""
                                    }
                                    .buttonStyle(.bordered)
                                    Menu("Active…") {
                                        ForEach(ActiveOpKind.allCases.filter { $0 != .armSystem }) { kind in
                                            Button(kind.title) {
                                                flash = app.drone.requestActive(kind: kind, track: track)
                                            }
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(FinchTheme.cyan)
                                }
                            }
                            .listRowBackground(FinchTheme.background)
                        }
                    }

                    Section("Hard ceiling") {
                        Text("Passive detect / classify / forensic log: YES on stock iPhone.\nMITM · inject · fuzz · GPS spoof · RF deny · MAVLink Tx: require authorized external SDR/C2 kit. Finch arms, consents, and audits — it does not transmit RF.")
                            .font(FinchTheme.monoSmall)
                            .foregroundStyle(.secondary)
                    }

                    if !flash.isEmpty {
                        Section("Last result") {
                            Text(flash).font(FinchTheme.monoSmall)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("DRONE MODULE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
                        app.refreshFusion()
                        app.drone.refresh(from: app.fusion.sortedTracks)
                    }
                }
            }
            .onAppear {
                app.refreshFusion()
                app.drone.refresh(from: app.fusion.sortedTracks)
            }
        }
    }
}
