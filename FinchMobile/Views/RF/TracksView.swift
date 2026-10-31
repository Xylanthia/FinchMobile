import SwiftUI
import UIKit

struct TracksView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            ZStack {
                FinchTheme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    statusBar
                    List {
                        ForEach(app.fusion.sortedTracks) { track in
                            NavigationLink {
                                TrackDetailView(trackID: track.id)
                            } label: {
                                TrackRow(track: track)
                            }
                            .listRowBackground(FinchTheme.background)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("TRACKS · RF FUSION")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fuse") { app.refreshFusion() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { app.fusion.clear() }
                }
            }
            .onAppear { app.refreshFusion() }
        }
    }

    private var statusBar: some View {
        HStack {
            Text(app.fusion.statusText)
                .font(FinchTheme.monoSmall)
                .foregroundStyle(FinchTheme.cyan)
            Spacer()
            Text(app.consent.statusSummary)
                .font(FinchTheme.monoSmall)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct TrackRow: View {
    let track: RFTrack

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.displayName)
                    .font(FinchTheme.mono)
                    .foregroundStyle(FinchTheme.textPrimary)
                Text("\(track.deviceClass.rawValue.uppercased()) · \(track.primarySource.rawValue)")
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(.secondary)
                if let d = track.estimatedDistanceM {
                    Text(String(format: "~%.1f m", d))
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(.secondary)
                } else if track.distanceUnreliable == true {
                    Text(String(format: "> %.0f m · estimate unreliable", TrackFusionEngine.maxReliableDistanceM))
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.warn)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(track.threatScore)/10")
                    .font(FinchTheme.mono)
                    .foregroundStyle(threatColor)
                Text(track.threatBand)
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(threatColor)
            }
        }
        .padding(.vertical, 4)
    }

    private var threatColor: Color {
        switch track.threatScore {
        case 8...10: return .red
        case 5...7: return .orange
        case 3...4: return .yellow
        default: return FinchTheme.cyan
        }
    }
}

struct TrackDetailView: View {
    @Environment(AppModel.self) private var app
    let trackID: UUID

    private var track: RFTrack? {
        app.fusion.tracks[trackID]
    }

    var body: some View {
        Group {
            if let track {
                trackList(track)
            } else {
                Text("Track cleared")
                    .font(FinchTheme.mono)
                    .foregroundStyle(FinchTheme.textSecondary)
            }
        }
        .background(FinchTheme.background)
        .navigationTitle(track?.displayName ?? "Track")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            if let ip = track?.linkedHostIP,
               app.glassPipeline.isRunning,
               app.glassPipeline.selectedHostIP == ip,
               !app.glassPipeline.progressText.isEmpty {
                Text(app.glassPipeline.progressText)
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.cyan)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(FinchTheme.surface.opacity(0.95))
            }
        }
    }

    @ViewBuilder
    private func trackList(_ track: RFTrack) -> some View {
        List {
            Section("Identity") {
                LabeledContent("Class", value: track.deviceClass.rawValue)
                LabeledContent("Threat", value: "\(track.threatScore) · \(track.threatBand)")
                LabeledContent("Anomaly", value: String(format: "%.2f", track.anomalyScore))
                if let ip = track.linkedHostIP {
                    LabeledContent("Host IP", value: ip)
                }
                if track.isSynthetic {
                    Text("SYNTHETIC / RESEARCH")
                        .foregroundStyle(.orange)
                        .font(FinchTheme.monoSmall)
                }
            }
            Section("Sources") {
                ForEach(track.sources) { s in
                    Text("\(s.kind.rawValue) · \(s.label) · \(String(format: "%.0f%%", s.confidence * 100))")
                        .font(FinchTheme.monoSmall)
                }
            }
            if !track.threatReasons.isEmpty {
                Section("Threat reasons") {
                    ForEach(track.threatReasons, id: \.self) { Text($0).font(FinchTheme.monoSmall) }
                }
            }
            if let meta = track.droneMeta {
                Section("Drone meta") {
                    LabeledContent("Vendor", value: meta.vendorGuess ?? "—")
                    LabeledContent("Link", value: meta.linkType ?? "—")
                    LabeledContent("MAVLink port", value: meta.mavlinkPortOpen ? "open" : "closed")
                    LabeledContent("Controller nearby", value: meta.controllerNearby ? "yes" : "no")
                }
            }
            if let ip = track.linkedHostIP {
                Section("Glass actions") {
                    Button("Deep Scan \(ip)") {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        app.glassPipeline.deepScan(ip: ip)
                        app.statusMessage = "Deep Scan → \(ip)"
                    }
                    .foregroundStyle(FinchTheme.cyan)
                    Button("IoT Vulns \(ip)") {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        app.glassPipeline.iotVulns(ip: ip)
                        app.statusMessage = "IoT Vulns → \(ip)"
                    }
                    .foregroundStyle(FinchTheme.cyan)
                    Text("Results land on Engage → host detail. Stay on Wi‑Fi with Local Network allowed.")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(FinchTheme.background)
    }
}
