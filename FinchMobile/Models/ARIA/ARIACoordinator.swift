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

    /// Durable record of everything the handheld reported (backfilled from /api/log, kept
    /// current by /api/stream). Lists, counts and the export read from here, not `session`.
    let history = ARIAHistory()
    private(set) var streamConnected = false
    private(set) var historyError: String?

    /// Snapshot cadence. With /api/stream up, deltas arrive as they happen and the snapshot
    /// only refreshes the full live rows; without it, this is the only update path.
    var pollInterval: TimeInterval { streamConnected ? 20 : 7 }

    private var geotagger = ARIAObservationGeotagger()
    private(set) var exportData = Data()

    private var pollTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    private var backfillTask: Task<Void, Never>?
    private var backfillAgain = false
    private var lastEventID: String?

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
        streamTask = Task { [weak self] in await self?.streamLoop() }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        streamTask?.cancel()
        streamTask = nil
        streamConnected = false
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
        ARIASelfDevice.update(host: client.baseURL.host, connected: connection.state.isConnected)
        guard connection.state.isConnected else { return }

        do {
            let snapshot = try await client.fetchSessionExport()
            let fix = ObservationLocation.capture()
            exportData = try geotagger.annotate(snapshot.raw, fix: fix)
            session = snapshot
            modes = snapshot.modes
            summary = snapshot.summary
            lastError = snapshot.warnings.isEmpty ? nil : snapshot.warnings.joined(separator: " · ")
            await history.ingestLive(snapshot)
        } catch {
            lastError = error.localizedDescription
        }
        // First connect (and any time history is not complete): pull the handheld's full log.
        if ARIALogSource.allCases.contains(where: { history.backfill[$0] != .complete }) {
            requestBackfill()
        }
    }

    // MARK: - History backfill (/api/log) and live stream (/api/stream)

    /// Coalesces requests: one backfill at a time, re-run once if asked again meanwhile.
    func requestBackfill() {
        guard backfillTask == nil else { backfillAgain = true; return }
        backfillTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.backfillAgain = false
                await self.backfill()
            } while self.backfillAgain && !Task.isCancelled
            self.backfillTask = nil
        }
    }

    private func backfill() async {
        while !history.loaded { try? await Task.sleep(nanoseconds: 100_000_000) }   // cursors first
        guard connection.state.isConnected else { return }
        do {
            let stats = try await client.logStats()
            history.setHandheldStats(stats)
            guard stats["ready"] as? Bool == true else {
                let reason = (stats["mount_error"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "starting"
                for source in ARIALogSource.allCases { history.setBackfill(source, .unavailable("handheld log not ready: \(reason)")) }
                return
            }
            let sources = stats["sources"] as? [String: Any] ?? [:]
            for source in ARIALogSource.allCases {
                guard let s = sources[source.rawValue] as? [String: Any] else {
                    history.setBackfill(source, .unavailable("handheld does not log \(source.label)"))
                    continue
                }
                try await page(source, stats: s)
            }
            historyError = nil
        } catch {
            historyError = "history: \(error.localizedDescription)"
            for source in ARIALogSource.allCases where history.backfill[source] != .complete {
                history.setBackfill(source, .unavailable(error.localizedDescription))
            }
        }
    }

    /// Pages one source from the stored cursor to the handheld's last_seq.
    private func page(_ source: ARIALogSource, stats: [String: Any]) async throws {
        let epoch = stats["epoch"] as? String ?? ""
        let total = ARIAHistoryCodec.int(stats["total_available"]) ?? 0
        let firstSeq = ARIAHistoryCodec.int(stats["first_seq"]) ?? 0
        let lastSeq = ARIAHistoryCodec.int(stats["last_seq"]) ?? 0
        func done() -> Int {
            guard let c = history.cursors[source], c.epoch == epoch, firstSeq > 0 else { return 0 }
            return min(total, max(0, c.lastSeq - firstSeq + 1))
        }
        func cursor() -> Int {
            guard let c = history.cursors[source], c.epoch == epoch, c.lastSeq <= lastSeq else { return 0 }
            return c.lastSeq
        }
        while cursor() < lastSeq {
            history.setBackfill(source, .loading(loaded: done(), total: total))
            let since = cursor()
            let page = try await client.logPage(source, sinceSeq: since, limit: source.pageLimit)
            guard page["epoch"] as? String == epoch else { backfillAgain = true; return }   // cleared mid-page
            let records = page["records"] as? [[String: Any]] ?? []
            await history.ingestLog(source, epoch: epoch, records: records, requireContiguous: false)
            let next = ARIAHistoryCodec.int(page["next_seq"]) ?? since
            // No progress (only corrupt lines left) or nothing more: stop rather than spin.
            if next <= since || page["has_more"] as? Bool != true { break }
        }
        history.setBackfill(source, .complete)
    }

    private func streamLoop() async {
        while !Task.isCancelled {
            if connection.state.isConnected {
                do {
                    for try await event in client.events(lastEventID: lastEventID) {
                        streamConnected = true
                        if let id = event.id { lastEventID = id }
                        await handle(event)
                    }
                } catch {
                    // dropped: fall through, reconnect, and let hello trigger a re-page
                }
                streamConnected = false
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    private func handle(_ event: ARIAClient.StreamEvent) async {
        guard let data = event.data.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        switch event.event {
        case "hello":
            // Cursors cover any gap (reboot, epoch change, missed events): re-page from them.
            if let stats = object["stats"] as? [String: Any] { history.setHandheldStats(stats) }
            requestBackfill()
        case "resync":
            history.setHandheldStats(object)
            requestBackfill()
        case "live", "snapshot":
            history.applyLiveUpdates(object)
        case "record":
            guard let name = object["source"] as? String, let source = ARIALogSource(rawValue: name),
                  let captureID = object["capture_id"] as? String else { return }
            // capture_id = "<source>-<epoch>-<seq>"
            let parts = captureID.split(separator: "-")
            guard parts.count >= 3 else { return }
            let epoch = String(parts[parts.count - 2])
            let contiguous = await history.ingestLog(source, epoch: epoch, records: [object], requireContiguous: true)
            if !contiguous { requestBackfill() }
        default:
            break   // ping
        }
    }

    // MARK: - Export (full persistent store, streamed to disk)

    /// Writes the whole history (every device/capture ever seen, in range or not) to a file.
    func exportHistory() async throws -> (URL, [ARIALogSource: Int]) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aria-history-\(stamp).json")
        let counts = try await history.writeExport(to: url, liveSnapshot: exportData)
        return (url, counts)
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
