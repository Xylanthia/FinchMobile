import SwiftUI
import Observation

@MainActor
@Observable
final class ARIADashboardViewModel {
    let coordinator: ARIACoordinator
    init(_ coordinator: ARIACoordinator) { self.coordinator = coordinator }

    var state: ARIAConnectionState { coordinator.connection.state }
    var summary: ARIASessionSummary? { coordinator.summary }
    var modes: [ARIAMode] { coordinator.modes }
    var lastPoll: Date? { coordinator.connection.lastSuccessfulPoll }
    var malformedSkipped: Int { coordinator.session.malformedSkipped }
}

struct ARIADashboardView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let vm = ARIADashboardViewModel(app.aria)
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ARIAConnectionBanner(state: vm.state, lastPoll: vm.lastPoll)

                    sessionSummary(vm)
                    healthStrip(vm)

                    // Band detail screens
                    VStack(spacing: 8) {
                        bandLink("Wi-Fi", "wifi", vm.summary?.wifiCount) { ARIAWiFiView() }
                        bandLink("Sub-GHz", "dot.radiowaves.right", vm.summary?.subghzCount) { ARIASubGHzView() }
                        bandLink("BLE", "antenna.radiowaves.left.and.right", vm.summary?.bleCount) { ARIABLEView() }
                        bandLink("UAS / Remote ID", "airplane", vm.summary?.uasCount) { ARIAUASView() }
                        bandLink("RFID", "wave.3.right", nil) { ARIARFIDView() }
                        bandLink("Session / Export", "square.and.arrow.up", nil) { ARIASessionExportView() }
                    }
                    .padding(.horizontal)

                    controlSurface(vm)
                }
                .padding(.vertical)
            }
            .scrollContentBackground(.hidden)
            .background(FinchTheme.background.ignoresSafeArea())
            .navigationTitle("ARIA")
            .refreshable { await app.aria.refresh() }
        }
        .onAppear { app.aria.start() }
    }

    // MARK: Session summary (§3.1)

    @ViewBuilder
    private func sessionSummary(_ vm: ARIADashboardViewModel) -> some View {
        if let s = vm.summary {
            VStack(alignment: .leading, spacing: 6) {
                Text("SESSION").font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.cyan)
                row("uptime", s.uptimeSeconds.map { "\($0)s" } ?? "—")
                row("Wi-Fi / BLE / Sub-GHz",
                    "\(s.wifiCount ?? 0) / \(s.bleCount ?? 0) / \(s.subghzCount ?? 0)")
                // UAS: "NO VALID UAS DETECTED" is a normal success state (§3.5).
                row("UAS", (s.uasCount ?? 0) == 0 ? "NO VALID UAS DETECTED" : "\(s.uasCount!) detected")
                row("RFID", s.rfidState ?? "idle")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FinchCardBackground())
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func healthStrip(_ vm: ARIADashboardViewModel) -> some View {
        if let s = vm.summary, s.heapFree != nil || s.queueDrops != nil {
            HStack {
                if let heap = s.heapFree { row("heap free", "\(heap)") }
                Spacer()
                if let drops = s.queueDrops {
                    row("queue drops", "\(drops)")
                }
            }
            .padding(10)
            .background(FinchCardBackground())
            .padding(.horizontal)
        }
    }

    // MARK: Registry-driven control surface (§1.5 / §1.6)

    @ViewBuilder
    private func controlSurface(_ vm: ARIADashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONTROL").font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.cyan)
                .padding(.horizontal)
            if vm.modes.isEmpty {
                Text(vm.state.isConnected
                     ? "Discovering device actions…"
                     : "Connect to ARIA-Setup to load controls.")
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.textSecondary)
                    .padding(.horizontal)
            } else {
                // Top-level mode list → each opens its real action set (two levels deep).
                ForEach(vm.modes) { mode in
                    NavigationLink {
                        ARIAModeActionsView(mode: mode)
                    } label: {
                        HStack {
                            Text(mode.name).font(FinchTheme.mono).foregroundStyle(FinchTheme.textPrimary)
                            Spacer()
                            Text("\(mode.actions.count)")
                                .font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary)
                            Image(systemName: "chevron.right").foregroundStyle(FinchTheme.cyanDim)
                        }
                        .padding()
                        .background(FinchCardBackground())
                    }
                    .disabled(!vm.state.isConnected)   // visibly present but dimmed when not connected
                    .opacity(vm.state.isConnected ? 1 : 0.4)
                    .padding(.horizontal)
                }
            }
        }
    }

    private func bandLink<Destination: View>(
        _ title: String, _ icon: String, _ count: Int?,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack {
                Image(systemName: icon).foregroundStyle(FinchTheme.cyan).frame(width: 24)
                Text(title).font(FinchTheme.mono).foregroundStyle(FinchTheme.textPrimary)
                Spacer()
                if let count { Text("\(count)").font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary) }
                Image(systemName: "chevron.right").foregroundStyle(FinchTheme.cyanDim)
            }
            .padding()
            .background(FinchCardBackground())
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(FinchTheme.textSecondary)
            Spacer()
            Text(value).font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textPrimary)
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
