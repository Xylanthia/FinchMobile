import Foundation
import Observation

/// MVVM-C coordinator for the ARIA module, sitting alongside the existing coordinators.
/// Owns the client, connection manager, discovered action registry, and the latest session
/// snapshot. All band ViewModels read from here so every screen shares one source of truth
/// and one last-successful-poll timestamp (spec §2, §1.5, §1.6).
@MainActor
@Observable
final class ARIACoordinator {
    let client: ARIAClient
    let connection: ARIAConnectionManager

    private(set) var modes: [ARIAMode] = []
    private(set) var session: ARIASessionExport = .empty
    private(set) var summary: ARIASessionSummary?

    private(set) var lastError: String?
    private(set) var isPolling: Bool = false

    /// Conservative client-side poll cadence until a firmware delta endpoint exists (§1).
    var pollInterval: TimeInterval = 7

    private var geotagger = ARIAObservationGeotagger()
    private(set) var exportData = Data()

    private var pollTask: Task<Void, Never>?

    init(client: ARIAClient = ARIAClient(),
         connection: ARIAConnectionManager = ARIAConnectionManager()) {
        self.client = client
        self.connection = connection
    }

    func start() {
        connection.start()
        BLESurveyFix.startIfNeeded()
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in await self?.pollLoop() }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        connection.stop()
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    /// One reconcile cycle: re-check reachability, then (if connected) pull fresh state.
    /// Never shows stale data as live — on a non-connected state we keep the banner honest
    /// and leave the last snapshot tagged with its real timestamp.
    func refresh() async {
        guard !isPolling else { return }
        connection.start()
        isPolling = true
        defer { isPolling = false }

        await connection.evaluate(using: client)
        guard connection.state.isConnected else { return }

        // Discover the full action set once we're connected (§1.5).
        if modes.isEmpty {
            do { modes = try await client.fetchActionRegistry() }
            catch { lastError = "registry: \(error)" }
        }

        do {
            let snapshot = try await client.fetchSessionExport()
            let fix = ObservationLocation.capture()
            exportData = try geotagger.annotate(snapshot.raw, fix: fix)
            session = snapshot
            lastError = nil
        } catch {
            lastError = "session: \(error)"
        }

        summary = try? await client.fetchSummary()
    }

    // MARK: - Control firing (§1.5 / §1.6)

    enum FireOutcome: Equatable {
        case success
        case unknown(String)     // AP dropped mid-flight: outcome genuinely unknown
        case failed(String)
    }

    func fire(_ action: ARIAAction) async -> FireOutcome {
        guard connection.state.isConnected else {
            return .failed("not connected to ARIA-Setup")
        }
        do {
            _ = try await client.fire(action)
            // Reconcile from the device rather than assuming our command is current truth.
            await refresh()
            return .success
        } catch let f as ARIAClient.Failure where f.statusCode == nil {
            return .unknown(f.message)   // transport-level: could have fired, result unknown
        } catch {
            return .failed("\(error)")
        }
    }

    func replaySubGHz(_ capture: ARIASubGHzCapture) async -> FireOutcome {
        guard connection.state.isConnected else {
            return .failed("not connected to ARIA-Setup")
        }
        do {
            _ = try await client.replaySubGHz(capture)
            return .success
        } catch let f as ARIAClient.Failure where f.statusCode == nil {
            return .unknown(f.message)
        } catch {
            return .failed("\(error)")
        }
    }
}
